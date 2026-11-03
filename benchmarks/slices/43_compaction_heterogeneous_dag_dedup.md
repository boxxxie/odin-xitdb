# #43. `Compaction (Heterogeneous DAG + dedup)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1462-L1521`)](../bench_xitdb.odin#L1462-L1521) · [Zig Harness (`bench_xitdb.zig#L1516-L1603`)](../bench_xitdb.zig#L1516-L1603)

- **Touched Library Scope:** **152** procedures across **8** `xitdb/*.odin` files (**3870** lines of library code)
- **Direct Benchmark Entry Points:** `core_memory_init`, `core_destroy`, `database_init`, `sha1_hasher`, `write_counted_hash_map_init`, `hash_map_put_cursor`, `write_array_list_init`, `array_list_append`, `array_list_slot`, `write_linked_array_list_init`, `linked_array_list_append`, `linked_array_list_slot`, `write_sorted_map_init`, `sorted_map_put`, `sorted_map_slot`, `hash_map_put`, `database_run_context`, `memory_offset_map_init`, `offset_map_destroy`, `database_compact`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1462-L1521`)

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

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1516-L1603</code>)</strong></summary>

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
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
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
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_init` | **Entry Point** (`depth 0`) | 3 | [`xitdb/compact_replicate.odin#L22-L24`](../../xitdb/compact_replicate.odin#L22-L24) |
| `xitdb/compact_replicate.odin` | `offset_map_destroy` | **Entry Point** (`depth 0`) | 6 | [`xitdb/compact_replicate.odin#L95-L100`](../../xitdb/compact_replicate.odin#L95-L100) |
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
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `write_counted_hash_map_init`, `read_array_list_init`, `cursor_slot`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_counted_hash_map_init`, `write_array_list_init`, `array_list_append`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `array_list_slot`, `linked_array_list_slot`, `sorted_map_slot`) | 4 | [`xitdb/cursor.odin#L63-L66`](../../xitdb/cursor.odin#L63-L66) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 1` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 1` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_put_by_bytes` | `depth 1` (from `sorted_map_put`) | 7 | [`xitdb/collections.odin#L766-L772`](../../xitdb/collections.odin#L766-L772) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`, `database_compact`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_destroy` | `depth 1` (from `offset_map_destroy`) | 3 | [`xitdb/compact_replicate.odin#L26-L28`](../../xitdb/compact_replicate.odin#L26-L28) |
| `xitdb/compact_replicate.odin` | `offset_map_reset` | `depth 1` (from `database_compact`) | 13 | [`xitdb/compact_replicate.odin#L49-L61`](../../xitdb/compact_replicate.odin#L49-L61) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_compact`, `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/types.odin` | `slot_empty` | `depth 1` (from `database_compact`, `cursor_read_path_slot`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `database_compact`) | 15 | [`xitdb/cursor.odin#L81-L95`](../../xitdb/cursor.odin#L81-L95) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `_exec_path_part`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `cursor_resolved`, `database_read_root_slot`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `cursor_write_path`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 2` (from `offset_map_reset`) | 5 | [`xitdb/cursor.odin#L185-L189`](../../xitdb/cursor.odin#L185-L189) |
| `xitdb/collections.odin` | `write_hash_map_init` | `depth 2` (from `offset_map_reset`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_insert`, `btree_write_node`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L345-L383`](../../xitdb/hamt.odin#L345-L383) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1397-L1450`](../../xitdb/database.odin#L1397-L1450) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1384-L1395`](../../xitdb/database.odin#L1384-L1395) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_encode_writeable_data`, `_try_encode_inline_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `btree_insert` | `depth 4` (from `_exec_path_part`) | 244 | [`xitdb/btree.odin#L183-L426`](../../xitdb/btree.odin#L183-L426) |
| `xitdb/btree.odin` | `btree_grow_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L428-L430`](../../xitdb/btree.odin#L428-L430) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1107-L1111`](../../xitdb/btree.odin#L1107-L1111) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1654-L2027`](../../xitdb/btree.odin#L1654-L2027) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2179-L2190`](../../xitdb/btree.odin#L2179-L2190) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 3` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `sorted_get`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`, `btree_write_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`, `btree_insert`, `sorted_put`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`, `read_array_list_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `sorted_get`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `btree_insert`, `sorted_put`, `btree_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_insert`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 5` (from `btree_insert`) | 7 | [`xitdb/btree.odin#L91-L97`](../../xitdb/btree.odin#L91-L97) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_insert`) | 10 | [`xitdb/types.odin#L1243-L1252`](../../xitdb/types.odin#L1243-L1252) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_grow_root`) | 11 | [`xitdb/btree.odin#L768-L778`](../../xitdb/btree.odin#L768-L778) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1067-L1105`](../../xitdb/btree.odin#L1067-L1105) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1591-L1597`](../../xitdb/btree.odin#L1591-L1597) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1121-L1127`](../../xitdb/btree.odin#L1121-L1127) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1143-L1148`](../../xitdb/btree.odin#L1143-L1148) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1599-L1652`](../../xitdb/btree.odin#L1599-L1652) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1113-L1119`](../../xitdb/btree.odin#L1113-L1119) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1293-L1302`](../../xitdb/types.odin#L1293-L1302) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1028-L1065`](../../xitdb/btree.odin#L1028-L1065) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1213-L1229`](../../xitdb/btree.odin#L1213-L1229) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1232-L1245`](../../xitdb/btree.odin#L1232-L1245) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`, `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1149-L1183`](../../xitdb/types.odin#L1149-L1183) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1130-L1139`](../../xitdb/types.odin#L1130-L1139) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Compaction (Heterogeneous DAG + dedup)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/btree.odin` (24 procedures · 1128 lines: [`L8–L41`](../../xitdb/btree.odin#L8-L41), [`L43–L75`](../../xitdb/btree.odin#L43-L75), [`L77–L81`](../../xitdb/btree.odin#L77-L81), [`L83–L89`](../../xitdb/btree.odin#L83-L89), [`L91–L97`](../../xitdb/btree.odin#L91-L97), [`L183–L426`](../../xitdb/btree.odin#L183-L426), [`L428–L430`](../../xitdb/btree.odin#L428-L430), [`L768–L778`](../../xitdb/btree.odin#L768-L778), [`L1028–L1065`](../../xitdb/btree.odin#L1028-L1065), [`L1067–L1105`](../../xitdb/btree.odin#L1067-L1105), [`L1107–L1111`](../../xitdb/btree.odin#L1107-L1111), [`L1113–L1119`](../../xitdb/btree.odin#L1113-L1119), [`L1121–L1127`](../../xitdb/btree.odin#L1121-L1127), [`L1129–L1141`](../../xitdb/btree.odin#L1129-L1141), [`L1143–L1148`](../../xitdb/btree.odin#L1143-L1148), [`L1150–L1209`](../../xitdb/btree.odin#L1150-L1209), [`L1213–L1229`](../../xitdb/btree.odin#L1213-L1229), [`L1232–L1245`](../../xitdb/btree.odin#L1232-L1245), [`L1247–L1359`](../../xitdb/btree.odin#L1247-L1359), [`L1591–L1597`](../../xitdb/btree.odin#L1591-L1597), [`L1599–L1652`](../../xitdb/btree.odin#L1599-L1652), [`L1654–L2027`](../../xitdb/btree.odin#L1654-L2027), [`L2179–L2190`](../../xitdb/btree.odin#L2179-L2190), [`L2192–L2209`](../../xitdb/btree.odin#L2192-L2209))

#### [`read_btree_node`](../../xitdb/btree.odin#L8-L41) — `DEPTH 5` (`L8–L41`)

```odin
   8 | read_btree_node :: proc(db: ^Database, ptr: i64) -> (res: BTree_Node, err: Error) {
   9 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
  10 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
  11 | 	core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
  12 | 	kind_int := header_bytes[0]
  13 | 	if kind_int > u8(BTree_Node_Kind.Branch) {
  14 | 		return {}, .Invalid_BTree_Node_Kind
  15 | 	}
  16 | 	kind := BTree_Node_Kind(kind_int)
  17 | 	num := int(header_bytes[1])
  18 | 	if num > BTREE_SLOT_COUNT {
  19 | 		return {}, .Invalid_BTree_Node
  20 | 	}
  21 | 	node := BTree_Node{kind = kind, num = num}
  22 | 	switch kind {
  23 | 	case .Leaf:
  24 | 		body: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
  25 | 		core_read_exact(db.core, body[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
  26 | 		for i in 0 ..< num {
  27 | 			node.values[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  28 | 		}
  29 | 	case .Branch:
  30 | 		body: [(SLOT_LENGTH + 8) * BTREE_SLOT_COUNT]u8 = ---
  31 | 		core_read_exact(db.core, body[:SLOT_LENGTH * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
  32 | 		for i in 0 ..< num {
  33 | 			node.children[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  34 | 		}
  35 | 		counts_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
  36 | 		for i in 0 ..< num {
  37 | 			node.counts[i] = i64(endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + i * 8 + 8]))
  38 | 		}
  39 | 	}
  40 | 	return node, nil
  41 | }
```

#### [`write_btree_node_at`](../../xitdb/btree.odin#L43-L75) — `DEPTH 5` (`L43–L75`)

```odin
  43 | write_btree_node_at :: proc(db: ^Database, node: BTree_Node, ptr: i64) -> Error {
  44 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
  45 | 	switch node.kind {
  46 | 	case .Leaf:
  47 | 		buf: [BTREE_LEAF_BLOCK_SIZE]u8
  48 | 		buf[0] = u8(node.kind)
  49 | 		buf[1] = u8(node.num)
  50 | 		off := BTREE_NODE_HEADER_SIZE
  51 | 		for i in 0 ..< node.num {
  52 | 			sb := slot_to_bytes(node.values[i])  // <== [calls slot_to_bytes]
  53 | 			copy(buf[off:], sb[:])
  54 | 			off += SLOT_LENGTH
  55 | 		}
  56 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
  57 | 	case .Branch:
  58 | 		buf: [BTREE_BRANCH_BLOCK_SIZE]u8
  59 | 		buf[0] = u8(node.kind)
  60 | 		buf[1] = u8(node.num)
  61 | 		off := BTREE_NODE_HEADER_SIZE
  62 | 		for i in 0 ..< node.num {
  63 | 			sb := slot_to_bytes(node.children[i])  // <== [calls slot_to_bytes]
  64 | 			copy(buf[off:], sb[:])
  65 | 			off += SLOT_LENGTH
  66 | 		}
  67 | 		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
  68 | 		for i in 0 ..< node.num {
  69 | 			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
  70 | 			counts_off += 8
  71 | 		}
  72 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
  73 | 	}
  74 | 	return .Unreachable
  75 | }
```

#### [`write_btree_node`](../../xitdb/btree.odin#L77-L81) — `DEPTH 4` (`L77–L81`)

```odin
  77 | write_btree_node :: proc(db: ^Database, node: BTree_Node) -> (res: i64, err: Error) {
  78 | 	ptr := core_length(db.core) or_return  // <== [calls core_length]
  79 | 	write_btree_node_at(db, node, ptr) or_return  // <== [calls write_btree_node_at]
  80 | 	return ptr, nil
  81 | }
```

#### [`btree_reusable`](../../xitdb/btree.odin#L83-L89) — `DEPTH 5` (`L83–L89`)

```odin
  83 | btree_reusable :: proc(db: ^Database, ptr, frozen_at: i64) -> bool {
  84 | 	old, err := database_is_old(db, ptr, frozen_at)  // <== [calls database_is_old]
  85 | 	if err != nil {
  86 | 		return false
  87 | 	}
  88 | 	return !old
  89 | }
```

#### [`btree_write_node`](../../xitdb/btree.odin#L91-L97) — `DEPTH 5` (`L91–L97`)

```odin
  91 | btree_write_node :: proc(db: ^Database, node: BTree_Node, old_ptr, frozen_at: i64) -> (res: i64, err: Error) {
  92 | 	if btree_reusable(db, old_ptr, frozen_at) {  // <== [calls btree_reusable]
  93 | 		write_btree_node_at(db, node, old_ptr) or_return  // <== [calls write_btree_node_at]
  94 | 		return old_ptr, nil
  95 | 	}
  96 | 	return write_btree_node(db, node)  // <== [calls write_btree_node]
  97 | }
```

#### [`btree_insert`](../../xitdb/btree.odin#L183-L426) — `DEPTH 4` (`L183–L426`)

```odin
 183 | btree_insert :: proc(db: ^Database, node_ptr, rank, frozen_at: i64) -> (res: BTree_Insert_Result, err: Error) {
 184 | 	if btree_reusable(db, node_ptr, frozen_at) {  // <== [calls btree_reusable]
 185 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
 186 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8
 187 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 188 | 		kind_int := header_bytes[0]
 189 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
 190 | 			return {}, .Invalid_BTree_Node_Kind
 191 | 		}
 192 | 		num := int(header_bytes[1])
 193 | 		if num > BTREE_SLOT_COUNT {
 194 | 			return {}, .Invalid_BTree_Node
 195 | 		}
 196 | 		if BTree_Node_Kind(kind_int) == .Leaf {
 197 | 			if num < BTREE_SLOT_COUNT {
 198 | 				r := int(rank)
 199 | 				total := num + 1
 200 | 				val_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH
 201 | 				empty_slot_bytes := slot_to_bytes(Slot{value = 0, tag = .None, full = true})  // <== [calls slot_to_bytes]
 202 | 				if r < num {
 203 | 					tail_len := (num - r) * SLOT_LENGTH
 204 | 					shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8
 205 | 					copy(shift_buf[:SLOT_LENGTH], empty_slot_bytes[:])
 206 | 					core_seek_to(db.core, val_pos) or_return  // <== [calls core_seek_to]
 207 | 					core_read_exact(db.core, shift_buf[SLOT_LENGTH : SLOT_LENGTH + tail_len]) or_return  // <== [calls core_read_exact]
 208 | 					core_seek_to(db.core, val_pos) or_return  // <== [calls core_seek_to]
 209 | 					core_write_all(db.core, shift_buf[:SLOT_LENGTH + tail_len]) or_return  // <== [calls core_write_all]
 210 | 				} else {
 211 | 					core_seek_to(db.core, val_pos) or_return  // <== [calls core_seek_to]
 212 | 					core_write_all(db.core, empty_slot_bytes[:]) or_return  // <== [calls core_write_all]
 213 | 				}
 214 | 				new_hdr := [BTREE_NODE_HEADER_SIZE]u8{header_bytes[0], u8(total)}
 215 | 				core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
 216 | 				core_write_all(db.core, new_hdr[:]) or_return  // <== [calls core_write_all]
 217 | 				return BTree_Insert_Result{
 218 | 					node_ptr       = node_ptr,
 219 | 					count          = i64(total),
 220 | 					value_position = val_pos,
 221 | 				}, nil
 222 | 			}
 223 | 		} else {
 224 | 			counts_pos := node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
 225 | 			core_seek_to(db.core, counts_pos) or_return  // <== [calls core_seek_to]
 226 | 			counts_buf: [8 * BTREE_SLOT_COUNT]u8
 227 | 			core_read_exact(db.core, counts_buf[:num * 8]) or_return  // <== [calls core_read_exact]
 228 | 			i := 0
 229 | 			rem := rank
 230 | 			total_count: i64 = 0
 231 | 			old_cnt_i: i64 = 0
 232 | 			for k in 0 ..< num {
 233 | 				cnt := i64(endian.unchecked_get_u64be(counts_buf[k * 8 : k * 8 + 8]))
 234 | 				total_count += cnt
 235 | 				if k == i {
 236 | 					old_cnt_i = cnt
 237 | 					if i + 1 < num && rem > cnt {
 238 | 						rem -= cnt
 239 | 						i += 1
 240 | 					}
 241 | 				}
 242 | 			}
 243 | 			child_slot_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
 244 | 			core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
 245 | 			child_slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 246 | 			child_ptr := child_slot.value
 247 | 			child := btree_insert(db, child_ptr, rem, frozen_at) or_return
 248 | 			if child.split == nil {
 249 | 				if child.node_ptr != child_ptr {
 250 | 					core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
 251 | 					core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 252 | 				}
 253 | 				core_seek_to(db.core, counts_pos + i64(i) * 8) or_return  // <== [calls core_seek_to]
 254 | 				core_write_i64(db.core, child.count) or_return  // <== [calls core_write_i64]
 255 | 				return BTree_Insert_Result{
 256 | 					node_ptr       = node_ptr,
 257 | 					count          = total_count - old_cnt_i + child.count,
 258 | 					value_position = child.value_position,
 259 | 				}, nil
 260 | 			}
 261 | 			// Child split: read full branch node and finish split handling
 262 | 			node := read_btree_node(db, node_ptr) or_return  // <== [calls read_btree_node]
 263 | 			children: [BTREE_SLOT_COUNT + 1]Slot
 264 | 			counts: [BTREE_SLOT_COUNT + 1]i64
 265 | 			copy(children[:node.num], node.children[:node.num])
 266 | 			copy(counts[:node.num], node.counts[:node.num])
 267 | 			children[i] = Slot{value = child.node_ptr, tag = .Index}
 268 | 			counts[i] = child.count
 269 | 			split := child.split.?
 270 | 			for j := node.num; j > i + 1; j -= 1 {
 271 | 				children[j] = children[j - 1]
 272 | 				counts[j] = counts[j - 1]
 273 | 			}
 274 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
 275 | 			counts[i + 1] = split.count
 276 | 			total := node.num + 1
 277 | 
 278 | 			if total <= BTREE_SLOT_COUNT {
 279 | 				branch := BTree_Node{kind = .Branch, num = total}
 280 | 				copy(branch.children[:total], children[:total])
 281 | 				copy(branch.counts[:total], counts[:total])
 282 | 				ptr := btree_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 283 | 				return BTree_Insert_Result{
 284 | 					node_ptr       = ptr,
 285 | 					count          = btree_node_subtree_count(branch),  // <== [calls btree_node_subtree_count]
 286 | 					value_position = child.value_position,
 287 | 				}, nil
 288 | 			}
 289 | 
 290 | 			left_n := BTREE_SPLIT_COUNT
 291 | 			right_n := total - left_n
 292 | 			left := BTree_Node{kind = .Branch, num = left_n}
 293 | 			copy(left.children[:left_n], children[:left_n])
 294 | 			copy(left.counts[:left_n], counts[:left_n])
 295 | 			right := BTree_Node{kind = .Branch, num = right_n}
 296 | 			copy(right.children[:right_n], children[left_n:total])
 297 | 			copy(right.counts[:right_n], counts[left_n:total])
 298 | 			left_ptr := btree_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 299 | 			right_ptr := write_btree_node(db, right) or_return  // <== [calls write_btree_node]
 300 | 			return BTree_Insert_Result{
 301 | 				node_ptr       = left_ptr,
 302 | 				count          = btree_node_subtree_count(left),  // <== [calls btree_node_subtree_count]
 303 | 				value_position = child.value_position,
 304 | 				split          = BTree_Node_Ref{node_ptr = right_ptr, count = btree_node_subtree_count(right)},  // <== [calls btree_node_subtree_count]
 305 | 			}, nil
 306 | 		}
 307 | 	}
 308 | 
 309 | 	node := read_btree_node(db, node_ptr) or_return  // <== [calls read_btree_node]
 310 | 	switch node.kind {
 311 | 	case .Leaf:
 312 | 		r := int(rank)
 313 | 		vals: [BTREE_SLOT_COUNT + 1]Slot
 314 | 		copy(vals[:r], node.values[:r])
 315 | 		vals[r] = Slot{value = 0, tag = .None, full = true}
 316 | 		copy(vals[r + 1 : node.num + 1], node.values[r:node.num])
 317 | 		total := node.num + 1
 318 | 
 319 | 		if total <= BTREE_SLOT_COUNT {
 320 | 			leaf := BTree_Node{kind = .Leaf, num = total}
 321 | 			copy(leaf.values[:total], vals[:total])
 322 | 			ptr := btree_write_node(db, leaf, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 323 | 			return BTree_Insert_Result{
 324 | 				node_ptr       = ptr,
 325 | 				count          = i64(total),
 326 | 				value_position = ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH,
 327 | 			}, nil
 328 | 		}
 329 | 
 330 | 		// Overflow: split into two leaves (reuse this node for the left half)
 331 | 		left_n := BTREE_SPLIT_COUNT
 332 | 		right_n := total - left_n
 333 | 		left := BTree_Node{kind = .Leaf, num = left_n}
 334 | 		copy(left.values[:left_n], vals[:left_n])
 335 | 		right := BTree_Node{kind = .Leaf, num = right_n}
 336 | 		copy(right.values[:right_n], vals[left_n:total])
 337 | 		left_ptr := btree_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 338 | 		right_ptr := write_btree_node(db, right) or_return  // <== [calls write_btree_node]
 339 | 		value_position: i64
 340 | 		if r < left_n {
 341 | 			value_position = left_ptr + BTREE_NODE_HEADER_SIZE + i64(r) * SLOT_LENGTH
 342 | 		} else {
 343 | 			value_position = right_ptr + BTREE_NODE_HEADER_SIZE + i64(r - left_n) * SLOT_LENGTH
 344 | 		}
 345 | 		return BTree_Insert_Result{
 346 | 			node_ptr       = left_ptr,
 347 | 			count          = i64(left_n),
 348 | 			value_position = value_position,
 349 | 			split          = BTree_Node_Ref{node_ptr = right_ptr, count = i64(right_n)},
 350 | 		}, nil
 351 | 
 352 | 	case .Branch:
 353 | 		i := 0
 354 | 		rem := rank
 355 | 		for i + 1 < node.num && rem > node.counts[i] {
 356 | 			rem -= node.counts[i]
 357 | 			i += 1
 358 | 		}
 359 | 		child_ptr := node.children[i].value
 360 | 		child := btree_insert(db, child_ptr, rem, frozen_at) or_return
 361 | 		if child.split == nil && btree_reusable(db, node_ptr, frozen_at) {  // <== [calls btree_reusable]
 362 | 			if child.node_ptr != child_ptr {
 363 | 				child_slot_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
 364 | 				core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
 365 | 				core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 366 | 				node.children[i] = Slot{value = child.node_ptr, tag = .Index}
 367 | 			}
 368 | 			count_pos := node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT + i64(i) * 8
 369 | 			core_seek_to(db.core, count_pos) or_return  // <== [calls core_seek_to]
 370 | 			core_write_i64(db.core, child.count) or_return  // <== [calls core_write_i64]
 371 | 			node.counts[i] = child.count
 372 | 			return BTree_Insert_Result{
 373 | 				node_ptr       = node_ptr,
 374 | 				count          = btree_node_subtree_count(node),  // <== [calls btree_node_subtree_count]
 375 | 				value_position = child.value_position,
 376 | 			}, nil
 377 | 		}
 378 | 
 379 | 		children: [BTREE_SLOT_COUNT + 1]Slot
 380 | 		counts: [BTREE_SLOT_COUNT + 1]i64
 381 | 		copy(children[:node.num], node.children[:node.num])
 382 | 		copy(counts[:node.num], node.counts[:node.num])
 383 | 		children[i] = Slot{value = child.node_ptr, tag = .Index}
 384 | 		counts[i] = child.count
 385 | 		total := node.num
 386 | 		if split, ok := child.split.?; ok {
 387 | 			for j := node.num; j > i + 1; j -= 1 {
 388 | 				children[j] = children[j - 1]
 389 | 				counts[j] = counts[j - 1]
 390 | 			}
 391 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
 392 | 			counts[i + 1] = split.count
 393 | 			total = node.num + 1
 394 | 		}
 395 | 
 396 | 		if total <= BTREE_SLOT_COUNT {
 397 | 			branch := BTree_Node{kind = .Branch, num = total}
 398 | 			copy(branch.children[:total], children[:total])
 399 | 			copy(branch.counts[:total], counts[:total])
 400 | 			ptr := btree_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 401 | 			return BTree_Insert_Result{
 402 | 				node_ptr       = ptr,
 403 | 				count          = btree_node_subtree_count(branch),  // <== [calls btree_node_subtree_count]
 404 | 				value_position = child.value_position,
 405 | 			}, nil
 406 | 		}
 407 | 
 408 | 		left_n := BTREE_SPLIT_COUNT
 409 | 		right_n := total - left_n
 410 | 		left := BTree_Node{kind = .Branch, num = left_n}
 411 | 		copy(left.children[:left_n], children[:left_n])
 412 | 		copy(left.counts[:left_n], counts[:left_n])
 413 | 		right := BTree_Node{kind = .Branch, num = right_n}
 414 | 		copy(right.children[:right_n], children[left_n:total])
 415 | 		copy(right.counts[:right_n], counts[left_n:total])
 416 | 		left_ptr := btree_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls btree_write_node]
 417 | 		right_ptr := write_btree_node(db, right) or_return  // <== [calls write_btree_node]
 418 | 		return BTree_Insert_Result{
 419 | 			node_ptr       = left_ptr,
 420 | 			count          = btree_node_subtree_count(left),  // <== [calls btree_node_subtree_count]
 421 | 			value_position = child.value_position,
 422 | 			split          = BTree_Node_Ref{node_ptr = right_ptr, count = btree_node_subtree_count(right)},  // <== [calls btree_node_subtree_count]
 423 | 		}, nil
 424 | 	}
 425 | 	return {}, .Unreachable
 426 | }
```

#### [`btree_grow_root`](../../xitdb/btree.odin#L428-L430) — `DEPTH 4` (`L428–L430`)

```odin
 428 | btree_grow_root :: proc(db: ^Database, result: BTree_Insert_Result) -> (res: i64, err: Error) {
 429 | 	return btree_make_root(db, BTree_Join_Result{node_ptr = result.node_ptr, count = result.count, split = result.split})  // <== [calls btree_make_root]
 430 | }
```

#### [`btree_make_root`](../../xitdb/btree.odin#L768-L778) — `DEPTH 5` (`L768–L778`)

```odin
 768 | btree_make_root :: proc(db: ^Database, result: BTree_Join_Result) -> (res: i64, err: Error) {
 769 | 	if split, ok := result.split.?; ok {
 770 | 		root := BTree_Node{kind = .Branch, num = 2}
 771 | 		root.children[0] = Slot{value = result.node_ptr, tag = .Index}
 772 | 		root.children[1] = Slot{value = split.node_ptr, tag = .Index}
 773 | 		root.counts[0] = result.count
 774 | 		root.counts[1] = split.count
 775 | 		return write_btree_node(db, root)  // <== [calls write_btree_node]
 776 | 	}
 777 | 	return result.node_ptr, nil
 778 | }
```

#### [`read_sorted_node`](../../xitdb/btree.odin#L1028-L1065) — `DEPTH 5` (`L1028–L1065`)

```odin
1028 | read_sorted_node :: proc(db: ^Database, ptr: i64) -> (res: Sorted_Node, err: Error) {
1029 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
1030 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1031 | 	core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1032 | 	kind_int := header_bytes[0]
1033 | 	if kind_int > u8(BTree_Node_Kind.Branch) {
1034 | 		return {}, .Invalid_BTree_Node_Kind
1035 | 	}
1036 | 	kind := BTree_Node_Kind(kind_int)
1037 | 	num := int(header_bytes[1])
1038 | 	if num > BTREE_SLOT_COUNT {
1039 | 		return {}, .Invalid_BTree_Node
1040 | 	}
1041 | 	node := Sorted_Node{kind = kind, num = num}
1042 | 	switch kind {
1043 | 	case .Leaf:
1044 | 		body: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1045 | 		core_read_exact(db.core, body[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1046 | 		for i in 0 ..< num {
1047 | 			node.entries[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1048 | 		}
1049 | 	case .Branch:
1050 | 		body: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
1051 | 		core_read_exact(db.core, body[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
1052 | 		for i in 0 ..< num {
1053 | 			node.children[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1054 | 		}
1055 | 		sep_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
1056 | 		for i in 0 ..< num {
1057 | 			node.separators[i] = slot_from_slice_raw(body[sep_offset + i * SLOT_LENGTH : sep_offset + i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1058 | 		}
1059 | 		counts_offset := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1060 | 		for i in 0 ..< num {
1061 | 			node.counts[i] = i64(endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + i * 8 + 8]))
1062 | 		}
1063 | 	}
1064 | 	return node, nil
1065 | }
```

#### [`write_sorted_node_at`](../../xitdb/btree.odin#L1067-L1105) — `DEPTH 5` (`L1067–L1105`)

```odin
1067 | write_sorted_node_at :: proc(db: ^Database, node: Sorted_Node, ptr: i64) -> Error {
1068 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
1069 | 	switch node.kind {
1070 | 	case .Leaf:
1071 | 		buf: [SORTED_LEAF_BLOCK_SIZE]u8
1072 | 		buf[0] = u8(node.kind)
1073 | 		buf[1] = u8(node.num)
1074 | 		off := BTREE_NODE_HEADER_SIZE
1075 | 		for i in 0 ..< node.num {
1076 | 			sb := slot_to_bytes(node.entries[i])  // <== [calls slot_to_bytes]
1077 | 			copy(buf[off:], sb[:])
1078 | 			off += SLOT_LENGTH
1079 | 		}
1080 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
1081 | 	case .Branch:
1082 | 		buf: [SORTED_BRANCH_BLOCK_SIZE]u8
1083 | 		buf[0] = u8(node.kind)
1084 | 		buf[1] = u8(node.num)
1085 | 		off := BTREE_NODE_HEADER_SIZE
1086 | 		for i in 0 ..< node.num {
1087 | 			sb := slot_to_bytes(node.children[i])  // <== [calls slot_to_bytes]
1088 | 			copy(buf[off:], sb[:])
1089 | 			off += SLOT_LENGTH
1090 | 		}
1091 | 		sep_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
1092 | 		for i in 0 ..< node.num {
1093 | 			sb := slot_to_bytes(node.separators[i])  // <== [calls slot_to_bytes]
1094 | 			copy(buf[sep_off:], sb[:])
1095 | 			sep_off += SLOT_LENGTH
1096 | 		}
1097 | 		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1098 | 		for i in 0 ..< node.num {
1099 | 			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
1100 | 			counts_off += 8
1101 | 		}
1102 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
1103 | 	}
1104 | 	return .Unreachable
1105 | }
```

#### [`write_sorted_node`](../../xitdb/btree.odin#L1107-L1111) — `DEPTH 4` (`L1107–L1111`)

```odin
1107 | write_sorted_node :: proc(db: ^Database, node: Sorted_Node) -> (res: i64, err: Error) {
1108 | 	ptr := core_length(db.core) or_return  // <== [calls core_length]
1109 | 	write_sorted_node_at(db, node, ptr) or_return  // <== [calls write_sorted_node_at]
1110 | 	return ptr, nil
1111 | }
```

#### [`sorted_write_node`](../../xitdb/btree.odin#L1113-L1119) — `DEPTH 5` (`L1113–L1119`)

```odin
1113 | sorted_write_node :: proc(db: ^Database, node: Sorted_Node, old_ptr, frozen_at: i64) -> (res: i64, err: Error) {
1114 | 	if btree_reusable(db, old_ptr, frozen_at) {  // <== [calls btree_reusable]
1115 | 		write_sorted_node_at(db, node, old_ptr) or_return  // <== [calls write_sorted_node_at]
1116 | 		return old_ptr, nil
1117 | 	}
1118 | 	return write_sorted_node(db, node)  // <== [calls write_sorted_node]
1119 | }
```

#### [`read_kv_pair`](../../xitdb/btree.odin#L1121-L1127) — `DEPTH 5` (`L1121–L1127`)

```odin
1121 | read_kv_pair :: proc(db: ^Database, entry: Slot) -> (res: Key_Value_Pair, err: Error) {
1122 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1123 | 		return Key_Value_Pair{value_slot = Slot{}, key_slot = entry, hash = nil}, nil
1124 | 	}
1125 | 	core_seek_to(db.core, entry.value) or_return  // <== [calls core_seek_to]
1126 | 	return decode_kv_pair(db.core, entry.tag, 0, context.temp_allocator)  // <== [calls decode_kv_pair]
1127 | }
```

#### [`sorted_entry_key_slot`](../../xitdb/btree.odin#L1129-L1141) — `DEPTH 5` (`L1129–L1141`)

```odin
1129 | sorted_entry_key_slot :: #force_inline proc(db: ^Database, entry: Slot) -> (res: Slot, err: Error) {
1130 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1131 | 		return entry, nil
1132 | 	}
1133 | 	if s_slice, in_mem, slice_err := core_slice_at(db.core, entry.value, SLOT_LENGTH); in_mem {  // <== [calls core_slice_at]
1134 | 		if slice_err != nil {
1135 | 			return {}, slice_err
1136 | 		}
1137 | 		return slot_from_slice_raw(s_slice), nil  // <== [calls slot_from_slice_raw]
1138 | 	}
1139 | 	core_seek_to(db.core, entry.value) or_return  // <== [calls core_seek_to]
1140 | 	return core_read_slot_raw(db.core)  // <== [calls core_read_slot_raw]
1141 | }
```

#### [`write_kv_pair`](../../xitdb/btree.odin#L1143-L1148) — `DEPTH 5` (`L1143–L1148`)

```odin
1143 | write_kv_pair :: proc(db: ^Database, tag: Tag, kv_pair: Key_Value_Pair) -> (res: Slot, err: Error) {
1144 | 	pos := core_length(db.core) or_return  // <== [calls core_length]
1145 | 	core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
1146 | 	encode_kv_pair(db.core, tag, kv_pair) or_return  // <== [calls encode_kv_pair]
1147 | 	return Slot{value = pos, tag = tag}, nil
1148 | }
```

#### [`compare_key`](../../xitdb/btree.odin#L1150-L1209) — `DEPTH 5` (`L1150–L1209`)

```odin
1150 | compare_key :: proc(db: ^Database, key_slot: Slot, target: []u8) -> (res: int, err: Error) {
1151 | 	#partial switch key_slot.tag {
1152 | 	case .Short_Bytes:
1153 | 		buf: [8]u8 = ---
1154 | 		endian.unchecked_put_u64be(buf[:], u64(key_slot.value))
1155 | 		total := 6 if key_slot.full else 8
1156 | 		length := total
1157 | 		for i in 0 ..< total {
1158 | 			if buf[i] == 0 {
1159 | 				length = i
1160 | 				break
1161 | 			}
1162 | 		}
1163 | 		return bytes.compare(buf[:length], target), nil
1164 | 	case .Bytes:
1165 | 		#partial switch &v in db.core {
1166 | 		case Core_Memory:
1167 | 			pos := int(key_slot.value)
1168 | 			if pos < 0 || pos + 8 > len(v.buf) {
1169 | 				return 0, Xitdb_Error.Unexpected_EOF
1170 | 			}
1171 | 			length := int(endian.unchecked_get_u64be(v.buf[pos : pos + 8]))
1172 | 			if length < 0 || pos + 8 + length > len(v.buf) {
1173 | 				return 0, Xitdb_Error.Unexpected_EOF
1174 | 			}
1175 | 			return bytes.compare(v.buf[pos + 8 : pos + 8 + length], target), nil
1176 | 		case Core_Buffered_File:
1177 | 			buf_len := i64(len(v.memory.buf))
1178 | 			if buf_len > 0 && key_slot.value >= v.memory_pos && key_slot.value + 8 <= v.memory_pos + buf_len {
1179 | 				mem_off := int(key_slot.value - v.memory_pos)
1180 | 				length := int(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
1181 | 				if length >= 0 && mem_off + 8 + length <= int(buf_len) {
1182 | 					return bytes.compare(v.memory.buf[mem_off + 8 : mem_off + 8 + length], target), nil
1183 | 				}
1184 | 			}
1185 | 		}
1186 | 		core_seek_to(db.core, key_slot.value) or_return  // <== [calls core_seek_to]
1187 | 		length := core_read_i64(db.core) or_return  // <== [calls core_read_i64]
1188 | 		read_len := min(int(length), len(target))
1189 | 		if read_len <= 256 {
1190 | 			stack_buf: [256]u8 = ---
1191 | 			key_bytes := stack_buf[:read_len]
1192 | 			core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1193 | 			c := bytes.compare(key_bytes, target[:read_len])
1194 | 			if c != 0 {
1195 | 				return c, nil
1196 | 			}
1197 | 			return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1198 | 		}
1199 | 		key_bytes := make([]u8, read_len, context.temp_allocator)
1200 | 		core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1201 | 		c := bytes.compare(key_bytes, target[:read_len])
1202 | 		if c != 0 {
1203 | 			return c, nil
1204 | 		}
1205 | 		return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1206 | 	case:
1207 | 		return 0, .Unexpected_Tag
1208 | 	}
1209 | }
```

#### [`sorted_leaf_search`](../../xitdb/btree.odin#L1213-L1229) — `DEPTH 5` (`L1213–L1229`)

```odin
1213 | sorted_leaf_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, found: bool, err: Error) {
1214 | 	lo := 0
1215 | 	hi := node.num
1216 | 	for lo < hi {
1217 | 		mid := int(uint(lo + hi) >> 1)
1218 | 		key_slot := sorted_entry_key_slot(db, node.entries[mid]) or_return  // <== [calls sorted_entry_key_slot]
1219 | 		cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1220 | 		if cmp == 0 {
1221 | 			return mid, true, nil
1222 | 		} else if cmp < 0 {
1223 | 			lo = mid + 1
1224 | 		} else {
1225 | 			hi = mid
1226 | 		}
1227 | 	}
1228 | 	return lo, false, nil
1229 | }
```

#### [`sorted_branch_search`](../../xitdb/btree.odin#L1232-L1245) — `DEPTH 5` (`L1232–L1245`)

```odin
1232 | sorted_branch_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, err: Error) {
1233 | 	lo := 1
1234 | 	hi := node.num
1235 | 	for lo < hi {
1236 | 		mid := int(uint(lo + hi) >> 1)
1237 | 		c := compare_key(db, node.separators[mid], key) or_return  // <== [calls compare_key]
1238 | 		if c <= 0 {
1239 | 			lo = mid + 1
1240 | 		} else {
1241 | 			hi = mid
1242 | 		}
1243 | 	}
1244 | 	return lo - 1, nil
1245 | }
```

#### [`sorted_get`](../../xitdb/btree.odin#L1247-L1359) — `DEPTH 4` (`L1247–L1359`)

```odin
1247 | sorted_get :: proc(db: ^Database, root_ptr: i64, key: []u8) -> (res: Maybe(Sorted_Slot), err: Error) {
1248 | 	node_ptr := root_ptr
1249 | 	for {
1250 | 		if hdr_slice, in_mem, slice_err := core_slice_at(db.core, node_ptr, BTREE_NODE_HEADER_SIZE); in_mem {  // <== [calls core_slice_at]
1251 | 			if slice_err != nil {
1252 | 				return nil, slice_err
1253 | 			}
1254 | 			kind_int := hdr_slice[0]
1255 | 			if kind_int > u8(BTree_Node_Kind.Branch) {
1256 | 				return nil, .Invalid_BTree_Node_Kind
1257 | 			}
1258 | 			num := int(hdr_slice[1])
1259 | 			if num > BTREE_SLOT_COUNT {
1260 | 				return nil, .Invalid_BTree_Node
1261 | 			}
1262 | 			if BTree_Node_Kind(kind_int) == .Leaf {
1263 | 				entries_slice, _, e_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, num * SLOT_LENGTH)  // <== [calls core_slice_at]
1264 | 				if e_err != nil {
1265 | 					return nil, e_err
1266 | 				}
1267 | 				lo := 0
1268 | 				hi := num
1269 | 				for lo < hi {
1270 | 					mid := int(uint(lo + hi) >> 1)
1271 | 					entry_slot := slot_from_slice_raw(entries_slice[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1272 | 					key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1273 | 					cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1274 | 					if cmp == 0 {
1275 | 						entry_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(mid) * SLOT_LENGTH
1276 | 						return Sorted_Slot{slot = entry_slot, key_slot = key_slot, position = entry_pos}, nil
1277 | 					} else if cmp < 0 {
1278 | 						lo = mid + 1
1279 | 					} else {
1280 | 						hi = mid
1281 | 					}
1282 | 				}
1283 | 				return nil, nil
1284 | 			}
1285 | 			branch_slice, _, b_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, (BTREE_SLOT_COUNT + num) * SLOT_LENGTH)  // <== [calls core_slice_at]
1286 | 			if b_err != nil {
1287 | 				return nil, b_err
1288 | 			}
1289 | 			lo := 1
1290 | 			hi := num
1291 | 			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1292 | 			for lo < hi {
1293 | 				mid := int(uint(lo + hi) >> 1)
1294 | 				sep_slot := slot_from_slice_raw(branch_slice[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1295 | 				c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1296 | 				if c <= 0 {
1297 | 					lo = mid + 1
1298 | 				} else {
1299 | 					hi = mid
1300 | 				}
1301 | 			}
1302 | 			child_idx := lo - 1
1303 | 			node_ptr = slot_from_slice_raw(branch_slice[child_idx * SLOT_LENGTH : (child_idx + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1304 | 			continue
1305 | 		}
1306 | 
1307 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1308 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1309 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1310 | 		kind_int := header_bytes[0]
1311 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1312 | 			return nil, .Invalid_BTree_Node_Kind
1313 | 		}
1314 | 		num := int(header_bytes[1])
1315 | 		if num > BTREE_SLOT_COUNT {
1316 | 			return nil, .Invalid_BTree_Node
1317 | 		}
1318 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1319 | 			entries_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1320 | 			if num > 0 {
1321 | 				core_read_exact(db.core, entries_buf[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1322 | 			}
1323 | 			lo := 0
1324 | 			hi := num
1325 | 			for lo < hi {
1326 | 				mid := int(uint(lo + hi) >> 1)
1327 | 				entry_slot := slot_from_slice_raw(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1328 | 				key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1329 | 				cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1330 | 				if cmp == 0 {
1331 | 					entry_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(mid) * SLOT_LENGTH
1332 | 					return Sorted_Slot{slot = entry_slot, key_slot = key_slot, position = entry_pos}, nil
1333 | 				} else if cmp < 0 {
1334 | 					lo = mid + 1
1335 | 				} else {
1336 | 					hi = mid
1337 | 				}
1338 | 			}
1339 | 			return nil, nil
1340 | 		}
1341 | 		branch_buf: [SLOT_LENGTH * 2 * BTREE_SLOT_COUNT]u8 = ---
1342 | 		core_read_exact(db.core, branch_buf[:(BTREE_SLOT_COUNT + num) * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1343 | 		lo := 1
1344 | 		hi := num
1345 | 		sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1346 | 		for lo < hi {
1347 | 			mid := int(uint(lo + hi) >> 1)
1348 | 			sep_slot := slot_from_slice_raw(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1349 | 			c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1350 | 			if c <= 0 {
1351 | 				lo = mid + 1
1352 | 			} else {
1353 | 				hi = mid
1354 | 			}
1355 | 		}
1356 | 		child_idx := lo - 1
1357 | 		node_ptr = slot_from_slice_raw(branch_buf[child_idx * SLOT_LENGTH : (child_idx + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1358 | 	}
1359 | }
```

#### [`write_sorted_pair`](../../xitdb/btree.odin#L1591-L1597) — `DEPTH 5` (`L1591–L1597`)

```odin
1591 | write_sorted_pair :: proc(db: ^Database, key_slot: Slot) -> (res: Slot, err: Error) {
1592 | 	return write_kv_pair(db, .Sorted_KV_Pair, Key_Value_Pair{  // <== [calls write_kv_pair]
1593 | 		value_slot = Slot{},
1594 | 		key_slot   = key_slot,
1595 | 		hash       = nil,
1596 | 	})
1597 | }
```

#### [`write_sorted_key_and_entry`](../../xitdb/btree.odin#L1599-L1652) — `DEPTH 5` (`L1599–L1652`)

```odin
1599 | write_sorted_key_and_entry :: proc(db: ^Database, key: []u8, key_only: bool) -> (key_slot: Slot, entry: Slot, err: Error) {
1600 | 	if len(key) <= 8 {
1601 | 		has_zero := false
1602 | 		for b in key {
1603 | 			if b == 0 {
1604 | 				has_zero = true
1605 | 				break
1606 | 			}
1607 | 		}
1608 | 		if !has_zero {
1609 | 			value: [8]u8
1610 | 			copy(value[:], key)
1611 | 			key_slot = Slot{value = i64(endian.unchecked_get_u64be(value[:])), tag = .Short_Bytes}
1612 | 			if key_only {
1613 | 				return key_slot, key_slot, nil
1614 | 			}
1615 | 			entry = write_sorted_pair(db, key_slot) or_return  // <== [calls write_sorted_pair]
1616 | 			return key_slot, entry, nil
1617 | 		}
1618 | 	}
1619 | 	pos := core_length(db.core) or_return  // <== [calls core_length]
1620 | 	core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
1621 | 	key_slot = Slot{value = pos, tag = .Bytes}
1622 | 	if key_only {
1623 | 		if len(key) <= 248 {
1624 | 			buf: [256]u8 = ---
1625 | 			endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
1626 | 			copy(buf[8:8 + len(key)], key)
1627 | 			core_write_all(db.core, buf[:8 + len(key)]) or_return  // <== [calls core_write_all]
1628 | 			return key_slot, key_slot, nil
1629 | 		}
1630 | 		core_write_i64(db.core, i64(len(key))) or_return  // <== [calls core_write_i64]
1631 | 		core_write_all(db.core, key) or_return  // <== [calls core_write_all]
1632 | 		return key_slot, key_slot, nil
1633 | 	}
1634 | 	pair_pos := pos + 8 + i64(len(key))
1635 | 	entry = Slot{value = pair_pos, tag = .Sorted_KV_Pair}
1636 | 	if len(key) <= 230 {
1637 | 		buf: [256]u8 = ---
1638 | 		endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
1639 | 		copy(buf[8 : 8 + len(key)], key)
1640 | 		ks_bytes := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1641 | 		vs_bytes := slot_to_bytes(Slot{})  // <== [calls slot_to_bytes]
1642 | 		pair_off := 8 + len(key)
1643 | 		copy(buf[pair_off : pair_off + SLOT_LENGTH], ks_bytes[:])
1644 | 		copy(buf[pair_off + SLOT_LENGTH : pair_off + SORTED_KV_PAIR_LENGTH], vs_bytes[:])
1645 | 		core_write_all(db.core, buf[:pair_off + SORTED_KV_PAIR_LENGTH]) or_return  // <== [calls core_write_all]
1646 | 		return key_slot, entry, nil
1647 | 	}
1648 | 	core_write_i64(db.core, i64(len(key))) or_return  // <== [calls core_write_i64]
1649 | 	core_write_all(db.core, key) or_return  // <== [calls core_write_all]
1650 | 	entry = write_sorted_pair(db, key_slot) or_return  // <== [calls write_sorted_pair]
1651 | 	return key_slot, entry, nil
1652 | }
```

#### [`sorted_put`](../../xitdb/btree.odin#L1654-L2027) — `DEPTH 4` (`L1654–L2027`)

```odin
1654 | sorted_put :: proc(db: ^Database, node_ptr: i64, key: []u8, key_only: bool, frozen_at: i64) -> (res: Sorted_Insert_Result, err: Error) {
1655 | 	reusable := btree_reusable(db, node_ptr, frozen_at)  // <== [calls btree_reusable]
1656 | 	if reusable {
1657 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1658 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8
1659 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1660 | 		kind_int := header_bytes[0]
1661 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1662 | 			return {}, .Invalid_BTree_Node_Kind
1663 | 		}
1664 | 		num := int(header_bytes[1])
1665 | 		if num > BTREE_SLOT_COUNT {
1666 | 			return {}, .Invalid_BTree_Node
1667 | 		}
1668 | 		position := node_ptr + BTREE_NODE_HEADER_SIZE
1669 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1670 | 			entries_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1671 | 			if num > 0 {
1672 | 				core_read_exact(db.core, entries_buf[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1673 | 			}
1674 | 			lo := 0
1675 | 			hi := num
1676 | 			matched_slot: Slot
1677 | 			found := false
1678 | 			for lo < hi {
1679 | 				mid := int(uint(lo + hi) >> 1)
1680 | 				entry_slot := slot_from_slice_raw(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1681 | 				key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1682 | 				cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1683 | 				if cmp == 0 {
1684 | 					lo = mid
1685 | 					matched_slot = entry_slot
1686 | 					found = true
1687 | 					break
1688 | 				} else if cmp < 0 {
1689 | 					lo = mid + 1
1690 | 				} else {
1691 | 					hi = mid
1692 | 				}
1693 | 			}
1694 | 			if found {
1695 | 				if key_only {
1696 | 					return Sorted_Insert_Result{
1697 | 						node_ptr = node_ptr,
1698 | 						count    = i64(num),
1699 | 						entry    = matched_slot,
1700 | 						added    = false,
1701 | 					}, nil
1702 | 				}
1703 | 				entry := matched_slot
1704 | 				rewritten := false
1705 | 				if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1706 | 					entry = write_sorted_pair(db, entry) or_return  // <== [calls write_sorted_pair]
1707 | 					rewritten = true
1708 | 				} else if !btree_reusable(db, entry.value, frozen_at) {  // <== [calls btree_reusable]
1709 | 					kv := read_kv_pair(db, entry) or_return  // <== [calls read_kv_pair]
1710 | 					entry = write_kv_pair(db, entry.tag, kv) or_return  // <== [calls write_kv_pair]
1711 | 					rewritten = true
1712 | 				}
1713 | 				if rewritten {
1714 | 					entry_pos := position + i64(lo) * SLOT_LENGTH
1715 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1716 | 					core_write_slot(db.core, entry) or_return  // <== [calls core_write_slot]
1717 | 				}
1718 | 				return Sorted_Insert_Result{
1719 | 					node_ptr = node_ptr,
1720 | 					count    = i64(num),
1721 | 					entry    = entry,
1722 | 					added    = false,
1723 | 				}, nil
1724 | 			}
1725 | 			idx := lo
1726 | 			key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return  // <== [calls write_sorted_key_and_entry]
1727 | 			if num < BTREE_SLOT_COUNT {
1728 | 				total := num + 1
1729 | 				entry_pos := position + i64(idx) * SLOT_LENGTH
1730 | 				eb := slot_to_bytes(entry)  // <== [calls slot_to_bytes]
1731 | 				if idx < num {
1732 | 					tail_len := (num - idx) * SLOT_LENGTH
1733 | 					shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1734 | 					copy(shift_buf[:SLOT_LENGTH], eb[:])
1735 | 					copy(shift_buf[SLOT_LENGTH : SLOT_LENGTH + tail_len], entries_buf[idx * SLOT_LENGTH : num * SLOT_LENGTH])
1736 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1737 | 					core_write_all(db.core, shift_buf[:SLOT_LENGTH + tail_len]) or_return  // <== [calls core_write_all]
1738 | 				} else {
1739 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1740 | 					core_write_all(db.core, eb[:]) or_return  // <== [calls core_write_all]
1741 | 				}
1742 | 				new_hdr := [BTREE_NODE_HEADER_SIZE]u8{header_bytes[0], u8(total)}
1743 | 				core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1744 | 				core_write_all(db.core, new_hdr[:]) or_return  // <== [calls core_write_all]
1745 | 				return Sorted_Insert_Result{
1746 | 					node_ptr = node_ptr,
1747 | 					count    = i64(total),
1748 | 					entry    = entry,
1749 | 					added    = true,
1750 | 				}, nil
1751 | 			}
1752 | 			entries: [BTREE_SLOT_COUNT + 1]Slot = ---
1753 | 			for j in 0 ..< idx {
1754 | 				entries[j] = slot_from_slice_raw(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1755 | 			}
1756 | 			entries[idx] = entry
1757 | 			for j in idx ..< num {
1758 | 				entries[j + 1] = slot_from_slice_raw(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1759 | 			}
1760 | 			total := num + 1
1761 | 			left_n := BTREE_SPLIT_COUNT
1762 | 			right_n := total - left_n
1763 | 			left := Sorted_Node{kind = .Leaf, num = left_n}
1764 | 			copy(left.entries[:left_n], entries[:left_n])
1765 | 			right := Sorted_Node{kind = .Leaf, num = right_n}
1766 | 			copy(right.entries[:right_n], entries[left_n:total])
1767 | 			separator: Slot
1768 | 			if left_n == idx {
1769 | 				separator = key_slot
1770 | 			} else {
1771 | 				separator = sorted_entry_key_slot(db, entries[left_n]) or_return  // <== [calls sorted_entry_key_slot]
1772 | 			}
1773 | 			left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1774 | 			right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1775 | 			return Sorted_Insert_Result{
1776 | 				node_ptr = left_ptr,
1777 | 				count    = i64(left_n),
1778 | 				entry    = entry,
1779 | 				added    = true,
1780 | 				split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
1781 | 			}, nil
1782 | 		} else {
1783 | 			branch_buf: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
1784 | 			core_read_exact(db.core, branch_buf[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
1785 | 			lo := 1
1786 | 			hi := num
1787 | 			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1788 | 			for lo < hi {
1789 | 				mid := int(uint(lo + hi) >> 1)
1790 | 				sep_slot := slot_from_slice_raw(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1791 | 				c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1792 | 				if c <= 0 {
1793 | 					lo = mid + 1
1794 | 				} else {
1795 | 					hi = mid
1796 | 				}
1797 | 			}
1798 | 			i := lo - 1
1799 | 			child_slot_pos := position + i64(i) * SLOT_LENGTH
1800 | 			child_slot := slot_from_slice_raw(branch_buf[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1801 | 			child_ptr := child_slot.value
1802 | 			child := sorted_put(db, child_ptr, key, key_only, frozen_at) or_return
1803 | 			if child.split == nil {
1804 | 				if child.node_ptr != child_ptr {
1805 | 					core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
1806 | 					core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
1807 | 				}
1808 | 				new_cnt: i64 = 0
1809 | 				if child.added {
1810 | 					counts_off := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + i * 8
1811 | 					old_cnt := i64(endian.unchecked_get_u64be(branch_buf[counts_off : counts_off + 8]))
1812 | 					new_cnt = old_cnt + 1
1813 | 					count_pos := position + i64(counts_off)
1814 | 					core_seek_to(db.core, count_pos) or_return  // <== [calls core_seek_to]
1815 | 					core_write_i64(db.core, new_cnt) or_return  // <== [calls core_write_i64]
1816 | 				}
1817 | 				return Sorted_Insert_Result{
1818 | 					node_ptr = node_ptr,
1819 | 					count    = new_cnt,
1820 | 					entry    = child.entry,
1821 | 					added    = child.added,
1822 | 				}, nil
1823 | 			}
1824 | 			// Child split: decode full branch node from branch_buf and finish split handling
1825 | 			children: [BTREE_SLOT_COUNT + 1]Slot = ---
1826 | 			separators: [BTREE_SLOT_COUNT + 1]Slot = ---
1827 | 			counts: [BTREE_SLOT_COUNT + 1]i64 = ---
1828 | 			counts_base := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1829 | 			for k in 0 ..< num {
1830 | 				children[k] = slot_from_slice_raw(branch_buf[k * SLOT_LENGTH : (k + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1831 | 				separators[k] = slot_from_slice_raw(branch_buf[sep_off + k * SLOT_LENGTH : sep_off + (k + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1832 | 				counts[k] = i64(endian.unchecked_get_u64be(branch_buf[counts_base + k * 8 : counts_base + (k + 1) * 8]))
1833 | 			}
1834 | 			children[i] = Slot{value = child.node_ptr, tag = .Index}
1835 | 			counts[i] = child.count
1836 | 			split := child.split.?
1837 | 			for j := num; j > i + 1; j -= 1 {
1838 | 				children[j] = children[j - 1]
1839 | 				separators[j] = separators[j - 1]
1840 | 				counts[j] = counts[j - 1]
1841 | 			}
1842 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
1843 | 			separators[i + 1] = split.separator
1844 | 			counts[i + 1] = split.count
1845 | 			total := num + 1
1846 | 
1847 | 			if total <= BTREE_SLOT_COUNT {
1848 | 				branch := Sorted_Node{kind = .Branch, num = total}
1849 | 				copy(branch.children[:total], children[:total])
1850 | 				copy(branch.separators[:total], separators[:total])
1851 | 				copy(branch.counts[:total], counts[:total])
1852 | 				ptr := sorted_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1853 | 				return Sorted_Insert_Result{
1854 | 					node_ptr = ptr,
1855 | 					count    = sorted_node_subtree_count(branch),  // <== [calls sorted_node_subtree_count]
1856 | 					entry    = child.entry,
1857 | 					added    = child.added,
1858 | 				}, nil
1859 | 			}
1860 | 
1861 | 			left_n := BTREE_SPLIT_COUNT
1862 | 			right_n := total - left_n
1863 | 			left := Sorted_Node{kind = .Branch, num = left_n}
1864 | 			copy(left.children[:left_n], children[:left_n])
1865 | 			copy(left.separators[:left_n], separators[:left_n])
1866 | 			copy(left.counts[:left_n], counts[:left_n])
1867 | 			right := Sorted_Node{kind = .Branch, num = right_n}
1868 | 			copy(right.children[:right_n], children[left_n:total])
1869 | 			copy(right.separators[:right_n], separators[left_n:total])
1870 | 			copy(right.counts[:right_n], counts[left_n:total])
1871 | 			separator := separators[left_n]
1872 | 			left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1873 | 			right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1874 | 			return Sorted_Insert_Result{
1875 | 				node_ptr = left_ptr,
1876 | 				count    = sorted_node_subtree_count(left),  // <== [calls sorted_node_subtree_count]
1877 | 				entry    = child.entry,
1878 | 				added    = child.added,
1879 | 				split    = Sorted_Split{node_ptr = right_ptr, count = sorted_node_subtree_count(right), separator = separator},  // <== [calls sorted_node_subtree_count]
1880 | 			}, nil
1881 | 		}
1882 | 	}
1883 | 
1884 | 	node := read_sorted_node(db, node_ptr) or_return  // <== [calls read_sorted_node]
1885 | 	switch node.kind {
1886 | 	case .Leaf:
1887 | 		idx, found := sorted_leaf_search(db, &node, key) or_return  // <== [calls sorted_leaf_search]
1888 | 
1889 | 		if found {
1890 | 			if key_only {
1891 | 				return Sorted_Insert_Result{
1892 | 					node_ptr = node_ptr,
1893 | 					count    = i64(node.num),
1894 | 					entry    = node.entries[idx],
1895 | 					added    = false,
1896 | 				}, nil
1897 | 			}
1898 | 			entry := node.entries[idx]
1899 | 			if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1900 | 				entry = write_sorted_pair(db, entry) or_return  // <== [calls write_sorted_pair]
1901 | 			} else if !btree_reusable(db, entry.value, frozen_at) {  // <== [calls btree_reusable]
1902 | 				kv := read_kv_pair(db, entry) or_return  // <== [calls read_kv_pair]
1903 | 				entry = write_kv_pair(db, entry.tag, kv) or_return  // <== [calls write_kv_pair]
1904 | 			}
1905 | 			leaf := node
1906 | 			leaf.entries[idx] = entry
1907 | 			ptr := sorted_write_node(db, leaf, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1908 | 			return Sorted_Insert_Result{
1909 | 				node_ptr = ptr,
1910 | 				count    = i64(node.num),
1911 | 				entry    = entry,
1912 | 				added    = false,
1913 | 			}, nil
1914 | 		}
1915 | 
1916 | 		key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return  // <== [calls write_sorted_key_and_entry]
1917 | 		entries: [BTREE_SLOT_COUNT + 1]Slot
1918 | 		copy(entries[:idx], node.entries[:idx])
1919 | 		entries[idx] = entry
1920 | 		copy(entries[idx + 1 : node.num + 1], node.entries[idx:node.num])
1921 | 		total := node.num + 1
1922 | 
1923 | 		if total <= BTREE_SLOT_COUNT {
1924 | 			leaf := Sorted_Node{kind = .Leaf, num = total}
1925 | 			copy(leaf.entries[:total], entries[:total])
1926 | 			ptr := sorted_write_node(db, leaf, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1927 | 			return Sorted_Insert_Result{
1928 | 				node_ptr = ptr,
1929 | 				count    = i64(total),
1930 | 				entry    = entry,
1931 | 				added    = true,
1932 | 			}, nil
1933 | 		}
1934 | 
1935 | 		left_n := BTREE_SPLIT_COUNT
1936 | 		right_n := total - left_n
1937 | 		left := Sorted_Node{kind = .Leaf, num = left_n}
1938 | 		copy(left.entries[:left_n], entries[:left_n])
1939 | 		right := Sorted_Node{kind = .Leaf, num = right_n}
1940 | 		copy(right.entries[:right_n], entries[left_n:total])
1941 | 		separator: Slot
1942 | 		if left_n == idx {
1943 | 			separator = key_slot
1944 | 		} else {
1945 | 			separator = sorted_entry_key_slot(db, entries[left_n]) or_return  // <== [calls sorted_entry_key_slot]
1946 | 		}
1947 | 		left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1948 | 		right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1949 | 		return Sorted_Insert_Result{
1950 | 			node_ptr = left_ptr,
1951 | 			count    = i64(left_n),
1952 | 			entry    = entry,
1953 | 			added    = true,
1954 | 			split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
1955 | 		}, nil
1956 | 
1957 | 	case .Branch:
1958 | 		i := sorted_branch_search(db, &node, key) or_return  // <== [calls sorted_branch_search]
1959 | 		child_ptr := node.children[i].value
1960 | 		child := sorted_put(db, child_ptr, key, key_only, frozen_at) or_return
1961 | 		if !child.added && child.node_ptr == child_ptr {
1962 | 			return Sorted_Insert_Result{
1963 | 				node_ptr = node_ptr,
1964 | 				count    = sorted_node_subtree_count(node),  // <== [calls sorted_node_subtree_count]
1965 | 				entry    = child.entry,
1966 | 				added    = false,
1967 | 			}, nil
1968 | 		}
1969 | 
1970 | 		children: [BTREE_SLOT_COUNT + 1]Slot
1971 | 		separators: [BTREE_SLOT_COUNT + 1]Slot
1972 | 		counts: [BTREE_SLOT_COUNT + 1]i64
1973 | 		copy(children[:node.num], node.children[:node.num])
1974 | 		copy(separators[:node.num], node.separators[:node.num])
1975 | 		copy(counts[:node.num], node.counts[:node.num])
1976 | 		children[i] = Slot{value = child.node_ptr, tag = .Index}
1977 | 		counts[i] = child.count if child.split != nil else (node.counts[i] + (1 if child.added else 0))
1978 | 		total := node.num
1979 | 		if split, ok := child.split.?; ok {
1980 | 			for j := node.num; j > i + 1; j -= 1 {
1981 | 				children[j] = children[j - 1]
1982 | 				separators[j] = separators[j - 1]
1983 | 				counts[j] = counts[j - 1]
1984 | 			}
1985 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
1986 | 			separators[i + 1] = split.separator
1987 | 			counts[i + 1] = split.count
1988 | 			total = node.num + 1
1989 | 		}
1990 | 
1991 | 		if total <= BTREE_SLOT_COUNT {
1992 | 			branch := Sorted_Node{kind = .Branch, num = total}
1993 | 			copy(branch.children[:total], children[:total])
1994 | 			copy(branch.separators[:total], separators[:total])
1995 | 			copy(branch.counts[:total], counts[:total])
1996 | 			ptr := sorted_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1997 | 			return Sorted_Insert_Result{
1998 | 				node_ptr = ptr,
1999 | 				count    = sorted_node_subtree_count(branch),  // <== [calls sorted_node_subtree_count]
2000 | 				entry    = child.entry,
2001 | 				added    = child.added,
2002 | 			}, nil
2003 | 		}
2004 | 
2005 | 		left_n := BTREE_SPLIT_COUNT
2006 | 		right_n := total - left_n
2007 | 		left := Sorted_Node{kind = .Branch, num = left_n}
2008 | 		copy(left.children[:left_n], children[:left_n])
2009 | 		copy(left.separators[:left_n], separators[:left_n])
2010 | 		copy(left.counts[:left_n], counts[:left_n])
2011 | 		right := Sorted_Node{kind = .Branch, num = right_n}
2012 | 		copy(right.children[:right_n], children[left_n:total])
2013 | 		copy(right.separators[:right_n], separators[left_n:total])
2014 | 		copy(right.counts[:right_n], counts[left_n:total])
2015 | 		separator := separators[left_n]
2016 | 		left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
2017 | 		right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
2018 | 		return Sorted_Insert_Result{
2019 | 			node_ptr = left_ptr,
2020 | 			count    = sorted_node_subtree_count(left),  // <== [calls sorted_node_subtree_count]
2021 | 			entry    = child.entry,
2022 | 			added    = child.added,
2023 | 			split    = Sorted_Split{node_ptr = right_ptr, count = sorted_node_subtree_count(right), separator = separator},  // <== [calls sorted_node_subtree_count]
2024 | 		}, nil
2025 | 	}
2026 | 	return {}, .Unreachable
2027 | }
```

#### [`sorted_grow_root`](../../xitdb/btree.odin#L2179-L2190) — `DEPTH 4` (`L2179–L2190`)

```odin
2179 | sorted_grow_root :: proc(db: ^Database, result: Sorted_Insert_Result) -> (res: i64, err: Error) {
2180 | 	if split, ok := result.split.?; ok {
2181 | 		root := Sorted_Node{kind = .Branch, num = 2}
2182 | 		root.children[0] = Slot{value = result.node_ptr, tag = .Index}
2183 | 		root.children[1] = Slot{value = split.node_ptr, tag = .Index}
2184 | 		root.separators[1] = split.separator
2185 | 		root.counts[0] = result.count
2186 | 		root.counts[1] = split.count
2187 | 		return write_sorted_node(db, root)  // <== [calls write_sorted_node]
2188 | 	}
2189 | 	return result.node_ptr, nil
2190 | }
```

#### [`sorted_target_slot`](../../xitdb/btree.odin#L2192-L2209) — `DEPTH 4` (`L2192–L2209`)

```odin
2192 | sorted_target_slot :: proc(db: ^Database, entry: Slot, target: Sorted_Map_Get_Target) -> (res: Slot_Pointer, err: Error) {
2193 | 	switch _ in target {
2194 | 	case Sorted_Map_Get_KV_Pair:
2195 | 		return Slot_Pointer{position = nil, slot = entry}, nil
2196 | 	case Sorted_Map_Get_Key:
2197 | 		key_slot := sorted_entry_key_slot(db, entry) or_return  // <== [calls sorted_entry_key_slot]
2198 | 		return Slot_Pointer{position = nil, slot = key_slot}, nil
2199 | 	case Sorted_Map_Get_Value:
2200 | 		if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
2201 | 			return Slot_Pointer{position = nil, slot = Slot{}}, nil
2202 | 		}
2203 | 		pos := entry.value + database_kv_key_offset(db, entry.tag) + SLOT_LENGTH  // <== [calls database_kv_key_offset]
2204 | 		core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
2205 | 		val_slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
2206 | 		return Slot_Pointer{position = pos, slot = val_slot}, nil
2207 | 	}
2208 | 	return {}, .Unexpected_Tag
2209 | }
```

### `xitdb/collections.odin` (21 procedures · 137 lines: [`L16–L24`](../../xitdb/collections.odin#L16-L24), [`L26–L31`](../../xitdb/collections.odin#L26-L31), [`L33–L35`](../../xitdb/collections.odin#L33-L35), [`L69–L75`](../../xitdb/collections.odin#L69-L75), [`L108–L116`](../../xitdb/collections.odin#L108-L116), [`L118–L123`](../../xitdb/collections.odin#L118-L123), [`L125–L127`](../../xitdb/collections.odin#L125-L127), [`L161–L167`](../../xitdb/collections.odin#L161-L167), [`L230–L238`](../../xitdb/collections.odin#L230-L238), [`L240–L245`](../../xitdb/collections.odin#L240-L245), [`L257–L270`](../../xitdb/collections.odin#L257-L270), [`L378–L382`](../../xitdb/collections.odin#L378-L382), [`L384–L390`](../../xitdb/collections.odin#L384-L390), [`L409–L415`](../../xitdb/collections.odin#L409-L415), [`L417–L421`](../../xitdb/collections.odin#L417-L421), [`L423–L428`](../../xitdb/collections.odin#L423-L428), [`L669–L677`](../../xitdb/collections.odin#L669-L677), [`L679–L684`](../../xitdb/collections.odin#L679-L684), [`L686–L688`](../../xitdb/collections.odin#L686-L688), [`L766–L772`](../../xitdb/collections.odin#L766-L772), [`L789–L791`](../../xitdb/collections.odin#L789-L791))

#### [`read_array_list_init`](../../xitdb/collections.odin#L16-L24) — `DEPTH 1` (`L16–L24`)

```odin
  16 | read_array_list_init :: proc(cursor: Read_Cursor) -> (res: Read_Array_List, err: Error) {
  17 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
  18 | 	#partial switch slot_ptr.slot.tag {
  19 | 	case .None, .Array_List:
  20 | 		return Read_Array_List{cursor = cursor}, nil
  21 | 	case:
  22 | 		return {}, .Unexpected_Tag
  23 | 	}
  24 | }
```

#### [`write_array_list_init`](../../xitdb/collections.odin#L26-L31) — `ENTRY POINT` (`L26–L31`)

```odin
  26 | write_array_list_init :: proc(cursor: Write_Cursor) -> (res: Write_Array_List, err: Error) {
  27 | 	c := cursor
  28 | 	wc := cursor_write_path(&c, []Path_Part{Array_List_Init{}}) or_return  // <== [calls cursor_write_path]
  29 | 	ra := read_array_list_init(wc.read_cursor) or_return  // <== [calls read_array_list_init]
  30 | 	return Write_Array_List{read_array_list = ra, write_cursor = wc}, nil
  31 | }
```

#### [`array_list_slot`](../../xitdb/collections.odin#L33-L35) — `ENTRY POINT` (`L33–L35`)

```odin
  33 | array_list_slot :: proc(a: Read_Array_List) -> (res: Slot, err: Error) {
  34 | 	return cursor_slot(a.cursor)  // <== [calls cursor_slot]
  35 | }
```

#### [`array_list_append`](../../xitdb/collections.odin#L69-L75) — `ENTRY POINT` (`L69–L75`)

```odin
  69 | array_list_append :: proc(a: ^Write_Array_List, data: Writeable_Data) -> Error {
  70 | 	_, err := cursor_write_path(&a.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
  71 | 		Array_List_Append{},
  72 | 		Write_Data{data = data},
  73 | 	})
  74 | 	return err
  75 | }
```

#### [`read_linked_array_list_init`](../../xitdb/collections.odin#L108-L116) — `DEPTH 1` (`L108–L116`)

```odin
 108 | read_linked_array_list_init :: proc(cursor: Read_Cursor) -> (res: Read_Linked_Array_List, err: Error) {
 109 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 110 | 	#partial switch slot_ptr.slot.tag {
 111 | 	case .None, .Linked_Array_List:
 112 | 		return Read_Linked_Array_List{cursor = cursor}, nil
 113 | 	case:
 114 | 		return {}, .Unexpected_Tag
 115 | 	}
 116 | }
```

#### [`write_linked_array_list_init`](../../xitdb/collections.odin#L118-L123) — `ENTRY POINT` (`L118–L123`)

```odin
 118 | write_linked_array_list_init :: proc(cursor: Write_Cursor) -> (res: Write_Linked_Array_List, err: Error) {
 119 | 	c := cursor
 120 | 	wc := cursor_write_path(&c, []Path_Part{Linked_Array_List_Init{}}) or_return  // <== [calls cursor_write_path]
 121 | 	ra := read_linked_array_list_init(wc.read_cursor) or_return  // <== [calls read_linked_array_list_init]
 122 | 	return Write_Linked_Array_List{read_linked_array_list = ra, write_cursor = wc}, nil
 123 | }
```

#### [`linked_array_list_slot`](../../xitdb/collections.odin#L125-L127) — `ENTRY POINT` (`L125–L127`)

```odin
 125 | linked_array_list_slot :: proc(a: Read_Linked_Array_List) -> (res: Slot, err: Error) {
 126 | 	return cursor_slot(a.cursor)  // <== [calls cursor_slot]
 127 | }
```

#### [`linked_array_list_append`](../../xitdb/collections.odin#L161-L167) — `ENTRY POINT` (`L161–L167`)

```odin
 161 | linked_array_list_append :: proc(a: ^Write_Linked_Array_List, data: Writeable_Data) -> Error {
 162 | 	_, err := cursor_write_path(&a.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 163 | 		Linked_Array_List_Append{},
 164 | 		Write_Data{data = data},
 165 | 	})
 166 | 	return err
 167 | }
```

#### [`read_hash_map_init`](../../xitdb/collections.odin#L230-L238) — `DEPTH 3` (`L230–L238`)

```odin
 230 | read_hash_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Hash_Map, err: Error) {
 231 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 232 | 	#partial switch slot_ptr.slot.tag {
 233 | 	case .None, .Hash_Map, .Hash_Set:
 234 | 		return Read_Hash_Map{cursor = cursor}, nil
 235 | 	case:
 236 | 		return {}, .Unexpected_Tag
 237 | 	}
 238 | }
```

#### [`write_hash_map_init`](../../xitdb/collections.odin#L240-L245) — `DEPTH 2` (`L240–L245`)

```odin
 240 | write_hash_map_init :: proc(cursor: Write_Cursor) -> (res: Write_Hash_Map, err: Error) {
 241 | 	c := cursor
 242 | 	wc := cursor_write_path(&c, []Path_Part{Hash_Map_Init{counted = false, set = false}}) or_return  // <== [calls cursor_write_path]
 243 | 	rm := read_hash_map_init(wc.read_cursor) or_return  // <== [calls read_hash_map_init]
 244 | 	return Write_Hash_Map{read_hash_map = rm, write_cursor = wc}, nil
 245 | }
```

#### [`write_counted_hash_map_init`](../../xitdb/collections.odin#L257-L270) — `ENTRY POINT` (`L257–L270`)

```odin
 257 | write_counted_hash_map_init :: proc(cursor: Write_Cursor) -> (res: Write_Counted_Hash_Map, err: Error) {
 258 | 	slot_ptr := cursor_resolved(cursor.read_cursor) or_return  // <== [calls cursor_resolved]
 259 | 	#partial switch slot_ptr.slot.tag {
 260 | 	case .None, .Counted_Hash_Map, .Counted_Hash_Set:
 261 | 	case:
 262 | 		return {}, .Unexpected_Tag
 263 | 	}
 264 | 	c := cursor
 265 | 	wc := cursor_write_path(&c, []Path_Part{Hash_Map_Init{counted = true, set = false}}) or_return  // <== [calls cursor_write_path]
 266 | 	rm := Read_Hash_Map{cursor = wc.read_cursor}
 267 | 	return Write_Counted_Hash_Map{
 268 | 		write_hash_map = Write_Hash_Map{read_hash_map = rm, write_cursor = wc},
 269 | 	}, nil
 270 | }
```

#### [`hash_map_put_cursor_by_hash`](../../xitdb/collections.odin#L378-L382) — `DEPTH 1` (`L378–L382`)

```odin
 378 | hash_map_put_cursor_by_hash :: proc(m: ^Write_Hash_Map, hash: []u8) -> (res: Write_Cursor, err: Error) {
 379 | 	return cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 380 | 		Hash_Map_Get{target = Hash_Map_Get_Value{hash = hash}},
 381 | 	})
 382 | }
```

#### [`hash_map_put_key_by_hash`](../../xitdb/collections.odin#L384-L390) — `DEPTH 1` (`L384–L390`)

```odin
 384 | hash_map_put_key_by_hash :: proc(m: ^Write_Hash_Map, hash: []u8, data: Writeable_Data) -> Error {
 385 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 386 | 		Hash_Map_Get{target = Hash_Map_Get_Key{hash = hash}},
 387 | 		Write_Data{data = data, if_empty = true},
 388 | 	})
 389 | 	return err
 390 | }
```

#### [`hash_map_put_key_and_value`](../../xitdb/collections.odin#L409-L415) — `DEPTH 1` (`L409–L415`)

```odin
 409 | hash_map_put_key_and_value :: proc(m: ^Write_Hash_Map, hash: []u8, key: Writeable_Data, data: Writeable_Data) -> Error {
 410 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 411 | 		Hash_Map_Get{target = Hash_Map_Get_KV_Pair{hash = hash}},
 412 | 		Write_KV_Data{key = key, value = data},
 413 | 	})
 414 | 	return err
 415 | }
```

#### [`hash_map_put`](../../xitdb/collections.odin#L417-L421) — `ENTRY POINT` (`L417–L421`)

```odin
 417 | hash_map_put :: proc(m: ^Write_Hash_Map, key: string, data: Writeable_Data) -> Error {
 418 | 	buf: [64]u8 = ---
 419 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 420 | 	return hash_map_put_key_and_value(m, hash, key, data)  // <== [calls hash_map_put_key_and_value]
 421 | }
```

#### [`hash_map_put_cursor`](../../xitdb/collections.odin#L423-L428) — `ENTRY POINT` (`L423–L428`)

```odin
 423 | hash_map_put_cursor :: proc(m: ^Write_Hash_Map, key: string) -> (res: Write_Cursor, err: Error) {
 424 | 	buf: [64]u8 = ---
 425 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 426 | 	hash_map_put_key_by_hash(m, hash, key) or_return  // <== [calls hash_map_put_key_by_hash]
 427 | 	return hash_map_put_cursor_by_hash(m, hash)  // <== [calls hash_map_put_cursor_by_hash]
 428 | }
```

#### [`read_sorted_map_init`](../../xitdb/collections.odin#L669-L677) — `DEPTH 1` (`L669–L677`)

```odin
 669 | read_sorted_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Sorted_Map, err: Error) {
 670 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 671 | 	#partial switch slot_ptr.slot.tag {
 672 | 	case .None, .Sorted_Map, .Sorted_Set:
 673 | 		return Read_Sorted_Map{cursor = cursor}, nil
 674 | 	case:
 675 | 		return {}, .Unexpected_Tag
 676 | 	}
 677 | }
```

#### [`write_sorted_map_init`](../../xitdb/collections.odin#L679-L684) — `ENTRY POINT` (`L679–L684`)

```odin
 679 | write_sorted_map_init :: proc(cursor: Write_Cursor) -> (res: Write_Sorted_Map, err: Error) {
 680 | 	c := cursor
 681 | 	wc := cursor_write_path(&c, []Path_Part{Sorted_Map_Init{set = false}}) or_return  // <== [calls cursor_write_path]
 682 | 	rm := read_sorted_map_init(wc.read_cursor) or_return  // <== [calls read_sorted_map_init]
 683 | 	return Write_Sorted_Map{read_sorted_map = rm, write_cursor = wc}, nil
 684 | }
```

#### [`sorted_map_slot`](../../xitdb/collections.odin#L686-L688) — `ENTRY POINT` (`L686–L688`)

```odin
 686 | sorted_map_slot :: proc(m: Read_Sorted_Map) -> (res: Slot, err: Error) {
 687 | 	return cursor_slot(m.cursor)  // <== [calls cursor_slot]
 688 | }
```

#### [`sorted_map_put_by_bytes`](../../xitdb/collections.odin#L766-L772) — `DEPTH 1` (`L766–L772`)

```odin
 766 | sorted_map_put_by_bytes :: proc(m: ^Write_Sorted_Map, key: []u8, data: Writeable_Data) -> Error {
 767 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 768 | 		Sorted_Map_Get{target = Sorted_Map_Get_Value{key = key}},
 769 | 		Write_Data{data = data},
 770 | 	})
 771 | 	return err
 772 | }
```

#### [`sorted_map_put`](../../xitdb/collections.odin#L789-L791) — `ENTRY POINT` (`L789–L791`)

```odin
 789 | sorted_map_put :: proc(m: ^Write_Sorted_Map, key: string, data: Writeable_Data) -> Error {
 790 | 	return sorted_map_put_by_bytes(m, transmute([]u8)key, data)  // <== [calls sorted_map_put_by_bytes]
 791 | }
```

### `xitdb/compact_replicate.odin` (5 procedures · 87 lines: [`L22–L24`](../../xitdb/compact_replicate.odin#L22-L24), [`L26–L28`](../../xitdb/compact_replicate.odin#L26-L28), [`L49–L61`](../../xitdb/compact_replicate.odin#L49-L61), [`L95–L100`](../../xitdb/compact_replicate.odin#L95-L100), [`L615–L676`](../../xitdb/compact_replicate.odin#L615-L676))

#### [`memory_offset_map_init`](../../xitdb/compact_replicate.odin#L22-L24) — `ENTRY POINT` (`L22–L24`)

```odin
  22 | memory_offset_map_init :: proc(allocator := context.allocator) -> Memory_Offset_Map {
  23 | 	return Memory_Offset_Map{entries = make(map[i64]i64, allocator = allocator)}
  24 | }
```

#### [`memory_offset_map_destroy`](../../xitdb/compact_replicate.odin#L26-L28) — `DEPTH 1` (`L26–L28`)

```odin
  26 | memory_offset_map_destroy :: proc(m: ^Memory_Offset_Map) {
  27 | 	delete(m.entries)
  28 | }
```

#### [`offset_map_reset`](../../xitdb/compact_replicate.odin#L49-L61) — `DEPTH 1` (`L49–L61`)

```odin
  49 | offset_map_reset :: proc(om: ^Offset_Map) -> Error {
  50 | 	switch &m in om {
  51 | 	case Memory_Offset_Map:
  52 | 		clear(&m.entries)
  53 | 		return nil
  54 | 	case File_Offset_Map:
  55 | 		cursor := m.m.write_cursor
  56 | 		cursor_write(&cursor, nil) or_return  // <== [calls cursor_write]
  57 | 		m.m = write_hash_map_init(cursor) or_return  // <== [calls write_hash_map_init]
  58 | 		return nil
  59 | 	}
  60 | 	return nil
  61 | }
```

#### [`offset_map_destroy`](../../xitdb/compact_replicate.odin#L95-L100) — `ENTRY POINT` (`L95–L100`)

```odin
  95 | offset_map_destroy :: proc(om: ^Offset_Map) {
  96 | 	#partial switch &m in om {
  97 | 	case Memory_Offset_Map:
  98 | 		memory_offset_map_destroy(&m)  // <== [calls memory_offset_map_destroy]
  99 | 	}
 100 | }
```

#### [`database_compact`](../../xitdb/compact_replicate.odin#L615-L676) — `ENTRY POINT` (`L615–L676`)

```odin
 615 | database_compact :: proc(db: ^Database, target_core: ^Core, offset_map: ^Offset_Map = nil) -> (target: Database, err: Error) {
 616 | 	local_map: Offset_Map
 617 | 	om := offset_map
 618 | 	if om == nil {
 619 | 		local_map = memory_offset_map_init()  // <== [calls memory_offset_map_init]
 620 | 		om = &local_map
 621 | 	}
 622 | 	defer if offset_map == nil {
 623 | 		offset_map_destroy(&local_map)  // <== [calls offset_map_destroy]
 624 | 	}
 625 | 
 626 | 	offset_map_reset(om) or_return  // <== [calls offset_map_reset]
 627 | 
 628 | 	h := db.hasher
 629 | 	h.id = db.header.hash_id
 630 | 	h.hash_size = db.header.hash_size
 631 | 	h.file_id = 0
 632 | 	target = database_init(target_core, h) or_return  // <== [calls database_init]
 633 | 
 634 | 	target_root := database_read_root_slot(&target) or_return  // <== [calls database_read_root_slot]
 635 | 	if !slot_empty(target_root) {  // <== [calls slot_empty]
 636 | 		return {}, .Target_Not_Empty
 637 | 	}
 638 | 
 639 | 	source_root := database_read_root_slot(db) or_return  // <== [calls database_read_root_slot]
 640 | 	if slot_empty(source_root) {  // <== [calls slot_empty]
 641 | 		return target, nil
 642 | 	}
 643 | 
 644 | 	compactor := _Compactor{
 645 | 		source_core = db.core,
 646 | 		target_core = target.core,
 647 | 		hash_size   = db.header.hash_size,
 648 | 		offset_map  = om,
 649 | 	}
 650 | 
 651 | 	#partial switch source_root.tag {
 652 | 	case .Array_List:
 653 | 		rc := database_root_cursor(db)  // <== [calls database_root_cursor]
 654 | 		last_moment_maybe := cursor_read_path_slot(rc.read_cursor, []Path_Part{Array_List_Get{index = -1}}) or_return  // <== [calls cursor_read_path_slot]
 655 | 		if last_moment, ok := last_moment_maybe.?; ok && !slot_empty(last_moment) {  // <== [calls slot_empty]
 656 | 			ctx := _Remap_Ctx{compactor = &compactor, slot = last_moment}
 657 | 			trc := database_root_cursor(&target)  // <== [calls database_root_cursor]
 658 | 			_, err = cursor_write_path(&trc, []Path_Part{  // <== [calls cursor_write_path]
 659 | 				Array_List_Init{},
 660 | 				Array_List_Append{},
 661 | 				Context{function = _remap_slot_cb, user_data = &ctx},
 662 | 			})
 663 | 			if err != nil {
 664 | 				return {}, err
 665 | 			}
 666 | 		}
 667 | 	case:
 668 | 		ctx := _Remap_Ctx{compactor = &compactor, slot = source_root}
 669 | 		err = database_run_context(&target, _remap_slot_cb, &ctx)  // <== [calls database_run_context]
 670 | 		if err != nil {
 671 | 			return {}, err
 672 | 		}
 673 | 	}
 674 | 
 675 | 	return target, nil
 676 | }
```

### `xitdb/core.odin` (19 procedures · 424 lines: [`L42–L48`](../../xitdb/core.odin#L42-L48), [`L102–L123`](../../xitdb/core.odin#L102-L123), [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L238–L285`](../../xitdb/core.odin#L238-L285), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437), [`L441–L457`](../../xitdb/core.odin#L441-L457), [`L494–L500`](../../xitdb/core.odin#L494-L500), [`L502–L507`](../../xitdb/core.odin#L502-L507), [`L509–L532`](../../xitdb/core.odin#L509-L532), [`L534–L550`](../../xitdb/core.odin#L534-L550), [`L552–L575`](../../xitdb/core.odin#L552-L575), [`L577–L581`](../../xitdb/core.odin#L577-L581), [`L583–L600`](../../xitdb/core.odin#L583-L600))

#### [`core_memory_init`](../../xitdb/core.odin#L42-L48) — `ENTRY POINT` (`L42–L48`)

```odin
  42 | core_memory_init :: proc(allocator := context.allocator) -> Core {
  43 | 	return Core_Memory{
  44 | 		buf       = make([dynamic]u8, 0, 1024, allocator),
  45 | 		pos       = 0,
  46 | 		allocator = allocator,
  47 | 	}
  48 | }
```

#### [`core_destroy`](../../xitdb/core.odin#L102-L123) — `ENTRY POINT` (`L102–L123`)

```odin
 102 | core_destroy :: proc(c: ^Core, close_file := false) -> Error {
 103 | 	switch &v in c {
 104 | 	case Core_Memory:
 105 | 		delete(v.buf)
 106 | 		v.buf = nil
 107 | 		v.pos = 0
 108 | 	case Core_File:
 109 | 		if close_file && v.file != nil {
 110 | 			os.close(v.file) or_return
 111 | 			v.file = nil
 112 | 		}
 113 | 	case Core_Buffered_File:
 114 | 		_ = _buffered_flush(&v)  // <== [calls _buffered_flush]
 115 | 		delete(v.memory.buf)
 116 | 		v.memory.buf = nil
 117 | 		if close_file && v.file.file != nil {
 118 | 			os.close(v.file.file) or_return
 119 | 			v.file.file = nil
 120 | 		}
 121 | 	}
 122 | 	return nil
 123 | }
```

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 2` (`L125–L142`)

```odin
 125 | @(private)
 126 | _buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
 127 | 	cached_len := bf.file_len
 128 | 	bf.file_len = nil
 129 | 	os.seek(bf.file.file, pos, .Start) or_return
 130 | 	written := 0
 131 | 	for written < len(data) {
 132 | 		n := os.write(bf.file.file, data[written:]) or_return
 133 | 		if n == 0 {
 134 | 			return io.Error.Short_Write
 135 | 		}
 136 | 		written += n
 137 | 	}
 138 | 	if cl, ok := cached_len.?; ok {
 139 | 		bf.file_len = max(cl, pos + i64(len(data)))
 140 | 	}
 141 | 	return nil
 142 | }
```

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 1` (`L144–L151`)

```odin
 144 | @(private)
 145 | _buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
 146 | 	if len(bf.memory.buf) > bf.flushed_len {
 147 | 		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return  // <== [calls _buffered_write_to_file]
 148 | 		bf.flushed_len = len(bf.memory.buf)
 149 | 	}
 150 | 	return nil
 151 | }
```

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 1` (`L153–L174`)

```odin
 153 | core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
 154 | 	switch &v in c {
 155 | 	case Core_Memory:
 156 | 		return i64(len(v.buf)), nil
 157 | 	case Core_File:
 158 | 		return os.file_size(v.file)
 159 | 	case Core_Buffered_File:
 160 | 		flen: i64
 161 | 		if fl, ok := v.file_len.?; ok {
 162 | 			flen = fl
 163 | 		} else {
 164 | 			flen = os.file_size(v.file.file) or_return
 165 | 			v.file_len = flen
 166 | 		}
 167 | 		buf_size := i64(len(v.memory.buf))
 168 | 		if buf_size == 0 {
 169 | 			return flen, nil
 170 | 		}
 171 | 		return max(v.memory_pos + buf_size, flen), nil
 172 | 	}
 173 | 	return 0, .Invalid_Database
 174 | }
```

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 1` (`L176–L192`)

```odin
 176 | core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
 177 | 	if pos < 0 {
 178 | 		return .Expected_Unsigned_Long
 179 | 	}
 180 | 	switch &v in c {
 181 | 	case Core_Memory:
 182 | 		v.pos = pos
 183 | 		return nil
 184 | 	case Core_File:
 185 | 		os.seek(v.file, pos, .Start) or_return
 186 | 		return nil
 187 | 	case Core_Buffered_File:
 188 | 		v.pos = pos
 189 | 		return nil
 190 | 	}
 191 | 	return .Invalid_Database
 192 | }
```

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 1` (`L219–L236`)

```odin
 219 | core_sync :: proc(c: ^Core) -> Error {
 220 | 	switch &v in c {
 221 | 	case Core_Memory:
 222 | 		return nil
 223 | 	case Core_File:
 224 | 		if !v.fsync {
 225 | 			return nil
 226 | 		}
 227 | 		return os.sync(v.file)
 228 | 	case Core_Buffered_File:
 229 | 		_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 230 | 		if !v.file.fsync {
 231 | 			return nil
 232 | 		}
 233 | 		return os.sync(v.file.file)
 234 | 	}
 235 | 	return .Invalid_Database
 236 | }
```

#### [`core_set_length`](../../xitdb/core.odin#L238-L285) — `DEPTH 4` (`L238–L285`)

```odin
 238 | core_set_length :: proc(c: ^Core, new_len: i64) -> Error {
 239 | 	if new_len < 0 {
 240 | 		return .Expected_Unsigned_Long
 241 | 	}
 242 | 	switch &v in c {
 243 | 	case Core_Memory:
 244 | 		if new_len > i64(len(v.buf)) {
 245 | 			return Xitdb_Error.Invalid_Offset
 246 | 		}
 247 | 		resize(&v.buf, int(new_len))
 248 | 		if v.pos > new_len {
 249 | 			v.pos = new_len
 250 | 		}
 251 | 		return nil
 252 | 	case Core_File:
 253 | 		err := os.truncate(v.file, new_len)
 254 | 		if err != nil {
 255 | 			// Read-only file handles ignore setLength just like Zig/Go xitdb.
 256 | 			return nil
 257 | 		}
 258 | 		pos := os.seek(v.file, 0, .Current) or_return
 259 | 		if pos > new_len {
 260 | 			os.seek(v.file, new_len, .Start) or_return
 261 | 		}
 262 | 		return nil
 263 | 	case Core_Buffered_File:
 264 | 		buf_size := i64(len(v.memory.buf))
 265 | 		if new_len <= v.memory_pos {
 266 | 			clear(&v.memory.buf)
 267 | 			v.flushed_len = 0
 268 | 		} else if new_len < v.memory_pos + buf_size {
 269 | 			new_buf_len := int(new_len - v.memory_pos)
 270 | 			resize(&v.memory.buf, new_buf_len)
 271 | 			if v.flushed_len > new_buf_len {
 272 | 				v.flushed_len = new_buf_len
 273 | 			}
 274 | 		}
 275 | 		v.file_len = nil
 276 | 		if err := os.truncate(v.file.file, new_len); err == nil {
 277 | 			v.file_len = new_len
 278 | 		}
 279 | 		if v.pos > new_len {
 280 | 			v.pos = new_len
 281 | 		}
 282 | 		return nil
 283 | 	}
 284 | 	return .Invalid_Database
 285 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 4` (`L288–L323`)

```odin
 288 | core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
 289 | 	if len(p) == 0 {
 290 | 		return 0, nil
 291 | 	}
 292 | 	switch &v in c {
 293 | 	case Core_Memory:
 294 | 		if v.pos >= i64(len(v.buf)) {
 295 | 			return 0, io.Error.EOF
 296 | 		}
 297 | 		avail := int(i64(len(v.buf)) - v.pos)
 298 | 		to_read := min(len(p), avail)
 299 | 		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
 300 | 		v.pos += i64(to_read)
 301 | 		return to_read, nil
 302 | 	case Core_File:
 303 | 		return os.read(v.file, p)
 304 | 	case Core_Buffered_File:
 305 | 		buf_len := i64(len(v.memory.buf))
 306 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
 307 | 			mem_off := int(v.pos - v.memory_pos)
 308 | 			size := min(len(p), int(buf_len) - mem_off)
 309 | 			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
 310 | 			v.pos += i64(size)
 311 | 			return size, nil
 312 | 		}
 313 | 		os.seek(v.file.file, v.pos, .Start) or_return
 314 | 		max_size := len(p)
 315 | 		if buf_len > 0 && v.pos < v.memory_pos {
 316 | 			max_size = min(len(p), int(v.memory_pos - v.pos))
 317 | 		}
 318 | 		n, err := os.read(v.file.file, p[:max_size])
 319 | 		v.pos += i64(n)
 320 | 		return n, err
 321 | 	}
 322 | 	return 0, .Invalid_Database
 323 | }
```

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 3` (`L326–L359`)

```odin
 326 | core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
 327 | 	if len(p) == 0 {
 328 | 		return nil
 329 | 	}
 330 | 	#partial switch &v in c {
 331 | 	case Core_Memory:
 332 | 		end_pos := v.pos + i64(len(p))
 333 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 334 | 			v.pos = i64(len(v.buf))
 335 | 			return Xitdb_Error.Unexpected_EOF
 336 | 		}
 337 | 		copy(p, v.buf[int(v.pos):int(end_pos)])
 338 | 		v.pos = end_pos
 339 | 		return nil
 340 | 	}
 341 | 	total := 0
 342 | 	for total < len(p) {
 343 | 		n, err := core_read(c, p[total:])  // <== [calls core_read]
 344 | 		total += n
 345 | 		if err != nil {
 346 | 			if err == io.Error.EOF {
 347 | 				if total == len(p) {
 348 | 					return nil
 349 | 				}
 350 | 				return Xitdb_Error.Unexpected_EOF
 351 | 			}
 352 | 			return err
 353 | 		}
 354 | 		if n == 0 {
 355 | 			return Xitdb_Error.Unexpected_EOF
 356 | 		}
 357 | 	}
 358 | 	return nil
 359 | }
```

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 1` (`L362–L437`)

```odin
 362 | core_write_all :: proc(c: ^Core, p: []u8) -> Error {
 363 | 	if len(p) == 0 {
 364 | 		return nil
 365 | 	}
 366 | 	switch &v in c {
 367 | 	case Core_Memory:
 368 | 		old_size := int(len(v.buf))
 369 | 		end_pos := int(v.pos) + len(p)
 370 | 		if end_pos > old_size {
 371 | 			resize(&v.buf, end_pos)
 372 | 		}
 373 | 		copy(v.buf[int(v.pos):end_pos], p)
 374 | 		v.pos = i64(end_pos)
 375 | 		return nil
 376 | 	case Core_File:
 377 | 		written := 0
 378 | 		for written < len(p) {
 379 | 			n := os.write(v.file, p[written:]) or_return
 380 | 			if n == 0 {
 381 | 				return io.Error.Short_Write
 382 | 			}
 383 | 			written += n
 384 | 		}
 385 | 		return nil
 386 | 	case Core_Buffered_File:
 387 | 		n := i64(len(p))
 388 | 		if v.file_len == nil {
 389 | 			fl := os.file_size(v.file.file) or_return
 390 | 			v.file_len = fl
 391 | 		}
 392 | 		buf_size := i64(len(v.memory.buf))
 393 | 		if buf_size > 0 && v.pos + n <= v.memory_pos {
 394 | 			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
 395 | 			// write directly to the file without evicting the hot tail buffer.
 396 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 397 | 			v.pos += n
 398 | 			return nil
 399 | 		}
 400 | 		if buf_size == 0 {
 401 | 			v.memory_pos = v.pos
 402 | 			v.flushed_len = 0
 403 | 		} else if v.pos > v.memory_pos + buf_size ||
 404 | 		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
 405 | 			_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 406 | 			clear(&v.memory.buf)
 407 | 			v.flushed_len = 0
 408 | 			v.memory_pos = v.pos
 409 | 		}
 410 | 		buf_size = i64(len(v.memory.buf))
 411 | 		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
 412 | 			rel_off := int(v.pos - v.memory_pos)
 413 | 			end_off := rel_off + len(p)
 414 | 			if end_off > len(v.memory.buf) {
 415 | 				resize(&v.memory.buf, end_off)
 416 | 			}
 417 | 			copy(v.memory.buf[rel_off:end_off], p)
 418 | 			if rel_off < v.flushed_len {
 419 | 				if end_off <= v.flushed_len {
 420 | 					_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 421 | 				} else {
 422 | 					v.flushed_len = rel_off
 423 | 				}
 424 | 			}
 425 | 		} else {
 426 | 			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
 427 | 				_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 428 | 				clear(&v.memory.buf)
 429 | 				v.flushed_len = 0
 430 | 			}
 431 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 432 | 		}
 433 | 		v.pos += n
 434 | 		return nil
 435 | 	}
 436 | 	return .Invalid_Database
 437 | }
```

#### [`core_slice_at`](../../xitdb/core.odin#L441-L457) — `DEPTH 5` (`L441–L457`)

```odin
 441 | core_slice_at :: #force_inline proc(c: ^Core, pos: i64, n: int) -> (slice: []u8, in_mem: bool, err: Error) {
 442 | 	#partial switch &v in c {
 443 | 	case Core_Memory:
 444 | 		p := int(pos)
 445 | 		if p < 0 || p + n > len(v.buf) {
 446 | 			return nil, true, Xitdb_Error.Unexpected_EOF
 447 | 		}
 448 | 		return v.buf[p : p + n], true, nil
 449 | 	case Core_Buffered_File:
 450 | 		buf_len := i64(len(v.memory.buf))
 451 | 		if buf_len > 0 && pos >= v.memory_pos && pos + i64(n) <= v.memory_pos + buf_len {
 452 | 			mem_off := int(pos - v.memory_pos)
 453 | 			return v.memory.buf[mem_off : mem_off + n], true, nil
 454 | 		}
 455 | 	}
 456 | 	return nil, false, nil
 457 | }
```

#### [`core_read_long`](../../xitdb/core.odin#L494-L500) — `DEPTH 4` (`L494–L500`)

```odin
 494 | core_read_long :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 495 | 	res = core_read_i64(c) or_return  // <== [calls core_read_i64]
 496 | 	if res < 0 {
 497 | 		return 0, Xitdb_Error.Expected_Unsigned_Long
 498 | 	}
 499 | 	return res, nil
 500 | }
```

#### [`core_write_long`](../../xitdb/core.odin#L502-L507) — `DEPTH 4` (`L502–L507`)

```odin
 502 | core_write_long :: #force_inline proc(c: ^Core, v: i64) -> Error {
 503 | 	if v < 0 {
 504 | 		return Xitdb_Error.Expected_Unsigned_Long
 505 | 	}
 506 | 	return core_write_i64(c, v)  // <== [calls core_write_i64]
 507 | }
```

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 5` (`L509–L532`)

```odin
 509 | core_read_i64 :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 510 | 	#partial switch &v in c {
 511 | 	case Core_Memory:
 512 | 		end_pos := v.pos + 8
 513 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 514 | 			v.pos = i64(len(v.buf))
 515 | 			return 0, Xitdb_Error.Unexpected_EOF
 516 | 		}
 517 | 		res = i64(endian.unchecked_get_u64be(v.buf[int(v.pos):int(end_pos)]))
 518 | 		v.pos = end_pos
 519 | 		return res, nil
 520 | 	case Core_Buffered_File:
 521 | 		buf_len := i64(len(v.memory.buf))
 522 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + 8 <= v.memory_pos + buf_len {
 523 | 			mem_off := int(v.pos - v.memory_pos)
 524 | 			res = i64(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
 525 | 			v.pos += 8
 526 | 			return res, nil
 527 | 		}
 528 | 	}
 529 | 	b: [8]u8 = ---
 530 | 	core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
 531 | 	return i64(endian.unchecked_get_u64be(b[:])), nil
 532 | }
```

#### [`core_write_i64`](../../xitdb/core.odin#L534-L550) — `DEPTH 5` (`L534–L550`)

```odin
 534 | core_write_i64 :: #force_inline proc(c: ^Core, v: i64) -> Error {
 535 | 	#partial switch &m in c {
 536 | 	case Core_Memory:
 537 | 		old_size := len(m.buf)
 538 | 		pos := int(m.pos)
 539 | 		end_pos := pos + 8
 540 | 		if end_pos > old_size {
 541 | 			resize(&m.buf, end_pos)
 542 | 		}
 543 | 		endian.unchecked_put_u64be(m.buf[pos:end_pos], u64(v))
 544 | 		m.pos = i64(end_pos)
 545 | 		return nil
 546 | 	}
 547 | 	b: [8]u8 = ---
 548 | 	endian.unchecked_put_u64be(b[:], u64(v))
 549 | 	return core_write_all(c, b[:])  // <== [calls core_write_all]
 550 | }
```

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 3` (`L552–L575`)

```odin
 552 | core_read_slot_raw :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 553 | 	#partial switch &v in c {
 554 | 	case Core_Memory:
 555 | 		end_pos := v.pos + SLOT_LENGTH
 556 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 557 | 			v.pos = i64(len(v.buf))
 558 | 			return {}, Xitdb_Error.Unexpected_EOF
 559 | 		}
 560 | 		s = slot_from_slice_raw(v.buf[int(v.pos):int(end_pos)])  // <== [calls slot_from_slice_raw]
 561 | 		v.pos = end_pos
 562 | 		return s, nil
 563 | 	case Core_Buffered_File:
 564 | 		buf_len := i64(len(v.memory.buf))
 565 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + SLOT_LENGTH <= v.memory_pos + buf_len {
 566 | 			mem_off := int(v.pos - v.memory_pos)
 567 | 			s = slot_from_slice_raw(v.memory.buf[mem_off : mem_off + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
 568 | 			v.pos += SLOT_LENGTH
 569 | 			return s, nil
 570 | 		}
 571 | 	}
 572 | 	buf: [SLOT_LENGTH]u8 = ---
 573 | 	core_read_exact(c, buf[:]) or_return  // <== [calls core_read_exact]
 574 | 	return slot_from_bytes_raw(buf), nil  // <== [calls slot_from_bytes_raw]
 575 | }
```

#### [`core_read_slot`](../../xitdb/core.odin#L577-L581) — `DEPTH 3` (`L577–L581`)

```odin
 577 | core_read_slot :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 578 | 	s = core_read_slot_raw(c) or_return  // <== [calls core_read_slot_raw]
 579 | 	tag_validate(s.tag) or_return  // <== [calls tag_validate]
 580 | 	return s, nil
 581 | }
```

#### [`core_write_slot`](../../xitdb/core.odin#L583-L600) — `DEPTH 3` (`L583–L600`)

```odin
 583 | core_write_slot :: #force_inline proc(c: ^Core, s: Slot) -> Error {
 584 | 	#partial switch &v in c {
 585 | 	case Core_Memory:
 586 | 		old_size := len(v.buf)
 587 | 		pos := int(v.pos)
 588 | 		end_pos := pos + SLOT_LENGTH
 589 | 		if end_pos > old_size {
 590 | 			resize(&v.buf, end_pos)
 591 | 		}
 592 | 		full_bit := u8(0x80) if s.full else u8(0)
 593 | 		v.buf[pos] = full_bit | (u8(s.tag) & 0x7f)
 594 | 		endian.unchecked_put_u64be(v.buf[pos + 1 : end_pos], u64(s.value))
 595 | 		v.pos = i64(end_pos)
 596 | 		return nil
 597 | 	}
 598 | 	buf := slot_to_bytes(s)  // <== [calls slot_to_bytes]
 599 | 	return core_write_all(c, buf[:])  // <== [calls core_write_all]
 600 | }
```

### `xitdb/cursor.odin` (8 procedures · 124 lines: [`L28–L40`](../../xitdb/cursor.odin#L28-L40), [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L63–L66`](../../xitdb/cursor.odin#L63-L66), [`L81–L95`](../../xitdb/cursor.odin#L81-L95), [`L97–L105`](../../xitdb/cursor.odin#L97-L105), [`L107–L116`](../../xitdb/cursor.odin#L107-L116), [`L118–L174`](../../xitdb/cursor.odin#L118-L174), [`L185–L189`](../../xitdb/cursor.odin#L185-L189))

#### [`new_write_cursor`](../../xitdb/cursor.odin#L28-L40) — `DEPTH 2` (`L28–L40`)

```odin
  28 | new_write_cursor :: proc(slot_ptr: Slot_Pointer, db: ^Database) -> Write_Cursor {
  29 | 	c := Write_Cursor{
  30 | 		read_cursor = Read_Cursor{
  31 | 			slot_ptr  = slot_ptr,
  32 | 			db        = db,
  33 | 			frozen_at = 0,
  34 | 		},
  35 | 	}
  36 | 	if slot_ptr.position != nil && !is_root(slot_ptr) {  // <== [calls is_root]
  37 | 		c.transaction = db.transaction
  38 | 	}
  39 | 	return c
  40 | }
```

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 1` (`L46–L56`)

```odin
  46 | cursor_resolved :: proc(c: Read_Cursor) -> (res: Slot_Pointer, err: Error) {
  47 | 	if is_root(c.slot_ptr) {  // <== [calls is_root]
  48 | 		header := database_read_root_header(c.db) or_return  // <== [calls database_read_root_header]
  49 | 		if header.file_size < ROOT_TRAILER_LENGTH {
  50 | 			return {}, .Invalid_Database
  51 | 		}
  52 | 		position := header.file_size - ROOT_TRAILER_LENGTH
  53 | 		return Slot_Pointer{position = position, slot = header.root}, nil
  54 | 	}
  55 | 	return c.slot_ptr, nil
  56 | }
```

#### [`cursor_slot`](../../xitdb/cursor.odin#L63-L66) — `DEPTH 1` (`L63–L66`)

```odin
  63 | cursor_slot :: proc(c: Read_Cursor) -> (res: Slot, err: Error) {
  64 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  65 | 	return slot_ptr.slot, nil
  66 | }
```

#### [`cursor_read_path_slot`](../../xitdb/cursor.odin#L81-L95) — `DEPTH 1` (`L81–L95`)

```odin
  81 | cursor_read_path_slot :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Slot), err: Error) {
  82 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  83 | 	slot_ptr: Slot_Pointer
  84 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  85 | 	if err != nil {
  86 | 		if err == .Key_Not_Found {
  87 | 			return nil, nil
  88 | 		}
  89 | 		return nil, err
  90 | 	}
  91 | 	if !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
  92 | 		return slot_ptr.slot, nil
  93 | 	}
  94 | 	return nil, nil
  95 | }
```

#### [`cursor_check_writable`](../../xitdb/cursor.odin#L97-L105) — `DEPTH 2` (`L97–L105`)

```odin
  97 | cursor_check_writable :: proc(c: ^Write_Cursor) -> Error {
  98 | 	if c.transaction != nil && c.transaction != c.db.transaction {
  99 | 		return .Expired_Transaction
 100 | 	}
 101 | 	if !is_root(c.slot_ptr) && c.transaction == nil && c.db.tx_start == nil {  // <== [calls is_root]
 102 | 		return .Expected_Tx_Start
 103 | 	}
 104 | 	return database_check_frozen_slot(c.db, c.slot_ptr)  // <== [calls database_check_frozen_slot]
 105 | }
```

#### [`cursor_reload_slot`](../../xitdb/cursor.odin#L107-L116) — `DEPTH 2` (`L107–L116`)

```odin
 107 | cursor_reload_slot :: proc(c: ^Write_Cursor) -> Error {
 108 | 	if (c.transaction != nil || c.db.tx_start != nil) && !is_root(c.slot_ptr) {  // <== [calls is_root]
 109 | 		if pos, ok := c.slot_ptr.position.?; ok {
 110 | 			core_seek_to(c.db.core, pos) or_return  // <== [calls core_seek_to]
 111 | 			slot := core_read_slot(c.db.core) or_return  // <== [calls core_read_slot]
 112 | 			c.slot_ptr = slot_pointer_with_slot(c.slot_ptr, slot)  // <== [calls slot_pointer_with_slot]
 113 | 		}
 114 | 	}
 115 | 	return nil
 116 | }
```

#### [`cursor_write_path`](../../xitdb/cursor.odin#L118-L174) — `DEPTH 1` (`L118–L174`)

```odin
 118 | cursor_write_path :: proc(c: ^Write_Cursor, path: []Path_Part) -> (res: Write_Cursor, err: Error) {
 119 | 	cursor_check_writable(c) or_return  // <== [calls cursor_check_writable]
 120 | 	if (c.db.transaction != nil || c.db.tx_start != nil) && is_root(c.slot_ptr) && len(path) > 0 {  // <== [calls is_root]
 121 | 		return {}, .Nested_Top_Level_Write
 122 | 	}
 123 | 
 124 | 	tx_stack: Transaction
 125 | 	starts_transaction := c.db.transaction == nil && is_root(c.slot_ptr)  // <== [calls is_root]
 126 | 	if starts_transaction {
 127 | 		c.db.transaction = &tx_stack
 128 | 	}
 129 | 	defer if starts_transaction {
 130 | 		c.db.transaction = nil
 131 | 	}
 132 | 
 133 | 	err = nil
 134 | 	switch c.slot_ptr.slot.tag {
 135 | 	case .Array_List, .Linked_Array_List, .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
 136 | 		is_init := false
 137 | 		if len(path) > 0 {
 138 | 			_, is_init = init_tag(path[0])  // <== [calls init_tag]
 139 | 		}
 140 | 		if is_init || (c.db.transaction != nil && (c.db.transaction.frozen_at != nil || c.frozen_at != 0)) {
 141 | 			err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 142 | 		}
 143 | 	case .None, .Index, .Bytes, .Short_Bytes, .Uint, .Int, .Float, .KV_Pair, .Sorted_KV_Pair:
 144 | 		err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 145 | 	}
 146 | 	slot_ptr: Slot_Pointer
 147 | 	if err == nil {
 148 | 		slot_ptr, err = read_slot_pointer(c.db, .Read_Write, path, 0, c.slot_ptr, c.frozen_at)  // <== [calls read_slot_pointer]
 149 | 	}
 150 | 	if err != nil {
 151 | 		if c.db.tx_start == nil {
 152 | 			_ = database_truncate(c.db)  // <== [calls database_truncate]
 153 | 		}
 154 | 		return {}, err
 155 | 	}
 156 | 	if c.db.tx_start == nil {
 157 | 		core_sync(c.db.core) or_return  // <== [calls core_sync]
 158 | 	}
 159 | 	ends_with_ctx := false
 160 | 	if len(path) > 0 {
 161 | 		_, ends_with_ctx = path[len(path) - 1].(Context)
 162 | 	}
 163 | 	res = new_write_cursor(slot_ptr, c.db)  // <== [calls new_write_cursor]
 164 | 	res.frozen_at = c.frozen_at
 165 | 	if ends_with_ctx {
 166 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 167 | 		cursor_reload_slot(&res) or_return  // <== [calls cursor_reload_slot]
 168 | 	} else if c.slot_ptr.position != nil && c.slot_ptr.position == slot_ptr.position {
 169 | 		c.slot_ptr = slot_ptr
 170 | 	} else if c.db.transaction == nil || c.db.transaction.frozen_at != nil || c.frozen_at != 0 || c.slot_ptr.slot.tag == .None {
 171 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 172 | 	}
 173 | 	return res, nil
 174 | }
```

#### [`cursor_write`](../../xitdb/cursor.odin#L185-L189) — `DEPTH 2` (`L185–L189`)

```odin
 185 | cursor_write :: proc(c: ^Write_Cursor, data: Writeable_Data) -> Error {
 186 | 	next := cursor_write_path(c, []Path_Part{Write_Data{data = data}}) or_return  // <== [calls cursor_write_path]
 187 | 	c.slot_ptr = next.slot_ptr
 188 | 	return nil
 189 | }
```

### `xitdb/database.odin` (34 procedures · 1011 lines: [`L13–L18`](../../xitdb/database.odin#L13-L18), [`L20–L25`](../../xitdb/database.odin#L20-L25), [`L182–L235`](../../xitdb/database.odin#L182-L235), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L259–L266`](../../xitdb/database.odin#L259-L266), [`L268–L270`](../../xitdb/database.odin#L268-L270), [`L272–L280`](../../xitdb/database.odin#L272-L280), [`L283–L298`](../../xitdb/database.odin#L283-L298), [`L302–L306`](../../xitdb/database.odin#L302-L306), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L337–L341`](../../xitdb/database.odin#L337-L341), [`L343–L362`](../../xitdb/database.odin#L343-L362), [`L364–L368`](../../xitdb/database.odin#L364-L368), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L379–L382`](../../xitdb/database.odin#L379-L382), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414), [`L416–L421`](../../xitdb/database.odin#L416-L421), [`L423–L438`](../../xitdb/database.odin#L423-L438), [`L440–L460`](../../xitdb/database.odin#L440-L460), [`L462–L468`](../../xitdb/database.odin#L462-L468), [`L470–L482`](../../xitdb/database.odin#L470-L482), [`L484–L489`](../../xitdb/database.odin#L484-L489), [`L491–L501`](../../xitdb/database.odin#L491-L501), [`L503–L515`](../../xitdb/database.odin#L503-L515), [`L517–L528`](../../xitdb/database.odin#L517-L528), [`L530–L535`](../../xitdb/database.odin#L530-L535), [`L552–L619`](../../xitdb/database.odin#L552-L619), [`L621–L1382`](../../xitdb/database.odin#L621-L1382), [`L1384–L1395`](../../xitdb/database.odin#L1384-L1395), [`L1397–L1450`](../../xitdb/database.odin#L1397-L1450), [`L1452–L1483`](../../xitdb/database.odin#L1452-L1483), [`L1485–L1533`](../../xitdb/database.odin#L1485-L1533))

#### [`transaction_is_root_position`](../../xitdb/database.odin#L13-L18) — `DEPTH 4` (`L13–L18`)

```odin
  13 | transaction_is_root_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  14 | 	if t == nil || pos == nil || t.root_position == nil {
  15 | 		return false
  16 | 	}
  17 | 	return pos.? == t.root_position.?
  18 | }
```

#### [`transaction_is_scratch_position`](../../xitdb/database.odin#L20-L25) — `DEPTH 4` (`L20–L25`)

```odin
  20 | transaction_is_scratch_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  21 | 	if t == nil || pos == nil || t.scratch_position == nil {
  22 | 		return false
  23 | 	}
  24 | 	return pos.? == t.scratch_position.?
  25 | }
```

#### [`database_init`](../../xitdb/database.odin#L182-L235) — `ENTRY POINT` (`L182–L235`)

```odin
 182 | database_init :: proc(core: ^Core, hasher := Hasher{}) -> (db: Database, err: Error) {
 183 | 	h := hasher
 184 | 	if h.hash_proc == nil && h.hash_size == 0 {
 185 | 		h = sha1_hasher()  // <== [calls sha1_hasher]
 186 | 	}
 187 | 
 188 | 	// If buffered file, clear any stale buffer bytes before opening.
 189 | 	#partial switch &bf in core {
 190 | 	case Core_Buffered_File:
 191 | 		clear(&bf.memory.buf)
 192 | 		bf.flushed_len = 0
 193 | 		bf.memory_pos = 0
 194 | 		bf.pos = 0
 195 | 		bf.file_len = nil
 196 | 	}
 197 | 
 198 | 	db.core = core
 199 | 	db.hasher = h
 200 | 	db.tx_start = nil
 201 | 	db.transaction = nil
 202 | 
 203 | 	core_seek_to(core, 0) or_return  // <== [calls core_seek_to]
 204 | 	length := core_length(core) or_return  // <== [calls core_length]
 205 | 
 206 | 	if length == 0 {
 207 | 		file_id := h.file_id
 208 | 		if file_id == 0 {
 209 | 			file_id = _random_u64()  // <== [calls _random_u64]
 210 | 		}
 211 | 		digest_len := h.hash_size
 212 | 		if digest_len == 0 {
 213 | 			digest_len = 20
 214 | 		}
 215 | 		db.header = Header{
 216 | 			file_id      = file_id,
 217 | 			hash_id      = h.id,
 218 | 			hash_size    = digest_len,
 219 | 			version      = VERSION,
 220 | 			padding      = 0,
 221 | 			magic_number = MAGIC_NUMBER,
 222 | 		}
 223 | 		header_write(db.header, core) or_return  // <== [calls header_write]
 224 | 		rh_bytes := root_header_to_bytes(Root_Header{file_size = 0, root = Slot{}})  // <== [calls root_header_to_bytes]
 225 | 		core_write_all(core, rh_bytes[:]) or_return  // <== [calls core_write_all]
 226 | 		database_commit_root(&db, Slot{}, 0) or_return  // <== [calls database_commit_root]
 227 | 		core_sync(core) or_return  // <== [calls core_sync]
 228 | 	} else {
 229 | 		db.header = database_read_and_validate_header(&db) or_return  // <== [calls database_read_and_validate_header]
 230 | 		_ = database_committed_size(&db) or_return  // <== [calls database_committed_size]
 231 | 	}
 232 | 
 233 | 	db.tx_start = nil
 234 | 	return db, nil
 235 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 1` (`L237–L244`)

```odin
 237 | @(private)
 238 | _random_u64 :: proc() -> u64 {
 239 | 	v := rand.uint64()
 240 | 	if v == 0 {
 241 | 		v = 1
 242 | 	}
 243 | 	return v
 244 | }
```

#### [`database_digest_buf`](../../xitdb/database.odin#L259-L266) — `DEPTH 2` (`L259–L266`)

```odin
 259 | database_digest_buf :: proc(db: ^Database, data: []u8, buf: []u8) -> []u8 {
 260 | 	hsize := int(db.header.hash_size)
 261 | 	out := buf[:hsize] if hsize <= len(buf) else make([]u8, hsize, context.temp_allocator)
 262 | 	if db.hasher.hash_proc != nil {
 263 | 		db.hasher.hash_proc(data, out, db.hasher.user_data)
 264 | 	}
 265 | 	return out
 266 | }
```

#### [`database_digest_string_buf`](../../xitdb/database.odin#L268-L270) — `DEPTH 1` (`L268–L270`)

```odin
 268 | database_digest_string_buf :: proc(db: ^Database, s: string, buf: []u8) -> []u8 {
 269 | 	return database_digest_buf(db, transmute([]u8)s, buf)  // <== [calls database_digest_buf]
 270 | }
```

#### [`database_read_and_validate_header`](../../xitdb/database.odin#L272-L280) — `DEPTH 1` (`L272–L280`)

```odin
 272 | database_read_and_validate_header :: proc(db: ^Database) -> (res: Header, err: Error) {
 273 | 	core_seek_to(db.core, 0) or_return  // <== [calls core_seek_to]
 274 | 	header := header_read(db.core) or_return  // <== [calls header_read]
 275 | 	header_validate(header) or_return  // <== [calls header_validate]
 276 | 	if db.hasher.hash_size != 0 && header.hash_size != db.hasher.hash_size {
 277 | 		return {}, .Invalid_Hash_Size
 278 | 	}
 279 | 	return header, nil
 280 | }
```

#### [`database_root_cursor`](../../xitdb/database.odin#L283-L298) — `DEPTH 1` (`L283–L298`)

```odin
 283 | database_root_cursor :: proc(db: ^Database) -> Write_Cursor {
 284 | 	root, err := database_read_root_slot(db)  // <== [calls database_read_root_slot]
 285 | 	if err != nil {
 286 | 		root = Slot{}
 287 | 	}
 288 | 	return Write_Cursor{
 289 | 		read_cursor = Read_Cursor{
 290 | 			slot_ptr = Slot_Pointer{
 291 | 				position = i64(ROOT_HEADER_START),
 292 | 				slot     = root,
 293 | 			},
 294 | 			db        = db,
 295 | 			frozen_at = 0,
 296 | 		},
 297 | 	}
 298 | }
```

#### [`database_run_context`](../../xitdb/database.odin#L302-L306) — `ENTRY POINT` (`L302–L306`)

```odin
 302 | database_run_context :: proc(db: ^Database, fn: Context_Function, user_data: rawptr = nil) -> Error {
 303 | 	rc := database_root_cursor(db)  // <== [calls database_root_cursor]
 304 | 	_, err := cursor_write_path(&rc, []Path_Part{Context{function = fn, user_data = user_data}})  // <== [calls cursor_write_path]
 305 | 	return err
 306 | }
```

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 2` (`L319–L334`)

```odin
 319 | @(private)
 320 | _database_committed_size_with_header :: proc(db: ^Database, header: Root_Header) -> (committed_size: i64, file_size: i64, err: Error) {
 321 | 	minimum_size := i64(ROOT_HEADER_END + ROOT_TRAILER_LENGTH)
 322 | 	if header.file_size < minimum_size {
 323 | 		return 0, 0, .Invalid_Database
 324 | 	}
 325 | 	file_size = core_length(db.core) or_return  // <== [calls core_length]
 326 | 	if file_size < header.file_size {
 327 | 		return 0, 0, .Truncated_Database
 328 | 	}
 329 | 	trailer := database_read_root_trailer(db, header.file_size) or_return  // <== [calls database_read_root_trailer]
 330 | 	if trailer.root != header.root {
 331 | 		return 0, 0, .Invalid_Database
 332 | 	}
 333 | 	return header.file_size, file_size, nil
 334 | }
```

#### [`database_committed_size`](../../xitdb/database.odin#L337-L341) — `DEPTH 1` (`L337–L341`)

```odin
 337 | database_committed_size :: proc(db: ^Database) -> (res: i64, err: Error) {
 338 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 339 | 	committed_size, _ := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 340 | 	return committed_size, nil
 341 | }
```

#### [`_database_truncate_with_header`](../../xitdb/database.odin#L343-L362) — `DEPTH 3` (`L343–L362`)

```odin
 343 | @(private)
 344 | _database_truncate_with_header :: proc(db: ^Database, header: Root_Header) -> (final_size: i64, err: Error) {
 345 | 	committed_size, file_size := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 346 | 	active := db.transaction
 347 | 	if active != nil {
 348 | 		if fa, ok := active.frozen_at.?; ok && fa > committed_size {
 349 | 			if file_size > fa {
 350 | 				core_set_length(db.core, fa) or_return  // <== [calls core_set_length]
 351 | 			}
 352 | 			commit_id := _random_u64()  // <== [calls _random_u64]
 353 | 			database_commit_root(db, header.root, commit_id) or_return  // <== [calls database_commit_root]
 354 | 			core_sync(db.core) or_return  // <== [calls core_sync]
 355 | 			return core_length(db.core)  // <== [calls core_length]
 356 | 		}
 357 | 	}
 358 | 	if file_size > committed_size {
 359 | 		core_set_length(db.core, committed_size) or_return  // <== [calls core_set_length]
 360 | 	}
 361 | 	return committed_size, nil
 362 | }
```

#### [`database_truncate`](../../xitdb/database.odin#L364-L368) — `DEPTH 2` (`L364–L368`)

```odin
 364 | database_truncate :: proc(db: ^Database) -> Error {
 365 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 366 | 	_, err := _database_truncate_with_header(db, header)  // <== [calls _database_truncate_with_header]
 367 | 	return err
 368 | }
```

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 2` (`L370–L377`)

```odin
 370 | database_read_root_header :: proc(db: ^Database) -> (res: Root_Header, err: Error) {
 371 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 372 | 	b: [ROOT_HEADER_LENGTH]u8
 373 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 374 | 	header := root_header_from_bytes(b)  // <== [calls root_header_from_bytes]
 375 | 	tag_validate(header.root.tag) or_return  // <== [calls tag_validate]
 376 | 	return header, nil
 377 | }
```

#### [`database_read_root_slot`](../../xitdb/database.odin#L379-L382) — `DEPTH 1` (`L379–L382`)

```odin
 379 | database_read_root_slot :: proc(db: ^Database) -> (res: Slot, err: Error) {
 380 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 381 | 	return header.root, nil
 382 | }
```

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 3` (`L384–L398`)

```odin
 384 | database_read_root_trailer :: proc(db: ^Database, end: i64) -> (res: Root_Trailer, err: Error) {
 385 | 	if end < ROOT_TRAILER_LENGTH {
 386 | 		return {}, .Invalid_Database
 387 | 	}
 388 | 	trailer_pos := end - ROOT_TRAILER_LENGTH
 389 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 390 | 	b: [ROOT_TRAILER_LENGTH]u8
 391 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 392 | 	trailer := root_trailer_from_bytes(b)  // <== [calls root_trailer_from_bytes]
 393 | 	if trailer.checksum != compute_root_trailer_checksum(db.header.file_id, trailer_pos, trailer.root, trailer.commit_id) {  // <== [calls compute_root_trailer_checksum]
 394 | 		return {}, .Invalid_Database
 395 | 	}
 396 | 	tag_validate(trailer.root.tag) or_return  // <== [calls tag_validate]
 397 | 	return trailer, nil
 398 | }
```

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 1` (`L400–L407`)

```odin
 400 | database_commit_root :: proc(db: ^Database, root: Slot, commit_id: u64) -> Error {
 401 | 	trailer_pos := core_length(db.core) or_return  // <== [calls core_length]
 402 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 403 | 	trailer := root_trailer_to_bytes(new_root_trailer(db.header.file_id, trailer_pos, root, commit_id))  // <== [calls root_trailer_to_bytes, new_root_trailer]
 404 | 	core_write_all(db.core, trailer[:]) or_return  // <== [calls core_write_all]
 405 | 	core_sync(db.core) or_return  // <== [calls core_sync]
 406 | 	return database_write_root_header(db, root)  // <== [calls database_write_root_header]
 407 | }
```

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 2` (`L409–L414`)

```odin
 409 | database_write_root_header :: proc(db: ^Database, root: Slot) -> Error {
 410 | 	file_size := core_length(db.core) or_return  // <== [calls core_length]
 411 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 412 | 	header := root_header_to_bytes(Root_Header{file_size = file_size, root = root})  // <== [calls root_header_to_bytes]
 413 | 	return core_write_all(db.core, header[:])  // <== [calls core_write_all]
 414 | }
```

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 2` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

#### [`init_tag`](../../xitdb/database.odin#L423-L438) — `DEPTH 2` (`L423–L438`)

```odin
 423 | init_tag :: proc(part: Path_Part) -> (res: Tag, err: bool) {
 424 | 	#partial switch p in part {
 425 | 	case Array_List_Init:
 426 | 		return .Array_List, true
 427 | 	case Linked_Array_List_Init:
 428 | 		return .Linked_Array_List, true
 429 | 	case Hash_Map_Init:
 430 | 		if p.counted {
 431 | 			return (.Counted_Hash_Set if p.set else .Counted_Hash_Map), true
 432 | 		}
 433 | 		return (.Hash_Set if p.set else .Hash_Map), true
 434 | 	case Sorted_Map_Init:
 435 | 		return (.Sorted_Set if p.set else .Sorted_Map), true
 436 | 	}
 437 | 	return .None, false
 438 | }
```

#### [`init_part_for`](../../xitdb/database.odin#L440-L460) — `DEPTH 3` (`L440–L460`)

```odin
 440 | init_part_for :: proc(tag: Tag) -> (res: Path_Part, err: bool) {
 441 | 	#partial switch tag {
 442 | 	case .Array_List:
 443 | 		return Array_List_Init{}, true
 444 | 	case .Linked_Array_List:
 445 | 		return Linked_Array_List_Init{}, true
 446 | 	case .Hash_Map:
 447 | 		return Hash_Map_Init{counted = false, set = false}, true
 448 | 	case .Hash_Set:
 449 | 		return Hash_Map_Init{counted = false, set = true}, true
 450 | 	case .Counted_Hash_Map:
 451 | 		return Hash_Map_Init{counted = true, set = false}, true
 452 | 	case .Counted_Hash_Set:
 453 | 		return Hash_Map_Init{counted = true, set = true}, true
 454 | 	case .Sorted_Map:
 455 | 		return Sorted_Map_Init{set = false}, true
 456 | 	case .Sorted_Set:
 457 | 		return Sorted_Map_Init{set = true}, true
 458 | 	}
 459 | 	return nil, false
 460 | }
```

#### [`database_is_old`](../../xitdb/database.odin#L462-L468) — `DEPTH 4` (`L462–L468`)

```odin
 462 | database_is_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: bool, err: Error) {
 463 | 	tx_s, ok := db.tx_start.?
 464 | 	if !ok {
 465 | 		return false, .Expected_Tx_Start
 466 | 	}
 467 | 	return ptr < max(tx_s, frozen_at), nil
 468 | }
```

#### [`database_copy_index_block_if_old`](../../xitdb/database.odin#L470-L482) — `DEPTH 5` (`L470–L482`)

```odin
 470 | database_copy_index_block_if_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: i64, err: Error) {
 471 | 	old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 472 | 	if !old {
 473 | 		return ptr, nil
 474 | 	}
 475 | 	index_block: [INDEX_BLOCK_SIZE]u8
 476 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 477 | 	core_read_exact(db.core, index_block[:]) or_return  // <== [calls core_read_exact]
 478 | 	next_ptr := core_length(db.core) or_return  // <== [calls core_length]
 479 | 	core_seek_to(db.core, next_ptr) or_return  // <== [calls core_seek_to]
 480 | 	core_write_all(db.core, index_block[:]) or_return  // <== [calls core_write_all]
 481 | 	return next_ptr, nil
 482 | }
```

#### [`database_check_hash`](../../xitdb/database.odin#L484-L489) — `DEPTH 5` (`L484–L489`)

```odin
 484 | database_check_hash :: proc(db: ^Database, h: []u8) -> (res: []u8, err: Error) {
 485 | 	if len(h) != int(db.header.hash_size) {
 486 | 		return nil, .Invalid_Hash_Size
 487 | 	}
 488 | 	return h, nil
 489 | }
```

#### [`database_check_hash_target`](../../xitdb/database.odin#L491-L501) — `DEPTH 4` (`L491–L501`)

```odin
 491 | database_check_hash_target :: proc(db: ^Database, target: Hash_Map_Get_Target) -> (res: []u8, err: Error) {
 492 | 	switch t in target {
 493 | 	case Hash_Map_Get_Value:
 494 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 495 | 	case Hash_Map_Get_Key:
 496 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 497 | 	case Hash_Map_Get_KV_Pair:
 498 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 499 | 	}
 500 | 	return nil, .Invalid_Hash_Size
 501 | }
```

#### [`database_check_frozen_slot`](../../xitdb/database.odin#L503-L515) — `DEPTH 3` (`L503–L515`)

```odin
 503 | database_check_frozen_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer) -> Error {
 504 | 	active := db.transaction
 505 | 	if active != nil {
 506 | 		if fa, ok := active.frozen_at.?; ok {
 507 | 			if pos, pok := slot_ptr.position.?; pok {
 508 | 				if pos < fa && !transaction_is_root_position(active, slot_ptr.position) {  // <== [calls transaction_is_root_position]
 509 | 					return .Frozen_Slot
 510 | 				}
 511 | 			}
 512 | 		}
 513 | 	}
 514 | 	return nil
 515 | }
```

#### [`database_copy_collection_if_frozen`](../../xitdb/database.odin#L517-L528) — `DEPTH 4` (`L517–L528`)

```odin
 517 | database_copy_collection_if_frozen :: proc(db: ^Database, slot_ptr: Slot_Pointer, init_part: Path_Part, frozen_at: i64) -> (res: Slot_Pointer, err: Error) {
 518 | 	if db.transaction != nil {
 519 | 		fa := frozen_at
 520 | 		if tfa, ok := db.transaction.frozen_at.?; ok && tfa > fa {
 521 | 			fa = tfa
 522 | 		}
 523 | 		if fa > 0 && slot_ptr.slot.value < fa {
 524 | 			return read_slot_pointer(db, .Read_Write, []Path_Part{init_part}, 0, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 525 | 		}
 526 | 	}
 527 | 	return slot_ptr, nil
 528 | }
```

#### [`database_kv_key_offset`](../../xitdb/database.odin#L530-L535) — `DEPTH 4` (`L530–L535`)

```odin
 530 | database_kv_key_offset :: proc(db: ^Database, tag: Tag) -> i64 {
 531 | 	if tag == .KV_Pair {
 532 | 		return i64(db.header.hash_size)
 533 | 	}
 534 | 	return 0
 535 | }
```

#### [`read_slot_pointer`](../../xitdb/database.odin#L552-L619) — `DEPTH 2` (`L552–L619`)

```odin
 552 | read_slot_pointer :: proc(
 553 | 	db: ^Database,
 554 | 	write_mode: Write_Mode,
 555 | 	path: []Path_Part,
 556 | 	path_i: int,
 557 | 	slot_ptr: Slot_Pointer,
 558 | 	frozen_at: i64,
 559 | ) -> (res: Slot_Pointer, err: Error) {
 560 | 	if path_i == len(path) {
 561 | 		if write_mode == .Read_Only && slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
 562 | 			return {}, .Key_Not_Found
 563 | 		}
 564 | 		return slot_ptr, nil
 565 | 	}
 566 | 	if write_mode == .Read_Write {
 567 | 		database_check_frozen_slot(db, slot_ptr) or_return  // <== [calls database_check_frozen_slot]
 568 | 	}
 569 | 	part := path[path_i]
 570 | 
 571 | 	// Every write that starts at the root is a transaction.
 572 | 	if is_root(slot_ptr) {  // <== [calls is_root]
 573 | 		root_header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 574 | 		root := root_header.root
 575 | 
 576 | 		if write_mode == .Read_Only {
 577 | 			return read_slot_pointer(db, write_mode, path, path_i, Slot_Pointer{position = nil, slot = root}, frozen_at)
 578 | 		}
 579 | 
 580 | 		// Initializing an already-initialized root is free.
 581 | 		if len(path) - path_i == 1 && root.tag != .None {
 582 | 			if tag, ok := init_tag(part); ok && tag == root.tag {  // <== [calls init_tag]
 583 | 				_ = _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 584 | 				return Slot_Pointer{position = i64(ROOT_HEADER_START), slot = root}, nil
 585 | 			}
 586 | 		}
 587 | 
 588 | 		scratch_pos := _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 589 | 		db.tx_start = scratch_pos
 590 | 		defer db.tx_start = nil
 591 | 
 592 | 		if db.transaction != nil {
 593 | 			db.transaction.root_position = scratch_pos
 594 | 			db.transaction.scratch_position = scratch_pos
 595 | 		}
 596 | 
 597 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 598 | 		core_write_slot(db.core, root) or_return  // <== [calls core_write_slot]
 599 | 		root_ptr := Slot_Pointer{position = scratch_pos, slot = root}
 600 | 
 601 | 		if init_p, ok := init_part_for(root.tag); ok {  // <== [calls init_part_for]
 602 | 			root_ptr = read_slot_pointer(db, write_mode, []Path_Part{init_p}, 0, root_ptr, frozen_at) or_return
 603 | 		}
 604 | 
 605 | 		result := read_slot_pointer(db, write_mode, path, path_i, root_ptr, frozen_at) or_return
 606 | 
 607 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 608 | 		next_root := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 609 | 		commit_id := _random_u64()  // <== [calls _random_u64]
 610 | 		database_commit_root(db, next_root, commit_id) or_return  // <== [calls database_commit_root]
 611 | 
 612 | 		if rpos, ok := result.position.?; ok && rpos == scratch_pos {
 613 | 			result = Slot_Pointer{position = i64(ROOT_HEADER_START), slot = next_root}
 614 | 		}
 615 | 		return result, nil
 616 | 	}
 617 | 
 618 | 	return _exec_path_part(db, part, write_mode, path, path_i, slot_ptr, frozen_at)  // <== [calls _exec_path_part]
 619 | }
```

#### [`_exec_path_part`](../../xitdb/database.odin#L621-L1382) — `DEPTH 3` (`L621–L1382`) — Active `Path_Part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`

```odin
 621 | @(private)
 622 | _exec_path_part :: proc(
 623 | 	db: ^Database,
 624 | 	part: Path_Part,
 625 | 	write_mode: Write_Mode,
 626 | 	path: []Path_Part,
 627 | 	path_i: int,
 628 | 	slot_ptr: Slot_Pointer,
 629 | 	frozen_at: i64,
 630 | ) -> (res: Slot_Pointer, err: Error) {
 631 | 	slot_ptr := slot_ptr
 632 | 
 633 | 	switch p in part {
 634 | 	case Array_List_Init:
 635 | 		if write_mode == .Read_Only {
 636 | 			return {}, .Write_Not_Allowed
 637 | 		}
 638 | 		position, pos_ok := slot_ptr.position.?
 639 | 		if !pos_ok {
 640 | 			return {}, .Cursor_Not_Writeable
 641 | 		}
 642 | 		#partial switch slot_ptr.slot.tag {
 643 | 		case .None:
 644 | 			array_list_start := core_length(db.core) or_return  // <== [calls core_length]
 645 | 			core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 646 | 			array_list_ptr := array_list_start + ARRAY_LIST_HEADER_LENGTH
 647 | 			al_header := array_list_header_to_bytes(Array_List_Header{ptr = array_list_ptr, size = 0})  // <== [calls array_list_header_to_bytes]
 648 | 			core_write_all(db.core, al_header[:]) or_return  // <== [calls core_write_all]
 649 | 			empty_block: [INDEX_BLOCK_SIZE]u8
 650 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 651 | 			next_slot_ptr := Slot_Pointer{
 652 | 				position = position,
 653 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 654 | 			}
 655 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 656 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 657 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 658 | 
 659 | 		case .Array_List:
 660 | 			array_list_start := slot_ptr.slot.value
 661 | 			old := database_is_old(db, array_list_start, frozen_at) or_return  // <== [calls database_is_old]
 662 | 			if old {
 663 | 				core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 664 | 				hb: [ARRAY_LIST_HEADER_LENGTH]u8
 665 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 666 | 				header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 667 | 				core_seek_to(db.core, header.ptr) or_return  // <== [calls core_seek_to]
 668 | 				idx_block: [INDEX_BLOCK_SIZE]u8
 669 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
 670 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
 671 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
 672 | 				next_ptr := new_start + ARRAY_LIST_HEADER_LENGTH
 673 | 				header = array_list_header_with_ptr(header, next_ptr)  // <== [calls array_list_header_with_ptr]
 674 | 				nhb := array_list_header_to_bytes(header)  // <== [calls array_list_header_to_bytes]
 675 | 				core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 676 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
 677 | 				array_list_start = new_start
 678 | 			}
 679 | 			next_slot_ptr := Slot_Pointer{
 680 | 				position = position,
 681 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 682 | 			}
 683 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 684 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 685 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 686 | 
 687 | 		case:
 688 | 			return {}, .Unexpected_Tag
 689 | 		}
   ... | 	// ... [lines 690–690: untouched Path_Part arms omitted] ...
 691 | 	case Array_List_Get:
 692 | 		#partial switch slot_ptr.slot.tag {
 693 | 		case .None:
 694 | 			return {}, .Key_Not_Found
 695 | 		case .Array_List:
 696 | 		case:
 697 | 			return {}, .Unexpected_Tag
 698 | 		}
 699 | 		if write_mode == .Read_Write {
 700 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 701 | 		}
 702 | 		next_array_list_start := slot_ptr.slot.value
 703 | 		index := p.index
 704 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 705 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 706 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 707 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 708 | 		if index >= header.size || index < -header.size {
 709 | 			return {}, .Key_Not_Found
 710 | 		}
 711 | 		key := (header.size + index) if index < 0 else index
 712 | 		shift := radix_shift(header.size - 1)  // <== [calls radix_shift]
 713 | 		final_slot_ptr := read_array_list_slot(db, header.ptr, key, shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 714 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, final_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 715–715: untouched Path_Part arms omitted] ...
 716 | 	case Array_List_Append:
 717 | 		if write_mode == .Read_Only {
 718 | 			return {}, .Write_Not_Allowed
 719 | 		}
 720 | 		if slot_ptr.slot.tag != .Array_List {
 721 | 			return {}, .Unexpected_Tag
 722 | 		}
 723 | 		slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 724 | 		next_array_list_start := slot_ptr.slot.value
 725 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 726 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 727 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 728 | 		orig_header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 729 | 		append_res := read_array_list_slot_append(db, orig_header, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot_append]
 730 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 731 | 		nhb := array_list_header_to_bytes(append_res.header)  // <== [calls array_list_header_to_bytes]
 732 | 		core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 733 | 		if db.transaction != nil && transaction_is_scratch_position(db.transaction, slot_ptr.position) {  // <== [calls transaction_is_scratch_position]
 734 | 			db.transaction.root_position = append_res.slot_ptr.position
 735 | 		}
 736 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, append_res.slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 737–756: untouched Path_Part arms omitted] ...
 757 | 	case Linked_Array_List_Init:
 758 | 		if write_mode == .Read_Only {
 759 | 			return {}, .Write_Not_Allowed
 760 | 		}
 761 | 		position, pos_ok := slot_ptr.position.?
 762 | 		if !pos_ok {
 763 | 			return {}, .Cursor_Not_Writeable
 764 | 		}
 765 | 		#partial switch slot_ptr.slot.tag {
 766 | 		case .None:
 767 | 			root_ptr := write_btree_node(db, BTree_Node{kind = .Leaf, num = 0}) or_return  // <== [calls write_btree_node]
 768 | 			header_ptr := core_length(db.core) or_return  // <== [calls core_length]
 769 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 770 | 			hb := btree_header_to_bytes(BTree_Header{root_ptr = root_ptr, size = 0})  // <== [calls btree_header_to_bytes]
 771 | 			core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
 772 | 			next_slot_ptr := Slot_Pointer{
 773 | 				position = position,
 774 | 				slot     = Slot{value = header_ptr, tag = .Linked_Array_List},
 775 | 			}
 776 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 777 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 778 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 779 | 
 780 | 		case .Linked_Array_List:
 781 | 			header_ptr := slot_ptr.slot.value
 782 | 			old := database_is_old(db, header_ptr, frozen_at) or_return  // <== [calls database_is_old]
 783 | 			if old {
 784 | 				core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 785 | 				hb: [BTREE_HEADER_LENGTH]u8
 786 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 787 | 				new_ptr := core_length(db.core) or_return  // <== [calls core_length]
 788 | 				core_seek_to(db.core, new_ptr) or_return  // <== [calls core_seek_to]
 789 | 				core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
 790 | 				header_ptr = new_ptr
 791 | 			}
 792 | 			next_slot_ptr := Slot_Pointer{
 793 | 				position = position,
 794 | 				slot     = Slot{value = header_ptr, tag = .Linked_Array_List},
 795 | 			}
 796 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 797 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 798 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 799 | 
 800 | 		case:
 801 | 			return {}, .Unexpected_Tag
 802 | 		}
   ... | 	// ... [lines 803–836: untouched Path_Part arms omitted] ...
 837 | 	case Linked_Array_List_Append:
 838 | 		if write_mode == .Read_Only {
 839 | 			return {}, .Write_Not_Allowed
 840 | 		}
 841 | 		if slot_ptr.slot.tag != .Linked_Array_List {
 842 | 			return {}, .Unexpected_Tag
 843 | 		}
 844 | 		slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Linked_Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 845 | 		header_ptr := slot_ptr.slot.value
 846 | 		core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 847 | 		hb: [BTREE_HEADER_LENGTH]u8
 848 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 849 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 850 | 		res := btree_insert(db, header.root_ptr, header.size, frozen_at) or_return  // <== [calls btree_insert]
 851 | 		new_root_ptr := btree_grow_root(db, res) or_return  // <== [calls btree_grow_root]
 852 | 		core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 853 | 		nhb := btree_header_to_bytes(BTree_Header{root_ptr = new_root_ptr, size = header.size + 1})  // <== [calls btree_header_to_bytes]
 854 | 		core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 855 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, Slot_Pointer{position = res.value_position, slot = Slot{}}, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 856–983: untouched Path_Part arms omitted] ...
 984 | 	case Hash_Map_Init:
 985 | 		if write_mode == .Read_Only {
 986 | 			return {}, .Write_Not_Allowed
 987 | 		}
 988 | 		tag: Tag
 989 | 		if p.counted {
 990 | 			tag = .Counted_Hash_Set if p.set else .Counted_Hash_Map
 991 | 		} else {
 992 | 			tag = .Hash_Set if p.set else .Hash_Map
 993 | 		}
 994 | 		position, pos_ok := slot_ptr.position.?
 995 | 		if !pos_ok {
 996 | 			return {}, .Cursor_Not_Writeable
 997 | 		}
 998 | 		#partial switch slot_ptr.slot.tag {
 999 | 		case .None:
1000 | 			map_start := core_length(db.core) or_return  // <== [calls core_length]
1001 | 			core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1002 | 			if p.counted {
1003 | 				core_write_long(db.core, 0) or_return  // <== [calls core_write_long]
1004 | 			}
1005 | 			empty_block: [INDEX_BLOCK_SIZE]u8
1006 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
1007 | 			next_slot_ptr := Slot_Pointer{
1008 | 				position = position,
1009 | 				slot     = Slot{value = map_start, tag = tag},
1010 | 			}
1011 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1012 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1013 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1014 | 
1015 | 		case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
1016 | 			if p.counted {
1017 | 				#partial switch slot_ptr.slot.tag {
1018 | 				case .Counted_Hash_Map, .Counted_Hash_Set:
1019 | 				case:
1020 | 					return {}, .Unexpected_Tag
1021 | 				}
1022 | 			} else {
1023 | 				#partial switch slot_ptr.slot.tag {
1024 | 				case .Hash_Map, .Hash_Set:
1025 | 				case:
1026 | 					return {}, .Unexpected_Tag
1027 | 				}
1028 | 			}
1029 | 			map_start := slot_ptr.slot.value
1030 | 			old := database_is_old(db, map_start, frozen_at) or_return  // <== [calls database_is_old]
1031 | 			if old {
1032 | 				core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1033 | 				map_count: i64 = 0
1034 | 				if p.counted {
1035 | 					map_count = core_read_long(db.core) or_return  // <== [calls core_read_long]
1036 | 				}
1037 | 				idx_block: [INDEX_BLOCK_SIZE]u8
1038 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
1039 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
1040 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
1041 | 				if p.counted {
1042 | 					core_write_long(db.core, map_count) or_return  // <== [calls core_write_long]
1043 | 				}
1044 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
1045 | 				map_start = new_start
1046 | 			}
1047 | 			next_slot_ptr := Slot_Pointer{
1048 | 				position = position,
1049 | 				slot     = Slot{value = map_start, tag = tag},
1050 | 			}
1051 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1052 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1053 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1054 | 
1055 | 		case:
1056 | 			return {}, .Unexpected_Tag
1057 | 		}
   ... | 	// ... [lines 1058–1058: untouched Path_Part arms omitted] ...
1059 | 	case Hash_Map_Get:
1060 | 		counted := false
1061 | 		#partial switch slot_ptr.slot.tag {
1062 | 		case .None:
1063 | 			return {}, .Key_Not_Found
1064 | 		case .Hash_Map, .Hash_Set:
1065 | 		case .Counted_Hash_Map, .Counted_Hash_Set:
1066 | 			counted = true
1067 | 		case:
1068 | 			return {}, .Unexpected_Tag
1069 | 		}
1070 | 		if write_mode == .Read_Write {
1071 | 			is_set := slot_ptr.slot.tag == .Hash_Set || slot_ptr.slot.tag == .Counted_Hash_Set
1072 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Hash_Map_Init{counted = counted, set = is_set}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
1073 | 		}
1074 | 		index_pos := (slot_ptr.slot.value + 8) if counted else slot_ptr.slot.value
1075 | 		key_hash := database_check_hash_target(db, p.target) or_return  // <== [calls database_check_hash_target]
1076 | 		res := read_map_slot(db, index_pos, key_hash, 0, write_mode, p.target, frozen_at) or_return  // <== [calls read_map_slot]
1077 | 		if write_mode == .Read_Write && counted && res.is_empty {
1078 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1079 | 			map_count := core_read_long(db.core) or_return  // <== [calls core_read_long]
1080 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1081 | 			core_write_long(db.core, map_count + 1) or_return  // <== [calls core_write_long]
1082 | 		}
1083 | 		next_sp := res.slot_ptr
1084 | 		if write_mode == .Read_Write && res.is_empty && next_sp.slot.tag == .KV_Pair {
1085 | 			next_sp.slot.full = true
1086 | 		}
1087 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1088–1126: untouched Path_Part arms omitted] ...
1127 | 	case Sorted_Map_Init:
1128 | 		if write_mode == .Read_Only {
1129 | 			return {}, .Write_Not_Allowed
1130 | 		}
1131 | 		position, pos_ok := slot_ptr.position.?
1132 | 		if !pos_ok {
1133 | 			return {}, .Cursor_Not_Writeable
1134 | 		}
1135 | 		tag: Tag = .Sorted_Set if p.set else .Sorted_Map
1136 | 		#partial switch slot_ptr.slot.tag {
1137 | 		case .None:
1138 | 			root_ptr := write_sorted_node(db, Sorted_Node{kind = .Leaf, num = 0}) or_return  // <== [calls write_sorted_node]
1139 | 			header_ptr := core_length(db.core) or_return  // <== [calls core_length]
1140 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1141 | 			hb := btree_header_to_bytes(BTree_Header{root_ptr = root_ptr, size = 0})  // <== [calls btree_header_to_bytes]
1142 | 			core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
1143 | 			next_slot_ptr := Slot_Pointer{
1144 | 				position = position,
1145 | 				slot     = Slot{value = header_ptr, tag = tag},
1146 | 			}
1147 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1148 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1149 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1150 | 
1151 | 		case .Sorted_Map, .Sorted_Set:
1152 | 			header_ptr := slot_ptr.slot.value
1153 | 			old := database_is_old(db, header_ptr, frozen_at) or_return  // <== [calls database_is_old]
1154 | 			if old {
1155 | 				core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1156 | 				hb: [BTREE_HEADER_LENGTH]u8
1157 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
1158 | 				new_ptr := core_length(db.core) or_return  // <== [calls core_length]
1159 | 				core_seek_to(db.core, new_ptr) or_return  // <== [calls core_seek_to]
1160 | 				core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
1161 | 				header_ptr = new_ptr
1162 | 			}
1163 | 			next_slot_ptr := Slot_Pointer{
1164 | 				position = position,
1165 | 				slot     = Slot{value = header_ptr, tag = tag},
1166 | 			}
1167 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1168 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1169 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1170 | 
1171 | 		case:
1172 | 			return {}, .Unexpected_Tag
1173 | 		}
   ... | 	// ... [lines 1174–1174: untouched Path_Part arms omitted] ...
1175 | 	case Sorted_Map_Get:
1176 | 		#partial switch slot_ptr.slot.tag {
1177 | 		case .None:
1178 | 			return {}, .Key_Not_Found
1179 | 		case .Sorted_Map, .Sorted_Set:
1180 | 		case:
1181 | 			return {}, .Unexpected_Tag
1182 | 		}
1183 | 		key: []u8
1184 | 		switch t in p.target {
1185 | 		case Sorted_Map_Get_Value:
1186 | 			key = t.key
1187 | 		case Sorted_Map_Get_Key:
1188 | 			key = t.key
1189 | 		case Sorted_Map_Get_KV_Pair:
1190 | 			key = t.key
1191 | 		}
1192 | 		if write_mode == .Read_Write {
1193 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Sorted_Map_Init{set = slot_ptr.slot.tag == .Sorted_Set}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
1194 | 		}
1195 | 		header_ptr := slot_ptr.slot.value
1196 | 		core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1197 | 		hb: [BTREE_HEADER_LENGTH]u8
1198 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
1199 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
1200 | 
1201 | 		if write_mode == .Read_Only {
1202 | 			found_maybe := sorted_get(db, header.root_ptr, key) or_return  // <== [calls sorted_get]
1203 | 			found, has_found := found_maybe.?
1204 | 			if !has_found {
1205 | 				return {}, .Key_Not_Found
1206 | 			}
1207 | 			target_slot: Slot_Pointer
1208 | 			if _, is_key := p.target.(Sorted_Map_Get_Key); is_key {
1209 | 				target_slot = Slot_Pointer{position = nil, slot = found.key_slot}
1210 | 			} else {
1211 | 				target_slot = sorted_target_slot(db, found.slot, p.target) or_return  // <== [calls sorted_target_slot]
1212 | 			}
1213 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, target_slot, frozen_at)  // <== [calls read_slot_pointer]
1214 | 		}
1215 | 
1216 | 		_, is_key_target := p.target.(Sorted_Map_Get_Key)
1217 | 		key_only := slot_ptr.slot.tag == .Sorted_Set && is_key_target
1218 | 		res := sorted_put(db, header.root_ptr, key, key_only, frozen_at) or_return  // <== [calls sorted_put]
1219 | 		new_root_ptr := sorted_grow_root(db, res) or_return  // <== [calls sorted_grow_root]
1220 | 		if new_root_ptr != header.root_ptr || res.added {
1221 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1222 | 			new_size := header.size + (1 if res.added else 0)
1223 | 			nhb := btree_header_to_bytes(BTree_Header{root_ptr = new_root_ptr, size = new_size})  // <== [calls btree_header_to_bytes]
1224 | 			core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
1225 | 		}
1226 | 		target_slot: Slot_Pointer
1227 | 		if _, is_val := p.target.(Sorted_Map_Get_Value); is_val && res.added {
1228 | 			target_slot = Slot_Pointer{position = res.entry.value + SLOT_LENGTH, slot = Slot{}}
1229 | 		} else {
1230 | 			target_slot = sorted_target_slot(db, res.entry, p.target) or_return  // <== [calls sorted_target_slot]
1231 | 		}
1232 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, target_slot, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1233–1284: untouched Path_Part arms omitted] ...
1285 | 	case Write_Data:
1286 | 		if write_mode == .Read_Only {
1287 | 			return {}, .Write_Not_Allowed
1288 | 		}
1289 | 		position, pos_ok := slot_ptr.position.?
1290 | 		if !pos_ok {
1291 | 			return {}, .Cursor_Not_Writeable
1292 | 		}
1293 | 		if p.if_empty && !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
1294 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1295 | 		}
1296 | 
1297 | 		slot := _encode_writeable_data(db, slot_ptr, p.data) or_return  // <== [calls _encode_writeable_data]
1298 | 
1299 | 		core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1300 | 		core_write_slot(db.core, slot) or_return  // <== [calls core_write_slot]
1301 | 		next_slot_ptr := Slot_Pointer{position = slot_ptr.position, slot = slot}
1302 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1303–1303: untouched Path_Part arms omitted] ...
1304 | 	case Write_KV_Data:
1305 | 		if write_mode == .Read_Only {
1306 | 			return {}, .Write_Not_Allowed
1307 | 		}
1308 | 		kv_pos := slot_ptr.slot.value
1309 | 		key_slot_pos := kv_pos + database_kv_key_offset(db, slot_ptr.slot.tag)  // <== [calls database_kv_key_offset]
1310 | 		val_slot_pos := key_slot_pos + SLOT_LENGTH
1311 | 
1312 | 		if slot_ptr.slot.full {
1313 | 			if val_slot, val_inline, val_err := _try_encode_inline_data(p.value); val_err != nil {  // <== [calls _try_encode_inline_data]
1314 | 				return {}, val_err
1315 | 			} else if val_inline {
1316 | 				if key_bytes, is_kbytes := _extract_bytes_data(p.key); is_kbytes && !bytes_is_short(key_bytes) {  // <== [calls _extract_bytes_data, bytes_is_short]
1317 | 					if key_bytes.format_tag != nil && len(key_bytes.format_tag) != 2 {
1318 | 						return {}, .Invalid_Format_Tag_Size
1319 | 					}
1320 | 					if db.tx_start == nil {
1321 | 						return {}, .Expected_Tx_Start
1322 | 					}
1323 | 					cur_len := core_length(db.core) or_return  // <== [calls core_length]
1324 | 					has_ft := key_bytes.format_tag != nil
1325 | 					key_payload_len := 8 + len(key_bytes.value) + (2 if has_ft else 0)
1326 | 					if cur_len == val_slot_pos + SLOT_LENGTH && key_payload_len <= 238 {
1327 | 						key_slot := Slot{value = cur_len, tag = .Bytes, full = has_ft}
1328 | 						combined_buf: [256]u8 = ---
1329 | 						out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1330 | 						out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1331 | 						copy(combined_buf[0:SLOT_LENGTH], out_kb[:])
1332 | 						copy(combined_buf[SLOT_LENGTH : SLOT_LENGTH * 2], out_vb[:])
1333 | 						endian.unchecked_put_u64be(combined_buf[18:26], u64(len(key_bytes.value)))
1334 | 						copy(combined_buf[26 : 26 + len(key_bytes.value)], key_bytes.value)
1335 | 						if has_ft {
1336 | 							copy(combined_buf[26 + len(key_bytes.value) : 18 + key_payload_len], key_bytes.format_tag)
1337 | 						}
1338 | 						core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1339 | 						core_write_all(db.core, combined_buf[:18 + key_payload_len]) or_return  // <== [calls core_write_all]
1340 | 						clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1341 | 						return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
1342 | 					}
1343 | 				}
1344 | 			}
1345 | 			key_slot := _encode_writeable_data(db, Slot_Pointer{position = key_slot_pos, slot = Slot{}}, p.key) or_return  // <== [calls _encode_writeable_data]
1346 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1347 | 			slots_buf: [SLOT_LENGTH * 2]u8 = ---
1348 | 			out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1349 | 			out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1350 | 			copy(slots_buf[:SLOT_LENGTH], out_kb[:])
1351 | 			copy(slots_buf[SLOT_LENGTH:], out_vb[:])
1352 | 			core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1353 | 			core_write_all(db.core, slots_buf[:]) or_return  // <== [calls core_write_all]
1354 | 		} else {
1355 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1356 | 			core_seek_to(db.core, val_slot_pos) or_return  // <== [calls core_seek_to]
1357 | 			core_write_slot(db.core, val_slot) or_return  // <== [calls core_write_slot]
1358 | 		}
1359 | 		clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1360 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1361–1361: untouched Path_Part arms omitted] ...
1362 | 	case Context:
1363 | 		if write_mode == .Read_Only {
1364 | 			return {}, .Write_Not_Allowed
1365 | 		}
1366 | 		if path_i != len(path) - 1 {
1367 | 			return {}, .Path_Part_Must_Be_At_End
1368 | 		}
1369 | 		clean_sp := slot_ptr
1370 | 		if clean_sp.slot.tag == .KV_Pair && clean_sp.slot.full {
1371 | 			clean_sp.slot.full = false
1372 | 		}
1373 | 		next_cursor := new_write_cursor(clean_sp, db)  // <== [calls new_write_cursor]
1374 | 		next_cursor.frozen_at = frozen_at
1375 | 		if p.function != nil {
1376 | 			p.function(&next_cursor, p.user_data) or_return
1377 | 		}
1378 | 		return next_cursor.slot_ptr, nil
1379 | 	}
1380 | 
1381 | 	return {}, .Unreachable
1382 | }
```

#### [`_extract_bytes_data`](../../xitdb/database.odin#L1384-L1395) — `DEPTH 4` (`L1384–L1395`)

```odin
1384 | @(private)
1385 | _extract_bytes_data :: #force_inline proc(write_data: Writeable_Data) -> (b: Bytes, ok: bool) {
1386 | 	#partial switch data in write_data {
1387 | 	case string:
1388 | 		return Bytes{value = transmute([]u8)data}, true
1389 | 	case []u8:
1390 | 		return Bytes{value = data}, true
1391 | 	case Bytes:
1392 | 		return data, true
1393 | 	}
1394 | 	return {}, false
1395 | }
```

#### [`_try_encode_inline_data`](../../xitdb/database.odin#L1397-L1450) — `DEPTH 4` (`L1397–L1450`)

```odin
1397 | @(private)
1398 | _try_encode_inline_data :: #force_inline proc(write_data: Writeable_Data) -> (slot: Slot, is_inline: bool, err: Error) {
1399 | 	switch data in write_data {
1400 | 	case nil:
1401 | 		return Slot{full = true}, true, nil
1402 | 	case Slot:
1403 | 		if data.tag == .None {
1404 | 			return slot_with_full(data, true), true, nil  // <== [calls slot_with_full]
1405 | 		}
1406 | 		return data, true, nil
1407 | 	case Uint:
1408 | 		return Slot{value = i64(data.value), tag = .Uint}, true, nil
1409 | 	case u64:
1410 | 		return Slot{value = i64(data), tag = .Uint}, true, nil
1411 | 	case Int:
1412 | 		return Slot{value = data.value, tag = .Int}, true, nil
1413 | 	case i64:
1414 | 		return Slot{value = data, tag = .Int}, true, nil
1415 | 	case Float:
1416 | 		return Slot{value = transmute(i64)data.value, tag = .Float}, true, nil
1417 | 	case f64:
1418 | 		return Slot{value = transmute(i64)data, tag = .Float}, true, nil
1419 | 	case string:
1420 | 		b := Bytes{value = transmute([]u8)data}
1421 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1422 | 			buf: [8]u8
1423 | 			copy(buf[:], b.value)
1424 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1425 | 		}
1426 | 		return {}, false, nil
1427 | 	case []u8:
1428 | 		b := Bytes{value = data}
1429 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1430 | 			buf: [8]u8
1431 | 			copy(buf[:], b.value)
1432 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1433 | 		}
1434 | 		return {}, false, nil
1435 | 	case Bytes:
1436 | 		if data.format_tag != nil && len(data.format_tag) != 2 {
1437 | 			return {}, false, .Invalid_Format_Tag_Size
1438 | 		}
1439 | 		if bytes_is_short(data) {  // <== [calls bytes_is_short]
1440 | 			buf: [8]u8
1441 | 			copy(buf[:], data.value)
1442 | 			if data.format_tag != nil {
1443 | 				copy(buf[6:8], data.format_tag)
1444 | 			}
1445 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes, full = data.format_tag != nil}, true, nil
1446 | 		}
1447 | 		return {}, false, nil
1448 | 	}
1449 | 	return {}, false, nil
1450 | }
```

#### [`_encode_writeable_data`](../../xitdb/database.odin#L1452-L1483) — `DEPTH 4` (`L1452–L1483`)

```odin
1452 | @(private)
1453 | _encode_writeable_data :: proc(db: ^Database, slot_ptr: Slot_Pointer, write_data: Writeable_Data) -> (slot: Slot, err: Error) {
1454 | 	switch data in write_data {
1455 | 	case nil:
1456 | 		slot = Slot{}
1457 | 	case Slot:
1458 | 		slot = data
1459 | 	case Uint:
1460 | 		slot = Slot{value = i64(data.value), tag = .Uint}
1461 | 	case u64:
1462 | 		slot = Slot{value = i64(data), tag = .Uint}
1463 | 	case Int:
1464 | 		slot = Slot{value = data.value, tag = .Int}
1465 | 	case i64:
1466 | 		slot = Slot{value = data, tag = .Int}
1467 | 	case Float:
1468 | 		slot = Slot{value = transmute(i64)data.value, tag = .Float}
1469 | 	case f64:
1470 | 		slot = Slot{value = transmute(i64)data, tag = .Float}
1471 | 	case string:
1472 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = transmute([]u8)data}) or_return  // <== [calls _encode_bytes_slot]
1473 | 	case []u8:
1474 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = data}) or_return  // <== [calls _encode_bytes_slot]
1475 | 	case Bytes:
1476 | 		slot = _encode_bytes_slot(db, slot_ptr, data) or_return  // <== [calls _encode_bytes_slot]
1477 | 	}
1478 | 
1479 | 	if slot.tag == .None {
1480 | 		slot = slot_with_full(slot, true)  // <== [calls slot_with_full]
1481 | 	}
1482 | 	return slot, nil
1483 | }
```

#### [`_encode_bytes_slot`](../../xitdb/database.odin#L1485-L1533) — `DEPTH 5` (`L1485–L1533`)

```odin
1485 | @(private)
1486 | _encode_bytes_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer, data: Bytes) -> (res: Slot, err: Error) {
1487 | 	if data.format_tag != nil && len(data.format_tag) != 2 {
1488 | 		return {}, .Invalid_Format_Tag_Size
1489 | 	}
1490 | 	if bytes_is_short(data) {  // <== [calls bytes_is_short]
1491 | 		buf: [8]u8
1492 | 		copy(buf[:], data.value)
1493 | 		if data.format_tag != nil {
1494 | 			copy(buf[6:8], data.format_tag)
1495 | 		}
1496 | 		uval := endian.unchecked_get_u64be(buf[:])
1497 | 		return Slot{
1498 | 			value = i64(uval),
1499 | 			tag   = .Short_Bytes,
1500 | 			full  = data.format_tag != nil,
1501 | 		}, nil
1502 | 	}
1503 | 	if is_root(slot_ptr) {  // <== [calls is_root]
1504 | 		return {}, .Cursor_Not_Writeable
1505 | 	}
1506 | 	if db.tx_start == nil {
1507 | 		return {}, .Expected_Tx_Start
1508 | 	}
1509 | 	ptr_pos := core_length(db.core) or_return  // <== [calls core_length]
1510 | 	core_seek_to(db.core, ptr_pos) or_return  // <== [calls core_seek_to]
1511 | 	has_ft := data.format_tag != nil
1512 | 	total_len := 8 + len(data.value) + (2 if has_ft else 0)
1513 | 	if total_len <= 256 {
1514 | 		buf: [256]u8 = ---
1515 | 		endian.unchecked_put_u64be(buf[0:8], u64(len(data.value)))
1516 | 		copy(buf[8 : 8 + len(data.value)], data.value)
1517 | 		if has_ft {
1518 | 			copy(buf[8 + len(data.value) : total_len], data.format_tag)
1519 | 		}
1520 | 		core_write_all(db.core, buf[:total_len]) or_return  // <== [calls core_write_all]
1521 | 	} else {
1522 | 		core_write_long(db.core, i64(len(data.value))) or_return  // <== [calls core_write_long]
1523 | 		core_write_all(db.core, data.value) or_return  // <== [calls core_write_all]
1524 | 		if has_ft {
1525 | 			core_write_all(db.core, data.format_tag) or_return  // <== [calls core_write_all]
1526 | 		}
1527 | 	}
1528 | 	return Slot{
1529 | 		value = ptr_pos,
1530 | 		tag   = .Bytes,
1531 | 		full  = has_ft,
1532 | 	}, nil
1533 | }
```

### `xitdb/hamt.odin` (3 procedures · 333 lines: [`L15–L240`](../../xitdb/hamt.odin#L15-L240), [`L345–L383`](../../xitdb/hamt.odin#L345-L383), [`L385–L452`](../../xitdb/hamt.odin#L385-L452))

#### [`read_map_slot`](../../xitdb/hamt.odin#L15-L240) — `DEPTH 4` (`L15–L240`)

```odin
  15 | read_map_slot :: proc(
  16 | 	db: ^Database,
  17 | 	index_pos: i64,
  18 | 	key_hash: []u8,
  19 | 	key_offset: u8,
  20 | 	write_mode: Write_Mode,
  21 | 	target: Hash_Map_Get_Target,
  22 | 	frozen_at: i64,
  23 | ) -> (res: Hash_Map_Get_Result, err: Error) {
  24 | 	index_pos := index_pos
  25 | 	key_offset := key_offset
  26 | 	max_offset := (int(db.header.hash_size) * 8) / BIT_COUNT
  27 | 
  28 | 	for {
  29 | 		if int(key_offset) > max_offset {
  30 | 			return {}, .Key_Offset_Exceeded
  31 | 		}
  32 | 
  33 | 		i := hamt_nibble(key_hash, key_offset)  // <== [calls hamt_nibble]
  34 | 		slot_pos := index_pos + i64(SLOT_LENGTH * i)
  35 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  36 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
  37 | 		ptr := slot.value
  38 | 
  39 | 		#partial switch slot.tag {
  40 | 		case .None:
  41 | 			switch write_mode {
  42 | 			case .Read_Only:
  43 | 				return {}, .Key_Not_Found
  44 | 			case .Read_Write:
  45 | 				hash_pos := core_length(db.core) or_return  // <== [calls core_length]
  46 | 				core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
  47 | 				key_slot_pos := hash_pos + i64(db.header.hash_size)
  48 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
  49 | 				kv_pair := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
  50 | 				kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
  51 | 
  52 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
  53 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  54 | 				core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
  55 | 
  56 | 				next_slot_ptr: Slot_Pointer
  57 | 				switch _ in target {
  58 | 				case Hash_Map_Get_KV_Pair:
  59 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
  60 | 				case Hash_Map_Get_Key:
  61 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
  62 | 				case Hash_Map_Get_Value:
  63 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
  64 | 				}
  65 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
  66 | 			}
  67 | 
  68 | 		case .Index:
  69 | 			next_ptr := ptr
  70 | 			if write_mode == .Read_Write {
  71 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
  72 | 				if next_ptr != ptr {
  73 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  74 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
  75 | 				}
  76 | 			}
  77 | 			index_pos = next_ptr
  78 | 			key_offset += 1
  79 | 			continue
  80 | 
  81 | 		case .KV_Pair:
  82 | 			hash_size := int(db.header.hash_size)
  83 | 			kv_len := hash_size + SLOT_LENGTH * 2
  84 | 			stack_hash: [64]u8 = ---
  85 | 			kv_pair: Key_Value_Pair
  86 | 			hash_matches: bool
  87 | 
  88 | 			if kv_slice, in_mem, slice_err := core_slice_at(db.core, ptr, kv_len); in_mem {  // <== [calls core_slice_at]
  89 | 				if slice_err != nil {
  90 | 					return {}, slice_err
  91 | 				}
  92 | 				key_slot := slot_from_slice_raw(kv_slice[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  93 | 				tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
  94 | 				val_slot := slot_from_slice_raw(kv_slice[hash_size + SLOT_LENGTH : kv_len])  // <== [calls slot_from_slice_raw]
  95 | 				tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
  96 | 				hash_matches = bytes.equal(kv_slice[:hash_size], key_hash)
  97 | 				if hash_matches && write_mode == .Read_Only {
  98 | 					key_slot_pos := ptr + i64(hash_size)
  99 | 					value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 100 | 					next_slot_ptr: Slot_Pointer
 101 | 					switch _ in target {
 102 | 					case Hash_Map_Get_KV_Pair:
 103 | 						next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 104 | 					case Hash_Map_Get_Key:
 105 | 						next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = key_slot}
 106 | 					case Hash_Map_Get_Value:
 107 | 						next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = val_slot}
 108 | 					}
 109 | 					return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 110 | 				}
 111 | 				if !hash_matches && write_mode == .Read_Only {
 112 | 					return {}, .Key_Not_Found
 113 | 				}
 114 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 115 | 				copy(hash_buf, kv_slice[:hash_size])
 116 | 				kv_pair = Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}
 117 | 			} else {
 118 | 				core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 119 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 120 | 				kv_pair = kv_pair_read_buf(db.core, hash_buf) or_return  // <== [calls kv_pair_read_buf]
 121 | 				hash_matches = bytes.equal(kv_pair.hash, key_hash)
 122 | 			}
 123 | 
 124 | 			if hash_matches {
 125 | 				if write_mode == .Read_Write {
 126 | 					old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 127 | 					if old {
 128 | 						hash_pos := core_length(db.core) or_return  // <== [calls core_length]
 129 | 						core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
 130 | 						key_slot_pos := hash_pos + i64(hash_size)
 131 | 						value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 132 | 						kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
 133 | 
 134 | 						next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 135 | 						core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 136 | 						core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
 137 | 
 138 | 						next_slot_ptr: Slot_Pointer
 139 | 						switch _ in target {
 140 | 						case Hash_Map_Get_KV_Pair:
 141 | 							next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
 142 | 						case Hash_Map_Get_Key:
 143 | 							next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 144 | 						case Hash_Map_Get_Value:
 145 | 							next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 146 | 						}
 147 | 						return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 148 | 					}
 149 | 				}
 150 | 
 151 | 				key_slot_pos := ptr + i64(hash_size)
 152 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 153 | 				next_slot_ptr: Slot_Pointer
 154 | 				switch _ in target {
 155 | 				case Hash_Map_Get_KV_Pair:
 156 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 157 | 				case Hash_Map_Get_Key:
 158 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 159 | 				case Hash_Map_Get_Value:
 160 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 161 | 				}
 162 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 163 | 			}
 164 | 
 165 | 			// Hash collision - different keys
 166 | 			switch write_mode {
 167 | 			case .Read_Only:
 168 | 				return {}, .Key_Not_Found
 169 | 			case .Read_Write:
 170 | 				diff_offset := int(key_offset) + 1
 171 | 				for diff_offset < max_offset {
 172 | 					if hamt_nibble(kv_pair.hash, u8(diff_offset)) != hamt_nibble(key_hash, u8(diff_offset)) {  // <== [calls hamt_nibble]
 173 | 						break
 174 | 					}
 175 | 					diff_offset += 1
 176 | 				}
 177 | 				if diff_offset >= max_offset {
 178 | 					return {}, .Key_Offset_Exceeded
 179 | 				}
 180 | 
 181 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 182 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 183 | 				cur_index_pos := first_index_pos
 184 | 
 185 | 				for off in int(key_offset) + 1 ..< diff_offset {
 186 | 					nib := hamt_nibble(key_hash, u8(off))  // <== [calls hamt_nibble]
 187 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 188 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 189 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 190 | 					copy(mid_block[SLOT_LENGTH * nib : SLOT_LENGTH * (nib + 1)], sb[:])
 191 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 192 | 					cur_index_pos = child_index_pos
 193 | 				}
 194 | 
 195 | 				next_i := hamt_nibble(kv_pair.hash, u8(diff_offset))  // <== [calls hamt_nibble]
 196 | 				new_i := hamt_nibble(key_hash, u8(diff_offset))  // <== [calls hamt_nibble]
 197 | 				hash_pos := cur_index_pos + INDEX_BLOCK_SIZE
 198 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 199 | 				key_slot_pos := hash_pos + i64(hash_size)
 200 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 201 | 
 202 | 				if hash_size <= 64 {
 203 | 					combined: [INDEX_BLOCK_SIZE + 64 + SLOT_LENGTH * 2]u8
 204 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 205 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 206 | 					copy(combined[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 207 | 					copy(combined[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 208 | 					copy(combined[INDEX_BLOCK_SIZE : INDEX_BLOCK_SIZE + hash_size], key_hash)
 209 | 					core_write_all(db.core, combined[:INDEX_BLOCK_SIZE + kv_len]) or_return  // <== [calls core_write_all]
 210 | 				} else {
 211 | 					new_block: [INDEX_BLOCK_SIZE]u8
 212 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 213 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 214 | 					copy(new_block[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 215 | 					copy(new_block[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 216 | 					core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 217 | 					new_kv := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
 218 | 					kv_pair_write(new_kv, db.core) or_return  // <== [calls kv_pair_write]
 219 | 				}
 220 | 
 221 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 222 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 223 | 
 224 | 				next_slot_ptr: Slot_Pointer
 225 | 				switch _ in target {
 226 | 				case Hash_Map_Get_KV_Pair:
 227 | 					next_slot_ptr = Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH * new_i), slot = next_slot}
 228 | 				case Hash_Map_Get_Key:
 229 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = Slot{}}
 230 | 				case Hash_Map_Get_Value:
 231 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = Slot{}}
 232 | 				}
 233 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
 234 | 			}
 235 | 
 236 | 		case:
 237 | 			return {}, .Unexpected_Tag
 238 | 		}
 239 | 	}
 240 | }
```

#### [`read_array_list_slot_append`](../../xitdb/hamt.odin#L345-L383) — `DEPTH 4` (`L345–L383`)

```odin
 345 | read_array_list_slot_append :: proc(
 346 | 	db: ^Database,
 347 | 	header: Array_List_Header,
 348 | 	write_mode: Write_Mode,
 349 | 	frozen_at: i64,
 350 | ) -> (res: Array_List_Append_Result, err: Error) {
 351 | 	index_pos := header.ptr
 352 | 	key := header.size
 353 | 
 354 | 	prev_shift := radix_shift(key - 1)  // <== [calls radix_shift]
 355 | 	next_shift := radix_shift(key)  // <== [calls radix_shift]
 356 | 
 357 | 	if prev_shift != next_shift {
 358 | 		// Root overflow
 359 | 		next_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 360 | 		core_seek_to(db.core, next_index_pos) or_return  // <== [calls core_seek_to]
 361 | 		new_block: [INDEX_BLOCK_SIZE]u8
 362 | 		sb := slot_to_bytes(Slot{value = index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 363 | 		copy(new_block[:SLOT_LENGTH], sb[:])
 364 | 		core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 365 | 		index_pos = next_index_pos
 366 | 	}
 367 | 
 368 | 	slot_ptr := read_array_list_slot(db, index_pos, key, next_shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 369 | 	pos, pos_ok := slot_ptr.position.?
 370 | 	if !pos_ok {
 371 | 		return {}, .Cursor_Not_Writeable
 372 | 	}
 373 | 	// Clear values left by a rollback or slice
 374 | 	if slot_ptr.slot != (Slot{}) {
 375 | 		slot_ptr = slot_pointer_with_slot(slot_ptr, Slot{})  // <== [calls slot_pointer_with_slot]
 376 | 		core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
 377 | 		core_write_slot(db.core, slot_ptr.slot) or_return  // <== [calls core_write_slot]
 378 | 	}
 379 | 	return Array_List_Append_Result{
 380 | 		header   = Array_List_Header{ptr = index_pos, size = header.size + 1},
 381 | 		slot_ptr = slot_ptr,
 382 | 	}, nil
 383 | }
```

#### [`read_array_list_slot`](../../xitdb/hamt.odin#L385-L452) — `DEPTH 4` (`L385–L452`)

```odin
 385 | read_array_list_slot :: proc(
 386 | 	db: ^Database,
 387 | 	index_pos: i64,
 388 | 	key: i64,
 389 | 	shift: u8,
 390 | 	write_mode: Write_Mode,
 391 | 	frozen_at: i64,
 392 | ) -> (res: Slot_Pointer, err: Error) {
 393 | 	if shift >= MAX_BRANCH_LENGTH {
 394 | 		return {}, .Max_Shift_Exceeded
 395 | 	}
 396 | 
 397 | 	index_pos := index_pos
 398 | 	shift := shift
 399 | 	for {
 400 | 		i := (key >> (u64(shift) * BIT_COUNT)) & i64(MASK)
 401 | 		slot_pos := index_pos + i64(SLOT_LENGTH) * i
 402 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 403 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 404 | 
 405 | 		if shift == 0 {
 406 | 			return Slot_Pointer{position = slot_pos, slot = slot}, nil
 407 | 		}
 408 | 
 409 | 		ptr := slot.value
 410 | 
 411 | 		#partial switch slot.tag {
 412 | 		case .None:
 413 | 			switch write_mode {
 414 | 			case .Read_Only:
 415 | 				return {}, .Key_Not_Found
 416 | 			case .Read_Write:
 417 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 418 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 419 | 				cur_index_pos := first_index_pos
 420 | 				for s := shift - 1; s > 0; s -= 1 {
 421 | 					child_i := (key >> (u64(s) * BIT_COUNT)) & i64(MASK)
 422 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 423 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 424 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 425 | 					copy(mid_block[int(child_i) * SLOT_LENGTH : (int(child_i) + 1) * SLOT_LENGTH], sb[:])
 426 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 427 | 					cur_index_pos = child_index_pos
 428 | 				}
 429 | 				empty_block: [INDEX_BLOCK_SIZE]u8
 430 | 				core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 431 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 432 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 433 | 				leaf_i := key & i64(MASK)
 434 | 				return Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH) * leaf_i, slot = Slot{}}, nil
 435 | 			}
 436 | 		case .Index:
 437 | 			next_ptr := ptr
 438 | 			if write_mode == .Read_Write {
 439 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
 440 | 				if next_ptr != ptr {
 441 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 442 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 443 | 				}
 444 | 			}
 445 | 			index_pos = next_ptr
 446 | 			shift -= 1
 447 | 			continue
 448 | 		case:
 449 | 			return {}, .Unexpected_Tag
 450 | 		}
 451 | 	}
 452 | }
```

### `xitdb/types.odin` (38 procedures · 626 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L175–L353`](../../xitdb/types.odin#L175-L353), [`L571–L691`](../../xitdb/types.odin#L571-L691), [`L825–L834`](../../xitdb/types.odin#L825-L834), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L865–L869`](../../xitdb/types.odin#L865-L869), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L915–L917`](../../xitdb/types.odin#L915-L917), [`L929–L937`](../../xitdb/types.odin#L929-L937), [`L939–L950`](../../xitdb/types.odin#L939-L950), [`L952–L966`](../../xitdb/types.odin#L952-L966), [`L968–L972`](../../xitdb/types.odin#L968-L972), [`L974–L977`](../../xitdb/types.odin#L974-L977), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051), [`L1065–L1067`](../../xitdb/types.odin#L1065-L1067), [`L1069–L1074`](../../xitdb/types.odin#L1069-L1074), [`L1076–L1084`](../../xitdb/types.odin#L1076-L1084), [`L1092–L1097`](../../xitdb/types.odin#L1092-L1097), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1116–L1118`](../../xitdb/types.odin#L1116-L1118), [`L1130–L1139`](../../xitdb/types.odin#L1130-L1139), [`L1141–L1143`](../../xitdb/types.odin#L1141-L1143), [`L1149–L1183`](../../xitdb/types.odin#L1149-L1183), [`L1186–L1198`](../../xitdb/types.odin#L1186-L1198), [`L1200–L1226`](../../xitdb/types.odin#L1200-L1226), [`L1243–L1252`](../../xitdb/types.odin#L1243-L1252), [`L1293–L1302`](../../xitdb/types.odin#L1293-L1302), [`L1329–L1331`](../../xitdb/types.odin#L1329-L1331), [`L1339–L1350`](../../xitdb/types.odin#L1339-L1350), [`L1408–L1413`](../../xitdb/types.odin#L1408-L1413), [`L1416–L1421`](../../xitdb/types.odin#L1416-L1421))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`sha1_transf_hw`](../../xitdb/types.odin#L175-L353) — `DEPTH 2` (`L175–L353`)

```odin
 175 | 	@(private = "file", enable_target_feature = "sse2,ssse3,sse4.1,sha")
 176 | 	sha1_transf_hw :: proc "contextless" (state: ^[5]u32, data: []u8) #no_bounds_check {
 177 | 		// Load initial state: state[0..3] = A, B, C, D; state[4] = E
 178 | 		abcd := intrinsics.unaligned_load((^x86.__m128i)(&state[0]))
 179 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B) // lane 3..0 = A, B, C, D
 180 | 		e0 := x86._mm_set_epi32(i32(state[4]), 0, 0, 0)
 181 | 
 182 | 		data := data
 183 | 		for len(data) >= 64 {
 184 | 			abcd_save := abcd
 185 | 			e0_save := e0
 186 | 
 187 | 			// Rounds 0..3
 188 | 			msg0 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[0:])))
 189 | 			msg0 = x86._mm_shuffle_epi8(msg0, SHA1_SHUF_MASK)
 190 | 			e0 = x86._mm_add_epi32(e0, msg0)
 191 | 			e1 := abcd
 192 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 193 | 
 194 | 			// Rounds 4..7
 195 | 			msg1 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[16:])))
 196 | 			msg1 = x86._mm_shuffle_epi8(msg1, SHA1_SHUF_MASK)
 197 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 198 | 			e0 = abcd
 199 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 200 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 201 | 
 202 | 			// Rounds 8..11
 203 | 			msg2 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[32:])))
 204 | 			msg2 = x86._mm_shuffle_epi8(msg2, SHA1_SHUF_MASK)
 205 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 206 | 			e1 = abcd
 207 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 208 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 209 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 210 | 
 211 | 			// Rounds 12..15
 212 | 			msg3 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[48:])))
 213 | 			msg3 = x86._mm_shuffle_epi8(msg3, SHA1_SHUF_MASK)
 214 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 215 | 			e0 = abcd
 216 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 217 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 218 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 219 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 220 | 
 221 | 			// Rounds 16..19
 222 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 223 | 			e1 = abcd
 224 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 225 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 226 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 227 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 228 | 
 229 | 			// Rounds 20..23
 230 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 231 | 			e0 = abcd
 232 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 233 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 234 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 235 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 236 | 
 237 | 			// Rounds 24..27
 238 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 239 | 			e1 = abcd
 240 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 241 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 242 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 243 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 244 | 
 245 | 			// Rounds 28..31
 246 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 247 | 			e0 = abcd
 248 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 249 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 250 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 251 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 252 | 
 253 | 			// Rounds 32..35
 254 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 255 | 			e1 = abcd
 256 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 257 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 258 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 259 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 260 | 
 261 | 			// Rounds 36..39
 262 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 263 | 			e0 = abcd
 264 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 265 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 266 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 267 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 268 | 
 269 | 			// Rounds 40..43
 270 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 271 | 			e1 = abcd
 272 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 273 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 274 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 275 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 276 | 
 277 | 			// Rounds 44..47
 278 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 279 | 			e0 = abcd
 280 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 281 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 282 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 283 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 284 | 
 285 | 			// Rounds 48..51
 286 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 287 | 			e1 = abcd
 288 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 289 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 290 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 291 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 292 | 
 293 | 			// Rounds 52..55
 294 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 295 | 			e0 = abcd
 296 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 297 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 298 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 299 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 300 | 
 301 | 			// Rounds 56..59
 302 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 303 | 			e1 = abcd
 304 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 305 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 306 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 307 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 308 | 
 309 | 			// Rounds 60..63
 310 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 311 | 			e0 = abcd
 312 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 313 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 314 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 315 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 316 | 
 317 | 			// Rounds 64..67
 318 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 319 | 			e1 = abcd
 320 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 321 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 322 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 323 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 324 | 
 325 | 			// Rounds 68..71
 326 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 327 | 			e0 = abcd
 328 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 329 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 330 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 331 | 
 332 | 			// Rounds 72..75
 333 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 334 | 			e1 = abcd
 335 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 336 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 337 | 
 338 | 			// Rounds 76..79
 339 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 340 | 			e0 = abcd
 341 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 342 | 
 343 | 			// Combine state
 344 | 			e0 = x86._mm_sha1nexte_epu32(e0, e0_save)
 345 | 			abcd = x86._mm_add_epi32(abcd, abcd_save)
 346 | 
 347 | 			data = data[64:]
 348 | 		}
 349 | 
 350 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B)
 351 | 		intrinsics.unaligned_store((^x86.__m128i)(&state[0]), abcd)
 352 | 		state[4] = u32(x86._mm_extract_epi32(e0, 3))
 353 | 	}
```

#### [`sha1_sum_into`](../../xitdb/types.odin#L571-L691) — `DEPTH 1` (`L571–L691`)

```odin
 571 | sha1_sum_into :: proc(data: []u8, out: []u8) #no_bounds_check {
 572 | 	state := [5]u32{
 573 | 		0x67452301,
 574 | 		0xEFCDAB89,
 575 | 		0x98BADCFE,
 576 | 		0x10325476,
 577 | 		0xC3D2E1F0,
 578 | 	}
 579 | 
 580 | 	when ODIN_ARCH == .amd64 {
 581 | 		if _has_sha_ni {
 582 | 			full_len := len(data) & ~int(63)
 583 | 			if full_len > 0 {
 584 | 				sha1_transf_hw(&state, data[:full_len])  // <== [calls sha1_transf_hw]
 585 | 			}
 586 | 			rem := len(data) - full_len
 587 | 			bit_len := u64(len(data)) * 8
 588 | 			if rem < 56 {
 589 | 				tail: [64]u8
 590 | 				copy(tail[:rem], data[full_len:])
 591 | 				tail[rem] = 0x80
 592 | 				endian.unchecked_put_u64be(tail[56:64], bit_len)
 593 | 				sha1_transf_hw(&state, tail[0:64])  // <== [calls sha1_transf_hw]
 594 | 			} else {
 595 | 				tail: [128]u8
 596 | 				copy(tail[:rem], data[full_len:])
 597 | 				tail[rem] = 0x80
 598 | 				endian.unchecked_put_u64be(tail[120:128], bit_len)
 599 | 				sha1_transf_hw(&state, tail[0:128])  // <== [calls sha1_transf_hw]
 600 | 			}
 601 | 			endian.unchecked_put_u32be(out[0:4], state[0])
 602 | 			endian.unchecked_put_u32be(out[4:8], state[1])
 603 | 			endian.unchecked_put_u32be(out[8:12], state[2])
 604 | 			endian.unchecked_put_u32be(out[12:16], state[3])
 605 | 			endian.unchecked_put_u32be(out[16:20], state[4])
 606 | 			return
 607 | 		}
 608 | 	}
 609 | 
 610 | 	h0, h1, h2, h3, h4 := state[0], state[1], state[2], state[3], state[4]
 611 | 
 612 | 	rol32 :: #force_inline proc(x: u32, n: uint) -> u32 {
 613 | 		return (x << n) | (x >> (32 - n))
 614 | 	}
 615 | 
 616 | 	process_block :: proc(block: []u8, h0, h1, h2, h3, h4: ^u32) {
 617 | 		w: [80]u32
 618 | 		for i in 0 ..< 16 {
 619 | 			v, _ := endian.get_u32(block[i * 4:i * 4 + 4], .Big)
 620 | 			w[i] = v
 621 | 		}
 622 | 		for i in 16 ..< 80 {
 623 | 			x := w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16]
 624 | 			w[i] = (x << 1) | (x >> 31)
 625 | 		}
 626 | 
 627 | 		a := h0^
 628 | 		b := h1^
 629 | 		c := h2^
 630 | 		d := h3^
 631 | 		e := h4^
 632 | 
 633 | 		for i in 0 ..< 80 {
 634 | 			f, k: u32
 635 | 			if i < 20 {
 636 | 				f = (b & c) | ((~b) & d)
 637 | 				k = 0x5A827999
 638 | 			} else if i < 40 {
 639 | 				f = b ~ c ~ d
 640 | 				k = 0x6ED9EBA1
 641 | 			} else if i < 60 {
 642 | 				f = (b & c) | (b & d) | (c & d)
 643 | 				k = 0x8F1BBCDC
 644 | 			} else {
 645 | 				f = b ~ c ~ d
 646 | 				k = 0xCA62C1D6
 647 | 			}
 648 | 			temp := ((a << 5) | (a >> 27)) + f + e + k + w[i]
 649 | 			e = d
 650 | 			d = c
 651 | 			c = (b << 30) | (b >> 2)
 652 | 			b = a
 653 | 			a = temp
 654 | 		}
 655 | 
 656 | 		h0^ += a
 657 | 		h1^ += b
 658 | 		h2^ += c
 659 | 		h3^ += d
 660 | 		h4^ += e
 661 | 	}
 662 | 
 663 | 	i := 0
 664 | 	for i + 64 <= len(data) {
 665 | 		process_block(data[i:i + 64], &h0, &h1, &h2, &h3, &h4)
 666 | 		i += 64
 667 | 	}
 668 | 
 669 | 	rem := len(data) - i
 670 | 	bit_len := u64(len(data)) * 8
 671 | 	if rem < 56 {
 672 | 		tail: [64]u8
 673 | 		copy(tail[:rem], data[i:])
 674 | 		tail[rem] = 0x80
 675 | 		endian.put_u64(tail[56:64], .Big, bit_len)
 676 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 677 | 	} else {
 678 | 		tail: [128]u8
 679 | 		copy(tail[:rem], data[i:])
 680 | 		tail[rem] = 0x80
 681 | 		endian.put_u64(tail[120:128], .Big, bit_len)
 682 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 683 | 		process_block(tail[64:128], &h0, &h1, &h2, &h3, &h4)
 684 | 	}
 685 | 
 686 | 	endian.put_u32(out[0:4], .Big, h0)
 687 | 	endian.put_u32(out[4:8], .Big, h1)
 688 | 	endian.put_u32(out[8:12], .Big, h2)
 689 | 	endian.put_u32(out[12:16], .Big, h3)
 690 | 	endian.put_u32(out[16:20], .Big, h4)
 691 | }
```

#### [`sha1_hasher`](../../xitdb/types.odin#L825-L834) — `ENTRY POINT` (`L825–L834`)

```odin
 825 | sha1_hasher :: proc(id: u32 = 0, file_id: u64 = 0) -> Hasher {
 826 | 	return Hasher{
 827 | 		hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
 828 | 			sha1_sum_into(data, out_hash)  // <== [calls sha1_sum_into]
 829 | 		},
 830 | 		hash_size = 20,
 831 | 		id        = id,
 832 | 		file_id   = file_id,
 833 | 	}
 834 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 1` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_with_full`](../../xitdb/types.odin#L865-L869) — `DEPTH 4` (`L865–L869`)

```odin
 865 | slot_with_full :: proc(s: Slot, full: bool) -> Slot {
 866 | 	res := s
 867 | 	res.full = full
 868 | 	return res
 869 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 2` (`L871–L877`)

```odin
 871 | slot_to_bytes :: #force_inline proc(s: Slot) -> [SLOT_LENGTH]u8 {
 872 | 	buf: [SLOT_LENGTH]u8 = ---
 873 | 	full_bit := u8(0x80) if s.full else u8(0)
 874 | 	buf[0] = full_bit | (u8(s.tag) & 0x7f)
 875 | 	endian.unchecked_put_u64be(buf[1:9], u64(s.value))
 876 | 	return buf
 877 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 4` (`L880–L890`)

```odin
 880 | slot_from_bytes_raw :: #force_inline proc(buf: [SLOT_LENGTH]u8) -> Slot {
 881 | 	b := buf
 882 | 	full := (b[0] & 0x80) != 0
 883 | 	raw_tag := b[0] & 0x7f
 884 | 	val := endian.unchecked_get_u64be(b[1:9])
 885 | 	return Slot{
 886 | 		value = i64(val),
 887 | 		tag   = Tag(raw_tag),
 888 | 		full  = full,
 889 | 	}
 890 | }
```

#### [`slot_from_slice_raw`](../../xitdb/types.odin#L892-L901) — `DEPTH 4` (`L892–L901`)

```odin
 892 | slot_from_slice_raw :: #force_inline proc(b: []u8) -> Slot #no_bounds_check {
 893 | 	full := (b[0] & 0x80) != 0
 894 | 	raw_tag := b[0] & 0x7f
 895 | 	val := endian.unchecked_get_u64be(b[1:9])
 896 | 	return Slot{
 897 | 		value = i64(val),
 898 | 		tag   = Tag(raw_tag),
 899 | 		full  = full,
 900 | 	}
 901 | }
```

#### [`slot_pointer_with_slot`](../../xitdb/types.odin#L915-L917) — `DEPTH 3` (`L915–L917`)

```odin
 915 | slot_pointer_with_slot :: proc(sp: Slot_Pointer, s: Slot) -> Slot_Pointer {
 916 | 	return Slot_Pointer{position = sp.position, slot = s}
 917 | }
```

#### [`header_validate`](../../xitdb/types.odin#L929-L937) — `DEPTH 2` (`L929–L937`)

```odin
 929 | header_validate :: proc(h: Header) -> Error {
 930 | 	if h.magic_number != MAGIC_NUMBER {
 931 | 		return .Invalid_Database
 932 | 	}
 933 | 	if h.version != VERSION {
 934 | 		return .Invalid_Version
 935 | 	}
 936 | 	return nil
 937 | }
```

#### [`header_to_bytes`](../../xitdb/types.odin#L939-L950) — `DEPTH 2` (`L939–L950`)

```odin
 939 | header_to_bytes :: proc(h: Header) -> [HEADER_LENGTH]u8 {
 940 | 	buf: [HEADER_LENGTH]u8
 941 | 	buf[0] = h.magic_number[0]
 942 | 	buf[1] = h.magic_number[1]
 943 | 	buf[2] = h.magic_number[2]
 944 | 	buf[3] = h.padding
 945 | 	endian.put_u16(buf[4:6], .Big, h.version)
 946 | 	endian.put_u16(buf[6:8], .Big, h.hash_size)
 947 | 	endian.put_u32(buf[8:12], .Big, h.hash_id)
 948 | 	endian.put_u64(buf[12:20], .Big, h.file_id)
 949 | 	return buf
 950 | }
```

#### [`header_from_bytes`](../../xitdb/types.odin#L952-L966) — `DEPTH 3` (`L952–L966`)

```odin
 952 | header_from_bytes :: proc(buf: [HEADER_LENGTH]u8) -> Header {
 953 | 	b := buf
 954 | 	version, _ := endian.get_u16(b[4:6], .Big)
 955 | 	hash_size, _ := endian.get_u16(b[6:8], .Big)
 956 | 	hash_id, _ := endian.get_u32(b[8:12], .Big)
 957 | 	file_id, _ := endian.get_u64(b[12:20], .Big)
 958 | 	return Header{
 959 | 		magic_number = {b[0], b[1], b[2]},
 960 | 		padding      = b[3],
 961 | 		version      = version,
 962 | 		hash_size    = hash_size,
 963 | 		hash_id      = hash_id,
 964 | 		file_id      = file_id,
 965 | 	}
 966 | }
```

#### [`header_read`](../../xitdb/types.odin#L968-L972) — `DEPTH 2` (`L968–L972`)

```odin
 968 | header_read :: proc(r: ^Core) -> (h: Header, err: Error) {
 969 | 	buf: [HEADER_LENGTH]u8
 970 | 	core_read_exact(r, buf[:]) or_return  // <== [calls core_read_exact]
 971 | 	return header_from_bytes(buf), nil  // <== [calls header_from_bytes]
 972 | }
```

#### [`header_write`](../../xitdb/types.odin#L974-L977) — `DEPTH 1` (`L974–L977`)

```odin
 974 | header_write :: proc(h: Header, w: ^Core) -> Error {
 975 | 	buf := header_to_bytes(h)  // <== [calls header_to_bytes]
 976 | 	return core_write_all(w, buf[:])  // <== [calls core_write_all]
 977 | }
```

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 1` (`L985–L991`)

```odin
 985 | root_header_to_bytes :: proc(rh: Root_Header) -> [ROOT_HEADER_LENGTH]u8 {
 986 | 	buf: [ROOT_HEADER_LENGTH]u8
 987 | 	slot_bytes := slot_to_bytes(rh.root)  // <== [calls slot_to_bytes]
 988 | 	copy(buf[0:9], slot_bytes[:])
 989 | 	endian.put_u64(buf[9:17], .Big, u64(rh.file_size))
 990 | 	return buf
 991 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 3` (`L993–L1003`)

```odin
 993 | root_header_from_bytes :: proc(buf: [ROOT_HEADER_LENGTH]u8) -> Root_Header {
 994 | 	b := buf
 995 | 	slot_buf: [SLOT_LENGTH]u8
 996 | 	copy(slot_buf[:], b[0:9])
 997 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
 998 | 	file_size, _ := endian.get_u64(b[9:17], .Big)
 999 | 	return Root_Header{
1000 | 		file_size = i64(file_size),
1001 | 		root      = root,
1002 | 	}
1003 | }
```

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 3` (`L1012–L1020`)

```odin
1012 | compute_root_trailer_checksum :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> u64 {
1013 | 	data: [33]u8
1014 | 	endian.put_u64(data[0:8], .Big, file_id)
1015 | 	endian.put_u64(data[8:16], .Big, u64(position))
1016 | 	slot_bytes := slot_to_bytes(root)  // <== [calls slot_to_bytes]
1017 | 	copy(data[16:25], slot_bytes[:])
1018 | 	endian.put_u64(data[25:33], .Big, commit_id)
1019 | 	return hash.crc64_xz(data[:])
1020 | }
```

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 2` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 2` (`L1030–L1037`)

```odin
1030 | root_trailer_to_bytes :: proc(rt: Root_Trailer) -> [ROOT_TRAILER_LENGTH]u8 {
1031 | 	buf: [ROOT_TRAILER_LENGTH]u8
1032 | 	slot_bytes := slot_to_bytes(rt.root)  // <== [calls slot_to_bytes]
1033 | 	copy(buf[0:9], slot_bytes[:])
1034 | 	endian.put_u64(buf[9:17], .Big, rt.commit_id)
1035 | 	endian.put_u64(buf[17:25], .Big, rt.checksum)
1036 | 	return buf
1037 | }
```

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 4` (`L1039–L1051`)

```odin
1039 | root_trailer_from_bytes :: proc(buf: [ROOT_TRAILER_LENGTH]u8) -> Root_Trailer {
1040 | 	b := buf
1041 | 	slot_buf: [SLOT_LENGTH]u8
1042 | 	copy(slot_buf[:], b[0:9])
1043 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
1044 | 	commit_id, _ := endian.get_u64(b[9:17], .Big)
1045 | 	checksum, _ := endian.get_u64(b[17:25], .Big)
1046 | 	return Root_Trailer{
1047 | 		checksum  = checksum,
1048 | 		commit_id = commit_id,
1049 | 		root      = root,
1050 | 	}
1051 | }
```

#### [`array_list_header_with_ptr`](../../xitdb/types.odin#L1065-L1067) — `DEPTH 4` (`L1065–L1067`)

```odin
1065 | array_list_header_with_ptr :: proc(h: Array_List_Header, ptr: i64) -> Array_List_Header {
1066 | 	return Array_List_Header{ptr = ptr, size = h.size}
1067 | }
```

#### [`array_list_header_to_bytes`](../../xitdb/types.odin#L1069-L1074) — `DEPTH 4` (`L1069–L1074`)

```odin
1069 | array_list_header_to_bytes :: #force_inline proc(h: Array_List_Header) -> [ARRAY_LIST_HEADER_LENGTH]u8 {
1070 | 	buf: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
1071 | 	endian.unchecked_put_u64be(buf[0:8], u64(h.size))
1072 | 	endian.unchecked_put_u64be(buf[8:16], u64(h.ptr))
1073 | 	return buf
1074 | }
```

#### [`array_list_header_from_bytes`](../../xitdb/types.odin#L1076-L1084) — `DEPTH 4` (`L1076–L1084`)

```odin
1076 | array_list_header_from_bytes :: #force_inline proc(buf: [ARRAY_LIST_HEADER_LENGTH]u8) -> (res: Array_List_Header, err: Error) {
1077 | 	b := buf
1078 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1079 | 	ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1080 | 	if size < 0 || ptr < 0 {
1081 | 		return {}, .Expected_Unsigned_Long
1082 | 	}
1083 | 	return Array_List_Header{ptr = ptr, size = size}, nil
1084 | }
```

#### [`btree_header_to_bytes`](../../xitdb/types.odin#L1092-L1097) — `DEPTH 4` (`L1092–L1097`)

```odin
1092 | btree_header_to_bytes :: #force_inline proc(h: BTree_Header) -> [BTREE_HEADER_LENGTH]u8 {
1093 | 	buf: [BTREE_HEADER_LENGTH]u8 = ---
1094 | 	endian.unchecked_put_u64be(buf[0:8], u64(h.size))
1095 | 	endian.unchecked_put_u64be(buf[8:16], u64(h.root_ptr))
1096 | 	return buf
1097 | }
```

#### [`btree_header_from_bytes`](../../xitdb/types.odin#L1099-L1107) — `DEPTH 4` (`L1099–L1107`)

```odin
1099 | btree_header_from_bytes :: #force_inline proc(buf: [BTREE_HEADER_LENGTH]u8) -> (res: BTree_Header, err: Error) {
1100 | 	b := buf
1101 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1102 | 	root_ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1103 | 	if size < 0 || root_ptr < 0 {
1104 | 		return {}, .Expected_Unsigned_Long
1105 | 	}
1106 | 	return BTree_Header{root_ptr = root_ptr, size = size}, nil
1107 | }
```

#### [`kv_pair_length`](../../xitdb/types.odin#L1116-L1118) — `DEPTH 6` (`L1116–L1118`)

```odin
1116 | kv_pair_length :: proc(hash_size: int) -> int {
1117 | 	return hash_size + SLOT_LENGTH * 2
1118 | }
```

#### [`kv_pair_from_bytes`](../../xitdb/types.odin#L1130-L1139) — `DEPTH 7` (`L1130–L1139`)

```odin
1130 | kv_pair_from_bytes :: proc(b: []u8, hash_size: int, allocator := context.allocator) -> Key_Value_Pair {
1131 | 	h: []u8
1132 | 	if hash_size > 0 {
1133 | 		h = make([]u8, hash_size, allocator)
1134 | 		copy(h, b[:hash_size])
1135 | 	}
1136 | 	key_slot := slot_from_slice_raw(b[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1137 | 	val_slot := slot_from_slice_raw(b[hash_size + SLOT_LENGTH : hash_size + SLOT_LENGTH * 2])  // <== [calls slot_from_slice_raw]
1138 | 	return Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = h}
1139 | }
```

#### [`kv_pair_write`](../../xitdb/types.odin#L1141-L1143) — `DEPTH 5` (`L1141–L1143`)

```odin
1141 | kv_pair_write :: proc(kv: Key_Value_Pair, c: ^Core) -> Error {
1142 | 	return encode_kv_pair(c, .KV_Pair, kv)  // <== [calls encode_kv_pair]
1143 | }
```

#### [`decode_kv_pair`](../../xitdb/types.odin#L1149-L1183) — `DEPTH 6` (`L1149–L1183`)

```odin
1149 | decode_kv_pair :: proc(c: ^Core, tag: Tag, hash_size: int, allocator := context.allocator) -> (kv: Key_Value_Pair, err: Error) {
1150 | 	#partial switch tag {
1151 | 	case .KV_Pair:
1152 | 		kv_len := kv_pair_length(hash_size)  // <== [calls kv_pair_length]
1153 | 		if kv_len <= 128 {
1154 | 			stack_buf: [128]u8 = ---
1155 | 			b := stack_buf[:kv_len]
1156 | 			core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1157 | 			kv = kv_pair_from_bytes(b, hash_size, allocator)  // <== [calls kv_pair_from_bytes]
1158 | 		} else {
1159 | 			b := make([]u8, kv_len, context.temp_allocator)
1160 | 			core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1161 | 			kv = kv_pair_from_bytes(b, hash_size, allocator)  // <== [calls kv_pair_from_bytes]
1162 | 		}
1163 | 	case .Sorted_KV_Pair:
1164 | 		b: [SORTED_KEY_VALUE_LEN]u8 = ---
1165 | 		core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
1166 | 		kv = kv_pair_from_bytes(b[:], 0, allocator)  // <== [calls kv_pair_from_bytes]
1167 | 	case:
1168 | 		return {}, .Unexpected_Tag
1169 | 	}
1170 | 	if err := tag_validate(kv.key_slot.tag); err != nil {  // <== [calls tag_validate]
1171 | 		if kv.hash != nil {
1172 | 			delete(kv.hash, allocator)
1173 | 		}
1174 | 		return {}, err
1175 | 	}
1176 | 	if err := tag_validate(kv.value_slot.tag); err != nil {  // <== [calls tag_validate]
1177 | 		if kv.hash != nil {
1178 | 			delete(kv.hash, allocator)
1179 | 		}
1180 | 		return {}, err
1181 | 	}
1182 | 	return kv, nil
1183 | }
```

#### [`kv_pair_read_buf`](../../xitdb/types.odin#L1186-L1198) — `DEPTH 5` (`L1186–L1198`)

```odin
1186 | kv_pair_read_buf :: proc(c: ^Core, hash_buf: []u8) -> (kv: Key_Value_Pair, err: Error) {
1187 | 	hash_size := len(hash_buf)
1188 | 	kv_len := kv_pair_length(hash_size)  // <== [calls kv_pair_length]
1189 | 	stack_buf: [128]u8 = ---
1190 | 	b := stack_buf[:kv_len] if kv_len <= len(stack_buf) else make([]u8, kv_len, context.temp_allocator)
1191 | 	core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1192 | 	copy(hash_buf, b[:hash_size])
1193 | 	key_slot := slot_from_slice_raw(b[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1194 | 	tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
1195 | 	val_slot := slot_from_slice_raw(b[hash_size + SLOT_LENGTH : hash_size + SLOT_LENGTH * 2])  // <== [calls slot_from_slice_raw]
1196 | 	tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
1197 | 	return Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}, nil
1198 | }
```

#### [`encode_kv_pair`](../../xitdb/types.odin#L1200-L1226) — `DEPTH 6` (`L1200–L1226`)

```odin
1200 | encode_kv_pair :: proc(c: ^Core, tag: Tag, kv: Key_Value_Pair) -> Error {
1201 | 	#partial switch tag {
1202 | 	case .KV_Pair:
1203 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1204 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1205 | 		total := len(kv.hash) + SLOT_LENGTH * 2
1206 | 		if total <= 128 {
1207 | 			buf: [128]u8 = ---
1208 | 			copy(buf[:len(kv.hash)], kv.hash)
1209 | 			copy(buf[len(kv.hash):len(kv.hash) + SLOT_LENGTH], kb[:])
1210 | 			copy(buf[len(kv.hash) + SLOT_LENGTH:total], vb[:])
1211 | 			return core_write_all(c, buf[:total])  // <== [calls core_write_all]
1212 | 		}
1213 | 		core_write_all(c, kv.hash) or_return  // <== [calls core_write_all]
1214 | 		core_write_all(c, kb[:]) or_return  // <== [calls core_write_all]
1215 | 		return core_write_all(c, vb[:])  // <== [calls core_write_all]
1216 | 	case .Sorted_KV_Pair:
1217 | 		buf: [SORTED_KEY_VALUE_LEN]u8 = ---
1218 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1219 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1220 | 		copy(buf[:SLOT_LENGTH], kb[:])
1221 | 		copy(buf[SLOT_LENGTH:], vb[:])
1222 | 		return core_write_all(c, buf[:])  // <== [calls core_write_all]
1223 | 	case:
1224 | 		return .Unexpected_Tag
1225 | 	}
1226 | }
```

#### [`btree_node_subtree_count`](../../xitdb/types.odin#L1243-L1252) — `DEPTH 5` (`L1243–L1252`)

```odin
1243 | btree_node_subtree_count :: proc(n: BTree_Node) -> i64 {
1244 | 	if n.kind == .Leaf {
1245 | 		return i64(n.num)
1246 | 	}
1247 | 	total: i64 = 0
1248 | 	for i in 0 ..< n.num {
1249 | 		total += n.counts[i]
1250 | 	}
1251 | 	return total
1252 | }
```

#### [`sorted_node_subtree_count`](../../xitdb/types.odin#L1293-L1302) — `DEPTH 5` (`L1293–L1302`)

```odin
1293 | sorted_node_subtree_count :: proc(n: Sorted_Node) -> i64 {
1294 | 	if n.kind == .Leaf {
1295 | 		return i64(n.num)
1296 | 	}
1297 | 	total: i64 = 0
1298 | 	for i in 0 ..< n.num {
1299 | 		total += n.counts[i]
1300 | 	}
1301 | 	return total
1302 | }
```

#### [`is_key_only_entry`](../../xitdb/types.odin#L1329-L1331) — `DEPTH 5` (`L1329–L1331`)

```odin
1329 | is_key_only_entry :: #force_inline proc(entry: Slot) -> bool {
1330 | 	return entry.tag == .Bytes || entry.tag == .Short_Bytes
1331 | }
```

#### [`bytes_is_short`](../../xitdb/types.odin#L1339-L1350) — `DEPTH 4` (`L1339–L1350`)

```odin
1339 | bytes_is_short :: proc(b: Bytes) -> bool {
1340 | 	total_size := 6 if b.format_tag != nil else 8
1341 | 	if len(b.value) > total_size {
1342 | 		return false
1343 | 	}
1344 | 	for ch in b.value {
1345 | 		if ch == 0 {
1346 | 			return false
1347 | 		}
1348 | 	}
1349 | 	return true
1350 | }
```

#### [`hamt_nibble`](../../xitdb/types.odin#L1408-L1413) — `DEPTH 5` (`L1408–L1413`)

```odin
1408 | hamt_nibble :: #force_inline proc(key_hash: []u8, key_offset: u8) -> int {
1409 | 	hash_size := len(key_hash)
1410 | 	byte_idx := hash_size - 1 - int(key_offset >> 1)
1411 | 	shift := (key_offset & 1) << 2
1412 | 	return int((key_hash[byte_idx] >> shift) & 0x0F)
1413 | }
```

#### [`radix_shift`](../../xitdb/types.odin#L1416-L1421) — `DEPTH 4` (`L1416–L1421`)

```odin
1416 | radix_shift :: #force_inline proc(key: i64) -> u8 {
1417 | 	if key < SLOT_COUNT {
1418 | 		return 0
1419 | 	}
1420 | 	return u8((63 - intrinsics.count_leading_zeros(u64(key))) >> 2)
1421 | }
```

