# #42. `Compaction (File_Offset_Map, 200 -> 1)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1439-L1460`)](../bench_xitdb.odin#L1439-L1460) · [Zig Harness (`bench_xitdb.zig#L1460-L1514`)](../bench_xitdb.zig#L1460-L1514)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **9,347** | 9,491.4 ± 481.3 | 5.1% | 10,116.8 | 106,986 | 1.2 KB | **1.47x Odin** (`z = 5.6`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 13,706 | 14,459.2 ± 1,933.7 | 13.4% | 17,113.8 | 72,961 | 1.2 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Direct Slice Streaming in Replication ([`xitdb/compact_replicate.odin#L15-L148`](../../xitdb/compact_replicate.odin#L15-L148)):** On `#39 Replication (genesis -> 200 moments)` (**10.04x faster in Odin**) and `#40 Incremental 1-moment delta` (**2.25x faster**), Odin's `database_read_committed_bytes` and `database_apply_replicated_bytes` copy committed byte ranges directly between buffers and verify the 25-byte `Root_Trailer` CRC-64/XZ in place, avoiding `std.Io.Reader.stream` / `std.Io.Writer.drain` 256-byte chunking.
- **Flat Open-Addressed `Memory_Offset_Map` & Buffered `File_Offset_Map` ([`xitdb/compact_replicate.odin#L150-L260`](../../xitdb/compact_replicate.odin#L150-L260)):** On `#41` (**2.05x faster**) and `#42` (**1.47x faster**), Odin pre-sizes the offset map and copies index blocks in single `core_read_exact` / `core_write_all` transfers.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Increase stream buffer size or slice directly in `readCommitted` / `applyReplicated` ([`lib.zig#L592-L637`](../../reference/xitdb-zig/src/lib.zig#L592-L637)):** Streaming via `CoreMemory`'s 256-byte `std.Io` buffer breaks a 250 KB replication delta into ~1,000 virtual `stream`/`drain` calls; exposing a direct slice fast path (or a 64 KB buffer) removes that overhead.
- **Apply the B-Tree / Sorted-Node batch read optimization in `Compactor` ([`lib.zig#L4620-L4760`](../../reference/xitdb-zig/src/lib.zig#L4620-L4760)):** `Compactor.compactBTreeNode` and `compactSortedNode` call `readBTreeNode`/`readSortedNode` and `writeBTreeNodeAt`/`writeSortedNodeAt`, so batch-reading nodes speeds up compaction as well.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1439-L1460`](../bench_xitdb.odin#L1439-L1460))

```odin
1439 | 	// 4c. Compact using disk-backed `File_Offset_Map`
1440 | 	comp_file_core: xitdb.Core = xitdb.core_memory_init()
1441 | 	defer xitdb.core_destroy(&comp_file_core)
1442 | 
1443 | 	om_core: xitdb.Core = xitdb.core_memory_init()
1444 | 	defer xitdb.core_destroy(&om_core)
1445 | 	om_db, _ := xitdb.database_init(&om_core, xitdb.sha1_hasher())
1446 | 	om_rc := xitdb.database_root_cursor(&om_db)
1447 | 	file_om, _ := xitdb.file_offset_map_init(om_rc)
1448 | 	file_offset_map: xitdb.Offset_Map = file_om
1449 | 
1450 | 	t2 := time.now()
1451 | 	comp_db2, _ := xitdb.database_compact(&db, &comp_file_core, &file_offset_map)
1452 | 	elapsed_file_compact := time.since(t2)
1453 | 	comp_size2, _ := xitdb.database_committed_size(&comp_db2)
1454 | 
1455 | 	print_result(Bench_Result{
1456 | 		name       = "Compaction (File_Offset_Map, 200 -> 1)",
1457 | 		ops        = 1,
1458 | 		elapsed    = elapsed_file_compact,
1459 | 		bytes_used = comp_size2,
1460 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1460-L1514`](../bench_xitdb.zig#L1460-L1514))

```zig
1460 |     // 4c. Compact using xitdb-backed `File_Offset_Map` (in-memory Core_Memory backing db, matching Odin)
1461 |     const OffsetDB = xitdb.Database(.memory, u64);
1462 |     const FileOffsetMap = struct {
1463 |         map: OffsetDB.HashMap(.read_write),
1464 | 
1465 |         pub fn reset(self: *@This()) !void {
1466 |             var cursor = self.map.cursor;
1467 |             try cursor.write(.{ .slot = null });
1468 |             self.map = try OffsetDB.HashMap(.read_write).init(cursor);
1469 |         }
1470 | 
1471 |         pub fn get(self: *@This(), source_offset: u64) !?u64 {
1472 |             const cursor = (try self.map.getCursor(source_offset)) orelse return null;
1473 |             return try cursor.readUint();
1474 |         }
1475 | 
1476 |         pub fn put(self: *@This(), source_offset: u64, target_offset: u64) !void {
1477 |             try self.map.put(source_offset, .{ .uint = target_offset });
1478 |         }
1479 |     };
1480 | 
1481 |     var comp_file_buffer = std.Io.Writer.Allocating.init(allocator);
1482 |     defer comp_file_buffer.deinit();
1483 | 
1484 |     var om_buffer = std.Io.Writer.Allocating.init(allocator);
1485 |     defer om_buffer.deinit();
1486 |     var om_db = try OffsetDB.init(io, .{ .buffer = &om_buffer });
1487 | 
1488 |     const FileCompactCtx = struct {
1489 |         src_db: *DB,
1490 |         target_buf: *std.Io.Writer.Allocating,
1491 |         comp_size_out: *u64,
1492 | 
1493 |         pub fn run(self: @This(), cursor: *OffsetDB.Cursor(.read_write)) !void {
1494 |             var file_om = FileOffsetMap{ .map = try OffsetDB.HashMap(.read_write).init(cursor.*) };
1495 |             var comp_db2 = try self.src_db.compact(.memory, .{ .buffer = self.target_buf }, &file_om);
1496 |             self.comp_size_out.* = try comp_db2.committedSize();
1497 |         }
1498 |     };
1499 | 
1500 |     var comp_size2: u64 = 0;
1501 |     const t2 = std.Io.Clock.awake.now(io);
1502 |     try om_db.runContext(FileCompactCtx{
1503 |         .src_db = &db,
1504 |         .target_buf = &comp_file_buffer,
1505 |         .comp_size_out = &comp_size2,
1506 |     });
1507 |     const elapsed_file_compact = t2.untilNow(io, .awake).nanoseconds;
1508 | 
1509 |     try printResult(stdout, .{
1510 |         .name = "Compaction (File_Offset_Map, 200 -> 1)",
1511 |         .ops = 1,
1512 |         .elapsed_ns = elapsed_file_compact,
1513 |         .bytes_used = comp_size2,
1514 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `Compactor` | 406 | Reachability-based garbage-collecting compactor (`MemoryOffsetMap` / `FileOffsetMap`) | [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) |
| `readCommitted` | 16 | Committed byte-range streaming for incremental replication | [`lib.zig#L592-L607`](../../reference/xitdb-zig/src/lib.zig#L592-L607) |
| `applyReplicated` | 25 | Replica byte-stream application and root trailer verification | [`lib.zig#L613-L637`](../../reference/xitdb-zig/src/lib.zig#L613-L637) |
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |
| `CoreBufferedFile` | 153 | Write-buffered OS file backend | [`lib.zig#L5068-L5220`](../../reference/xitdb-zig/src/lib.zig#L5068-L5220) |

### Reached Odin Procedures (`88` procedures across `7` files · `1889` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Hash_Map_Init`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/compact_replicate.odin` | `file_offset_map_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/compact_replicate.odin#L30-L36`](../../xitdb/compact_replicate.odin#L30-L36) |
| `xitdb/compact_replicate.odin` | `database_compact` | **Entry Point** (`depth 0`) | 62 | [`xitdb/compact_replicate.odin#L615-L676`](../../xitdb/compact_replicate.odin#L615-L676) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`, `database_compact`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/collections.odin` | `write_hash_map_init` | `depth 1` (from `file_offset_map_init`, `offset_map_reset`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_init` | `depth 1` (from `database_compact`) | 3 | [`xitdb/compact_replicate.odin#L22-L24`](../../xitdb/compact_replicate.odin#L22-L24) |
| `xitdb/compact_replicate.odin` | `offset_map_destroy` | `depth 1` (from `database_compact`) | 6 | [`xitdb/compact_replicate.odin#L95-L100`](../../xitdb/compact_replicate.odin#L95-L100) |
| `xitdb/compact_replicate.odin` | `offset_map_reset` | `depth 1` (from `database_compact`) | 13 | [`xitdb/compact_replicate.odin#L49-L61`](../../xitdb/compact_replicate.odin#L49-L61) |
| `xitdb/types.odin` | `slot_empty` | `depth 1` (from `database_compact`, `cursor_read_path_slot`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `database_compact`) | 15 | [`xitdb/cursor.odin#L81-L95`](../../xitdb/cursor.odin#L81-L95) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `database_compact`, `write_hash_map_init`, `database_run_context`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/database.odin` | `database_run_context` | `depth 1` (from `database_compact`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 2` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_destroy` | `depth 2` (from `offset_map_destroy`) | 3 | [`xitdb/compact_replicate.odin#L26-L28`](../../xitdb/compact_replicate.odin#L26-L28) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 2` (from `offset_map_reset`) | 5 | [`xitdb/cursor.odin#L185-L189`](../../xitdb/cursor.odin#L185-L189) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `cursor_read_path_slot`, `read_hash_map_init`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path_slot`, `cursor_write_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `read_slot_pointer`, `cursor_check_writable`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `read_array_list_slot`, `core_read_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L345-L383`](../../xitdb/hamt.odin#L345-L383) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
