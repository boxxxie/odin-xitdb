# #68. `DSL Layer 3: Datomic pull projection (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2233-L2243`)](../bench_xitdb.odin#L2233-L2243)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **1,710** | 1,837.8 ± 245.0 | 13.3% | 2,177.0 | 584,795 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2233-L2243`](../bench_xitdb.odin#L2233-L2243))

```odin
2233 | 		t2 := time.now()
2234 | 		for i in 0 ..< M {
2235 | 			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
2236 | 			pv, p_err := xitdb.pull(pcur_maybe.?, "{username, age, todos[0..2]}", context.temp_allocator)
2237 | 			assert(p_err == nil && pv != nil)
2238 | 		}
2239 | 		print_result(Bench_Result{
2240 | 			name    = "DSL Layer 3: Datomic pull projection (N=200)",
2241 | 			ops     = M,
2242 | 			elapsed = time.since(t2),
2243 | 		})
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

### Reached Odin Procedures (`100` procedures across `8` files · `2321` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`, `Hash_Map_Get`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 15 | [`xitdb/dsl.odin#L410-L424`](../../xitdb/dsl.odin#L410-L424) |
| `xitdb/dsl.odin` | `pull` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L1697-L1707`](../../xitdb/dsl.odin#L1697-L1707) |
| `xitdb/dsl.odin` | `parse_selector` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L122-L152`](../../xitdb/dsl.odin#L122-L152) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `select_cursor`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `read_steps_cursor`, `_pull_range`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`, `_eval_pull_spec`) | 91 | [`xitdb/dsl.odin#L317-L407`](../../xitdb/dsl.odin#L317-L407) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `pull`, `_pull_wildcard`, `_pull_range`) | 4 | [`xitdb/cursor.odin#L64-L67`](../../xitdb/cursor.odin#L64-L67) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 1` (from `pull`, `_pull_wildcard`) | 9 | [`xitdb/dsl.odin#L1686-L1694`](../../xitdb/dsl.odin#L1686-L1694) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 1` (from `pull`) | 24 | [`xitdb/dsl.odin#L1709-L1732`](../../xitdb/dsl.odin#L1709-L1732) |
| `xitdb/dsl.odin` | `_pull_with_visited` | `depth 1` (from `pull`, `_eval_pull_spec`, `_pull_range`) | 20 | [`xitdb/dsl.odin#L1744-L1763`](../../xitdb/dsl.odin#L1744-L1763) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 2` (from `parse_selector`, `_eval_pull_spec`) | 107 | [`xitdb/dsl.odin#L154-L260`](../../xitdb/dsl.odin#L154-L260) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`, `read_steps_cursor`, `cursor_slot`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L247-L255`](../../xitdb/collections.odin#L247-L255) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 2` (from `read_steps_cursor`, `_pull_range`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L133-L135`](../../xitdb/collections.odin#L133-L135) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L500-L508`](../../xitdb/collections.odin#L500-L508) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L562-L566`](../../xitdb/collections.odin#L562-L566) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L517-L525`](../../xitdb/collections.odin#L517-L525) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L803-L811`](../../xitdb/collections.odin#L803-L811) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 10 | [`xitdb/cursor.odin#L201-L210`](../../xitdb/cursor.odin#L201-L210) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L212-L218`](../../xitdb/cursor.odin#L212-L218) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L220-L226`](../../xitdb/cursor.odin#L220-L226) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`, `cursor_read_bytes`) | 56 | [`xitdb/cursor.odin#L241-L296`](../../xitdb/cursor.odin#L241-L296) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L236-L239`](../../xitdb/cursor.odin#L236-L239) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 2` (from `_pull_with_visited`) | 80 | [`xitdb/dsl.odin#L1860-L1939`](../../xitdb/dsl.odin#L1860-L1939) |
| `xitdb/dsl.odin` | `_split_top_level_pull_specs` | `depth 2` (from `_pull_with_visited`) | 27 | [`xitdb/dsl.odin#L1941-L1967`](../../xitdb/dsl.odin#L1941-L1967) |
| `xitdb/dsl.odin` | `_eval_pull_spec` | `depth 2` (from `_pull_with_visited`) | 51 | [`xitdb/dsl.odin#L1779-L1829`](../../xitdb/dsl.odin#L1779-L1829) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 3` (from `parse_steps`) | 33 | [`xitdb/dsl.odin#L262-L294`](../../xitdb/dsl.odin#L262-L294) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 3` (from `parse_steps`, `_parse_step_ident_or_bracket`) | 19 | [`xitdb/dsl.odin#L296-L314`](../../xitdb/dsl.odin#L296-L314) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 3` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 3` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L554-L556`](../../xitdb/collections.odin#L554-L556) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_read_bytes_object`, `database_read_root_header`, `read_slot_pointer`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_long` | `depth 3` (from `cursor_read_bytes_object`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `cursor_read_bytes_object`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L228-L234`](../../xitdb/cursor.odin#L228-L234) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 3` (from `_pull_wildcard`) | 43 | [`xitdb/cursor.odin#L755-L797`](../../xitdb/cursor.odin#L755-L797) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_pull_wildcard`, `_pull_range`) | 22 | [`xitdb/cursor.odin#L1117-L1138`](../../xitdb/cursor.odin#L1117-L1138) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 3` (from `_pull_wildcard`) | 19 | [`xitdb/cursor.odin#L366-L384`](../../xitdb/cursor.odin#L366-L384) |
| `xitdb/dsl.odin` | `_pull_range` | `depth 3` (from `_eval_pull_spec`) | 28 | [`xitdb/dsl.odin#L1831-L1858`](../../xitdb/dsl.odin#L1831-L1858) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`, `read_map_slot`, `decode_kv_pair`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_empty` | `depth 4` (from `read_slot_pointer`, `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `read_slot_pointer`, `sorted_target_slot`, `read_array_list_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator`, `cursor_iterator_linked_array_list_from_index`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator`, `cursor_iterator_array_list_from_index`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `cursor_iterator_array_list_from_index`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 5` (from `_exec_path_part`) | 79 | [`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 4` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read_i64` | `depth 4` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator`, `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 4 | [`xitdb/cursor.odin#L59-L62`](../../xitdb/cursor.odin#L59-L62) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L722-L725`](../../xitdb/cursor.odin#L722-L725) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L727-L753`](../../xitdb/cursor.odin#L727-L753) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 4` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1082-L1115`](../../xitdb/cursor.odin#L1082-L1115) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `cursor_read_kv_pair`, `sorted_target_slot`, `database_kv_key_position`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 4` (from `cursor_read_kv_pair`) | 35 | [`xitdb/types.odin#L1149-L1183`](../../xitdb/types.odin#L1149-L1183) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 4` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L537-L542`](../../xitdb/database.odin#L537-L542) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 4` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L544-L549`](../../xitdb/database.odin#L544-L549) |
| `xitdb/collections.odin` | `array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/collections.odin` | `linked_array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L145-L147`](../../xitdb/collections.odin#L145-L147) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `root_header_from_bytes`, `core_read_slot_raw`, `_init_btree_iter_level`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 5` (from `core_read_slot_raw`, `sorted_get`, `read_btree_slot`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `sorted_get`, `read_btree_slot`, `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_get`, `sorted_target_slot`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `sorted_get`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 6` (from `sorted_target_slot`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/core.odin` | `core_length` | `depth 6` (from `read_array_list_slot`, `read_map_slot`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 6` (from `read_array_list_slot`, `read_map_slot`, `encode_kv_pair`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/database.odin` | `database_is_old` | `depth 6` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_iter_level`, `cursor_iterator_array_list_from_index`) | 21 | [`xitdb/cursor.odin#L680-L700`](../../xitdb/cursor.odin#L680-L700) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 5` (from `decode_kv_pair`, `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 5` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1130-L1139`](../../xitdb/types.odin#L1130-L1139) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 5` (from `array_list_iterator_from`) | 36 | [`xitdb/cursor.odin#L983-L1018`](../../xitdb/cursor.odin#L983-L1018) |
| `xitdb/cursor.odin` | `cursor_iterator_linked_array_list_from_index` | `depth 5` (from `linked_array_list_iterator_from`) | 61 | [`xitdb/cursor.odin#L1020-L1080`](../../xitdb/cursor.odin#L1020-L1080) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 6` (from `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 11 | [`xitdb/cursor.odin#L799-L809`](../../xitdb/cursor.odin#L799-L809) |
| `xitdb/cursor.odin` | `_fill_slot_block_raw_from` | `depth 6` (from `cursor_iterator_linked_array_list_from_index`) | 19 | [`xitdb/cursor.odin#L702-L720`](../../xitdb/cursor.odin#L702-L720) |
