# #66. `DSL Layer 3: Struct marshal (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2195-L2231`)](../bench_xitdb.odin#L2195-L2231)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **6,377** | 6,496.2 ± 204.1 | 3.1% | 6,775.8 | 156,814 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2195-L2231`](../bench_xitdb.odin#L2195-L2231))

```odin
2195 | 	// 3. Layer 3: Odin Struct Reflection `marshal` & `unmarshal` + Datomic `pull`
2196 | 	{
2197 | 		dto := Bench_User_DTO{
2198 | 			username = "alice",
2199 | 			dept     = "eng",
2200 | 			age      = 31,
2201 | 			bio      = "# Principal Systems Engineer",
2202 | 			todos    = {"Design DSL", "Optimize B+Tree pushdown", "Write benchmarks"},
2203 | 			tags     = {"odin", "xitdb", "datalog"},
2204 | 		}
2205 | 		M :: 200
2206 | 		t0 := time.now()
2207 | 		tx := xitdb.tx_init(&db, base_moment = -1, allocator = context.temp_allocator)
2208 | 		Swap_Ctx :: struct {
2209 | 			dto:   ^Bench_User_DTO,
2210 | 			count: int,
2211 | 		}
2212 | 		sctx := Swap_Ctx{dto = &dto, count = M}
2213 | 		xitdb.tx_with_cursor(&tx, proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
2214 | 			sc := (^Swap_Ctx)(user_data)
2215 | 			m := xitdb.write_hash_map_init(cursor^) or_return
2216 | 			profiles_cur := xitdb.hash_map_put_cursor(&m, "profiles") or_return
2217 | 			profiles := xitdb.write_hash_map_init(profiles_cur) or_return
2218 | 			for i in 0 ..< sc.count {
2219 | 				k := fmt.tprintf("p%03d", i)
2220 | 				pcur := xitdb.hash_map_put_cursor(&profiles, k) or_return
2221 | 				xitdb.marshal(&pcur, sc.dto^) or_return
2222 | 			}
2223 | 			return nil
2224 | 		}, &sctx)
2225 | 		rep, err := xitdb.tx_commit(&tx)
2226 | 		assert(err == nil)
2227 | 		print_result(Bench_Result{
2228 | 			name    = "DSL Layer 3: Struct marshal (N=200)",
2229 | 			ops     = M,
2230 | 			elapsed = time.since(t0),
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

### Reached Odin Procedures (`180` procedures across `8` files · `4331` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Array_List_Slice`, `Linked_Array_List_Init`, `Linked_Array_List_Append`, `Linked_Array_List_Slice`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `tx_init` | **Entry Point** (`depth 0`) | 12 | [`xitdb/dsl.odin#L905-L916`](../../xitdb/dsl.odin#L905-L916) |
| `xitdb/dsl.odin` | `tx_with_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/dsl.odin#L1053-L1055`](../../xitdb/dsl.odin#L1053-L1055) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L256-L261`](../../xitdb/collections.odin#L256-L261) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L443-L448`](../../xitdb/collections.odin#L443-L448) |
| `xitdb/dsl.odin` | `marshal` | **Entry Point** (`depth 0`) | 92 | [`xitdb/dsl.odin#L1668-L1759`](../../xitdb/dsl.odin#L1668-L1759) |
| `xitdb/dsl.odin` | `tx_commit` | **Entry Point** (`depth 0`) | 63 | [`xitdb/dsl.odin#L1334-L1396`](../../xitdb/dsl.odin#L1334-L1396) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_by_hash`, `hash_map_put_cursor_by_hash`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`, `tx_commit`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_get_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L404-L410`](../../xitdb/collections.odin#L404-L410) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L398-L402`](../../xitdb/collections.odin#L398-L402) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 1` (from `marshal`) | 5 | [`xitdb/cursor.odin#L183-L187`](../../xitdb/cursor.odin#L183-L187) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `marshal`, `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_slice` | `depth 1` (from `marshal`) | 4 | [`xitdb/collections.odin#L98-L101`](../../xitdb/collections.odin#L98-L101) |
| `xitdb/collections.odin` | `array_list_append_cursor` | `depth 1` (from `marshal`) | 3 | [`xitdb/collections.odin#L85-L87`](../../xitdb/collections.odin#L85-L87) |
| `xitdb/dsl.odin` | `_parse_field_tag` | `depth 1` (from `marshal`) | 8 | [`xitdb/dsl.odin#L1658-L1665`](../../xitdb/dsl.odin#L1658-L1665) |
| `xitdb/dsl.odin` | `_marshal_struct_field` | `depth 1` (from `marshal`) | 79 | [`xitdb/dsl.odin#L1761-L1839`](../../xitdb/dsl.odin#L1761-L1839) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L89-L96`](../../xitdb/collections.odin#L89-L96) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path_slot`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `read_array_list_init`, `write_counted_hash_map_init`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 2` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/dsl.odin` | `_parse_raw_tag_val` | `depth 2` (from `_parse_field_tag`) | 50 | [`xitdb/dsl.odin#L1607-L1656`](../../xitdb/dsl.odin#L1607-L1656) |
| `xitdb/collections.odin` | `hash_map_put` | `depth 2` (from `_marshal_struct_field`) | 5 | [`xitdb/collections.odin#L437-L441`](../../xitdb/collections.odin#L437-L441) |
| `xitdb/types.odin` | `new_tagged_string` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/types.odin#L1423-L1425`](../../xitdb/types.odin#L1423-L1425) |
| `xitdb/collections.odin` | `write_linked_array_list_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L126-L131`](../../xitdb/collections.odin#L126-L131) |
| `xitdb/collections.odin` | `linked_array_list_slice` | `depth 2` (from `_marshal_struct_field`) | 4 | [`xitdb/collections.odin#L198-L201`](../../xitdb/collections.odin#L198-L201) |
| `xitdb/collections.odin` | `linked_array_list_append_cursor` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L185-L187`](../../xitdb/collections.odin#L185-L187) |
| `xitdb/collections.odin` | `write_hash_set_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L530-L535`](../../xitdb/collections.odin#L530-L535) |
| `xitdb/collections.odin` | `hash_set_put` | `depth 2` (from `_marshal_struct_field`) | 5 | [`xitdb/collections.odin#L635-L639`](../../xitdb/collections.odin#L635-L639) |
| `xitdb/collections.odin` | `write_sorted_set_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L852-L857`](../../xitdb/collections.odin#L852-L857) |
| `xitdb/collections.odin` | `sorted_set_put` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L939-L941`](../../xitdb/collections.odin#L939-L941) |
| `xitdb/collections.odin` | `write_sorted_map_init` | `depth 2` (from `_marshal_struct_field`) | 6 | [`xitdb/collections.odin#L703-L708`](../../xitdb/collections.odin#L703-L708) |
| `xitdb/collections.odin` | `sorted_map_put_cursor` | `depth 2` (from `_marshal_struct_field`) | 3 | [`xitdb/collections.odin#L832-L834`](../../xitdb/collections.odin#L832-L834) |
| `xitdb/collections.odin` | `write_counted_hash_map_init` | `depth 2` (from `_marshal_struct_field`) | 14 | [`xitdb/collections.odin#L273-L286`](../../xitdb/collections.odin#L273-L286) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`) | 37 | [`xitdb/cursor.odin#L436-L472`](../../xitdb/cursor.odin#L436-L472) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L80-L94`](../../xitdb/cursor.odin#L80-L94) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot`, `read_array_list_slice`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `cursor_read_path_slot`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`, `read_map_slot`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 4` (from `_exec_path_part`, `cursor_count`, `core_read_slot_raw_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`, `read_array_list_slice`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `_database_truncate_with_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 38 | [`xitdb/hamt.odin#L343-L380`](../../xitdb/hamt.odin#L343-L380) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/hamt.odin` | `read_array_list_slice` | `depth 4` (from `_exec_path_part`) | 27 | [`xitdb/hamt.odin#L450-L476`](../../xitdb/hamt.odin#L450-L476) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`, `core_flush`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 3` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L429-L435`](../../xitdb/collections.odin#L429-L435) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 3` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_new_root`, `btree_split_right`) | 5 | [`xitdb/btree.odin#L79-L83`](../../xitdb/btree.odin#L79-L83) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/btree.odin` | `btree_new_root` | `depth 4` (from `_exec_path_part`, `btree_split_left`, `btree_subtree`) | 3 | [`xitdb/btree.odin#L101-L103`](../../xitdb/btree.odin#L101-L103) |
| `xitdb/btree.odin` | `btree_split_right` | `depth 4` (from `_exec_path_part`) | 37 | [`xitdb/btree.odin#L953-L989`](../../xitdb/btree.odin#L953-L989) |
| `xitdb/btree.odin` | `btree_split_left` | `depth 4` (from `_exec_path_part`) | 43 | [`xitdb/btree.odin#L991-L1033`](../../xitdb/btree.odin#L991-L1033) |
| `xitdb/btree.odin` | `btree_insert` | `depth 4` (from `_exec_path_part`) | 255 | [`xitdb/btree.odin#L154-L408`](../../xitdb/btree.odin#L154-L408) |
| `xitdb/btree.odin` | `btree_grow_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L410-L412`](../../xitdb/btree.odin#L410-L412) |
| `xitdb/collections.odin` | `read_hash_set_init` | `depth 3` (from `write_hash_set_init`) | 9 | [`xitdb/collections.odin#L520-L528`](../../xitdb/collections.odin#L520-L528) |
| `xitdb/collections.odin` | `hash_set_put_by_hash` | `depth 3` (from `hash_set_put`) | 7 | [`xitdb/collections.odin#L610-L616`](../../xitdb/collections.odin#L610-L616) |
| `xitdb/collections.odin` | `read_sorted_set_init` | `depth 3` (from `write_sorted_set_init`) | 9 | [`xitdb/collections.odin#L842-L850`](../../xitdb/collections.odin#L842-L850) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1159-L1163`](../../xitdb/btree.odin#L1159-L1163) |
| `xitdb/collections.odin` | `sorted_set_put_by_bytes` | `depth 3` (from `sorted_set_put`) | 4 | [`xitdb/collections.odin#L934-L937`](../../xitdb/collections.odin#L934-L937) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 3` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L693-L701`](../../xitdb/collections.odin#L693-L701) |
| `xitdb/collections.odin` | `sorted_map_put_cursor_by_bytes` | `depth 3` (from `sorted_map_put_cursor`) | 3 | [`xitdb/collections.odin#L813-L815`](../../xitdb/collections.odin#L813-L815) |
| `xitdb/types.odin` | `check_long` | `depth 3` (from `cursor_count`) | 6 | [`xitdb/types.odin#L1482-L1487`](../../xitdb/types.odin#L1482-L1487) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 3` (from `database_read_root_header`, `database_write_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 3` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `core_read_slot_at`, `read_map_slot`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/core.odin` | `_memory_resize` | `depth 4` (from `core_write_slot`, `core_write_all`, `_overlay_write_at`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `read_array_list_slot`, `read_array_list_slot_append`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `read_map_slot`, `kv_pair_read_buf_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/core.odin` | `core_read_at` | `depth 5` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`, `read_map_slot`, `read_array_list_slice`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/core.odin` | `_overlay_length` | `depth 5` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 5` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`, `btree_insert`, `database_write_root_header`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`, `_exec_path_part`, `_try_encode_inline_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1420-L1473`](../../xitdb/database.odin#L1420-L1473) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1407-L1418`](../../xitdb/database.odin#L1407-L1418) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`, `_try_encode_inline_data`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`, `btree_write_node`) | 33 | [`xitdb/btree.odin#L45-L77`](../../xitdb/btree.odin#L45-L77) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_split_right`, `btree_split_left`, `btree_insert`) | 36 | [`xitdb/btree.odin#L8-L43`](../../xitdb/btree.odin#L8-L43) |
| `xitdb/btree.odin` | `btree_subtree` | `depth 5` (from `btree_split_right`, `btree_split_left`) | 14 | [`xitdb/btree.odin#L938-L951`](../../xitdb/btree.odin#L938-L951) |
| `xitdb/btree.odin` | `btree_join` | `depth 5` (from `btree_split_right`, `btree_split_left`) | 15 | [`xitdb/btree.odin#L922-L936`](../../xitdb/btree.odin#L922-L936) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `btree_insert`, `btree_write_node`, `sorted_put`) | 7 | [`xitdb/btree.odin#L85-L91`](../../xitdb/btree.odin#L85-L91) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 5` (from `btree_insert`) | 7 | [`xitdb/btree.odin#L93-L99`](../../xitdb/btree.odin#L93-L99) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_insert`, `btree_assemble_branch`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_grow_root`, `btree_join`) | 11 | [`xitdb/btree.odin#L773-L783`](../../xitdb/btree.odin#L773-L783) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1119-L1157`](../../xitdb/btree.odin#L1119-L1157) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 61 | [`xitdb/btree.odin#L1315-L1375`](../../xitdb/btree.odin#L1315-L1375) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 17 | [`xitdb/btree.odin#L2087-L2103`](../../xitdb/btree.odin#L2087-L2103) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 384 | [`xitdb/btree.odin#L1536-L1919`](../../xitdb/btree.odin#L1536-L1919) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2074-L2085`](../../xitdb/btree.odin#L2074-L2085) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 5` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `core_flush` | `depth 5` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 6` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_overlay_page` | `depth 6` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 6` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf_at`, `decode_kv_pair_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 6` (from `read_btree_node`, `sorted_get`, `read_sorted_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `read_btree_node`, `sorted_get`, `sorted_put`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/btree.odin` | `btree_assemble_branch` | `depth 6` (from `btree_subtree`, `btree_merge_nodes`, `btree_join_right`) | 23 | [`xitdb/btree.odin#L806-L828`](../../xitdb/btree.odin#L806-L828) |
| `xitdb/btree.odin` | `btree_height` | `depth 6` (from `btree_join`) | 24 | [`xitdb/btree.odin#L748-L771`](../../xitdb/btree.odin#L748-L771) |
| `xitdb/btree.odin` | `btree_merge_nodes` | `depth 6` (from `btree_join`, `btree_join_right`, `btree_join_left`) | 16 | [`xitdb/btree.odin#L830-L845`](../../xitdb/btree.odin#L830-L845) |
| `xitdb/btree.odin` | `btree_join_right` | `depth 6` (from `btree_join`) | 35 | [`xitdb/btree.odin#L847-L881`](../../xitdb/btree.odin#L847-L881) |
| `xitdb/btree.odin` | `btree_join_left` | `depth 6` (from `btree_join`) | 38 | [`xitdb/btree.odin#L883-L920`](../../xitdb/btree.odin#L883-L920) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 6 | [`xitdb/btree.odin#L1180-L1185`](../../xitdb/btree.odin#L1180-L1185) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 84 | [`xitdb/btree.odin#L1194-L1277`](../../xitdb/btree.odin#L1194-L1277) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1388-L1390`](../../xitdb/types.odin#L1388-L1390) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 5` (from `sorted_put`, `core_read_block_at`, `compare_key`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1473-L1479`](../../xitdb/btree.odin#L1473-L1479) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 6 | [`xitdb/btree.odin#L1173-L1178`](../../xitdb/btree.odin#L1173-L1178) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1187-L1192`](../../xitdb/btree.odin#L1187-L1192) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1481-L1534`](../../xitdb/btree.odin#L1481-L1534) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1165-L1171`](../../xitdb/btree.odin#L1165-L1171) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 40 | [`xitdb/btree.odin#L1078-L1117`](../../xitdb/btree.odin#L1078-L1117) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1281-L1297`](../../xitdb/btree.odin#L1281-L1297) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1300-L1313`](../../xitdb/btree.odin#L1300-L1313) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 6` (from `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/btree.odin` | `btree_assemble_leaf` | `depth 7` (from `btree_merge_nodes`) | 20 | [`xitdb/btree.odin#L785-L804`](../../xitdb/btree.odin#L785-L804) |
| `xitdb/types.odin` | `decode_kv_pair_at` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1215-L1249`](../../xitdb/types.odin#L1215-L1249) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair_at`) | 10 | [`xitdb/types.odin#L1145-L1154`](../../xitdb/types.odin#L1145-L1154) |
