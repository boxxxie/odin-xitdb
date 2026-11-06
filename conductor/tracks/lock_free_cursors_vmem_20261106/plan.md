# Implementation Plan: Lock-Free Stateless Cursors & Virtual Memory Core

## Phase 1: Stateless Positional I/O & Virtual Memory Backing (`xitdb/core.odin`, `xitdb/types.odin`)
- [x] Task 1.1: Implement `vmem.reserve` / `vmem.commit` / `vmem.release` backing for `Core_Memory` in `xitdb/core.odin`, keeping `raw_data(m.buf)` fixed across growth while preserving custom allocator fallback when `vmem_reserved == 0`.
- [x] Task 1.2: Implement stateless positional `core_read_at`, `core_read_exact_at`, `core_read_byte_at`, `core_read_u16_at`, `core_read_u32_at`, `core_read_i64_at`, `core_read_long_at`, `core_read_slot_raw_at`, and `core_read_slot_at` in `xitdb/core.odin` for `Core_Memory`, `Core_File` (`os.read_at`), and `Core_Buffered_File`.
- [x] Task 1.3: Implement `header_read_at`, `decode_kv_pair_at`, and `kv_pair_read_buf_at` in `xitdb/types.odin`.

## Phase 2: Migrate Read & Traversal Paths to Stateless Positional Reads
- [x] Task 2.1: Migrate `Read_Cursor`, `Cursor_Reader`, and `Cursor_Iterator` in `xitdb/cursor.odin` from `core_seek_to` + `core_read_*` to `core_read_*_at`.
- [x] Task 2.2: Migrate header validation, root header/trailer reading, index block copy, and path traversal read steps in `xitdb/database.odin` to `core_read_*_at`.
- [x] Task 2.3: Migrate HAMT and Radix Trie read/traversal helpers in `xitdb/hamt.odin` to `core_read_*_at`.
- [x] Task 2.4: Migrate Counted B-Tree and B+Tree `Sorted_Map` read/traversal helpers in `xitdb/btree.odin` and `xitdb/collections.odin` to `core_read_*_at`.
- [x] Task 2.5: Migrate compactor and replication read helpers and `Core_Memory` resize calls in `xitdb/compact_replicate.odin` to `_memory_resize` and `core_read_*_at`.

## Phase 3: 3-Layer ATDD Executable Specifications & Documentation (`tests/`, `docs/`)
- [x] Task 3.1: Add ATDD specifications (`tests/spec_xitdb.odin`), DSL steps (`tests/dsl_xitdb.odin`), and protocol drivers (`tests/driver_xitdb.odin`) for multi-threaded lock-free concurrent cursors, iterators, `Cursor_Reader` streams, and cross-thread `{moment_id, slot}` / B+Tree key resumption across `Core_Memory`, `Core_File`, and `Core_Buffered_File` (Scenario 37).
- [x] Task 3.2: Add ATDD specifications, DSL steps, and protocol drivers for `Core_Memory` virtual memory (`vmem.reserve`) base-pointer stability (`raw_data(m.buf)`), reservation cap enforcement, and `core_set_length` shrink/re-grow while a writer thread appends Moments concurrently with reader threads (Scenarios 38 & 41).
- [x] Task 3.3: Add ATDD specifications for concurrent compaction/replication (`database_compact`, `database_read_committed_bytes`, `database_apply_replicated`) and concurrent 5-layer DSL/Datalog queries (`select_cursor`, `diff_moments`, `history_of`, `query_datalog`) alongside parallel readers (Scenarios 39 & 40).
- [x] Task 3.4: Update `AGENTS.md`, `usage-rules.md`, `README.md`, `docs/CORE_API.md`, and `tests/README.md`, and verify 100% pass rate with zero memory leaks under `odin test tests`.
