# #68. `DSL Layer 3: Datomic pull projection (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2275-L2285`)](../bench_xitdb.odin#L2275-L2285)

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

### Odin ([`benchmarks/bench_xitdb.odin#L2275-L2285`](../bench_xitdb.odin#L2275-L2285))

```odin
2275 | 		t2 := time.now()
2276 | 		for i in 0 ..< M {
2277 | 			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
2278 | 			pv, p_err := xitdb.pull(pcur_maybe.?, "{username, age, todos[0..2]}", context.temp_allocator)
2279 | 			assert(p_err == nil && pv != nil)
2280 | 		}
2281 | 		print_result(Bench_Result{
2282 | 			name    = "DSL Layer 3: Datomic pull projection (N=200)",
2283 | 			ops     = M,
2284 | 			elapsed = time.since(t2),
2285 | 		})
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

### Reached Odin Procedures (`111` procedures across `8` files · `2619` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`, `Hash_Map_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 17 | [`xitdb/dsl.odin#L685-L701`](../../xitdb/dsl.odin#L685-L701) |
| `xitdb/dsl.odin` | `pull` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L2020-L2030`](../../xitdb/dsl.odin#L2020-L2030) |
| `xitdb/dsl.odin` | `parse_selector_buf` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L199-L229`](../../xitdb/dsl.odin#L199-L229) |
| `xitdb/dsl.odin` | `selector_destroy_buf` | `depth 1` (from `select_cursor`) | 4 | [`xitdb/dsl.odin#L69-L72`](../../xitdb/dsl.odin#L69-L72) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `select_cursor`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `read_steps_cursor`, `_pull_range`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`, `_eval_pull_spec`) | 91 | [`xitdb/dsl.odin#L467-L557`](../../xitdb/dsl.odin#L467-L557) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `pull`, `_pull_wildcard`, `_pull_range`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 1` (from `pull`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L2009-L2017`](../../xitdb/dsl.odin#L2009-L2017) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 1` (from `pull`) | 24 | [`xitdb/dsl.odin#L2032-L2055`](../../xitdb/dsl.odin#L2032-L2055) |
| `xitdb/dsl.odin` | `_pull_with_visited` | `depth 1` (from `pull`, `_eval_pull_spec`, `_pull_range`) | 30 | [`xitdb/dsl.odin#L2102-L2131`](../../xitdb/dsl.odin#L2102-L2131) |
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
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 2` (from `read_steps_cursor`, `_pull_range`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
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
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 2` (from `_pull_with_visited`) | 106 | [`xitdb/dsl.odin#L2243-L2348`](../../xitdb/dsl.odin#L2243-L2348) |
| `xitdb/dsl.odin` | `_split_top_level_pull_specs` | `depth 2` (from `_pull_with_visited`) | 27 | [`xitdb/dsl.odin#L2350-L2376`](../../xitdb/dsl.odin#L2350-L2376) |
| `xitdb/dsl.odin` | `pull_value_destroy` | `depth 2` (from `_pull_with_visited`, `_pull_wildcard`, `_pull_range`) | 33 | [`xitdb/dsl.odin#L2068-L2100`](../../xitdb/dsl.odin#L2068-L2100) |
| `xitdb/dsl.odin` | `_eval_pull_spec` | `depth 2` (from `_pull_with_visited`) | 53 | [`xitdb/dsl.odin#L2147-L2199`](../../xitdb/dsl.odin#L2147-L2199) |
| `xitdb/dsl.odin` | `steps_destroy` | `depth 3` (from `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L39-L48`](../../xitdb/dsl.odin#L39-L48) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 3` (from `parse_steps_buf`) | 42 | [`xitdb/dsl.odin#L394-L435`](../../xitdb/dsl.odin#L394-L435) |
| `xitdb/dsl.odin` | `_push_step_buf` | `depth 3` (from `parse_steps_buf`) | 23 | [`xitdb/dsl.odin#L174-L196`](../../xitdb/dsl.odin#L174-L196) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 3` (from `parse_steps_buf`, `_parse_step_ident_or_bracket`) | 28 | [`xitdb/dsl.odin#L437-L464`](../../xitdb/dsl.odin#L437-L464) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_read_path`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 3` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 3` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L578-L580`](../../xitdb/collections.odin#L578-L580) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 3` (from `cursor_read_bytes_object`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_length` | `depth 3` (from `cursor_read_bytes_object`, `database_read_root_header`, `read_array_list_slot`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `cursor_read_bytes_object`, `_exec_path_part`, `cursor_iterator`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L225-L231`](../../xitdb/cursor.odin#L225-L231) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 3` (from `_pull_wildcard`) | 45 | [`xitdb/cursor.odin#L891-L935`](../../xitdb/cursor.odin#L891-L935) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_pull_wildcard`, `_pull_range`) | 22 | [`xitdb/cursor.odin#L1614-L1635`](../../xitdb/cursor.odin#L1614-L1635) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair_slots` | `depth 3` (from `_pull_wildcard`) | 22 | [`xitdb/cursor.odin#L404-L425`](../../xitdb/cursor.odin#L404-L425) |
| `xitdb/dsl.odin` | `_pull_range` | `depth 3` (from `_eval_pull_spec`) | 41 | [`xitdb/dsl.odin#L2201-L2241`](../../xitdb/dsl.odin#L2201-L2241) |
| `xitdb/dsl.odin` | `_unescape_quoted_key` | `depth 4` (from `_parse_step_ident_or_bracket`, `_parse_bracketed_string`) | 26 | [`xitdb/dsl.odin#L367-L392`](../../xitdb/dsl.odin#L367-L392) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 4` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 4` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/types.odin` | `slot_empty` | `depth 4` (from `read_slot_pointer`, `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/core.odin` | `core_seek_to` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 4` (from `read_slot_pointer`, `read_map_slot`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator`, `cursor_iterator_array_list_from_index`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `cursor_iterator_array_list_from_index`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator`, `cursor_iterator_linked_array_list_from_index`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 61 | [`xitdb/btree.odin#L1315-L1375`](../../xitdb/btree.odin#L1315-L1375) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 17 | [`xitdb/btree.odin#L2087-L2103`](../../xitdb/btree.odin#L2087-L2103) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/btree.odin` | `descend_by_rank` | `depth 5` (from `_exec_path_part`) | 48 | [`xitdb/btree.odin#L105-L152`](../../xitdb/btree.odin#L105-L152) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 4` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `_overlay_length` | `depth 4` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`, `_init_btree_iter_level`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator`, `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L786-L789`](../../xitdb/cursor.odin#L786-L789) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 44 | [`xitdb/cursor.odin#L796-L839`](../../xitdb/cursor.odin#L796-L839) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 4` (from `cursor_iterator_next`) | 37 | [`xitdb/cursor.odin#L1538-L1574`](../../xitdb/cursor.odin#L1538-L1574) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `cursor_read_kv_pair_slots`, `core_read_slot_raw_at`, `read_map_slot`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `cursor_read_kv_pair_slots`, `database_read_root_trailer`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/collections.odin` | `array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/collections.odin` | `linked_array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L153-L155`](../../xitdb/collections.odin#L153-L155) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 6` (from `read_array_list_slot`, `sorted_target_slot`, `sorted_entry_key_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 6` (from `read_array_list_slot`, `read_map_slot`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 6` (from `sorted_get`, `descend_by_rank`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `sorted_get`, `descend_by_rank`, `_init_btree_iter_level`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_get`, `sorted_target_slot`) | 6 | [`xitdb/btree.odin#L1180-L1185`](../../xitdb/btree.odin#L1180-L1185) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `sorted_get`) | 84 | [`xitdb/btree.odin#L1194-L1277`](../../xitdb/btree.odin#L1194-L1277) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `read_map_slot`, `_init_btree_iter_level`, `_fill_slot_block_from`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `database_is_old` | `depth 6` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_iter_level`, `_init_btree_iter_level`, `cursor_iterator_array_list_from_index`) | 27 | [`xitdb/cursor.odin#L730-L756`](../../xitdb/cursor.odin#L730-L756) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 5` (from `array_list_iterator_from`) | 38 | [`xitdb/cursor.odin#L1157-L1194`](../../xitdb/cursor.odin#L1157-L1194) |
| `xitdb/cursor.odin` | `cursor_iterator_linked_array_list_from_index` | `depth 5` (from `linked_array_list_iterator_from`) | 64 | [`xitdb/cursor.odin#L1196-L1259`](../../xitdb/cursor.odin#L1196-L1259) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 7` (from `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 7` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 6` (from `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 11 | [`xitdb/cursor.odin#L974-L984`](../../xitdb/cursor.odin#L974-L984) |
