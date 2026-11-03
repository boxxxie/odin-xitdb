# #67. `DSL Layer 3: Struct unmarshal (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L2221-L2231`)](../bench_xitdb.odin#L2221-L2231)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **1,977** | 1,971.8 ± 25.7 | 1.3% | 1,998.2 | 505,817 | - |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Odin-Native 5-Layer Ergonomic DSL ([`xitdb/dsl.odin`](../../xitdb/dsl.odin)):** Built directly on top of the wire-compatible core (`Read_Cursor`, `Write_Cursor`, `Hash_Map`, `Sorted_Map`, `Array_List`), providing path selectors (`Layer 1`), transactional `Tx` + automatic B+Tree secondary index maintenance (`Layer 2`), reflection-driven struct `marshal`/`unmarshal` & cycle-safe Datomic `pull` (`Layer 3`), structural `diff_moments` & `history_of` (`Layer 4`), and a stratified Datalog engine with B+Tree prefix pushdown (`Layer 5`).
- **Zero-Allocation Hot Paths & B+Tree Index Selection ([`xitdb/dsl.odin#L2800-L3783`](../../xitdb/dsl.odin#L2800-L3783)):** The Datalog engine inspects bound variables in pattern clauses, automatically selecting `Sorted_Map` (`indices/<index>`) range iterators for prefix-bound lookups and falling back to full collection scans only when unbound.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Comptime Struct Marshaling & Pull Projection in Zig:** Zig's `@typeInfo(T)` comptime reflection maps naturally to Odin's runtime `type_info_of(T)` in `marshal`/`unmarshal` (`Layer 3`) and could be layered on top of `lib.zig` without altering the wire format.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L2221-L2231`](../bench_xitdb.odin#L2221-L2231))

```odin
2221 | 		t1 := time.now()
2222 | 		for i in 0 ..< M {
2223 | 			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
2224 | 			out, u_err := xitdb.unmarshal(Bench_User_DTO, pcur_maybe.?, context.temp_allocator)
2225 | 			assert(u_err == nil && out.age == 31)
2226 | 		}
2227 | 		print_result(Bench_Result{
2228 | 			name    = "DSL Layer 3: Struct unmarshal (N=200)",
2229 | 			ops     = M,
2230 | 			elapsed = time.since(t1),
2231 | 		})
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

### Reached Odin Procedures (`136` procedures across `8` files · `3502` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Linked_Array_List_Init`, `Linked_Array_List_Get`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 15 | [`xitdb/dsl.odin#L410-L424`](../../xitdb/dsl.odin#L410-L424) |
| `xitdb/dsl.odin` | `unmarshal` | **Entry Point** (`depth 0`) | 4 | [`xitdb/dsl.odin#L1519-L1522`](../../xitdb/dsl.odin#L1519-L1522) |
| `xitdb/dsl.odin` | `parse_selector` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L122-L152`](../../xitdb/dsl.odin#L122-L152) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `select_cursor`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `select_cursor`, `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`) | 91 | [`xitdb/dsl.odin#L317-L407`](../../xitdb/dsl.odin#L317-L407) |
| `xitdb/dsl.odin` | `unmarshal_into` | `depth 1` (from `unmarshal`) | 107 | [`xitdb/dsl.odin#L1524-L1630`](../../xitdb/dsl.odin#L1524-L1630) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 2` (from `parse_selector`) | 107 | [`xitdb/dsl.odin#L154-L260`](../../xitdb/dsl.odin#L154-L260) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`, `read_steps_cursor`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 2` (from `read_steps_cursor`, `unmarshal_into`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 2` (from `read_steps_cursor`, `unmarshal_into`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L247-L255`](../../xitdb/collections.odin#L247-L255) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | `depth 2` (from `read_steps_cursor`) | 3 | [`xitdb/collections.odin#L133-L135`](../../xitdb/collections.odin#L133-L135) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L500-L508`](../../xitdb/collections.odin#L500-L508) |
| `xitdb/collections.odin` | `hash_set_get_cursor` | `depth 2` (from `read_steps_cursor`) | 5 | [`xitdb/collections.odin#L562-L566`](../../xitdb/collections.odin#L562-L566) |
| `xitdb/collections.odin` | `read_counted_hash_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L517-L525`](../../xitdb/collections.odin#L517-L525) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L803-L811`](../../xitdb/collections.odin#L803-L811) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 2` (from `unmarshal_into`) | 4 | [`xitdb/cursor.odin#L63-L66`](../../xitdb/cursor.odin#L63-L66) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 2` (from `unmarshal_into`) | 7 | [`xitdb/cursor.odin#L211-L217`](../../xitdb/cursor.odin#L211-L217) |
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 2` (from `unmarshal_into`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/dsl.odin` | `_assign_signed_int` | `depth 2` (from `unmarshal_into`) | 15 | [`xitdb/dsl.odin#L1632-L1646`](../../xitdb/dsl.odin#L1632-L1646) |
| `xitdb/dsl.odin` | `_assign_unsigned_int` | `depth 2` (from `unmarshal_into`) | 15 | [`xitdb/dsl.odin#L1648-L1662`](../../xitdb/dsl.odin#L1648-L1662) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 2` (from `unmarshal_into`) | 7 | [`xitdb/cursor.odin#L219-L225`](../../xitdb/cursor.odin#L219-L225) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 2` (from `unmarshal_into`) | 4 | [`xitdb/cursor.odin#L235-L238`](../../xitdb/cursor.odin#L235-L238) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 2` (from `unmarshal_into`, `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L227-L233`](../../xitdb/cursor.odin#L227-L233) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 2` (from `unmarshal_into`) | 43 | [`xitdb/cursor.odin#L723-L765`](../../xitdb/cursor.odin#L723-L765) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 2` (from `unmarshal_into`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 2` (from `unmarshal_into`) | 19 | [`xitdb/cursor.odin#L365-L383`](../../xitdb/cursor.odin#L365-L383) |
| `xitdb/dsl.odin` | `_parse_field_tag` | `depth 2` (from `unmarshal_into`) | 42 | [`xitdb/dsl.odin#L1301-L1342`](../../xitdb/dsl.odin#L1301-L1342) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 3` (from `parse_steps`) | 33 | [`xitdb/dsl.odin#L262-L294`](../../xitdb/dsl.odin#L262-L294) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 3` (from `parse_steps`, `_parse_step_ident_or_bracket`) | 19 | [`xitdb/dsl.odin#L296-L314`](../../xitdb/dsl.odin#L296-L314) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_read_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 3` (from `hash_map_get_cursor`, `hash_set_get_cursor`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 3` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L554-L556`](../../xitdb/collections.odin#L554-L556) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 3` (from `cursor_read_bytes`) | 56 | [`xitdb/cursor.odin#L240-L295`](../../xitdb/cursor.odin#L240-L295) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 3` (from `cursor_iterator`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_iterator`, `cursor_read_kv_pair`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `cursor_iterator`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 3` (from `cursor_iterator`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 3` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `cursor_iterator`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 3` (from `cursor_iterator`, `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 3` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 3` (from `cursor_read_kv_pair`, `database_kv_key_position`, `sorted_target_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 3` (from `cursor_read_kv_pair`, `read_kv_pair`) | 35 | [`xitdb/types.odin#L1149-L1183`](../../xitdb/types.odin#L1149-L1183) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 3` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L537-L542`](../../xitdb/database.odin#L537-L542) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 3` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L544-L549`](../../xitdb/database.odin#L544-L549) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`, `decode_kv_pair`, `read_map_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_empty` | `depth 4` (from `read_slot_pointer`, `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 4` (from `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/database.odin` | `init_tag` | `depth 4` (from `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 4` (from `read_slot_pointer`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 4` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `read_slot_pointer`, `read_array_list_slot`, `sorted_target_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 5` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1107-L1111`](../../xitdb/btree.odin#L1107-L1111) |
| `xitdb/core.odin` | `core_length` | `depth 5` (from `_exec_path_part`, `_database_truncate_with_header`, `database_commit_root`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/core.odin` | `core_write_all` | `depth 5` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/btree.odin` | `sorted_get` | `depth 5` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 5` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/btree.odin` | `sorted_put` | `depth 5` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1654-L2027`](../../xitdb/btree.odin#L1654-L2027) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2179-L2190`](../../xitdb/btree.odin#L2179-L2190) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 5` (from `_exec_path_part`) | 79 | [`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181) |
| `xitdb/btree.odin` | `btree_get_for_write` | `depth 5` (from `_exec_path_part`) | 73 | [`xitdb/btree.odin#L432-L504`](../../xitdb/btree.odin#L432-L504) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 5` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 5` (from `_exec_path_part`, `btree_get_for_write`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 4` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/core.odin` | `core_write_long` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/core.odin` | `core_read_long` | `depth 5` (from `_exec_path_part`, `cursor_read_bytes_object`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 4` (from `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `_init_btree_iter_level`, `root_header_from_bytes`, `core_read_slot_raw`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 4` (from `decode_kv_pair`, `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 4` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1130-L1139`](../../xitdb/types.odin#L1130-L1139) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `database_kv_key_position`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 5` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 5` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/core.odin` | `core_set_length` | `depth 5` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/core.odin` | `core_sync` | `depth 5` (from `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `core_write_slot`, `read_array_list_slot`, `sorted_put`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 5` (from `core_read_slot_raw`, `sorted_get`, `sorted_put`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 5` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 5` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 5` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 6` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1067-L1105`](../../xitdb/btree.odin#L1067-L1105) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 6` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 6` (from `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`, `read_map_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `sorted_get`, `read_btree_slot`, `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 6` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 6` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 6` (from `sorted_put`, `btree_get_for_write`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 6` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1591-L1597`](../../xitdb/btree.odin#L1591-L1597) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 6` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1121-L1127`](../../xitdb/btree.odin#L1121-L1127) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 6` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1143-L1148`](../../xitdb/btree.odin#L1143-L1148) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 6` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1599-L1652`](../../xitdb/btree.odin#L1599-L1652) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 6` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1113-L1119`](../../xitdb/btree.odin#L1113-L1119) |
| `xitdb/core.odin` | `core_write_i64` | `depth 6` (from `sorted_put`, `core_write_long`, `write_sorted_key_and_entry`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 6` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1293-L1302`](../../xitdb/types.odin#L1293-L1302) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 6` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1028-L1065`](../../xitdb/btree.odin#L1028-L1065) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 6` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1213-L1229`](../../xitdb/btree.odin#L1213-L1229) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 6` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1232-L1245`](../../xitdb/btree.odin#L1232-L1245) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 6` (from `btree_get_for_write`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 6` (from `write_btree_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/core.odin` | `core_read_i64` | `depth 6` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 6` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 6` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 6` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `write_kv_pair`, `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 7` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
