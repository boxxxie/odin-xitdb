# #74. `DSL Layer 2: Secondary Index Evict+Update (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2340-L2357`)](../bench_xitdb.odin#L2340-L2357)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **2,985** | 3,032.0 ± 118.6 | 3.9% | 3,195.4 | 335,008 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2340-L2357`](../bench_xitdb.odin#L2340-L2357))

```odin
2340 | 	// 6. Layer 2 & 3/4: Secondary Index Stale-Key Eviction (`tx_index_on` update) & Cyclic Graph `pull` + `diff`
2341 | 	{
2342 | 		U :: 200
2343 | 		t0 := time.now()
2344 | 		tx_evict := xitdb.tx_init(&db, base_moment = -1, track_changes = false, allocator = context.temp_allocator)
2345 | 		xitdb.tx_index_on(&tx_evict, "users", "username", "username->id")
2346 | 		for i in 0 ..< U {
2347 | 			id_str := fmt.tprintf("u%04d", i)
2348 | 			new_uname := fmt.tprintf("renamed_%04d", i)
2349 | 			_ = xitdb.tx_put(&tx_evict, fmt.tprintf(".users[%q].username", id_str), new_uname)
2350 | 		}
2351 | 		_, ev_err := xitdb.tx_commit(&tx_evict)
2352 | 		assert(ev_err == nil)
2353 | 		print_result(Bench_Result{
2354 | 			name    = "DSL Layer 2: Secondary Index Evict+Update (N=200)",
2355 | 			ops     = U,
2356 | 			elapsed = time.since(t0),
2357 | 		})
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

### Reached Odin Procedures (`98` procedures across `7` files · `2021` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `tx_init` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L627-L637`](../../xitdb/dsl.odin#L627-L637) |
| `xitdb/dsl.odin` | `tx_index_on` | **Entry Point** (`depth 0`) | 7 | [`xitdb/dsl.odin#L684-L690`](../../xitdb/dsl.odin#L684-L690) |
| `xitdb/dsl.odin` | `tx_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/dsl.odin#L698-L702`](../../xitdb/dsl.odin#L698-L702) |
| `xitdb/dsl.odin` | `tx_commit` | **Entry Point** (`depth 0`) | 58 | [`xitdb/dsl.odin#L1035-L1092`](../../xitdb/dsl.odin#L1035-L1092) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 1` (from `tx_put`) | 107 | [`xitdb/dsl.odin#L154-L260`](../../xitdb/dsl.odin#L154-L260) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/dsl.odin` | `diff_changes_destroy` | `depth 1` (from `tx_commit`) | 10 | [`xitdb/dsl.odin#L655-L664`](../../xitdb/dsl.odin#L655-L664) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `tx_commit`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 2` (from `parse_steps`) | 33 | [`xitdb/dsl.odin#L262-L294`](../../xitdb/dsl.odin#L262-L294) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 2` (from `parse_steps`, `_parse_step_ident_or_bracket`) | 19 | [`xitdb/dsl.odin#L296-L314`](../../xitdb/dsl.odin#L296-L314) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 2` (from `write_array_list_init`, `array_list_append_context`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 2` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`) | 39 | [`xitdb/cursor.odin#L395-L433`](../../xitdb/cursor.odin#L395-L433) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `read_array_list_init`, `cursor_count`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 3` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_write_path`, `cursor_resolved`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 3` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 3` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 3` (from `cursor_write_path`, `cursor_read_path_slot`, `cursor_read_path`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 3` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/core.odin` | `core_sync` | `depth 3` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 3` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_count`, `database_read_root_header`, `cursor_reload_slot`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `cursor_count`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 3` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `cursor_count`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/core.odin` | `core_read_long` | `depth 3` (from `cursor_count`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L488-L494`](../../xitdb/core.odin#L488-L494) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `cursor_read_path_slot`, `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 3` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/core.odin` | `core_length` | `depth 3` (from `_database_committed_size_with_header`, `_exec_path_part`, `_database_truncate_with_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 4` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 4` (from `cursor_reload_slot`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L568-L572`](../../xitdb/core.odin#L568-L572) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 4` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 4` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 4` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 15 | [`xitdb/core.odin#L574-L588`](../../xitdb/core.odin#L574-L588) |
| `xitdb/database.odin` | `init_part_for` | `depth 4` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L543-L566`](../../xitdb/core.odin#L543-L566) |
| `xitdb/database.odin` | `_random_u64` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/database.odin` | `database_commit_root` | `depth 4` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 4` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/core.odin` | `core_write_all` | `depth 5` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 5` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 5` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 5` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 5` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/core.odin` | `core_write_long` | `depth 5` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L496-L501`](../../xitdb/core.odin#L496-L501) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 5` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 5` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 5` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 4` (from `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/core.odin` | `core_read_i64` | `depth 4` (from `core_read_long`) | 24 | [`xitdb/core.odin#L503-L526`](../../xitdb/core.odin#L503-L526) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 5` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 5` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/core.odin` | `_memory_resize` | `depth 5` (from `core_write_slot`, `core_write_all`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `core_write_slot`, `read_array_list_slot_append`, `read_array_list_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 5` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 5` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 5` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 5` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 6` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `core_write_i64` | `depth 6` (from `core_write_long`) | 14 | [`xitdb/core.odin#L528-L541`](../../xitdb/core.odin#L528-L541) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 6` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/types.odin` | `slot_with_full` | `depth 6` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`, `read_map_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/database.odin` | `database_check_hash` | `depth 6` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 6` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 6` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/core.odin` | `core_slice_at` | `depth 6` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L435-L451`](../../xitdb/core.odin#L435-L451) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 6` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 6` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 7` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 7` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
