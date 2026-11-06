# Specification: Lock-Free Stateless Cursors & Virtual Memory Core

## 1. Overview & Motivation
In an append-only immutable database, a snapshot (`Moment_ID` / root slot) and a cursor (`Slot` offset or B+Tree key) are pure values. Any thread or actor should be able to take `{moment_id, slot}`, read or resume iteration from where it left off, and execute in parallel with zero locks.

Previously, `xitdb` had two stateful storage-layer bottlenecks that prevented concurrent readers from sharing a `Database` instance safely:

1. **Two-Step Stateful `core_seek_to(offset)` + `core_read_exact(buf)`:**
   Read paths across `cursor.odin`, `database.odin`, `hamt.odin`, `btree.odin`, and `compact_replicate.odin` mutated shared `db.core.pos` (or the OS file descriptor's seek offset) before reading. Concurrent readers interleaved `core_seek_to` and `core_read_exact`, causing threads to read from each other's offsets.
2. **Heap Reallocation of `Core_Memory.buf: [dynamic]u8` During Appends:**
   When a writer appended a new Moment and `m.buf` exceeded its capacity, `resize(&m.buf, end_pos)` allocated a new backing array, copied bytes, and freed the old backing array while concurrent readers were slicing `m.buf[offset : offset + n]`.

This track eliminates both bottlenecks by introducing:
1. **Stateless Positional Reads (`core_read_at` / `core_read_exact_at` and typed `*_at` helpers)** across `Core_Memory`, `Core_File` (`os.read_at` / `pread`), and `Core_Buffered_File`.
2. **Fixed Virtual Address Space Reservation (`vmem.reserve` / `vmem.commit`) for `Core_Memory`**, guaranteeing that `raw_data(m.buf)` never moves for the lifetime of the database while committing physical pages on demand as length grows.

---

## 2. Functional Requirements

### 2.1 Stateless Positional Read Primitives (`xitdb/core.odin` & `xitdb/types.odin`)
- Provide stateless positional read procedures that never read or mutate `Core_Memory.pos`, `Core_Buffered_File.pos`, or the OS file descriptor seek offset:
  - `core_read_at(c: ^Core, pos: i64, p: []u8) -> (read_n: int, err: Error)`
  - `core_read_exact_at(c: ^Core, pos: i64, p: []u8) -> Error`
  - `core_read_byte_at(c: ^Core, pos: i64) -> (v: u8, err: Error)`
  - `core_read_u16_at(c: ^Core, pos: i64) -> (v: u16, err: Error)`
  - `core_read_u32_at(c: ^Core, pos: i64) -> (v: u32, err: Error)`
  - `core_read_i64_at(c: ^Core, pos: i64) -> (res: i64, err: Error)`
  - `core_read_long_at(c: ^Core, pos: i64) -> (res: i64, err: Error)`
  - `core_read_slot_raw_at(c: ^Core, pos: i64) -> (s: Slot, err: Error)`
  - `core_read_slot_at(c: ^Core, pos: i64) -> (s: Slot, err: Error)`
  - `header_read_at(r: ^Core, pos: i64 = 0) -> (h: Header, err: Error)`
  - `decode_kv_pair_at(c: ^Core, pos: i64, tag: Tag, hash_size: int, allocator := context.allocator) -> (kv: Key_Value_Pair, err: Error)`
  - `kv_pair_read_buf_at(c: ^Core, pos: i64, hash_buf: []u8) -> (kv: Key_Value_Pair, err: Error)`
- Backend behavior for `core_read_at` / `core_read_exact_at`:
  - **`Core_Memory`:** Bounds-check `pos >= 0` and `pos + len(p) <= len(v.buf)`, then copy directly via `copy(p, v.buf[pos : pos + i64(len(p))])` without touching `v.pos`.
  - **`Core_File`:** Loop over `os.read_at(v.file, p[total:], pos + i64(total))` (`pread` on Linux/POSIX) until `len(p)` bytes are read or EOF/error occurs, without modifying the file descriptor's seek position.
  - **`Core_Buffered_File`:** Read committed disk regions via stateless `os.read_at(v.file.file, ...)` and any overlapping unflushed tail region `[v.memory_pos, v.memory_pos + len(v.memory.buf))` directly from `v.memory.buf`, without mutating `v.pos` or calling `os.seek`.

### 2.2 Virtual Address Space Reservation for `Core_Memory` (`xitdb/core.odin`)
- Back default `Core_Memory` instances (`core_memory_init`, `core_memory_init_from_bytes`) with a contiguous virtual address space reservation via `core:mem/virtual` (`vmem.reserve`):
  - Default reservation size: `DEFAULT_VMEM_RESERVE_SIZE :: 1 << 30` (1 GiB on 64-bit platforms; `128 << 20` on 32-bit).
  - Commit physical pages on demand via `vmem.commit` in page-aligned increments as `_memory_resize` grows `len(m.buf)` beyond `cap(m.buf)`.
  - Maintain `m.buf` (`runtime.Raw_Dynamic_Array`) so `raw_data(m.buf)` points to the fixed `vmem` base address, `len(m.buf)` reflects the active byte length, and `cap(m.buf)` reflects the currently committed byte capacity.
  - Ensure `raw_data(m.buf)` never moves across growth up to `vmem_reserved`, allowing a writer thread to append at the tail while concurrent reader threads slice `m.buf[0 .. header.file_size)` lock-free.
  - Release the virtual reservation via `vmem.release` in `core_destroy`.
  - Preserve fallback support when `vmem_reserved == 0` (e.g., when callers explicitly construct `Core_Memory{buf = make([dynamic]u8, ..., tiny_arena_alloc), allocator = tiny_arena_alloc}` in bounded-arena OOM tests or `Core_Buffered_File`'s small internal buffer).

### 2.3 Stateless Read Paths Across `xitdb`
- Replace all two-step `core_seek_to` + `core_read_*` sequences on read paths with `core_read_*_at` in:
  - `xitdb/cursor.odin` (`Read_Cursor`, `Cursor_Reader`, `Cursor_Iterator` for HAMT, Radix Trie, B-Tree, and B+Tree)
  - `xitdb/database.odin` (`database_read_and_validate_header`, `database_read_root_header`, `database_read_root_trailer`, `database_copy_index_block_if_old`, and read operations in `read_slot_pointer` / `_exec_path_part`)
  - `xitdb/hamt.odin` (`read_map_slot`, `remove_map_slot`, `read_array_list_slot`, `read_array_list_slice`)
  - `xitdb/btree.odin` (`read_btree_node`, `read_btree_slot`, `btree_insert`, `btree_get_for_write`, `btree_remove`, `btree_height`, `read_sorted_node`, `read_kv_pair`, `sorted_entry_key_slot`, `compare_key`, `sorted_get`, `sorted_get_by_index`, `sorted_rank`, `sorted_put`, `sorted_remove`)
  - `xitdb/compact_replicate.odin` (`_compactor_reserve_block`, `database_compact`, `_compactor_remap_bytes`, `_compactor_populate_*`, `_stream_bytes`, `database_read_committed_buf`, `database_read_committed_bytes`)

---

## 3. Non-Functional Requirements & Invariants
- **100% Wire Compatibility:** Zero changes to wire format constants, slot layout, or on-disk headers/trailers.
- **Zero Memory Leaks:** All `vmem` reservations and heap allocations must be cleanly released on `core_destroy`, passing `odin test tests` with Odin's `Tracking_Allocator`.
- **3-Layer ATDD Coverage:** All new concurrency, cursor resumption, and virtual memory stability guarantees must be verified via 3-layer ATDD executable specifications (`tests/spec_xitdb.odin`, `tests/dsl_xitdb.odin`, `tests/driver_xitdb.odin`).
