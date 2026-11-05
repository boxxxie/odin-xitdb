# #75. `DSL Layer 3/4: Cyclic Graph pull + diff (N=200)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Idiomatic Zig Optimization Guide (Overview)**](../zig-guide/README.md) · [Odin Harness (`bench_xitdb.odin#L2360-L2402`)](../bench_xitdb.odin#L2360-L2402)

## 1. Statistical Performance Summary (Odin 5-Layer DSL)

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Odin** (`-o:speed -microarch:native`) | **7,008** | 6,977.4 ± 51.7 | 0.7% | 7,013.8 | 142,694 | - |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2360-L2402`](../bench_xitdb.odin#L2360-L2402))

```odin
2360 | 		// Seed cyclic Slot references in a dedicated moment and benchmark cycle-safe `pull` + `diff_moments`
2361 | 		tx_cyc := xitdb.tx_init(&db, base_moment = -1, track_changes = true, allocator = context.temp_allocator)
2362 | 		xitdb.tx_with_cursor(&tx_cyc, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
2363 | 			moment := xitdb.write_hash_map_init(cursor^) or_return
2364 | 			m_slot := xitdb.hash_map_slot(moment.read_hash_map) or_return
2365 | 			xitdb.hash_map_put(&moment, "self", m_slot) or_return
2366 | 
2367 | 			ma_cur := xitdb.hash_map_put_cursor(&moment, "node_a") or_return
2368 | 			ma := xitdb.write_hash_map_init(ma_cur) or_return
2369 | 			xitdb.hash_map_put(&ma, "label", "A") or_return
2370 | 
2371 | 			mb_cur := xitdb.hash_map_put_cursor(&moment, "node_b") or_return
2372 | 			mb := xitdb.write_hash_map_init(mb_cur) or_return
2373 | 			xitdb.hash_map_put(&mb, "label", "B") or_return
2374 | 
2375 | 			mb_slot := xitdb.hash_map_slot(mb.read_hash_map) or_return
2376 | 			xitdb.hash_map_put(&ma, "peer", mb_slot) or_return
2377 | 			ma_slot := xitdb.hash_map_slot(ma.read_hash_map) or_return
2378 | 			xitdb.hash_map_put(&mb, "peer", ma_slot) or_return
2379 | 			return nil
2380 | 		})
2381 | 		rep_cyc, cyc_err := xitdb.tx_commit(&tx_cyc)
2382 | 		assert(cyc_err == nil)
2383 | 
2384 | 		tx_cyc2 := xitdb.tx_init(&db, base_moment = -1, track_changes = false, allocator = context.temp_allocator)
2385 | 		_ = xitdb.tx_put(&tx_cyc2, ".node_a.label", "A_v2")
2386 | 		rep_cyc2, cyc2_err := xitdb.tx_commit(&tx_cyc2)
2387 | 		assert(cyc2_err == nil)
2388 | 
2389 | 		C :: 200
2390 | 		node_a_cur, _ := xitdb.select_cursor(&db, "@-1.node_a")
2391 | 		t1 := time.now()
2392 | 		for _ in 0 ..< C {
2393 | 			pv, p_err := xitdb.pull(node_a_cur.?, "*", context.temp_allocator)
2394 | 			assert(p_err == nil && pv != nil)
2395 | 			diffs, d_err := xitdb.diff_moments(&db, rep_cyc.moment_index, rep_cyc2.moment_index, false, context.temp_allocator)
2396 | 			assert(d_err == nil && len(diffs) == 1)
2397 | 		}
2398 | 		print_result(Bench_Result{
2399 | 			name    = "DSL Layer 3/4: Cyclic Graph pull + diff (N=200)",
2400 | 			ops     = C,
2401 | 			elapsed = time.since(t1),
2402 | 		})
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

### Reached Odin Procedures (`185` procedures across `8` files · `4538` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Get`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/dsl.odin` | `tx_init` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L627-L637`](../../xitdb/dsl.odin#L627-L637) |
| `xitdb/dsl.odin` | `tx_with_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/dsl.odin#L754-L756`](../../xitdb/dsl.odin#L754-L756) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/collections.odin` | `hash_map_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L272-L274`](../../xitdb/collections.odin#L272-L274) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L423-L428`](../../xitdb/collections.odin#L423-L428) |
| `xitdb/dsl.odin` | `tx_commit` | **Entry Point** (`depth 0`) | 58 | [`xitdb/dsl.odin#L1035-L1092`](../../xitdb/dsl.odin#L1035-L1092) |
| `xitdb/dsl.odin` | `tx_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/dsl.odin#L698-L702`](../../xitdb/dsl.odin#L698-L702) |
| `xitdb/dsl.odin` | `select_cursor` | **Entry Point** (`depth 0`) | 15 | [`xitdb/dsl.odin#L410-L424`](../../xitdb/dsl.odin#L410-L424) |
| `xitdb/dsl.odin` | `pull` | **Entry Point** (`depth 0`) | 11 | [`xitdb/dsl.odin#L1697-L1707`](../../xitdb/dsl.odin#L1697-L1707) |
| `xitdb/dsl.odin` | `diff_moments` | **Entry Point** (`depth 0`) | 12 | [`xitdb/dsl.odin#L1985-L1996`](../../xitdb/dsl.odin#L1985-L1996) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_and_value`, `hash_map_put_key_by_hash`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`, `tx_commit`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `hash_map_slot`, `pull`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L64-L67`](../../xitdb/cursor.odin#L64-L67) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put`, `hash_map_put_cursor`, `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`, `select_cursor`, `diff_moments`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/dsl.odin` | `diff_changes_destroy` | `depth 1` (from `tx_commit`) | 10 | [`xitdb/dsl.odin#L655-L664`](../../xitdb/dsl.odin#L655-L664) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`, `select_cursor`, `diff_moments`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`, `read_steps_cursor`, `_diff_recursive`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 1` (from `tx_put`, `parse_selector`, `_eval_pull_spec`) | 107 | [`xitdb/dsl.odin#L154-L260`](../../xitdb/dsl.odin#L154-L260) |
| `xitdb/dsl.odin` | `parse_selector` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L122-L152`](../../xitdb/dsl.odin#L122-L152) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `diff_moments`, `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`, `_eval_pull_spec`, `_diff_recursive`) | 91 | [`xitdb/dsl.odin#L317-L407`](../../xitdb/dsl.odin#L317-L407) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 1` (from `pull`, `_pull_wildcard`, `_diff_recursive`) | 9 | [`xitdb/dsl.odin#L1686-L1694`](../../xitdb/dsl.odin#L1686-L1694) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 1` (from `pull`) | 24 | [`xitdb/dsl.odin#L1709-L1732`](../../xitdb/dsl.odin#L1709-L1732) |
| `xitdb/dsl.odin` | `_pull_with_visited` | `depth 1` (from `pull`, `_eval_pull_spec`, `_pull_range`) | 20 | [`xitdb/dsl.odin#L1744-L1763`](../../xitdb/dsl.odin#L1744-L1763) |
| `xitdb/dsl.odin` | `diff_cursors` | `depth 1` (from `diff_moments`) | 6 | [`xitdb/dsl.odin#L1998-L2003`](../../xitdb/dsl.odin#L1998-L2003) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path_slot`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `cursor_slot`, `read_array_list_init`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`, `_diff_recursive`) | 39 | [`xitdb/cursor.odin#L395-L433`](../../xitdb/cursor.odin#L395-L433) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/dsl.odin` | `_parse_step_ident_or_bracket` | `depth 2` (from `parse_steps`) | 33 | [`xitdb/dsl.odin#L262-L294`](../../xitdb/dsl.odin#L262-L294) |
| `xitdb/dsl.odin` | `_parse_bracketed_string` | `depth 2` (from `parse_steps`, `_parse_step_ident_or_bracket`) | 19 | [`xitdb/dsl.odin#L296-L314`](../../xitdb/dsl.odin#L296-L314) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L247-L255`](../../xitdb/collections.odin#L247-L255) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 2` (from `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_get_cursor` | `depth 2` (from `read_steps_cursor`, `_diff_recursive`) | 3 | [`xitdb/collections.odin#L750-L752`](../../xitdb/collections.odin#L750-L752) |
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
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`, `_diff_recursive`) | 4 | [`xitdb/cursor.odin#L236-L239`](../../xitdb/cursor.odin#L236-L239) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 2` (from `_pull_with_visited`) | 80 | [`xitdb/dsl.odin#L1860-L1939`](../../xitdb/dsl.odin#L1860-L1939) |
| `xitdb/dsl.odin` | `_split_top_level_pull_specs` | `depth 2` (from `_pull_with_visited`) | 27 | [`xitdb/dsl.odin#L1941-L1967`](../../xitdb/dsl.odin#L1941-L1967) |
| `xitdb/dsl.odin` | `_eval_pull_spec` | `depth 2` (from `_pull_with_visited`) | 51 | [`xitdb/dsl.odin#L1779-L1829`](../../xitdb/dsl.odin#L1779-L1829) |
| `xitdb/dsl.odin` | `_diff_recursive` | `depth 2` (from `diff_cursors`) | 205 | [`xitdb/dsl.odin#L2005-L2209`](../../xitdb/dsl.odin#L2005-L2209) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_reload_slot`, `read_slot_pointer`, `_exec_path_part`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `sorted_target_slot`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L568-L572`](../../xitdb/core.odin#L568-L572) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `cursor_read_path_slot`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `sorted_put`) | 15 | [`xitdb/core.odin#L574-L588`](../../xitdb/core.odin#L574-L588) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L543-L566`](../../xitdb/core.odin#L543-L566) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1138-L1142`](../../xitdb/btree.odin#L1138-L1142) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_committed_size_with_header`, `_database_truncate_with_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `btree_reusable`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `cursor_count`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_iterator`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_iterator`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 115 | [`xitdb/btree.odin#L1278-L1392`](../../xitdb/btree.odin#L1278-L1392) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2229-L2246`](../../xitdb/btree.odin#L2229-L2246) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1697-L2070`](../../xitdb/btree.odin#L1697-L2070) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2216-L2227`](../../xitdb/btree.odin#L2216-L2227) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L496-L501`](../../xitdb/core.odin#L496-L501) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_read_bytes_object`) | 7 | [`xitdb/core.odin#L488-L494`](../../xitdb/core.odin#L488-L494) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1396-L1449`](../../xitdb/database.odin#L1396-L1449) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1383-L1394`](../../xitdb/database.odin#L1383-L1394) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `sorted_put`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`, `cursor_iterator_array_list_from_index`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `read_map_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 4` (from `_exec_path_part`) | 87 | [`xitdb/btree.odin#L103-L189`](../../xitdb/btree.odin#L103-L189) |
| `xitdb/btree.odin` | `btree_get_for_write` | `depth 4` (from `_exec_path_part`) | 76 | [`xitdb/btree.odin#L446-L521`](../../xitdb/btree.odin#L446-L521) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_get_for_write`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L554-L556`](../../xitdb/collections.odin#L554-L556) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L228-L234`](../../xitdb/cursor.odin#L228-L234) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`) | 43 | [`xitdb/cursor.odin#L713-L755`](../../xitdb/cursor.odin#L713-L755) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`, `_pull_range`) | 22 | [`xitdb/cursor.odin#L1075-L1096`](../../xitdb/cursor.odin#L1075-L1096) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`) | 19 | [`xitdb/cursor.odin#L366-L384`](../../xitdb/cursor.odin#L366-L384) |
| `xitdb/dsl.odin` | `_pull_range` | `depth 3` (from `_eval_pull_spec`) | 28 | [`xitdb/dsl.odin#L1831-L1858`](../../xitdb/dsl.odin#L1831-L1858) |
| `xitdb/dsl.odin` | `ll` | `depth 3` (from `_diff_recursive`) | 3 | [`xitdb/dsl.odin#L54-L56`](../../xitdb/dsl.odin#L54-L56) |
| `xitdb/dsl.odin` | `al` | `depth 3` (from `_diff_recursive`) | 3 | [`xitdb/dsl.odin#L50-L52`](../../xitdb/dsl.odin#L50-L52) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/core.odin` | `_memory_resize` | `depth 4` (from `core_write_slot`, `core_write_all`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `slot_from_slice`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1098-L1136`](../../xitdb/btree.odin#L1098-L1136) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `sorted_get`, `read_map_slot`, `read_btree_slot`) | 17 | [`xitdb/core.odin#L435-L451`](../../xitdb/core.odin#L435-L451) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `sorted_get`, `sorted_put`, `read_btree_slot`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1160-L1172`](../../xitdb/btree.odin#L1160-L1172) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1181-L1240`](../../xitdb/btree.odin#L1181-L1240) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `cursor_read_kv_pair`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `sorted_put`, `btree_get_for_write`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1634-L1640`](../../xitdb/btree.odin#L1634-L1640) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1152-L1158`](../../xitdb/btree.odin#L1152-L1158) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1174-L1179`](../../xitdb/btree.odin#L1174-L1179) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1642-L1695`](../../xitdb/btree.odin#L1642-L1695) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1144-L1150`](../../xitdb/btree.odin#L1144-L1150) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `sorted_put`, `core_write_long`, `write_sorted_key_and_entry`) | 14 | [`xitdb/core.odin#L528-L541`](../../xitdb/core.odin#L528-L541) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1299-L1308`](../../xitdb/types.odin#L1299-L1308) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1059-L1096`](../../xitdb/btree.odin#L1059-L1096) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1244-L1260`](../../xitdb/btree.odin#L1244-L1260) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1263-L1276`](../../xitdb/btree.odin#L1263-L1276) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L503-L526`](../../xitdb/core.odin#L503-L526) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`, `read_map_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_get_for_write`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator`, `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 4 | [`xitdb/cursor.odin#L59-L62`](../../xitdb/cursor.odin#L59-L62) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L692-L695`](../../xitdb/cursor.odin#L692-L695) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 15 | [`xitdb/cursor.odin#L697-L711`](../../xitdb/cursor.odin#L697-L711) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 4` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1040-L1073`](../../xitdb/cursor.odin#L1040-L1073) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 4` (from `cursor_read_kv_pair`, `read_kv_pair`) | 35 | [`xitdb/types.odin#L1155-L1189`](../../xitdb/types.odin#L1155-L1189) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 4` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L536-L541`](../../xitdb/database.odin#L536-L541) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 4` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L543-L548`](../../xitdb/database.odin#L543-L548) |
| `xitdb/collections.odin` | `array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/collections.odin` | `linked_array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L145-L147`](../../xitdb/collections.odin#L145-L147) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `write_kv_pair`, `kv_pair_write`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`, `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_iter_level`, `_init_btree_iter_level`, `cursor_iterator_array_list_from_index`) | 21 | [`xitdb/cursor.odin#L670-L690`](../../xitdb/cursor.odin#L670-L690) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 5` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1136-L1145`](../../xitdb/types.odin#L1136-L1145) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 5` (from `array_list_iterator_from`) | 36 | [`xitdb/cursor.odin#L938-L973`](../../xitdb/cursor.odin#L938-L973) |
| `xitdb/cursor.odin` | `cursor_iterator_linked_array_list_from_index` | `depth 5` (from `linked_array_list_iterator_from`) | 64 | [`xitdb/cursor.odin#L975-L1038`](../../xitdb/cursor.odin#L975-L1038) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 6` (from `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 11 | [`xitdb/cursor.odin#L757-L767`](../../xitdb/cursor.odin#L757-L767) |
