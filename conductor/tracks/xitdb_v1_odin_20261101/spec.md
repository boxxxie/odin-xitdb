# Specification: Full v1 Odin Implementation of `xitdb`

## Overview
Port **[`xitdb`](https://github.com/xit-vcs/xitdb)** (`v1` binary wire format) to idiomatic Odin with zero external dependencies and 100% wire compatibility with the reference Zig (`.tmp/ref/xitdb-zig`) and Go (`.tmp/ref/xitdb-go`) implementations.

## Architecture & Scope

1. **Binary Wire Format (`v1`) & Primitives ([`xitdb/types.odin`](../../xitdb/types.odin)):**
   - 20-byte `Header` (`magic_number = "xit"`, `version = 1`, `hash_size`, `hash_id`, `file_id`)
   - 17-byte `Root_Header` and 25-byte `Root_Trailer` protected by CRC-64/XZ (`compute_root_trailer_checksum`)
   - 9-byte `Slot` (1-byte tag + full bit, 8-byte big-endian value/offset)
   - Pure-Odin `sha1_sum` (20-byte) and `sha256_sum` (32-byte) + configurable `Hasher`

2. **Storage Backends ([`xitdb/core.odin`](../../xitdb/core.odin)):**
   - `Core_Memory`: In-memory dynamic buffer
   - `Core_File`: OS file with configurable `fsync`
   - `Core_Buffered_File`: Write-buffered OS file matching Zig `CoreBufferedFile` semantics

3. **Persistent Data Structures ([`xitdb/hamt.odin`](../../xitdb/hamt.odin), [`xitdb/btree.odin`](../../xitdb/btree.odin)):**
   - 16-way Radix Trie (`Array_List`)
   - 16-way Hash Array Mapped Trie (`Hash_Map`, `Counted_Hash_Map`, `Hash_Set`, `Counted_Hash_Set`)
   - Count-augmented 16-way B-Tree (`Linked_Array_List`) supporting `O(log N)` insert, remove, slice, and concat
   - Count-augmented 16-way B+Tree (`Sorted_Map`, `Sorted_Set`) supporting lexicographical ordering, rank, index lookup, and range iterators

4. **Cursors, High-Level Collections, Compaction & Replication ([`xitdb/cursor.odin`](../../xitdb/cursor.odin), [`xitdb/collections.odin`](../../xitdb/collections.odin), [`xitdb/compact_replicate.odin`](../../xitdb/compact_replicate.odin)):**
   - `Read_Cursor`, `Write_Cursor`, `Cursor_Reader`, `Cursor_Writer`, `Cursor_Iterator`
   - `database_compact` with `Memory_Offset_Map` and `File_Offset_Map`
   - Incremental log replication (`database_replica_state`, `database_replication_start`, `database_read_committed`, `database_apply_replicated`)
