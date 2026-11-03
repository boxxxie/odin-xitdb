# #29. `Sorted_Map (B+Tree) key lookup` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1150-L1165`)](../bench_xitdb.odin#L1150-L1165) · [Zig Harness (`bench_xitdb.zig#L1176-L1191`)](../bench_xitdb.zig#L1176-L1191)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **163** | 163.0 ± 1.0 | 0.6% | 164.0 | 6,134,969 | - | **26.02x Odin** (`z = 218.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 4,242 | 4,262.8 ± 41.9 | 1.0% | 4,320.4 | 235,738 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Binary Search ($O(\log_2 B)$) vs. Linear Scan ($O(B)$) in Nodes ([`xitdb/btree.odin#L1200-L1480`](../../xitdb/btree.odin#L1200-L1480) vs. [`lib.zig#L2634-L2760`](../../reference/xitdb-zig/src/lib.zig#L2634-L2760)):** In Zig's `sortedGet`, `sortedRank`, and `sortedPut`, both branch separator search (`while (i + 1 < node.num ...)`) and leaf entry search (`for (0..node.num) |i|`) use **linear scans**, performing up to 32 `readKvPair` + `compareKey` disk seeks per node. Odin uses **binary search** on both branch separators and leaf entries, cutting key comparisons and disk seeks from up to 32 down to $\le 5$ per node (**11.6x–32.1x faster**).
- **Single-Read Node Decoding Only Up to `node.num` ([`xitdb/btree.odin#L1028-L1105`](../../xitdb/btree.odin#L1028-L1105)):** Zig's [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) executes **98 separate `takeInt` calls** for every branch node (reading all 32 children, 32 separators, and 32 counts even if `node.num == 2`). Odin reads the block in one `core_read_exact` call and decodes only `0 ..< node.num` slots.
- **O(1) Direct Leaf Slot Seek in `sorted_get_by_index` ([`xitdb/btree.odin#L1301-L1336`](../../xitdb/btree.odin#L1301-L1336)):** On `#34 Sorted_Map get_index select` (**51.25x faster in Odin: 64 ns vs 3,280 ns**), Odin reads the 2-byte leaf header and seeks straight to `node_ptr + 2 + rem * 9` to read the single target `Slot`, whereas Zig's [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) deserializes all 32 leaf slots via `readSortedNode`.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Replace linear scans in `sortedGet`, `sortedRank`, and `sortedPut` with binary search (`~12 lines` in [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** A standard `while (lo < hi)` binary search over `node.separators[1..node.num]` (branches) and `node.entries[0..node.num]` (leaves) reduces `readKvPair` + `compareKey` calls by up to 6x per level with zero structural changes.
- **Batch-read `SortedNode` from a stack buffer and slice `0..node.num` ([`lib.zig#L2481-L2528`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528)):** Eliminates up to 98 `takeInt`/`writeInt` calls per B+Tree node.
- **Direct leaf slot read in `sortedGetByIndex` ([`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680)):** When `kind == .leaf`, seek to `node_ptr + 2 + rem * 9` and read 1 `Slot` instead of calling `readSortedNode`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1150-L1165`](../bench_xitdb.odin#L1150-L1165))

```odin
1150 | 	sm_cur, _ := xitdb.array_list_get_cursor(history, 0)
1151 | 	sm, _ := xitdb.read_sorted_map_init(sm_cur.?)
1152 | 
1153 | 	t1 := time.now()
1154 | 	for k, idx in keys {
1155 | 		vc, _ := xitdb.sorted_map_get_cursor(sm, k)
1156 | 		v, _ := xitdb.cursor_read_uint(vc.?)
1157 | 		assert(v == u64(idx))
1158 | 	}
1159 | 	elapsed_get := time.since(t1)
1160 | 
1161 | 	print_result(Bench_Result{
1162 | 		name    = "Sorted_Map (B+Tree) key lookup",
1163 | 		ops     = n,
1164 | 		elapsed = elapsed_get,
1165 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1176-L1191`](../bench_xitdb.zig#L1176-L1191))

```zig
1176 |     const sm_cur = (try history.getCursor(0)).?;
1177 |     const sm = try DB.SortedMap(.read_only).init(sm_cur);
1178 | 
1179 |     const t1 = std.Io.Clock.awake.now(io);
1180 |     for (keys, 0..) |k, idx| {
1181 |         const vc = (try sm.getCursor(k)).?;
1182 |         const v = try vc.readUint();
1183 |         std.debug.assert(v == @as(u64, @intCast(idx)));
1184 |     }
1185 |     const elapsed_get = t1.untilNow(io, .awake).nanoseconds;
1186 | 
1187 |     try printResult(stdout, .{
1188 |         .name = "Sorted_Map (B+Tree) key lookup",
1189 |         .ops = n,
1190 |         .elapsed_ns = elapsed_get,
1191 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `SortedMap` | 101 | Typed counted B+Tree `SortedMap` wrapper (`put`, `getCursor`, `getIndex`, `rank`, `remove`) | [`lib.zig#L4128-L4228`](../../reference/xitdb-zig/src/lib.zig#L4128-L4228) |
| `SortedSet` | 66 | Typed counted B+Tree `SortedSet` wrapper | [`lib.zig#L4232-L4297`](../../reference/xitdb-zig/src/lib.zig#L4232-L4297) |
| `readSlotPointer.sorted_map` | 126 | `PathPart` switch arms: `.sorted_map_init`, `.sorted_map_get`, `.sorted_map_get_index`, `.sorted_map_remove` | [`lib.zig#L1399-L1524`](../../reference/xitdb-zig/src/lib.zig#L1399-L1524) |
| `readSortedNode` | 31 | Counted B+Tree node deserializer (34–98 `takeInt` calls) | [`lib.zig#L2481-L2511`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) |
| `writeSortedNodeAt` | 16 | Counted B+Tree node serializer (34–98 `writeInt` calls) | [`lib.zig#L2513-L2528`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) |
| `compareKey` | 31 | Lexicographic key comparison against `.short_bytes` / `.bytes` slot | [`lib.zig#L2599-L2629`](../../reference/xitdb-zig/src/lib.zig#L2599-L2629) |
| `sortedGet` | 25 | Counted B+Tree key lookup descent (linear separator/leaf scan) | [`lib.zig#L2634-L2658`](../../reference/xitdb-zig/src/lib.zig#L2634-L2658) |
| `sortedGetByIndex` | 20 | Counted B+Tree O(log N) rank selection by subtree counts | [`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) |
| `sortedRank` | 25 | Counted B+Tree O(log N) order-statistic rank query | [`lib.zig#L2683-L2707`](../../reference/xitdb-zig/src/lib.zig#L2683-L2707) |
| `sortedPut` | 140 | Counted B+Tree key insertion, leaf/branch split, and separator propagation | [`lib.zig#L2736-L2875`](../../reference/xitdb-zig/src/lib.zig#L2736-L2875) |
| `sortedRemove` | 40 | Counted B+Tree key deletion and sibling merge/rebalance | [`lib.zig#L2879-L2918`](../../reference/xitdb-zig/src/lib.zig#L2879-L2918) |

### Reached Odin Procedures (`35` procedures across `7` files · `764` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_sorted_map_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`, `sorted_map_get_cursor_by_bytes`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `read_sorted_map_init`, `cursor_read_uint`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 1` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `read_array_list_slot`, `sorted_target_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `sorted_get`, `sorted_entry_key_slot`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_length` | `depth 5` (from `read_array_list_slot`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `read_array_list_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `sorted_get`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 5` (from `sorted_target_slot`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/core.odin` | `core_read_i64` | `depth 6` (from `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
