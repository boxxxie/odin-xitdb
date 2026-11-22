# xitdb Core & Collections API Reference

This guide documents the low-level Odin core storage backends, wire format primitives, cursors, persistent collections, streaming I/O, compaction, and replication in [`xitdb/`](../xitdb).

> For the 5-layer query/transaction/Datalog DSL, see [`DSL.md`](DSL.md). For embedded LuaJIT 2.1 bindings, see [`LUAJIT.md`](LUAJIT.md).

---

## 1. Storage Cores & Hashers (`xitdb/core.odin`, `xitdb/types.odin`)

### Storage Cores

`xitdb` abstracts storage through the `Core` union (`Core_Memory | Core_File | Core_Buffered_File`). All read paths across `xitdb` use **stateless positional reads** (`core_read_at`, `core_read_exact_at`, `core_read_slot_at`, etc.) that never mutate `core.pos` or the OS file descriptor's seek offset:

* **`core_memory_init(allocator := context.allocator, reserve_size: int = DEFAULT_VMEM_RESERVE_SIZE) -> Core`**
  In-memory byte buffer backed by a fixed virtual address reservation (`1 GiB` on 64-bit via `core:mem/virtual`, committing physical pages on demand). Because `raw_data(buf)` never moves across appends, multiple reader threads can concurrently read committed snapshots while a writer appends new moments at the tail. Pass `reserve_size = 0` to fall back to a standard heap/arena `[dynamic]u8`.
* **`core_memory_init_from_bytes(data: []u8, allocator := context.allocator, reserve_size: int = DEFAULT_VMEM_RESERVE_SIZE) -> Core`**
  Initializes a `vmem`-backed `Core_Memory` populated with a copy of `data`.
* **`core_file_open(path: string, flags := os.File_Flags{.Read, .Write, .Create}, fsync := true) -> (Core, Error)`**
  Unbuffered OS file I/O using `os.read_at` (`pread` on Linux) for lock-free concurrent reads on a shared `^Database`. When a thread or process only reads, open its file in read-only mode (`flags = {.Read}`) so `database_init` cannot write to an empty file or one whose creation or `database_apply_replicated` replacement is still in progress.
* **`core_buffered_file_open(path: string, buffer_size: i64 = DEFAULT_BUFFER_SIZE, flags := os.File_Flags{.Read, .Write, .Create}, fsync := true, allocator := context.allocator) -> (Core, Error)`**
  Pairs an OS file handle with an in-memory tail write buffer (`2 MiB` default). Flushes on root commit (`database_commit_root`) so all committed moments are served via stateless `os.read_at`.
* **`core_destroy(c: ^Core, close_file := false) -> Error`**
  Releases virtual or heap memory buffers (`vmem.release` / `delete`) and optionally closes the underlying file handle.

### Hashers & `hash_id` Validation

HAMT collections (`Hash_Map`, `Counted_Hash_Map`, `Hash_Set`, `Counted_Hash_Set`) hash keys using the `Database`'s configured `Hasher`:

* **`sha1_hasher(id: u32 = 0, file_id: u64 = 0) -> Hasher`**
  20-byte SHA-1 digest (automatically hardware-accelerated via x86 SHA-NI when supported by the CPU).
* **`sha256_hasher(id: u32 = 0, file_id: u64 = 0) -> Hasher`**
  32-byte SHA-256 digest (hardware-accelerated via x86 SHA-NI when supported).
* **Custom `Hasher`** (using `string_to_id` / `bytes_to_id` / `id_to_bytes` for 4-byte ASCII identifiers):
  ```odin
  custom := xitdb.Hasher{
      hash_proc = my_blake3_proc,
      hash_size = 32,
      id        = xitdb.string_to_id("blk3"),
      file_id   = 0, // random u64 assigned when a new database is initialized
  }
  ```
* **Header `hash_id` Validation (`header_validate_hasher`)**:
  On `database_init` (when reopening an existing store) and full replication (`start == 0`), `header_validate_hasher(header, hasher)` enforces `header.hash_size == hasher.hash_size` (unless `hasher.hash_size == 0`) and rejects mismatched non-zero algorithm IDs (`hasher.id != 0 && header.hash_id != 0 && header.hash_id != hasher.id`) with `.Invalid_Hash_Id`. Untagged headers (`header.hash_id == 0`, the default for `sha1_hasher()`, `cmd/xit`, and upstream Zig `xitdb`) and wildcard hashers (`hasher.id == 0`) remain mutually compatible when `hash_size` matches.

---

## 2. Wire Format & Slot Primitives (`xitdb/types.odin`)

Every reference in `xitdb` is a 9-byte `Slot` (`SLOT_LENGTH :: 9`):
* **Byte 0 (`tag_and_full`)**: Lower 7 bits store the `Tag` (`0..16`); bit 7 (`0x80`) stores the `full` flag.
* **Bytes 1..8 (`value: i64`, big-endian)**:
  * For `.Uint`, `.Int`, and `.Float`: stores the 64-bit scalar inline.
  * For `.Short_Bytes`: stores up to 8 bytes of non-null payload inline (or up to 6 bytes + 2-byte `format_tag` when `full == true`).
  * For `.Bytes` and all collection tags: stores the byte offset in the database file.

### Crash-Safe Root Header & Trailer

A database file begins with:
1. **`Header` (20 bytes)**: Magic (`"xit"`), `padding` (`u8`), `version` (`u16`, `2` for new databases; `1` also supported), `hash_size` (`u16`), `hash_id` (`u32`), and `file_id` (`u64`).
2. **`Root_Header` (12 bytes in v2, 17 bytes in v1)**: 4 zero padding bytes at offset `20..24` followed by the 8-byte aligned committed `file_size` (`i64`) at `FILE_SIZE_START` (`24..32`), with the root `Slot` resolved from the verified `Root_Trailer` at `file_size`.
3. **`Root_Trailer` (25 bytes, appended at the end of every root transaction)**: `commit_id` (`u64`), `root_slot` (`Slot`), and `checksum` (`u64` CRC-64/XZ over `file_id || trailer_offset || commit_id || root_slot_bytes`).

If a crash occurs mid-transaction before `Root_Header` is updated, reopening the database verifies the trailer at the committed `file_size` and automatically truncates any uncommitted trailing bytes on the next write.

---

## 3. Database Lifecycle & Cursors (`xitdb/database.odin`, `xitdb/cursor.odin`)

```odin
db, err := xitdb.database_init(&core, xitdb.sha1_hasher())
root_wc := xitdb.database_root_cursor(&db)
```

* **`database_run_context(db: ^Database, cb: Context_Callback, user_data: rawptr = nil) -> Error`**
  Executes `cb` inside a root transaction and appends a verified `Root_Trailer` on success, or rolls back uncommitted writes on error.
* **`database_freeze(db: ^Database) -> Error`**
  Advances `db.tx_start` mid-transaction so all nodes written so far become immutable within the current transaction (surviving even if a subsequent operation aborts).
* **`cursor_freeze(c: ^Write_Cursor) -> Error`**
  Sets `c.read_cursor.slot_ptr.slot.full = true` so subsequent mutations to a cloned collection allocate copy-on-write nodes rather than mutating the source in place.

### Reading & Writing Values at Cursors

* **Scalar & Byte Reads**:
  * `cursor_read_uint(c: Read_Cursor) -> (u64, Error)`
  * `cursor_read_int(c: Read_Cursor) -> (i64, Error)`
  * `cursor_read_float(c: Read_Cursor) -> (f64, Error)`
  * `cursor_read_bytes_buf(c: Read_Cursor, buf: []u8) -> (Bytes, Error)` *(zero heap allocations)*
  * `cursor_read_string(c: Read_Cursor, max_size: i64 = -1, allocator := context.allocator) -> (string, Error)`
  * `cursor_read_bytes_object(c: Read_Cursor, max_size: i64 = -1, allocator := context.allocator) -> (Bytes, Error)`
  * `cursor_read_kv_pair_slots(c: Read_Cursor) -> (KV_Pair_Cursor, Error)` *(zero heap allocations)*
  * `database_kv_key_position(db: ^Database, entry: Slot) -> (Maybe(i64), Error)` / `database_kv_value_position(db: ^Database, entry: Slot) -> (Maybe(i64), Error)` *(slot-only KV offset reads without decoding full payloads)*
* **Scalar & Byte Writes**:
  * `cursor_write(c: ^Write_Cursor, data: Writeable_Data) -> Error`
  * `cursor_write_if_empty(c: ^Write_Cursor, data: Writeable_Data) -> Error`

### In-Place `Cursor_Iterator` Initialization (`*_init`)

For recursive traversals on small thread stacks (e.g., `512 KiB`) or pooled/reused `Cursor_Iterator` instances, initialize an existing `^Cursor_Iterator` in place instead of returning a `Cursor_Iterator` by value. All 10 procedures below are `@(require_results)`, reset the iterator up front, zero the target on error (preventing stale state on reuse), and pair with `cursor_iterator_next` or `cursor_iterator_prev`:

* **Full Collection (Forward & Reverse)**:
  * `cursor_iterator_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor) -> Error`
  * `cursor_iterator_reverse_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor) -> Error`
* **`Sorted_Map` / `Sorted_Set` Range Seeks**:
  * `cursor_iterator_sorted_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`
  * `cursor_iterator_sorted_from_key_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_key: []u8) -> Error`
  * `cursor_iterator_sorted_reverse_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`
  * `cursor_iterator_sorted_reverse_from_key_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, upper_key: []u8, inclusive: bool = true) -> Error`
* **`Array_List` & `Linked_Array_List` Index Seeks**:
  * `cursor_iterator_array_list_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`
  * `cursor_iterator_array_list_reverse_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`
  * `cursor_iterator_linked_array_list_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`
  * `cursor_iterator_linked_array_list_reverse_from_index_init(res: ^Cursor_Iterator, unresolved_cursor: Read_Cursor, start_index: i64) -> Error`

---

## 4. Persistent Collections (`xitdb/collections.odin`)

### `Array_List` (16-way Radix Trie)
* `read_array_list_init(c: Read_Cursor)` / `write_array_list_init(c: Write_Cursor)`
* `array_list_count(l)` $\rightarrow O(1)$
* `array_list_get_cursor(l, index)` / `array_list_get_slot(l, index)` $\rightarrow O(\log_{16} N)$ (supports negative indices `-1`)
* `array_list_append(l, data)` / `array_list_append_cursor(l)` / `array_list_append_context(l, prev_slot, cb)`
* `array_list_put(l, index, data)` / `array_list_put_cursor(l, index)`
* `array_list_slice(l, size)` $\rightarrow$ truncates tail and collapses unused trie depth
* `array_list_iterator(l)` / `array_list_iterator_from(l, start_index)`
* `array_list_iterator_reverse(l)` / `array_list_iterator_reverse_from(l, start_index)` (step backward with `cursor_iterator_prev`)

### `Linked_Array_List` (Count-Augmented B-Tree)
* `read_linked_array_list_init(c: Read_Cursor)` / `write_linked_array_list_init(c: Write_Cursor)`
* `linked_array_list_count(l)` $\rightarrow O(1)$
* `linked_array_list_get_cursor(l, index)` / `linked_array_list_get_slot(l, index)` $\rightarrow O(\log_{16} N)$
* `linked_array_list_append(l, data)` / `linked_array_list_put(l, index, data)`
* `linked_array_list_insert(l, index, data)` / `linked_array_list_insert_cursor(l, index)` $\rightarrow O(\log_{16} N)$ mid-list insertion
* `linked_array_list_remove(l, index)` $\rightarrow O(\log_{16} N)$ mid-list removal
* `linked_array_list_slice(l, offset, size)` / `linked_array_list_concat(l, list_b_slot)` $\rightarrow O(\log_{16} N)$ rope split & join
* `linked_array_list_iterator(l)` / `linked_array_list_iterator_from(l, start_index)`
* `linked_array_list_iterator_reverse(l)` / `linked_array_list_iterator_reverse_from(l, start_index)` (step backward with `cursor_iterator_prev`)

### `Hash_Map` & `Counted_Hash_Map` (16-way HAMT)
* `read_hash_map_init` / `write_hash_map_init` / `read_counted_hash_map_init` / `write_counted_hash_map_init`
* `counted_hash_map_count(m)` $\rightarrow O(1)$
* `hash_map_get_cursor(m, key)` / `hash_map_get_cursor_by_hash(m, hash)`
* `hash_map_put(m, key, data)` / `hash_map_put_cursor(m, key)` / `hash_map_put_key_and_value(m, hash, key, val)`
* `hash_map_remove(m, key)` / `hash_map_remove_by_hash(m, hash)` $\rightarrow$ automatically collapses singleton branches
* `hash_map_iterator(m)` / `hash_map_iterator_reverse(m)`

### `Sorted_Map` & `Sorted_Set` (Count-Augmented B+Tree)
* `read_sorted_map_init` / `write_sorted_map_init` / `read_sorted_set_init` / `write_sorted_set_init`
* `sorted_map_count(m)` $\rightarrow O(1)$
* `sorted_map_get_cursor(m, key)` / `sorted_map_put(m, key, data)` / `sorted_map_remove(m, key)`
* `sorted_map_rank(m, key)` $\rightarrow O(\log_{16} N)$ count of keys strictly `< key`
* `sorted_map_get_index_kv_pair(m, index)` $\rightarrow O(\log_{16} N)$ positional lookup by sorted rank
* `sorted_map_iterator(m)` / `sorted_map_iterator_from_string(m, lower_bound)` / `sorted_map_iterator_from_index(m, start_index)`
* `sorted_map_iterator_reverse(m)` / `sorted_map_iterator_reverse_from_string(m, upper_bound, inclusive := true)` / `sorted_map_iterator_reverse_from_index(m, start_index)` (step backward with `cursor_iterator_prev`)
* `sorted_set_iterator(s)` / `sorted_set_iterator_from_string(s, lower_bound)` / `sorted_set_iterator_from_index(s, start_index)`
* `sorted_set_iterator_reverse(s)` / `sorted_set_iterator_reverse_from_string(s, upper_bound, inclusive := true)` / `sorted_set_iterator_reverse_from_index(s, start_index)`

### `Hash_Set` & `Counted_Hash_Set` (16-way HAMT)
* `read_hash_set_init` / `write_hash_set_init` / `read_counted_hash_set_init` / `write_counted_hash_set_init`
* `hash_set_put(s, key)` / `hash_set_get_cursor(s, key)` / `hash_set_remove(s, key)`
* `hash_set_iterator(s)` / `hash_set_iterator_reverse(s)`

---

## 5. Streaming Blobs (`Cursor_Writer` & `Cursor_Reader`)

Stream arbitrarily large `.Bytes` payloads with random-access seek and zero full-blob buffering:

```odin
// Streaming write inside an active transaction:
writer, _ := xitdb.cursor_writer(&blob_wc)
writer.format_tag = transmute([]u8)string("md")
_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("# Title\n"))
_ = xitdb.cursor_writer_seek_to(&writer, 2)
_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string(" Guide\n"))
_ = xitdb.cursor_writer_finish(&writer)

// Streaming read with random-access seek:
reader, _ := xitdb.cursor_reader(blob_wc.read_cursor)
_ = xitdb.cursor_reader_seek_to(&reader, 0)
buf: [64]u8
n, _ := xitdb.cursor_reader_read(&reader, buf[:])
```

---

## 6. Compaction & Incremental Replication (`xitdb/compact_replicate.odin`)

### Garbage-Collecting Compaction
```odin
// Option A: Fast open-addressed in-memory offset map (default)
compacted_db, err := xitdb.database_compact(&source_db, &target_core)

// Option B: Disk-backed File_Offset_Map for bounded RAM on multi-GB databases
om_core := xitdb.core_memory_init()
defer xitdb.core_destroy(&om_core)
om_db, _ := xitdb.database_init(&om_core, xitdb.sha1_hasher())
fom, _   := xitdb.file_offset_map_init(&om_db)
compacted_db2, err2 := xitdb.database_compact(&source_db, &target_core2, xitdb.Offset_Map(fom))
```

### Incremental Byte-Range Replication
```odin
rep_state, _    := xitdb.database_replica_state(&replica_db)
start_offset, _ := xitdb.database_replication_start(&primary_db, rep_state)
end_offset, _   := xitdb.database_committed_size(&primary_db)
delta, _        := xitdb.database_read_committed_bytes(&primary_db, start_offset, end_offset, context.temp_allocator)
_                = xitdb.database_apply_replicated_bytes(&replica_db, start_offset, delta)
```
Full replication (`start == 0` in `database_apply_replicated` and `database_apply_replicated_bytes`) validates `header_validate_hasher` (`.Invalid_Hash_Size` / `.Invalid_Hash_Id`) before truncating or mutating replica state.

---

## 7. Structural Collection Diff (`xitdb/collection_diff.odin`)

Compare two versions of a `Hash_Map`, `Hash_Set`, `Counted_Hash_Map`, `Counted_Hash_Set`, `Sorted_Map`, or `Sorted_Set` by raw byte keys without decoding unchanged entries:

* **`diff_collection(cur_a, cur_b: Read_Cursor, allocator := context.temp_allocator) -> ([]Collection_Change, Error)`**
* **`diff_collection_with_stats(cur_a, cur_b: Read_Cursor, stats: ^Diff_Stats = nil, allocator := context.temp_allocator, scratch_allocator := context.temp_allocator) -> ([]Collection_Change, Error)`**
  * `Diff_Stats` records `slots_skipped`, `blocks_compared`, and `keys_decoded` across both HAMT (`O(changes x depth)`) and B+Tree (`O(changes x log N)`) traversals.
  * `Collection_Change` emits `op` (`Collection_Change_Op`: `.Added`, `.Removed`, `.Changed`), `key: []u8`, `old_value: Read_Cursor`, and `new_value: Read_Cursor`.
* **Same-`Database` Contract & `Core_Overlay`**:
  Both cursors must belong to the same `Database` instance (`Slot` pointer equality is only valid within one file); mismatched `db` handles or non-empty/root cursors with `db == nil` return `.Invalid_Database`. An empty sentinel `Read_Cursor{}` is permitted on one side to enumerate all additions or removals. When diffing across a `Core_Overlay` fork, resolve both moments from the overlay's own `Database` handle.
* **Zero-Alloc Equal-Slot Fast-Path & Allocator Isolation**:
  Identical slots (`a.slot_ptr.slot == b.slot_ptr.slot`) short-circuit immediately returning `nil, nil` (`slots_skipped = 1`) with zero allocations. All temporary HAMT entry buffers and B+Tree key comparison slices are freed on `scratch_allocator` on both normal and error paths; callers own the returned `[]Collection_Change` slice and each `ch.key` buffer on `allocator`.

```odin
stats: xitdb.Diff_Stats
changes, err := xitdb.diff_collection_with_stats(
    cur_a,
    cur_b,
    &stats,
    allocator = context.allocator,
    scratch_allocator = context.temp_allocator,
)
assert(err == nil)
defer {
    for ch in changes {
        delete(ch.key, context.allocator)
    }
    delete(changes, context.allocator)
}
```
