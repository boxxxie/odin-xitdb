# #68. `DSL Layer 3: Datomic pull projection (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2583-L2596`)](../bench_xitdb.odin#L2583-L2596)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **2,950** | 3,062.4 ± 262.7 | 8.6% | 3,423.0 | 338,983 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2583-L2596`](../bench_xitdb.odin#L2583-L2596))

```odin
2583 | 		sp2 := span_begin()
2584 | 		for i in 0 ..< M {
2585 | 			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
2586 | 			pv, p_err := xitdb.pull(pcur_maybe.?, "{username, age, todos[0..2]}", context.temp_allocator)
2587 | 			assert(p_err == nil && pv != nil)
2588 | 		}
2589 | 		el2, hw2, has_hw2 := span_end(sp2)
2590 | 		print_result(Bench_Result{
2591 | 			name         = "DSL Layer 3: Datomic pull projection (N=200)",
2592 | 			ops          = M,
2593 | 			elapsed      = el2,
2594 | 			counters     = hw2,
2595 | 			has_counters = has_hw2,
2596 | 		})
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

### Reached Odin Procedures (`133` procedures across `8` files · `3325` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`, `Hash_Map_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 17 | [`xitdb/dsl.odin#L685-L701`](../../xitdb/dsl.odin#L685-L701) |
| `xitdb/dsl.odin` | `pull` | **Entry Point** (`depth 0`) | 13 | [`xitdb/dsl.odin#L2104-L2116`](../../xitdb/dsl.odin#L2104-L2116) |
| `xitdb/dsl.odin` | `parse_selector_buf` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L199-L229`](../../xitdb/dsl.odin#L199-L229) |
| `xitdb/dsl.odin` | `selector_destroy_buf` | `depth 1` (from `select_cursor`) | 4 | [`xitdb/dsl.odin#L69-L72`](../../xitdb/dsl.odin#L69-L72) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `select_cursor`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`, `_eval_pull_spec`) | 91 | [`xitdb/dsl.odin#L467-L557`](../../xitdb/dsl.odin#L467-L557) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `pull`, `_pull_wildcard`, `_pull_range`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 1` (from `pull`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L2093-L2101`](../../xitdb/dsl.odin#L2093-L2101) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 1` (from `pull`) | 24 | [`xitdb/dsl.odin#L2118-L2141`](../../xitdb/dsl.odin#L2118-L2141) |
| `xitdb/dsl.odin` | `_iter_pool_init` | `depth 1` (from `pull`) | 7 | [`xitdb/dsl.odin#L1853-L1859`](../../xitdb/dsl.odin#L1853-L1859) |
| `xitdb/dsl.odin` | `_iter_pool_destroy` | `depth 1` (from `pull`) | 7 | [`xitdb/dsl.odin#L1861-L1867`](../../xitdb/dsl.odin#L1861-L1867) |
| `xitdb/dsl.odin` | `_pull_with_visited` | `depth 1` (from `pull`, `_eval_pull_spec`, `_pull_range`) | 36 | [`xitdb/dsl.odin#L2188-L2223`](../../xitdb/dsl.odin#L2188-L2223) |
| `xitdb/dsl.odin` | `parse_steps_buf` | `depth 2` (from `parse_selector_buf`, `_eval_pull_spec`) | 127 | [`xitdb/dsl.odin#L239-L365`](../../xitdb/dsl.odin#L239-L365) |
| `xitdb/dsl.odin` | `steps_destroy_buf` | `depth 2` (from `selector_destroy_buf`, `parse_steps_buf`, `_eval_pull_spec`) | 10 | [`xitdb/dsl.odin#L57-L66`](../../xitdb/dsl.odin#L57-L66) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`, `read_steps_cursor`, `cursor_slot`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L263-L271`](../../xitdb/collections.odin#L263-L271) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L693-L701`](../../xitdb/collections.odin#L693-L701) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L141-L143`](../../xitdb/collections.odin#L141-L143) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L520-L528`](../../xitdb/collections.odin#L520-L528) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L586-L590`](../../xitdb/collections.odin#L586-L590) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L537-L545`](../../xitdb/collections.odin#L537-L545) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L842-L850`](../../xitdb/collections.odin#L842-L850) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 10 | [`xitdb/cursor.odin#L198-L207`](../../xitdb/cursor.odin#L198-L207) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L209-L215`](../../xitdb/cursor.odin#L209-L215) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L217-L223`](../../xitdb/cursor.odin#L217-L223) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`, `cursor_read_bytes`) | 66 | [`xitdb/cursor.odin#L238-L303`](../../xitdb/cursor.odin#L238-L303) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L233-L236`](../../xitdb/cursor.odin#L233-L236) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 2` (from `_pull_with_visited`) | 126 | [`xitdb/dsl.odin#L2347-L2472`](../../xitdb/dsl.odin#L2347-L2472) |
| `xitdb/dsl.odin` | `_split_top_level_pull_specs` | `depth 2` (from `_pull_with_visited`) | 34 | [`xitdb/dsl.odin#L2474-L2507`](../../xitdb/dsl.odin#L2474-L2507) |
| `xitdb/dsl.odin` | `pull_value_destroy` | `depth 2` (from `_pull_with_visited`, `_pull_wildcard`, `_eval_pull_spec`) | 33 | [`xitdb/dsl.odin#L2154-L2186`](../../xitdb/dsl.odin#L2154-L2186) |
| `xitdb/dsl.odin` | `_eval_pull_spec` | `depth 2` (from `_pull_with_visited`) | 63 | [`xitdb/dsl.odin#L2239-L2301`](../../xitdb/dsl.odin#L2239-L2301) |
| `xitdb/dsl.odin` | `steps_destroy` | `depth 3` (from `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L39-L48`](../../xitdb/dsl.odin#L39-L48) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 3` (from `parse_steps_buf`) | 42 | [`xitdb/dsl.odin#L394-L435`](../../xitdb/dsl.odin#L394-L435) |
| `xitdb/dsl.odin` | `_push_step_buf` | `depth 3` (from `parse_steps_buf`) | 23 | [`xitdb/dsl.odin#L174-L196`](../../xitdb/dsl.odin#L174-L196) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 3` (from `parse_steps_buf`, `_parse_step_ident_or_bracket`) | 28 | [`xitdb/dsl.odin#L437-L464`](../../xitdb/dsl.odin#L437-L464) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_read_path`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L603-L669`](../../xitdb/database.odin#L603-L669) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 3` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 3` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L578-L580`](../../xitdb/collections.odin#L578-L580) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 3` (from `cursor_read_bytes_object`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_length` | `depth 3` (from `cursor_read_bytes_object`, `database_read_root_header`, `read_array_list_slot`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `cursor_read_bytes_object`, `_exec_path_part`, `cursor_iterator_init`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L225-L231`](../../xitdb/cursor.odin#L225-L231) |
| `xitdb/dsl.odin` | `_iter_pool_acquire` | `depth 3` (from `_pull_wildcard`, `_pull_range`) | 7 | [`xitdb/dsl.odin#L1878-L1884`](../../xitdb/dsl.odin#L1878-L1884) |
| `xitdb/dsl.odin` | `_iter_pool_release` | `depth 3` (from `_pull_wildcard`, `_pull_range`) | 9 | [`xitdb/dsl.odin#L1886-L1894`](../../xitdb/dsl.odin#L1886-L1894) |
| `xitdb/cursor.odin` | `cursor_iterator_init` | `depth 3` (from `_pull_wildcard`) | 43 | [`xitdb/cursor.odin#L1032-L1074`](../../xitdb/cursor.odin#L1032-L1074) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_pull_wildcard`, `_pull_range`) | 40 | [`xitdb/cursor.odin#L1791-L1830`](../../xitdb/cursor.odin#L1791-L1830) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair_slots` | `depth 3` (from `_pull_wildcard`) | 28 | [`xitdb/cursor.odin#L404-L431`](../../xitdb/cursor.odin#L404-L431) |
| `xitdb/dsl.odin` | `_pull_range` | `depth 3` (from `_eval_pull_spec`) | 43 | [`xitdb/dsl.odin#L2303-L2345`](../../xitdb/dsl.odin#L2303-L2345) |
| `xitdb/dsl.odin` | `_unescape_quoted_key` | `depth 4` (from `_parse_step_ident_or_bracket`, `_parse_bracketed_string`) | 26 | [`xitdb/dsl.odin#L367-L392`](../../xitdb/dsl.odin#L367-L392) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 4` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 4` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/types.odin` | `slot_empty` | `depth 4` (from `read_slot_pointer`, `_init_array_list_stack`, `_iterator_step_internal`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/core.odin` | `core_seek_to` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 4` (from `read_slot_pointer`, `read_map_slot`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 788 | [`xitdb/database.odin#L671-L1458`](../../xitdb/database.odin#L671-L1458) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator_init`, `cursor_iterator_array_list_from_index_init`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `_init_array_list_stack`) | 6 | [`xitdb/types.odin#L1484-L1489`](../../xitdb/types.odin#L1484-L1489) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`) | 70 | [`xitdb/hamt.odin#L382-L451`](../../xitdb/hamt.odin#L382-L451) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator_init`, `cursor_iterator_linked_array_list_from_index_init`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `descend_by_rank` | `depth 5` (from `_exec_path_part`) | 76 | [`xitdb/btree.odin#L135-L210`](../../xitdb/btree.odin#L135-L210) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 31 | [`xitdb/btree.odin#L1542-L1572`](../../xitdb/btree.odin#L1542-L1572) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 21 | [`xitdb/btree.odin#L2343-L2363`](../../xitdb/btree.odin#L2343-L2363) |
| `xitdb/types.odin` | `_checked_add_i64` | `depth 5` (from `_exec_path_part`, `cursor_read_kv_pair_slots`, `descend_by_rank`) | 7 | [`xitdb/types.odin#L1498-L1504`](../../xitdb/types.odin#L1498-L1504) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 4` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `_overlay_length` | `depth 4` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/dsl.odin` | `_alloc_cursor_iterator` | `depth 4` (from `_iter_pool_acquire`) | 8 | [`xitdb/dsl.odin#L1869-L1876`](../../xitdb/dsl.odin#L1869-L1876) |
| `xitdb/cursor.odin` | `_reset_cursor_iterator` | `depth 4` (from `cursor_iterator_init`, `cursor_iterator_array_list_from_index_init`, `cursor_iterator_linked_array_list_from_index_init`) | 8 | [`xitdb/cursor.odin#L1023-L1030`](../../xitdb/cursor.odin#L1023-L1030) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator_init`, `cursor_iterator_array_list_from_index_init`, `cursor_iterator_linked_array_list_from_index_init`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_init_array_list_stack` | `depth 4` (from `cursor_iterator_init`, `cursor_iterator_array_list_from_index_init`) | 38 | [`xitdb/cursor.odin#L941-L978`](../../xitdb/cursor.odin#L941-L978) |
| `xitdb/cursor.odin` | `_init_btree_stack` | `depth 4` (from `cursor_iterator_init`) | 32 | [`xitdb/cursor.odin#L908-L939`](../../xitdb/cursor.odin#L908-L939) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator_init`, `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L835-L838`](../../xitdb/cursor.odin#L835-L838) |
| `xitdb/cursor.odin` | `_init_counted_hash_iter` | `depth 4` (from `cursor_iterator_init`) | 42 | [`xitdb/cursor.odin#L980-L1021`](../../xitdb/cursor.odin#L980-L1021) |
| `xitdb/cursor.odin` | `_iterator_step_internal` | `depth 4` (from `cursor_iterator_next`) | 93 | [`xitdb/cursor.odin#L1697-L1789`](../../xitdb/cursor.odin#L1697-L1789) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `cursor_read_kv_pair_slots`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `cursor_read_kv_pair_slots`, `core_read_slot_raw_at`, `read_map_slot`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `cursor_read_kv_pair_slots`, `database_read_root_trailer`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index_init` | `depth 4` (from `_pull_range`) | 30 | [`xitdb/cursor.odin#L1410-L1439`](../../xitdb/cursor.odin#L1410-L1439) |
| `xitdb/cursor.odin` | `cursor_iterator_linked_array_list_from_index_init` | `depth 4` (from `_pull_range`) | 30 | [`xitdb/cursor.odin#L1446-L1475`](../../xitdb/cursor.odin#L1446-L1475) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 6` (from `read_array_list_slot`, `sorted_target_slot`, `sorted_entry_key_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 6` (from `read_array_list_slot`, `read_map_slot`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 6` (from `descend_by_rank`, `sorted_get`, `_read_btree_iter_level`) | 83 | [`xitdb/btree.odin#L1262-L1344`](../../xitdb/btree.odin#L1262-L1344) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 6` (from `descend_by_rank`, `sorted_get`, `_read_btree_iter_level`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 6` (from `descend_by_rank`, `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 66 | [`xitdb/btree.odin#L8-L73`](../../xitdb/btree.odin#L8-L73) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 6` (from `descend_by_rank`, `_read_btree_iter_level`, `_init_btree_stack_from_index`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 6` (from `sorted_get`) | 17 | [`xitdb/btree.odin#L1508-L1524`](../../xitdb/btree.odin#L1508-L1524) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 6` (from `sorted_get`) | 14 | [`xitdb/btree.odin#L1527-L1540`](../../xitdb/btree.odin#L1527-L1540) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_target_slot`, `sorted_leaf_search`) | 6 | [`xitdb/btree.odin#L1407-L1412`](../../xitdb/btree.odin#L1407-L1412) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 6` (from `sorted_target_slot`) | 10 | [`xitdb/database.odin#L591-L600`](../../xitdb/database.odin#L591-L600) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1476-L1481`](../../xitdb/types.odin#L1476-L1481) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `read_map_slot`, `_init_counted_hash_iter`, `_fill_slot_block_rev`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `database_is_old` | `depth 6` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/cursor.odin` | `_fill_slot_block_rev` | `depth 5` (from `_init_array_list_stack`, `_init_iter_level_rev`) | 38 | [`xitdb/cursor.odin#L796-L833`](../../xitdb/cursor.odin#L796-L833) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_array_list_stack`, `_init_iter_level`) | 41 | [`xitdb/cursor.odin#L754-L794`](../../xitdb/cursor.odin#L754-L794) |
| `xitdb/cursor.odin` | `_read_btree_iter_level` | `depth 5` (from `_init_btree_stack`, `_iterator_step_internal`) | 55 | [`xitdb/cursor.odin#L852-L906`](../../xitdb/cursor.odin#L852-L906) |
| `xitdb/cursor.odin` | `_assign_btree_heights` | `depth 5` (from `_init_btree_stack`, `_init_btree_stack_from_index`) | 6 | [`xitdb/cursor.odin#L845-L850`](../../xitdb/cursor.odin#L845-L850) |
| `xitdb/cursor.odin` | `_decode_slot_block_raw` | `depth 5` (from `_init_counted_hash_iter`) | 7 | [`xitdb/cursor.odin#L746-L752`](../../xitdb/cursor.odin#L746-L752) |
| `xitdb/cursor.odin` | `_init_iter_level_rev` | `depth 5` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L840-L843`](../../xitdb/cursor.odin#L840-L843) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 5` (from `cursor_iterator_array_list_from_index_init`, `cursor_iterator_linked_array_list_from_index_init`) | 11 | [`xitdb/cursor.odin#L1130-L1140`](../../xitdb/cursor.odin#L1130-L1140) |
| `xitdb/cursor.odin` | `_init_btree_stack_from_index` | `depth 5` (from `cursor_iterator_linked_array_list_from_index_init`) | 132 | [`xitdb/cursor.odin#L1154-L1285`](../../xitdb/cursor.odin#L1154-L1285) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 7` (from `read_sorted_node`, `read_btree_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 7` (from `read_sorted_node`, `read_btree_node`, `_fill_slot_block_rev`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/types.odin` | `is_sorted_entry_tag` | `depth 7` (from `read_sorted_node`) | 8 | [`xitdb/types.odin#L1392-L1399`](../../xitdb/types.odin#L1392-L1399) |
| `xitdb/btree.odin` | `compare_key` | `depth 7` (from `sorted_leaf_search`, `sorted_branch_search`) | 84 | [`xitdb/btree.odin#L1421-L1504`](../../xitdb/btree.odin#L1421-L1504) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 7` (from `database_kv_value_position`) | 10 | [`xitdb/database.odin#L580-L589`](../../xitdb/database.odin#L580-L589) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 7` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 8` (from `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
