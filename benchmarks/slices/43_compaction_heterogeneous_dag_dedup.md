# #43. `Compaction (Heterogeneous DAG + dedup)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1462-L1521`)](../bench_xitdb.odin#L1462-L1521) · [Zig Harness (`bench_xitdb.zig#L1516-L1603`)](../bench_xitdb.zig#L1516-L1603)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **32,772** | 33,414.8 ± 1,667.6 | 5.0% | 35,683.2 | 30,514 | 23.4 KB | **3.23x Odin** (`z = 16.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 105,729 | 108,305.6 ± 10,018.2 | 9.2% | 119,276.4 | 9,458 | 23.4 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Open-Addressed `Memory_Offset_Map` & Single-Pass Block Reservation (`#43` — 3.22x faster in Odin: `32.8 µs` vs `105.7 µs`):** Both implementations produce the exact same `23.4 KB` compacted wire image and deduplicate shared structural nodes identically ([`xitdb/compact_replicate.odin#L11-L177`](../../xitdb/compact_replicate.odin#L11-L177) vs. [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913)). Odin's `Memory_Offset_Map` uses a flat, open-addressed `[]Memory_Offset_Entry` table with Fibonacci hashing (`0x9e3779b97f4a7c15`), `_compactor_reserve_block` resizes `Core_Memory.buf` in $O(1)$ without zero-writing twice (while enforcing `max_size`), and B-Tree/B+Tree compaction formats active `0..<num` slots in stack buffers.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Pre-size `CoreMemory` target buffer & batch-write remapped slots in `Compactor` ([`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911)):** Visiting `0..header.num` and writing each compacted node in one `writeAll` (after pre-reserving the target `CoreMemory` buffer instead of zero-writing twice) eliminates per-slot `writeInt` vtable dispatches.
- **Streamlined `readCommitted` / `applyReplicated` slice copies (`#39–#40`):** Copying committed byte slices directly on `CoreMemory` avoids unbuffered `std.Io` vtable overhead.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1462-L1521`](../bench_xitdb.odin#L1462-L1521))

```odin
1462 | 	// 4d. Heterogeneous DAG Compaction (`Array_List` + `Linked_Array_List` + `Sorted_Map` + `Counted_Hash_Map` + DAG shared subtrees)
1463 | 	{
1464 | 		dag_src_core: xitdb.Core = xitdb.core_memory_init()
1465 | 		defer xitdb.core_destroy(&dag_src_core)
1466 | 		dag_db, _ := xitdb.database_init(&dag_src_core, xitdb.sha1_hasher())
1467 | 
1468 | 		build_dag_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1469 | 			root_map := xitdb.write_counted_hash_map_init(cursor^) or_return
1470 | 
1471 | 			// 1. Array_List with 200 items
1472 | 			al_wc := xitdb.hash_map_put_cursor(&root_map, "array_list") or_return
1473 | 			al := xitdb.write_array_list_init(al_wc) or_return
1474 | 			for i in 0 ..< 200 {
1475 | 				xitdb.array_list_append(&al, fmt.tprintf("arr-item-%04d-payload", i)) or_return
1476 | 			}
1477 | 			al_slot := xitdb.array_list_slot(al.read_array_list) or_return
1478 | 
1479 | 			// 2. Linked_Array_List with 200 items
1480 | 			lal_wc := xitdb.hash_map_put_cursor(&root_map, "linked_list") or_return
1481 | 			lal := xitdb.write_linked_array_list_init(lal_wc) or_return
1482 | 			for i in 0 ..< 200 {
1483 | 				xitdb.linked_array_list_append(&lal, u64(i)) or_return
1484 | 			}
1485 | 			lal_slot := xitdb.linked_array_list_slot(lal.read_linked_array_list) or_return
1486 | 
1487 | 			// 3. Sorted_Map with 200 items
1488 | 			sm_wc := xitdb.hash_map_put_cursor(&root_map, "sorted_map") or_return
1489 | 			sm := xitdb.write_sorted_map_init(sm_wc) or_return
1490 | 			for i in 0 ..< 200 {
1491 | 				xitdb.sorted_map_put(&sm, fmt.tprintf("skey-%04d", (i * 73) % 200), u64(i)) or_return
1492 | 			}
1493 | 			sm_slot := xitdb.sorted_map_slot(sm.read_sorted_map) or_return
1494 | 
1495 | 			// 4. DAG structural sharing: reference the same 3 collections under 5 alias keys each
1496 | 			for alias_i in 0 ..< 5 {
1497 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-al-%d", alias_i), al_slot) or_return
1498 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-lal-%d", alias_i), lal_slot) or_return
1499 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-sm-%d", alias_i), sm_slot) or_return
1500 | 			}
1501 | 			return nil
1502 | 		}
1503 | 
1504 | 		_ = xitdb.database_run_context(&dag_db, build_dag_cb, nil)
1505 | 
1506 | 		dag_dst_core: xitdb.Core = xitdb.core_memory_init()
1507 | 		defer xitdb.core_destroy(&dag_dst_core)
1508 | 		dag_om: xitdb.Offset_Map = xitdb.memory_offset_map_init()
1509 | 		defer xitdb.offset_map_destroy(&dag_om)
1510 | 
1511 | 		t_dag := time.now()
1512 | 		dag_comp_db, _ := xitdb.database_compact(&dag_db, &dag_dst_core, &dag_om)
1513 | 		elapsed_dag := time.since(t_dag)
1514 | 		dag_comp_sz, _ := xitdb.database_committed_size(&dag_comp_db)
1515 | 
1516 | 		print_result(Bench_Result{
1517 | 			name       = "Compaction (Heterogeneous DAG + dedup)",
1518 | 			ops        = 1,
1519 | 			elapsed    = elapsed_dag,
1520 | 			bytes_used = dag_comp_sz,
1521 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1516-L1603`](../bench_xitdb.zig#L1516-L1603))

```zig
1516 |     // 4d. Heterogeneous DAG Compaction (`Array_List` + `Linked_Array_List` + `Sorted_Map` + `Counted_Hash_Map` + DAG shared subtrees)
1517 |     {
1518 |         var dag_src_buffer = std.Io.Writer.Allocating.init(allocator);
1519 |         defer dag_src_buffer.deinit();
1520 |         var dag_db = try DB.init(io, .{ .buffer = &dag_src_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1521 | 
1522 |         const BuildDagCtx = struct {
1523 |             pub fn run(_: @This(), cursor: *DB.Cursor(.read_write)) !void {
1524 |                 const root_map = try DB.CountedHashMap(.read_write).init(cursor.*);
1525 | 
1526 |                 // 1. Array_List with 200 items
1527 |                 const al_key = "array_list";
1528 |                 const al_hash = hashSha1(al_key);
1529 |                 try root_map.putKey(al_hash, .{ .bytes = al_key });
1530 |                 const al_wc = try root_map.putCursor(al_hash);
1531 |                 const al = try DB.ArrayList(.read_write).init(al_wc);
1532 |                 for (0..200) |i| {
1533 |                     var ibuf: [32]u8 = undefined;
1534 |                     const item = try std.fmt.bufPrint(&ibuf, "arr-item-{d:0>4}-payload", .{i});
1535 |                     try al.append(.{ .bytes = item });
1536 |                 }
1537 |                 const al_slot = try al.slot();
1538 | 
1539 |                 // 2. Linked_Array_List with 200 items
1540 |                 const lal_key = "linked_list";
1541 |                 const lal_hash = hashSha1(lal_key);
1542 |                 try root_map.putKey(lal_hash, .{ .bytes = lal_key });
1543 |                 const lal_wc = try root_map.putCursor(lal_hash);
1544 |                 const lal = try DB.LinkedArrayList(.read_write).init(lal_wc);
1545 |                 for (0..200) |i| {
1546 |                     try lal.append(.{ .uint = @intCast(i) });
1547 |                 }
1548 |                 const lal_slot = try lal.slot();
1549 | 
1550 |                 // 3. Sorted_Map with 200 items
1551 |                 const sm_key = "sorted_map";
1552 |                 const sm_hash = hashSha1(sm_key);
1553 |                 try root_map.putKey(sm_hash, .{ .bytes = sm_key });
1554 |                 const sm_wc = try root_map.putCursor(sm_hash);
1555 |                 const sm = try DB.SortedMap(.read_write).init(sm_wc);
1556 |                 for (0..200) |i| {
1557 |                     var skbuf: [16]u8 = undefined;
1558 |                     const sk = try std.fmt.bufPrint(&skbuf, "skey-{d:0>4}", .{(i * 73) % 200});
1559 |                     try sm.put(sk, .{ .uint = @intCast(i) });
1560 |                 }
1561 |                 const sm_slot = try sm.slot();
1562 | 
1563 |                 // 4. DAG structural sharing: reference the same 3 collections under 5 alias keys each
1564 |                 for (0..5) |alias_i| {
1565 |                     var k1buf: [16]u8 = undefined;
1566 |                     const k1 = try std.fmt.bufPrint(&k1buf, "alias-al-{d}", .{alias_i});
1567 |                     const h1 = hashSha1(k1);
1568 |                     try root_map.putKey(h1, .{ .bytes = k1 });
1569 |                     try root_map.put(h1, .{ .slot = al_slot });
1570 | 
1571 |                     var k2buf: [16]u8 = undefined;
1572 |                     const k2 = try std.fmt.bufPrint(&k2buf, "alias-lal-{d}", .{alias_i});
1573 |                     const h2 = hashSha1(k2);
1574 |                     try root_map.putKey(h2, .{ .bytes = k2 });
1575 |                     try root_map.put(h2, .{ .slot = lal_slot });
1576 | 
1577 |                     var k3buf: [16]u8 = undefined;
1578 |                     const k3 = try std.fmt.bufPrint(&k3buf, "alias-sm-{d}", .{alias_i});
1579 |                     const h3 = hashSha1(k3);
1580 |                     try root_map.putKey(h3, .{ .bytes = k3 });
1581 |                     try root_map.put(h3, .{ .slot = sm_slot });
1582 |                 }
1583 |             }
1584 |         };
1585 | 
1586 |         try dag_db.runContext(BuildDagCtx{});
1587 | 
1588 |         var dag_dst_buffer = std.Io.Writer.Allocating.init(allocator);
1589 |         defer dag_dst_buffer.deinit();
1590 |         var dag_om = std.AutoHashMap(u64, u64).init(allocator);
1591 |         defer dag_om.deinit();
1592 | 
1593 |         const t_dag = std.Io.Clock.awake.now(io);
1594 |         var dag_comp_db = try dag_db.compact(.memory, .{ .buffer = &dag_dst_buffer }, &dag_om);
1595 |         const elapsed_dag = t_dag.untilNow(io, .awake).nanoseconds;
1596 |         const dag_comp_sz = try dag_comp_db.committedSize();
1597 | 
1598 |         try printResult(stdout, .{
1599 |             .name = "Compaction (Heterogeneous DAG + dedup)",
1600 |             .ops = 1,
1601 |             .elapsed_ns = elapsed_dag,
1602 |             .bytes_used = dag_comp_sz,
1603 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `compact` | 60 | Top-level `Database.compact` reachability-copy entry point | [`lib.zig#L650-L709`](../../reference/xitdb-zig/src/lib.zig#L650-L709) |
| `Compactor` | 406 | Reachability-based garbage-collecting compactor (`std.AutoHashMap` / custom `OffsetMap`) | [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) |
| `readCommitted` | 16 | Committed byte-range streaming for incremental replication | [`lib.zig#L592-L607`](../../reference/xitdb-zig/src/lib.zig#L592-L607) |
| `applyReplicated` | 25 | Replica byte-stream application and root trailer verification | [`lib.zig#L613-L637`](../../reference/xitdb-zig/src/lib.zig#L613-L637) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |
| `CoreBufferedFile` | 166 | Contiguous tail-buffered OS file backend (`flush` clears buffer on `sync`) | [`lib.zig#L5067-L5232`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232) |

### Reached Odin Procedures (`154` procedures across `8` files · `3892` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/collections.odin` | `write_counted_hash_map_init` | **Entry Point** (`depth 0`) | 14 | [`xitdb/collections.odin#L257-L270`](../../xitdb/collections.odin#L257-L270) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L423-L428`](../../xitdb/collections.odin#L423-L428) |
| `xitdb/collections.odin` | `write_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_append` | **Entry Point** (`depth 0`) | 7 | [`xitdb/collections.odin#L69-L75`](../../xitdb/collections.odin#L69-L75) |
| `xitdb/collections.odin` | `array_list_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L33-L35`](../../xitdb/collections.odin#L33-L35) |
| `xitdb/collections.odin` | `write_linked_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L118-L123`](../../xitdb/collections.odin#L118-L123) |
| `xitdb/collections.odin` | `linked_array_list_append` | **Entry Point** (`depth 0`) | 7 | [`xitdb/collections.odin#L161-L167`](../../xitdb/collections.odin#L161-L167) |
| `xitdb/collections.odin` | `linked_array_list_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L125-L127`](../../xitdb/collections.odin#L125-L127) |
| `xitdb/collections.odin` | `write_sorted_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L679-L684`](../../xitdb/collections.odin#L679-L684) |
| `xitdb/collections.odin` | `sorted_map_put` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/collections.odin` | `sorted_map_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L686-L688`](../../xitdb/collections.odin#L686-L688) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L301-L305`](../../xitdb/database.odin#L301-L305) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_init` | **Entry Point** (`depth 0`) | 3 | [`xitdb/compact_replicate.odin#L31-L33`](../../xitdb/compact_replicate.odin#L31-L33) |
| `xitdb/compact_replicate.odin` | `offset_map_destroy` | **Entry Point** (`depth 0`) | 6 | [`xitdb/compact_replicate.odin#L172-L177`](../../xitdb/compact_replicate.odin#L172-L177) |
| `xitdb/compact_replicate.odin` | `database_compact` | **Entry Point** (`depth 0`) | 78 | [`xitdb/compact_replicate.odin#L734-L811`](../../xitdb/compact_replicate.odin#L734-L811) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_compact`, `database_commit_root`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `write_counted_hash_map_init`, `read_array_list_init`, `cursor_slot`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_counted_hash_map_init`, `write_array_list_init`, `array_list_append`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `array_list_slot`, `linked_array_list_slot`, `sorted_map_slot`) | 4 | [`xitdb/cursor.odin#L64-L67`](../../xitdb/cursor.odin#L64-L67) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 1` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 1` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_put_by_bytes` | `depth 1` (from `sorted_map_put`) | 7 | [`xitdb/collections.odin#L766-L772`](../../xitdb/collections.odin#L766-L772) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`, `database_compact`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_destroy` | `depth 1` (from `offset_map_destroy`) | 7 | [`xitdb/compact_replicate.odin#L35-L41`](../../xitdb/compact_replicate.odin#L35-L41) |
| `xitdb/compact_replicate.odin` | `offset_map_reset` | `depth 1` (from `database_compact`) | 16 | [`xitdb/compact_replicate.odin#L89-L104`](../../xitdb/compact_replicate.odin#L89-L104) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_compact`, `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/types.odin` | `slot_empty` | `depth 1` (from `database_compact`, `cursor_read_path_slot`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `database_compact`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `_exec_path_part`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_memory_resize` | `depth 2` (from `core_write_all`, `core_write_slot`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `cursor_resolved`, `database_read_root_slot`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `cursor_write_path`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 2` (from `offset_map_reset`) | 5 | [`xitdb/cursor.odin#L186-L190`](../../xitdb/cursor.odin#L186-L190) |
| `xitdb/collections.odin` | `write_hash_map_init` | `depth 2` (from `offset_map_reset`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `btree_insert`, `sorted_target_slot`) | 5 | [`xitdb/core.odin#L568-L572`](../../xitdb/core.odin#L568-L572) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `btree_insert`) | 15 | [`xitdb/core.odin#L574-L588`](../../xitdb/core.odin#L574-L588) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L543-L566`](../../xitdb/core.odin#L543-L566) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1138-L1142`](../../xitdb/btree.odin#L1138-L1142) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `btree_reusable`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/btree.odin` | `btree_insert` | `depth 4` (from `_exec_path_part`) | 250 | [`xitdb/btree.odin#L191-L440`](../../xitdb/btree.odin#L191-L440) |
| `xitdb/btree.odin` | `btree_grow_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L442-L444`](../../xitdb/btree.odin#L442-L444) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 115 | [`xitdb/btree.odin#L1278-L1392`](../../xitdb/btree.odin#L1278-L1392) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2229-L2246`](../../xitdb/btree.odin#L2229-L2246) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1697-L2070`](../../xitdb/btree.odin#L1697-L2070) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2216-L2227`](../../xitdb/btree.odin#L2216-L2227) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L496-L501`](../../xitdb/core.odin#L496-L501) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L488-L494`](../../xitdb/core.odin#L488-L494) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1396-L1449`](../../xitdb/database.odin#L1396-L1449) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1383-L1394`](../../xitdb/database.odin#L1383-L1394) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_insert`, `btree_write_node`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 3` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `slot_from_slice`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1098-L1136`](../../xitdb/btree.odin#L1098-L1136) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `btree_insert`, `sorted_put`, `btree_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `btree_insert`, `sorted_put`, `core_write_long`) | 14 | [`xitdb/core.odin#L528-L541`](../../xitdb/core.odin#L528-L541) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_insert`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 5` (from `btree_insert`) | 7 | [`xitdb/btree.odin#L91-L97`](../../xitdb/btree.odin#L91-L97) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_insert`) | 10 | [`xitdb/types.odin#L1249-L1258`](../../xitdb/types.odin#L1249-L1258) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_grow_root`) | 11 | [`xitdb/btree.odin#L790-L800`](../../xitdb/btree.odin#L790-L800) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `sorted_get`, `read_map_slot`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L435-L451`](../../xitdb/core.odin#L435-L451) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `sorted_get`, `sorted_put`, `read_btree_node`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1160-L1172`](../../xitdb/btree.odin#L1160-L1172) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1181-L1240`](../../xitdb/btree.odin#L1181-L1240) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1634-L1640`](../../xitdb/btree.odin#L1634-L1640) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1152-L1158`](../../xitdb/btree.odin#L1152-L1158) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1174-L1179`](../../xitdb/btree.odin#L1174-L1179) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1642-L1695`](../../xitdb/btree.odin#L1642-L1695) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1144-L1150`](../../xitdb/btree.odin#L1144-L1150) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1299-L1308`](../../xitdb/types.odin#L1299-L1308) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1059-L1096`](../../xitdb/btree.odin#L1059-L1096) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1244-L1260`](../../xitdb/btree.odin#L1244-L1260) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1263-L1276`](../../xitdb/btree.odin#L1263-L1276) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L503-L526`](../../xitdb/core.odin#L503-L526) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`, `btree_write_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`, `read_map_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1155-L1189`](../../xitdb/types.odin#L1155-L1189) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `write_kv_pair`, `kv_pair_write`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`, `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1136-L1145`](../../xitdb/types.odin#L1136-L1145) |
