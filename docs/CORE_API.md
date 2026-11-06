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
  Unbuffered OS file I/O using `os.read_at` (`pread` on Linux) for lock-free concurrent reads on a shared `^Database`.
* **`core_buffered_file_open(path: string, buffer_size: i64 = DEFAULT_BUFFER_SIZE, flags := os.File_Flags{.Read, .Write, .Create}, fsync := true, allocator := context.allocator) -> (Core, Error)`**
  Pairs an OS file handle with an in-memory tail write buffer (`2 MiB` default). Flushes on root commit (`database_commit_root`) so all committed moments are served via stateless `os.read_at`.
* **`core_destroy(c: ^Core, close_file := false) -> Error`**
  Releases virtual or heap memory buffers (`vmem.release` / `delete`) and optionally closes the underlying file handle.

### Hashers

HAMT collections (`Hash_Map`, `Counted_Hash_Map`, `Hash_Set`, `Counted_Hash_Set`) hash keys using the `Database`'s configured `Hasher`:

* **`sha1_hasher(id: u32 = HASH_ID_SHA1, file_id: [4]u8 = DEFAULT_FILE_ID) -> Hasher`**
  20-byte SHA-1 digest (automatically hardware-accelerated via x86 SHA-NI when supported by the CPU).
* **`sha256_hasher(id: u32 = HASH_ID_SHA256, file_id: [4]u8 = DEFAULT_FILE_ID) -> Hasher`**
  32-byte SHA-256 digest (hardware-accelerated via x86 SHA-NI when supported).
* **Custom `Hasher`**:
  ```odin
  custom := xitdb.Hasher{
      hash_proc = my_blake3_proc,
      hash_size = 32,
      id        = xitdb.bytes_to_hash_id("blk3"),
      file_id   = xitdb.DEFAULT_FILE_ID,
  }
  ```

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
1. **`Header` (20 bytes)**: Magic (`"xit\x00"` or custom `file_id`), `hash_size` (`u16`), `hash_id` (`u32`), `version` (`u16`), and `root_header_offset` (`i64`).
2. **`Root_Header` (17 bytes)**: Latest committed `trailer_offset` (`i64`) and `root_slot` (`Slot`).
3. **`Root_Trailer` (25 bytes, appended at the end of every root transaction)**: `commit_id` (`u64`), `root_slot` (`Slot`), and `checksum` (`u64` CRC-64/XZ over `file_id || trailer_offset || commit_id || root_slot_bytes`).

If a crash occurs mid-transaction before `Root_Header` is updated, reopening the database verifies the trailer at `Root_Header.trailer_offset` and automatically truncates any uncommitted trailing bytes on the next write.

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
* **Scalar & Byte Writes**:
  * `cursor_write(c: ^Write_Cursor, data: Writeable_Data) -> Error`
  * `cursor_write_if_empty(c: ^Write_Cursor, data: Writeable_Data) -> Error`

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
