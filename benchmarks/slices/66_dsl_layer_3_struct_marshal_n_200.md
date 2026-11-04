# #66. `DSL Layer 3: Struct marshal (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2183-L2219`)](../bench_xitdb.odin#L2183-L2219)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **3,978** | 3,987.2 ± 46.3 | 1.2% | 4,044.8 | 251,383 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2183-L2219`](../bench_xitdb.odin#L2183-L2219))

```odin
2183 | 	// 3. Layer 3: Odin Struct Reflection `marshal` & `unmarshal` + Datomic `pull`
2184 | 	{
2185 | 		dto := Bench_User_DTO{
2186 | 			username = "alice",
2187 | 			dept     = "eng",
2188 | 			age      = 31,
2189 | 			bio      = "# Principal Systems Engineer",
2190 | 			todos    = {"Design DSL", "Optimize B+Tree pushdown", "Write benchmarks"},
2191 | 			tags     = {"odin", "xitdb", "datalog"},
2192 | 		}
2193 | 		M :: 200
2194 | 		t0 := time.now()
2195 | 		tx := xitdb.tx_init(&db, base_moment = -1, allocator = context.temp_allocator)
2196 | 		Swap_Ctx :: struct {
2197 | 			dto:   ^Bench_User_DTO,
2198 | 			count: int,
2199 | 		}
2200 | 		sctx := Swap_Ctx{dto = &dto, count = M}
2201 | 		xitdb.tx_with_cursor(&tx, proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
2202 | 			sc := (^Swap_Ctx)(user_data)
2203 | 			m := xitdb.write_hash_map_init(cursor^) or_return
2204 | 			profiles_cur := xitdb.hash_map_put_cursor(&m, "profiles") or_return
2205 | 			profiles := xitdb.write_hash_map_init(profiles_cur) or_return
2206 | 			for i in 0 ..< sc.count {
2207 | 				k := fmt.tprintf("p%03d", i)
2208 | 				pcur := xitdb.hash_map_put_cursor(&profiles, k) or_return
2209 | 				xitdb.marshal(&pcur, sc.dto^) or_return
2210 | 			}
2211 | 			return nil
2212 | 		}, &sctx)
2213 | 		rep, err := xitdb.tx_commit(&tx)
2214 | 		assert(err == nil)
2215 | 		print_result(Bench_Result{
2216 | 			name    = "DSL Layer 3: Struct marshal (N=200)",
2217 | 			ops     = M,
2218 | 			elapsed = time.since(t0),
2219 | 		})
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

### Reached Odin Procedures (`170` procedures across `8` files · `4031` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Array_List_Slice`, `Linked_Array_List_Init`, `Linked_Array_List_Append`, `Linked_Array_List_Slice`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `tx_init` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L627-L637`](../../xitdb/dsl.odin#L627-L637) |
| `xitdb/dsl.odin` | `tx_with_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/dsl.odin#L754-L756`](../../xitdb/dsl.odin#L754-L756) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L423-L428`](../../xitdb/collections.odin#L423-L428) |
| `xitdb/dsl.odin` | `marshal` | **Entry Point** (`depth 0`) | 92 | [`xitdb/dsl.odin#L1345-L1436`](../../xitdb/dsl.odin#L1345-L1436) |
| `xitdb/dsl.odin` | `tx_commit` | **Entry Point** (`depth 0`) | 58 | [`xitdb/dsl.odin#L1035-L1092`](../../xitdb/dsl.odin#L1035-L1092) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_by_hash`, `hash_map_put_cursor_by_hash`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`, `tx_commit`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_get_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 1` (from `marshal`) | 5 | [`xitdb/cursor.odin#L186-L190`](../../xitdb/cursor.odin#L186-L190) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `marshal`, `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_slice` | `depth 1` (from `marshal`) | 4 | [`xitdb/collections.odin#L90-L93`](../../xitdb/collections.odin#L90-L93) |
| `xitdb/collections.odin` | `array_list_append_cursor` | `depth 1` (from `marshal`) | 3 | [`xitdb/collections.odin#L77-L79`](../../xitdb/collections.odin#L77-L79) |
| `xitdb/dsl.odin` | `_parse_field_tag` | `depth 1` (from `marshal`) | 42 | [`xitdb/dsl.odin#L1301-L1342`](../../xitdb/dsl.odin#L1301-L1342) |
| `xitdb/dsl.odin` | `_marshal_struct_field` | `depth 1` (from `marshal`) | 79 | [`xitdb/dsl.odin#L1438-L1516`](../../xitdb/dsl.odin#L1438-L1516) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/dsl.odin` | `diff_changes_destroy` | `depth 1` (from `tx_commit`) | 10 | [`xitdb/dsl.odin#L655-L664`](../../xitdb/dsl.odin#L655-L664) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path_slot`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `read_array_list_init`, `write_counted_hash_map_init`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 2` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `hash_map_put` | `depth 2` (from `_marshal_struct_field`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/types.odin` | `new_tagged_string` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/types.odin#L1370-L1372`](../../xitdb/types.odin#L1370-L1372) |
| `xitdb/collections.odin` | `write_linked_array_list_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L118-L123`](../../xitdb/collections.odin#L118-L123) |
| `xitdb/collections.odin` | `linked_array_list_slice` | `depth 2` (from `_marshal_struct_field`) | 4 | [`xitdb/collections.odin#L182-L185`](../../xitdb/collections.odin#L182-L185) |
| `xitdb/collections.odin` | `linked_array_list_append_cursor` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L169-L171`](../../xitdb/collections.odin#L169-L171) |
| `xitdb/collections.odin` | `write_hash_set_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L510-L515`](../../xitdb/collections.odin#L510-L515) |
| `xitdb/collections.odin` | `hash_set_put` | `depth 2` (from `_marshal_struct_field`) | 5 | [`xitdb/collections.odin#L611-L615`](../../xitdb/collections.odin#L611-L615) |
| `xitdb/collections.odin` | `write_sorted_set_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L813-L818`](../../xitdb/collections.odin#L813-L818) |
| `xitdb/collections.odin` | `sorted_set_put` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L885-L887`](../../xitdb/collections.odin#L885-L887) |
| `xitdb/collections.odin` | `write_sorted_map_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L679-L684`](../../xitdb/collections.odin#L679-L684) |
| `xitdb/collections.odin` | `sorted_map_put_cursor` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L793-L795`](../../xitdb/collections.odin#L793-L795) |
| `xitdb/collections.odin` | `write_counted_hash_map_init` | `depth 2` (from `_marshal_struct_field`) | 14 | [`xitdb/collections.odin#L257-L270`](../../xitdb/collections.odin#L257-L270) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`) | 39 | [`xitdb/cursor.odin#L395-L433`](../../xitdb/cursor.odin#L395-L433) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_reload_slot`, `read_slot_pointer`, `_exec_path_part`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slice`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L564-L568`](../../xitdb/core.odin#L564-L568) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `cursor_read_path_slot`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 15 | [`xitdb/core.odin#L570-L584`](../../xitdb/core.odin#L570-L584) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L539-L562`](../../xitdb/core.odin#L539-L562) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `cursor_count`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/hamt.odin` | `read_array_list_slice` | `depth 4` (from `_exec_path_part`) | 28 | [`xitdb/hamt.odin#L457-L484`](../../xitdb/hamt.odin#L457-L484) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 52 | [`xitdb/core.odin#L376-L427`](../../xitdb/core.odin#L376-L427) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 7 | [`xitdb/core.odin#L484-L490`](../../xitdb/core.odin#L484-L490) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L492-L497`](../../xitdb/core.odin#L492-L497) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_committed_size_with_header`, `_database_truncate_with_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slice`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 3` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 3` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_new_root`, `btree_split_right`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/btree.odin` | `btree_new_root` | `depth 4` (from `_exec_path_part`, `btree_split_left`, `btree_subtree`) | 3 | [`xitdb/btree.odin#L99-L101`](../../xitdb/btree.odin#L99-L101) |
| `xitdb/btree.odin` | `btree_split_right` | `depth 4` (from `_exec_path_part`) | 28 | [`xitdb/btree.odin#L937-L964`](../../xitdb/btree.odin#L937-L964) |
| `xitdb/btree.odin` | `btree_split_left` | `depth 4` (from `_exec_path_part`) | 34 | [`xitdb/btree.odin#L966-L999`](../../xitdb/btree.odin#L966-L999) |
| `xitdb/btree.odin` | `btree_insert` | `depth 4` (from `_exec_path_part`) | 244 | [`xitdb/btree.odin#L191-L434`](../../xitdb/btree.odin#L191-L434) |
| `xitdb/btree.odin` | `btree_grow_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L436-L438`](../../xitdb/btree.odin#L436-L438) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 3` (from `write_hash_set_init`) | 9 | [`xitdb/collections.odin#L500-L508`](../../xitdb/collections.odin#L500-L508) |
| `xitdb/collections.odin` | `hash_set_put_by_hash` | `depth 3` (from `hash_set_put`) | 7 | [`xitdb/collections.odin#L586-L592`](../../xitdb/collections.odin#L586-L592) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 3` (from `write_sorted_set_init`) | 9 | [`xitdb/collections.odin#L803-L811`](../../xitdb/collections.odin#L803-L811) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1114-L1118`](../../xitdb/btree.odin#L1114-L1118) |
| `xitdb/collections.odin` | `sorted_set_put_by_bytes` | `depth 3` (from `sorted_set_put`) | 4 | [`xitdb/collections.odin#L880-L883`](../../xitdb/collections.odin#L880-L883) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 3` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_put_cursor_by_bytes` | `depth 3` (from `sorted_map_put_cursor`) | 3 | [`xitdb/collections.odin#L774-L776`](../../xitdb/collections.odin#L774-L776) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `read_map_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/core.odin` | `_memory_resize` | `depth 4` (from `core_write_slot`, `core_write_all`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `read_map_slot`, `read_array_list_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slice`, `read_map_slot`, `read_array_list_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `sorted_get`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L431-L447`](../../xitdb/core.odin#L431-L447) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L499-L522`](../../xitdb/core.odin#L499-L522) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`, `btree_insert`, `sorted_put`) | 14 | [`xitdb/core.odin#L524-L537`](../../xitdb/core.odin#L524-L537) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`, `_exec_path_part`, `_try_encode_inline_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1396-L1449`](../../xitdb/database.odin#L1396-L1449) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1383-L1394`](../../xitdb/database.odin#L1383-L1394) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`, `_try_encode_inline_data`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`, `btree_write_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_split_right`, `btree_split_left`, `btree_insert`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `btree_subtree` | `depth 5` (from `btree_split_right`, `btree_split_left`) | 14 | [`xitdb/btree.odin#L922-L935`](../../xitdb/btree.odin#L922-L935) |
| `xitdb/btree.odin` | `btree_join` | `depth 5` (from `btree_split_right`, `btree_split_left`) | 15 | [`xitdb/btree.odin#L906-L920`](../../xitdb/btree.odin#L906-L920) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `btree_insert`, `btree_write_node`, `sorted_put`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 5` (from `btree_insert`) | 7 | [`xitdb/btree.odin#L91-L97`](../../xitdb/btree.odin#L91-L97) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_insert`, `btree_assemble_branch`) | 10 | [`xitdb/types.odin#L1249-L1258`](../../xitdb/types.odin#L1249-L1258) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_grow_root`, `btree_join`) | 11 | [`xitdb/btree.odin#L775-L785`](../../xitdb/btree.odin#L775-L785) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1074-L1112`](../../xitdb/btree.odin#L1074-L1112) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 115 | [`xitdb/btree.odin#L1254-L1368`](../../xitdb/btree.odin#L1254-L1368) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2205-L2222`](../../xitdb/btree.odin#L2205-L2222) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1673-L2046`](../../xitdb/btree.odin#L1673-L2046) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2192-L2203`](../../xitdb/btree.odin#L2192-L2203) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`, `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `read_btree_node`, `sorted_get`, `sorted_put`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `btree_assemble_branch` | `depth 6` (from `btree_subtree`, `btree_merge_nodes`, `btree_join_right`) | 23 | [`xitdb/btree.odin#L808-L830`](../../xitdb/btree.odin#L808-L830) |
| `xitdb/btree.odin` | `btree_height` | `depth 6` (from `btree_join`) | 19 | [`xitdb/btree.odin#L755-L773`](../../xitdb/btree.odin#L755-L773) |
| `xitdb/btree.odin` | `btree_merge_nodes` | `depth 6` (from `btree_join`, `btree_join_right`, `btree_join_left`) | 16 | [`xitdb/btree.odin#L832-L847`](../../xitdb/btree.odin#L832-L847) |
| `xitdb/btree.odin` | `btree_join_right` | `depth 6` (from `btree_join`) | 26 | [`xitdb/btree.odin#L849-L874`](../../xitdb/btree.odin#L849-L874) |
| `xitdb/btree.odin` | `btree_join_left` | `depth 6` (from `btree_join`) | 29 | [`xitdb/btree.odin#L876-L904`](../../xitdb/btree.odin#L876-L904) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1136-L1148`](../../xitdb/btree.odin#L1136-L1148) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1157-L1216`](../../xitdb/btree.odin#L1157-L1216) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1610-L1616`](../../xitdb/btree.odin#L1610-L1616) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1128-L1134`](../../xitdb/btree.odin#L1128-L1134) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1150-L1155`](../../xitdb/btree.odin#L1150-L1155) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1618-L1671`](../../xitdb/btree.odin#L1618-L1671) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1120-L1126`](../../xitdb/btree.odin#L1120-L1126) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1299-L1308`](../../xitdb/types.odin#L1299-L1308) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1035-L1072`](../../xitdb/btree.odin#L1035-L1072) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1220-L1236`](../../xitdb/btree.odin#L1220-L1236) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1239-L1252`](../../xitdb/btree.odin#L1239-L1252) |
| `xitdb/btree.odin` | `btree_assemble_leaf` | `depth 7` (from `btree_merge_nodes`) | 20 | [`xitdb/btree.odin#L787-L806`](../../xitdb/btree.odin#L787-L806) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1155-L1189`](../../xitdb/types.odin#L1155-L1189) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1136-L1145`](../../xitdb/types.odin#L1136-L1145) |
