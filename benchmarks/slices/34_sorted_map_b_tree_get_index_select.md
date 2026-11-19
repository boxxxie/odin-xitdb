# #34. `Sorted_Map (B+Tree) get_index select` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) · [Odin Harness (`bench_xitdb.odin#L1254-L1266`)](../bench_xitdb.odin#L1254-L1266) · [Zig Harness (`bench_xitdb.zig#L1261-L1273`)](../bench_xitdb.zig#L1261-L1273)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **116** | 116.0 ± 1.2 | 1.1% | 117.6 | 8,620,690 | - | **1.53x Odin** (`z = 32.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 178 | 177.6 ± 4.1 | 2.3% | 181.0 | 5,617,978 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1254-L1266`](../bench_xitdb.odin#L1254-L1266))

```odin
1254 | 	// 3d. Order-Statistic B+Tree positional select (`sorted_map_get_index_kv_pair`)
1255 | 	t6 := time.now()
1256 | 	for i in 0 ..< n {
1257 | 		kv_maybe, _ := xitdb.sorted_map_get_index_kv_pair(sm, i64(i))
1258 | 		assert(kv_maybe != nil)
1259 | 	}
1260 | 	elapsed_select := time.since(t6)
1261 | 
1262 | 	print_result(Bench_Result{
1263 | 		name    = "Sorted_Map (B+Tree) get_index select",
1264 | 		ops     = n,
1265 | 		elapsed = elapsed_select,
1266 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1261-L1273`](../bench_xitdb.zig#L1261-L1273))

```zig
1261 |     // 3d. Order-Statistic B+Tree positional select (`sorted_map_get_index_kv_pair`)
1262 |     const t6 = std.Io.Clock.awake.now(io);
1263 |     for (0..n) |i| {
1264 |         const kv_maybe = try sm.getIndexKeyValuePair(@intCast(i));
1265 |         std.debug.assert(kv_maybe != null);
1266 |     }
1267 |     const elapsed_select = t6.untilNow(io, .awake).nanoseconds;
1268 | 
1269 |     try printResult(stdout, .{
1270 |         .name = "Sorted_Map (B+Tree) get_index select",
1271 |         .ops = n,
1272 |         .elapsed_ns = elapsed_select,
1273 |     });
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

### Reached Odin Procedures (`37` procedures across `6` files · `672` LOC) (Active `_exec_path_part` arms: `Sorted_Map_Get_Index`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_get_index_kv_pair` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L768-L776`](../../xitdb/collections.odin#L768-L776) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `sorted_map_get_index_kv_pair`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 1` (from `sorted_map_get_index_kv_pair`) | 19 | [`xitdb/cursor.odin#L383-L401`](../../xitdb/cursor.odin#L383-L401) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `cursor_read_path`, `cursor_read_kv_pair`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 2` (from `cursor_read_kv_pair`, `database_kv_key_position`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/types.odin` | `decode_kv_pair_at` | `depth 2` (from `cursor_read_kv_pair`) | 35 | [`xitdb/types.odin#L1215-L1249`](../../xitdb/types.odin#L1215-L1249) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 2` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L580-L585`](../../xitdb/database.odin#L580-L585) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 2` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L587-L592`](../../xitdb/database.odin#L587-L592) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 4` (from `_exec_path_part`, `decode_kv_pair_at`, `core_read_slot_raw_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `descend_by_rank` | `depth 4` (from `_exec_path_part`) | 48 | [`xitdb/btree.odin#L105-L152`](../../xitdb/btree.odin#L105-L152) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 3` (from `decode_kv_pair_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 3` (from `decode_kv_pair_at`) | 10 | [`xitdb/types.odin#L1145-L1154`](../../xitdb/types.odin#L1145-L1154) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `decode_kv_pair_at`, `database_read_root_trailer`, `slot_from_slice`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 3` (from `database_kv_key_position`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 4` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 4` (from `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `database_read_root_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `kv_pair_from_bytes`, `slot_from_slice`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/core.odin` | `core_read_at` | `depth 5` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 5` (from `descend_by_rank`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `descend_by_rank`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/core.odin` | `_overlay_length` | `depth 5` (from `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 6` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 6` (from `core_read_block_at`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 6` (from `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
