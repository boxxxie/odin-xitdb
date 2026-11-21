# #67. `DSL Layer 3: Struct unmarshal (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2568-L2581`)](../bench_xitdb.odin#L2568-L2581)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **3,333** | 3,332.0 ± 30.1 | 0.9% | 3,369.4 | 300,030 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2568-L2581`](../bench_xitdb.odin#L2568-L2581))

```odin
2568 | 		sp1 := span_begin()
2569 | 		for i in 0 ..< M {
2570 | 			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
2571 | 			out, u_err := xitdb.unmarshal(Bench_User_DTO, pcur_maybe.?, context.temp_allocator)
2572 | 			assert(u_err == nil && out.age == 31)
2573 | 		}
2574 | 		el1, hw1, has_hw1 := span_end(sp1)
2575 | 		print_result(Bench_Result{
2576 | 			name         = "DSL Layer 3: Struct unmarshal (N=200)",
2577 | 			ops          = M,
2578 | 			elapsed      = el1,
2579 | 			counters     = hw1,
2580 | 			has_counters = has_hw1,
2581 | 		})
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

### Reached Odin Procedures (`173` procedures across `8` files · `4454` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Linked_Array_List_Init`, `Linked_Array_List_Get`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 17 | [`xitdb/dsl.odin#L685-L701`](../../xitdb/dsl.odin#L685-L701) |
| `xitdb/dsl.odin` | `unmarshal` | **Entry Point** (`depth 0`) | 4 | [`xitdb/dsl.odin#L1842-L1845`](../../xitdb/dsl.odin#L1842-L1845) |
| `xitdb/dsl.odin` | `parse_selector_buf` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L199-L229`](../../xitdb/dsl.odin#L199-L229) |
| `xitdb/dsl.odin` | `selector_destroy_buf` | `depth 1` (from `select_cursor`) | 4 | [`xitdb/dsl.odin#L69-L72`](../../xitdb/dsl.odin#L69-L72) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `select_cursor`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`) | 91 | [`xitdb/dsl.odin#L467-L557`](../../xitdb/dsl.odin#L467-L557) |
| `xitdb/dsl.odin` | `unmarshal_into` | `depth 1` (from `unmarshal`) | 5 | [`xitdb/dsl.odin#L1907-L1911`](../../xitdb/dsl.odin#L1907-L1911) |
| `xitdb/dsl.odin` | `parse_steps_buf` | `depth 2` (from `parse_selector_buf`) | 127 | [`xitdb/dsl.odin#L239-L365`](../../xitdb/dsl.odin#L239-L365) |
| `xitdb/dsl.odin` | `steps_destroy_buf` | `depth 2` (from `selector_destroy_buf`, `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L57-L66`](../../xitdb/dsl.odin#L57-L66) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`, `read_steps_cursor`, `cursor_read_path`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 2` (from `read_steps_cursor`, `_unmarshal_into_pooled`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 2` (from `read_steps_cursor`, `_unmarshal_into_pooled`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L263-L271`](../../xitdb/collections.odin#L263-L271) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L693-L701`](../../xitdb/collections.odin#L693-L701) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L141-L143`](../../xitdb/collections.odin#L141-L143) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L520-L528`](../../xitdb/collections.odin#L520-L528) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L586-L590`](../../xitdb/collections.odin#L586-L590) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L537-L545`](../../xitdb/collections.odin#L537-L545) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L842-L850`](../../xitdb/collections.odin#L842-L850) |
| `xitdb/dsl.odin` | `_iter_pool_init` | `depth 2` (from `unmarshal_into`) | 7 | [`xitdb/dsl.odin#L1853-L1859`](../../xitdb/dsl.odin#L1853-L1859) |
| `xitdb/dsl.odin` | `_iter_pool_destroy` | `depth 2` (from `unmarshal_into`) | 7 | [`xitdb/dsl.odin#L1861-L1867`](../../xitdb/dsl.odin#L1861-L1867) |
| `xitdb/dsl.odin` | `_unmarshal_into_pooled` | `depth 2` (from `unmarshal_into`) | 125 | [`xitdb/dsl.odin#L1913-L2037`](../../xitdb/dsl.odin#L1913-L2037) |
| `xitdb/dsl.odin` | `steps_destroy` | `depth 3` (from `parse_steps_buf`) | 10 | [`xitdb/dsl.odin#L39-L48`](../../xitdb/dsl.odin#L39-L48) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 3` (from `parse_steps_buf`) | 42 | [`xitdb/dsl.odin#L394-L435`](../../xitdb/dsl.odin#L394-L435) |
| `xitdb/dsl.odin` | `_push_step_buf` | `depth 3` (from `parse_steps_buf`) | 23 | [`xitdb/dsl.odin#L174-L196`](../../xitdb/dsl.odin#L174-L196) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 3` (from `parse_steps_buf`, `_parse_step_ident_or_bracket`) | 28 | [`xitdb/dsl.odin#L437-L464`](../../xitdb/dsl.odin#L437-L464) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_read_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 67 | [`xitdb/database.odin#L603-L669`](../../xitdb/database.odin#L603-L669) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 3` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 3` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L578-L580`](../../xitdb/collections.odin#L578-L580) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 3` (from `_unmarshal_into_pooled`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 3` (from `_unmarshal_into_pooled`) | 7 | [`xitdb/cursor.odin#L209-L215`](../../xitdb/cursor.odin#L209-L215) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 3` (from `_unmarshal_into_pooled`) | 10 | [`xitdb/cursor.odin#L198-L207`](../../xitdb/cursor.odin#L198-L207) |
| `xitdb/dsl.odin` | `_assign_signed_int` | `depth 3` (from `_unmarshal_into_pooled`) | 15 | [`xitdb/dsl.odin#L2039-L2053`](../../xitdb/dsl.odin#L2039-L2053) |
| `xitdb/dsl.odin` | `_assign_unsigned_int` | `depth 3` (from `_unmarshal_into_pooled`) | 15 | [`xitdb/dsl.odin#L2055-L2069`](../../xitdb/dsl.odin#L2055-L2069) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 3` (from `_unmarshal_into_pooled`) | 7 | [`xitdb/cursor.odin#L217-L223`](../../xitdb/cursor.odin#L217-L223) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 3` (from `_unmarshal_into_pooled`) | 4 | [`xitdb/cursor.odin#L233-L236`](../../xitdb/cursor.odin#L233-L236) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `_unmarshal_into_pooled`, `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L225-L231`](../../xitdb/cursor.odin#L225-L231) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 3` (from `_unmarshal_into_pooled`) | 9 | [`xitdb/dsl.odin#L2093-L2101`](../../xitdb/dsl.odin#L2093-L2101) |
| `xitdb/dsl.odin` | `_iter_pool_acquire` | `depth 3` (from `_unmarshal_into_pooled`) | 7 | [`xitdb/dsl.odin#L1878-L1884`](../../xitdb/dsl.odin#L1878-L1884) |
| `xitdb/dsl.odin` | `_iter_pool_release` | `depth 3` (from `_unmarshal_into_pooled`) | 9 | [`xitdb/dsl.odin#L1886-L1894`](../../xitdb/dsl.odin#L1886-L1894) |
| `xitdb/cursor.odin` | `cursor_iterator_init` | `depth 3` (from `_unmarshal_into_pooled`) | 43 | [`xitdb/cursor.odin#L1032-L1074`](../../xitdb/cursor.odin#L1032-L1074) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_unmarshal_into_pooled`) | 40 | [`xitdb/cursor.odin#L1791-L1830`](../../xitdb/cursor.odin#L1791-L1830) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair_slots` | `depth 3` (from `_unmarshal_into_pooled`) | 28 | [`xitdb/cursor.odin#L404-L431`](../../xitdb/cursor.odin#L404-L431) |
| `xitdb/dsl.odin` | `_parse_field_tag` | `depth 3` (from `_unmarshal_into_pooled`) | 8 | [`xitdb/dsl.odin#L1658-L1665`](../../xitdb/dsl.odin#L1658-L1665) |
| `xitdb/dsl.odin` | `_unescape_quoted_key` | `depth 4` (from `_parse_step_ident_or_bracket`, `_parse_bracketed_string`) | 26 | [`xitdb/dsl.odin#L367-L392`](../../xitdb/dsl.odin#L367-L392) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 4` (from `database_read_root_header`, `database_write_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 4` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `database_read_root_header`, `_exec_path_part`, `_database_truncate_with_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/types.odin` | `slot_empty` | `depth 4` (from `read_slot_pointer`, `btree_get_for_write`, `_init_array_list_stack`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 4` (from `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/database.odin` | `init_tag` | `depth 4` (from `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 4` (from `read_slot_pointer`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_seek_to` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_write_slot` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 4` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 4` (from `read_slot_pointer`, `read_map_slot`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_random_u64` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_commit_root` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 788 | [`xitdb/database.odin#L671-L1458`](../../xitdb/database.odin#L671-L1458) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 5` (from `_exec_path_part`, `cursor_iterator_init`, `cursor_read_kv_pair_slots`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator_init`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `_init_array_list_stack`) | 6 | [`xitdb/types.odin#L1484-L1489`](../../xitdb/types.odin#L1484-L1489) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`) | 70 | [`xitdb/hamt.odin#L382-L451`](../../xitdb/hamt.odin#L382-L451) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 5` (from `_exec_path_part`, `btree_get_for_write`) | 5 | [`xitdb/btree.odin#L109-L113`](../../xitdb/btree.odin#L109-L113) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/core.odin` | `core_write_all` | `depth 5` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 5` (from `_exec_path_part`, `cursor_iterator_init`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `descend_by_rank` | `depth 5` (from `_exec_path_part`) | 76 | [`xitdb/btree.odin#L135-L210`](../../xitdb/btree.odin#L135-L210) |
| `xitdb/btree.odin` | `btree_get_for_write` | `depth 5` (from `_exec_path_part`) | 106 | [`xitdb/btree.odin#L492-L597`](../../xitdb/btree.odin#L492-L597) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 5` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1386-L1390`](../../xitdb/btree.odin#L1386-L1390) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 5` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 31 | [`xitdb/btree.odin#L1542-L1572`](../../xitdb/btree.odin#L1542-L1572) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 21 | [`xitdb/btree.odin#L2343-L2363`](../../xitdb/btree.odin#L2343-L2363) |
| `xitdb/btree.odin` | `sorted_put` | `depth 5` (from `_exec_path_part`) | 438 | [`xitdb/btree.odin#L1707-L2144`](../../xitdb/btree.odin#L1707-L2144) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2330-L2341`](../../xitdb/btree.odin#L2330-L2341) |
| `xitdb/types.odin` | `_checked_add_i64` | `depth 5` (from `_exec_path_part`, `cursor_read_kv_pair_slots`, `descend_by_rank`) | 7 | [`xitdb/types.odin#L1498-L1504`](../../xitdb/types.odin#L1498-L1504) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 4` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/core.odin` | `core_write_long` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 5` (from `_exec_path_part`, `cursor_read_bytes_object`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 4` (from `cursor_read_bytes`) | 66 | [`xitdb/cursor.odin#L238-L303`](../../xitdb/cursor.odin#L238-L303) |
| `xitdb/dsl.odin` | `_alloc_cursor_iterator` | `depth 4` (from `_iter_pool_acquire`) | 8 | [`xitdb/dsl.odin#L1869-L1876`](../../xitdb/dsl.odin#L1869-L1876) |
| `xitdb/cursor.odin` | `_reset_cursor_iterator` | `depth 4` (from `cursor_iterator_init`) | 8 | [`xitdb/cursor.odin#L1023-L1030`](../../xitdb/cursor.odin#L1023-L1030) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator_init`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/cursor.odin` | `_init_array_list_stack` | `depth 4` (from `cursor_iterator_init`) | 38 | [`xitdb/cursor.odin#L941-L978`](../../xitdb/cursor.odin#L941-L978) |
| `xitdb/cursor.odin` | `_init_btree_stack` | `depth 4` (from `cursor_iterator_init`) | 32 | [`xitdb/cursor.odin#L908-L939`](../../xitdb/cursor.odin#L908-L939) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator_init`, `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L835-L838`](../../xitdb/cursor.odin#L835-L838) |
| `xitdb/cursor.odin` | `_init_counted_hash_iter` | `depth 4` (from `cursor_iterator_init`) | 42 | [`xitdb/cursor.odin#L980-L1021`](../../xitdb/cursor.odin#L980-L1021) |
| `xitdb/cursor.odin` | `_iterator_step_internal` | `depth 4` (from `cursor_iterator_next`) | 93 | [`xitdb/cursor.odin#L1697-L1789`](../../xitdb/cursor.odin#L1697-L1789) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `cursor_read_kv_pair_slots`, `sorted_target_slot`, `sorted_put`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `cursor_read_kv_pair_slots`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `cursor_read_kv_pair_slots`, `core_read_slot_raw_at`, `read_map_slot`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `cursor_read_kv_pair_slots`, `database_read_root_trailer`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/dsl.odin` | `_parse_raw_tag_val` | `depth 4` (from `_parse_field_tag`) | 50 | [`xitdb/dsl.odin#L1607-L1656`](../../xitdb/dsl.odin#L1607-L1656) |
| `xitdb/core.odin` | `_overlay_length` | `depth 5` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 5` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 5` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/core.odin` | `core_set_length` | `depth 5` (from `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/core.odin` | `core_sync` | `depth 5` (from `_database_truncate_with_header`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/core.odin` | `_memory_resize` | `depth 5` (from `core_write_slot`, `core_write_all`, `_overlay_write_at`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `core_write_slot`, `read_array_list_slot`, `sorted_put`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 5` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 5` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 5` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/core.odin` | `core_read_at` | `depth 6` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 6` (from `read_array_list_slot`, `btree_get_for_write`, `sorted_target_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`, `read_map_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 6` (from `write_btree_node`) | 33 | [`xitdb/btree.odin#L75-L107`](../../xitdb/btree.odin#L75-L107) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 6` (from `core_write_all`, `core_sync`, `core_flush`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 6` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 6` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 6` (from `descend_by_rank`, `sorted_get`, `sorted_put`) | 83 | [`xitdb/btree.odin#L1262-L1344`](../../xitdb/btree.odin#L1262-L1344) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 6` (from `descend_by_rank`, `sorted_get`, `sorted_put`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 6` (from `descend_by_rank`, `btree_get_for_write`, `_read_btree_iter_level`) | 66 | [`xitdb/btree.odin#L8-L73`](../../xitdb/btree.odin#L8-L73) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 6` (from `descend_by_rank`, `btree_get_for_write`, `_read_btree_iter_level`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 6` (from `btree_get_for_write`, `sorted_put`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L115-L121`](../../xitdb/btree.odin#L115-L121) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 6` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1346-L1384`](../../xitdb/btree.odin#L1346-L1384) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 6` (from `sorted_get`, `sorted_put`) | 17 | [`xitdb/btree.odin#L1508-L1524`](../../xitdb/btree.odin#L1508-L1524) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 6` (from `sorted_get`, `sorted_put`) | 14 | [`xitdb/btree.odin#L1527-L1540`](../../xitdb/btree.odin#L1527-L1540) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_target_slot`, `sorted_put`, `sorted_leaf_search`) | 6 | [`xitdb/btree.odin#L1407-L1412`](../../xitdb/btree.odin#L1407-L1412) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 6` (from `sorted_target_slot`) | 10 | [`xitdb/database.odin#L591-L600`](../../xitdb/database.odin#L591-L600) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 6` (from `sorted_put`, `compare_key`, `core_read_block_at`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `sorted_put`, `read_sorted_node`, `read_btree_node`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/types.odin` | `is_sorted_entry_tag` | `depth 6` (from `sorted_put`, `read_sorted_node`) | 8 | [`xitdb/types.odin#L1392-L1399`](../../xitdb/types.odin#L1392-L1399) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `sorted_put`, `sorted_leaf_search`, `sorted_branch_search`) | 84 | [`xitdb/btree.odin#L1421-L1504`](../../xitdb/btree.odin#L1421-L1504) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 6` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1644-L1650`](../../xitdb/btree.odin#L1644-L1650) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 6` (from `sorted_put`) | 6 | [`xitdb/btree.odin#L1400-L1405`](../../xitdb/btree.odin#L1400-L1405) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 6` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1414-L1419`](../../xitdb/btree.odin#L1414-L1419) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 6` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1652-L1705`](../../xitdb/btree.odin#L1652-L1705) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 6` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1392-L1398`](../../xitdb/btree.odin#L1392-L1398) |
| `xitdb/core.odin` | `core_write_i64` | `depth 6` (from `sorted_put`, `core_write_long`, `database_write_root_header`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/types.odin` | `_sum_counts_i64` | `depth 6` (from `sorted_put`) | 14 | [`xitdb/types.odin#L1506-L1519`](../../xitdb/types.odin#L1506-L1519) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1476-L1481`](../../xitdb/types.odin#L1476-L1481) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `read_map_slot`, `_init_counted_hash_iter`, `_fill_slot_block_rev`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/cursor.odin` | `_fill_slot_block_rev` | `depth 5` (from `_init_array_list_stack`, `_init_iter_level_rev`) | 38 | [`xitdb/cursor.odin#L796-L833`](../../xitdb/cursor.odin#L796-L833) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_array_list_stack`, `_init_iter_level`) | 41 | [`xitdb/cursor.odin#L754-L794`](../../xitdb/cursor.odin#L754-L794) |
| `xitdb/cursor.odin` | `_read_btree_iter_level` | `depth 5` (from `_init_btree_stack`, `_iterator_step_internal`) | 55 | [`xitdb/cursor.odin#L852-L906`](../../xitdb/cursor.odin#L852-L906) |
| `xitdb/cursor.odin` | `_assign_btree_heights` | `depth 5` (from `_init_btree_stack`) | 6 | [`xitdb/cursor.odin#L845-L850`](../../xitdb/cursor.odin#L845-L850) |
| `xitdb/cursor.odin` | `_decode_slot_block_raw` | `depth 5` (from `_init_counted_hash_iter`) | 7 | [`xitdb/cursor.odin#L746-L752`](../../xitdb/cursor.odin#L746-L752) |
| `xitdb/cursor.odin` | `_init_iter_level_rev` | `depth 5` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L840-L843`](../../xitdb/cursor.odin#L840-L843) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 6` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `core_flush` | `depth 6` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 7` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_overlay_page` | `depth 7` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 7` (from `read_sorted_node`, `read_btree_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 7` (from `database_kv_value_position`) | 10 | [`xitdb/database.odin#L580-L589`](../../xitdb/database.odin#L580-L589) |
| `xitdb/types.odin` | `decode_kv_pair_at` | `depth 7` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1215-L1249`](../../xitdb/types.odin#L1215-L1249) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `write_kv_pair`, `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 7` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `kv_pair_read_buf_at`, `decode_kv_pair_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 7` (from `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 8` (from `decode_kv_pair_at`) | 10 | [`xitdb/types.odin#L1145-L1154`](../../xitdb/types.odin#L1145-L1154) |
