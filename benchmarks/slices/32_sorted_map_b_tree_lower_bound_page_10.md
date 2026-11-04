# #32. `Sorted_Map (B+Tree) lower-bound page(10)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) · [Odin Harness (`bench_xitdb.odin#L1197-L1212`)](../bench_xitdb.odin#L1197-L1212) · [Zig Harness (`bench_xitdb.zig#L1221-L1235`)](../bench_xitdb.zig#L1221-L1235)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **466** | 466.0 ± 1.9 | 0.4% | 467.8 | 2,145,923 | - | **6.59x Odin** (`z = 251.0`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 3,071 | 3,060.0 ± 23.0 | 0.8% | 3,075.2 | 325,627 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Binary Search ($O(\log_2 16)$) vs. Linear Scan ($O(16)$) in Nodes ([`xitdb/btree.odin#L1213-L1245`](../../xitdb/btree.odin#L1213-L1245) vs. [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Zig's `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey` scan `0..node.num` linearly (up to 16 `sortedEntryKeySlot` + `compareKey` seeks per node), and [`compareKey`](../../reference/xitdb-zig/src/lib.zig#L2612) zero-fills `var key_buf: [256]u8 = @splat(0)` on every external key check. Odin uses **binary search** (`<= 4` comparisons per node) and an uninitialized `stack_buf: [256]u8 = ---` (**11.6x–32.1x faster**).
- **Single-Read `Sorted_Node` Decoding Only Up to `node.num` ([`xitdb/btree.odin#L1028-L1105`](../../xitdb/btree.odin#L1028-L1105)):** Zig's [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) and [`writeSortedNodeAt`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) execute **18 `takeInt`/`writeInt` calls** for a `146B` leaf and **50 calls** for a `418B` branch (reading all 16 children, 16 separators, and 16 counts even when `node.num == 2`). Odin reads the block in one `core_read_exact` call and decodes `0 ..< node.num`.
- **O(1) Direct Leaf Slot Seek in `sorted_get_by_index` ([`xitdb/btree.odin#L1361-L1439`](../../xitdb/btree.odin#L1361-L1439)):** On `#34 Sorted_Map get_index select` (**51.25x faster in Odin: 64 ns vs 3,280 ns**), Odin reads the 2-byte leaf header and seeks straight to `node_ptr + 2 + rem * 9` to read 1 `Slot`, whereas Zig's [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) decodes all 16 leaf slots via `readSortedNode`.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Extract `sortedBranchSearch` and `sortedLeafSearch` binary search helpers (`~24 lines` replacing 4 linear loops in [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Cuts key comparisons and `SortedKeyValuePair` seeks from up to 16 down to at most 4 per level while *reducing* code duplication across `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey`.
- **Drop `@splat(0)` in `compareKey` ([`lib.zig#L2612`](../../reference/xitdb-zig/src/lib.zig#L2612)) and batch-decode `SortedNode` ([`lib.zig#L2481-L2528`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528)):** Change `var key_buf: [256]u8 = @splat(0)` to `undefined`, and read/write `SortedNode` via one stack `[146]u8` / `[418]u8` buffer.
- **Direct leaf slot read in `sortedGetByIndex` ([`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680)):** When `hdr[0] == .leaf`, seek to `node_ptr + 2 + rem * 9` and read 1 `Slot` instead of calling `readSortedNode`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1197-L1212`](../bench_xitdb.odin#L1197-L1212))

```odin
1197 | 	// 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
1198 | 	t4 := time.now()
1199 | 	for k in keys {
1200 | 		rit, _ := xitdb.sorted_map_iterator_from_string(sm, k)
1201 | 		for _ in 0 ..< 10 {
1202 | 			c_maybe, _ := xitdb.cursor_iterator_next(&rit)
1203 | 			if c_maybe == nil do break
1204 | 		}
1205 | 	}
1206 | 	elapsed_range_seek := time.since(t4)
1207 | 
1208 | 	print_result(Bench_Result{
1209 | 		name    = "Sorted_Map (B+Tree) lower-bound page(10)",
1210 | 		ops     = n,
1211 | 		elapsed = elapsed_range_seek,
1212 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1221-L1235`](../bench_xitdb.zig#L1221-L1235))

```zig
1221 |     // 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
1222 |     const t4 = std.Io.Clock.awake.now(io);
1223 |     for (keys) |k| {
1224 |         var rit = try sm.iteratorFrom(k);
1225 |         for (0..10) |_| {
1226 |             if ((try rit.next()) == null) break;
1227 |         }
1228 |     }
1229 |     const elapsed_range_seek = t4.untilNow(io, .awake).nanoseconds;
1230 | 
1231 |     try printResult(stdout, .{
1232 |         .name = "Sorted_Map (B+Tree) lower-bound page(10)",
1233 |         .ops = n,
1234 |         .elapsed_ns = elapsed_range_seek,
1235 |     });
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

### Reached Odin Procedures (`29` procedures across `6` files · `527` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_iterator_from_string` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L702-L704`](../../xitdb/collections.odin#L702-L704) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1069-L1090`](../../xitdb/cursor.odin#L1069-L1090) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_key` | `depth 1` (from `sorted_map_iterator_from_string`) | 92 | [`xitdb/cursor.odin#L842-L933`](../../xitdb/cursor.odin#L842-L933) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1034-L1067`](../../xitdb/cursor.odin#L1034-L1067) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 4 | [`xitdb/cursor.odin#L59-L62`](../../xitdb/cursor.odin#L59-L62) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 12 | [`xitdb/cursor.odin#L769-L780`](../../xitdb/cursor.odin#L769-L780) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator_sorted_from_key`, `_sorted_header`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L175-L191`](../../xitdb/core.odin#L175-L191) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator_sorted_from_key`, `_sorted_header`, `compare_key`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 2` (from `cursor_iterator_sorted_from_key`, `sorted_entry_key_slot`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 13 | [`xitdb/btree.odin#L1136-L1148`](../../xitdb/btree.odin#L1136-L1148) |
| `xitdb/btree.odin` | `compare_key` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 60 | [`xitdb/btree.odin#L1157-L1216`](../../xitdb/btree.odin#L1157-L1216) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `_iterator_next_internal`) | 15 | [`xitdb/cursor.odin#L697-L711`](../../xitdb/cursor.odin#L697-L711) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L692-L695`](../../xitdb/cursor.odin#L692-L695) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 3` (from `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `_sorted_header`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L281-L323`](../../xitdb/core.odin#L281-L323) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `slot_from_slice`, `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `slot_from_slice`, `core_read_slot`, `_fill_slot_block_from`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 3` (from `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/core.odin` | `core_slice_at` | `depth 3` (from `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L420-L436`](../../xitdb/core.odin#L420-L436) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `sorted_entry_key_slot`) | 5 | [`xitdb/core.odin#L556-L560`](../../xitdb/core.odin#L556-L560) |
| `xitdb/core.odin` | `core_read_i64` | `depth 3` (from `compare_key`) | 24 | [`xitdb/core.odin#L488-L511`](../../xitdb/core.odin#L488-L511) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_btree_iter_level`, `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L670-L690`](../../xitdb/cursor.odin#L670-L690) |
| `xitdb/database.odin` | `is_root` | `depth 4` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 4` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `core_read_slot`) | 24 | [`xitdb/core.odin#L531-L554`](../../xitdb/core.odin#L531-L554) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `_fill_slot_block_from`, `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 5` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
