# #30. `Sorted_Map (B+Tree) rank query` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1167-L1178`)](../bench_xitdb.odin#L1167-L1178) · [Zig Harness (`bench_xitdb.zig#L1193-L1204`)](../bench_xitdb.zig#L1193-L1204)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **131** | 131.0 ± 0.7 | 0.5% | 131.8 | 7,633,588 | - | **32.10x Odin** (`z = 76.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 4,205 | 4,261.2 ± 121.2 | 2.8% | 4,428.8 | 237,812 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1167-L1178`](../bench_xitdb.odin#L1167-L1178))

```odin
1167 | 	t2 := time.now()
1168 | 	for k in keys {
1169 | 		rk, _ := xitdb.sorted_map_rank(sm, k)
1170 | 		assert(rk >= 0 && rk < i64(n))
1171 | 	}
1172 | 	elapsed_rank := time.since(t2)
1173 | 
1174 | 	print_result(Bench_Result{
1175 | 		name    = "Sorted_Map (B+Tree) rank query",
1176 | 		ops     = n,
1177 | 		elapsed = elapsed_rank,
1178 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1193-L1204`](../bench_xitdb.zig#L1193-L1204))

```zig
1193 |     const t2 = std.Io.Clock.awake.now(io);
1194 |     for (keys) |k| {
1195 |         const rk = try sm.rank(k);
1196 |         std.debug.assert(rk < @as(u64, @intCast(n)));
1197 |     }
1198 |     const elapsed_rank = t2.untilNow(io, .awake).nanoseconds;
1199 | 
1200 |     try printResult(stdout, .{
1201 |         .name = "Sorted_Map (B+Tree) rank query",
1202 |         .ops = n,
1203 |         .elapsed_ns = elapsed_rank,
1204 |     });
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

### Reached Odin Procedures (`20` procedures across `6` files · `434` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_rank` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L762-L764`](../../xitdb/collections.odin#L762-L764) |
| `xitdb/collections.odin` | `sorted_map_rank_by_bytes` | `depth 1` (from `sorted_map_rank`) | 11 | [`xitdb/collections.odin#L738-L748`](../../xitdb/collections.odin#L738-L748) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `sorted_map_rank_by_bytes`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `sorted_map_rank_by_bytes`, `sorted_rank`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `sorted_map_rank_by_bytes`, `sorted_rank`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `sorted_map_rank_by_bytes`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_rank` | `depth 2` (from `sorted_map_rank_by_bytes`) | 120 | [`xitdb/btree.odin#L1441-L1560`](../../xitdb/btree.odin#L1441-L1560) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_slice_at` | `depth 3` (from `sorted_rank`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `sorted_rank`, `sorted_entry_key_slot`, `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 3` (from `sorted_rank`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 3` (from `sorted_rank`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `sorted_entry_key_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/core.odin` | `core_read_i64` | `depth 4` (from `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `root_header_from_bytes`, `core_read_slot_raw`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
