# Implementation Plan: `xitdb_v1_odin_20261101`

## Phase 1: Wire Protocol & Core I/O Backends
- [x] Implement `Tag`, `Slot`, `Header`, `Root_Header`, `Root_Trailer`, CRC-64/XZ checksums, and pure-Odin SHA-1 / SHA-256 in [`xitdb/types.odin`](../../xitdb/types.odin).
- [x] Implement `Core_Memory`, `Core_File`, and `Core_Buffered_File` in [`xitdb/core.odin`](../../xitdb/core.odin).

## Phase 2: Database Engine, HAMT, and B-Tree / B+Tree
- [x] Implement `Database`, `Transaction`, root header/trailer commits, and `read_slot_pointer` path resolution in [`xitdb/database.odin`](../../xitdb/database.odin).
- [x] Implement 16-way HAMT and Radix-Trie index blocks in [`xitdb/hamt.odin`](../../xitdb/hamt.odin).
- [x] Implement count-augmented B-Tree (`Linked_Array_List`) and Sorted B+Tree (`Sorted_Map`, `Sorted_Set`) in [`xitdb/btree.odin`](../../xitdb/btree.odin).

## Phase 3: Cursors, Collections, Compaction & Replication
- [x] Implement `Read_Cursor`, `Write_Cursor`, `Cursor_Reader`, `Cursor_Writer`, and `Cursor_Iterator` in [`xitdb/cursor.odin`](../../xitdb/cursor.odin).
- [x] Implement high-level collection wrappers in [`xitdb/collections.odin`](../../xitdb/collections.odin).
- [x] Implement `database_compact` (`Memory_Offset_Map`, `File_Offset_Map`) and incremental replication in [`xitdb/compact_replicate.odin`](../../xitdb/compact_replicate.odin).

## Phase 4: Verification & Reference Fixture Testing
- [x] Copy upstream binary fixture to [`tests/testdata/test.db`](../../tests/testdata/test.db).
- [x] Write comprehensive test suite in [`tests/test_xitdb.odin`](../../tests/test_xitdb.odin) and verify all 6 test suites pass with zero memory leaks (`odin test tests`).
