# #72. `DSL Layer 5: Datalog Grouped Aggs (N=500)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2303-L2318`)](../bench_xitdb.odin#L2303-L2318)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **571,238** | 577,630.2 ± 16,871.9 | 2.9% | 599,143.4 | 1,751 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2303-L2318`](../bench_xitdb.odin#L2303-L2318))

```odin
2303 | 		A :: 25
2304 | 		t1 := time.now()
2305 | 		for _ in 0 ..< A {
2306 | 			res, err := xitdb.query_datalog(&db, `
2307 | 				find ?dept, count(?id), min(?age), max(?age), sum(?age)
2308 | 				where
2309 | 					.users[?id].dept = ?dept
2310 | 					.users[?id].age = ?age
2311 | 			`, -1, context.temp_allocator)
2312 | 			assert(err == nil && len(res.rows) == 2)
2313 | 		}
2314 | 		print_result(Bench_Result{
2315 | 			name    = "DSL Layer 5: Datalog Grouped Aggs (N=500)",
2316 | 			ops     = A,
2317 | 			elapsed = time.since(t1),
2318 | 		})
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

### Reached Odin Procedures (`123` procedures across `8` files · `3402` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`, `Hash_Map_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `query_datalog` | **Entry Point** (`depth 0`) | 4 | [`xitdb/dsl.odin#L3017-L3020`](../../xitdb/dsl.odin#L3017-L3020) |
| `xitdb/dsl.odin` | `parse_datalog` | `depth 1` (from `query_datalog`) | 39 | [`xitdb/dsl.odin#L2461-L2499`](../../xitdb/dsl.odin#L2461-L2499) |
| `xitdb/dsl.odin` | `datalog_execute` | `depth 1` (from `query_datalog`) | 19 | [`xitdb/dsl.odin#L3022-L3040`](../../xitdb/dsl.odin#L3022-L3040) |
| `xitdb/dsl.odin` | `datalog_query_init` | `depth 2` (from `parse_datalog`) | 8 | [`xitdb/dsl.odin#L2435-L2442`](../../xitdb/dsl.odin#L2435-L2442) |
| `xitdb/dsl.odin` | `_parse_datalog_find_item` | `depth 2` (from `parse_datalog`) | 37 | [`xitdb/dsl.odin#L2601-L2637`](../../xitdb/dsl.odin#L2601-L2637) |
| `xitdb/dsl.odin` | `_split_datalog_where_clauses` | `depth 2` (from `parse_datalog`) | 58 | [`xitdb/dsl.odin#L2501-L2558`](../../xitdb/dsl.odin#L2501-L2558) |
| `xitdb/dsl.odin` | `_parse_datalog_clause` | `depth 2` (from `parse_datalog`) | 133 | [`xitdb/dsl.odin#L2639-L2771`](../../xitdb/dsl.odin#L2639-L2771) |
| `xitdb/dsl.odin` | `_eval_datalog_clauses` | `depth 2` (from `datalog_execute`, `_eval_reach_clause`, `_eval_pattern_steps`) | 54 | [`xitdb/dsl.odin#L3199-L3252`](../../xitdb/dsl.odin#L3199-L3252) |
| `xitdb/dsl.odin` | `_compute_datalog_aggregations` | `depth 2` (from `datalog_execute`) | 117 | [`xitdb/dsl.odin#L3081-L3197`](../../xitdb/dsl.odin#L3081-L3197) |
| `xitdb/dsl.odin` | `_intern_datalog_var` | `depth 3` (from `_parse_datalog_find_item`, `_parse_datalog_clause`, `_parse_datalog_predicate`) | 15 | [`xitdb/dsl.odin#L2444-L2458`](../../xitdb/dsl.odin#L2444-L2458) |
| `xitdb/dsl.odin` | `_looks_like_complete_clause` | `depth 3` (from `_split_datalog_where_clauses`) | 11 | [`xitdb/dsl.odin#L2560-L2570`](../../xitdb/dsl.odin#L2560-L2570) |
| `xitdb/dsl.odin` | `_looks_like_clause_start` | `depth 3` (from `_split_datalog_where_clauses`) | 28 | [`xitdb/dsl.odin#L2572-L2599`](../../xitdb/dsl.odin#L2572-L2599) |
| `xitdb/dsl.odin` | `_split_top_level_comma_args` | `depth 3` (from `_parse_datalog_clause`) | 26 | [`xitdb/dsl.odin#L2773-L2798`](../../xitdb/dsl.odin#L2773-L2798) |
| `xitdb/dsl.odin` | `_parse_datalog_value` | `depth 3` (from `_parse_datalog_clause`, `_parse_datalog_predicate`) | 25 | [`xitdb/dsl.odin#L2862-L2886`](../../xitdb/dsl.odin#L2862-L2886) |
| `xitdb/dsl.odin` | `_parse_datalog_predicate` | `depth 3` (from `_parse_datalog_clause`) | 40 | [`xitdb/dsl.odin#L2821-L2860`](../../xitdb/dsl.odin#L2821-L2860) |
| `xitdb/dsl.odin` | `_find_top_level_equals` | `depth 3` (from `_parse_datalog_clause`) | 20 | [`xitdb/dsl.odin#L2800-L2819`](../../xitdb/dsl.odin#L2800-L2819) |
| `xitdb/dsl.odin` | `_parse_datalog_steps` | `depth 3` (from `_parse_datalog_clause`) | 90 | [`xitdb/dsl.odin#L2888-L2977`](../../xitdb/dsl.odin#L2888-L2977) |
| `xitdb/dsl.odin` | `_eval_datalog_predicate` | `depth 3` (from `_eval_datalog_clauses`) | 61 | [`xitdb/dsl.odin#L3660-L3720`](../../xitdb/dsl.odin#L3660-L3720) |
| `xitdb/dsl.odin` | `_eval_pattern_moment` | `depth 3` (from `_eval_datalog_clauses`, `_eval_reach_clause`) | 79 | [`xitdb/dsl.odin#L3379-L3457`](../../xitdb/dsl.odin#L3379-L3457) |
| `xitdb/dsl.odin` | `_eval_reach_clause` | `depth 3` (from `_eval_datalog_clauses`) | 108 | [`xitdb/dsl.odin#L3260-L3367`](../../xitdb/dsl.odin#L3260-L3367) |
| `xitdb/dsl.odin` | `_pull_value_equals` | `depth 3` (from `_compute_datalog_aggregations`, `_eval_datalog_predicate`, `_eval_reach_clause`) | 19 | [`xitdb/dsl.odin#L3733-L3751`](../../xitdb/dsl.odin#L3733-L3751) |
| `xitdb/dsl.odin` | `_compare_pull_values` | `depth 3` (from `_compute_datalog_aggregations`, `_eval_datalog_predicate`) | 31 | [`xitdb/dsl.odin#L3753-L3783`](../../xitdb/dsl.odin#L3753-L3783) |
| `xitdb/dsl.odin` | `_parse_script_literal` | `depth 4` (from `_parse_datalog_value`) | 57 | [`xitdb/dsl.odin#L1231-L1287`](../../xitdb/dsl.odin#L1231-L1287) |
| `xitdb/dsl.odin` | `_parse_datalog_key_or_var` | `depth 4` (from `_parse_datalog_steps`) | 36 | [`xitdb/dsl.odin#L2979-L3014`](../../xitdb/dsl.odin#L2979-L3014) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 4` (from `_parse_datalog_steps`, `_parse_datalog_key_or_var`, `_parse_step_ident_or_bracket`) | 19 | [`xitdb/dsl.odin#L296-L314`](../../xitdb/dsl.odin#L296-L314) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 4` (from `_eval_pattern_moment`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 4` (from `_eval_pattern_moment`, `_eval_pattern_steps`, `_pull_cursor_value`) | 4 | [`xitdb/cursor.odin#L64-L67`](../../xitdb/cursor.odin#L64-L67) |
| `xitdb/dsl.odin` | `_eval_pattern_steps` | `depth 4` (from `_eval_pattern_moment`) | 176 | [`xitdb/dsl.odin#L3459-L3634`](../../xitdb/dsl.odin#L3459-L3634) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 4` (from `_eval_pattern_moment`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_count` | `depth 4` (from `_eval_pattern_moment`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 4` (from `_eval_pattern_moment`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `_pull_val_as_i64` | `depth 4` (from `_eval_pattern_moment`, `_pull_value_equals`, `_compare_pull_values`) | 10 | [`xitdb/dsl.odin#L3722-L3731`](../../xitdb/dsl.odin#L3722-L3731) |
| `xitdb/dsl.odin` | `_pull_slice_contains` | `depth 4` (from `_eval_reach_clause`) | 9 | [`xitdb/dsl.odin#L3369-L3377`](../../xitdb/dsl.odin#L3369-L3377) |
| `xitdb/types.odin` | `new_tagged_string` | `depth 5` (from `_parse_script_literal`) | 3 | [`xitdb/types.odin#L1370-L1372`](../../xitdb/types.odin#L1370-L1372) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 5` (from `_parse_datalog_key_or_var`) | 33 | [`xitdb/dsl.odin#L262-L294`](../../xitdb/dsl.odin#L262-L294) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 5` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 5` (from `cursor_slot`, `read_array_list_init`, `read_steps_cursor`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/dsl.odin` | `_pull_cursor_value` | `depth 5` (from `_eval_pattern_steps`) | 9 | [`xitdb/dsl.odin#L1734-L1742`](../../xitdb/dsl.odin#L1734-L1742) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 5` (from `_eval_pattern_steps`) | 91 | [`xitdb/dsl.odin#L317-L407`](../../xitdb/dsl.odin#L317-L407) |
| `xitdb/dsl.odin` | `_find_prefix_hint` | `depth 5` (from `_eval_pattern_steps`) | 11 | [`xitdb/dsl.odin#L3636-L3646`](../../xitdb/dsl.odin#L3636-L3646) |
| `xitdb/dsl.odin` | `_find_lower_bound_hint` | `depth 5` (from `_eval_pattern_steps`) | 11 | [`xitdb/dsl.odin#L3648-L3658`](../../xitdb/dsl.odin#L3648-L3658) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_key` | `depth 5` (from `_eval_pattern_steps`) | 92 | [`xitdb/cursor.odin#L842-L933`](../../xitdb/cursor.odin#L842-L933) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 43 | [`xitdb/cursor.odin#L713-L755`](../../xitdb/cursor.odin#L713-L755) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 22 | [`xitdb/cursor.odin#L1069-L1090`](../../xitdb/cursor.odin#L1069-L1090) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 5` (from `_eval_pattern_steps`, `_pull_wildcard`) | 19 | [`xitdb/cursor.odin#L366-L384`](../../xitdb/cursor.odin#L366-L384) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 5` (from `_eval_pattern_steps`, `_pull_scalar_slot`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L236-L239`](../../xitdb/cursor.odin#L236-L239) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 5` (from `array_list_count`) | 39 | [`xitdb/cursor.odin#L395-L433`](../../xitdb/cursor.odin#L395-L433) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 5` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 6` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `is_root` | `depth 6` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 6` (from `_pull_cursor_value`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L1686-L1694`](../../xitdb/dsl.odin#L1686-L1694) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 6` (from `_pull_cursor_value`) | 24 | [`xitdb/dsl.odin#L1709-L1732`](../../xitdb/dsl.odin#L1709-L1732) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 6` (from `_pull_cursor_value`) | 80 | [`xitdb/dsl.odin#L1860-L1939`](../../xitdb/dsl.odin#L1860-L1939) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 6` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L247-L255`](../../xitdb/collections.odin#L247-L255) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 6` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 6` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L133-L135`](../../xitdb/collections.odin#L133-L135) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L500-L508`](../../xitdb/collections.odin#L500-L508) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 6` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L562-L566`](../../xitdb/collections.odin#L562-L566) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L517-L525`](../../xitdb/collections.odin#L517-L525) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 6` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L803-L811`](../../xitdb/collections.odin#L803-L811) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 6` (from `cursor_iterator_sorted_from_key`, `cursor_iterator`) | 4 | [`xitdb/cursor.odin#L59-L62`](../../xitdb/cursor.odin#L59-L62) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 6` (from `cursor_iterator_sorted_from_key`) | 12 | [`xitdb/cursor.odin#L769-L780`](../../xitdb/cursor.odin#L769-L780) |
| `xitdb/core.odin` | `core_seek_to` | `depth 6` (from `cursor_iterator_sorted_from_key`, `cursor_iterator`, `cursor_read_kv_pair`) | 17 | [`xitdb/core.odin#L175-L191`](../../xitdb/core.odin#L175-L191) |
| `xitdb/core.odin` | `core_read_exact` | `depth 6` (from `cursor_iterator_sorted_from_key`, `cursor_iterator`, `cursor_count`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `cursor_iterator_sorted_from_key`, `sorted_entry_key_slot`, `read_btree_slot`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `cursor_iterator_sorted_from_key`, `sorted_get`, `sorted_target_slot`) | 13 | [`xitdb/btree.odin#L1136-L1148`](../../xitdb/btree.odin#L1136-L1148) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `cursor_iterator_sorted_from_key`, `sorted_get`) | 60 | [`xitdb/btree.odin#L1157-L1216`](../../xitdb/btree.odin#L1157-L1216) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 6` (from `cursor_iterator`, `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 6` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L692-L695`](../../xitdb/cursor.odin#L692-L695) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 6` (from `cursor_iterator`, `cursor_count`, `_sorted_header`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 6` (from `cursor_iterator`, `_iterator_next_internal`) | 15 | [`xitdb/cursor.odin#L697-L711`](../../xitdb/cursor.odin#L697-L711) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 6` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1034-L1067`](../../xitdb/cursor.odin#L1034-L1067) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 6` (from `cursor_read_kv_pair`, `sorted_entry_key_slot`, `database_kv_key_position`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `cursor_read_kv_pair`) | 35 | [`xitdb/types.odin#L1155-L1189`](../../xitdb/types.odin#L1155-L1189) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 6` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L536-L541`](../../xitdb/database.odin#L536-L541) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 6` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L543-L548`](../../xitdb/database.odin#L543-L548) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 6` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L228-L234`](../../xitdb/cursor.odin#L228-L234) |
| `xitdb/core.odin` | `core_read_long` | `depth 6` (from `cursor_count`, `cursor_read_bytes_object`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L473-L479`](../../xitdb/core.odin#L473-L479) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 6` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 7` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 7` (from `database_read_root_header`, `slot_from_slice`, `decode_kv_pair`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 10 | [`xitdb/cursor.odin#L201-L210`](../../xitdb/cursor.odin#L201-L210) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L212-L218`](../../xitdb/cursor.odin#L212-L218) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L220-L226`](../../xitdb/cursor.odin#L220-L226) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 7` (from `_pull_scalar_slot`, `_pull_wildcard`, `cursor_read_bytes`) | 56 | [`xitdb/cursor.odin#L241-L296`](../../xitdb/cursor.odin#L241-L296) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 7` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 7` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 7` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 7` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L554-L556`](../../xitdb/collections.odin#L554-L556) |
| `xitdb/core.odin` | `core_read` | `depth 7` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L281-L323`](../../xitdb/core.odin#L281-L323) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 7` (from `slot_from_slice`, `kv_pair_from_bytes`, `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/core.odin` | `core_slice_at` | `depth 7` (from `sorted_entry_key_slot`, `read_btree_slot`, `sorted_get`) | 17 | [`xitdb/core.odin#L420-L436`](../../xitdb/core.odin#L420-L436) |
| `xitdb/core.odin` | `core_read_slot` | `depth 7` (from `sorted_entry_key_slot`, `read_array_list_slot`, `read_btree_slot`) | 5 | [`xitdb/core.odin#L556-L560`](../../xitdb/core.odin#L556-L560) |
| `xitdb/core.odin` | `core_read_i64` | `depth 7` (from `compare_key`, `core_read_long`) | 24 | [`xitdb/core.odin#L488-L511`](../../xitdb/core.odin#L488-L511) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 7` (from `_init_iter_level`, `_init_btree_iter_level`) | 21 | [`xitdb/cursor.odin#L670-L690`](../../xitdb/cursor.odin#L670-L690) |
| `xitdb/types.odin` | `slot_empty` | `depth 7` (from `_iterator_next_internal`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `decode_kv_pair`, `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1136-L1145`](../../xitdb/types.odin#L1136-L1145) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 7` (from `database_kv_key_position`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 7` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L531-L554`](../../xitdb/core.odin#L531-L554) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 7` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/types.odin` | `radix_shift` | `depth 8` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 8` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 8` (from `_exec_path_part`) | 87 | [`xitdb/btree.odin#L103-L189`](../../xitdb/btree.odin#L103-L189) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 8` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/btree.odin` | `sorted_get` | `depth 8` (from `_exec_path_part`) | 115 | [`xitdb/btree.odin#L1254-L1368`](../../xitdb/btree.odin#L1254-L1368) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 8` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2205-L2222`](../../xitdb/btree.odin#L2205-L2222) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 8` (from `root_header_from_bytes`, `_fill_slot_block_from`, `core_read_slot_raw`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 8` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 8` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 8` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_length` | `depth 9` (from `read_array_list_slot`, `read_map_slot`) | 21 | [`xitdb/core.odin#L153-L173`](../../xitdb/core.odin#L153-L173) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 9` (from `read_array_list_slot`, `read_map_slot`, `encode_kv_pair`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/database.odin` | `database_check_hash` | `depth 9` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 9` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 9` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 9` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/database.odin` | `database_is_old` | `depth 9` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 10` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
