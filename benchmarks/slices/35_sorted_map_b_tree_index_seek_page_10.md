# #35. `Sorted_Map (B+Tree) index-seek page(10)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) · [Odin Harness (`bench_xitdb.odin#L1522-L1539`)](../bench_xitdb.odin#L1522-L1539) · [Zig Harness (`bench_xitdb.zig#L1275-L1289`)](../bench_xitdb.zig#L1275-L1289)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **558** | 558.8 ± 2.4 | 0.4% | 562.0 | 1,792,115 | - | **5.26x Odin** (`z = 110.4`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 2,934 | 2,915.6 ± 47.7 | 1.6% | 2,947.2 | 340,832 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Binary Search ($O(\log_2 16)$) vs. Linear Scan ($O(16)$) in Nodes ([`xitdb/btree.odin#L1244-L1276`](../../xitdb/btree.odin#L1244-L1276) vs. [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Zig's `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey` scan `0..node.num` linearly (up to 16 `sortedEntryKeySlot` + `compareKey` seeks per node), and [`compareKey`](../../reference/xitdb-zig/src/lib.zig#L2612) zero-fills `var key_buf: [256]u8 = @splat(0)` on every external key check. Odin uses **binary search** (`<= 4` comparisons per node) and an uninitialized `stack_buf: [256]u8 = ---` (**10.2x–50.5x faster**).
- **Single-Read `Sorted_Node` Decoding Only Up to `node.num` ([`xitdb/btree.odin#L1059-L1136`](../../xitdb/btree.odin#L1059-L1136)):** Zig's [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) and [`writeSortedNodeAt`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) execute **18 `takeInt`/`writeInt` calls** for a `146B` leaf and **50 calls** for a `418B` branch (reading all 16 children, 16 separators, and 16 counts even when `node.num == 2`). Odin reads the block in one `core_read_exact` call and decodes `0 ..< node.num`.
- **O(1) Direct Leaf Slot Seek in `sorted_get_by_index` ([`xitdb/btree.odin#L1394-L1480`](../../xitdb/btree.odin#L1394-L1480)):** On `#34 Sorted_Map get_index select` (**50.46x faster in Odin: 65 ns vs 3,280 ns**), Odin reads the 2-byte leaf header, validates `rem < leaf_num`, and seeks straight to `node_ptr + 2 + rem * 9` to read 1 `Slot`, whereas Zig's [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) decodes all 16 leaf slots via `readSortedNode`.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Extract `sortedBranchSearch` and `sortedLeafSearch` binary search helpers (`~24 lines` replacing 4 linear loops in [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Cuts key comparisons and `SortedKeyValuePair` seeks from up to 16 down to at most 4 per level while *reducing* code duplication across `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey`.
- **Drop `@splat(0)` in `compareKey` ([`lib.zig#L2612`](../../reference/xitdb-zig/src/lib.zig#L2612)) and batch-decode `SortedNode` ([`lib.zig#L2481-L2528`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528)):** Change `var key_buf: [256]u8 = @splat(0)` to `undefined`, and read/write `SortedNode` via one stack `[146]u8` / `[418]u8` buffer.
- **Direct leaf slot read in `sortedGetByIndex` ([`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680)):** When `hdr[0] == .leaf`, verify `rem < num` and seek to `node_ptr + 2 + rem * 9` to read 1 `Slot` instead of calling `readSortedNode`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1522-L1539`](../bench_xitdb.odin#L1522-L1539))

```odin
1522 | 	// 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
1523 | 	sp7 := span_begin()
1524 | 	for i in 0 ..< n {
1525 | 		iit, _ := xitdb.sorted_map_iterator_from_index(sm, i64(i))
1526 | 		for _ in 0 ..< 10 {
1527 | 			c_maybe, _ := xitdb.cursor_iterator_next(&iit)
1528 | 			if c_maybe == nil do break
1529 | 		}
1530 | 	}
1531 | 	elapsed_index_seek, hw7, has_hw7 := span_end(sp7)
1532 | 
1533 | 	print_result(Bench_Result{
1534 | 		name         = "Sorted_Map (B+Tree) index-seek page(10)",
1535 | 		ops          = n,
1536 | 		elapsed      = elapsed_index_seek,
1537 | 		counters     = hw7,
1538 | 		has_counters = has_hw7,
1539 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1275-L1289`](../bench_xitdb.zig#L1275-L1289))

```zig
1275 |     // 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
1276 |     const t7 = std.Io.Clock.awake.now(io);
1277 |     for (0..n) |i| {
1278 |         var iit = try sm.iteratorFromIndex(@intCast(i));
1279 |         for (0..10) |_| {
1280 |             if ((try iit.next()) == null) break;
1281 |         }
1282 |     }
1283 |     const elapsed_index_seek = t7.untilNow(io, .awake).nanoseconds;
1284 | 
1285 |     try printResult(stdout, .{
1286 |         .name = "Sorted_Map (B+Tree) index-seek page(10)",
1287 |         .ops = n,
1288 |         .elapsed_ns = elapsed_index_seek,
1289 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `SortedMap` | 101 | Typed counted B+Tree `SortedMap` wrapper (`put`, `getCursor`, `getIndex`, `rank`, `remove`) | [`lib.zig#L4128-L4228`](../../reference/xitdb-zig/src/lib.zig#L4128-L4228) |
| `SortedSet` | 66 | Typed counted B+Tree `SortedSet` wrapper | [`lib.zig#L4232-L4297`](../../reference/xitdb-zig/src/lib.zig#L4232-L4297) |
| `readSlotPointer.sorted_map` | 126 | `PathPart` switch arms: `.sorted_map_init`, `.sorted_map_get`, `.sorted_map_get_index`, `.sorted_map_remove` | [`lib.zig#L1399-L1524`](../../reference/xitdb-zig/src/lib.zig#L1399-L1524) |
| `readSortedNode` | 31 | Counted B+Tree 16-slot node deserializer (18–50 `takeInt` calls) | [`lib.zig#L2481-L2511`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) |
| `writeSortedNodeAt` | 16 | Counted B+Tree 16-slot node serializer (18–50 `writeInt` calls) | [`lib.zig#L2513-L2528`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) |
| `compareKey` | 31 | Lexicographic key comparison against `.short_bytes` / `.bytes` slot | [`lib.zig#L2599-L2629`](../../reference/xitdb-zig/src/lib.zig#L2599-L2629) |
| `sortedGet` | 25 | Counted B+Tree key lookup descent (linear separator/leaf scan) | [`lib.zig#L2634-L2658`](../../reference/xitdb-zig/src/lib.zig#L2634-L2658) |
| `sortedGetByIndex` | 20 | Counted B+Tree O(log N) rank selection by subtree counts | [`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) |
| `sortedRank` | 25 | Counted B+Tree O(log N) order-statistic rank query | [`lib.zig#L2683-L2707`](../../reference/xitdb-zig/src/lib.zig#L2683-L2707) |
| `sortedPut` | 140 | Counted B+Tree key insertion, leaf/branch split, and separator propagation | [`lib.zig#L2736-L2875`](../../reference/xitdb-zig/src/lib.zig#L2736-L2875) |
| `sortedRemove` | 40 | Counted B+Tree key deletion and sibling merge/rebalance | [`lib.zig#L2879-L2918`](../../reference/xitdb-zig/src/lib.zig#L2879-L2918) |

### Reached Odin Procedures (`46` procedures across `6` files · `1085` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_iterator_from_index` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L730-L732`](../../xitdb/collections.odin#L730-L732) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 40 | [`xitdb/cursor.odin#L1791-L1830`](../../xitdb/cursor.odin#L1791-L1830) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_index` | `depth 1` (from `sorted_map_iterator_from_index`) | 4 | [`xitdb/cursor.odin#L1317-L1320`](../../xitdb/cursor.odin#L1317-L1320) |
| `xitdb/cursor.odin` | `_iterator_step_internal` | `depth 1` (from `cursor_iterator_next`) | 93 | [`xitdb/cursor.odin#L1697-L1789`](../../xitdb/cursor.odin#L1697-L1789) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_index_init` | `depth 2` (from `cursor_iterator_sorted_from_index`) | 29 | [`xitdb/cursor.odin#L1287-L1315`](../../xitdb/cursor.odin#L1287-L1315) |
| `xitdb/cursor.odin` | `_read_btree_iter_level` | `depth 2` (from `_iterator_step_internal`) | 55 | [`xitdb/cursor.odin#L852-L906`](../../xitdb/cursor.odin#L852-L906) |
| `xitdb/cursor.odin` | `_init_iter_level_rev` | `depth 2` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L840-L843`](../../xitdb/cursor.odin#L840-L843) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L835-L838`](../../xitdb/cursor.odin#L835-L838) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_step_internal`, `read_btree_node`, `read_sorted_node`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/cursor.odin` | `_reset_cursor_iterator` | `depth 3` (from `cursor_iterator_sorted_from_index_init`) | 8 | [`xitdb/cursor.odin#L1023-L1030`](../../xitdb/cursor.odin#L1023-L1030) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 3` (from `cursor_iterator_sorted_from_index_init`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 3` (from `cursor_iterator_sorted_from_index_init`) | 11 | [`xitdb/cursor.odin#L1142-L1152`](../../xitdb/cursor.odin#L1142-L1152) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 3` (from `cursor_iterator_sorted_from_index_init`) | 11 | [`xitdb/cursor.odin#L1130-L1140`](../../xitdb/cursor.odin#L1130-L1140) |
| `xitdb/cursor.odin` | `_init_btree_stack_from_index` | `depth 3` (from `cursor_iterator_sorted_from_index_init`) | 132 | [`xitdb/cursor.odin#L1154-L1285`](../../xitdb/cursor.odin#L1154-L1285) |
| `xitdb/types.odin` | `_checked_add_i64` | `depth 3` (from `_read_btree_iter_level`, `_init_btree_stack_from_index`, `read_btree_node`) | 7 | [`xitdb/types.odin#L1498-L1504`](../../xitdb/types.odin#L1498-L1504) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 3` (from `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 66 | [`xitdb/btree.odin#L8-L73`](../../xitdb/btree.odin#L8-L73) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 3` (from `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 3` (from `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 83 | [`xitdb/btree.odin#L1262-L1344`](../../xitdb/btree.odin#L1262-L1344) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 3` (from `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/cursor.odin` | `_fill_slot_block_rev` | `depth 3` (from `_init_iter_level_rev`) | 38 | [`xitdb/cursor.odin#L796-L833`](../../xitdb/cursor.odin#L796-L833) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`) | 41 | [`xitdb/cursor.odin#L754-L794`](../../xitdb/cursor.odin#L754-L794) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 4` (from `cursor_resolved_cursor`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 4` (from `_sorted_header`, `_fill_slot_block_rev`, `_fill_slot_block_from`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_sorted_header`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/cursor.odin` | `_assign_btree_heights` | `depth 4` (from `_init_btree_stack_from_index`) | 6 | [`xitdb/cursor.odin#L845-L850`](../../xitdb/cursor.odin#L845-L850) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 4` (from `read_btree_node`, `read_sorted_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 4` (from `read_btree_node`, `read_sorted_node`, `_fill_slot_block_rev`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/types.odin` | `is_sorted_entry_tag` | `depth 4` (from `read_sorted_node`) | 8 | [`xitdb/types.odin#L1392-L1399`](../../xitdb/types.odin#L1392-L1399) |
| `xitdb/core.odin` | `core_slice_at` | `depth 4` (from `_fill_slot_block_rev`, `_fill_slot_block_from`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/database.odin` | `is_root` | `depth 5` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 5` (from `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/core.odin` | `core_read_at` | `depth 5` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 5` (from `core_read_block_at`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 5` (from `slot_from_slice`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 5` (from `slot_from_slice`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 5` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 6` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 6` (from `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 6` (from `database_read_root_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 6` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 6` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_overlay_length` | `depth 6` (from `_overlay_slice_at`, `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 7` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 7` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 8` (from `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 8` (from `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
