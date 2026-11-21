# #71. `DSL Layer 5: Datalog B+Tree Prefix + Join` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2639-L2662`)](../bench_xitdb.odin#L2639-L2662)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **25,767** | 25,818.6 ± 142.9 | 0.6% | 25,997.6 | 38,809 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2639-L2662`](../bench_xitdb.odin#L2639-L2662))

```odin
2639 | 	// 5. Layer 5: Datalog B+Tree Prefix Pushdown, Grouped Aggregations & Cycle-Safe `reach`
2640 | 	{
2641 | 		Q :: 100
2642 | 		sp0 := span_begin()
2643 | 		for _ in 0 ..< Q {
2644 | 			// Prefix "user_025" matches 10 users ("user_0250".."user_0259") via B+Tree seek
2645 | 			res, err := xitdb.query_datalog(&db, `
2646 | 				find ?id, ?name, ?age
2647 | 				where
2648 | 					$username->id[?name] = ?id
2649 | 					starts_with(?name, "user_025")
2650 | 					.users[?id].age = ?age
2651 | 					not .users[?id].roles%"suspended"
2652 | 			`, -1, context.temp_allocator)
2653 | 			assert(err == nil && len(res.rows) == 9)
2654 | 		}
2655 | 		el0, hw0, has_hw0 := span_end(sp0)
2656 | 		print_result(Bench_Result{
2657 | 			name         = "DSL Layer 5: Datalog B+Tree Prefix + Join",
2658 | 			ops          = Q,
2659 | 			elapsed      = el0,
2660 | 			counters     = hw0,
2661 | 			has_counters = has_hw0,
2662 | 		})
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

### Reached Odin Procedures (`158` procedures across `8` files · `4330` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`, `Hash_Map_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `query_datalog` | **Entry Point** (`depth 0`) | 5 | [`xitdb/dsl.odin#L3773-L3777`](../../xitdb/dsl.odin#L3773-L3777) |
| `xitdb/dsl.odin` | `parse_datalog` | `depth 1` (from `query_datalog`) | 48 | [`xitdb/dsl.odin#L3195-L3242`](../../xitdb/dsl.odin#L3195-L3242) |
| `xitdb/dsl.odin` | `datalog_query_destroy` | `depth 1` (from `query_datalog`, `parse_datalog`) | 12 | [`xitdb/dsl.odin#L3136-L3147`](../../xitdb/dsl.odin#L3136-L3147) |
| `xitdb/dsl.odin` | `datalog_execute` | `depth 1` (from `query_datalog`) | 32 | [`xitdb/dsl.odin#L3779-L3810`](../../xitdb/dsl.odin#L3779-L3810) |
| `xitdb/dsl.odin` | `_is_ascii_space` | `depth 2` (from `parse_datalog`, `_find_datalog_where_keyword`) | 4 | [`xitdb/dsl.odin#L3149-L3152`](../../xitdb/dsl.odin#L3149-L3152) |
| `xitdb/dsl.odin` | `_find_datalog_where_keyword` | `depth 2` (from `parse_datalog`) | 23 | [`xitdb/dsl.odin#L3154-L3176`](../../xitdb/dsl.odin#L3154-L3176) |
| `xitdb/dsl.odin` | `datalog_query_init` | `depth 2` (from `parse_datalog`) | 8 | [`xitdb/dsl.odin#L3100-L3107`](../../xitdb/dsl.odin#L3100-L3107) |
| `xitdb/dsl.odin` | `_parse_datalog_find_item` | `depth 2` (from `parse_datalog`) | 37 | [`xitdb/dsl.odin#L3345-L3381`](../../xitdb/dsl.odin#L3345-L3381) |
| `xitdb/dsl.odin` | `_split_datalog_where_clauses` | `depth 2` (from `parse_datalog`) | 59 | [`xitdb/dsl.odin#L3244-L3302`](../../xitdb/dsl.odin#L3244-L3302) |
| `xitdb/dsl.odin` | `_parse_datalog_clause` | `depth 2` (from `parse_datalog`) | 142 | [`xitdb/dsl.odin#L3383-L3524`](../../xitdb/dsl.odin#L3383-L3524) |
| `xitdb/dsl.odin` | `_destroy_datalog_clause` | `depth 2` (from `datalog_query_destroy`) | 13 | [`xitdb/dsl.odin#L3121-L3133`](../../xitdb/dsl.odin#L3121-L3133) |
| `xitdb/dsl.odin` | `_iter_pool_init` | `depth 2` (from `datalog_execute`) | 7 | [`xitdb/dsl.odin#L1853-L1859`](../../xitdb/dsl.odin#L1853-L1859) |
| `xitdb/dsl.odin` | `_iter_pool_destroy` | `depth 2` (from `datalog_execute`) | 7 | [`xitdb/dsl.odin#L1861-L1867`](../../xitdb/dsl.odin#L1861-L1867) |
| `xitdb/dsl.odin` | `_eval_datalog_clauses` | `depth 2` (from `datalog_execute`, `_eval_reach_clause`, `_eval_pattern_steps`) | 55 | [`xitdb/dsl.odin#L3970-L4024`](../../xitdb/dsl.odin#L3970-L4024) |
| `xitdb/dsl.odin` | `_compute_datalog_aggregations` | `depth 2` (from `datalog_execute`) | 118 | [`xitdb/dsl.odin#L3851-L3968`](../../xitdb/dsl.odin#L3851-L3968) |
| `xitdb/dsl.odin` | `_intern_datalog_var` | `depth 3` (from `_parse_datalog_find_item`, `_parse_datalog_clause`, `_parse_datalog_predicate`) | 15 | [`xitdb/dsl.odin#L3178-L3192`](../../xitdb/dsl.odin#L3178-L3192) |
| `xitdb/dsl.odin` | `_looks_like_complete_clause` | `depth 3` (from `_split_datalog_where_clauses`) | 11 | [`xitdb/dsl.odin#L3304-L3314`](../../xitdb/dsl.odin#L3304-L3314) |
| `xitdb/dsl.odin` | `_looks_like_clause_start` | `depth 3` (from `_split_datalog_where_clauses`) | 28 | [`xitdb/dsl.odin#L3316-L3343`](../../xitdb/dsl.odin#L3316-L3343) |
| `xitdb/dsl.odin` | `_split_top_level_comma_args` | `depth 3` (from `_parse_datalog_clause`) | 26 | [`xitdb/dsl.odin#L3526-L3551`](../../xitdb/dsl.odin#L3526-L3551) |
| `xitdb/dsl.odin` | `_parse_datalog_value` | `depth 3` (from `_parse_datalog_clause`, `_parse_datalog_predicate`) | 25 | [`xitdb/dsl.odin#L3615-L3639`](../../xitdb/dsl.odin#L3615-L3639) |
| `xitdb/dsl.odin` | `_parse_datalog_predicate` | `depth 3` (from `_parse_datalog_clause`) | 40 | [`xitdb/dsl.odin#L3574-L3613`](../../xitdb/dsl.odin#L3574-L3613) |
| `xitdb/dsl.odin` | `_find_top_level_equals` | `depth 3` (from `_parse_datalog_clause`) | 20 | [`xitdb/dsl.odin#L3553-L3572`](../../xitdb/dsl.odin#L3553-L3572) |
| `xitdb/dsl.odin` | `_parse_datalog_steps` | `depth 3` (from `_parse_datalog_clause`) | 93 | [`xitdb/dsl.odin#L3641-L3733`](../../xitdb/dsl.odin#L3641-L3733) |
| `xitdb/dsl.odin` | `_destroy_datalog_steps` | `depth 3` (from `_destroy_datalog_clause`, `_parse_datalog_steps`) | 11 | [`xitdb/dsl.odin#L3109-L3119`](../../xitdb/dsl.odin#L3109-L3119) |
| `xitdb/dsl.odin` | `_eval_datalog_predicate` | `depth 3` (from `_eval_datalog_clauses`) | 61 | [`xitdb/dsl.odin#L4467-L4527`](../../xitdb/dsl.odin#L4467-L4527) |
| `xitdb/dsl.odin` | `_eval_pattern_moment` | `depth 3` (from `_eval_datalog_clauses`, `_eval_reach_clause`) | 80 | [`xitdb/dsl.odin#L4169-L4248`](../../xitdb/dsl.odin#L4169-L4248) |
| `xitdb/dsl.odin` | `_eval_reach_clause` | `depth 3` (from `_eval_datalog_clauses`) | 126 | [`xitdb/dsl.odin#L4032-L4157`](../../xitdb/dsl.odin#L4032-L4157) |
| `xitdb/dsl.odin` | `_pull_value_equals` | `depth 3` (from `_compute_datalog_aggregations`, `_eval_datalog_predicate`, `_eval_reach_clause`) | 19 | [`xitdb/dsl.odin#L4540-L4558`](../../xitdb/dsl.odin#L4540-L4558) |
| `xitdb/dsl.odin` | `_compare_pull_values` | `depth 3` (from `_compute_datalog_aggregations`, `_eval_datalog_predicate`) | 31 | [`xitdb/dsl.odin#L4560-L4590`](../../xitdb/dsl.odin#L4560-L4590) |
| `xitdb/dsl.odin` | `_parse_script_literal` | `depth 4` (from `_parse_datalog_value`) | 57 | [`xitdb/dsl.odin#L1537-L1593`](../../xitdb/dsl.odin#L1537-L1593) |
| `xitdb/dsl.odin` | `_parse_datalog_key_or_var` | `depth 4` (from `_parse_datalog_steps`) | 36 | [`xitdb/dsl.odin#L3735-L3770`](../../xitdb/dsl.odin#L3735-L3770) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 4` (from `_parse_datalog_steps`, `_parse_datalog_key_or_var`, `_parse_step_ident_or_bracket`) | 28 | [`xitdb/dsl.odin#L437-L464`](../../xitdb/dsl.odin#L437-L464) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 4` (from `_eval_pattern_moment`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 4` (from `_eval_pattern_moment`, `_eval_pattern_steps`, `_pull_cursor_value`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/dsl.odin` | `_eval_pattern_steps` | `depth 4` (from `_eval_pattern_moment`) | 192 | [`xitdb/dsl.odin#L4250-L4441`](../../xitdb/dsl.odin#L4250-L4441) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 4` (from `_eval_pattern_moment`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_count` | `depth 4` (from `_eval_pattern_moment`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 4` (from `_eval_pattern_moment`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `_pull_val_as_i64` | `depth 4` (from `_eval_pattern_moment`, `_pull_value_equals`, `_compare_pull_values`) | 10 | [`xitdb/dsl.odin#L4529-L4538`](../../xitdb/dsl.odin#L4529-L4538) |
| `xitdb/dsl.odin` | `_pull_slice_contains` | `depth 4` (from `_eval_reach_clause`) | 9 | [`xitdb/dsl.odin#L4159-L4167`](../../xitdb/dsl.odin#L4159-L4167) |
| `xitdb/types.odin` | `new_tagged_string` | `depth 5` (from `_parse_script_literal`) | 3 | [`xitdb/types.odin#L1432-L1434`](../../xitdb/types.odin#L1432-L1434) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 5` (from `_parse_datalog_key_or_var`) | 42 | [`xitdb/dsl.odin#L394-L435`](../../xitdb/dsl.odin#L394-L435) |
| `xitdb/dsl.odin` | `_unescape_quoted_key` | `depth 5` (from `_parse_bracketed_string`, `_parse_step_ident_or_bracket`) | 26 | [`xitdb/dsl.odin#L367-L392`](../../xitdb/dsl.odin#L367-L392) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 5` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 5` (from `cursor_slot`, `read_array_list_init`, `read_steps_cursor`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/dsl.odin` | `_pull_cursor_value` | `depth 5` (from `_eval_pattern_steps`) | 9 | [`xitdb/dsl.odin#L2143-L2151`](../../xitdb/dsl.odin#L2143-L2151) |
| `xitdb/dsl.odin` | `pull_value_destroy` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 33 | [`xitdb/dsl.odin#L2154-L2186`](../../xitdb/dsl.odin#L2154-L2186) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 5` (from `_eval_pattern_steps`) | 91 | [`xitdb/dsl.odin#L467-L557`](../../xitdb/dsl.odin#L467-L557) |
| `xitdb/dsl.odin` | `_find_prefix_hint` | `depth 5` (from `_eval_pattern_steps`) | 11 | [`xitdb/dsl.odin#L4443-L4453`](../../xitdb/dsl.odin#L4443-L4453) |
| `xitdb/dsl.odin` | `_find_lower_bound_hint` | `depth 5` (from `_eval_pattern_steps`) | 11 | [`xitdb/dsl.odin#L4455-L4465`](../../xitdb/dsl.odin#L4455-L4465) |
| `xitdb/dsl.odin` | `_iter_pool_acquire` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 7 | [`xitdb/dsl.odin#L1878-L1884`](../../xitdb/dsl.odin#L1878-L1884) |
| `xitdb/dsl.odin` | `_iter_pool_release` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L1886-L1894`](../../xitdb/dsl.odin#L1886-L1894) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_key_init` | `depth 5` (from `_eval_pattern_steps`) | 82 | [`xitdb/cursor.odin#L1322-L1403`](../../xitdb/cursor.odin#L1322-L1403) |
| `xitdb/cursor.odin` | `cursor_iterator_init` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 43 | [`xitdb/cursor.odin#L1032-L1074`](../../xitdb/cursor.odin#L1032-L1074) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 40 | [`xitdb/cursor.odin#L1791-L1830`](../../xitdb/cursor.odin#L1791-L1830) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair_slots` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 28 | [`xitdb/cursor.odin#L404-L431`](../../xitdb/cursor.odin#L404-L431) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 5` (from `_eval_pattern_steps`, `_pull_scalar_slot`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L233-L236`](../../xitdb/cursor.odin#L233-L236) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 5` (from `array_list_count`) | 37 | [`xitdb/cursor.odin#L442-L478`](../../xitdb/cursor.odin#L442-L478) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 5` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 6` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `is_root` | `depth 6` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 6` (from `_pull_cursor_value`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L2093-L2101`](../../xitdb/dsl.odin#L2093-L2101) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 6` (from `_pull_cursor_value`) | 24 | [`xitdb/dsl.odin#L2118-L2141`](../../xitdb/dsl.odin#L2118-L2141) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 6` (from `_pull_cursor_value`) | 126 | [`xitdb/dsl.odin#L2347-L2472`](../../xitdb/dsl.odin#L2347-L2472) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 6` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L263-L271`](../../xitdb/collections.odin#L263-L271) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L693-L701`](../../xitdb/collections.odin#L693-L701) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 6` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 6` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L141-L143`](../../xitdb/collections.odin#L141-L143) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L520-L528`](../../xitdb/collections.odin#L520-L528) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 6` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L586-L590`](../../xitdb/collections.odin#L586-L590) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L537-L545`](../../xitdb/collections.odin#L537-L545) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L842-L850`](../../xitdb/collections.odin#L842-L850) |
| `xitdb/dsl.odin` | `_alloc_cursor_iterator` | `depth 6` (from `_iter_pool_acquire`) | 8 | [`xitdb/dsl.odin#L1869-L1876`](../../xitdb/dsl.odin#L1869-L1876) |
| `xitdb/cursor.odin` | `_reset_cursor_iterator` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `cursor_iterator_init`) | 8 | [`xitdb/cursor.odin#L1023-L1030`](../../xitdb/cursor.odin#L1023-L1030) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `cursor_iterator_init`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 6` (from `cursor_iterator_sorted_from_key_init`) | 11 | [`xitdb/cursor.odin#L1142-L1152`](../../xitdb/cursor.odin#L1142-L1152) |
| `xitdb/types.odin` | `_checked_add_i64` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `cursor_read_kv_pair_slots`, `read_sorted_node`) | 7 | [`xitdb/types.odin#L1498-L1504`](../../xitdb/types.odin#L1498-L1504) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `_read_btree_iter_level`, `descend_by_rank`) | 83 | [`xitdb/btree.odin#L1262-L1344`](../../xitdb/btree.odin#L1262-L1344) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `sorted_get`) | 17 | [`xitdb/btree.odin#L1508-L1524`](../../xitdb/btree.odin#L1508-L1524) |
| `xitdb/cursor.odin` | `_assign_btree_heights` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `_init_btree_stack`) | 6 | [`xitdb/cursor.odin#L845-L850`](../../xitdb/cursor.odin#L845-L850) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `_read_btree_iter_level`, `descend_by_rank`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 6` (from `cursor_iterator_sorted_from_key_init`, `sorted_get`) | 14 | [`xitdb/btree.odin#L1527-L1540`](../../xitdb/btree.odin#L1527-L1540) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 6` (from `cursor_iterator_init`, `cursor_read_kv_pair_slots`, `cursor_count`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 6` (from `cursor_iterator_init`, `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/cursor.odin` | `_init_array_list_stack` | `depth 6` (from `cursor_iterator_init`) | 38 | [`xitdb/cursor.odin#L941-L978`](../../xitdb/cursor.odin#L941-L978) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 6` (from `cursor_iterator_init`, `cursor_count`, `_sorted_header`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/cursor.odin` | `_init_btree_stack` | `depth 6` (from `cursor_iterator_init`) | 32 | [`xitdb/cursor.odin#L908-L939`](../../xitdb/cursor.odin#L908-L939) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 6` (from `cursor_iterator_init`, `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L835-L838`](../../xitdb/cursor.odin#L835-L838) |
| `xitdb/cursor.odin` | `_init_counted_hash_iter` | `depth 6` (from `cursor_iterator_init`) | 42 | [`xitdb/cursor.odin#L980-L1021`](../../xitdb/cursor.odin#L980-L1021) |
| `xitdb/cursor.odin` | `_iterator_step_internal` | `depth 6` (from `cursor_iterator_next`) | 93 | [`xitdb/cursor.odin#L1697-L1789`](../../xitdb/cursor.odin#L1697-L1789) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 6` (from `cursor_read_kv_pair_slots`, `sorted_entry_key_slot`, `sorted_target_slot`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 6` (from `cursor_read_kv_pair_slots`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 6` (from `cursor_read_kv_pair_slots`, `slot_from_slice`, `core_read_slot_raw_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 6` (from `cursor_read_kv_pair_slots`, `database_read_root_trailer`, `slot_from_slice`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 6` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L225-L231`](../../xitdb/cursor.odin#L225-L231) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 6` (from `cursor_count`, `cursor_read_bytes_object`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/types.odin` | `check_long` | `depth 6` (from `cursor_count`) | 6 | [`xitdb/types.odin#L1491-L1496`](../../xitdb/types.odin#L1491-L1496) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 6` (from `cursor_read_path`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L603-L669`](../../xitdb/database.odin#L603-L669) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 7` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 7` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 7` (from `database_read_root_header`, `cursor_read_bytes_object`, `compare_key`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 7` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 10 | [`xitdb/cursor.odin#L198-L207`](../../xitdb/cursor.odin#L198-L207) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L209-L215`](../../xitdb/cursor.odin#L209-L215) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L217-L223`](../../xitdb/cursor.odin#L217-L223) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`, `cursor_read_bytes`) | 66 | [`xitdb/cursor.odin#L238-L303`](../../xitdb/cursor.odin#L238-L303) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 7` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 7` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 7` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 7` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L578-L580`](../../xitdb/collections.odin#L578-L580) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 7` (from `read_sorted_node`, `read_btree_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 7` (from `read_sorted_node`, `_fill_slot_block_rev`, `_fill_slot_block_from`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/types.odin` | `is_sorted_entry_tag` | `depth 7` (from `read_sorted_node`) | 8 | [`xitdb/types.odin#L1392-L1399`](../../xitdb/types.odin#L1392-L1399) |
| `xitdb/types.odin` | `slot_empty` | `depth 7` (from `read_sorted_node`, `_init_array_list_stack`, `_iterator_step_internal`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 7` (from `sorted_leaf_search`, `sorted_target_slot`) | 6 | [`xitdb/btree.odin#L1407-L1412`](../../xitdb/btree.odin#L1407-L1412) |
| `xitdb/btree.odin` | `compare_key` | `depth 7` (from `sorted_leaf_search`, `sorted_branch_search`) | 84 | [`xitdb/btree.odin#L1421-L1504`](../../xitdb/btree.odin#L1421-L1504) |
| `xitdb/core.odin` | `core_read_at` | `depth 7` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/types.odin` | `radix_shift` | `depth 7` (from `_init_array_list_stack`, `_exec_path_part`) | 6 | [`xitdb/types.odin#L1484-L1489`](../../xitdb/types.odin#L1484-L1489) |
| `xitdb/cursor.odin` | `_fill_slot_block_rev` | `depth 7` (from `_init_array_list_stack`, `_init_iter_level_rev`) | 38 | [`xitdb/cursor.odin#L796-L833`](../../xitdb/cursor.odin#L796-L833) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 7` (from `_init_array_list_stack`, `_init_iter_level`) | 41 | [`xitdb/cursor.odin#L754-L794`](../../xitdb/cursor.odin#L754-L794) |
| `xitdb/cursor.odin` | `_read_btree_iter_level` | `depth 7` (from `_init_btree_stack`, `_iterator_step_internal`) | 55 | [`xitdb/cursor.odin#L852-L906`](../../xitdb/cursor.odin#L852-L906) |
| `xitdb/core.odin` | `core_slice_at` | `depth 7` (from `_init_counted_hash_iter`, `_fill_slot_block_rev`, `_fill_slot_block_from`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/cursor.odin` | `_decode_slot_block_raw` | `depth 7` (from `_init_counted_hash_iter`) | 7 | [`xitdb/cursor.odin#L746-L752`](../../xitdb/cursor.odin#L746-L752) |
| `xitdb/cursor.odin` | `_init_iter_level_rev` | `depth 7` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L840-L843`](../../xitdb/cursor.odin#L840-L843) |
| `xitdb/core.odin` | `core_seek_to` | `depth 7` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 7` (from `read_slot_pointer`, `read_map_slot`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 7` (from `read_slot_pointer`) | 788 | [`xitdb/database.odin#L671-L1458`](../../xitdb/database.odin#L671-L1458) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 8` (from `_exec_path_part`) | 70 | [`xitdb/hamt.odin#L382-L451`](../../xitdb/hamt.odin#L382-L451) |
| `xitdb/btree.odin` | `descend_by_rank` | `depth 8` (from `_exec_path_part`) | 76 | [`xitdb/btree.odin#L135-L210`](../../xitdb/btree.odin#L135-L210) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 8` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/btree.odin` | `sorted_get` | `depth 8` (from `_exec_path_part`) | 31 | [`xitdb/btree.odin#L1542-L1572`](../../xitdb/btree.odin#L1542-L1572) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 8` (from `_exec_path_part`) | 21 | [`xitdb/btree.odin#L2343-L2363`](../../xitdb/btree.odin#L2343-L2363) |
| `xitdb/core.odin` | `_overlay_length` | `depth 8` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 8` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 8` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 8` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 8` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 8` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 8` (from `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 8` (from `sorted_entry_key_slot`, `read_array_list_slot`, `sorted_target_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 8` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 8` (from `_read_btree_iter_level`, `descend_by_rank`) | 66 | [`xitdb/btree.odin#L8-L73`](../../xitdb/btree.odin#L8-L73) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 8` (from `_read_btree_iter_level`, `descend_by_rank`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 8` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 8` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 9` (from `read_array_list_slot`, `compute_root_trailer_checksum`, `read_map_slot`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 9` (from `sorted_target_slot`) | 10 | [`xitdb/database.odin#L591-L600`](../../xitdb/database.odin#L591-L600) |
| `xitdb/database.odin` | `database_check_hash` | `depth 9` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 9` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1476-L1481`](../../xitdb/types.odin#L1476-L1481) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 9` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 9` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `database_is_old` | `depth 9` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 10` (from `database_kv_value_position`) | 10 | [`xitdb/database.odin#L580-L589`](../../xitdb/database.odin#L580-L589) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 10` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 10` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
