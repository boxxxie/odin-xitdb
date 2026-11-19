# #43. `Compaction (Heterogeneous DAG + dedup)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1508-L1567`)](../bench_xitdb.odin#L1508-L1567) · [Zig Harness (`bench_xitdb.zig#L1516-L1603`)](../bench_xitdb.zig#L1516-L1603)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **72,436** | 72,688.4 ± 2,988.3 | 4.1% | 76,353.4 | 13,805 | 23.4 KB | **1.80x Odin** (`z = 10.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 130,575 | 134,315.6 ± 12,377.5 | 9.2% | 150,742.2 | 7,658 | 23.4 KB | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1508-L1567`](../bench_xitdb.odin#L1508-L1567))

```odin
1508 | 	// 4d. Heterogeneous DAG Compaction (`Array_List` + `Linked_Array_List` + `Sorted_Map` + `Counted_Hash_Map` + DAG shared subtrees)
1509 | 	{
1510 | 		dag_src_core: xitdb.Core = xitdb.core_memory_init()
1511 | 		defer xitdb.core_destroy(&dag_src_core)
1512 | 		dag_db, _ := xitdb.database_init(&dag_src_core, xitdb.sha1_hasher())
1513 | 
1514 | 		build_dag_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1515 | 			root_map := xitdb.write_counted_hash_map_init(cursor^) or_return
1516 | 
1517 | 			// 1. Array_List with 200 items
1518 | 			al_wc := xitdb.hash_map_put_cursor(&root_map, "array_list") or_return
1519 | 			al := xitdb.write_array_list_init(al_wc) or_return
1520 | 			for i in 0 ..< 200 {
1521 | 				xitdb.array_list_append(&al, fmt.tprintf("arr-item-%04d-payload", i)) or_return
1522 | 			}
1523 | 			al_slot := xitdb.array_list_slot(al.read_array_list) or_return
1524 | 
1525 | 			// 2. Linked_Array_List with 200 items
1526 | 			lal_wc := xitdb.hash_map_put_cursor(&root_map, "linked_list") or_return
1527 | 			lal := xitdb.write_linked_array_list_init(lal_wc) or_return
1528 | 			for i in 0 ..< 200 {
1529 | 				xitdb.linked_array_list_append(&lal, u64(i)) or_return
1530 | 			}
1531 | 			lal_slot := xitdb.linked_array_list_slot(lal.read_linked_array_list) or_return
1532 | 
1533 | 			// 3. Sorted_Map with 200 items
1534 | 			sm_wc := xitdb.hash_map_put_cursor(&root_map, "sorted_map") or_return
1535 | 			sm := xitdb.write_sorted_map_init(sm_wc) or_return
1536 | 			for i in 0 ..< 200 {
1537 | 				xitdb.sorted_map_put(&sm, fmt.tprintf("skey-%04d", (i * 73) % 200), u64(i)) or_return
1538 | 			}
1539 | 			sm_slot := xitdb.sorted_map_slot(sm.read_sorted_map) or_return
1540 | 
1541 | 			// 4. DAG structural sharing: reference the same 3 collections under 5 alias keys each
1542 | 			for alias_i in 0 ..< 5 {
1543 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-al-%d", alias_i), al_slot) or_return
1544 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-lal-%d", alias_i), lal_slot) or_return
1545 | 				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-sm-%d", alias_i), sm_slot) or_return
1546 | 			}
1547 | 			return nil
1548 | 		}
1549 | 
1550 | 		_ = xitdb.database_run_context(&dag_db, build_dag_cb, nil)
1551 | 
1552 | 		dag_dst_core: xitdb.Core = xitdb.core_memory_init()
1553 | 		defer xitdb.core_destroy(&dag_dst_core)
1554 | 		dag_om: xitdb.Offset_Map = xitdb.memory_offset_map_init()
1555 | 		defer xitdb.offset_map_destroy(&dag_om)
1556 | 
1557 | 		t_dag := time.now()
1558 | 		dag_comp_db, _ := xitdb.database_compact(&dag_db, &dag_dst_core, &dag_om)
1559 | 		elapsed_dag := time.since(t_dag)
1560 | 		dag_comp_sz, _ := xitdb.database_committed_size(&dag_comp_db)
1561 | 
1562 | 		print_result(Bench_Result{
1563 | 			name       = "Compaction (Heterogeneous DAG + dedup)",
1564 | 			ops        = 1,
1565 | 			elapsed    = elapsed_dag,
1566 | 			bytes_used = dag_comp_sz,
1567 | 		})
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

### Reached Odin Procedures (`167` procedures across `8` files · `4209` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 28 | [`xitdb/core.odin#L85-L112`](../../xitdb/core.odin#L85-L112) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 30 | [`xitdb/core.odin#L351-L380`](../../xitdb/core.odin#L351-L380) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/collections.odin` | `write_counted_hash_map_init` | **Entry Point** (`depth 0`) | 14 | [`xitdb/collections.odin#L273-L286`](../../xitdb/collections.odin#L273-L286) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L443-L448`](../../xitdb/collections.odin#L443-L448) |
| `xitdb/collections.odin` | `write_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_append` | **Entry Point** (`depth 0`) | 7 | [`xitdb/collections.odin#L77-L83`](../../xitdb/collections.odin#L77-L83) |
| `xitdb/collections.odin` | `array_list_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L33-L35`](../../xitdb/collections.odin#L33-L35) |
| `xitdb/collections.odin` | `write_linked_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L126-L131`](../../xitdb/collections.odin#L126-L131) |
| `xitdb/collections.odin` | `linked_array_list_append` | **Entry Point** (`depth 0`) | 7 | [`xitdb/collections.odin#L177-L183`](../../xitdb/collections.odin#L177-L183) |
| `xitdb/collections.odin` | `linked_array_list_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L133-L135`](../../xitdb/collections.odin#L133-L135) |
| `xitdb/collections.odin` | `write_sorted_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L703-L708`](../../xitdb/collections.odin#L703-L708) |
| `xitdb/collections.odin` | `sorted_map_put` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L828-L830`](../../xitdb/collections.odin#L828-L830) |
| `xitdb/collections.odin` | `sorted_map_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L437-L441`](../../xitdb/collections.odin#L437-L441) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L343-L347`](../../xitdb/database.odin#L343-L347) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_init` | **Entry Point** (`depth 0`) | 3 | [`xitdb/compact_replicate.odin#L31-L33`](../../xitdb/compact_replicate.odin#L31-L33) |
| `xitdb/compact_replicate.odin` | `offset_map_destroy` | **Entry Point** (`depth 0`) | 6 | [`xitdb/compact_replicate.odin#L172-L177`](../../xitdb/compact_replicate.odin#L172-L177) |
| `xitdb/compact_replicate.odin` | `database_compact` | **Entry Point** (`depth 0`) | 78 | [`xitdb/compact_replicate.odin#L741-L818`](../../xitdb/compact_replicate.odin#L741-L818) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 1` (from `core_memory_init`, `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `_memory_destroy` | `depth 1` (from `core_destroy`, `_overlay_destroy`) | 14 | [`xitdb/core.odin#L207-L220`](../../xitdb/core.odin#L207-L220) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_overlay_destroy` | `depth 1` (from `core_destroy`) | 11 | [`xitdb/core.odin#L222-L232`](../../xitdb/core.odin#L222-L232) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_write_headers`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_compact`, `database_read_file_size`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L293-L300`](../../xitdb/database.odin#L293-L300) |
| `xitdb/database.odin` | `database_read_file_size` | `depth 1` (from `database_init`) | 7 | [`xitdb/database.odin#L315-L321`](../../xitdb/database.odin#L315-L321) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 1` (from `database_init`, `database_read_file_size`, `database_write_headers`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_init`, `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_write_headers` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L304-L311`](../../xitdb/database.odin#L304-L311) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L574-L694`](../../xitdb/types.odin#L574-L694) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `write_counted_hash_map_init`, `read_array_list_init`, `cursor_slot`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_counted_hash_map_init`, `write_array_list_init`, `array_list_append`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L404-L410`](../../xitdb/collections.odin#L404-L410) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L398-L402`](../../xitdb/collections.odin#L398-L402) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `array_list_slot`, `linked_array_list_slot`, `sorted_map_slot`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 1` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 1` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L693-L701`](../../xitdb/collections.odin#L693-L701) |
| `xitdb/collections.odin` | `sorted_map_put_by_bytes` | `depth 1` (from `sorted_map_put`) | 7 | [`xitdb/collections.odin#L805-L811`](../../xitdb/collections.odin#L805-L811) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L429-L435`](../../xitdb/collections.odin#L429-L435) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`, `database_compact`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_destroy` | `depth 1` (from `offset_map_destroy`) | 7 | [`xitdb/compact_replicate.odin#L35-L41`](../../xitdb/compact_replicate.odin#L35-L41) |
| `xitdb/compact_replicate.odin` | `offset_map_reset` | `depth 1` (from `database_compact`) | 16 | [`xitdb/compact_replicate.odin#L89-L104`](../../xitdb/compact_replicate.odin#L89-L104) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_compact`, `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/types.odin` | `slot_empty` | `depth 1` (from `database_compact`, `cursor_read_path_slot`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 1` (from `database_compact`, `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `database_compact`) | 15 | [`xitdb/cursor.odin#L80-L94`](../../xitdb/cursor.odin#L80-L94) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_write_headers`, `database_commit_root`, `header_write`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `cursor_resolved`, `database_read_root_slot`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `cursor_write_path`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 2` (from `offset_map_reset`) | 5 | [`xitdb/cursor.odin#L183-L187`](../../xitdb/cursor.odin#L183-L187) |
| `xitdb/collections.odin` | `write_hash_map_init` | `depth 2` (from `offset_map_reset`) | 6 | [`xitdb/collections.odin#L256-L261`](../../xitdb/collections.odin#L256-L261) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `header_read_at`, `core_read_i64_at`, `_exec_path_part`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 3` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `_exec_path_part`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `core_write_i64` | `depth 3` (from `database_write_root_header`, `core_write_long`, `sorted_put`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`, `sorted_target_slot`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`, `read_map_slot`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 38 | [`xitdb/hamt.odin#L343-L380`](../../xitdb/hamt.odin#L343-L380) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 61 | [`xitdb/btree.odin#L1315-L1375`](../../xitdb/btree.odin#L1315-L1375) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 17 | [`xitdb/btree.odin#L2087-L2103`](../../xitdb/btree.odin#L2087-L2103) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 384 | [`xitdb/btree.odin#L1536-L1919`](../../xitdb/btree.odin#L1536-L1919) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2074-L2085`](../../xitdb/btree.odin#L2074-L2085) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1420-L1473`](../../xitdb/database.odin#L1420-L1473) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1407-L1418`](../../xitdb/database.odin#L1407-L1418) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/btree.odin` | `btree_insert` | `depth 4` (from `_exec_path_part`) | 255 | [`xitdb/btree.odin#L154-L408`](../../xitdb/btree.odin#L154-L408) |
| `xitdb/btree.odin` | `btree_grow_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L410-L412`](../../xitdb/btree.odin#L410-L412) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1159-L1163`](../../xitdb/btree.odin#L1159-L1163) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_insert`, `btree_write_node`) | 5 | [`xitdb/btree.odin#L79-L83`](../../xitdb/btree.odin#L79-L83) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 3` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_overlay_page` | `depth 4` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`, `core_read_slot_at`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `read_map_slot`, `kv_pair_read_buf_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`, `read_array_list_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 5` (from `sorted_get`, `read_sorted_node`, `read_btree_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `sorted_get`, `sorted_put`, `read_sorted_node`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 6 | [`xitdb/btree.odin#L1180-L1185`](../../xitdb/btree.odin#L1180-L1185) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 84 | [`xitdb/btree.odin#L1194-L1277`](../../xitdb/btree.odin#L1194-L1277) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `sorted_put`, `btree_insert`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L85-L91`](../../xitdb/btree.odin#L85-L91) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 5` (from `sorted_put`, `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1473-L1479`](../../xitdb/btree.odin#L1473-L1479) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 6 | [`xitdb/btree.odin#L1173-L1178`](../../xitdb/btree.odin#L1173-L1178) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1187-L1192`](../../xitdb/btree.odin#L1187-L1192) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1481-L1534`](../../xitdb/btree.odin#L1481-L1534) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1165-L1171`](../../xitdb/btree.odin#L1165-L1171) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 40 | [`xitdb/btree.odin#L1078-L1117`](../../xitdb/btree.odin#L1078-L1117) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1281-L1297`](../../xitdb/btree.odin#L1281-L1297) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1300-L1313`](../../xitdb/btree.odin#L1300-L1313) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_insert`) | 36 | [`xitdb/btree.odin#L8-L43`](../../xitdb/btree.odin#L8-L43) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 5` (from `btree_insert`) | 7 | [`xitdb/btree.odin#L93-L99`](../../xitdb/btree.odin#L93-L99) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_insert`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_grow_root`) | 11 | [`xitdb/btree.odin#L773-L783`](../../xitdb/btree.odin#L773-L783) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1119-L1157`](../../xitdb/btree.odin#L1119-L1157) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`, `btree_write_node`) | 33 | [`xitdb/btree.odin#L45-L77`](../../xitdb/btree.odin#L45-L77) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 6` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf_at`, `decode_kv_pair_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/types.odin` | `decode_kv_pair_at` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1215-L1249`](../../xitdb/types.odin#L1215-L1249) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair_at`) | 10 | [`xitdb/types.odin#L1145-L1154`](../../xitdb/types.odin#L1145-L1154) |
