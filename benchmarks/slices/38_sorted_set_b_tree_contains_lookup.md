# #38. `Sorted_Set (B+Tree) contains lookup` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1316-L1330`)](../bench_xitdb.odin#L1316-L1330) · [Zig Harness (`bench_xitdb.zig#L1338-L1352`)](../bench_xitdb.zig#L1338-L1352)

- **Touched Library Scope:** **79** procedures across **7** `xitdb/*.odin` files (**1948** lines of library code)
- **Direct Benchmark Entry Points:** `array_list_get_cursor`, `read_sorted_set_init`, `sorted_set_contains`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1316-L1330`)

```odin
1316 | 	ss_cur, _ := xitdb.array_list_get_cursor(history, -1)
1317 | 	rss, _ := xitdb.read_sorted_set_init(ss_cur.?)
1318 | 
1319 | 	t10 := time.now()
1320 | 	for k in keys {
1321 | 		ok, _ := xitdb.sorted_set_contains(rss, k)
1322 | 		assert(ok)
1323 | 	}
1324 | 	elapsed_sset_contains := time.since(t10)
1325 | 
1326 | 	print_result(Bench_Result{
1327 | 		name    = "Sorted_Set (B+Tree) contains lookup",
1328 | 		ops     = n,
1329 | 		elapsed = elapsed_sset_contains,
1330 | 	})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1338-L1352</code>)</strong></summary>

```zig
1338 |     const ss_cur = (try history.getCursor(-1)).?;
1339 |     const rss = try DB.SortedSet(.read_only).init(ss_cur);
1340 | 
1341 |     const t10 = std.Io.Clock.awake.now(io);
1342 |     for (keys) |k| {
1343 |         const ok = try rss.contains(k);
1344 |         std.debug.assert(ok);
1345 |     }
1346 |     const elapsed_sset_contains = t10.untilNow(io, .awake).nanoseconds;
1347 | 
1348 |     try printResult(stdout, .{
1349 |         .name = "Sorted_Set (B+Tree) contains lookup",
1350 |         .ops = n,
1351 |         .elapsed_ns = elapsed_sset_contains,
1352 |     });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_sorted_set_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L803-L811`](../../xitdb/collections.odin#L803-L811) |
| `xitdb/collections.odin` | `sorted_set_contains` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L860-L862`](../../xitdb/collections.odin#L860-L862) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`, `sorted_set_contains_by_bytes`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `read_sorted_set_init`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/collections.odin` | `sorted_set_contains_by_bytes` | `depth 1` (from `sorted_set_contains`) | 5 | [`xitdb/collections.odin#L854-L858`](../../xitdb/collections.odin#L854-L858) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/database.odin` | `init_tag` | `depth 3` (from `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `sorted_put`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `sorted_target_slot`, `read_array_list_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1107-L1111`](../../xitdb/btree.odin#L1107-L1111) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_truncate_with_header`, `database_commit_root`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `btree_reusable`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1654-L2027`](../../xitdb/btree.odin#L1654-L2027) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2179-L2190`](../../xitdb/btree.odin#L2179-L2190) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `decode_kv_pair`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/core.odin` | `core_sync` | `depth 4` (from `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `sorted_put`, `read_array_list_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `sorted_get`, `sorted_put`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1067-L1105`](../../xitdb/btree.odin#L1067-L1105) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 5` (from `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `sorted_get`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 5` (from `sorted_target_slot`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `sorted_put`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1591-L1597`](../../xitdb/btree.odin#L1591-L1597) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1121-L1127`](../../xitdb/btree.odin#L1121-L1127) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1143-L1148`](../../xitdb/btree.odin#L1143-L1148) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1599-L1652`](../../xitdb/btree.odin#L1599-L1652) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1113-L1119`](../../xitdb/btree.odin#L1113-L1119) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1293-L1302`](../../xitdb/types.odin#L1293-L1302) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1028-L1065`](../../xitdb/btree.odin#L1028-L1065) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1213-L1229`](../../xitdb/btree.odin#L1213-L1229) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1232-L1245`](../../xitdb/btree.odin#L1232-L1245) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_read_i64` | `depth 6` (from `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1149-L1183`](../../xitdb/types.odin#L1149-L1183) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `write_kv_pair`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1130-L1139`](../../xitdb/types.odin#L1130-L1139) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Sorted_Set (B+Tree) contains lookup`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/btree.odin` (17 procedures · 791 lines: [`L83–L89`](../../xitdb/btree.odin#L83-L89), [`L1028–L1065`](../../xitdb/btree.odin#L1028-L1065), [`L1067–L1105`](../../xitdb/btree.odin#L1067-L1105), [`L1107–L1111`](../../xitdb/btree.odin#L1107-L1111), [`L1113–L1119`](../../xitdb/btree.odin#L1113-L1119), [`L1121–L1127`](../../xitdb/btree.odin#L1121-L1127), [`L1129–L1141`](../../xitdb/btree.odin#L1129-L1141), [`L1143–L1148`](../../xitdb/btree.odin#L1143-L1148), [`L1150–L1209`](../../xitdb/btree.odin#L1150-L1209), [`L1213–L1229`](../../xitdb/btree.odin#L1213-L1229), [`L1232–L1245`](../../xitdb/btree.odin#L1232-L1245), [`L1247–L1359`](../../xitdb/btree.odin#L1247-L1359), [`L1591–L1597`](../../xitdb/btree.odin#L1591-L1597), [`L1599–L1652`](../../xitdb/btree.odin#L1599-L1652), [`L1654–L2027`](../../xitdb/btree.odin#L1654-L2027), [`L2179–L2190`](../../xitdb/btree.odin#L2179-L2190), [`L2192–L2209`](../../xitdb/btree.odin#L2192-L2209))

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

### `xitdb/collections.odin` (4 procedures · 20 lines: [`L41–L43`](../../xitdb/collections.odin#L41-L43), [`L803–L811`](../../xitdb/collections.odin#L803-L811), [`L854–L858`](../../xitdb/collections.odin#L854-L858), [`L860–L862`](../../xitdb/collections.odin#L860-L862))

#### [`array_list_get_cursor`](../../xitdb/collections.odin#L41-L43) — `ENTRY POINT` (`L41–L43`)

```odin
  41 | array_list_get_cursor :: proc(a: Read_Array_List, index: i64) -> (Maybe(Read_Cursor), Error) {
  42 | 	return cursor_read_path(a.cursor, []Path_Part{Array_List_Get{index = index}})  // <== [calls cursor_read_path]
  43 | }
```

#### [`read_sorted_set_init`](../../xitdb/collections.odin#L803-L811) — `ENTRY POINT` (`L803–L811`)

```odin
 803 | read_sorted_set_init :: proc(cursor: Read_Cursor) -> (res: Read_Sorted_Set, err: Error) {
 804 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 805 | 	#partial switch slot_ptr.slot.tag {
 806 | 	case .None, .Sorted_Map, .Sorted_Set:
 807 | 		return Read_Sorted_Set{cursor = cursor}, nil
 808 | 	case:
 809 | 		return {}, .Unexpected_Tag
 810 | 	}
 811 | }
```

#### [`sorted_set_contains_by_bytes`](../../xitdb/collections.odin#L854-L858) — `DEPTH 1` (`L854–L858`)

```odin
 854 | sorted_set_contains_by_bytes :: proc(s: Read_Sorted_Set, key: []u8) -> (res: bool, err: Error) {
 855 | 	mc := cursor_read_path(s.cursor, []Path_Part{Sorted_Map_Get{target = Sorted_Map_Get_Key{key = key}}}) or_return  // <== [calls cursor_read_path]
 856 | 	_, ok := mc.?
 857 | 	return ok, nil
 858 | }
```

#### [`sorted_set_contains`](../../xitdb/collections.odin#L860-L862) — `ENTRY POINT` (`L860–L862`)

```odin
 860 | sorted_set_contains :: proc(s: Read_Sorted_Set, key: string) -> (res: bool, err: Error) {
 861 | 	return sorted_set_contains_by_bytes(s, transmute([]u8)key)  // <== [calls sorted_set_contains_by_bytes]
 862 | }
```

### `xitdb/core.odin` (14 procedures · 377 lines: [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L238–L285`](../../xitdb/core.odin#L238-L285), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437), [`L441–L457`](../../xitdb/core.odin#L441-L457), [`L509–L532`](../../xitdb/core.odin#L509-L532), [`L534–L550`](../../xitdb/core.odin#L534-L550), [`L552–L575`](../../xitdb/core.odin#L552-L575), [`L583–L600`](../../xitdb/core.odin#L583-L600))

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 5` (`L125–L142`)

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

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 5` (`L144–L151`)

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

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 4` (`L153–L174`)

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

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 3` (`L176–L192`)

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

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 4` (`L219–L236`)

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

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 5` (`L288–L323`)

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

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 4` (`L326–L359`)

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

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 4` (`L362–L437`)

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

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 6` (`L509–L532`)

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

### `xitdb/cursor.odin` (2 procedures · 23 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L68–L79`](../../xitdb/cursor.odin#L68-L79))

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

#### [`cursor_read_path`](../../xitdb/cursor.odin#L68-L79) — `DEPTH 1` (`L68–L79`)

```odin
  68 | cursor_read_path :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Read_Cursor), err: Error) {
  69 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  70 | 	slot_ptr: Slot_Pointer
  71 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  72 | 	if err != nil {
  73 | 		if err == .Key_Not_Found {
  74 | 			return nil, nil
  75 | 		}
  76 | 		return nil, err
  77 | 	}
  78 | 	return Read_Cursor{slot_ptr = slot_ptr, db = c.db}, nil
  79 | }
```

### `xitdb/database.odin` (18 procedures · 450 lines: [`L13–L18`](../../xitdb/database.odin#L13-L18), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L343–L362`](../../xitdb/database.odin#L343-L362), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414), [`L416–L421`](../../xitdb/database.odin#L416-L421), [`L423–L438`](../../xitdb/database.odin#L423-L438), [`L440–L460`](../../xitdb/database.odin#L440-L460), [`L462–L468`](../../xitdb/database.odin#L462-L468), [`L470–L482`](../../xitdb/database.odin#L470-L482), [`L503–L515`](../../xitdb/database.odin#L503-L515), [`L517–L528`](../../xitdb/database.odin#L517-L528), [`L530–L535`](../../xitdb/database.odin#L530-L535), [`L552–L619`](../../xitdb/database.odin#L552-L619), [`L621–L1382`](../../xitdb/database.odin#L621-L1382))

#### [`transaction_is_root_position`](../../xitdb/database.odin#L13-L18) — `DEPTH 4` (`L13–L18`)

```odin
  13 | transaction_is_root_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  14 | 	if t == nil || pos == nil || t.root_position == nil {
  15 | 		return false
  16 | 	}
  17 | 	return pos.? == t.root_position.?
  18 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 3` (`L237–L244`)

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

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 4` (`L319–L334`)

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

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 5` (`L384–L398`)

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

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 3` (`L400–L407`)

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

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 4` (`L409–L414`)

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

#### [`init_tag`](../../xitdb/database.odin#L423-L438) — `DEPTH 3` (`L423–L438`)

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

#### [`database_kv_key_offset`](../../xitdb/database.odin#L530-L535) — `DEPTH 5` (`L530–L535`)

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

#### [`_exec_path_part`](../../xitdb/database.odin#L621-L1382) — `DEPTH 3` (`L621–L1382`) — Active `Path_Part` arms: `Array_List_Init`, `Array_List_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`

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
   ... | 	// ... [lines 715–1126: untouched Path_Part arms omitted] ...
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
   ... | 	// ... [lines 1233–1379: untouched Path_Part arms omitted] ...
1380 | 
1381 | 	return {}, .Unreachable
1382 | }
```

### `xitdb/hamt.odin` (1 procedures · 68 lines: [`L385–L452`](../../xitdb/hamt.odin#L385-L452))

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

### `xitdb/types.odin` (23 procedures · 219 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051), [`L1065–L1067`](../../xitdb/types.odin#L1065-L1067), [`L1069–L1074`](../../xitdb/types.odin#L1069-L1074), [`L1076–L1084`](../../xitdb/types.odin#L1076-L1084), [`L1092–L1097`](../../xitdb/types.odin#L1092-L1097), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1116–L1118`](../../xitdb/types.odin#L1116-L1118), [`L1130–L1139`](../../xitdb/types.odin#L1130-L1139), [`L1149–L1183`](../../xitdb/types.odin#L1149-L1183), [`L1200–L1226`](../../xitdb/types.odin#L1200-L1226), [`L1293–L1302`](../../xitdb/types.odin#L1293-L1302), [`L1329–L1331`](../../xitdb/types.odin#L1329-L1331), [`L1416–L1421`](../../xitdb/types.odin#L1416-L1421))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 3` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 4` (`L871–L877`)

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

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 5` (`L985–L991`)

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

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 5` (`L1012–L1020`)

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

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 4` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 4` (`L1030–L1037`)

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

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 6` (`L1039–L1051`)

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

#### [`kv_pair_length`](../../xitdb/types.odin#L1116-L1118) — `DEPTH 7` (`L1116–L1118`)

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

#### [`radix_shift`](../../xitdb/types.odin#L1416-L1421) — `DEPTH 4` (`L1416–L1421`)

```odin
1416 | radix_shift :: #force_inline proc(key: i64) -> u8 {
1417 | 	if key < SLOT_COUNT {
1418 | 		return 0
1419 | 	}
1420 | 	return u8((63 - intrinsics.count_leading_zeros(u64(key))) >> 2)
1421 | }
```

