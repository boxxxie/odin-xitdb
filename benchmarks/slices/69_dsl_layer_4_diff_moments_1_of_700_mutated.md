# #69. `DSL Layer 4: diff_moments (1 of 700 mutated)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2260-L2277`)](../bench_xitdb.odin#L2260-L2277)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **390,102** | 389,353.4 ± 1,302.6 | 0.3% | 390,342.4 | 2,563 | - |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Odin-Native 5-Layer Ergonomic DSL ([`xitdb/dsl.odin`](../../xitdb/dsl.odin)):** Built directly on top of the wire-compatible core (`Read_Cursor`, `Write_Cursor`, `Hash_Map`, `Sorted_Map`, `Array_List`), providing path selectors (`Layer 1`), transactional `Tx` + automatic B+Tree secondary index maintenance (`Layer 2`), reflection-driven struct `marshal`/`unmarshal` & cycle-safe Datomic `pull` (`Layer 3`), structural `diff_moments` & `history_of` (`Layer 4`), and a stratified Datalog engine with B+Tree prefix pushdown (`Layer 5`).
- **Zero-Allocation Hot Paths & B+Tree Index Selection ([`xitdb/dsl.odin#L2800-L3783`](../../xitdb/dsl.odin#L2800-L3783)):** The Datalog engine inspects bound variables in pattern clauses, automatically selecting `Sorted_Map` (`indices/<index>`) range iterators for prefix-bound lookups and falling back to full collection scans only when unbound.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Comptime Struct Marshaling & Pull Projection in Zig:** Zig's `@typeInfo(T)` comptime reflection maps naturally to Odin's runtime `type_info_of(T)` in `marshal`/`unmarshal` (`Layer 3`) and could be layered cleanly on top of `lib.zig` without altering the v1 wire format.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L2260-L2277`](../bench_xitdb.odin#L2260-L2277))

```odin
2260 | 	// 4. Layer 4: O(1) Subtree-Skipping `diff_moments` & `history_of`
2261 | 	{
2262 | 		// Commit a small delta in Moment 2 (mutating 1 key out of 500 users + 200 profiles)
2263 | 		tx := xitdb.tx_init(&db, base_moment = -1, allocator = context.temp_allocator)
2264 | 		_ = xitdb.tx_put(&tx, ".users[\"u0042\"].age", u64(99))
2265 | 		_, _ = xitdb.tx_commit(&tx)
2266 | 
2267 | 		Q :: 200
2268 | 		t0 := time.now()
2269 | 		for _ in 0 ..< Q {
2270 | 			diffs, d_err := xitdb.diff_moments(&db, 1, 2, false, context.temp_allocator)
2271 | 			assert(d_err == nil && len(diffs) == 1)
2272 | 		}
2273 | 		print_result(Bench_Result{
2274 | 			name    = "DSL Layer 4: diff_moments (1 of 700 mutated)",
2275 | 			ops     = Q,
2276 | 			elapsed = time.since(t0),
2277 | 		})
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |
| `HashMap` | 96 | Typed `HashMap(.read_only/.read_write)` wrapper (`put`, `putKey`, `getCursor`, `remove`) | [`lib.zig#L3835-L3930`](../../reference/xitdb-zig/src/lib.zig#L3835-L3930) |
| `SortedMap` | 101 | Typed counted B+Tree `SortedMap` wrapper (`put`, `getCursor`, `getIndex`, `rank`, `remove`) | [`lib.zig#L4128-L4228`](../../reference/xitdb-zig/src/lib.zig#L4128-L4228) |
| `ArrayList` | 90 | Typed 16-way Radix Trie `ArrayList` wrapper (`append`, `getCursor`, `put`, `slice`) | [`lib.zig#L4299-L4388`](../../reference/xitdb-zig/src/lib.zig#L4299-L4388) |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |

### Reached Odin Procedures (`155` procedures across `8` files · `3884` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `tx_init` | **Entry Point** (`depth 0`) | 12 | [`xitdb/dsl.odin#L905-L916`](../../xitdb/dsl.odin#L905-L916) |
| `xitdb/dsl.odin` | `tx_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/dsl.odin#L993-L997`](../../xitdb/dsl.odin#L993-L997) |
| `xitdb/dsl.odin` | `tx_commit` | **Entry Point** (`depth 0`) | 63 | [`xitdb/dsl.odin#L1334-L1396`](../../xitdb/dsl.odin#L1334-L1396) |
| `xitdb/dsl.odin` | `diff_moments` | **Entry Point** (`depth 0`) | 12 | [`xitdb/dsl.odin#L2394-L2405`](../../xitdb/dsl.odin#L2394-L2405) |
| `xitdb/dsl.odin` | `_tx_parse_steps` | `depth 1` (from `tx_put`) | 11 | [`xitdb/dsl.odin#L975-L985`](../../xitdb/dsl.odin#L975-L985) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`, `diff_moments`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L89-L96`](../../xitdb/collections.odin#L89-L96) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`, `diff_moments`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `tx_commit`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`, `_diff_recursive`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `diff_moments`, `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/dsl.odin` | `diff_cursors` | `depth 1` (from `diff_moments`) | 9 | [`xitdb/dsl.odin#L2407-L2415`](../../xitdb/dsl.odin#L2407-L2415) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 2` (from `_tx_parse_steps`) | 3 | [`xitdb/dsl.odin#L235-L237`](../../xitdb/dsl.odin#L235-L237) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 2` (from `write_array_list_init`, `array_list_append_context`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`) | 37 | [`xitdb/cursor.odin#L436-L472`](../../xitdb/cursor.odin#L436-L472) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L80-L94`](../../xitdb/cursor.odin#L80-L94) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`, `sorted_map_get_cursor_by_bytes`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `read_array_list_init`, `cursor_count`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/dsl.odin` | `diff_changes_destroy` | `depth 2` (from `diff_cursors`) | 10 | [`xitdb/dsl.odin#L938-L947`](../../xitdb/dsl.odin#L938-L947) |
| `xitdb/dsl.odin` | `_diff_recursive` | `depth 2` (from `diff_cursors`) | 213 | [`xitdb/dsl.odin#L2417-L2629`](../../xitdb/dsl.odin#L2417-L2629) |
| `xitdb/dsl.odin` | `parse_steps_buf` | `depth 3` (from `parse_steps`) | 127 | [`xitdb/dsl.odin#L239-L365`](../../xitdb/dsl.odin#L239-L365) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 3` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_write_path`, `cursor_resolved`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 3` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 3` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_write_path`, `cursor_read_path_slot`, `cursor_read_path`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 3` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/core.odin` | `core_sync` | `depth 3` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 3` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `cursor_count`, `_exec_path_part`, `core_read_i64_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 3` (from `cursor_count`, `_exec_path_part`, `cursor_iterator`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `cursor_count`, `cursor_iterator`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 3` (from `cursor_count`, `_exec_path_part`, `cursor_read_bytes_object`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/types.odin` | `check_long` | `depth 3` (from `cursor_count`) | 6 | [`xitdb/types.odin#L1482-L1487`](../../xitdb/types.odin#L1482-L1487) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `cursor_read_path_slot`, `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 3` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 3` (from `database_read_root_header`, `database_write_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 3` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 3` (from `database_read_root_header`, `_exec_path_part`, `_database_truncate_with_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 3` (from `_diff_recursive`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 3` (from `_diff_recursive`) | 9 | [`xitdb/dsl.odin#L2009-L2017`](../../xitdb/dsl.odin#L2009-L2017) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 3` (from `_diff_recursive`) | 45 | [`xitdb/cursor.odin#L891-L935`](../../xitdb/cursor.odin#L891-L935) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_diff_recursive`) | 22 | [`xitdb/cursor.odin#L1614-L1635`](../../xitdb/cursor.odin#L1614-L1635) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair_slots` | `depth 3` (from `_diff_recursive`) | 22 | [`xitdb/cursor.odin#L404-L425`](../../xitdb/cursor.odin#L404-L425) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 3` (from `_diff_recursive`) | 4 | [`xitdb/cursor.odin#L233-L236`](../../xitdb/cursor.odin#L233-L236) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 3` (from `_diff_recursive`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/dsl.odin` | `steps_destroy` | `depth 4` (from `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L39-L48`](../../xitdb/dsl.odin#L39-L48) |
| `xitdb/dsl.odin` | `steps_destroy_buf` | `depth 4` (from `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L57-L66`](../../xitdb/dsl.odin#L57-L66) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 4` (from `parse_steps_buf`) | 42 | [`xitdb/dsl.odin#L394-L435`](../../xitdb/dsl.odin#L394-L435) |
| `xitdb/dsl.odin` | `_push_step_buf` | `depth 4` (from `parse_steps_buf`) | 23 | [`xitdb/dsl.odin#L174-L196`](../../xitdb/dsl.odin#L174-L196) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 4` (from `parse_steps_buf`, `_parse_step_ident_or_bracket`) | 28 | [`xitdb/dsl.odin#L437-L464`](../../xitdb/dsl.odin#L437-L464) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 4` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 4` (from `cursor_reload_slot`, `read_array_list_slot`, `sorted_target_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 4` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 4` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_seek_to` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_write_slot` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 4` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 4` (from `read_slot_pointer`, `core_read_slot_at`, `read_map_slot`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_random_u64` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_commit_root` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`, `read_array_list_slot_append`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/core.odin` | `core_write_all` | `depth 5` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 5` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/core.odin` | `core_write_long` | `depth 5` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 5` (from `_exec_path_part`) | 38 | [`xitdb/hamt.odin#L343-L380`](../../xitdb/hamt.odin#L343-L380) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 5` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 4` (from `core_sync`, `core_write_all`, `core_flush`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`, `_init_btree_iter_level`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_overlay_length` | `depth 4` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`, `cursor_read_kv_pair_slots`, `core_read_slot_at`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L786-L789`](../../xitdb/cursor.odin#L786-L789) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 44 | [`xitdb/cursor.odin#L796-L839`](../../xitdb/cursor.odin#L796-L839) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 4` (from `cursor_iterator_next`) | 37 | [`xitdb/cursor.odin#L1538-L1574`](../../xitdb/cursor.odin#L1538-L1574) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`, `sorted_put`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `cursor_read_kv_pair_slots`, `core_read_slot_raw_at`, `read_map_slot`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 4` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L225-L231`](../../xitdb/cursor.odin#L225-L231) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 4` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/dsl.odin` | `_unescape_quoted_key` | `depth 5` (from `_parse_step_ident_or_bracket`, `_parse_bracketed_string`) | 26 | [`xitdb/dsl.odin#L367-L392`](../../xitdb/dsl.odin#L367-L392) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 5` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 5` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/core.odin` | `core_set_length` | `depth 5` (from `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/core.odin` | `_memory_resize` | `depth 5` (from `core_write_slot`, `core_write_all`, `_overlay_write_at`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `core_write_slot`, `read_array_list_slot`, `read_array_list_slot_append`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 5` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 5` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 5` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`, `read_map_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 6` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 6` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/core.odin` | `core_write_i64` | `depth 6` (from `core_write_long`, `database_write_root_header`, `sorted_put`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 6` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/types.odin` | `slot_with_full` | `depth 6` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `read_map_slot`, `_init_btree_iter_level`, `_fill_slot_block_from`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_iter_level`, `_init_btree_iter_level`) | 27 | [`xitdb/cursor.odin#L730-L756`](../../xitdb/cursor.odin#L730-L756) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `_init_btree_iter_level`, `_fill_slot_block_from`, `sorted_get`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 5` (from `cursor_read_bytes`) | 66 | [`xitdb/cursor.odin#L238-L303`](../../xitdb/cursor.odin#L238-L303) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 5` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1159-L1163`](../../xitdb/btree.odin#L1159-L1163) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 61 | [`xitdb/btree.odin#L1315-L1375`](../../xitdb/btree.odin#L1315-L1375) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 17 | [`xitdb/btree.odin#L2087-L2103`](../../xitdb/btree.odin#L2087-L2103) |
| `xitdb/btree.odin` | `sorted_put` | `depth 5` (from `_exec_path_part`) | 384 | [`xitdb/btree.odin#L1536-L1919`](../../xitdb/btree.odin#L1536-L1919) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2074-L2085`](../../xitdb/btree.odin#L2074-L2085) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 6` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `core_flush` | `depth 6` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/core.odin` | `_overlay_page` | `depth 7` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 7` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 7` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `kv_pair_read_buf_at`, `decode_kv_pair_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 6` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1119-L1157`](../../xitdb/btree.odin#L1119-L1157) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 6` (from `sorted_get`, `read_sorted_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 6 | [`xitdb/btree.odin#L1180-L1185`](../../xitdb/btree.odin#L1180-L1185) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 84 | [`xitdb/btree.odin#L1194-L1277`](../../xitdb/btree.odin#L1194-L1277) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 6` (from `sorted_put`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L85-L91`](../../xitdb/btree.odin#L85-L91) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 6` (from `sorted_put`, `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 6` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1473-L1479`](../../xitdb/btree.odin#L1473-L1479) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 6` (from `sorted_put`) | 6 | [`xitdb/btree.odin#L1173-L1178`](../../xitdb/btree.odin#L1173-L1178) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 6` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1187-L1192`](../../xitdb/btree.odin#L1187-L1192) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 6` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1481-L1534`](../../xitdb/btree.odin#L1481-L1534) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 6` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1165-L1171`](../../xitdb/btree.odin#L1165-L1171) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 6` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 6` (from `sorted_put`) | 40 | [`xitdb/btree.odin#L1078-L1117`](../../xitdb/btree.odin#L1078-L1117) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 6` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1281-L1297`](../../xitdb/btree.odin#L1281-L1297) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 6` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1300-L1313`](../../xitdb/btree.odin#L1300-L1313) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 7` (from `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/types.odin` | `decode_kv_pair_at` | `depth 7` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1215-L1249`](../../xitdb/types.odin#L1215-L1249) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 8` (from `decode_kv_pair_at`) | 10 | [`xitdb/types.odin#L1145-L1154`](../../xitdb/types.odin#L1145-L1154) |
