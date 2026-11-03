# #75. `DSL Layer 3/4: Cyclic Graph pull + diff (N=200)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L2360-L2402`)](../bench_xitdb.odin#L2360-L2402)

- **Touched Library Scope:** **184** procedures across **8** `xitdb/*.odin` files (**4561** lines of library code)
- **Direct Benchmark Entry Points:** `tx_init`, `tx_with_cursor`, `write_hash_map_init`, `hash_map_slot`, `hash_map_put`, `hash_map_put_cursor`, `tx_commit`, `tx_put`, `select_cursor`, `pull`, `diff_moments`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L2360-L2402`)

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

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
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
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_and_value`, `hash_map_put_key_by_hash`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`, `tx_commit`, `read_steps_cursor`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `hash_map_slot`, `pull`, `_pull_wildcard`) | 4 | [`xitdb/cursor.odin#L63-L66`](../../xitdb/cursor.odin#L63-L66) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put`, `hash_map_put_cursor`, `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `tx_commit`, `select_cursor`, `diff_moments`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/collections.odin` | `write_array_list_init` | `depth 1` (from `tx_commit`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_count` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L37-L39`](../../xitdb/collections.odin#L37-L39) |
| `xitdb/dsl.odin` | `diff_changes_destroy` | `depth 1` (from `tx_commit`) | 10 | [`xitdb/dsl.odin#L655-L664`](../../xitdb/dsl.odin#L655-L664) |
| `xitdb/collections.odin` | `array_list_get_slot` | `depth 1` (from `tx_commit`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | `depth 1` (from `tx_commit`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/collections.odin` | `array_list_get_cursor` | `depth 1` (from `tx_commit`, `select_cursor`, `diff_moments`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | `depth 1` (from `tx_commit`, `read_steps_cursor`, `_diff_recursive`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `tx_commit`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/dsl.odin` | `parse_steps` | `depth 1` (from `tx_put`, `parse_selector`, `_eval_pull_spec`) | 107 | [`xitdb/dsl.odin#L154-L260`](../../xitdb/dsl.odin#L154-L260) |
| `xitdb/dsl.odin` | `parse_selector` | `depth 1` (from `select_cursor`) | 31 | [`xitdb/dsl.odin#L122-L152`](../../xitdb/dsl.odin#L122-L152) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `select_cursor`, `diff_moments`, `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/dsl.odin` | `read_steps_cursor` | `depth 1` (from `select_cursor`, `_eval_pull_spec`, `_diff_recursive`) | 91 | [`xitdb/dsl.odin#L317-L407`](../../xitdb/dsl.odin#L317-L407) |
| `xitdb/dsl.odin` | `_is_collection_tag` | `depth 1` (from `pull`, `_pull_wildcard`, `_diff_recursive`) | 9 | [`xitdb/dsl.odin#L1686-L1694`](../../xitdb/dsl.odin#L1686-L1694) |
| `xitdb/dsl.odin` | `_pull_scalar_slot` | `depth 1` (from `pull`) | 24 | [`xitdb/dsl.odin#L1709-L1732`](../../xitdb/dsl.odin#L1709-L1732) |
| `xitdb/dsl.odin` | `_pull_with_visited` | `depth 1` (from `pull`, `_eval_pull_spec`, `_pull_range`) | 20 | [`xitdb/dsl.odin#L1744-L1763`](../../xitdb/dsl.odin#L1744-L1763) |
| `xitdb/dsl.odin` | `diff_cursors` | `depth 1` (from `diff_moments`) | 6 | [`xitdb/dsl.odin#L1998-L2003`](../../xitdb/dsl.odin#L1998-L2003) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path_slot`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `cursor_slot`, `read_array_list_init`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 2` (from `array_list_count`, `_diff_recursive`) | 39 | [`xitdb/cursor.odin#L394-L432`](../../xitdb/cursor.odin#L394-L432) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 2` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L81-L95`](../../xitdb/cursor.odin#L81-L95) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `array_list_get_cursor`, `read_steps_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 2` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
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
| `xitdb/cursor.odin` | `cursor_read_uint` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/cursor.odin` | `cursor_read_int` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L211-L217`](../../xitdb/cursor.odin#L211-L217) |
| `xitdb/cursor.odin` | `cursor_read_float` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`) | 7 | [`xitdb/cursor.odin#L219-L225`](../../xitdb/cursor.odin#L219-L225) |
| `xitdb/cursor.odin` | `cursor_read_bytes_object` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`, `cursor_read_bytes`) | 56 | [`xitdb/cursor.odin#L240-L295`](../../xitdb/cursor.odin#L240-L295) |
| `xitdb/cursor.odin` | `cursor_read_string` | `depth 2` (from `_pull_scalar_slot`, `_pull_wildcard`, `_diff_recursive`) | 4 | [`xitdb/cursor.odin#L235-L238`](../../xitdb/cursor.odin#L235-L238) |
| `xitdb/dsl.odin` | `_pull_wildcard` | `depth 2` (from `_pull_with_visited`) | 80 | [`xitdb/dsl.odin#L1860-L1939`](../../xitdb/dsl.odin#L1860-L1939) |
| `xitdb/dsl.odin` | `_split_top_level_pull_specs` | `depth 2` (from `_pull_with_visited`) | 27 | [`xitdb/dsl.odin#L1941-L1967`](../../xitdb/dsl.odin#L1941-L1967) |
| `xitdb/dsl.odin` | `_eval_pull_spec` | `depth 2` (from `_pull_with_visited`) | 51 | [`xitdb/dsl.odin#L1779-L1829`](../../xitdb/dsl.odin#L1779-L1829) |
| `xitdb/dsl.odin` | `_diff_recursive` | `depth 2` (from `diff_cursors`) | 205 | [`xitdb/dsl.odin#L2005-L2209`](../../xitdb/dsl.odin#L2005-L2209) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_reload_slot`, `read_slot_pointer`, `_exec_path_part`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `cursor_read_path_slot`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1107-L1111`](../../xitdb/btree.odin#L1107-L1111) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_committed_size_with_header`, `_database_truncate_with_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `cursor_count`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_read_bytes_object`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_iterator`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L345-L383`](../../xitdb/hamt.odin#L345-L383) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`, `sorted_target_slot`, `database_kv_key_position`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1397-L1450`](../../xitdb/database.odin#L1397-L1450) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1384-L1395`](../../xitdb/database.odin#L1384-L1395) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `read_map_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_encode_writeable_data`, `_try_encode_inline_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`, `cursor_iterator_array_list_from_index`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`, `cursor_count`, `cursor_iterator`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 113 | [`xitdb/btree.odin#L1247-L1359`](../../xitdb/btree.odin#L1247-L1359) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2192-L2209`](../../xitdb/btree.odin#L2192-L2209) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1654-L2027`](../../xitdb/btree.odin#L1654-L2027) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2179-L2190`](../../xitdb/btree.odin#L2179-L2190) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `read_map_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/collections.odin` | `sorted_map_get_cursor_by_bytes` | `depth 3` (from `sorted_map_get_cursor`) | 3 | [`xitdb/collections.odin#L710-L712`](../../xitdb/collections.odin#L710-L712) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_get_for_write`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 4` (from `_exec_path_part`) | 79 | [`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181) |
| `xitdb/btree.odin` | `btree_get_for_write` | `depth 4` (from `_exec_path_part`) | 73 | [`xitdb/btree.odin#L432-L504`](../../xitdb/btree.odin#L432-L504) |
| `xitdb/collections.odin` | `hash_set_get_cursor_by_hash` | `depth 3` (from `hash_set_get_cursor`) | 3 | [`xitdb/collections.odin#L554-L556`](../../xitdb/collections.odin#L554-L556) |
| `xitdb/cursor.odin` | `cursor_read_bytes` | `depth 3` (from `cursor_read_string`) | 7 | [`xitdb/cursor.odin#L227-L233`](../../xitdb/cursor.odin#L227-L233) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`) | 43 | [`xitdb/cursor.odin#L723-L765`](../../xitdb/cursor.odin#L723-L765) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`, `_pull_range`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_read_kv_pair` | `depth 3` (from `_pull_wildcard`, `_diff_recursive`) | 19 | [`xitdb/cursor.odin#L365-L383`](../../xitdb/cursor.odin#L365-L383) |
| `xitdb/dsl.odin` | `_pull_range` | `depth 3` (from `_eval_pull_spec`) | 28 | [`xitdb/dsl.odin#L1831-L1858`](../../xitdb/dsl.odin#L1831-L1858) |
| `xitdb/dsl.odin` | `ll` | `depth 3` (from `_diff_recursive`) | 3 | [`xitdb/dsl.odin#L54-L56`](../../xitdb/dsl.odin#L54-L56) |
| `xitdb/dsl.odin` | `al` | `depth 3` (from `_diff_recursive`) | 3 | [`xitdb/dsl.odin#L50-L52`](../../xitdb/dsl.odin#L50-L52) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `sorted_get`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1067-L1105`](../../xitdb/btree.odin#L1067-L1105) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`, `sorted_put`, `write_sorted_key_and_entry`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`, `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`, `read_array_list_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `sorted_get`, `read_btree_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `cursor_read_kv_pair`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `sorted_put`, `btree_get_for_write`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1591-L1597`](../../xitdb/btree.odin#L1591-L1597) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1121-L1127`](../../xitdb/btree.odin#L1121-L1127) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1143-L1148`](../../xitdb/btree.odin#L1143-L1148) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1599-L1652`](../../xitdb/btree.odin#L1599-L1652) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1113-L1119`](../../xitdb/btree.odin#L1113-L1119) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1293-L1302`](../../xitdb/types.odin#L1293-L1302) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1028-L1065`](../../xitdb/btree.odin#L1028-L1065) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1213-L1229`](../../xitdb/btree.odin#L1213-L1229) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1232-L1245`](../../xitdb/btree.odin#L1232-L1245) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_get_for_write`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 4` (from `cursor_iterator`, `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 4` (from `cursor_iterator`, `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 4` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 4` (from `cursor_read_kv_pair`, `read_kv_pair`) | 35 | [`xitdb/types.odin#L1149-L1183`](../../xitdb/types.odin#L1149-L1183) |
| `xitdb/database.odin` | `database_kv_key_position` | `depth 4` (from `cursor_read_kv_pair`, `database_kv_value_position`) | 6 | [`xitdb/database.odin#L537-L542`](../../xitdb/database.odin#L537-L542) |
| `xitdb/database.odin` | `database_kv_value_position` | `depth 4` (from `cursor_read_kv_pair`) | 6 | [`xitdb/database.odin#L544-L549`](../../xitdb/database.odin#L544-L549) |
| `xitdb/collections.odin` | `array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/collections.odin` | `linked_array_list_iterator_from` | `depth 4` (from `_pull_range`) | 3 | [`xitdb/collections.odin#L145-L147`](../../xitdb/collections.odin#L145-L147) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`, `write_kv_pair`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`, `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 5` (from `_init_iter_level`, `cursor_iterator_array_list_from_index`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 5` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1130-L1139`](../../xitdb/types.odin#L1130-L1139) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 5` (from `array_list_iterator_from`) | 36 | [`xitdb/cursor.odin#L951-L986`](../../xitdb/cursor.odin#L951-L986) |
| `xitdb/cursor.odin` | `cursor_iterator_linked_array_list_from_index` | `depth 5` (from `linked_array_list_iterator_from`) | 61 | [`xitdb/cursor.odin#L988-L1048`](../../xitdb/cursor.odin#L988-L1048) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 6` (from `cursor_iterator_array_list_from_index`, `cursor_iterator_linked_array_list_from_index`) | 11 | [`xitdb/cursor.odin#L767-L777`](../../xitdb/cursor.odin#L767-L777) |
| `xitdb/cursor.odin` | `_fill_slot_block_raw_from` | `depth 6` (from `cursor_iterator_linked_array_list_from_index`) | 19 | [`xitdb/cursor.odin#L670-L688`](../../xitdb/cursor.odin#L670-L688) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/btree.odin` (22 procedures · 1015 lines: [`L8–L41`](../../xitdb/btree.odin#L8-L41), [`L43–L75`](../../xitdb/btree.odin#L43-L75), [`L77–L81`](../../xitdb/btree.odin#L77-L81), [`L83–L89`](../../xitdb/btree.odin#L83-L89), [`L103–L181`](../../xitdb/btree.odin#L103-L181), [`L432–L504`](../../xitdb/btree.odin#L432-L504), [`L1028–L1065`](../../xitdb/btree.odin#L1028-L1065), [`L1067–L1105`](../../xitdb/btree.odin#L1067-L1105), [`L1107–L1111`](../../xitdb/btree.odin#L1107-L1111), [`L1113–L1119`](../../xitdb/btree.odin#L1113-L1119), [`L1121–L1127`](../../xitdb/btree.odin#L1121-L1127), [`L1129–L1141`](../../xitdb/btree.odin#L1129-L1141), [`L1143–L1148`](../../xitdb/btree.odin#L1143-L1148), [`L1150–L1209`](../../xitdb/btree.odin#L1150-L1209), [`L1213–L1229`](../../xitdb/btree.odin#L1213-L1229), [`L1232–L1245`](../../xitdb/btree.odin#L1232-L1245), [`L1247–L1359`](../../xitdb/btree.odin#L1247-L1359), [`L1591–L1597`](../../xitdb/btree.odin#L1591-L1597), [`L1599–L1652`](../../xitdb/btree.odin#L1599-L1652), [`L1654–L2027`](../../xitdb/btree.odin#L1654-L2027), [`L2179–L2190`](../../xitdb/btree.odin#L2179-L2190), [`L2192–L2209`](../../xitdb/btree.odin#L2192-L2209))

#### [`read_btree_node`](../../xitdb/btree.odin#L8-L41) — `DEPTH 5` (`L8–L41`)

```odin
   8 | read_btree_node :: proc(db: ^Database, ptr: i64) -> (res: BTree_Node, err: Error) {
   9 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
  10 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
  11 | 	core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
  12 | 	kind_int := header_bytes[0]
  13 | 	if kind_int > u8(BTree_Node_Kind.Branch) {
  14 | 		return {}, .Invalid_BTree_Node_Kind
  15 | 	}
  16 | 	kind := BTree_Node_Kind(kind_int)
  17 | 	num := int(header_bytes[1])
  18 | 	if num > BTREE_SLOT_COUNT {
  19 | 		return {}, .Invalid_BTree_Node
  20 | 	}
  21 | 	node := BTree_Node{kind = kind, num = num}
  22 | 	switch kind {
  23 | 	case .Leaf:
  24 | 		body: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
  25 | 		core_read_exact(db.core, body[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
  26 | 		for i in 0 ..< num {
  27 | 			node.values[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  28 | 		}
  29 | 	case .Branch:
  30 | 		body: [(SLOT_LENGTH + 8) * BTREE_SLOT_COUNT]u8 = ---
  31 | 		core_read_exact(db.core, body[:SLOT_LENGTH * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
  32 | 		for i in 0 ..< num {
  33 | 			node.children[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  34 | 		}
  35 | 		counts_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
  36 | 		for i in 0 ..< num {
  37 | 			node.counts[i] = i64(endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + i * 8 + 8]))
  38 | 		}
  39 | 	}
  40 | 	return node, nil
  41 | }
```

#### [`write_btree_node_at`](../../xitdb/btree.odin#L43-L75) — `DEPTH 5` (`L43–L75`)

```odin
  43 | write_btree_node_at :: proc(db: ^Database, node: BTree_Node, ptr: i64) -> Error {
  44 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
  45 | 	switch node.kind {
  46 | 	case .Leaf:
  47 | 		buf: [BTREE_LEAF_BLOCK_SIZE]u8
  48 | 		buf[0] = u8(node.kind)
  49 | 		buf[1] = u8(node.num)
  50 | 		off := BTREE_NODE_HEADER_SIZE
  51 | 		for i in 0 ..< node.num {
  52 | 			sb := slot_to_bytes(node.values[i])  // <== [calls slot_to_bytes]
  53 | 			copy(buf[off:], sb[:])
  54 | 			off += SLOT_LENGTH
  55 | 		}
  56 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
  57 | 	case .Branch:
  58 | 		buf: [BTREE_BRANCH_BLOCK_SIZE]u8
  59 | 		buf[0] = u8(node.kind)
  60 | 		buf[1] = u8(node.num)
  61 | 		off := BTREE_NODE_HEADER_SIZE
  62 | 		for i in 0 ..< node.num {
  63 | 			sb := slot_to_bytes(node.children[i])  // <== [calls slot_to_bytes]
  64 | 			copy(buf[off:], sb[:])
  65 | 			off += SLOT_LENGTH
  66 | 		}
  67 | 		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
  68 | 		for i in 0 ..< node.num {
  69 | 			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
  70 | 			counts_off += 8
  71 | 		}
  72 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
  73 | 	}
  74 | 	return .Unreachable
  75 | }
```

#### [`write_btree_node`](../../xitdb/btree.odin#L77-L81) — `DEPTH 4` (`L77–L81`)

```odin
  77 | write_btree_node :: proc(db: ^Database, node: BTree_Node) -> (res: i64, err: Error) {
  78 | 	ptr := core_length(db.core) or_return  // <== [calls core_length]
  79 | 	write_btree_node_at(db, node, ptr) or_return  // <== [calls write_btree_node_at]
  80 | 	return ptr, nil
  81 | }
```

#### [`btree_reusable`](../../xitdb/btree.odin#L83-L89) — `DEPTH 5` (`L83–L89`)

```odin
  83 | btree_reusable :: proc(db: ^Database, ptr, frozen_at: i64) -> bool {
  84 | 	old, err := database_is_old(db, ptr, frozen_at)  // <== [calls database_is_old]
  85 | 	if err != nil {
  86 | 		return false
  87 | 	}
  88 | 	return !old
  89 | }
```

#### [`read_btree_slot`](../../xitdb/btree.odin#L103-L181) — `DEPTH 4` (`L103–L181`)

```odin
 103 | read_btree_slot :: proc(db: ^Database, root_ptr, rank: i64) -> (res: Slot_Pointer, err: Error) {
 104 | 	node_ptr := root_ptr
 105 | 	rem := rank
 106 | 	for {
 107 | 		if hdr_slice, in_mem, slice_err := core_slice_at(db.core, node_ptr, BTREE_NODE_HEADER_SIZE); in_mem {  // <== [calls core_slice_at]
 108 | 			if slice_err != nil {
 109 | 				return {}, slice_err
 110 | 			}
 111 | 			kind_int := hdr_slice[0]
 112 | 			if kind_int > u8(BTree_Node_Kind.Branch) {
 113 | 				return {}, .Invalid_BTree_Node_Kind
 114 | 			}
 115 | 			num := int(hdr_slice[1])
 116 | 			if num > BTREE_SLOT_COUNT {
 117 | 				return {}, .Invalid_BTree_Node
 118 | 			}
 119 | 			if BTree_Node_Kind(kind_int) == .Leaf {
 120 | 				position := node_ptr + BTREE_NODE_HEADER_SIZE + rem * SLOT_LENGTH
 121 | 				slot_slice, _, s_err := core_slice_at(db.core, position, SLOT_LENGTH)  // <== [calls core_slice_at]
 122 | 				if s_err != nil {
 123 | 					return {}, s_err
 124 | 				}
 125 | 				return Slot_Pointer{position = position, slot = slot_from_slice_raw(slot_slice)}, nil  // <== [calls slot_from_slice_raw]
 126 | 			}
 127 | 			body_len := SLOT_LENGTH * BTREE_SLOT_COUNT + num * 8
 128 | 			body_slice, _, b_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, body_len)  // <== [calls core_slice_at]
 129 | 			if b_err != nil {
 130 | 				return {}, b_err
 131 | 			}
 132 | 			counts_off := SLOT_LENGTH * BTREE_SLOT_COUNT
 133 | 			i := 0
 134 | 			for i + 1 < num {
 135 | 				cnt := i64(endian.unchecked_get_u64be(body_slice[counts_off + i * 8 : counts_off + (i + 1) * 8]))
 136 | 				if rem < cnt {
 137 | 					break
 138 | 				}
 139 | 				rem -= cnt
 140 | 				i += 1
 141 | 			}
 142 | 			node_ptr = slot_from_slice_raw(body_slice[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
 143 | 			continue
 144 | 		}
 145 | 
 146 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
 147 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
 148 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 149 | 		kind_int := header_bytes[0]
 150 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
 151 | 			return {}, .Invalid_BTree_Node_Kind
 152 | 		}
 153 | 		num := int(header_bytes[1])
 154 | 		if num > BTREE_SLOT_COUNT {
 155 | 			return {}, .Invalid_BTree_Node
 156 | 		}
 157 | 		if BTree_Node_Kind(kind_int) == .Leaf {
 158 | 			position := node_ptr + BTREE_NODE_HEADER_SIZE + rem * SLOT_LENGTH
 159 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 160 | 			slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 161 | 			return Slot_Pointer{position = position, slot = slot}, nil
 162 | 		}
 163 | 		counts_pos := node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
 164 | 		core_seek_to(db.core, counts_pos) or_return  // <== [calls core_seek_to]
 165 | 		counts_buf: [8 * BTREE_SLOT_COUNT]u8 = ---
 166 | 		core_read_exact(db.core, counts_buf[:num * 8]) or_return  // <== [calls core_read_exact]
 167 | 		i := 0
 168 | 		for i + 1 < num {
 169 | 			cnt := i64(endian.unchecked_get_u64be(counts_buf[i * 8 : i * 8 + 8]))
 170 | 			if rem < cnt {
 171 | 				break
 172 | 			}
 173 | 			rem -= cnt
 174 | 			i += 1
 175 | 		}
 176 | 		child_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
 177 | 		core_seek_to(db.core, child_pos) or_return  // <== [calls core_seek_to]
 178 | 		child_slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 179 | 		node_ptr = child_slot.value
 180 | 	}
 181 | }
```

#### [`btree_get_for_write`](../../xitdb/btree.odin#L432-L504) — `DEPTH 4` (`L432–L504`)

```odin
 432 | btree_get_for_write :: proc(db: ^Database, node_ptr, rank, frozen_at: i64) -> (res: BTree_Write_Slot, err: Error) {
 433 | 	core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
 434 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8
 435 | 	core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 436 | 	kind_int := header_bytes[0]
 437 | 	if kind_int > u8(BTree_Node_Kind.Branch) {
 438 | 		return {}, .Invalid_BTree_Node_Kind
 439 | 	}
 440 | 	num := int(header_bytes[1])
 441 | 	if num > BTREE_SLOT_COUNT {
 442 | 		return {}, .Invalid_BTree_Node
 443 | 	}
 444 | 	reusable := btree_reusable(db, node_ptr, frozen_at)  // <== [calls btree_reusable]
 445 | 	if BTree_Node_Kind(kind_int) == .Leaf {
 446 | 		if reusable {
 447 | 			val_pos := node_ptr + BTREE_NODE_HEADER_SIZE + rank * SLOT_LENGTH
 448 | 			core_seek_to(db.core, val_pos) or_return  // <== [calls core_seek_to]
 449 | 			slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 450 | 			return BTree_Write_Slot{
 451 | 				node_ptr       = node_ptr,
 452 | 				value_position = val_pos,
 453 | 				slot           = slot,
 454 | 			}, nil
 455 | 		}
 456 | 		node := read_btree_node(db, node_ptr) or_return  // <== [calls read_btree_node]
 457 | 		new_ptr := write_btree_node(db, node) or_return  // <== [calls write_btree_node]
 458 | 		return BTree_Write_Slot{
 459 | 			node_ptr       = new_ptr,
 460 | 			value_position = new_ptr + BTREE_NODE_HEADER_SIZE + rank * SLOT_LENGTH,
 461 | 			slot           = node.values[rank],
 462 | 		}, nil
 463 | 	}
 464 | 
 465 | 	if reusable {
 466 | 		counts_pos := node_ptr + BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
 467 | 		core_seek_to(db.core, counts_pos) or_return  // <== [calls core_seek_to]
 468 | 		counts_buf: [8 * BTREE_SLOT_COUNT]u8
 469 | 		core_read_exact(db.core, counts_buf[:num * 8]) or_return  // <== [calls core_read_exact]
 470 | 		i := 0
 471 | 		rem := rank
 472 | 		for i + 1 < num {
 473 | 			cnt := i64(endian.unchecked_get_u64be(counts_buf[i * 8 : i * 8 + 8]))
 474 | 			if rem < cnt {
 475 | 				break
 476 | 			}
 477 | 			rem -= cnt
 478 | 			i += 1
 479 | 		}
 480 | 		child_slot_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(i) * SLOT_LENGTH
 481 | 		core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
 482 | 		child_slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 483 | 		child_ptr := child_slot.value
 484 | 		child := btree_get_for_write(db, child_ptr, rem, frozen_at) or_return
 485 | 		if child.node_ptr != child_ptr {
 486 | 			core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
 487 | 			core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 488 | 		}
 489 | 		return BTree_Write_Slot{node_ptr = node_ptr, value_position = child.value_position, slot = child.slot}, nil
 490 | 	}
 491 | 
 492 | 	node := read_btree_node(db, node_ptr) or_return  // <== [calls read_btree_node]
 493 | 	i := 0
 494 | 	rem := rank
 495 | 	for i + 1 < node.num && rem >= node.counts[i] {
 496 | 		rem -= node.counts[i]
 497 | 		i += 1
 498 | 	}
 499 | 	child_ptr := node.children[i].value
 500 | 	child := btree_get_for_write(db, child_ptr, rem, frozen_at) or_return
 501 | 	node.children[i] = Slot{value = child.node_ptr, tag = .Index}
 502 | 	new_ptr := write_btree_node(db, node) or_return  // <== [calls write_btree_node]
 503 | 	return BTree_Write_Slot{node_ptr = new_ptr, value_position = child.value_position, slot = child.slot}, nil
 504 | }
```

#### [`read_sorted_node`](../../xitdb/btree.odin#L1028-L1065) — `DEPTH 5` (`L1028–L1065`)

```odin
1028 | read_sorted_node :: proc(db: ^Database, ptr: i64) -> (res: Sorted_Node, err: Error) {
1029 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
1030 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1031 | 	core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1032 | 	kind_int := header_bytes[0]
1033 | 	if kind_int > u8(BTree_Node_Kind.Branch) {
1034 | 		return {}, .Invalid_BTree_Node_Kind
1035 | 	}
1036 | 	kind := BTree_Node_Kind(kind_int)
1037 | 	num := int(header_bytes[1])
1038 | 	if num > BTREE_SLOT_COUNT {
1039 | 		return {}, .Invalid_BTree_Node
1040 | 	}
1041 | 	node := Sorted_Node{kind = kind, num = num}
1042 | 	switch kind {
1043 | 	case .Leaf:
1044 | 		body: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1045 | 		core_read_exact(db.core, body[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1046 | 		for i in 0 ..< num {
1047 | 			node.entries[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1048 | 		}
1049 | 	case .Branch:
1050 | 		body: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
1051 | 		core_read_exact(db.core, body[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
1052 | 		for i in 0 ..< num {
1053 | 			node.children[i] = slot_from_slice_raw(body[i * SLOT_LENGTH : i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1054 | 		}
1055 | 		sep_offset := SLOT_LENGTH * BTREE_SLOT_COUNT
1056 | 		for i in 0 ..< num {
1057 | 			node.separators[i] = slot_from_slice_raw(body[sep_offset + i * SLOT_LENGTH : sep_offset + i * SLOT_LENGTH + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1058 | 		}
1059 | 		counts_offset := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1060 | 		for i in 0 ..< num {
1061 | 			node.counts[i] = i64(endian.unchecked_get_u64be(body[counts_offset + i * 8 : counts_offset + i * 8 + 8]))
1062 | 		}
1063 | 	}
1064 | 	return node, nil
1065 | }
```

#### [`write_sorted_node_at`](../../xitdb/btree.odin#L1067-L1105) — `DEPTH 5` (`L1067–L1105`)

```odin
1067 | write_sorted_node_at :: proc(db: ^Database, node: Sorted_Node, ptr: i64) -> Error {
1068 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
1069 | 	switch node.kind {
1070 | 	case .Leaf:
1071 | 		buf: [SORTED_LEAF_BLOCK_SIZE]u8
1072 | 		buf[0] = u8(node.kind)
1073 | 		buf[1] = u8(node.num)
1074 | 		off := BTREE_NODE_HEADER_SIZE
1075 | 		for i in 0 ..< node.num {
1076 | 			sb := slot_to_bytes(node.entries[i])  // <== [calls slot_to_bytes]
1077 | 			copy(buf[off:], sb[:])
1078 | 			off += SLOT_LENGTH
1079 | 		}
1080 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
1081 | 	case .Branch:
1082 | 		buf: [SORTED_BRANCH_BLOCK_SIZE]u8
1083 | 		buf[0] = u8(node.kind)
1084 | 		buf[1] = u8(node.num)
1085 | 		off := BTREE_NODE_HEADER_SIZE
1086 | 		for i in 0 ..< node.num {
1087 | 			sb := slot_to_bytes(node.children[i])  // <== [calls slot_to_bytes]
1088 | 			copy(buf[off:], sb[:])
1089 | 			off += SLOT_LENGTH
1090 | 		}
1091 | 		sep_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * BTREE_SLOT_COUNT
1092 | 		for i in 0 ..< node.num {
1093 | 			sb := slot_to_bytes(node.separators[i])  // <== [calls slot_to_bytes]
1094 | 			copy(buf[sep_off:], sb[:])
1095 | 			sep_off += SLOT_LENGTH
1096 | 		}
1097 | 		counts_off := BTREE_NODE_HEADER_SIZE + SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1098 | 		for i in 0 ..< node.num {
1099 | 			endian.unchecked_put_u64be(buf[counts_off : counts_off + 8], u64(node.counts[i]))
1100 | 			counts_off += 8
1101 | 		}
1102 | 		return core_write_all(db.core, buf[:])  // <== [calls core_write_all]
1103 | 	}
1104 | 	return .Unreachable
1105 | }
```

#### [`write_sorted_node`](../../xitdb/btree.odin#L1107-L1111) — `DEPTH 4` (`L1107–L1111`)

```odin
1107 | write_sorted_node :: proc(db: ^Database, node: Sorted_Node) -> (res: i64, err: Error) {
1108 | 	ptr := core_length(db.core) or_return  // <== [calls core_length]
1109 | 	write_sorted_node_at(db, node, ptr) or_return  // <== [calls write_sorted_node_at]
1110 | 	return ptr, nil
1111 | }
```

#### [`sorted_write_node`](../../xitdb/btree.odin#L1113-L1119) — `DEPTH 5` (`L1113–L1119`)

```odin
1113 | sorted_write_node :: proc(db: ^Database, node: Sorted_Node, old_ptr, frozen_at: i64) -> (res: i64, err: Error) {
1114 | 	if btree_reusable(db, old_ptr, frozen_at) {  // <== [calls btree_reusable]
1115 | 		write_sorted_node_at(db, node, old_ptr) or_return  // <== [calls write_sorted_node_at]
1116 | 		return old_ptr, nil
1117 | 	}
1118 | 	return write_sorted_node(db, node)  // <== [calls write_sorted_node]
1119 | }
```

#### [`read_kv_pair`](../../xitdb/btree.odin#L1121-L1127) — `DEPTH 5` (`L1121–L1127`)

```odin
1121 | read_kv_pair :: proc(db: ^Database, entry: Slot) -> (res: Key_Value_Pair, err: Error) {
1122 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1123 | 		return Key_Value_Pair{value_slot = Slot{}, key_slot = entry, hash = nil}, nil
1124 | 	}
1125 | 	core_seek_to(db.core, entry.value) or_return  // <== [calls core_seek_to]
1126 | 	return decode_kv_pair(db.core, entry.tag, 0, context.temp_allocator)  // <== [calls decode_kv_pair]
1127 | }
```

#### [`sorted_entry_key_slot`](../../xitdb/btree.odin#L1129-L1141) — `DEPTH 5` (`L1129–L1141`)

```odin
1129 | sorted_entry_key_slot :: #force_inline proc(db: ^Database, entry: Slot) -> (res: Slot, err: Error) {
1130 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1131 | 		return entry, nil
1132 | 	}
1133 | 	if s_slice, in_mem, slice_err := core_slice_at(db.core, entry.value, SLOT_LENGTH); in_mem {  // <== [calls core_slice_at]
1134 | 		if slice_err != nil {
1135 | 			return {}, slice_err
1136 | 		}
1137 | 		return slot_from_slice_raw(s_slice), nil  // <== [calls slot_from_slice_raw]
1138 | 	}
1139 | 	core_seek_to(db.core, entry.value) or_return  // <== [calls core_seek_to]
1140 | 	return core_read_slot_raw(db.core)  // <== [calls core_read_slot_raw]
1141 | }
```

#### [`write_kv_pair`](../../xitdb/btree.odin#L1143-L1148) — `DEPTH 5` (`L1143–L1148`)

```odin
1143 | write_kv_pair :: proc(db: ^Database, tag: Tag, kv_pair: Key_Value_Pair) -> (res: Slot, err: Error) {
1144 | 	pos := core_length(db.core) or_return  // <== [calls core_length]
1145 | 	core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
1146 | 	encode_kv_pair(db.core, tag, kv_pair) or_return  // <== [calls encode_kv_pair]
1147 | 	return Slot{value = pos, tag = tag}, nil
1148 | }
```

#### [`compare_key`](../../xitdb/btree.odin#L1150-L1209) — `DEPTH 5` (`L1150–L1209`)

```odin
1150 | compare_key :: proc(db: ^Database, key_slot: Slot, target: []u8) -> (res: int, err: Error) {
1151 | 	#partial switch key_slot.tag {
1152 | 	case .Short_Bytes:
1153 | 		buf: [8]u8 = ---
1154 | 		endian.unchecked_put_u64be(buf[:], u64(key_slot.value))
1155 | 		total := 6 if key_slot.full else 8
1156 | 		length := total
1157 | 		for i in 0 ..< total {
1158 | 			if buf[i] == 0 {
1159 | 				length = i
1160 | 				break
1161 | 			}
1162 | 		}
1163 | 		return bytes.compare(buf[:length], target), nil
1164 | 	case .Bytes:
1165 | 		#partial switch &v in db.core {
1166 | 		case Core_Memory:
1167 | 			pos := int(key_slot.value)
1168 | 			if pos < 0 || pos + 8 > len(v.buf) {
1169 | 				return 0, Xitdb_Error.Unexpected_EOF
1170 | 			}
1171 | 			length := int(endian.unchecked_get_u64be(v.buf[pos : pos + 8]))
1172 | 			if length < 0 || pos + 8 + length > len(v.buf) {
1173 | 				return 0, Xitdb_Error.Unexpected_EOF
1174 | 			}
1175 | 			return bytes.compare(v.buf[pos + 8 : pos + 8 + length], target), nil
1176 | 		case Core_Buffered_File:
1177 | 			buf_len := i64(len(v.memory.buf))
1178 | 			if buf_len > 0 && key_slot.value >= v.memory_pos && key_slot.value + 8 <= v.memory_pos + buf_len {
1179 | 				mem_off := int(key_slot.value - v.memory_pos)
1180 | 				length := int(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
1181 | 				if length >= 0 && mem_off + 8 + length <= int(buf_len) {
1182 | 					return bytes.compare(v.memory.buf[mem_off + 8 : mem_off + 8 + length], target), nil
1183 | 				}
1184 | 			}
1185 | 		}
1186 | 		core_seek_to(db.core, key_slot.value) or_return  // <== [calls core_seek_to]
1187 | 		length := core_read_i64(db.core) or_return  // <== [calls core_read_i64]
1188 | 		read_len := min(int(length), len(target))
1189 | 		if read_len <= 256 {
1190 | 			stack_buf: [256]u8 = ---
1191 | 			key_bytes := stack_buf[:read_len]
1192 | 			core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1193 | 			c := bytes.compare(key_bytes, target[:read_len])
1194 | 			if c != 0 {
1195 | 				return c, nil
1196 | 			}
1197 | 			return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1198 | 		}
1199 | 		key_bytes := make([]u8, read_len, context.temp_allocator)
1200 | 		core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1201 | 		c := bytes.compare(key_bytes, target[:read_len])
1202 | 		if c != 0 {
1203 | 			return c, nil
1204 | 		}
1205 | 		return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1206 | 	case:
1207 | 		return 0, .Unexpected_Tag
1208 | 	}
1209 | }
```

#### [`sorted_leaf_search`](../../xitdb/btree.odin#L1213-L1229) — `DEPTH 5` (`L1213–L1229`)

```odin
1213 | sorted_leaf_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, found: bool, err: Error) {
1214 | 	lo := 0
1215 | 	hi := node.num
1216 | 	for lo < hi {
1217 | 		mid := int(uint(lo + hi) >> 1)
1218 | 		key_slot := sorted_entry_key_slot(db, node.entries[mid]) or_return  // <== [calls sorted_entry_key_slot]
1219 | 		cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1220 | 		if cmp == 0 {
1221 | 			return mid, true, nil
1222 | 		} else if cmp < 0 {
1223 | 			lo = mid + 1
1224 | 		} else {
1225 | 			hi = mid
1226 | 		}
1227 | 	}
1228 | 	return lo, false, nil
1229 | }
```

#### [`sorted_branch_search`](../../xitdb/btree.odin#L1232-L1245) — `DEPTH 5` (`L1232–L1245`)

```odin
1232 | sorted_branch_search :: proc(db: ^Database, node: ^Sorted_Node, key: []u8) -> (idx: int, err: Error) {
1233 | 	lo := 1
1234 | 	hi := node.num
1235 | 	for lo < hi {
1236 | 		mid := int(uint(lo + hi) >> 1)
1237 | 		c := compare_key(db, node.separators[mid], key) or_return  // <== [calls compare_key]
1238 | 		if c <= 0 {
1239 | 			lo = mid + 1
1240 | 		} else {
1241 | 			hi = mid
1242 | 		}
1243 | 	}
1244 | 	return lo - 1, nil
1245 | }
```

#### [`sorted_get`](../../xitdb/btree.odin#L1247-L1359) — `DEPTH 4` (`L1247–L1359`)

```odin
1247 | sorted_get :: proc(db: ^Database, root_ptr: i64, key: []u8) -> (res: Maybe(Sorted_Slot), err: Error) {
1248 | 	node_ptr := root_ptr
1249 | 	for {
1250 | 		if hdr_slice, in_mem, slice_err := core_slice_at(db.core, node_ptr, BTREE_NODE_HEADER_SIZE); in_mem {  // <== [calls core_slice_at]
1251 | 			if slice_err != nil {
1252 | 				return nil, slice_err
1253 | 			}
1254 | 			kind_int := hdr_slice[0]
1255 | 			if kind_int > u8(BTree_Node_Kind.Branch) {
1256 | 				return nil, .Invalid_BTree_Node_Kind
1257 | 			}
1258 | 			num := int(hdr_slice[1])
1259 | 			if num > BTREE_SLOT_COUNT {
1260 | 				return nil, .Invalid_BTree_Node
1261 | 			}
1262 | 			if BTree_Node_Kind(kind_int) == .Leaf {
1263 | 				entries_slice, _, e_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, num * SLOT_LENGTH)  // <== [calls core_slice_at]
1264 | 				if e_err != nil {
1265 | 					return nil, e_err
1266 | 				}
1267 | 				lo := 0
1268 | 				hi := num
1269 | 				for lo < hi {
1270 | 					mid := int(uint(lo + hi) >> 1)
1271 | 					entry_slot := slot_from_slice_raw(entries_slice[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1272 | 					key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1273 | 					cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1274 | 					if cmp == 0 {
1275 | 						entry_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(mid) * SLOT_LENGTH
1276 | 						return Sorted_Slot{slot = entry_slot, key_slot = key_slot, position = entry_pos}, nil
1277 | 					} else if cmp < 0 {
1278 | 						lo = mid + 1
1279 | 					} else {
1280 | 						hi = mid
1281 | 					}
1282 | 				}
1283 | 				return nil, nil
1284 | 			}
1285 | 			branch_slice, _, b_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, (BTREE_SLOT_COUNT + num) * SLOT_LENGTH)  // <== [calls core_slice_at]
1286 | 			if b_err != nil {
1287 | 				return nil, b_err
1288 | 			}
1289 | 			lo := 1
1290 | 			hi := num
1291 | 			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1292 | 			for lo < hi {
1293 | 				mid := int(uint(lo + hi) >> 1)
1294 | 				sep_slot := slot_from_slice_raw(branch_slice[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1295 | 				c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1296 | 				if c <= 0 {
1297 | 					lo = mid + 1
1298 | 				} else {
1299 | 					hi = mid
1300 | 				}
1301 | 			}
1302 | 			child_idx := lo - 1
1303 | 			node_ptr = slot_from_slice_raw(branch_slice[child_idx * SLOT_LENGTH : (child_idx + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1304 | 			continue
1305 | 		}
1306 | 
1307 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1308 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1309 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1310 | 		kind_int := header_bytes[0]
1311 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1312 | 			return nil, .Invalid_BTree_Node_Kind
1313 | 		}
1314 | 		num := int(header_bytes[1])
1315 | 		if num > BTREE_SLOT_COUNT {
1316 | 			return nil, .Invalid_BTree_Node
1317 | 		}
1318 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1319 | 			entries_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1320 | 			if num > 0 {
1321 | 				core_read_exact(db.core, entries_buf[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1322 | 			}
1323 | 			lo := 0
1324 | 			hi := num
1325 | 			for lo < hi {
1326 | 				mid := int(uint(lo + hi) >> 1)
1327 | 				entry_slot := slot_from_slice_raw(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1328 | 				key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1329 | 				cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1330 | 				if cmp == 0 {
1331 | 					entry_pos := node_ptr + BTREE_NODE_HEADER_SIZE + i64(mid) * SLOT_LENGTH
1332 | 					return Sorted_Slot{slot = entry_slot, key_slot = key_slot, position = entry_pos}, nil
1333 | 				} else if cmp < 0 {
1334 | 					lo = mid + 1
1335 | 				} else {
1336 | 					hi = mid
1337 | 				}
1338 | 			}
1339 | 			return nil, nil
1340 | 		}
1341 | 		branch_buf: [SLOT_LENGTH * 2 * BTREE_SLOT_COUNT]u8 = ---
1342 | 		core_read_exact(db.core, branch_buf[:(BTREE_SLOT_COUNT + num) * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1343 | 		lo := 1
1344 | 		hi := num
1345 | 		sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1346 | 		for lo < hi {
1347 | 			mid := int(uint(lo + hi) >> 1)
1348 | 			sep_slot := slot_from_slice_raw(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1349 | 			c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1350 | 			if c <= 0 {
1351 | 				lo = mid + 1
1352 | 			} else {
1353 | 				hi = mid
1354 | 			}
1355 | 		}
1356 | 		child_idx := lo - 1
1357 | 		node_ptr = slot_from_slice_raw(branch_buf[child_idx * SLOT_LENGTH : (child_idx + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1358 | 	}
1359 | }
```

#### [`write_sorted_pair`](../../xitdb/btree.odin#L1591-L1597) — `DEPTH 5` (`L1591–L1597`)

```odin
1591 | write_sorted_pair :: proc(db: ^Database, key_slot: Slot) -> (res: Slot, err: Error) {
1592 | 	return write_kv_pair(db, .Sorted_KV_Pair, Key_Value_Pair{  // <== [calls write_kv_pair]
1593 | 		value_slot = Slot{},
1594 | 		key_slot   = key_slot,
1595 | 		hash       = nil,
1596 | 	})
1597 | }
```

#### [`write_sorted_key_and_entry`](../../xitdb/btree.odin#L1599-L1652) — `DEPTH 5` (`L1599–L1652`)

```odin
1599 | write_sorted_key_and_entry :: proc(db: ^Database, key: []u8, key_only: bool) -> (key_slot: Slot, entry: Slot, err: Error) {
1600 | 	if len(key) <= 8 {
1601 | 		has_zero := false
1602 | 		for b in key {
1603 | 			if b == 0 {
1604 | 				has_zero = true
1605 | 				break
1606 | 			}
1607 | 		}
1608 | 		if !has_zero {
1609 | 			value: [8]u8
1610 | 			copy(value[:], key)
1611 | 			key_slot = Slot{value = i64(endian.unchecked_get_u64be(value[:])), tag = .Short_Bytes}
1612 | 			if key_only {
1613 | 				return key_slot, key_slot, nil
1614 | 			}
1615 | 			entry = write_sorted_pair(db, key_slot) or_return  // <== [calls write_sorted_pair]
1616 | 			return key_slot, entry, nil
1617 | 		}
1618 | 	}
1619 | 	pos := core_length(db.core) or_return  // <== [calls core_length]
1620 | 	core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
1621 | 	key_slot = Slot{value = pos, tag = .Bytes}
1622 | 	if key_only {
1623 | 		if len(key) <= 248 {
1624 | 			buf: [256]u8 = ---
1625 | 			endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
1626 | 			copy(buf[8:8 + len(key)], key)
1627 | 			core_write_all(db.core, buf[:8 + len(key)]) or_return  // <== [calls core_write_all]
1628 | 			return key_slot, key_slot, nil
1629 | 		}
1630 | 		core_write_i64(db.core, i64(len(key))) or_return  // <== [calls core_write_i64]
1631 | 		core_write_all(db.core, key) or_return  // <== [calls core_write_all]
1632 | 		return key_slot, key_slot, nil
1633 | 	}
1634 | 	pair_pos := pos + 8 + i64(len(key))
1635 | 	entry = Slot{value = pair_pos, tag = .Sorted_KV_Pair}
1636 | 	if len(key) <= 230 {
1637 | 		buf: [256]u8 = ---
1638 | 		endian.unchecked_put_u64be(buf[0:8], u64(len(key)))
1639 | 		copy(buf[8 : 8 + len(key)], key)
1640 | 		ks_bytes := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1641 | 		vs_bytes := slot_to_bytes(Slot{})  // <== [calls slot_to_bytes]
1642 | 		pair_off := 8 + len(key)
1643 | 		copy(buf[pair_off : pair_off + SLOT_LENGTH], ks_bytes[:])
1644 | 		copy(buf[pair_off + SLOT_LENGTH : pair_off + SORTED_KV_PAIR_LENGTH], vs_bytes[:])
1645 | 		core_write_all(db.core, buf[:pair_off + SORTED_KV_PAIR_LENGTH]) or_return  // <== [calls core_write_all]
1646 | 		return key_slot, entry, nil
1647 | 	}
1648 | 	core_write_i64(db.core, i64(len(key))) or_return  // <== [calls core_write_i64]
1649 | 	core_write_all(db.core, key) or_return  // <== [calls core_write_all]
1650 | 	entry = write_sorted_pair(db, key_slot) or_return  // <== [calls write_sorted_pair]
1651 | 	return key_slot, entry, nil
1652 | }
```

#### [`sorted_put`](../../xitdb/btree.odin#L1654-L2027) — `DEPTH 4` (`L1654–L2027`)

```odin
1654 | sorted_put :: proc(db: ^Database, node_ptr: i64, key: []u8, key_only: bool, frozen_at: i64) -> (res: Sorted_Insert_Result, err: Error) {
1655 | 	reusable := btree_reusable(db, node_ptr, frozen_at)  // <== [calls btree_reusable]
1656 | 	if reusable {
1657 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1658 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8
1659 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1660 | 		kind_int := header_bytes[0]
1661 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1662 | 			return {}, .Invalid_BTree_Node_Kind
1663 | 		}
1664 | 		num := int(header_bytes[1])
1665 | 		if num > BTREE_SLOT_COUNT {
1666 | 			return {}, .Invalid_BTree_Node
1667 | 		}
1668 | 		position := node_ptr + BTREE_NODE_HEADER_SIZE
1669 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1670 | 			entries_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1671 | 			if num > 0 {
1672 | 				core_read_exact(db.core, entries_buf[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1673 | 			}
1674 | 			lo := 0
1675 | 			hi := num
1676 | 			matched_slot: Slot
1677 | 			found := false
1678 | 			for lo < hi {
1679 | 				mid := int(uint(lo + hi) >> 1)
1680 | 				entry_slot := slot_from_slice_raw(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1681 | 				key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1682 | 				cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1683 | 				if cmp == 0 {
1684 | 					lo = mid
1685 | 					matched_slot = entry_slot
1686 | 					found = true
1687 | 					break
1688 | 				} else if cmp < 0 {
1689 | 					lo = mid + 1
1690 | 				} else {
1691 | 					hi = mid
1692 | 				}
1693 | 			}
1694 | 			if found {
1695 | 				if key_only {
1696 | 					return Sorted_Insert_Result{
1697 | 						node_ptr = node_ptr,
1698 | 						count    = i64(num),
1699 | 						entry    = matched_slot,
1700 | 						added    = false,
1701 | 					}, nil
1702 | 				}
1703 | 				entry := matched_slot
1704 | 				rewritten := false
1705 | 				if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1706 | 					entry = write_sorted_pair(db, entry) or_return  // <== [calls write_sorted_pair]
1707 | 					rewritten = true
1708 | 				} else if !btree_reusable(db, entry.value, frozen_at) {  // <== [calls btree_reusable]
1709 | 					kv := read_kv_pair(db, entry) or_return  // <== [calls read_kv_pair]
1710 | 					entry = write_kv_pair(db, entry.tag, kv) or_return  // <== [calls write_kv_pair]
1711 | 					rewritten = true
1712 | 				}
1713 | 				if rewritten {
1714 | 					entry_pos := position + i64(lo) * SLOT_LENGTH
1715 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1716 | 					core_write_slot(db.core, entry) or_return  // <== [calls core_write_slot]
1717 | 				}
1718 | 				return Sorted_Insert_Result{
1719 | 					node_ptr = node_ptr,
1720 | 					count    = i64(num),
1721 | 					entry    = entry,
1722 | 					added    = false,
1723 | 				}, nil
1724 | 			}
1725 | 			idx := lo
1726 | 			key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return  // <== [calls write_sorted_key_and_entry]
1727 | 			if num < BTREE_SLOT_COUNT {
1728 | 				total := num + 1
1729 | 				entry_pos := position + i64(idx) * SLOT_LENGTH
1730 | 				eb := slot_to_bytes(entry)  // <== [calls slot_to_bytes]
1731 | 				if idx < num {
1732 | 					tail_len := (num - idx) * SLOT_LENGTH
1733 | 					shift_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1734 | 					copy(shift_buf[:SLOT_LENGTH], eb[:])
1735 | 					copy(shift_buf[SLOT_LENGTH : SLOT_LENGTH + tail_len], entries_buf[idx * SLOT_LENGTH : num * SLOT_LENGTH])
1736 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1737 | 					core_write_all(db.core, shift_buf[:SLOT_LENGTH + tail_len]) or_return  // <== [calls core_write_all]
1738 | 				} else {
1739 | 					core_seek_to(db.core, entry_pos) or_return  // <== [calls core_seek_to]
1740 | 					core_write_all(db.core, eb[:]) or_return  // <== [calls core_write_all]
1741 | 				}
1742 | 				new_hdr := [BTREE_NODE_HEADER_SIZE]u8{header_bytes[0], u8(total)}
1743 | 				core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1744 | 				core_write_all(db.core, new_hdr[:]) or_return  // <== [calls core_write_all]
1745 | 				return Sorted_Insert_Result{
1746 | 					node_ptr = node_ptr,
1747 | 					count    = i64(total),
1748 | 					entry    = entry,
1749 | 					added    = true,
1750 | 				}, nil
1751 | 			}
1752 | 			entries: [BTREE_SLOT_COUNT + 1]Slot = ---
1753 | 			for j in 0 ..< idx {
1754 | 				entries[j] = slot_from_slice_raw(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1755 | 			}
1756 | 			entries[idx] = entry
1757 | 			for j in idx ..< num {
1758 | 				entries[j + 1] = slot_from_slice_raw(entries_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1759 | 			}
1760 | 			total := num + 1
1761 | 			left_n := BTREE_SPLIT_COUNT
1762 | 			right_n := total - left_n
1763 | 			left := Sorted_Node{kind = .Leaf, num = left_n}
1764 | 			copy(left.entries[:left_n], entries[:left_n])
1765 | 			right := Sorted_Node{kind = .Leaf, num = right_n}
1766 | 			copy(right.entries[:right_n], entries[left_n:total])
1767 | 			separator: Slot
1768 | 			if left_n == idx {
1769 | 				separator = key_slot
1770 | 			} else {
1771 | 				separator = sorted_entry_key_slot(db, entries[left_n]) or_return  // <== [calls sorted_entry_key_slot]
1772 | 			}
1773 | 			left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1774 | 			right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1775 | 			return Sorted_Insert_Result{
1776 | 				node_ptr = left_ptr,
1777 | 				count    = i64(left_n),
1778 | 				entry    = entry,
1779 | 				added    = true,
1780 | 				split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
1781 | 			}, nil
1782 | 		} else {
1783 | 			branch_buf: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
1784 | 			core_read_exact(db.core, branch_buf[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
1785 | 			lo := 1
1786 | 			hi := num
1787 | 			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1788 | 			for lo < hi {
1789 | 				mid := int(uint(lo + hi) >> 1)
1790 | 				sep_slot := slot_from_slice_raw(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1791 | 				c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1792 | 				if c <= 0 {
1793 | 					lo = mid + 1
1794 | 				} else {
1795 | 					hi = mid
1796 | 				}
1797 | 			}
1798 | 			i := lo - 1
1799 | 			child_slot_pos := position + i64(i) * SLOT_LENGTH
1800 | 			child_slot := slot_from_slice_raw(branch_buf[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1801 | 			child_ptr := child_slot.value
1802 | 			child := sorted_put(db, child_ptr, key, key_only, frozen_at) or_return
1803 | 			if child.split == nil {
1804 | 				if child.node_ptr != child_ptr {
1805 | 					core_seek_to(db.core, child_slot_pos) or_return  // <== [calls core_seek_to]
1806 | 					core_write_slot(db.core, Slot{value = child.node_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
1807 | 				}
1808 | 				new_cnt: i64 = 0
1809 | 				if child.added {
1810 | 					counts_off := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + i * 8
1811 | 					old_cnt := i64(endian.unchecked_get_u64be(branch_buf[counts_off : counts_off + 8]))
1812 | 					new_cnt = old_cnt + 1
1813 | 					count_pos := position + i64(counts_off)
1814 | 					core_seek_to(db.core, count_pos) or_return  // <== [calls core_seek_to]
1815 | 					core_write_i64(db.core, new_cnt) or_return  // <== [calls core_write_i64]
1816 | 				}
1817 | 				return Sorted_Insert_Result{
1818 | 					node_ptr = node_ptr,
1819 | 					count    = new_cnt,
1820 | 					entry    = child.entry,
1821 | 					added    = child.added,
1822 | 				}, nil
1823 | 			}
1824 | 			// Child split: decode full branch node from branch_buf and finish split handling
1825 | 			children: [BTREE_SLOT_COUNT + 1]Slot = ---
1826 | 			separators: [BTREE_SLOT_COUNT + 1]Slot = ---
1827 | 			counts: [BTREE_SLOT_COUNT + 1]i64 = ---
1828 | 			counts_base := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1829 | 			for k in 0 ..< num {
1830 | 				children[k] = slot_from_slice_raw(branch_buf[k * SLOT_LENGTH : (k + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1831 | 				separators[k] = slot_from_slice_raw(branch_buf[sep_off + k * SLOT_LENGTH : sep_off + (k + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1832 | 				counts[k] = i64(endian.unchecked_get_u64be(branch_buf[counts_base + k * 8 : counts_base + (k + 1) * 8]))
1833 | 			}
1834 | 			children[i] = Slot{value = child.node_ptr, tag = .Index}
1835 | 			counts[i] = child.count
1836 | 			split := child.split.?
1837 | 			for j := num; j > i + 1; j -= 1 {
1838 | 				children[j] = children[j - 1]
1839 | 				separators[j] = separators[j - 1]
1840 | 				counts[j] = counts[j - 1]
1841 | 			}
1842 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
1843 | 			separators[i + 1] = split.separator
1844 | 			counts[i + 1] = split.count
1845 | 			total := num + 1
1846 | 
1847 | 			if total <= BTREE_SLOT_COUNT {
1848 | 				branch := Sorted_Node{kind = .Branch, num = total}
1849 | 				copy(branch.children[:total], children[:total])
1850 | 				copy(branch.separators[:total], separators[:total])
1851 | 				copy(branch.counts[:total], counts[:total])
1852 | 				ptr := sorted_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1853 | 				return Sorted_Insert_Result{
1854 | 					node_ptr = ptr,
1855 | 					count    = sorted_node_subtree_count(branch),  // <== [calls sorted_node_subtree_count]
1856 | 					entry    = child.entry,
1857 | 					added    = child.added,
1858 | 				}, nil
1859 | 			}
1860 | 
1861 | 			left_n := BTREE_SPLIT_COUNT
1862 | 			right_n := total - left_n
1863 | 			left := Sorted_Node{kind = .Branch, num = left_n}
1864 | 			copy(left.children[:left_n], children[:left_n])
1865 | 			copy(left.separators[:left_n], separators[:left_n])
1866 | 			copy(left.counts[:left_n], counts[:left_n])
1867 | 			right := Sorted_Node{kind = .Branch, num = right_n}
1868 | 			copy(right.children[:right_n], children[left_n:total])
1869 | 			copy(right.separators[:right_n], separators[left_n:total])
1870 | 			copy(right.counts[:right_n], counts[left_n:total])
1871 | 			separator := separators[left_n]
1872 | 			left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1873 | 			right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1874 | 			return Sorted_Insert_Result{
1875 | 				node_ptr = left_ptr,
1876 | 				count    = sorted_node_subtree_count(left),  // <== [calls sorted_node_subtree_count]
1877 | 				entry    = child.entry,
1878 | 				added    = child.added,
1879 | 				split    = Sorted_Split{node_ptr = right_ptr, count = sorted_node_subtree_count(right), separator = separator},  // <== [calls sorted_node_subtree_count]
1880 | 			}, nil
1881 | 		}
1882 | 	}
1883 | 
1884 | 	node := read_sorted_node(db, node_ptr) or_return  // <== [calls read_sorted_node]
1885 | 	switch node.kind {
1886 | 	case .Leaf:
1887 | 		idx, found := sorted_leaf_search(db, &node, key) or_return  // <== [calls sorted_leaf_search]
1888 | 
1889 | 		if found {
1890 | 			if key_only {
1891 | 				return Sorted_Insert_Result{
1892 | 					node_ptr = node_ptr,
1893 | 					count    = i64(node.num),
1894 | 					entry    = node.entries[idx],
1895 | 					added    = false,
1896 | 				}, nil
1897 | 			}
1898 | 			entry := node.entries[idx]
1899 | 			if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1900 | 				entry = write_sorted_pair(db, entry) or_return  // <== [calls write_sorted_pair]
1901 | 			} else if !btree_reusable(db, entry.value, frozen_at) {  // <== [calls btree_reusable]
1902 | 				kv := read_kv_pair(db, entry) or_return  // <== [calls read_kv_pair]
1903 | 				entry = write_kv_pair(db, entry.tag, kv) or_return  // <== [calls write_kv_pair]
1904 | 			}
1905 | 			leaf := node
1906 | 			leaf.entries[idx] = entry
1907 | 			ptr := sorted_write_node(db, leaf, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1908 | 			return Sorted_Insert_Result{
1909 | 				node_ptr = ptr,
1910 | 				count    = i64(node.num),
1911 | 				entry    = entry,
1912 | 				added    = false,
1913 | 			}, nil
1914 | 		}
1915 | 
1916 | 		key_slot, entry := write_sorted_key_and_entry(db, key, key_only) or_return  // <== [calls write_sorted_key_and_entry]
1917 | 		entries: [BTREE_SLOT_COUNT + 1]Slot
1918 | 		copy(entries[:idx], node.entries[:idx])
1919 | 		entries[idx] = entry
1920 | 		copy(entries[idx + 1 : node.num + 1], node.entries[idx:node.num])
1921 | 		total := node.num + 1
1922 | 
1923 | 		if total <= BTREE_SLOT_COUNT {
1924 | 			leaf := Sorted_Node{kind = .Leaf, num = total}
1925 | 			copy(leaf.entries[:total], entries[:total])
1926 | 			ptr := sorted_write_node(db, leaf, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1927 | 			return Sorted_Insert_Result{
1928 | 				node_ptr = ptr,
1929 | 				count    = i64(total),
1930 | 				entry    = entry,
1931 | 				added    = true,
1932 | 			}, nil
1933 | 		}
1934 | 
1935 | 		left_n := BTREE_SPLIT_COUNT
1936 | 		right_n := total - left_n
1937 | 		left := Sorted_Node{kind = .Leaf, num = left_n}
1938 | 		copy(left.entries[:left_n], entries[:left_n])
1939 | 		right := Sorted_Node{kind = .Leaf, num = right_n}
1940 | 		copy(right.entries[:right_n], entries[left_n:total])
1941 | 		separator: Slot
1942 | 		if left_n == idx {
1943 | 			separator = key_slot
1944 | 		} else {
1945 | 			separator = sorted_entry_key_slot(db, entries[left_n]) or_return  // <== [calls sorted_entry_key_slot]
1946 | 		}
1947 | 		left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1948 | 		right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
1949 | 		return Sorted_Insert_Result{
1950 | 			node_ptr = left_ptr,
1951 | 			count    = i64(left_n),
1952 | 			entry    = entry,
1953 | 			added    = true,
1954 | 			split    = Sorted_Split{node_ptr = right_ptr, count = i64(right_n), separator = separator},
1955 | 		}, nil
1956 | 
1957 | 	case .Branch:
1958 | 		i := sorted_branch_search(db, &node, key) or_return  // <== [calls sorted_branch_search]
1959 | 		child_ptr := node.children[i].value
1960 | 		child := sorted_put(db, child_ptr, key, key_only, frozen_at) or_return
1961 | 		if !child.added && child.node_ptr == child_ptr {
1962 | 			return Sorted_Insert_Result{
1963 | 				node_ptr = node_ptr,
1964 | 				count    = sorted_node_subtree_count(node),  // <== [calls sorted_node_subtree_count]
1965 | 				entry    = child.entry,
1966 | 				added    = false,
1967 | 			}, nil
1968 | 		}
1969 | 
1970 | 		children: [BTREE_SLOT_COUNT + 1]Slot
1971 | 		separators: [BTREE_SLOT_COUNT + 1]Slot
1972 | 		counts: [BTREE_SLOT_COUNT + 1]i64
1973 | 		copy(children[:node.num], node.children[:node.num])
1974 | 		copy(separators[:node.num], node.separators[:node.num])
1975 | 		copy(counts[:node.num], node.counts[:node.num])
1976 | 		children[i] = Slot{value = child.node_ptr, tag = .Index}
1977 | 		counts[i] = child.count if child.split != nil else (node.counts[i] + (1 if child.added else 0))
1978 | 		total := node.num
1979 | 		if split, ok := child.split.?; ok {
1980 | 			for j := node.num; j > i + 1; j -= 1 {
1981 | 				children[j] = children[j - 1]
1982 | 				separators[j] = separators[j - 1]
1983 | 				counts[j] = counts[j - 1]
1984 | 			}
1985 | 			children[i + 1] = Slot{value = split.node_ptr, tag = .Index}
1986 | 			separators[i + 1] = split.separator
1987 | 			counts[i + 1] = split.count
1988 | 			total = node.num + 1
1989 | 		}
1990 | 
1991 | 		if total <= BTREE_SLOT_COUNT {
1992 | 			branch := Sorted_Node{kind = .Branch, num = total}
1993 | 			copy(branch.children[:total], children[:total])
1994 | 			copy(branch.separators[:total], separators[:total])
1995 | 			copy(branch.counts[:total], counts[:total])
1996 | 			ptr := sorted_write_node(db, branch, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
1997 | 			return Sorted_Insert_Result{
1998 | 				node_ptr = ptr,
1999 | 				count    = sorted_node_subtree_count(branch),  // <== [calls sorted_node_subtree_count]
2000 | 				entry    = child.entry,
2001 | 				added    = child.added,
2002 | 			}, nil
2003 | 		}
2004 | 
2005 | 		left_n := BTREE_SPLIT_COUNT
2006 | 		right_n := total - left_n
2007 | 		left := Sorted_Node{kind = .Branch, num = left_n}
2008 | 		copy(left.children[:left_n], children[:left_n])
2009 | 		copy(left.separators[:left_n], separators[:left_n])
2010 | 		copy(left.counts[:left_n], counts[:left_n])
2011 | 		right := Sorted_Node{kind = .Branch, num = right_n}
2012 | 		copy(right.children[:right_n], children[left_n:total])
2013 | 		copy(right.separators[:right_n], separators[left_n:total])
2014 | 		copy(right.counts[:right_n], counts[left_n:total])
2015 | 		separator := separators[left_n]
2016 | 		left_ptr := sorted_write_node(db, left, node_ptr, frozen_at) or_return  // <== [calls sorted_write_node]
2017 | 		right_ptr := write_sorted_node(db, right) or_return  // <== [calls write_sorted_node]
2018 | 		return Sorted_Insert_Result{
2019 | 			node_ptr = left_ptr,
2020 | 			count    = sorted_node_subtree_count(left),  // <== [calls sorted_node_subtree_count]
2021 | 			entry    = child.entry,
2022 | 			added    = child.added,
2023 | 			split    = Sorted_Split{node_ptr = right_ptr, count = sorted_node_subtree_count(right), separator = separator},  // <== [calls sorted_node_subtree_count]
2024 | 		}, nil
2025 | 	}
2026 | 	return {}, .Unreachable
2027 | }
```

#### [`sorted_grow_root`](../../xitdb/btree.odin#L2179-L2190) — `DEPTH 4` (`L2179–L2190`)

```odin
2179 | sorted_grow_root :: proc(db: ^Database, result: Sorted_Insert_Result) -> (res: i64, err: Error) {
2180 | 	if split, ok := result.split.?; ok {
2181 | 		root := Sorted_Node{kind = .Branch, num = 2}
2182 | 		root.children[0] = Slot{value = result.node_ptr, tag = .Index}
2183 | 		root.children[1] = Slot{value = split.node_ptr, tag = .Index}
2184 | 		root.separators[1] = split.separator
2185 | 		root.counts[0] = result.count
2186 | 		root.counts[1] = split.count
2187 | 		return write_sorted_node(db, root)  // <== [calls write_sorted_node]
2188 | 	}
2189 | 	return result.node_ptr, nil
2190 | }
```

#### [`sorted_target_slot`](../../xitdb/btree.odin#L2192-L2209) — `DEPTH 4` (`L2192–L2209`)

```odin
2192 | sorted_target_slot :: proc(db: ^Database, entry: Slot, target: Sorted_Map_Get_Target) -> (res: Slot_Pointer, err: Error) {
2193 | 	switch _ in target {
2194 | 	case Sorted_Map_Get_KV_Pair:
2195 | 		return Slot_Pointer{position = nil, slot = entry}, nil
2196 | 	case Sorted_Map_Get_Key:
2197 | 		key_slot := sorted_entry_key_slot(db, entry) or_return  // <== [calls sorted_entry_key_slot]
2198 | 		return Slot_Pointer{position = nil, slot = key_slot}, nil
2199 | 	case Sorted_Map_Get_Value:
2200 | 		if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
2201 | 			return Slot_Pointer{position = nil, slot = Slot{}}, nil
2202 | 		}
2203 | 		pos := entry.value + database_kv_key_offset(db, entry.tag) + SLOT_LENGTH  // <== [calls database_kv_key_offset]
2204 | 		core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
2205 | 		val_slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
2206 | 		return Slot_Pointer{position = pos, slot = val_slot}, nil
2207 | 	}
2208 | 	return {}, .Unexpected_Tag
2209 | }
```

### `xitdb/collections.odin` (29 procedures · 165 lines: [`L16–L24`](../../xitdb/collections.odin#L16-L24), [`L26–L31`](../../xitdb/collections.odin#L26-L31), [`L37–L39`](../../xitdb/collections.odin#L37-L39), [`L41–L43`](../../xitdb/collections.odin#L41-L43), [`L45–L47`](../../xitdb/collections.odin#L45-L47), [`L53–L55`](../../xitdb/collections.odin#L53-L55), [`L81–L88`](../../xitdb/collections.odin#L81-L88), [`L108–L116`](../../xitdb/collections.odin#L108-L116), [`L133–L135`](../../xitdb/collections.odin#L133-L135), [`L145–L147`](../../xitdb/collections.odin#L145-L147), [`L230–L238`](../../xitdb/collections.odin#L230-L238), [`L240–L245`](../../xitdb/collections.odin#L240-L245), [`L247–L255`](../../xitdb/collections.odin#L247-L255), [`L272–L274`](../../xitdb/collections.odin#L272-L274), [`L284–L286`](../../xitdb/collections.odin#L284-L286), [`L310–L314`](../../xitdb/collections.odin#L310-L314), [`L378–L382`](../../xitdb/collections.odin#L378-L382), [`L384–L390`](../../xitdb/collections.odin#L384-L390), [`L409–L415`](../../xitdb/collections.odin#L409-L415), [`L417–L421`](../../xitdb/collections.odin#L417-L421), [`L423–L428`](../../xitdb/collections.odin#L423-L428), [`L500–L508`](../../xitdb/collections.odin#L500-L508), [`L517–L525`](../../xitdb/collections.odin#L517-L525), [`L554–L556`](../../xitdb/collections.odin#L554-L556), [`L562–L566`](../../xitdb/collections.odin#L562-L566), [`L669–L677`](../../xitdb/collections.odin#L669-L677), [`L710–L712`](../../xitdb/collections.odin#L710-L712), [`L750–L752`](../../xitdb/collections.odin#L750-L752), [`L803–L811`](../../xitdb/collections.odin#L803-L811))

#### [`read_array_list_init`](../../xitdb/collections.odin#L16-L24) — `DEPTH 1` (`L16–L24`)

```odin
  16 | read_array_list_init :: proc(cursor: Read_Cursor) -> (res: Read_Array_List, err: Error) {
  17 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
  18 | 	#partial switch slot_ptr.slot.tag {
  19 | 	case .None, .Array_List:
  20 | 		return Read_Array_List{cursor = cursor}, nil
  21 | 	case:
  22 | 		return {}, .Unexpected_Tag
  23 | 	}
  24 | }
```

#### [`write_array_list_init`](../../xitdb/collections.odin#L26-L31) — `DEPTH 1` (`L26–L31`)

```odin
  26 | write_array_list_init :: proc(cursor: Write_Cursor) -> (res: Write_Array_List, err: Error) {
  27 | 	c := cursor
  28 | 	wc := cursor_write_path(&c, []Path_Part{Array_List_Init{}}) or_return  // <== [calls cursor_write_path]
  29 | 	ra := read_array_list_init(wc.read_cursor) or_return  // <== [calls read_array_list_init]
  30 | 	return Write_Array_List{read_array_list = ra, write_cursor = wc}, nil
  31 | }
```

#### [`array_list_count`](../../xitdb/collections.odin#L37-L39) — `DEPTH 1` (`L37–L39`)

```odin
  37 | array_list_count :: proc(a: Read_Array_List) -> (res: i64, err: Error) {
  38 | 	return cursor_count(a.cursor)  // <== [calls cursor_count]
  39 | }
```

#### [`array_list_get_cursor`](../../xitdb/collections.odin#L41-L43) — `DEPTH 1` (`L41–L43`)

```odin
  41 | array_list_get_cursor :: proc(a: Read_Array_List, index: i64) -> (Maybe(Read_Cursor), Error) {
  42 | 	return cursor_read_path(a.cursor, []Path_Part{Array_List_Get{index = index}})  // <== [calls cursor_read_path]
  43 | }
```

#### [`array_list_get_slot`](../../xitdb/collections.odin#L45-L47) — `DEPTH 1` (`L45–L47`)

```odin
  45 | array_list_get_slot :: proc(a: Read_Array_List, index: i64) -> (Maybe(Slot), Error) {
  46 | 	return cursor_read_path_slot(a.cursor, []Path_Part{Array_List_Get{index = index}})  // <== [calls cursor_read_path_slot]
  47 | }
```

#### [`array_list_iterator_from`](../../xitdb/collections.odin#L53-L55) — `DEPTH 4` (`L53–L55`)

```odin
  53 | array_list_iterator_from :: proc(a: Read_Array_List, index: i64) -> (res: Cursor_Iterator, err: Error) {
  54 | 	return cursor_iterator_array_list_from_index(a.cursor, index)  // <== [calls cursor_iterator_array_list_from_index]
  55 | }
```

#### [`array_list_append_context`](../../xitdb/collections.odin#L81-L88) — `DEPTH 1` (`L81–L88`)

```odin
  81 | array_list_append_context :: proc(a: ^Write_Array_List, data: Writeable_Data, fn: Context_Function, user_data: rawptr = nil) -> Error {
  82 | 	_, err := cursor_write_path(&a.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
  83 | 		Array_List_Append{},
  84 | 		Write_Data{data = data},
  85 | 		Context{function = fn, user_data = user_data},
  86 | 	})
  87 | 	return err
  88 | }
```

#### [`read_linked_array_list_init`](../../xitdb/collections.odin#L108-L116) — `DEPTH 2` (`L108–L116`)

```odin
 108 | read_linked_array_list_init :: proc(cursor: Read_Cursor) -> (res: Read_Linked_Array_List, err: Error) {
 109 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 110 | 	#partial switch slot_ptr.slot.tag {
 111 | 	case .None, .Linked_Array_List:
 112 | 		return Read_Linked_Array_List{cursor = cursor}, nil
 113 | 	case:
 114 | 		return {}, .Unexpected_Tag
 115 | 	}
 116 | }
```

#### [`linked_array_list_get_cursor`](../../xitdb/collections.odin#L133-L135) — `DEPTH 2` (`L133–L135`)

```odin
 133 | linked_array_list_get_cursor :: proc(a: Read_Linked_Array_List, index: i64) -> (Maybe(Read_Cursor), Error) {
 134 | 	return cursor_read_path(a.cursor, []Path_Part{Linked_Array_List_Get{index = index}})  // <== [calls cursor_read_path]
 135 | }
```

#### [`linked_array_list_iterator_from`](../../xitdb/collections.odin#L145-L147) — `DEPTH 4` (`L145–L147`)

```odin
 145 | linked_array_list_iterator_from :: proc(a: Read_Linked_Array_List, index: i64) -> (res: Cursor_Iterator, err: Error) {
 146 | 	return cursor_iterator_linked_array_list_from_index(a.cursor, index)  // <== [calls cursor_iterator_linked_array_list_from_index]
 147 | }
```

#### [`read_hash_map_init`](../../xitdb/collections.odin#L230-L238) — `DEPTH 1` (`L230–L238`)

```odin
 230 | read_hash_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Hash_Map, err: Error) {
 231 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 232 | 	#partial switch slot_ptr.slot.tag {
 233 | 	case .None, .Hash_Map, .Hash_Set:
 234 | 		return Read_Hash_Map{cursor = cursor}, nil
 235 | 	case:
 236 | 		return {}, .Unexpected_Tag
 237 | 	}
 238 | }
```

#### [`write_hash_map_init`](../../xitdb/collections.odin#L240-L245) — `ENTRY POINT` (`L240–L245`)

```odin
 240 | write_hash_map_init :: proc(cursor: Write_Cursor) -> (res: Write_Hash_Map, err: Error) {
 241 | 	c := cursor
 242 | 	wc := cursor_write_path(&c, []Path_Part{Hash_Map_Init{counted = false, set = false}}) or_return  // <== [calls cursor_write_path]
 243 | 	rm := read_hash_map_init(wc.read_cursor) or_return  // <== [calls read_hash_map_init]
 244 | 	return Write_Hash_Map{read_hash_map = rm, write_cursor = wc}, nil
 245 | }
```

#### [`read_counted_hash_map_init`](../../xitdb/collections.odin#L247-L255) — `DEPTH 2` (`L247–L255`)

```odin
 247 | read_counted_hash_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Counted_Hash_Map, err: Error) {
 248 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 249 | 	#partial switch slot_ptr.slot.tag {
 250 | 	case .None, .Counted_Hash_Map, .Counted_Hash_Set:
 251 | 		return Read_Counted_Hash_Map{read_hash_map = Read_Hash_Map{cursor = cursor}}, nil
 252 | 	case:
 253 | 		return {}, .Unexpected_Tag
 254 | 	}
 255 | }
```

#### [`hash_map_slot`](../../xitdb/collections.odin#L272-L274) — `ENTRY POINT` (`L272–L274`)

```odin
 272 | hash_map_slot :: proc(m: Read_Hash_Map) -> (res: Slot, err: Error) {
 273 | 	return cursor_slot(m.cursor)  // <== [calls cursor_slot]
 274 | }
```

#### [`hash_map_get_cursor_by_hash`](../../xitdb/collections.odin#L284-L286) — `DEPTH 2` (`L284–L286`)

```odin
 284 | hash_map_get_cursor_by_hash :: proc(m: Read_Hash_Map, hash: []u8) -> (Maybe(Read_Cursor), Error) {
 285 | 	return cursor_read_path(m.cursor, []Path_Part{Hash_Map_Get{target = Hash_Map_Get_Value{hash = hash}}})  // <== [calls cursor_read_path]
 286 | }
```

#### [`hash_map_get_cursor`](../../xitdb/collections.odin#L310-L314) — `DEPTH 1` (`L310–L314`)

```odin
 310 | hash_map_get_cursor :: proc(m: Read_Hash_Map, key: string) -> (Maybe(Read_Cursor), Error) {
 311 | 	buf: [64]u8 = ---
 312 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 313 | 	return hash_map_get_cursor_by_hash(m, hash)  // <== [calls hash_map_get_cursor_by_hash]
 314 | }
```

#### [`hash_map_put_cursor_by_hash`](../../xitdb/collections.odin#L378-L382) — `DEPTH 1` (`L378–L382`)

```odin
 378 | hash_map_put_cursor_by_hash :: proc(m: ^Write_Hash_Map, hash: []u8) -> (res: Write_Cursor, err: Error) {
 379 | 	return cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 380 | 		Hash_Map_Get{target = Hash_Map_Get_Value{hash = hash}},
 381 | 	})
 382 | }
```

#### [`hash_map_put_key_by_hash`](../../xitdb/collections.odin#L384-L390) — `DEPTH 1` (`L384–L390`)

```odin
 384 | hash_map_put_key_by_hash :: proc(m: ^Write_Hash_Map, hash: []u8, data: Writeable_Data) -> Error {
 385 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 386 | 		Hash_Map_Get{target = Hash_Map_Get_Key{hash = hash}},
 387 | 		Write_Data{data = data, if_empty = true},
 388 | 	})
 389 | 	return err
 390 | }
```

#### [`hash_map_put_key_and_value`](../../xitdb/collections.odin#L409-L415) — `DEPTH 1` (`L409–L415`)

```odin
 409 | hash_map_put_key_and_value :: proc(m: ^Write_Hash_Map, hash: []u8, key: Writeable_Data, data: Writeable_Data) -> Error {
 410 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 411 | 		Hash_Map_Get{target = Hash_Map_Get_KV_Pair{hash = hash}},
 412 | 		Write_KV_Data{key = key, value = data},
 413 | 	})
 414 | 	return err
 415 | }
```

#### [`hash_map_put`](../../xitdb/collections.odin#L417-L421) — `ENTRY POINT` (`L417–L421`)

```odin
 417 | hash_map_put :: proc(m: ^Write_Hash_Map, key: string, data: Writeable_Data) -> Error {
 418 | 	buf: [64]u8 = ---
 419 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 420 | 	return hash_map_put_key_and_value(m, hash, key, data)  // <== [calls hash_map_put_key_and_value]
 421 | }
```

#### [`hash_map_put_cursor`](../../xitdb/collections.odin#L423-L428) — `ENTRY POINT` (`L423–L428`)

```odin
 423 | hash_map_put_cursor :: proc(m: ^Write_Hash_Map, key: string) -> (res: Write_Cursor, err: Error) {
 424 | 	buf: [64]u8 = ---
 425 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 426 | 	hash_map_put_key_by_hash(m, hash, key) or_return  // <== [calls hash_map_put_key_by_hash]
 427 | 	return hash_map_put_cursor_by_hash(m, hash)  // <== [calls hash_map_put_cursor_by_hash]
 428 | }
```

#### [`read_hash_set_init`](../../xitdb/collections.odin#L500-L508) — `DEPTH 2` (`L500–L508`)

```odin
 500 | read_hash_set_init :: proc(cursor: Read_Cursor) -> (res: Read_Hash_Set, err: Error) {
 501 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 502 | 	#partial switch slot_ptr.slot.tag {
 503 | 	case .None, .Hash_Map, .Hash_Set:
 504 | 		return Read_Hash_Set{cursor = cursor}, nil
 505 | 	case:
 506 | 		return {}, .Unexpected_Tag
 507 | 	}
 508 | }
```

#### [`read_counted_hash_set_init`](../../xitdb/collections.odin#L517-L525) — `DEPTH 2` (`L517–L525`)

```odin
 517 | read_counted_hash_set_init :: proc(cursor: Read_Cursor) -> (res: Read_Counted_Hash_Set, err: Error) {
 518 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 519 | 	#partial switch slot_ptr.slot.tag {
 520 | 	case .None, .Counted_Hash_Map, .Counted_Hash_Set:
 521 | 		return Read_Counted_Hash_Set{read_hash_set = Read_Hash_Set{cursor = cursor}}, nil
 522 | 	case:
 523 | 		return {}, .Unexpected_Tag
 524 | 	}
 525 | }
```

#### [`hash_set_get_cursor_by_hash`](../../xitdb/collections.odin#L554-L556) — `DEPTH 3` (`L554–L556`)

```odin
 554 | hash_set_get_cursor_by_hash :: proc(s: Read_Hash_Set, hash: []u8) -> (Maybe(Read_Cursor), Error) {
 555 | 	return cursor_read_path(s.cursor, []Path_Part{Hash_Map_Get{target = Hash_Map_Get_Key{hash = hash}}})  // <== [calls cursor_read_path]
 556 | }
```

#### [`hash_set_get_cursor`](../../xitdb/collections.odin#L562-L566) — `DEPTH 2` (`L562–L566`)

```odin
 562 | hash_set_get_cursor :: proc(s: Read_Hash_Set, key: string) -> (Maybe(Read_Cursor), Error) {
 563 | 	buf: [64]u8 = ---
 564 | 	hash := database_digest_string_buf(s.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 565 | 	return hash_set_get_cursor_by_hash(s, hash)  // <== [calls hash_set_get_cursor_by_hash]
 566 | }
```

#### [`read_sorted_map_init`](../../xitdb/collections.odin#L669-L677) — `DEPTH 2` (`L669–L677`)

```odin
 669 | read_sorted_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Sorted_Map, err: Error) {
 670 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 671 | 	#partial switch slot_ptr.slot.tag {
 672 | 	case .None, .Sorted_Map, .Sorted_Set:
 673 | 		return Read_Sorted_Map{cursor = cursor}, nil
 674 | 	case:
 675 | 		return {}, .Unexpected_Tag
 676 | 	}
 677 | }
```

#### [`sorted_map_get_cursor_by_bytes`](../../xitdb/collections.odin#L710-L712) — `DEPTH 3` (`L710–L712`)

```odin
 710 | sorted_map_get_cursor_by_bytes :: proc(m: Read_Sorted_Map, key: []u8) -> (Maybe(Read_Cursor), Error) {
 711 | 	return cursor_read_path(m.cursor, []Path_Part{Sorted_Map_Get{target = Sorted_Map_Get_Value{key = key}}})  // <== [calls cursor_read_path]
 712 | }
```

#### [`sorted_map_get_cursor`](../../xitdb/collections.odin#L750-L752) — `DEPTH 2` (`L750–L752`)

```odin
 750 | sorted_map_get_cursor :: proc(m: Read_Sorted_Map, key: string) -> (Maybe(Read_Cursor), Error) {
 751 | 	return sorted_map_get_cursor_by_bytes(m, transmute([]u8)key)  // <== [calls sorted_map_get_cursor_by_bytes]
 752 | }
```

#### [`read_sorted_set_init`](../../xitdb/collections.odin#L803-L811) — `DEPTH 2` (`L803–L811`)

```odin
 803 | read_sorted_set_init :: proc(cursor: Read_Cursor) -> (res: Read_Sorted_Set, err: Error) {
 804 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 805 | 	#partial switch slot_ptr.slot.tag {
 806 | 	case .None, .Sorted_Map, .Sorted_Set:
 807 | 		return Read_Sorted_Set{cursor = cursor}, nil
 808 | 	case:
 809 | 		return {}, .Unexpected_Tag
 810 | 	}
 811 | }
```

### `xitdb/core.odin` (17 procedures · 395 lines: [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L238–L285`](../../xitdb/core.odin#L238-L285), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437), [`L441–L457`](../../xitdb/core.odin#L441-L457), [`L494–L500`](../../xitdb/core.odin#L494-L500), [`L502–L507`](../../xitdb/core.odin#L502-L507), [`L509–L532`](../../xitdb/core.odin#L509-L532), [`L534–L550`](../../xitdb/core.odin#L534-L550), [`L552–L575`](../../xitdb/core.odin#L552-L575), [`L577–L581`](../../xitdb/core.odin#L577-L581), [`L583–L600`](../../xitdb/core.odin#L583-L600))

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 5` (`L125–L142`)

```odin
 125 | @(private)
 126 | _buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
 127 | 	cached_len := bf.file_len
 128 | 	bf.file_len = nil
 129 | 	os.seek(bf.file.file, pos, .Start) or_return
 130 | 	written := 0
 131 | 	for written < len(data) {
 132 | 		n := os.write(bf.file.file, data[written:]) or_return
 133 | 		if n == 0 {
 134 | 			return io.Error.Short_Write
 135 | 		}
 136 | 		written += n
 137 | 	}
 138 | 	if cl, ok := cached_len.?; ok {
 139 | 		bf.file_len = max(cl, pos + i64(len(data)))
 140 | 	}
 141 | 	return nil
 142 | }
```

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 3` (`L144–L151`)

```odin
 144 | @(private)
 145 | _buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
 146 | 	if len(bf.memory.buf) > bf.flushed_len {
 147 | 		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return  // <== [calls _buffered_write_to_file]
 148 | 		bf.flushed_len = len(bf.memory.buf)
 149 | 	}
 150 | 	return nil
 151 | }
```

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 4` (`L153–L174`)

```odin
 153 | core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
 154 | 	switch &v in c {
 155 | 	case Core_Memory:
 156 | 		return i64(len(v.buf)), nil
 157 | 	case Core_File:
 158 | 		return os.file_size(v.file)
 159 | 	case Core_Buffered_File:
 160 | 		flen: i64
 161 | 		if fl, ok := v.file_len.?; ok {
 162 | 			flen = fl
 163 | 		} else {
 164 | 			flen = os.file_size(v.file.file) or_return
 165 | 			v.file_len = flen
 166 | 		}
 167 | 		buf_size := i64(len(v.memory.buf))
 168 | 		if buf_size == 0 {
 169 | 			return flen, nil
 170 | 		}
 171 | 		return max(v.memory_pos + buf_size, flen), nil
 172 | 	}
 173 | 	return 0, .Invalid_Database
 174 | }
```

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 3` (`L176–L192`)

```odin
 176 | core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
 177 | 	if pos < 0 {
 178 | 		return .Expected_Unsigned_Long
 179 | 	}
 180 | 	switch &v in c {
 181 | 	case Core_Memory:
 182 | 		v.pos = pos
 183 | 		return nil
 184 | 	case Core_File:
 185 | 		os.seek(v.file, pos, .Start) or_return
 186 | 		return nil
 187 | 	case Core_Buffered_File:
 188 | 		v.pos = pos
 189 | 		return nil
 190 | 	}
 191 | 	return .Invalid_Database
 192 | }
```

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 2` (`L219–L236`)

```odin
 219 | core_sync :: proc(c: ^Core) -> Error {
 220 | 	switch &v in c {
 221 | 	case Core_Memory:
 222 | 		return nil
 223 | 	case Core_File:
 224 | 		if !v.fsync {
 225 | 			return nil
 226 | 		}
 227 | 		return os.sync(v.file)
 228 | 	case Core_Buffered_File:
 229 | 		_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 230 | 		if !v.file.fsync {
 231 | 			return nil
 232 | 		}
 233 | 		return os.sync(v.file.file)
 234 | 	}
 235 | 	return .Invalid_Database
 236 | }
```

#### [`core_set_length`](../../xitdb/core.odin#L238-L285) — `DEPTH 4` (`L238–L285`)

```odin
 238 | core_set_length :: proc(c: ^Core, new_len: i64) -> Error {
 239 | 	if new_len < 0 {
 240 | 		return .Expected_Unsigned_Long
 241 | 	}
 242 | 	switch &v in c {
 243 | 	case Core_Memory:
 244 | 		if new_len > i64(len(v.buf)) {
 245 | 			return Xitdb_Error.Invalid_Offset
 246 | 		}
 247 | 		resize(&v.buf, int(new_len))
 248 | 		if v.pos > new_len {
 249 | 			v.pos = new_len
 250 | 		}
 251 | 		return nil
 252 | 	case Core_File:
 253 | 		err := os.truncate(v.file, new_len)
 254 | 		if err != nil {
 255 | 			// Read-only file handles ignore setLength just like Zig/Go xitdb.
 256 | 			return nil
 257 | 		}
 258 | 		pos := os.seek(v.file, 0, .Current) or_return
 259 | 		if pos > new_len {
 260 | 			os.seek(v.file, new_len, .Start) or_return
 261 | 		}
 262 | 		return nil
 263 | 	case Core_Buffered_File:
 264 | 		buf_size := i64(len(v.memory.buf))
 265 | 		if new_len <= v.memory_pos {
 266 | 			clear(&v.memory.buf)
 267 | 			v.flushed_len = 0
 268 | 		} else if new_len < v.memory_pos + buf_size {
 269 | 			new_buf_len := int(new_len - v.memory_pos)
 270 | 			resize(&v.memory.buf, new_buf_len)
 271 | 			if v.flushed_len > new_buf_len {
 272 | 				v.flushed_len = new_buf_len
 273 | 			}
 274 | 		}
 275 | 		v.file_len = nil
 276 | 		if err := os.truncate(v.file.file, new_len); err == nil {
 277 | 			v.file_len = new_len
 278 | 		}
 279 | 		if v.pos > new_len {
 280 | 			v.pos = new_len
 281 | 		}
 282 | 		return nil
 283 | 	}
 284 | 	return .Invalid_Database
 285 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 5` (`L288–L323`)

```odin
 288 | core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
 289 | 	if len(p) == 0 {
 290 | 		return 0, nil
 291 | 	}
 292 | 	switch &v in c {
 293 | 	case Core_Memory:
 294 | 		if v.pos >= i64(len(v.buf)) {
 295 | 			return 0, io.Error.EOF
 296 | 		}
 297 | 		avail := int(i64(len(v.buf)) - v.pos)
 298 | 		to_read := min(len(p), avail)
 299 | 		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
 300 | 		v.pos += i64(to_read)
 301 | 		return to_read, nil
 302 | 	case Core_File:
 303 | 		return os.read(v.file, p)
 304 | 	case Core_Buffered_File:
 305 | 		buf_len := i64(len(v.memory.buf))
 306 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
 307 | 			mem_off := int(v.pos - v.memory_pos)
 308 | 			size := min(len(p), int(buf_len) - mem_off)
 309 | 			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
 310 | 			v.pos += i64(size)
 311 | 			return size, nil
 312 | 		}
 313 | 		os.seek(v.file.file, v.pos, .Start) or_return
 314 | 		max_size := len(p)
 315 | 		if buf_len > 0 && v.pos < v.memory_pos {
 316 | 			max_size = min(len(p), int(v.memory_pos - v.pos))
 317 | 		}
 318 | 		n, err := os.read(v.file.file, p[:max_size])
 319 | 		v.pos += i64(n)
 320 | 		return n, err
 321 | 	}
 322 | 	return 0, .Invalid_Database
 323 | }
```

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 4` (`L326–L359`)

```odin
 326 | core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
 327 | 	if len(p) == 0 {
 328 | 		return nil
 329 | 	}
 330 | 	#partial switch &v in c {
 331 | 	case Core_Memory:
 332 | 		end_pos := v.pos + i64(len(p))
 333 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 334 | 			v.pos = i64(len(v.buf))
 335 | 			return Xitdb_Error.Unexpected_EOF
 336 | 		}
 337 | 		copy(p, v.buf[int(v.pos):int(end_pos)])
 338 | 		v.pos = end_pos
 339 | 		return nil
 340 | 	}
 341 | 	total := 0
 342 | 	for total < len(p) {
 343 | 		n, err := core_read(c, p[total:])  // <== [calls core_read]
 344 | 		total += n
 345 | 		if err != nil {
 346 | 			if err == io.Error.EOF {
 347 | 				if total == len(p) {
 348 | 					return nil
 349 | 				}
 350 | 				return Xitdb_Error.Unexpected_EOF
 351 | 			}
 352 | 			return err
 353 | 		}
 354 | 		if n == 0 {
 355 | 			return Xitdb_Error.Unexpected_EOF
 356 | 		}
 357 | 	}
 358 | 	return nil
 359 | }
```

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 4` (`L362–L437`)

```odin
 362 | core_write_all :: proc(c: ^Core, p: []u8) -> Error {
 363 | 	if len(p) == 0 {
 364 | 		return nil
 365 | 	}
 366 | 	switch &v in c {
 367 | 	case Core_Memory:
 368 | 		old_size := int(len(v.buf))
 369 | 		end_pos := int(v.pos) + len(p)
 370 | 		if end_pos > old_size {
 371 | 			resize(&v.buf, end_pos)
 372 | 		}
 373 | 		copy(v.buf[int(v.pos):end_pos], p)
 374 | 		v.pos = i64(end_pos)
 375 | 		return nil
 376 | 	case Core_File:
 377 | 		written := 0
 378 | 		for written < len(p) {
 379 | 			n := os.write(v.file, p[written:]) or_return
 380 | 			if n == 0 {
 381 | 				return io.Error.Short_Write
 382 | 			}
 383 | 			written += n
 384 | 		}
 385 | 		return nil
 386 | 	case Core_Buffered_File:
 387 | 		n := i64(len(p))
 388 | 		if v.file_len == nil {
 389 | 			fl := os.file_size(v.file.file) or_return
 390 | 			v.file_len = fl
 391 | 		}
 392 | 		buf_size := i64(len(v.memory.buf))
 393 | 		if buf_size > 0 && v.pos + n <= v.memory_pos {
 394 | 			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
 395 | 			// write directly to the file without evicting the hot tail buffer.
 396 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 397 | 			v.pos += n
 398 | 			return nil
 399 | 		}
 400 | 		if buf_size == 0 {
 401 | 			v.memory_pos = v.pos
 402 | 			v.flushed_len = 0
 403 | 		} else if v.pos > v.memory_pos + buf_size ||
 404 | 		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
 405 | 			_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 406 | 			clear(&v.memory.buf)
 407 | 			v.flushed_len = 0
 408 | 			v.memory_pos = v.pos
 409 | 		}
 410 | 		buf_size = i64(len(v.memory.buf))
 411 | 		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
 412 | 			rel_off := int(v.pos - v.memory_pos)
 413 | 			end_off := rel_off + len(p)
 414 | 			if end_off > len(v.memory.buf) {
 415 | 				resize(&v.memory.buf, end_off)
 416 | 			}
 417 | 			copy(v.memory.buf[rel_off:end_off], p)
 418 | 			if rel_off < v.flushed_len {
 419 | 				if end_off <= v.flushed_len {
 420 | 					_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 421 | 				} else {
 422 | 					v.flushed_len = rel_off
 423 | 				}
 424 | 			}
 425 | 		} else {
 426 | 			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
 427 | 				_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 428 | 				clear(&v.memory.buf)
 429 | 				v.flushed_len = 0
 430 | 			}
 431 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 432 | 		}
 433 | 		v.pos += n
 434 | 		return nil
 435 | 	}
 436 | 	return .Invalid_Database
 437 | }
```

#### [`core_slice_at`](../../xitdb/core.odin#L441-L457) — `DEPTH 5` (`L441–L457`)

```odin
 441 | core_slice_at :: #force_inline proc(c: ^Core, pos: i64, n: int) -> (slice: []u8, in_mem: bool, err: Error) {
 442 | 	#partial switch &v in c {
 443 | 	case Core_Memory:
 444 | 		p := int(pos)
 445 | 		if p < 0 || p + n > len(v.buf) {
 446 | 			return nil, true, Xitdb_Error.Unexpected_EOF
 447 | 		}
 448 | 		return v.buf[p : p + n], true, nil
 449 | 	case Core_Buffered_File:
 450 | 		buf_len := i64(len(v.memory.buf))
 451 | 		if buf_len > 0 && pos >= v.memory_pos && pos + i64(n) <= v.memory_pos + buf_len {
 452 | 			mem_off := int(pos - v.memory_pos)
 453 | 			return v.memory.buf[mem_off : mem_off + n], true, nil
 454 | 		}
 455 | 	}
 456 | 	return nil, false, nil
 457 | }
```

#### [`core_read_long`](../../xitdb/core.odin#L494-L500) — `DEPTH 4` (`L494–L500`)

```odin
 494 | core_read_long :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 495 | 	res = core_read_i64(c) or_return  // <== [calls core_read_i64]
 496 | 	if res < 0 {
 497 | 		return 0, Xitdb_Error.Expected_Unsigned_Long
 498 | 	}
 499 | 	return res, nil
 500 | }
```

#### [`core_write_long`](../../xitdb/core.odin#L502-L507) — `DEPTH 4` (`L502–L507`)

```odin
 502 | core_write_long :: #force_inline proc(c: ^Core, v: i64) -> Error {
 503 | 	if v < 0 {
 504 | 		return Xitdb_Error.Expected_Unsigned_Long
 505 | 	}
 506 | 	return core_write_i64(c, v)  // <== [calls core_write_i64]
 507 | }
```

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 5` (`L509–L532`)

```odin
 509 | core_read_i64 :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 510 | 	#partial switch &v in c {
 511 | 	case Core_Memory:
 512 | 		end_pos := v.pos + 8
 513 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 514 | 			v.pos = i64(len(v.buf))
 515 | 			return 0, Xitdb_Error.Unexpected_EOF
 516 | 		}
 517 | 		res = i64(endian.unchecked_get_u64be(v.buf[int(v.pos):int(end_pos)]))
 518 | 		v.pos = end_pos
 519 | 		return res, nil
 520 | 	case Core_Buffered_File:
 521 | 		buf_len := i64(len(v.memory.buf))
 522 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + 8 <= v.memory_pos + buf_len {
 523 | 			mem_off := int(v.pos - v.memory_pos)
 524 | 			res = i64(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
 525 | 			v.pos += 8
 526 | 			return res, nil
 527 | 		}
 528 | 	}
 529 | 	b: [8]u8 = ---
 530 | 	core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
 531 | 	return i64(endian.unchecked_get_u64be(b[:])), nil
 532 | }
```

#### [`core_write_i64`](../../xitdb/core.odin#L534-L550) — `DEPTH 5` (`L534–L550`)

```odin
 534 | core_write_i64 :: #force_inline proc(c: ^Core, v: i64) -> Error {
 535 | 	#partial switch &m in c {
 536 | 	case Core_Memory:
 537 | 		old_size := len(m.buf)
 538 | 		pos := int(m.pos)
 539 | 		end_pos := pos + 8
 540 | 		if end_pos > old_size {
 541 | 			resize(&m.buf, end_pos)
 542 | 		}
 543 | 		endian.unchecked_put_u64be(m.buf[pos:end_pos], u64(v))
 544 | 		m.pos = i64(end_pos)
 545 | 		return nil
 546 | 	}
 547 | 	b: [8]u8 = ---
 548 | 	endian.unchecked_put_u64be(b[:], u64(v))
 549 | 	return core_write_all(c, b[:])  // <== [calls core_write_all]
 550 | }
```

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 3` (`L552–L575`)

```odin
 552 | core_read_slot_raw :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 553 | 	#partial switch &v in c {
 554 | 	case Core_Memory:
 555 | 		end_pos := v.pos + SLOT_LENGTH
 556 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 557 | 			v.pos = i64(len(v.buf))
 558 | 			return {}, Xitdb_Error.Unexpected_EOF
 559 | 		}
 560 | 		s = slot_from_slice_raw(v.buf[int(v.pos):int(end_pos)])  // <== [calls slot_from_slice_raw]
 561 | 		v.pos = end_pos
 562 | 		return s, nil
 563 | 	case Core_Buffered_File:
 564 | 		buf_len := i64(len(v.memory.buf))
 565 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + SLOT_LENGTH <= v.memory_pos + buf_len {
 566 | 			mem_off := int(v.pos - v.memory_pos)
 567 | 			s = slot_from_slice_raw(v.memory.buf[mem_off : mem_off + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
 568 | 			v.pos += SLOT_LENGTH
 569 | 			return s, nil
 570 | 		}
 571 | 	}
 572 | 	buf: [SLOT_LENGTH]u8 = ---
 573 | 	core_read_exact(c, buf[:]) or_return  // <== [calls core_read_exact]
 574 | 	return slot_from_bytes_raw(buf), nil  // <== [calls slot_from_bytes_raw]
 575 | }
```

#### [`core_read_slot`](../../xitdb/core.odin#L577-L581) — `DEPTH 3` (`L577–L581`)

```odin
 577 | core_read_slot :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 578 | 	s = core_read_slot_raw(c) or_return  // <== [calls core_read_slot_raw]
 579 | 	tag_validate(s.tag) or_return  // <== [calls tag_validate]
 580 | 	return s, nil
 581 | }
```

#### [`core_write_slot`](../../xitdb/core.odin#L583-L600) — `DEPTH 3` (`L583–L600`)

```odin
 583 | core_write_slot :: #force_inline proc(c: ^Core, s: Slot) -> Error {
 584 | 	#partial switch &v in c {
 585 | 	case Core_Memory:
 586 | 		old_size := len(v.buf)
 587 | 		pos := int(v.pos)
 588 | 		end_pos := pos + SLOT_LENGTH
 589 | 		if end_pos > old_size {
 590 | 			resize(&v.buf, end_pos)
 591 | 		}
 592 | 		full_bit := u8(0x80) if s.full else u8(0)
 593 | 		v.buf[pos] = full_bit | (u8(s.tag) & 0x7f)
 594 | 		endian.unchecked_put_u64be(v.buf[pos + 1 : end_pos], u64(s.value))
 595 | 		v.pos = i64(end_pos)
 596 | 		return nil
 597 | 	}
 598 | 	buf := slot_to_bytes(s)  // <== [calls slot_to_bytes]
 599 | 	return core_write_all(c, buf[:])  // <== [calls core_write_all]
 600 | }
```

### `xitdb/cursor.odin` (27 procedures · 562 lines: [`L28–L40`](../../xitdb/cursor.odin#L28-L40), [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L58–L61`](../../xitdb/cursor.odin#L58-L61), [`L63–L66`](../../xitdb/cursor.odin#L63-L66), [`L68–L79`](../../xitdb/cursor.odin#L68-L79), [`L81–L95`](../../xitdb/cursor.odin#L81-L95), [`L97–L105`](../../xitdb/cursor.odin#L97-L105), [`L107–L116`](../../xitdb/cursor.odin#L107-L116), [`L118–L174`](../../xitdb/cursor.odin#L118-L174), [`L200–L209`](../../xitdb/cursor.odin#L200-L209), [`L211–L217`](../../xitdb/cursor.odin#L211-L217), [`L219–L225`](../../xitdb/cursor.odin#L219-L225), [`L227–L233`](../../xitdb/cursor.odin#L227-L233), [`L235–L238`](../../xitdb/cursor.odin#L235-L238), [`L240–L295`](../../xitdb/cursor.odin#L240-L295), [`L365–L383`](../../xitdb/cursor.odin#L365-L383), [`L394–L432`](../../xitdb/cursor.odin#L394-L432), [`L648–L668`](../../xitdb/cursor.odin#L648-L668), [`L670–L688`](../../xitdb/cursor.odin#L670-L688), [`L690–L693`](../../xitdb/cursor.odin#L690-L693), [`L695–L721`](../../xitdb/cursor.odin#L695-L721), [`L723–L765`](../../xitdb/cursor.odin#L723-L765), [`L767–L777`](../../xitdb/cursor.odin#L767-L777), [`L951–L986`](../../xitdb/cursor.odin#L951-L986), [`L988–L1048`](../../xitdb/cursor.odin#L988-L1048), [`L1050–L1083`](../../xitdb/cursor.odin#L1050-L1083), [`L1085–L1106`](../../xitdb/cursor.odin#L1085-L1106))

#### [`new_write_cursor`](../../xitdb/cursor.odin#L28-L40) — `DEPTH 2` (`L28–L40`)

```odin
  28 | new_write_cursor :: proc(slot_ptr: Slot_Pointer, db: ^Database) -> Write_Cursor {
  29 | 	c := Write_Cursor{
  30 | 		read_cursor = Read_Cursor{
  31 | 			slot_ptr  = slot_ptr,
  32 | 			db        = db,
  33 | 			frozen_at = 0,
  34 | 		},
  35 | 	}
  36 | 	if slot_ptr.position != nil && !is_root(slot_ptr) {  // <== [calls is_root]
  37 | 		c.transaction = db.transaction
  38 | 	}
  39 | 	return c
  40 | }
```

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 2` (`L46–L56`)

```odin
  46 | cursor_resolved :: proc(c: Read_Cursor) -> (res: Slot_Pointer, err: Error) {
  47 | 	if is_root(c.slot_ptr) {  // <== [calls is_root]
  48 | 		header := database_read_root_header(c.db) or_return  // <== [calls database_read_root_header]
  49 | 		if header.file_size < ROOT_TRAILER_LENGTH {
  50 | 			return {}, .Invalid_Database
  51 | 		}
  52 | 		position := header.file_size - ROOT_TRAILER_LENGTH
  53 | 		return Slot_Pointer{position = position, slot = header.root}, nil
  54 | 	}
  55 | 	return c.slot_ptr, nil
  56 | }
```

#### [`cursor_resolved_cursor`](../../xitdb/cursor.odin#L58-L61) — `DEPTH 4` (`L58–L61`)

```odin
  58 | cursor_resolved_cursor :: proc(c: Read_Cursor) -> (res: Read_Cursor, err: Error) {
  59 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  60 | 	return Read_Cursor{slot_ptr = slot_ptr, db = c.db, frozen_at = c.frozen_at}, nil
  61 | }
```

#### [`cursor_slot`](../../xitdb/cursor.odin#L63-L66) — `DEPTH 1` (`L63–L66`)

```odin
  63 | cursor_slot :: proc(c: Read_Cursor) -> (res: Slot, err: Error) {
  64 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  65 | 	return slot_ptr.slot, nil
  66 | }
```

#### [`cursor_read_path`](../../xitdb/cursor.odin#L68-L79) — `DEPTH 2` (`L68–L79`)

```odin
  68 | cursor_read_path :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Read_Cursor), err: Error) {
  69 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  70 | 	slot_ptr: Slot_Pointer
  71 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  72 | 	if err != nil {
  73 | 		if err == .Key_Not_Found {
  74 | 			return nil, nil
  75 | 		}
  76 | 		return nil, err
  77 | 	}
  78 | 	return Read_Cursor{slot_ptr = slot_ptr, db = c.db}, nil
  79 | }
```

#### [`cursor_read_path_slot`](../../xitdb/cursor.odin#L81-L95) — `DEPTH 2` (`L81–L95`)

```odin
  81 | cursor_read_path_slot :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Slot), err: Error) {
  82 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  83 | 	slot_ptr: Slot_Pointer
  84 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  85 | 	if err != nil {
  86 | 		if err == .Key_Not_Found {
  87 | 			return nil, nil
  88 | 		}
  89 | 		return nil, err
  90 | 	}
  91 | 	if !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
  92 | 		return slot_ptr.slot, nil
  93 | 	}
  94 | 	return nil, nil
  95 | }
```

#### [`cursor_check_writable`](../../xitdb/cursor.odin#L97-L105) — `DEPTH 2` (`L97–L105`)

```odin
  97 | cursor_check_writable :: proc(c: ^Write_Cursor) -> Error {
  98 | 	if c.transaction != nil && c.transaction != c.db.transaction {
  99 | 		return .Expired_Transaction
 100 | 	}
 101 | 	if !is_root(c.slot_ptr) && c.transaction == nil && c.db.tx_start == nil {  // <== [calls is_root]
 102 | 		return .Expected_Tx_Start
 103 | 	}
 104 | 	return database_check_frozen_slot(c.db, c.slot_ptr)  // <== [calls database_check_frozen_slot]
 105 | }
```

#### [`cursor_reload_slot`](../../xitdb/cursor.odin#L107-L116) — `DEPTH 2` (`L107–L116`)

```odin
 107 | cursor_reload_slot :: proc(c: ^Write_Cursor) -> Error {
 108 | 	if (c.transaction != nil || c.db.tx_start != nil) && !is_root(c.slot_ptr) {  // <== [calls is_root]
 109 | 		if pos, ok := c.slot_ptr.position.?; ok {
 110 | 			core_seek_to(c.db.core, pos) or_return  // <== [calls core_seek_to]
 111 | 			slot := core_read_slot(c.db.core) or_return  // <== [calls core_read_slot]
 112 | 			c.slot_ptr = slot_pointer_with_slot(c.slot_ptr, slot)  // <== [calls slot_pointer_with_slot]
 113 | 		}
 114 | 	}
 115 | 	return nil
 116 | }
```

#### [`cursor_write_path`](../../xitdb/cursor.odin#L118-L174) — `DEPTH 1` (`L118–L174`)

```odin
 118 | cursor_write_path :: proc(c: ^Write_Cursor, path: []Path_Part) -> (res: Write_Cursor, err: Error) {
 119 | 	cursor_check_writable(c) or_return  // <== [calls cursor_check_writable]
 120 | 	if (c.db.transaction != nil || c.db.tx_start != nil) && is_root(c.slot_ptr) && len(path) > 0 {  // <== [calls is_root]
 121 | 		return {}, .Nested_Top_Level_Write
 122 | 	}
 123 | 
 124 | 	tx_stack: Transaction
 125 | 	starts_transaction := c.db.transaction == nil && is_root(c.slot_ptr)  // <== [calls is_root]
 126 | 	if starts_transaction {
 127 | 		c.db.transaction = &tx_stack
 128 | 	}
 129 | 	defer if starts_transaction {
 130 | 		c.db.transaction = nil
 131 | 	}
 132 | 
 133 | 	err = nil
 134 | 	switch c.slot_ptr.slot.tag {
 135 | 	case .Array_List, .Linked_Array_List, .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
 136 | 		is_init := false
 137 | 		if len(path) > 0 {
 138 | 			_, is_init = init_tag(path[0])  // <== [calls init_tag]
 139 | 		}
 140 | 		if is_init || (c.db.transaction != nil && (c.db.transaction.frozen_at != nil || c.frozen_at != 0)) {
 141 | 			err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 142 | 		}
 143 | 	case .None, .Index, .Bytes, .Short_Bytes, .Uint, .Int, .Float, .KV_Pair, .Sorted_KV_Pair:
 144 | 		err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 145 | 	}
 146 | 	slot_ptr: Slot_Pointer
 147 | 	if err == nil {
 148 | 		slot_ptr, err = read_slot_pointer(c.db, .Read_Write, path, 0, c.slot_ptr, c.frozen_at)  // <== [calls read_slot_pointer]
 149 | 	}
 150 | 	if err != nil {
 151 | 		if c.db.tx_start == nil {
 152 | 			_ = database_truncate(c.db)  // <== [calls database_truncate]
 153 | 		}
 154 | 		return {}, err
 155 | 	}
 156 | 	if c.db.tx_start == nil {
 157 | 		core_sync(c.db.core) or_return  // <== [calls core_sync]
 158 | 	}
 159 | 	ends_with_ctx := false
 160 | 	if len(path) > 0 {
 161 | 		_, ends_with_ctx = path[len(path) - 1].(Context)
 162 | 	}
 163 | 	res = new_write_cursor(slot_ptr, c.db)  // <== [calls new_write_cursor]
 164 | 	res.frozen_at = c.frozen_at
 165 | 	if ends_with_ctx {
 166 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 167 | 		cursor_reload_slot(&res) or_return  // <== [calls cursor_reload_slot]
 168 | 	} else if c.slot_ptr.position != nil && c.slot_ptr.position == slot_ptr.position {
 169 | 		c.slot_ptr = slot_ptr
 170 | 	} else if c.db.transaction == nil || c.db.transaction.frozen_at != nil || c.frozen_at != 0 || c.slot_ptr.slot.tag == .None {
 171 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 172 | 	}
 173 | 	return res, nil
 174 | }
```

#### [`cursor_read_uint`](../../xitdb/cursor.odin#L200-L209) — `DEPTH 2` (`L200–L209`)

```odin
 200 | cursor_read_uint :: proc(c: Read_Cursor) -> (res: u64, err: Error) {
 201 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 202 | 	if slot_ptr.slot.tag != .Uint {
 203 | 		return 0, .Unexpected_Tag
 204 | 	}
 205 | 	if slot_ptr.slot.value < 0 {
 206 | 		return 0, .Expected_Unsigned_Long
 207 | 	}
 208 | 	return u64(slot_ptr.slot.value), nil
 209 | }
```

#### [`cursor_read_int`](../../xitdb/cursor.odin#L211-L217) — `DEPTH 2` (`L211–L217`)

```odin
 211 | cursor_read_int :: proc(c: Read_Cursor) -> (res: i64, err: Error) {
 212 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 213 | 	if slot_ptr.slot.tag != .Int {
 214 | 		return 0, .Unexpected_Tag
 215 | 	}
 216 | 	return slot_ptr.slot.value, nil
 217 | }
```

#### [`cursor_read_float`](../../xitdb/cursor.odin#L219-L225) — `DEPTH 2` (`L219–L225`)

```odin
 219 | cursor_read_float :: proc(c: Read_Cursor) -> (res: f64, err: Error) {
 220 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 221 | 	if slot_ptr.slot.tag != .Float {
 222 | 		return 0, .Unexpected_Tag
 223 | 	}
 224 | 	return transmute(f64)slot_ptr.slot.value, nil
 225 | }
```

#### [`cursor_read_bytes`](../../xitdb/cursor.odin#L227-L233) — `DEPTH 3` (`L227–L233`)

```odin
 227 | cursor_read_bytes :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: []u8, err: Error) {
 228 | 	obj := cursor_read_bytes_object(c, max_size, allocator) or_return  // <== [calls cursor_read_bytes_object]
 229 | 	if obj.format_tag != nil {
 230 | 		delete(obj.format_tag, allocator)
 231 | 	}
 232 | 	return obj.value, nil
 233 | }
```

#### [`cursor_read_string`](../../xitdb/cursor.odin#L235-L238) — `DEPTH 2` (`L235–L238`)

```odin
 235 | cursor_read_string :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: string, err: Error) {
 236 | 	b := cursor_read_bytes(c, max_size, allocator) or_return  // <== [calls cursor_read_bytes]
 237 | 	return string(b), nil
 238 | }
```

#### [`cursor_read_bytes_object`](../../xitdb/cursor.odin#L240-L295) — `DEPTH 2` (`L240–L295`)

```odin
 240 | cursor_read_bytes_object :: proc(c: Read_Cursor, max_size: i64 = 0, allocator := context.allocator) -> (res: Bytes, err: Error) {
 241 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 242 | 	#partial switch slot_ptr.slot.tag {
 243 | 	case .None:
 244 | 		return Bytes{value = make([]u8, 0, allocator)}, nil
 245 | 
 246 | 	case .Bytes:
 247 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 248 | 		value_size := core_read_long(c.db.core) or_return  // <== [calls core_read_long]
 249 | 		if max_size > 0 && value_size > max_size {
 250 | 			return {}, .Stream_Too_Long
 251 | 		}
 252 | 		value := make([]u8, int(value_size), allocator)
 253 | 		err := core_read_exact(c.db.core, value)  // <== [calls core_read_exact]
 254 | 		if err != nil {
 255 | 			delete(value, allocator)
 256 | 			return {}, err
 257 | 		}
 258 | 		format_tag: []u8
 259 | 		if slot_ptr.slot.full {
 260 | 			format_tag = make([]u8, 2, allocator)
 261 | 			if ft_err := core_read_exact(c.db.core, format_tag); ft_err != nil {  // <== [calls core_read_exact]
 262 | 				delete(value, allocator)
 263 | 				delete(format_tag, allocator)
 264 | 				return {}, ft_err
 265 | 			}
 266 | 		}
 267 | 		return Bytes{value = value, format_tag = format_tag}, nil
 268 | 
 269 | 	case .Short_Bytes:
 270 | 		buf: [8]u8
 271 | 		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
 272 | 		total_size: i64 = 6 if slot_ptr.slot.full else 8
 273 | 		value_size: i64 = 0
 274 | 		for b in buf {
 275 | 			if b == 0 || value_size == total_size {
 276 | 				break
 277 | 			}
 278 | 			value_size += 1
 279 | 		}
 280 | 		if max_size > 0 && value_size > max_size {
 281 | 			return {}, .Stream_Too_Long
 282 | 		}
 283 | 		format_tag: []u8
 284 | 		if slot_ptr.slot.full {
 285 | 			format_tag = make([]u8, 2, allocator)
 286 | 			copy(format_tag, buf[total_size : total_size + 2])
 287 | 		}
 288 | 		value := make([]u8, int(value_size), allocator)
 289 | 		copy(value, buf[:value_size])
 290 | 		return Bytes{value = value, format_tag = format_tag}, nil
 291 | 
 292 | 	case:
 293 | 		return {}, .Unexpected_Tag
 294 | 	}
 295 | }
```

#### [`cursor_read_kv_pair`](../../xitdb/cursor.odin#L365-L383) — `DEPTH 3` (`L365–L383`)

```odin
 365 | cursor_read_kv_pair :: proc(c: Read_Cursor, allocator := context.temp_allocator) -> (res: Read_KV_Pair_Cursor, err: Error) {
 366 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 367 | 	if is_key_only_entry(slot_ptr.slot) {  // <== [calls is_key_only_entry]
 368 | 		return Read_KV_Pair_Cursor{
 369 | 			value_cursor = Read_Cursor{slot_ptr = Slot_Pointer{position = nil, slot = Slot{}}, db = c.db, frozen_at = c.frozen_at},
 370 | 			key_cursor   = Read_Cursor{slot_ptr = Slot_Pointer{position = nil, slot = slot_ptr.slot}, db = c.db, frozen_at = c.frozen_at},
 371 | 			hash         = nil,
 372 | 		}, nil
 373 | 	}
 374 | 	core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 375 | 	kv_pair := decode_kv_pair(c.db.core, slot_ptr.slot.tag, int(c.db.header.hash_size), allocator) or_return  // <== [calls decode_kv_pair]
 376 | 	key_slot_pos := database_kv_key_position(c.db, slot_ptr.slot)  // <== [calls database_kv_key_position]
 377 | 	value_slot_pos := database_kv_value_position(c.db, slot_ptr.slot)  // <== [calls database_kv_value_position]
 378 | 	return Read_KV_Pair_Cursor{
 379 | 		value_cursor = Read_Cursor{slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}, db = c.db, frozen_at = c.frozen_at},
 380 | 		key_cursor   = Read_Cursor{slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}, db = c.db, frozen_at = c.frozen_at},
 381 | 		hash         = kv_pair.hash,
 382 | 	}, nil
 383 | }
```

#### [`cursor_count`](../../xitdb/cursor.odin#L394-L432) — `DEPTH 2` (`L394–L432`)

```odin
 394 | cursor_count :: proc(c: Read_Cursor) -> (res: i64, err: Error) {
 395 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 396 | 	#partial switch slot_ptr.slot.tag {
 397 | 	case .None:
 398 | 		return 0, nil
 399 | 	case .Array_List:
 400 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 401 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 402 | 		core_read_exact(c.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 403 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 404 | 		return header.size, nil
 405 | 	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
 406 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 407 | 		hb: [BTREE_HEADER_LENGTH]u8
 408 | 		core_read_exact(c.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 409 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 410 | 		return header.size, nil
 411 | 	case .Bytes:
 412 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 413 | 		return core_read_long(c.db.core)  // <== [calls core_read_long]
 414 | 	case .Short_Bytes:
 415 | 		buf: [8]u8
 416 | 		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
 417 | 		total_size := 6 if slot_ptr.slot.full else 8
 418 | 		size := 0
 419 | 		for b in buf {
 420 | 			if b == 0 || size == total_size {
 421 | 				break
 422 | 			}
 423 | 			size += 1
 424 | 		}
 425 | 		return i64(size), nil
 426 | 	case .Counted_Hash_Map, .Counted_Hash_Set:
 427 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 428 | 		return core_read_long(c.db.core)  // <== [calls core_read_long]
 429 | 	case:
 430 | 		return 0, .Unexpected_Tag
 431 | 	}
 432 | }
```

#### [`_fill_slot_block_from`](../../xitdb/cursor.odin#L648-L668) — `DEPTH 5` (`L648–L668`)

```odin
 648 | @(private)
 649 | _fill_slot_block_from :: proc(cursor: Read_Cursor, position: i64, start_idx: int, end_idx: int, level: ^Iter_Level) -> Error {
 650 | 	level.position = position
 651 | 	level.index = u8(start_idx)
 652 | 	level.count = u8(end_idx)
 653 | 	rem_slots := end_idx - start_idx
 654 | 	if rem_slots <= 0 {
 655 | 		return nil
 656 | 	}
 657 | 	core_seek_to(cursor.db.core, position + i64(start_idx) * SLOT_LENGTH) or_return  // <== [calls core_seek_to]
 658 | 	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 659 | 	core_read_exact(cursor.db.core, index_block_bytes[:rem_slots * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 660 | 	for j in 0 ..< rem_slots {
 661 | 		sb: [SLOT_LENGTH]u8 = ---
 662 | 		copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 663 | 		s := slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 664 | 		tag_validate(s.tag) or_return  // <== [calls tag_validate]
 665 | 		level.block[start_idx + j] = s
 666 | 	}
 667 | 	return nil
 668 | }
```

#### [`_fill_slot_block_raw_from`](../../xitdb/cursor.odin#L670-L688) — `DEPTH 6` (`L670–L688`)

```odin
 670 | @(private)
 671 | _fill_slot_block_raw_from :: proc(cursor: Read_Cursor, position: i64, start_idx: int, end_idx: int, level: ^Iter_Level) -> Error {
 672 | 	level.position = position
 673 | 	level.index = u8(start_idx)
 674 | 	level.count = u8(end_idx)
 675 | 	rem_slots := end_idx - start_idx
 676 | 	if rem_slots <= 0 {
 677 | 		return nil
 678 | 	}
 679 | 	core_seek_to(cursor.db.core, position + i64(start_idx) * SLOT_LENGTH) or_return  // <== [calls core_seek_to]
 680 | 	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 681 | 	core_read_exact(cursor.db.core, index_block_bytes[:rem_slots * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 682 | 	for j in 0 ..< rem_slots {
 683 | 		sb: [SLOT_LENGTH]u8 = ---
 684 | 		copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 685 | 		level.block[start_idx + j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 686 | 	}
 687 | 	return nil
 688 | }
```

#### [`_init_iter_level`](../../xitdb/cursor.odin#L690-L693) — `DEPTH 4` (`L690–L693`)

```odin
 690 | @(private)
 691 | _init_iter_level :: proc(cursor: Read_Cursor, position: i64, level: ^Iter_Level) -> Error {
 692 | 	return _fill_slot_block_from(cursor, position, 0, SLOT_COUNT, level)  // <== [calls _fill_slot_block_from]
 693 | }
```

#### [`_init_btree_iter_level`](../../xitdb/cursor.odin#L695-L721) — `DEPTH 4` (`L695–L721`)

```odin
 695 | @(private)
 696 | _init_btree_iter_level :: proc(cursor: Read_Cursor, node_ptr: i64, level: ^Iter_Level) -> Error {
 697 | 	core_seek_to(cursor.db.core, node_ptr) or_return  // <== [calls core_seek_to]
 698 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
 699 | 	core_read_exact(cursor.db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 700 | 	if header_bytes[0] > u8(BTree_Node_Kind.Branch) {
 701 | 		return .Invalid_BTree_Node_Kind
 702 | 	}
 703 | 	num := int(header_bytes[1])
 704 | 	if num > BTREE_SLOT_COUNT {
 705 | 		return .Invalid_BTree_Node
 706 | 	}
 707 | 	position := node_ptr + BTREE_NODE_HEADER_SIZE
 708 | 	level.position = position
 709 | 	level.index = 0
 710 | 	level.count = u8(num)
 711 | 	if num > 0 {
 712 | 		index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 713 | 		core_read_exact(cursor.db.core, index_block_bytes[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 714 | 		for j in 0 ..< num {
 715 | 			sb: [SLOT_LENGTH]u8 = ---
 716 | 			copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 717 | 			level.block[j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 718 | 		}
 719 | 	}
 720 | 	return nil
 721 | }
```

#### [`cursor_iterator`](../../xitdb/cursor.odin#L723-L765) — `DEPTH 3` (`L723–L765`)

```odin
 723 | cursor_iterator :: proc(unresolved_cursor: Read_Cursor) -> (res: Cursor_Iterator, err: Error) {
 724 | 	cursor := cursor_resolved_cursor(unresolved_cursor) or_return  // <== [calls cursor_resolved_cursor]
 725 | 	res.cursor = cursor
 726 | 
 727 | 	#partial switch cursor.slot_ptr.slot.tag {
 728 | 	case .None:
 729 | 		res.size = 0
 730 | 		res.index = 0
 731 | 	case .Array_List:
 732 | 		position := cursor.slot_ptr.slot.value
 733 | 		core_seek_to(cursor.db.core, position) or_return  // <== [calls core_seek_to]
 734 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
 735 | 		core_read_exact(cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 736 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 737 | 		res.size = header.size
 738 | 		res.index = 0
 739 | 		_init_iter_level(cursor, header.ptr, &res.stack[0]) or_return  // <== [calls _init_iter_level]
 740 | 		res.stack_len = 1
 741 | 	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
 742 | 		position := cursor.slot_ptr.slot.value
 743 | 		core_seek_to(cursor.db.core, position) or_return  // <== [calls core_seek_to]
 744 | 		hb: [BTREE_HEADER_LENGTH]u8 = ---
 745 | 		core_read_exact(cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 746 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 747 | 		res.size = header.size
 748 | 		res.index = 0
 749 | 		_init_btree_iter_level(cursor, header.root_ptr, &res.stack[0]) or_return  // <== [calls _init_btree_iter_level]
 750 | 		res.stack_len = 1
 751 | 	case .Hash_Map, .Hash_Set:
 752 | 		res.size = 0
 753 | 		res.index = 0
 754 | 		_init_iter_level(cursor, cursor.slot_ptr.slot.value, &res.stack[0]) or_return  // <== [calls _init_iter_level]
 755 | 		res.stack_len = 1
 756 | 	case .Counted_Hash_Map, .Counted_Hash_Set:
 757 | 		res.size = 0
 758 | 		res.index = 0
 759 | 		_init_iter_level(cursor, cursor.slot_ptr.slot.value + 8, &res.stack[0]) or_return  // <== [calls _init_iter_level]
 760 | 		res.stack_len = 1
 761 | 	case:
 762 | 		return {}, .Unexpected_Tag
 763 | 	}
 764 | 	return res, nil
 765 | }
```

#### [`_resolve_start_index`](../../xitdb/cursor.odin#L767-L777) — `DEPTH 6` (`L767–L777`)

```odin
 767 | @(private)
 768 | _resolve_start_index :: proc(index: i64, size: i64) -> (res: i64, err: bool) {
 769 | 	resolved := index
 770 | 	if index < 0 {
 771 | 		resolved = index + size
 772 | 	}
 773 | 	if resolved < 0 || resolved >= size {
 774 | 		return 0, false
 775 | 	}
 776 | 	return resolved, true
 777 | }
```

#### [`cursor_iterator_array_list_from_index`](../../xitdb/cursor.odin#L951-L986) — `DEPTH 5` (`L951–L986`)

```odin
 951 | cursor_iterator_array_list_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
 952 | 	cursor := cursor_resolved_cursor(unresolved_cursor) or_return  // <== [calls cursor_resolved_cursor]
 953 | 	res.cursor = cursor
 954 | 	#partial switch cursor.slot_ptr.slot.tag {
 955 | 	case .None:
 956 | 		return res, nil
 957 | 	case .Array_List:
 958 | 	case:
 959 | 		return {}, .Unexpected_Tag
 960 | 	}
 961 | 	core_seek_to(cursor.db.core, cursor.slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 962 | 	hb: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
 963 | 	core_read_exact(cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 964 | 	header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 965 | 	idx, ok := _resolve_start_index(start_index, header.size)  // <== [calls _resolve_start_index]
 966 | 	if !ok {
 967 | 		return res, nil
 968 | 	}
 969 | 	shift := radix_shift(header.size - 1)  // <== [calls radix_shift]
 970 | 	pos := header.ptr
 971 | 	sh := shift
 972 | 	for {
 973 | 		i := int((idx >> (u64(sh) * BIT_COUNT)) & i64(MASK))
 974 | 		level := &res.stack[res.stack_len]
 975 | 		_fill_slot_block_from(cursor, pos, i, SLOT_COUNT, level) or_return  // <== [calls _fill_slot_block_from]
 976 | 		res.stack_len += 1
 977 | 		if sh == 0 {
 978 | 			break
 979 | 		}
 980 | 		pos = level.block[i].value
 981 | 		sh -= 1
 982 | 	}
 983 | 	res.size = header.size
 984 | 	res.index = idx
 985 | 	return res, nil
 986 | }
```

#### [`cursor_iterator_linked_array_list_from_index`](../../xitdb/cursor.odin#L988-L1048) — `DEPTH 5` (`L988–L1048`)

```odin
 988 | cursor_iterator_linked_array_list_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
 989 | 	cursor := cursor_resolved_cursor(unresolved_cursor) or_return  // <== [calls cursor_resolved_cursor]
 990 | 	res.cursor = cursor
 991 | 	#partial switch cursor.slot_ptr.slot.tag {
 992 | 	case .None:
 993 | 		return res, nil
 994 | 	case .Linked_Array_List:
 995 | 	case:
 996 | 		return {}, .Unexpected_Tag
 997 | 	}
 998 | 	core_seek_to(cursor.db.core, cursor.slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 999 | 	hb: [BTREE_HEADER_LENGTH]u8 = ---
1000 | 	core_read_exact(cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
1001 | 	header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
1002 | 	idx, ok := _resolve_start_index(start_index, header.size)  // <== [calls _resolve_start_index]
1003 | 	if !ok {
1004 | 		return res, nil
1005 | 	}
1006 | 	node_ptr := header.root_ptr
1007 | 	rem := idx
1008 | 	for {
1009 | 		core_seek_to(cursor.db.core, node_ptr) or_return  // <== [calls core_seek_to]
1010 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1011 | 		core_read_exact(cursor.db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1012 | 		kind_int := header_bytes[0]
1013 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1014 | 			return {}, .Invalid_BTree_Node_Kind
1015 | 		}
1016 | 		num := int(header_bytes[1])
1017 | 		if num > BTREE_SLOT_COUNT {
1018 | 			return {}, .Invalid_BTree_Node
1019 | 		}
1020 | 		position := node_ptr + BTREE_NODE_HEADER_SIZE
1021 | 		level := &res.stack[res.stack_len]
1022 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1023 | 			r := int(rem)
1024 | 			_fill_slot_block_raw_from(cursor, position, r, num, level) or_return  // <== [calls _fill_slot_block_raw_from]
1025 | 			res.stack_len += 1
1026 | 			break
1027 | 		}
1028 | 		counts_pos := position + SLOT_LENGTH * BTREE_SLOT_COUNT
1029 | 		core_seek_to(cursor.db.core, counts_pos) or_return  // <== [calls core_seek_to]
1030 | 		counts_buf: [8 * BTREE_SLOT_COUNT]u8 = ---
1031 | 		core_read_exact(cursor.db.core, counts_buf[:num * 8]) or_return  // <== [calls core_read_exact]
1032 | 		i := 0
1033 | 		for i + 1 < num {
1034 | 			cnt := i64(endian.unchecked_get_u64be(counts_buf[i * 8 : i * 8 + 8]))
1035 | 			if rem < cnt {
1036 | 				break
1037 | 			}
1038 | 			rem -= cnt
1039 | 			i += 1
1040 | 		}
1041 | 		_fill_slot_block_raw_from(cursor, position, i, num, level) or_return  // <== [calls _fill_slot_block_raw_from]
1042 | 		res.stack_len += 1
1043 | 		node_ptr = level.block[i].value
1044 | 	}
1045 | 	res.size = header.size
1046 | 	res.index = idx
1047 | 	return res, nil
1048 | }
```

#### [`_iterator_next_internal`](../../xitdb/cursor.odin#L1050-L1083) — `DEPTH 4` (`L1050–L1083`)

```odin
1050 | @(private)
1051 | _iterator_next_internal :: proc(it: ^Cursor_Iterator, node_offset: i64) -> (res: Maybe(Read_Cursor), err: Error) {
1052 | 	for it.stack_len > 0 {
1053 | 		level := &it.stack[it.stack_len - 1]
1054 | 		if level.index >= level.count {
1055 | 			it.stack_len -= 1
1056 | 			if it.stack_len > 0 {
1057 | 				it.stack[it.stack_len - 1].index += 1
1058 | 			}
1059 | 			continue
1060 | 		}
1061 | 		next_slot := level.block[level.index]
1062 | 		if next_slot.tag == .Index {
1063 | 			if node_offset == BTREE_NODE_HEADER_SIZE {
1064 | 				_init_btree_iter_level(it.cursor, next_slot.value, &it.stack[it.stack_len]) or_return  // <== [calls _init_btree_iter_level]
1065 | 			} else {
1066 | 				_init_iter_level(it.cursor, next_slot.value, &it.stack[it.stack_len]) or_return  // <== [calls _init_iter_level]
1067 | 			}
1068 | 			it.stack_len += 1
1069 | 			continue
1070 | 		}
1071 | 		slot_idx := level.index
1072 | 		level.index += 1
1073 | 		if !slot_empty(next_slot) {  // <== [calls slot_empty]
1074 | 			position := level.position + i64(slot_idx) * SLOT_LENGTH
1075 | 			return Read_Cursor{
1076 | 				slot_ptr  = Slot_Pointer{position = position, slot = next_slot},
1077 | 				db        = it.cursor.db,
1078 | 				frozen_at = it.cursor.frozen_at,
1079 | 			}, nil
1080 | 		}
1081 | 	}
1082 | 	return nil, nil
1083 | }
```

#### [`cursor_iterator_next`](../../xitdb/cursor.odin#L1085-L1106) — `DEPTH 3` (`L1085–L1106`)

```odin
1085 | cursor_iterator_next :: proc(it: ^Cursor_Iterator) -> (res: Maybe(Read_Cursor), err: Error) {
1086 | 	#partial switch it.cursor.slot_ptr.slot.tag {
1087 | 	case .None:
1088 | 		return nil, nil
1089 | 	case .Array_List:
1090 | 		if it.index == it.size {
1091 | 			return nil, nil
1092 | 		}
1093 | 		it.index += 1
1094 | 		return _iterator_next_internal(it, 0)  // <== [calls _iterator_next_internal]
1095 | 	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
1096 | 		if it.index == it.size {
1097 | 			return nil, nil
1098 | 		}
1099 | 		it.index += 1
1100 | 		return _iterator_next_internal(it, BTREE_NODE_HEADER_SIZE)  // <== [calls _iterator_next_internal]
1101 | 	case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
1102 | 		return _iterator_next_internal(it, 0)  // <== [calls _iterator_next_internal]
1103 | 	case:
1104 | 		return nil, .Unexpected_Tag
1105 | 	}
1106 | }
```

### `xitdb/database.odin` (33 procedures · 968 lines: [`L13–L18`](../../xitdb/database.odin#L13-L18), [`L20–L25`](../../xitdb/database.odin#L20-L25), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L259–L266`](../../xitdb/database.odin#L259-L266), [`L268–L270`](../../xitdb/database.odin#L268-L270), [`L283–L298`](../../xitdb/database.odin#L283-L298), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L337–L341`](../../xitdb/database.odin#L337-L341), [`L343–L362`](../../xitdb/database.odin#L343-L362), [`L364–L368`](../../xitdb/database.odin#L364-L368), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L379–L382`](../../xitdb/database.odin#L379-L382), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414), [`L416–L421`](../../xitdb/database.odin#L416-L421), [`L423–L438`](../../xitdb/database.odin#L423-L438), [`L440–L460`](../../xitdb/database.odin#L440-L460), [`L462–L468`](../../xitdb/database.odin#L462-L468), [`L470–L482`](../../xitdb/database.odin#L470-L482), [`L484–L489`](../../xitdb/database.odin#L484-L489), [`L491–L501`](../../xitdb/database.odin#L491-L501), [`L503–L515`](../../xitdb/database.odin#L503-L515), [`L517–L528`](../../xitdb/database.odin#L517-L528), [`L530–L535`](../../xitdb/database.odin#L530-L535), [`L537–L542`](../../xitdb/database.odin#L537-L542), [`L544–L549`](../../xitdb/database.odin#L544-L549), [`L552–L619`](../../xitdb/database.odin#L552-L619), [`L621–L1382`](../../xitdb/database.odin#L621-L1382), [`L1384–L1395`](../../xitdb/database.odin#L1384-L1395), [`L1397–L1450`](../../xitdb/database.odin#L1397-L1450), [`L1452–L1483`](../../xitdb/database.odin#L1452-L1483), [`L1485–L1533`](../../xitdb/database.odin#L1485-L1533))

#### [`transaction_is_root_position`](../../xitdb/database.odin#L13-L18) — `DEPTH 4` (`L13–L18`)

```odin
  13 | transaction_is_root_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  14 | 	if t == nil || pos == nil || t.root_position == nil {
  15 | 		return false
  16 | 	}
  17 | 	return pos.? == t.root_position.?
  18 | }
```

#### [`transaction_is_scratch_position`](../../xitdb/database.odin#L20-L25) — `DEPTH 4` (`L20–L25`)

```odin
  20 | transaction_is_scratch_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  21 | 	if t == nil || pos == nil || t.scratch_position == nil {
  22 | 		return false
  23 | 	}
  24 | 	return pos.? == t.scratch_position.?
  25 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 3` (`L237–L244`)

```odin
 237 | @(private)
 238 | _random_u64 :: proc() -> u64 {
 239 | 	v := rand.uint64()
 240 | 	if v == 0 {
 241 | 		v = 1
 242 | 	}
 243 | 	return v
 244 | }
```

#### [`database_digest_buf`](../../xitdb/database.odin#L259-L266) — `DEPTH 2` (`L259–L266`)

```odin
 259 | database_digest_buf :: proc(db: ^Database, data: []u8, buf: []u8) -> []u8 {
 260 | 	hsize := int(db.header.hash_size)
 261 | 	out := buf[:hsize] if hsize <= len(buf) else make([]u8, hsize, context.temp_allocator)
 262 | 	if db.hasher.hash_proc != nil {
 263 | 		db.hasher.hash_proc(data, out, db.hasher.user_data)
 264 | 	}
 265 | 	return out
 266 | }
```

#### [`database_digest_string_buf`](../../xitdb/database.odin#L268-L270) — `DEPTH 1` (`L268–L270`)

```odin
 268 | database_digest_string_buf :: proc(db: ^Database, s: string, buf: []u8) -> []u8 {
 269 | 	return database_digest_buf(db, transmute([]u8)s, buf)  // <== [calls database_digest_buf]
 270 | }
```

#### [`database_root_cursor`](../../xitdb/database.odin#L283-L298) — `DEPTH 1` (`L283–L298`)

```odin
 283 | database_root_cursor :: proc(db: ^Database) -> Write_Cursor {
 284 | 	root, err := database_read_root_slot(db)  // <== [calls database_read_root_slot]
 285 | 	if err != nil {
 286 | 		root = Slot{}
 287 | 	}
 288 | 	return Write_Cursor{
 289 | 		read_cursor = Read_Cursor{
 290 | 			slot_ptr = Slot_Pointer{
 291 | 				position = i64(ROOT_HEADER_START),
 292 | 				slot     = root,
 293 | 			},
 294 | 			db        = db,
 295 | 			frozen_at = 0,
 296 | 		},
 297 | 	}
 298 | }
```

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 2` (`L319–L334`)

```odin
 319 | @(private)
 320 | _database_committed_size_with_header :: proc(db: ^Database, header: Root_Header) -> (committed_size: i64, file_size: i64, err: Error) {
 321 | 	minimum_size := i64(ROOT_HEADER_END + ROOT_TRAILER_LENGTH)
 322 | 	if header.file_size < minimum_size {
 323 | 		return 0, 0, .Invalid_Database
 324 | 	}
 325 | 	file_size = core_length(db.core) or_return  // <== [calls core_length]
 326 | 	if file_size < header.file_size {
 327 | 		return 0, 0, .Truncated_Database
 328 | 	}
 329 | 	trailer := database_read_root_trailer(db, header.file_size) or_return  // <== [calls database_read_root_trailer]
 330 | 	if trailer.root != header.root {
 331 | 		return 0, 0, .Invalid_Database
 332 | 	}
 333 | 	return header.file_size, file_size, nil
 334 | }
```

#### [`database_committed_size`](../../xitdb/database.odin#L337-L341) — `DEPTH 1` (`L337–L341`)

```odin
 337 | database_committed_size :: proc(db: ^Database) -> (res: i64, err: Error) {
 338 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 339 | 	committed_size, _ := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 340 | 	return committed_size, nil
 341 | }
```

#### [`_database_truncate_with_header`](../../xitdb/database.odin#L343-L362) — `DEPTH 3` (`L343–L362`)

```odin
 343 | @(private)
 344 | _database_truncate_with_header :: proc(db: ^Database, header: Root_Header) -> (final_size: i64, err: Error) {
 345 | 	committed_size, file_size := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 346 | 	active := db.transaction
 347 | 	if active != nil {
 348 | 		if fa, ok := active.frozen_at.?; ok && fa > committed_size {
 349 | 			if file_size > fa {
 350 | 				core_set_length(db.core, fa) or_return  // <== [calls core_set_length]
 351 | 			}
 352 | 			commit_id := _random_u64()  // <== [calls _random_u64]
 353 | 			database_commit_root(db, header.root, commit_id) or_return  // <== [calls database_commit_root]
 354 | 			core_sync(db.core) or_return  // <== [calls core_sync]
 355 | 			return core_length(db.core)  // <== [calls core_length]
 356 | 		}
 357 | 	}
 358 | 	if file_size > committed_size {
 359 | 		core_set_length(db.core, committed_size) or_return  // <== [calls core_set_length]
 360 | 	}
 361 | 	return committed_size, nil
 362 | }
```

#### [`database_truncate`](../../xitdb/database.odin#L364-L368) — `DEPTH 2` (`L364–L368`)

```odin
 364 | database_truncate :: proc(db: ^Database) -> Error {
 365 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 366 | 	_, err := _database_truncate_with_header(db, header)  // <== [calls _database_truncate_with_header]
 367 | 	return err
 368 | }
```

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 2` (`L370–L377`)

```odin
 370 | database_read_root_header :: proc(db: ^Database) -> (res: Root_Header, err: Error) {
 371 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 372 | 	b: [ROOT_HEADER_LENGTH]u8
 373 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 374 | 	header := root_header_from_bytes(b)  // <== [calls root_header_from_bytes]
 375 | 	tag_validate(header.root.tag) or_return  // <== [calls tag_validate]
 376 | 	return header, nil
 377 | }
```

#### [`database_read_root_slot`](../../xitdb/database.odin#L379-L382) — `DEPTH 2` (`L379–L382`)

```odin
 379 | database_read_root_slot :: proc(db: ^Database) -> (res: Slot, err: Error) {
 380 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 381 | 	return header.root, nil
 382 | }
```

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 3` (`L384–L398`)

```odin
 384 | database_read_root_trailer :: proc(db: ^Database, end: i64) -> (res: Root_Trailer, err: Error) {
 385 | 	if end < ROOT_TRAILER_LENGTH {
 386 | 		return {}, .Invalid_Database
 387 | 	}
 388 | 	trailer_pos := end - ROOT_TRAILER_LENGTH
 389 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 390 | 	b: [ROOT_TRAILER_LENGTH]u8
 391 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 392 | 	trailer := root_trailer_from_bytes(b)  // <== [calls root_trailer_from_bytes]
 393 | 	if trailer.checksum != compute_root_trailer_checksum(db.header.file_id, trailer_pos, trailer.root, trailer.commit_id) {  // <== [calls compute_root_trailer_checksum]
 394 | 		return {}, .Invalid_Database
 395 | 	}
 396 | 	tag_validate(trailer.root.tag) or_return  // <== [calls tag_validate]
 397 | 	return trailer, nil
 398 | }
```

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 3` (`L400–L407`)

```odin
 400 | database_commit_root :: proc(db: ^Database, root: Slot, commit_id: u64) -> Error {
 401 | 	trailer_pos := core_length(db.core) or_return  // <== [calls core_length]
 402 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 403 | 	trailer := root_trailer_to_bytes(new_root_trailer(db.header.file_id, trailer_pos, root, commit_id))  // <== [calls root_trailer_to_bytes, new_root_trailer]
 404 | 	core_write_all(db.core, trailer[:]) or_return  // <== [calls core_write_all]
 405 | 	core_sync(db.core) or_return  // <== [calls core_sync]
 406 | 	return database_write_root_header(db, root)  // <== [calls database_write_root_header]
 407 | }
```

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 4` (`L409–L414`)

```odin
 409 | database_write_root_header :: proc(db: ^Database, root: Slot) -> Error {
 410 | 	file_size := core_length(db.core) or_return  // <== [calls core_length]
 411 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 412 | 	header := root_header_to_bytes(Root_Header{file_size = file_size, root = root})  // <== [calls root_header_to_bytes]
 413 | 	return core_write_all(db.core, header[:])  // <== [calls core_write_all]
 414 | }
```

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 2` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

#### [`init_tag`](../../xitdb/database.odin#L423-L438) — `DEPTH 2` (`L423–L438`)

```odin
 423 | init_tag :: proc(part: Path_Part) -> (res: Tag, err: bool) {
 424 | 	#partial switch p in part {
 425 | 	case Array_List_Init:
 426 | 		return .Array_List, true
 427 | 	case Linked_Array_List_Init:
 428 | 		return .Linked_Array_List, true
 429 | 	case Hash_Map_Init:
 430 | 		if p.counted {
 431 | 			return (.Counted_Hash_Set if p.set else .Counted_Hash_Map), true
 432 | 		}
 433 | 		return (.Hash_Set if p.set else .Hash_Map), true
 434 | 	case Sorted_Map_Init:
 435 | 		return (.Sorted_Set if p.set else .Sorted_Map), true
 436 | 	}
 437 | 	return .None, false
 438 | }
```

#### [`init_part_for`](../../xitdb/database.odin#L440-L460) — `DEPTH 3` (`L440–L460`)

```odin
 440 | init_part_for :: proc(tag: Tag) -> (res: Path_Part, err: bool) {
 441 | 	#partial switch tag {
 442 | 	case .Array_List:
 443 | 		return Array_List_Init{}, true
 444 | 	case .Linked_Array_List:
 445 | 		return Linked_Array_List_Init{}, true
 446 | 	case .Hash_Map:
 447 | 		return Hash_Map_Init{counted = false, set = false}, true
 448 | 	case .Hash_Set:
 449 | 		return Hash_Map_Init{counted = false, set = true}, true
 450 | 	case .Counted_Hash_Map:
 451 | 		return Hash_Map_Init{counted = true, set = false}, true
 452 | 	case .Counted_Hash_Set:
 453 | 		return Hash_Map_Init{counted = true, set = true}, true
 454 | 	case .Sorted_Map:
 455 | 		return Sorted_Map_Init{set = false}, true
 456 | 	case .Sorted_Set:
 457 | 		return Sorted_Map_Init{set = true}, true
 458 | 	}
 459 | 	return nil, false
 460 | }
```

#### [`database_is_old`](../../xitdb/database.odin#L462-L468) — `DEPTH 4` (`L462–L468`)

```odin
 462 | database_is_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: bool, err: Error) {
 463 | 	tx_s, ok := db.tx_start.?
 464 | 	if !ok {
 465 | 		return false, .Expected_Tx_Start
 466 | 	}
 467 | 	return ptr < max(tx_s, frozen_at), nil
 468 | }
```

#### [`database_copy_index_block_if_old`](../../xitdb/database.odin#L470-L482) — `DEPTH 5` (`L470–L482`)

```odin
 470 | database_copy_index_block_if_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: i64, err: Error) {
 471 | 	old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 472 | 	if !old {
 473 | 		return ptr, nil
 474 | 	}
 475 | 	index_block: [INDEX_BLOCK_SIZE]u8
 476 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 477 | 	core_read_exact(db.core, index_block[:]) or_return  // <== [calls core_read_exact]
 478 | 	next_ptr := core_length(db.core) or_return  // <== [calls core_length]
 479 | 	core_seek_to(db.core, next_ptr) or_return  // <== [calls core_seek_to]
 480 | 	core_write_all(db.core, index_block[:]) or_return  // <== [calls core_write_all]
 481 | 	return next_ptr, nil
 482 | }
```

#### [`database_check_hash`](../../xitdb/database.odin#L484-L489) — `DEPTH 5` (`L484–L489`)

```odin
 484 | database_check_hash :: proc(db: ^Database, h: []u8) -> (res: []u8, err: Error) {
 485 | 	if len(h) != int(db.header.hash_size) {
 486 | 		return nil, .Invalid_Hash_Size
 487 | 	}
 488 | 	return h, nil
 489 | }
```

#### [`database_check_hash_target`](../../xitdb/database.odin#L491-L501) — `DEPTH 4` (`L491–L501`)

```odin
 491 | database_check_hash_target :: proc(db: ^Database, target: Hash_Map_Get_Target) -> (res: []u8, err: Error) {
 492 | 	switch t in target {
 493 | 	case Hash_Map_Get_Value:
 494 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 495 | 	case Hash_Map_Get_Key:
 496 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 497 | 	case Hash_Map_Get_KV_Pair:
 498 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 499 | 	}
 500 | 	return nil, .Invalid_Hash_Size
 501 | }
```

#### [`database_check_frozen_slot`](../../xitdb/database.odin#L503-L515) — `DEPTH 3` (`L503–L515`)

```odin
 503 | database_check_frozen_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer) -> Error {
 504 | 	active := db.transaction
 505 | 	if active != nil {
 506 | 		if fa, ok := active.frozen_at.?; ok {
 507 | 			if pos, pok := slot_ptr.position.?; pok {
 508 | 				if pos < fa && !transaction_is_root_position(active, slot_ptr.position) {  // <== [calls transaction_is_root_position]
 509 | 					return .Frozen_Slot
 510 | 				}
 511 | 			}
 512 | 		}
 513 | 	}
 514 | 	return nil
 515 | }
```

#### [`database_copy_collection_if_frozen`](../../xitdb/database.odin#L517-L528) — `DEPTH 4` (`L517–L528`)

```odin
 517 | database_copy_collection_if_frozen :: proc(db: ^Database, slot_ptr: Slot_Pointer, init_part: Path_Part, frozen_at: i64) -> (res: Slot_Pointer, err: Error) {
 518 | 	if db.transaction != nil {
 519 | 		fa := frozen_at
 520 | 		if tfa, ok := db.transaction.frozen_at.?; ok && tfa > fa {
 521 | 			fa = tfa
 522 | 		}
 523 | 		if fa > 0 && slot_ptr.slot.value < fa {
 524 | 			return read_slot_pointer(db, .Read_Write, []Path_Part{init_part}, 0, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 525 | 		}
 526 | 	}
 527 | 	return slot_ptr, nil
 528 | }
```

#### [`database_kv_key_offset`](../../xitdb/database.odin#L530-L535) — `DEPTH 4` (`L530–L535`)

```odin
 530 | database_kv_key_offset :: proc(db: ^Database, tag: Tag) -> i64 {
 531 | 	if tag == .KV_Pair {
 532 | 		return i64(db.header.hash_size)
 533 | 	}
 534 | 	return 0
 535 | }
```

#### [`database_kv_key_position`](../../xitdb/database.odin#L537-L542) — `DEPTH 4` (`L537–L542`)

```odin
 537 | database_kv_key_position :: proc(db: ^Database, entry: Slot) -> Maybe(i64) {
 538 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
 539 | 		return nil
 540 | 	}
 541 | 	return entry.value + database_kv_key_offset(db, entry.tag)  // <== [calls database_kv_key_offset]
 542 | }
```

#### [`database_kv_value_position`](../../xitdb/database.odin#L544-L549) — `DEPTH 4` (`L544–L549`)

```odin
 544 | database_kv_value_position :: proc(db: ^Database, entry: Slot) -> Maybe(i64) {
 545 | 	if key_pos, ok := database_kv_key_position(db, entry).?; ok {  // <== [calls database_kv_key_position]
 546 | 		return key_pos + SLOT_LENGTH
 547 | 	}
 548 | 	return nil
 549 | }
```

#### [`read_slot_pointer`](../../xitdb/database.odin#L552-L619) — `DEPTH 2` (`L552–L619`)

```odin
 552 | read_slot_pointer :: proc(
 553 | 	db: ^Database,
 554 | 	write_mode: Write_Mode,
 555 | 	path: []Path_Part,
 556 | 	path_i: int,
 557 | 	slot_ptr: Slot_Pointer,
 558 | 	frozen_at: i64,
 559 | ) -> (res: Slot_Pointer, err: Error) {
 560 | 	if path_i == len(path) {
 561 | 		if write_mode == .Read_Only && slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
 562 | 			return {}, .Key_Not_Found
 563 | 		}
 564 | 		return slot_ptr, nil
 565 | 	}
 566 | 	if write_mode == .Read_Write {
 567 | 		database_check_frozen_slot(db, slot_ptr) or_return  // <== [calls database_check_frozen_slot]
 568 | 	}
 569 | 	part := path[path_i]
 570 | 
 571 | 	// Every write that starts at the root is a transaction.
 572 | 	if is_root(slot_ptr) {  // <== [calls is_root]
 573 | 		root_header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 574 | 		root := root_header.root
 575 | 
 576 | 		if write_mode == .Read_Only {
 577 | 			return read_slot_pointer(db, write_mode, path, path_i, Slot_Pointer{position = nil, slot = root}, frozen_at)
 578 | 		}
 579 | 
 580 | 		// Initializing an already-initialized root is free.
 581 | 		if len(path) - path_i == 1 && root.tag != .None {
 582 | 			if tag, ok := init_tag(part); ok && tag == root.tag {  // <== [calls init_tag]
 583 | 				_ = _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 584 | 				return Slot_Pointer{position = i64(ROOT_HEADER_START), slot = root}, nil
 585 | 			}
 586 | 		}
 587 | 
 588 | 		scratch_pos := _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 589 | 		db.tx_start = scratch_pos
 590 | 		defer db.tx_start = nil
 591 | 
 592 | 		if db.transaction != nil {
 593 | 			db.transaction.root_position = scratch_pos
 594 | 			db.transaction.scratch_position = scratch_pos
 595 | 		}
 596 | 
 597 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 598 | 		core_write_slot(db.core, root) or_return  // <== [calls core_write_slot]
 599 | 		root_ptr := Slot_Pointer{position = scratch_pos, slot = root}
 600 | 
 601 | 		if init_p, ok := init_part_for(root.tag); ok {  // <== [calls init_part_for]
 602 | 			root_ptr = read_slot_pointer(db, write_mode, []Path_Part{init_p}, 0, root_ptr, frozen_at) or_return
 603 | 		}
 604 | 
 605 | 		result := read_slot_pointer(db, write_mode, path, path_i, root_ptr, frozen_at) or_return
 606 | 
 607 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 608 | 		next_root := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 609 | 		commit_id := _random_u64()  // <== [calls _random_u64]
 610 | 		database_commit_root(db, next_root, commit_id) or_return  // <== [calls database_commit_root]
 611 | 
 612 | 		if rpos, ok := result.position.?; ok && rpos == scratch_pos {
 613 | 			result = Slot_Pointer{position = i64(ROOT_HEADER_START), slot = next_root}
 614 | 		}
 615 | 		return result, nil
 616 | 	}
 617 | 
 618 | 	return _exec_path_part(db, part, write_mode, path, path_i, slot_ptr, frozen_at)  // <== [calls _exec_path_part]
 619 | }
```

#### [`_exec_path_part`](../../xitdb/database.odin#L621-L1382) — `DEPTH 3` (`L621–L1382`) — Active `Path_Part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Get`, `Hash_Map_Init`, `Hash_Map_Get`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`

```odin
 621 | @(private)
 622 | _exec_path_part :: proc(
 623 | 	db: ^Database,
 624 | 	part: Path_Part,
 625 | 	write_mode: Write_Mode,
 626 | 	path: []Path_Part,
 627 | 	path_i: int,
 628 | 	slot_ptr: Slot_Pointer,
 629 | 	frozen_at: i64,
 630 | ) -> (res: Slot_Pointer, err: Error) {
 631 | 	slot_ptr := slot_ptr
 632 | 
 633 | 	switch p in part {
 634 | 	case Array_List_Init:
 635 | 		if write_mode == .Read_Only {
 636 | 			return {}, .Write_Not_Allowed
 637 | 		}
 638 | 		position, pos_ok := slot_ptr.position.?
 639 | 		if !pos_ok {
 640 | 			return {}, .Cursor_Not_Writeable
 641 | 		}
 642 | 		#partial switch slot_ptr.slot.tag {
 643 | 		case .None:
 644 | 			array_list_start := core_length(db.core) or_return  // <== [calls core_length]
 645 | 			core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 646 | 			array_list_ptr := array_list_start + ARRAY_LIST_HEADER_LENGTH
 647 | 			al_header := array_list_header_to_bytes(Array_List_Header{ptr = array_list_ptr, size = 0})  // <== [calls array_list_header_to_bytes]
 648 | 			core_write_all(db.core, al_header[:]) or_return  // <== [calls core_write_all]
 649 | 			empty_block: [INDEX_BLOCK_SIZE]u8
 650 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 651 | 			next_slot_ptr := Slot_Pointer{
 652 | 				position = position,
 653 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 654 | 			}
 655 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 656 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 657 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 658 | 
 659 | 		case .Array_List:
 660 | 			array_list_start := slot_ptr.slot.value
 661 | 			old := database_is_old(db, array_list_start, frozen_at) or_return  // <== [calls database_is_old]
 662 | 			if old {
 663 | 				core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 664 | 				hb: [ARRAY_LIST_HEADER_LENGTH]u8
 665 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 666 | 				header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 667 | 				core_seek_to(db.core, header.ptr) or_return  // <== [calls core_seek_to]
 668 | 				idx_block: [INDEX_BLOCK_SIZE]u8
 669 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
 670 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
 671 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
 672 | 				next_ptr := new_start + ARRAY_LIST_HEADER_LENGTH
 673 | 				header = array_list_header_with_ptr(header, next_ptr)  // <== [calls array_list_header_with_ptr]
 674 | 				nhb := array_list_header_to_bytes(header)  // <== [calls array_list_header_to_bytes]
 675 | 				core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 676 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
 677 | 				array_list_start = new_start
 678 | 			}
 679 | 			next_slot_ptr := Slot_Pointer{
 680 | 				position = position,
 681 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 682 | 			}
 683 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 684 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 685 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 686 | 
 687 | 		case:
 688 | 			return {}, .Unexpected_Tag
 689 | 		}
   ... | 	// ... [lines 690–690: untouched Path_Part arms omitted] ...
 691 | 	case Array_List_Get:
 692 | 		#partial switch slot_ptr.slot.tag {
 693 | 		case .None:
 694 | 			return {}, .Key_Not_Found
 695 | 		case .Array_List:
 696 | 		case:
 697 | 			return {}, .Unexpected_Tag
 698 | 		}
 699 | 		if write_mode == .Read_Write {
 700 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 701 | 		}
 702 | 		next_array_list_start := slot_ptr.slot.value
 703 | 		index := p.index
 704 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 705 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 706 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 707 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 708 | 		if index >= header.size || index < -header.size {
 709 | 			return {}, .Key_Not_Found
 710 | 		}
 711 | 		key := (header.size + index) if index < 0 else index
 712 | 		shift := radix_shift(header.size - 1)  // <== [calls radix_shift]
 713 | 		final_slot_ptr := read_array_list_slot(db, header.ptr, key, shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 714 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, final_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 715–715: untouched Path_Part arms omitted] ...
 716 | 	case Array_List_Append:
 717 | 		if write_mode == .Read_Only {
 718 | 			return {}, .Write_Not_Allowed
 719 | 		}
 720 | 		if slot_ptr.slot.tag != .Array_List {
 721 | 			return {}, .Unexpected_Tag
 722 | 		}
 723 | 		slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 724 | 		next_array_list_start := slot_ptr.slot.value
 725 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 726 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 727 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 728 | 		orig_header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 729 | 		append_res := read_array_list_slot_append(db, orig_header, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot_append]
 730 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 731 | 		nhb := array_list_header_to_bytes(append_res.header)  // <== [calls array_list_header_to_bytes]
 732 | 		core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 733 | 		if db.transaction != nil && transaction_is_scratch_position(db.transaction, slot_ptr.position) {  // <== [calls transaction_is_scratch_position]
 734 | 			db.transaction.root_position = append_res.slot_ptr.position
 735 | 		}
 736 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, append_res.slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 737–756: untouched Path_Part arms omitted] ...
 757 | 	case Linked_Array_List_Init:
 758 | 		if write_mode == .Read_Only {
 759 | 			return {}, .Write_Not_Allowed
 760 | 		}
 761 | 		position, pos_ok := slot_ptr.position.?
 762 | 		if !pos_ok {
 763 | 			return {}, .Cursor_Not_Writeable
 764 | 		}
 765 | 		#partial switch slot_ptr.slot.tag {
 766 | 		case .None:
 767 | 			root_ptr := write_btree_node(db, BTree_Node{kind = .Leaf, num = 0}) or_return  // <== [calls write_btree_node]
 768 | 			header_ptr := core_length(db.core) or_return  // <== [calls core_length]
 769 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 770 | 			hb := btree_header_to_bytes(BTree_Header{root_ptr = root_ptr, size = 0})  // <== [calls btree_header_to_bytes]
 771 | 			core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
 772 | 			next_slot_ptr := Slot_Pointer{
 773 | 				position = position,
 774 | 				slot     = Slot{value = header_ptr, tag = .Linked_Array_List},
 775 | 			}
 776 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 777 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 778 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 779 | 
 780 | 		case .Linked_Array_List:
 781 | 			header_ptr := slot_ptr.slot.value
 782 | 			old := database_is_old(db, header_ptr, frozen_at) or_return  // <== [calls database_is_old]
 783 | 			if old {
 784 | 				core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 785 | 				hb: [BTREE_HEADER_LENGTH]u8
 786 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 787 | 				new_ptr := core_length(db.core) or_return  // <== [calls core_length]
 788 | 				core_seek_to(db.core, new_ptr) or_return  // <== [calls core_seek_to]
 789 | 				core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
 790 | 				header_ptr = new_ptr
 791 | 			}
 792 | 			next_slot_ptr := Slot_Pointer{
 793 | 				position = position,
 794 | 				slot     = Slot{value = header_ptr, tag = .Linked_Array_List},
 795 | 			}
 796 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 797 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 798 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 799 | 
 800 | 		case:
 801 | 			return {}, .Unexpected_Tag
 802 | 		}
   ... | 	// ... [lines 803–803: untouched Path_Part arms omitted] ...
 804 | 	case Linked_Array_List_Get:
 805 | 		#partial switch slot_ptr.slot.tag {
 806 | 		case .None:
 807 | 			return {}, .Key_Not_Found
 808 | 		case .Linked_Array_List:
 809 | 		case:
 810 | 			return {}, .Unexpected_Tag
 811 | 		}
 812 | 		index := p.index
 813 | 		if write_mode == .Read_Write {
 814 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Linked_Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 815 | 		}
 816 | 		header_ptr := slot_ptr.slot.value
 817 | 		core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 818 | 		hb: [BTREE_HEADER_LENGTH]u8
 819 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 820 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 821 | 		if index >= header.size || index < -header.size {
 822 | 			return {}, .Key_Not_Found
 823 | 		}
 824 | 		rank := (header.size + index) if index < 0 else index
 825 | 		if write_mode == .Read_Only {
 826 | 			final_slot_ptr := read_btree_slot(db, header.root_ptr, rank) or_return  // <== [calls read_btree_slot]
 827 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, final_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 828 | 		}
 829 | 		write_slot := btree_get_for_write(db, header.root_ptr, rank, frozen_at) or_return  // <== [calls btree_get_for_write]
 830 | 		if write_slot.node_ptr != header.root_ptr {
 831 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
 832 | 			nhb := btree_header_to_bytes(BTree_Header{root_ptr = write_slot.node_ptr, size = header.size})  // <== [calls btree_header_to_bytes]
 833 | 			core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 834 | 		}
 835 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, Slot_Pointer{position = write_slot.value_position, slot = write_slot.slot}, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 836–983: untouched Path_Part arms omitted] ...
 984 | 	case Hash_Map_Init:
 985 | 		if write_mode == .Read_Only {
 986 | 			return {}, .Write_Not_Allowed
 987 | 		}
 988 | 		tag: Tag
 989 | 		if p.counted {
 990 | 			tag = .Counted_Hash_Set if p.set else .Counted_Hash_Map
 991 | 		} else {
 992 | 			tag = .Hash_Set if p.set else .Hash_Map
 993 | 		}
 994 | 		position, pos_ok := slot_ptr.position.?
 995 | 		if !pos_ok {
 996 | 			return {}, .Cursor_Not_Writeable
 997 | 		}
 998 | 		#partial switch slot_ptr.slot.tag {
 999 | 		case .None:
1000 | 			map_start := core_length(db.core) or_return  // <== [calls core_length]
1001 | 			core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1002 | 			if p.counted {
1003 | 				core_write_long(db.core, 0) or_return  // <== [calls core_write_long]
1004 | 			}
1005 | 			empty_block: [INDEX_BLOCK_SIZE]u8
1006 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
1007 | 			next_slot_ptr := Slot_Pointer{
1008 | 				position = position,
1009 | 				slot     = Slot{value = map_start, tag = tag},
1010 | 			}
1011 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1012 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1013 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1014 | 
1015 | 		case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
1016 | 			if p.counted {
1017 | 				#partial switch slot_ptr.slot.tag {
1018 | 				case .Counted_Hash_Map, .Counted_Hash_Set:
1019 | 				case:
1020 | 					return {}, .Unexpected_Tag
1021 | 				}
1022 | 			} else {
1023 | 				#partial switch slot_ptr.slot.tag {
1024 | 				case .Hash_Map, .Hash_Set:
1025 | 				case:
1026 | 					return {}, .Unexpected_Tag
1027 | 				}
1028 | 			}
1029 | 			map_start := slot_ptr.slot.value
1030 | 			old := database_is_old(db, map_start, frozen_at) or_return  // <== [calls database_is_old]
1031 | 			if old {
1032 | 				core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1033 | 				map_count: i64 = 0
1034 | 				if p.counted {
1035 | 					map_count = core_read_long(db.core) or_return  // <== [calls core_read_long]
1036 | 				}
1037 | 				idx_block: [INDEX_BLOCK_SIZE]u8
1038 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
1039 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
1040 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
1041 | 				if p.counted {
1042 | 					core_write_long(db.core, map_count) or_return  // <== [calls core_write_long]
1043 | 				}
1044 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
1045 | 				map_start = new_start
1046 | 			}
1047 | 			next_slot_ptr := Slot_Pointer{
1048 | 				position = position,
1049 | 				slot     = Slot{value = map_start, tag = tag},
1050 | 			}
1051 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1052 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1053 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1054 | 
1055 | 		case:
1056 | 			return {}, .Unexpected_Tag
1057 | 		}
   ... | 	// ... [lines 1058–1058: untouched Path_Part arms omitted] ...
1059 | 	case Hash_Map_Get:
1060 | 		counted := false
1061 | 		#partial switch slot_ptr.slot.tag {
1062 | 		case .None:
1063 | 			return {}, .Key_Not_Found
1064 | 		case .Hash_Map, .Hash_Set:
1065 | 		case .Counted_Hash_Map, .Counted_Hash_Set:
1066 | 			counted = true
1067 | 		case:
1068 | 			return {}, .Unexpected_Tag
1069 | 		}
1070 | 		if write_mode == .Read_Write {
1071 | 			is_set := slot_ptr.slot.tag == .Hash_Set || slot_ptr.slot.tag == .Counted_Hash_Set
1072 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Hash_Map_Init{counted = counted, set = is_set}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
1073 | 		}
1074 | 		index_pos := (slot_ptr.slot.value + 8) if counted else slot_ptr.slot.value
1075 | 		key_hash := database_check_hash_target(db, p.target) or_return  // <== [calls database_check_hash_target]
1076 | 		res := read_map_slot(db, index_pos, key_hash, 0, write_mode, p.target, frozen_at) or_return  // <== [calls read_map_slot]
1077 | 		if write_mode == .Read_Write && counted && res.is_empty {
1078 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1079 | 			map_count := core_read_long(db.core) or_return  // <== [calls core_read_long]
1080 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1081 | 			core_write_long(db.core, map_count + 1) or_return  // <== [calls core_write_long]
1082 | 		}
1083 | 		next_sp := res.slot_ptr
1084 | 		if write_mode == .Read_Write && res.is_empty && next_sp.slot.tag == .KV_Pair {
1085 | 			next_sp.slot.full = true
1086 | 		}
1087 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1088–1126: untouched Path_Part arms omitted] ...
1127 | 	case Sorted_Map_Init:
1128 | 		if write_mode == .Read_Only {
1129 | 			return {}, .Write_Not_Allowed
1130 | 		}
1131 | 		position, pos_ok := slot_ptr.position.?
1132 | 		if !pos_ok {
1133 | 			return {}, .Cursor_Not_Writeable
1134 | 		}
1135 | 		tag: Tag = .Sorted_Set if p.set else .Sorted_Map
1136 | 		#partial switch slot_ptr.slot.tag {
1137 | 		case .None:
1138 | 			root_ptr := write_sorted_node(db, Sorted_Node{kind = .Leaf, num = 0}) or_return  // <== [calls write_sorted_node]
1139 | 			header_ptr := core_length(db.core) or_return  // <== [calls core_length]
1140 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1141 | 			hb := btree_header_to_bytes(BTree_Header{root_ptr = root_ptr, size = 0})  // <== [calls btree_header_to_bytes]
1142 | 			core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
1143 | 			next_slot_ptr := Slot_Pointer{
1144 | 				position = position,
1145 | 				slot     = Slot{value = header_ptr, tag = tag},
1146 | 			}
1147 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1148 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1149 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1150 | 
1151 | 		case .Sorted_Map, .Sorted_Set:
1152 | 			header_ptr := slot_ptr.slot.value
1153 | 			old := database_is_old(db, header_ptr, frozen_at) or_return  // <== [calls database_is_old]
1154 | 			if old {
1155 | 				core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1156 | 				hb: [BTREE_HEADER_LENGTH]u8
1157 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
1158 | 				new_ptr := core_length(db.core) or_return  // <== [calls core_length]
1159 | 				core_seek_to(db.core, new_ptr) or_return  // <== [calls core_seek_to]
1160 | 				core_write_all(db.core, hb[:]) or_return  // <== [calls core_write_all]
1161 | 				header_ptr = new_ptr
1162 | 			}
1163 | 			next_slot_ptr := Slot_Pointer{
1164 | 				position = position,
1165 | 				slot     = Slot{value = header_ptr, tag = tag},
1166 | 			}
1167 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1168 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1169 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1170 | 
1171 | 		case:
1172 | 			return {}, .Unexpected_Tag
1173 | 		}
   ... | 	// ... [lines 1174–1174: untouched Path_Part arms omitted] ...
1175 | 	case Sorted_Map_Get:
1176 | 		#partial switch slot_ptr.slot.tag {
1177 | 		case .None:
1178 | 			return {}, .Key_Not_Found
1179 | 		case .Sorted_Map, .Sorted_Set:
1180 | 		case:
1181 | 			return {}, .Unexpected_Tag
1182 | 		}
1183 | 		key: []u8
1184 | 		switch t in p.target {
1185 | 		case Sorted_Map_Get_Value:
1186 | 			key = t.key
1187 | 		case Sorted_Map_Get_Key:
1188 | 			key = t.key
1189 | 		case Sorted_Map_Get_KV_Pair:
1190 | 			key = t.key
1191 | 		}
1192 | 		if write_mode == .Read_Write {
1193 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Sorted_Map_Init{set = slot_ptr.slot.tag == .Sorted_Set}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
1194 | 		}
1195 | 		header_ptr := slot_ptr.slot.value
1196 | 		core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1197 | 		hb: [BTREE_HEADER_LENGTH]u8
1198 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
1199 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
1200 | 
1201 | 		if write_mode == .Read_Only {
1202 | 			found_maybe := sorted_get(db, header.root_ptr, key) or_return  // <== [calls sorted_get]
1203 | 			found, has_found := found_maybe.?
1204 | 			if !has_found {
1205 | 				return {}, .Key_Not_Found
1206 | 			}
1207 | 			target_slot: Slot_Pointer
1208 | 			if _, is_key := p.target.(Sorted_Map_Get_Key); is_key {
1209 | 				target_slot = Slot_Pointer{position = nil, slot = found.key_slot}
1210 | 			} else {
1211 | 				target_slot = sorted_target_slot(db, found.slot, p.target) or_return  // <== [calls sorted_target_slot]
1212 | 			}
1213 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, target_slot, frozen_at)  // <== [calls read_slot_pointer]
1214 | 		}
1215 | 
1216 | 		_, is_key_target := p.target.(Sorted_Map_Get_Key)
1217 | 		key_only := slot_ptr.slot.tag == .Sorted_Set && is_key_target
1218 | 		res := sorted_put(db, header.root_ptr, key, key_only, frozen_at) or_return  // <== [calls sorted_put]
1219 | 		new_root_ptr := sorted_grow_root(db, res) or_return  // <== [calls sorted_grow_root]
1220 | 		if new_root_ptr != header.root_ptr || res.added {
1221 | 			core_seek_to(db.core, header_ptr) or_return  // <== [calls core_seek_to]
1222 | 			new_size := header.size + (1 if res.added else 0)
1223 | 			nhb := btree_header_to_bytes(BTree_Header{root_ptr = new_root_ptr, size = new_size})  // <== [calls btree_header_to_bytes]
1224 | 			core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
1225 | 		}
1226 | 		target_slot: Slot_Pointer
1227 | 		if _, is_val := p.target.(Sorted_Map_Get_Value); is_val && res.added {
1228 | 			target_slot = Slot_Pointer{position = res.entry.value + SLOT_LENGTH, slot = Slot{}}
1229 | 		} else {
1230 | 			target_slot = sorted_target_slot(db, res.entry, p.target) or_return  // <== [calls sorted_target_slot]
1231 | 		}
1232 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, target_slot, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1233–1284: untouched Path_Part arms omitted] ...
1285 | 	case Write_Data:
1286 | 		if write_mode == .Read_Only {
1287 | 			return {}, .Write_Not_Allowed
1288 | 		}
1289 | 		position, pos_ok := slot_ptr.position.?
1290 | 		if !pos_ok {
1291 | 			return {}, .Cursor_Not_Writeable
1292 | 		}
1293 | 		if p.if_empty && !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
1294 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1295 | 		}
1296 | 
1297 | 		slot := _encode_writeable_data(db, slot_ptr, p.data) or_return  // <== [calls _encode_writeable_data]
1298 | 
1299 | 		core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1300 | 		core_write_slot(db.core, slot) or_return  // <== [calls core_write_slot]
1301 | 		next_slot_ptr := Slot_Pointer{position = slot_ptr.position, slot = slot}
1302 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1303–1303: untouched Path_Part arms omitted] ...
1304 | 	case Write_KV_Data:
1305 | 		if write_mode == .Read_Only {
1306 | 			return {}, .Write_Not_Allowed
1307 | 		}
1308 | 		kv_pos := slot_ptr.slot.value
1309 | 		key_slot_pos := kv_pos + database_kv_key_offset(db, slot_ptr.slot.tag)  // <== [calls database_kv_key_offset]
1310 | 		val_slot_pos := key_slot_pos + SLOT_LENGTH
1311 | 
1312 | 		if slot_ptr.slot.full {
1313 | 			if val_slot, val_inline, val_err := _try_encode_inline_data(p.value); val_err != nil {  // <== [calls _try_encode_inline_data]
1314 | 				return {}, val_err
1315 | 			} else if val_inline {
1316 | 				if key_bytes, is_kbytes := _extract_bytes_data(p.key); is_kbytes && !bytes_is_short(key_bytes) {  // <== [calls _extract_bytes_data, bytes_is_short]
1317 | 					if key_bytes.format_tag != nil && len(key_bytes.format_tag) != 2 {
1318 | 						return {}, .Invalid_Format_Tag_Size
1319 | 					}
1320 | 					if db.tx_start == nil {
1321 | 						return {}, .Expected_Tx_Start
1322 | 					}
1323 | 					cur_len := core_length(db.core) or_return  // <== [calls core_length]
1324 | 					has_ft := key_bytes.format_tag != nil
1325 | 					key_payload_len := 8 + len(key_bytes.value) + (2 if has_ft else 0)
1326 | 					if cur_len == val_slot_pos + SLOT_LENGTH && key_payload_len <= 238 {
1327 | 						key_slot := Slot{value = cur_len, tag = .Bytes, full = has_ft}
1328 | 						combined_buf: [256]u8 = ---
1329 | 						out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1330 | 						out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1331 | 						copy(combined_buf[0:SLOT_LENGTH], out_kb[:])
1332 | 						copy(combined_buf[SLOT_LENGTH : SLOT_LENGTH * 2], out_vb[:])
1333 | 						endian.unchecked_put_u64be(combined_buf[18:26], u64(len(key_bytes.value)))
1334 | 						copy(combined_buf[26 : 26 + len(key_bytes.value)], key_bytes.value)
1335 | 						if has_ft {
1336 | 							copy(combined_buf[26 + len(key_bytes.value) : 18 + key_payload_len], key_bytes.format_tag)
1337 | 						}
1338 | 						core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1339 | 						core_write_all(db.core, combined_buf[:18 + key_payload_len]) or_return  // <== [calls core_write_all]
1340 | 						clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1341 | 						return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
1342 | 					}
1343 | 				}
1344 | 			}
1345 | 			key_slot := _encode_writeable_data(db, Slot_Pointer{position = key_slot_pos, slot = Slot{}}, p.key) or_return  // <== [calls _encode_writeable_data]
1346 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1347 | 			slots_buf: [SLOT_LENGTH * 2]u8 = ---
1348 | 			out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1349 | 			out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1350 | 			copy(slots_buf[:SLOT_LENGTH], out_kb[:])
1351 | 			copy(slots_buf[SLOT_LENGTH:], out_vb[:])
1352 | 			core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1353 | 			core_write_all(db.core, slots_buf[:]) or_return  // <== [calls core_write_all]
1354 | 		} else {
1355 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1356 | 			core_seek_to(db.core, val_slot_pos) or_return  // <== [calls core_seek_to]
1357 | 			core_write_slot(db.core, val_slot) or_return  // <== [calls core_write_slot]
1358 | 		}
1359 | 		clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1360 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1361–1361: untouched Path_Part arms omitted] ...
1362 | 	case Context:
1363 | 		if write_mode == .Read_Only {
1364 | 			return {}, .Write_Not_Allowed
1365 | 		}
1366 | 		if path_i != len(path) - 1 {
1367 | 			return {}, .Path_Part_Must_Be_At_End
1368 | 		}
1369 | 		clean_sp := slot_ptr
1370 | 		if clean_sp.slot.tag == .KV_Pair && clean_sp.slot.full {
1371 | 			clean_sp.slot.full = false
1372 | 		}
1373 | 		next_cursor := new_write_cursor(clean_sp, db)  // <== [calls new_write_cursor]
1374 | 		next_cursor.frozen_at = frozen_at
1375 | 		if p.function != nil {
1376 | 			p.function(&next_cursor, p.user_data) or_return
1377 | 		}
1378 | 		return next_cursor.slot_ptr, nil
1379 | 	}
1380 | 
1381 | 	return {}, .Unreachable
1382 | }
```

#### [`_extract_bytes_data`](../../xitdb/database.odin#L1384-L1395) — `DEPTH 4` (`L1384–L1395`)

```odin
1384 | @(private)
1385 | _extract_bytes_data :: #force_inline proc(write_data: Writeable_Data) -> (b: Bytes, ok: bool) {
1386 | 	#partial switch data in write_data {
1387 | 	case string:
1388 | 		return Bytes{value = transmute([]u8)data}, true
1389 | 	case []u8:
1390 | 		return Bytes{value = data}, true
1391 | 	case Bytes:
1392 | 		return data, true
1393 | 	}
1394 | 	return {}, false
1395 | }
```

#### [`_try_encode_inline_data`](../../xitdb/database.odin#L1397-L1450) — `DEPTH 4` (`L1397–L1450`)

```odin
1397 | @(private)
1398 | _try_encode_inline_data :: #force_inline proc(write_data: Writeable_Data) -> (slot: Slot, is_inline: bool, err: Error) {
1399 | 	switch data in write_data {
1400 | 	case nil:
1401 | 		return Slot{full = true}, true, nil
1402 | 	case Slot:
1403 | 		if data.tag == .None {
1404 | 			return slot_with_full(data, true), true, nil  // <== [calls slot_with_full]
1405 | 		}
1406 | 		return data, true, nil
1407 | 	case Uint:
1408 | 		return Slot{value = i64(data.value), tag = .Uint}, true, nil
1409 | 	case u64:
1410 | 		return Slot{value = i64(data), tag = .Uint}, true, nil
1411 | 	case Int:
1412 | 		return Slot{value = data.value, tag = .Int}, true, nil
1413 | 	case i64:
1414 | 		return Slot{value = data, tag = .Int}, true, nil
1415 | 	case Float:
1416 | 		return Slot{value = transmute(i64)data.value, tag = .Float}, true, nil
1417 | 	case f64:
1418 | 		return Slot{value = transmute(i64)data, tag = .Float}, true, nil
1419 | 	case string:
1420 | 		b := Bytes{value = transmute([]u8)data}
1421 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1422 | 			buf: [8]u8
1423 | 			copy(buf[:], b.value)
1424 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1425 | 		}
1426 | 		return {}, false, nil
1427 | 	case []u8:
1428 | 		b := Bytes{value = data}
1429 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1430 | 			buf: [8]u8
1431 | 			copy(buf[:], b.value)
1432 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1433 | 		}
1434 | 		return {}, false, nil
1435 | 	case Bytes:
1436 | 		if data.format_tag != nil && len(data.format_tag) != 2 {
1437 | 			return {}, false, .Invalid_Format_Tag_Size
1438 | 		}
1439 | 		if bytes_is_short(data) {  // <== [calls bytes_is_short]
1440 | 			buf: [8]u8
1441 | 			copy(buf[:], data.value)
1442 | 			if data.format_tag != nil {
1443 | 				copy(buf[6:8], data.format_tag)
1444 | 			}
1445 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes, full = data.format_tag != nil}, true, nil
1446 | 		}
1447 | 		return {}, false, nil
1448 | 	}
1449 | 	return {}, false, nil
1450 | }
```

#### [`_encode_writeable_data`](../../xitdb/database.odin#L1452-L1483) — `DEPTH 4` (`L1452–L1483`)

```odin
1452 | @(private)
1453 | _encode_writeable_data :: proc(db: ^Database, slot_ptr: Slot_Pointer, write_data: Writeable_Data) -> (slot: Slot, err: Error) {
1454 | 	switch data in write_data {
1455 | 	case nil:
1456 | 		slot = Slot{}
1457 | 	case Slot:
1458 | 		slot = data
1459 | 	case Uint:
1460 | 		slot = Slot{value = i64(data.value), tag = .Uint}
1461 | 	case u64:
1462 | 		slot = Slot{value = i64(data), tag = .Uint}
1463 | 	case Int:
1464 | 		slot = Slot{value = data.value, tag = .Int}
1465 | 	case i64:
1466 | 		slot = Slot{value = data, tag = .Int}
1467 | 	case Float:
1468 | 		slot = Slot{value = transmute(i64)data.value, tag = .Float}
1469 | 	case f64:
1470 | 		slot = Slot{value = transmute(i64)data, tag = .Float}
1471 | 	case string:
1472 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = transmute([]u8)data}) or_return  // <== [calls _encode_bytes_slot]
1473 | 	case []u8:
1474 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = data}) or_return  // <== [calls _encode_bytes_slot]
1475 | 	case Bytes:
1476 | 		slot = _encode_bytes_slot(db, slot_ptr, data) or_return  // <== [calls _encode_bytes_slot]
1477 | 	}
1478 | 
1479 | 	if slot.tag == .None {
1480 | 		slot = slot_with_full(slot, true)  // <== [calls slot_with_full]
1481 | 	}
1482 | 	return slot, nil
1483 | }
```

#### [`_encode_bytes_slot`](../../xitdb/database.odin#L1485-L1533) — `DEPTH 5` (`L1485–L1533`)

```odin
1485 | @(private)
1486 | _encode_bytes_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer, data: Bytes) -> (res: Slot, err: Error) {
1487 | 	if data.format_tag != nil && len(data.format_tag) != 2 {
1488 | 		return {}, .Invalid_Format_Tag_Size
1489 | 	}
1490 | 	if bytes_is_short(data) {  // <== [calls bytes_is_short]
1491 | 		buf: [8]u8
1492 | 		copy(buf[:], data.value)
1493 | 		if data.format_tag != nil {
1494 | 			copy(buf[6:8], data.format_tag)
1495 | 		}
1496 | 		uval := endian.unchecked_get_u64be(buf[:])
1497 | 		return Slot{
1498 | 			value = i64(uval),
1499 | 			tag   = .Short_Bytes,
1500 | 			full  = data.format_tag != nil,
1501 | 		}, nil
1502 | 	}
1503 | 	if is_root(slot_ptr) {  // <== [calls is_root]
1504 | 		return {}, .Cursor_Not_Writeable
1505 | 	}
1506 | 	if db.tx_start == nil {
1507 | 		return {}, .Expected_Tx_Start
1508 | 	}
1509 | 	ptr_pos := core_length(db.core) or_return  // <== [calls core_length]
1510 | 	core_seek_to(db.core, ptr_pos) or_return  // <== [calls core_seek_to]
1511 | 	has_ft := data.format_tag != nil
1512 | 	total_len := 8 + len(data.value) + (2 if has_ft else 0)
1513 | 	if total_len <= 256 {
1514 | 		buf: [256]u8 = ---
1515 | 		endian.unchecked_put_u64be(buf[0:8], u64(len(data.value)))
1516 | 		copy(buf[8 : 8 + len(data.value)], data.value)
1517 | 		if has_ft {
1518 | 			copy(buf[8 + len(data.value) : total_len], data.format_tag)
1519 | 		}
1520 | 		core_write_all(db.core, buf[:total_len]) or_return  // <== [calls core_write_all]
1521 | 	} else {
1522 | 		core_write_long(db.core, i64(len(data.value))) or_return  // <== [calls core_write_long]
1523 | 		core_write_all(db.core, data.value) or_return  // <== [calls core_write_all]
1524 | 		if has_ft {
1525 | 			core_write_all(db.core, data.format_tag) or_return  // <== [calls core_write_all]
1526 | 		}
1527 | 	}
1528 | 	return Slot{
1529 | 		value = ptr_pos,
1530 | 		tag   = .Bytes,
1531 | 		full  = has_ft,
1532 | 	}, nil
1533 | }
```

### `xitdb/dsl.odin` (24 procedures · 862 lines: [`L50–L52`](../../xitdb/dsl.odin#L50-L52), [`L54–L56`](../../xitdb/dsl.odin#L54-L56), [`L122–L152`](../../xitdb/dsl.odin#L122-L152), [`L154–L260`](../../xitdb/dsl.odin#L154-L260), [`L262–L294`](../../xitdb/dsl.odin#L262-L294), [`L296–L314`](../../xitdb/dsl.odin#L296-L314), [`L317–L407`](../../xitdb/dsl.odin#L317-L407), [`L410–L424`](../../xitdb/dsl.odin#L410-L424), [`L627–L637`](../../xitdb/dsl.odin#L627-L637), [`L655–L664`](../../xitdb/dsl.odin#L655-L664), [`L698–L702`](../../xitdb/dsl.odin#L698-L702), [`L754–L756`](../../xitdb/dsl.odin#L754-L756), [`L1035–L1092`](../../xitdb/dsl.odin#L1035-L1092), [`L1686–L1694`](../../xitdb/dsl.odin#L1686-L1694), [`L1697–L1707`](../../xitdb/dsl.odin#L1697-L1707), [`L1709–L1732`](../../xitdb/dsl.odin#L1709-L1732), [`L1744–L1763`](../../xitdb/dsl.odin#L1744-L1763), [`L1779–L1829`](../../xitdb/dsl.odin#L1779-L1829), [`L1831–L1858`](../../xitdb/dsl.odin#L1831-L1858), [`L1860–L1939`](../../xitdb/dsl.odin#L1860-L1939), [`L1941–L1967`](../../xitdb/dsl.odin#L1941-L1967), [`L1985–L1996`](../../xitdb/dsl.odin#L1985-L1996), [`L1998–L2003`](../../xitdb/dsl.odin#L1998-L2003), [`L2005–L2209`](../../xitdb/dsl.odin#L2005-L2209))

#### [`al`](../../xitdb/dsl.odin#L50-L52) — `DEPTH 3` (`L50–L52`)

```odin
  50 | al :: proc(index: i64) -> Path_Step {
  51 | 	return Path_Step{kind = .Array_List_Idx, index = index}
  52 | }
```

#### [`ll`](../../xitdb/dsl.odin#L54-L56) — `DEPTH 3` (`L54–L56`)

```odin
  54 | ll :: proc(index: i64) -> Path_Step {
  55 | 	return Path_Step{kind = .Linked_List_Idx, index = index}
  56 | }
```

#### [`parse_selector`](../../xitdb/dsl.odin#L122-L152) — `DEPTH 1` (`L122–L152`)

```odin
 122 | parse_selector :: proc(selector: string, allocator := context.temp_allocator) -> (res: Parsed_Selector, err: Error) {
 123 | 	s := strings.trim_space(selector)
 124 | 	if len(s) == 0 {
 125 | 		return {}, nil
 126 | 	}
 127 | 
 128 | 	i := 0
 129 | 	if s[i] == '@' {
 130 | 		i += 1
 131 | 		start := i
 132 | 		if i < len(s) && s[i] == '-' {
 133 | 			i += 1
 134 | 		}
 135 | 		for i < len(s) && s[i] >= '0' && s[i] <= '9' {
 136 | 			i += 1
 137 | 		}
 138 | 		if i == start || (i == start + 1 && s[start] == '-') {
 139 | 			return {}, .Invalid_Range
 140 | 		}
 141 | 		m_idx, ok := strconv.parse_i64(s[start:i])
 142 | 		if !ok {
 143 | 			return {}, .Invalid_Range
 144 | 		}
 145 | 		res.has_moment = true
 146 | 		res.moment_index = m_idx
 147 | 	}
 148 | 
 149 | 	steps := parse_steps(s[i:], allocator) or_return  // <== [calls parse_steps]
 150 | 	res.steps = steps
 151 | 	return res, nil
 152 | }
```

#### [`parse_steps`](../../xitdb/dsl.odin#L154-L260) — `DEPTH 1` (`L154–L260`)

```odin
 154 | parse_steps :: proc(path_str: string, allocator := context.temp_allocator) -> (res: []Path_Step, err: Error) {
 155 | 	s := strings.trim_space(path_str)
 156 | 	steps := make([dynamic]Path_Step, 0, 8, allocator)
 157 | 	i := 0
 158 | 
 159 | 	for i < len(s) {
 160 | 		ch := s[i]
 161 | 		switch ch {
 162 | 		case '.':
 163 | 			i += 1
 164 | 			key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 165 | 			append(&steps, Path_Step{kind = .Hash_Map_Key, key = key})
 166 | 			i = next_i
 167 | 
 168 | 		case '#':
 169 | 			i += 1
 170 | 			if i < len(s) && s[i] == '%' {
 171 | 				i += 1
 172 | 				key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 173 | 				append(&steps, Path_Step{kind = .Counted_Set_Member, key = key})
 174 | 				i = next_i
 175 | 			} else {
 176 | 				key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 177 | 				append(&steps, Path_Step{kind = .Counted_Hash_Map_Key, key = key})
 178 | 				i = next_i
 179 | 			}
 180 | 
 181 | 		case '$':
 182 | 			i += 1
 183 | 			key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 184 | 			append(&steps, Path_Step{kind = .Sorted_Map_Key, key = key})
 185 | 			i = next_i
 186 | 
 187 | 		case '%':
 188 | 			i += 1
 189 | 			key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 190 | 			append(&steps, Path_Step{kind = .Hash_Set_Member, key = key})
 191 | 			i = next_i
 192 | 
 193 | 		case '^':
 194 | 			i += 1
 195 | 			key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 196 | 			append(&steps, Path_Step{kind = .Sorted_Set_Member, key = key})
 197 | 			i = next_i
 198 | 
 199 | 		case '[':
 200 | 			if i + 1 < len(s) && s[i + 1] == '[' {
 201 | 				// Linked_Array_List index: [[i]]
 202 | 				i += 2
 203 | 				start := i
 204 | 				for i < len(s) && s[i] != ']' {
 205 | 					i += 1
 206 | 				}
 207 | 				if i + 1 >= len(s) || s[i] != ']' || s[i + 1] != ']' {
 208 | 					return nil, .Invalid_Range
 209 | 				}
 210 | 				idx_str := strings.trim_space(s[start:i])
 211 | 				idx, ok := strconv.parse_i64(idx_str)
 212 | 				if !ok {
 213 | 					return nil, .Invalid_Range
 214 | 				}
 215 | 				append(&steps, Path_Step{kind = .Linked_List_Idx, index = idx})
 216 | 				i += 2
 217 | 			} else if i + 1 < len(s) && (s[i + 1] == '"' || s[i + 1] == '\'') {
 218 | 				// Bracketed map key: ["key"] — inherits collection kind if preceded by $key or #key
 219 | 				key, next_i := _parse_bracketed_string(s, i) or_return  // <== [calls _parse_bracketed_string]
 220 | 				step_kind := Step_Kind.Hash_Map_Key
 221 | 				if len(steps) == 1 {
 222 | 					if steps[0].kind == .Counted_Hash_Map_Key {
 223 | 						steps[0].kind = .Hash_Map_Key
 224 | 						step_kind = .Counted_Hash_Map_Key
 225 | 					} else if steps[0].kind == .Sorted_Map_Key {
 226 | 						steps[0].kind = .Hash_Map_Key
 227 | 						step_kind = .Sorted_Map_Key
 228 | 					}
 229 | 				}
 230 | 				append(&steps, Path_Step{kind = step_kind, key = key})
 231 | 				i = next_i
 232 | 			} else {
 233 | 				// Array_List index: [i]
 234 | 				i += 1
 235 | 				start := i
 236 | 				for i < len(s) && s[i] != ']' {
 237 | 					i += 1
 238 | 				}
 239 | 				if i >= len(s) || s[i] != ']' {
 240 | 					return nil, .Invalid_Range
 241 | 				}
 242 | 				idx_str := strings.trim_space(s[start:i])
 243 | 				idx, ok := strconv.parse_i64(idx_str)
 244 | 				if !ok {
 245 | 					return nil, .Invalid_Range
 246 | 				}
 247 | 				append(&steps, Path_Step{kind = .Array_List_Idx, index = idx})
 248 | 				i += 1
 249 | 			}
 250 | 
 251 | 		case:
 252 | 			// Bare leading identifier defaults to Hash_Map_Key
 253 | 			key, next_i := _parse_step_ident_or_bracket(s, i) or_return  // <== [calls _parse_step_ident_or_bracket]
 254 | 			append(&steps, Path_Step{kind = .Hash_Map_Key, key = key})
 255 | 			i = next_i
 256 | 		}
 257 | 	}
 258 | 
 259 | 	return steps[:], nil
 260 | }
```

#### [`_parse_step_ident_or_bracket`](../../xitdb/dsl.odin#L262-L294) — `DEPTH 2` (`L262–L294`)

```odin
 262 | @(private = "file")
 263 | _parse_step_ident_or_bracket :: proc(s: string, start_i: int) -> (key: string, next_i: int, err: Error) {
 264 | 	if start_i >= len(s) {
 265 | 		return "", start_i, .Invalid_Range
 266 | 	}
 267 | 	if s[start_i] == '[' {
 268 | 		return _parse_bracketed_string(s, start_i)  // <== [calls _parse_bracketed_string]
 269 | 	}
 270 | 	if s[start_i] == '"' || s[start_i] == '\'' {
 271 | 		quote := s[start_i]
 272 | 		i := start_i + 1
 273 | 		key_start := i
 274 | 		for i < len(s) && s[i] != quote {
 275 | 			i += 1
 276 | 		}
 277 | 		if i >= len(s) || s[i] != quote {
 278 | 			return "", start_i, .Invalid_Range
 279 | 		}
 280 | 		return s[key_start:i], i + 1, nil
 281 | 	}
 282 | 	i := start_i
 283 | 	for i < len(s) {
 284 | 		ch := s[i]
 285 | 		if ch == '.' || ch == '[' || ch == '#' || ch == '$' || ch == '%' || ch == '^' {
 286 | 			break
 287 | 		}
 288 | 		i += 1
 289 | 	}
 290 | 	if i == start_i {
 291 | 		return "", start_i, .Invalid_Range
 292 | 	}
 293 | 	return s[start_i:i], i, nil
 294 | }
```

#### [`_parse_bracketed_string`](../../xitdb/dsl.odin#L296-L314) — `DEPTH 2` (`L296–L314`)

```odin
 296 | @(private = "file")
 297 | _parse_bracketed_string :: proc(s: string, start_i: int) -> (key: string, next_i: int, err: Error) {
 298 | 	if start_i + 2 >= len(s) || s[start_i] != '[' {
 299 | 		return "", start_i, .Invalid_Range
 300 | 	}
 301 | 	quote := s[start_i + 1]
 302 | 	if quote != '"' && quote != '\'' {
 303 | 		return "", start_i, .Invalid_Range
 304 | 	}
 305 | 	i := start_i + 2
 306 | 	key_start := i
 307 | 	for i < len(s) && s[i] != quote {
 308 | 		i += 1
 309 | 	}
 310 | 	if i + 1 >= len(s) || s[i] != quote || s[i + 1] != ']' {
 311 | 		return "", start_i, .Invalid_Range
 312 | 	}
 313 | 	return s[key_start:i], i + 2, nil
 314 | }
```

#### [`read_steps_cursor`](../../xitdb/dsl.odin#L317-L407) — `DEPTH 1` (`L317–L407`)

```odin
 317 | read_steps_cursor :: proc(start: Read_Cursor, steps: []Path_Step) -> (res: Maybe(Read_Cursor), err: Error) {
 318 | 	cur := start
 319 | 	for step in steps {
 320 | 		switch step.kind {
 321 | 		case .Hash_Map_Key:
 322 | 			m := read_hash_map_init(cur) or_return  // <== [calls read_hash_map_init]
 323 | 			next_maybe := hash_map_get_cursor(m, step.key) or_return  // <== [calls hash_map_get_cursor]
 324 | 			next_cur, ok := next_maybe.?
 325 | 			if !ok {
 326 | 				return nil, nil
 327 | 			}
 328 | 			cur = next_cur
 329 | 
 330 | 		case .Counted_Hash_Map_Key:
 331 | 			cm := read_counted_hash_map_init(cur) or_return  // <== [calls read_counted_hash_map_init]
 332 | 			next_maybe := hash_map_get_cursor(cm.read_hash_map, step.key) or_return  // <== [calls hash_map_get_cursor]
 333 | 			next_cur, ok := next_maybe.?
 334 | 			if !ok {
 335 | 				return nil, nil
 336 | 			}
 337 | 			cur = next_cur
 338 | 
 339 | 		case .Sorted_Map_Key:
 340 | 			if slot_ptr := cursor_resolved(cur) or_return; slot_ptr.slot.tag == .Hash_Map || slot_ptr.slot.tag == .Counted_Hash_Map {  // <== [calls cursor_resolved]
 341 | 				m := read_hash_map_init(cur) or_return  // <== [calls read_hash_map_init]
 342 | 				next_maybe := hash_map_get_cursor(m, step.key) or_return  // <== [calls hash_map_get_cursor]
 343 | 				next_cur, ok := next_maybe.?
 344 | 				if !ok {
 345 | 					return nil, nil
 346 | 				}
 347 | 				cur = next_cur
 348 | 			} else {
 349 | 				sm_col := read_sorted_map_init(cur) or_return  // <== [calls read_sorted_map_init]
 350 | 				next_maybe := sorted_map_get_cursor(sm_col, step.key) or_return  // <== [calls sorted_map_get_cursor]
 351 | 				next_cur, ok := next_maybe.?
 352 | 				if !ok {
 353 | 					return nil, nil
 354 | 				}
 355 | 				cur = next_cur
 356 | 			}
 357 | 
 358 | 		case .Array_List_Idx:
 359 | 			al_col := read_array_list_init(cur) or_return  // <== [calls read_array_list_init]
 360 | 			next_maybe := array_list_get_cursor(al_col, step.index) or_return  // <== [calls array_list_get_cursor]
 361 | 			next_cur, ok := next_maybe.?
 362 | 			if !ok {
 363 | 				return nil, nil
 364 | 			}
 365 | 			cur = next_cur
 366 | 
 367 | 		case .Linked_List_Idx:
 368 | 			ll_col := read_linked_array_list_init(cur) or_return  // <== [calls read_linked_array_list_init]
 369 | 			next_maybe := linked_array_list_get_cursor(ll_col, step.index) or_return  // <== [calls linked_array_list_get_cursor]
 370 | 			next_cur, ok := next_maybe.?
 371 | 			if !ok {
 372 | 				return nil, nil
 373 | 			}
 374 | 			cur = next_cur
 375 | 
 376 | 		case .Hash_Set_Member:
 377 | 			hs_col := read_hash_set_init(cur) or_return  // <== [calls read_hash_set_init]
 378 | 			next_maybe := hash_set_get_cursor(hs_col, step.key) or_return  // <== [calls hash_set_get_cursor]
 379 | 			next_cur, ok := next_maybe.?
 380 | 			if !ok {
 381 | 				return nil, nil
 382 | 			}
 383 | 			cur = next_cur
 384 | 
 385 | 		case .Counted_Set_Member:
 386 | 			cs_col := read_counted_hash_set_init(cur) or_return  // <== [calls read_counted_hash_set_init]
 387 | 			next_maybe := hash_set_get_cursor(cs_col.read_hash_set, step.key) or_return  // <== [calls hash_set_get_cursor]
 388 | 			next_cur, ok := next_maybe.?
 389 | 			if !ok {
 390 | 				return nil, nil
 391 | 			}
 392 | 			cur = next_cur
 393 | 
 394 | 		case .Sorted_Set_Member:
 395 | 			ss_col := read_sorted_set_init(cur) or_return  // <== [calls read_sorted_set_init]
 396 | 			next_maybe := cursor_read_path(ss_col.cursor, []Path_Part{  // <== [calls cursor_read_path]
 397 | 				Sorted_Map_Get{target = Sorted_Map_Get_Key{key = transmute([]u8)step.key}},
 398 | 			}) or_return
 399 | 			next_cur, ok := next_maybe.?
 400 | 			if !ok {
 401 | 				return nil, nil
 402 | 			}
 403 | 			cur = next_cur
 404 | 		}
 405 | 	}
 406 | 	return cur, nil
 407 | }
```

#### [`select_cursor`](../../xitdb/dsl.odin#L410-L424) — `ENTRY POINT` (`L410–L424`)

```odin
 410 | select_cursor :: proc(db: ^Database, selector: string) -> (res: Maybe(Read_Cursor), err: Error) {
 411 | 	parsed := parse_selector(selector, context.temp_allocator) or_return  // <== [calls parse_selector]
 412 | 	rc := database_root_cursor(db).read_cursor  // <== [calls database_root_cursor]
 413 | 	start := rc
 414 | 	if parsed.has_moment {
 415 | 		history := read_array_list_init(rc) or_return  // <== [calls read_array_list_init]
 416 | 		mc_maybe := array_list_get_cursor(history, parsed.moment_index) or_return  // <== [calls array_list_get_cursor]
 417 | 		mc, ok := mc_maybe.?
 418 | 		if !ok {
 419 | 			return nil, nil
 420 | 		}
 421 | 		start = mc
 422 | 	}
 423 | 	return read_steps_cursor(start, parsed.steps)  // <== [calls read_steps_cursor]
 424 | }
```

#### [`tx_init`](../../xitdb/dsl.odin#L627-L637) — `ENTRY POINT` (`L627–L637`)

```odin
 627 | tx_init :: proc(db: ^Database, base_moment: Maybe(i64) = -1, track_changes := false, allocator := context.temp_allocator) -> Tx {
 628 | 	return Tx{
 629 | 		db            = db,
 630 | 		base_moment   = base_moment,
 631 | 		track_changes = track_changes,
 632 | 		meta          = make([dynamic]Tx_Meta_Entry, 0, 4, allocator),
 633 | 		ops           = make([dynamic]Tx_Op, 0, 8, allocator),
 634 | 		index_rules   = make([dynamic]Secondary_Index_Rule, 0, 2, allocator),
 635 | 		allocator     = allocator,
 636 | 	}
 637 | }
```

#### [`diff_changes_destroy`](../../xitdb/dsl.odin#L655-L664) — `DEPTH 1` (`L655–L664`)

```odin
 655 | diff_changes_destroy :: proc(changes: []Tx_Change, allocator := context.allocator) {
 656 | 	for chg in changes {
 657 | 		if len(chg.path_str) > 0 {
 658 | 			delete(chg.path_str, allocator)
 659 | 		}
 660 | 	}
 661 | 	if changes != nil {
 662 | 		delete(changes, allocator)
 663 | 	}
 664 | }
```

#### [`tx_put`](../../xitdb/dsl.odin#L698-L702) — `ENTRY POINT` (`L698–L702`)

```odin
 698 | tx_put :: proc(tx: ^Tx, path_str: string, val: Writeable_Data) -> Error {
 699 | 	steps := parse_steps(path_str, tx.allocator) or_return  // <== [calls parse_steps]
 700 | 	append(&tx.ops, Tx_Op{kind = .Put, steps = steps, val = val})
 701 | 	return nil
 702 | }
```

#### [`tx_with_cursor`](../../xitdb/dsl.odin#L754-L756) — `ENTRY POINT` (`L754–L756`)

```odin
 754 | tx_with_cursor :: proc(tx: ^Tx, fn: Context_Function, user_data: rawptr = nil) {
 755 | 	append(&tx.ops, Tx_Op{kind = .Callback, callback = fn, user_data = user_data})
 756 | }
```

#### [`tx_commit`](../../xitdb/dsl.odin#L1035-L1092) — `ENTRY POINT` (`L1035–L1092`)

```odin
1035 | tx_commit :: proc(tx: ^Tx) -> (report: Tx_Report, err: Error) {
1036 | 	rc := database_root_cursor(tx.db)  // <== [calls database_root_cursor]
1037 | 	history := write_array_list_init(rc) or_return  // <== [calls write_array_list_init]
1038 | 	hist_count := array_list_count(history.read_array_list) or_return  // <== [calls array_list_count]
1039 | 
1040 | 	ectx := _Tx_Exec_Ctx{
1041 | 		tx       = tx,
1042 | 		recorded = make([dynamic]Tx_Change, 0, len(tx.ops), tx.allocator),
1043 | 	}
1044 | 	defer if err != nil {
1045 | 		diff_changes_destroy(ectx.recorded[:], tx.allocator)  // <== [calls diff_changes_destroy]
1046 | 	}
1047 | 
1048 | 	if bm, has_bm := tx.base_moment.?; has_bm && hist_count > 0 {
1049 | 		resolved_idx := bm if bm >= 0 else hist_count + bm
1050 | 		if resolved_idx < 0 || resolved_idx >= hist_count {
1051 | 			return {}, .Key_Not_Found
1052 | 		}
1053 | 		slot_maybe := array_list_get_slot(history.read_array_list, resolved_idx) or_return  // <== [calls array_list_get_slot]
1054 | 		if s, ok := slot_maybe.?; ok {
1055 | 			ectx.base_slot = s
1056 | 			ectx.has_parent = true
1057 | 			ectx.resolved_parent = resolved_idx
1058 | 		}
1059 | 	}
1060 | 
1061 | 	array_list_append_context(&history, ectx.base_slot, _execute_tx_cb, &ectx) or_return  // <== [calls array_list_append_context]
1062 | 
1063 | 	new_moment_idx := hist_count
1064 | 	after_cur_maybe := array_list_get_cursor(history.read_array_list, new_moment_idx) or_return  // <== [calls array_list_get_cursor]
1065 | 	after_map := read_hash_map_init(after_cur_maybe.?) or_return  // <== [calls read_hash_map_init]
1066 | 
1067 | 	before_map: Maybe(Read_Hash_Map)
1068 | 	if ectx.has_parent {
1069 | 		before_cur_maybe := array_list_get_cursor(history.read_array_list, ectx.resolved_parent) or_return  // <== [calls array_list_get_cursor]
1070 | 		if bc, ok := before_cur_maybe.?; ok {
1071 | 			bm := read_hash_map_init(bc) or_return  // <== [calls read_hash_map_init]
1072 | 			before_map = bm
1073 | 		}
1074 | 	}
1075 | 
1076 | 	tx_meta_map: Maybe(Read_Hash_Map)
1077 | 	tx_cur_maybe := hash_map_get_cursor(after_map, "__tx") or_return  // <== [calls hash_map_get_cursor]
1078 | 	if tc, ok := tx_cur_maybe.?; ok {
1079 | 		tm := read_hash_map_init(tc) or_return  // <== [calls read_hash_map_init]
1080 | 		tx_meta_map = tm
1081 | 	}
1082 | 
1083 | 	committed := database_committed_size(tx.db) or_return  // <== [calls database_committed_size]
1084 | 	return Tx_Report{
1085 | 		moment_index = new_moment_idx,
1086 | 		commit_size  = committed,
1087 | 		before       = before_map,
1088 | 		after        = after_map,
1089 | 		tx_meta      = tx_meta_map,
1090 | 		changes      = ectx.recorded[:],
1091 | 	}, nil
1092 | }
```

#### [`_is_collection_tag`](../../xitdb/dsl.odin#L1686-L1694) — `DEPTH 1` (`L1686–L1694`)

```odin
1686 | @(private = "file")
1687 | _is_collection_tag :: proc(tag: Tag) -> bool {
1688 | 	#partial switch tag {
1689 | 	case .Array_List, .Linked_Array_List, .Hash_Map, .Counted_Hash_Map,
1690 | 	     .Hash_Set, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
1691 | 		return true
1692 | 	}
1693 | 	return false
1694 | }
```

#### [`pull`](../../xitdb/dsl.odin#L1697-L1707) — `ENTRY POINT` (`L1697–L1707`)

```odin
1697 | pull :: proc(cursor: Read_Cursor, pattern: string, allocator := context.temp_allocator) -> (res: Pull_Value, err: Error) {
1698 | 	p := strings.trim_space(pattern)
1699 | 	if len(p) == 0 || p == "*" {
1700 | 		slot := cursor_slot(cursor) or_return  // <== [calls cursor_slot]
1701 | 		if !_is_collection_tag(slot.tag) {  // <== [calls _is_collection_tag]
1702 | 			return _pull_scalar_slot(cursor, slot, allocator)  // <== [calls _pull_scalar_slot]
1703 | 		}
1704 | 	}
1705 | 	visited := make(map[i64]bool, 16, context.temp_allocator)
1706 | 	return _pull_with_visited(cursor, pattern, &visited, allocator)  // <== [calls _pull_with_visited]
1707 | }
```

#### [`_pull_scalar_slot`](../../xitdb/dsl.odin#L1709-L1732) — `DEPTH 1` (`L1709–L1732`)

```odin
1709 | @(private = "file")
1710 | _pull_scalar_slot :: proc(cursor: Read_Cursor, slot: Slot, allocator: runtime.Allocator) -> (res: Pull_Value, err: Error) {
1711 | 	#partial switch slot.tag {
1712 | 	case .None:
1713 | 		return nil, nil
1714 | 	case .Uint:
1715 | 		u := cursor_read_uint(cursor) or_return  // <== [calls cursor_read_uint]
1716 | 		return u, nil
1717 | 	case .Int:
1718 | 		i := cursor_read_int(cursor) or_return  // <== [calls cursor_read_int]
1719 | 		return i, nil
1720 | 	case .Float:
1721 | 		f := cursor_read_float(cursor) or_return  // <== [calls cursor_read_float]
1722 | 		return f, nil
1723 | 	case .Short_Bytes, .Bytes:
1724 | 		if slot.full {
1725 | 			obj := cursor_read_bytes_object(cursor, 0, allocator) or_return  // <== [calls cursor_read_bytes_object]
1726 | 			return obj, nil
1727 | 		}
1728 | 		s := cursor_read_string(cursor, 0, allocator) or_return  // <== [calls cursor_read_string]
1729 | 		return s, nil
1730 | 	}
1731 | 	return nil, .Unexpected_Tag
1732 | }
```

#### [`_pull_with_visited`](../../xitdb/dsl.odin#L1744-L1763) — `DEPTH 1` (`L1744–L1763`)

```odin
1744 | @(private = "file")
1745 | _pull_with_visited :: proc(cursor: Read_Cursor, pattern: string, visited: ^map[i64]bool, allocator: runtime.Allocator) -> (res: Pull_Value, err: Error) {
1746 | 	p := strings.trim_space(pattern)
1747 | 	if len(p) == 0 || p == "*" {
1748 | 		return _pull_wildcard(cursor, visited, allocator)  // <== [calls _pull_wildcard]
1749 | 	}
1750 | 	if p[0] == '{' && p[len(p) - 1] == '}' {
1751 | 		inner := strings.trim_space(p[1 : len(p) - 1])
1752 | 		specs := _split_top_level_pull_specs(inner, allocator)  // <== [calls _split_top_level_pull_specs]
1753 | 		entries := make([dynamic]Pull_Map_Entry, 0, len(specs), allocator)
1754 | 		for spec in specs {
1755 | 			entry, has_entry := _eval_pull_spec(cursor, spec, visited, allocator) or_return  // <== [calls _eval_pull_spec]
1756 | 			if has_entry {
1757 | 				append(&entries, entry)
1758 | 			}
1759 | 		}
1760 | 		return Pull_Map(entries[:]), nil
1761 | 	}
1762 | 	return _pull_wildcard(cursor, visited, allocator)  // <== [calls _pull_wildcard]
1763 | }
```

#### [`_eval_pull_spec`](../../xitdb/dsl.odin#L1779-L1829) — `DEPTH 2` (`L1779–L1829`)

```odin
1779 | @(private = "file")
1780 | _eval_pull_spec :: proc(cursor: Read_Cursor, spec: string, visited: ^map[i64]bool, allocator: runtime.Allocator) -> (entry: Pull_Map_Entry, found: bool, err: Error) {
1781 | 	s := strings.trim_space(spec)
1782 | 	if len(s) == 0 {
1783 | 		return {}, false, nil
1784 | 	}
1785 | 
1786 | 	brace_idx := strings.index_byte(s, '{')
1787 | 	sub_pattern := "*"
1788 | 	path_part := s
1789 | 	if brace_idx > 0 {
1790 | 		path_part = strings.trim_space(s[:brace_idx])
1791 | 		sub_pattern = strings.trim_space(s[brace_idx:])
1792 | 	}
1793 | 
1794 | 	range_start: i64 = 0
1795 | 	range_end: i64 = -1
1796 | 	has_range := false
1797 | 	if bracket_idx := strings.last_index_byte(path_part, '['); bracket_idx > 0 && strings.has_suffix(path_part, "]") {
1798 | 		inside := path_part[bracket_idx + 1 : len(path_part) - 1]
1799 | 		if dots_idx := strings.index(inside, ".."); dots_idx >= 0 {
1800 | 			r_start, ok1 := strconv.parse_i64(strings.trim_space(inside[:dots_idx]))
1801 | 			r_end, ok2 := strconv.parse_i64(strings.trim_space(inside[dots_idx + 2:]))
1802 | 			if ok1 && ok2 {
1803 | 				range_start = r_start
1804 | 				range_end = r_end
1805 | 				has_range = true
1806 | 				path_part = strings.trim_space(path_part[:bracket_idx])
1807 | 			}
1808 | 		}
1809 | 	}
1810 | 
1811 | 	steps := parse_steps(path_part, allocator) or_return  // <== [calls parse_steps]
1812 | 	if len(steps) == 0 {
1813 | 		return {}, false, nil
1814 | 	}
1815 | 	target_maybe := read_steps_cursor(cursor, steps) or_return  // <== [calls read_steps_cursor]
1816 | 	target_cur, ok := target_maybe.?
1817 | 	if !ok {
1818 | 		return {}, false, nil
1819 | 	}
1820 | 
1821 | 	label := steps[len(steps) - 1].key if len(steps[len(steps) - 1].key) > 0 else path_part
1822 | 	if has_range {
1823 | 		list_vals := _pull_range(target_cur, range_start, range_end, sub_pattern, visited, allocator) or_return  // <== [calls _pull_range]
1824 | 		return Pull_Map_Entry{key = label, val = list_vals}, true, nil
1825 | 	}
1826 | 
1827 | 	pulled := _pull_with_visited(target_cur, sub_pattern, visited, allocator) or_return  // <== [calls _pull_with_visited]
1828 | 	return Pull_Map_Entry{key = label, val = pulled}, true, nil
1829 | }
```

#### [`_pull_range`](../../xitdb/dsl.odin#L1831-L1858) — `DEPTH 3` (`L1831–L1858`)

```odin
1831 | @(private = "file")
1832 | _pull_range :: proc(cursor: Read_Cursor, start_idx, end_idx: i64, sub_pattern: string, visited: ^map[i64]bool, allocator: runtime.Allocator) -> (res: Pull_Value, err: Error) {
1833 | 	slot := cursor_slot(cursor) or_return  // <== [calls cursor_slot]
1834 | 	it: Cursor_Iterator
1835 | 	#partial switch slot.tag {
1836 | 	case .Array_List:
1837 | 		al_col := read_array_list_init(cursor) or_return  // <== [calls read_array_list_init]
1838 | 		it = array_list_iterator_from(al_col, start_idx) or_return  // <== [calls array_list_iterator_from]
1839 | 	case .Linked_Array_List:
1840 | 		ll_col := read_linked_array_list_init(cursor) or_return  // <== [calls read_linked_array_list_init]
1841 | 		it = linked_array_list_iterator_from(ll_col, start_idx) or_return  // <== [calls linked_array_list_iterator_from]
1842 | 	case:
1843 | 		return nil, .Unexpected_Tag
1844 | 	}
1845 | 
1846 | 	limit := end_idx - start_idx
1847 | 	items := make([dynamic]Pull_Value, 0, max(0, int(limit)), allocator)
1848 | 	for i: i64 = 0; i < limit; i += 1 {
1849 | 		c_maybe := cursor_iterator_next(&it) or_return  // <== [calls cursor_iterator_next]
1850 | 		c, ok := c_maybe.?
1851 | 		if !ok {
1852 | 			break
1853 | 		}
1854 | 		v := _pull_with_visited(c, sub_pattern, visited, allocator) or_return  // <== [calls _pull_with_visited]
1855 | 		append(&items, v)
1856 | 	}
1857 | 	return Pull_List(items[:]), nil
1858 | }
```

#### [`_pull_wildcard`](../../xitdb/dsl.odin#L1860-L1939) — `DEPTH 2` (`L1860–L1939`)

```odin
1860 | @(private = "file")
1861 | _pull_wildcard :: proc(cursor: Read_Cursor, visited: ^map[i64]bool, allocator: runtime.Allocator) -> (res: Pull_Value, err: Error) {
1862 | 	slot := cursor_slot(cursor) or_return  // <== [calls cursor_slot]
1863 | 	if _is_collection_tag(slot.tag) {  // <== [calls _is_collection_tag]
1864 | 		if visited[slot.value] {
1865 | 			return nil, nil
1866 | 		}
1867 | 		visited[slot.value] = true
1868 | 	}
1869 | 	defer if _is_collection_tag(slot.tag) {  // <== [calls _is_collection_tag]
1870 | 		delete_key(visited, slot.value)
1871 | 	}
1872 | 
1873 | 	#partial switch slot.tag {
1874 | 	case .None:
1875 | 		return nil, nil
1876 | 	case .Uint:
1877 | 		u := cursor_read_uint(cursor) or_return  // <== [calls cursor_read_uint]
1878 | 		return u, nil
1879 | 	case .Int:
1880 | 		i := cursor_read_int(cursor) or_return  // <== [calls cursor_read_int]
1881 | 		return i, nil
1882 | 	case .Float:
1883 | 		f := cursor_read_float(cursor) or_return  // <== [calls cursor_read_float]
1884 | 		return f, nil
1885 | 	case .Short_Bytes, .Bytes:
1886 | 		if slot.full {
1887 | 			obj := cursor_read_bytes_object(cursor, 0, allocator) or_return  // <== [calls cursor_read_bytes_object]
1888 | 			return obj, nil
1889 | 		}
1890 | 		s := cursor_read_string(cursor, 0, allocator) or_return  // <== [calls cursor_read_string]
1891 | 		return s, nil
1892 | 	case .Array_List, .Linked_Array_List:
1893 | 		it := cursor_iterator(cursor) or_return  // <== [calls cursor_iterator]
1894 | 		items := make([dynamic]Pull_Value, 0, 8, allocator)
1895 | 		for {
1896 | 			c_maybe := cursor_iterator_next(&it) or_return  // <== [calls cursor_iterator_next]
1897 | 			c, ok := c_maybe.?
1898 | 			if !ok {
1899 | 				break
1900 | 			}
1901 | 			v := _pull_wildcard(c, visited, allocator) or_return
1902 | 			append(&items, v)
1903 | 		}
1904 | 		return Pull_List(items[:]), nil
1905 | 	case .Hash_Set, .Counted_Hash_Set, .Sorted_Set:
1906 | 		it := cursor_iterator(cursor) or_return  // <== [calls cursor_iterator]
1907 | 		items := make([dynamic]Pull_Value, 0, 8, allocator)
1908 | 		for {
1909 | 			c_maybe := cursor_iterator_next(&it) or_return  // <== [calls cursor_iterator_next]
1910 | 			c, ok := c_maybe.?
1911 | 			if !ok {
1912 | 				break
1913 | 			}
1914 | 			kv := cursor_read_kv_pair(c, allocator) or_return  // <== [calls cursor_read_kv_pair]
1915 | 			v := _pull_wildcard(kv.key_cursor, visited, allocator) or_return
1916 | 			append(&items, v)
1917 | 		}
1918 | 		return Pull_List(items[:]), nil
1919 | 	case .Hash_Map, .Counted_Hash_Map, .Sorted_Map:
1920 | 		it := cursor_iterator(cursor) or_return  // <== [calls cursor_iterator]
1921 | 		entries := make([dynamic]Pull_Map_Entry, 0, 8, allocator)
1922 | 		for {
1923 | 			c_maybe := cursor_iterator_next(&it) or_return  // <== [calls cursor_iterator_next]
1924 | 			c, ok := c_maybe.?
1925 | 			if !ok {
1926 | 				break
1927 | 			}
1928 | 			kv := cursor_read_kv_pair(c, allocator) or_return  // <== [calls cursor_read_kv_pair]
1929 | 			k_str := cursor_read_string(kv.key_cursor, 0, allocator) or_return  // <== [calls cursor_read_string]
1930 | 			if k_str == "__tx" {
1931 | 				continue
1932 | 			}
1933 | 			v := _pull_wildcard(kv.value_cursor, visited, allocator) or_return
1934 | 			append(&entries, Pull_Map_Entry{key = k_str, val = v})
1935 | 		}
1936 | 		return Pull_Map(entries[:]), nil
1937 | 	}
1938 | 	return nil, .Unexpected_Tag
1939 | }
```

#### [`_split_top_level_pull_specs`](../../xitdb/dsl.odin#L1941-L1967) — `DEPTH 2` (`L1941–L1967`)

```odin
1941 | @(private = "file")
1942 | _split_top_level_pull_specs :: proc(inner: string, allocator: runtime.Allocator) -> []string {
1943 | 	specs := make([dynamic]string, 0, 8, allocator)
1944 | 	depth := 0
1945 | 	start := 0
1946 | 	for i in 0 ..< len(inner) {
1947 | 		ch := inner[i]
1948 | 		if ch == '{' || ch == '[' {
1949 | 			depth += 1
1950 | 		} else if ch == '}' || ch == ']' {
1951 | 			depth -= 1
1952 | 		} else if (ch == ',' || ch == '\n') && depth == 0 {
1953 | 			part := strings.trim_space(inner[start:i])
1954 | 			if len(part) > 0 {
1955 | 				append(&specs, part)
1956 | 			}
1957 | 			start = i + 1
1958 | 		}
1959 | 	}
1960 | 	if start < len(inner) {
1961 | 		part := strings.trim_space(inner[start:])
1962 | 		if len(part) > 0 {
1963 | 			append(&specs, part)
1964 | 		}
1965 | 	}
1966 | 	return specs[:]
1967 | }
```

#### [`diff_moments`](../../xitdb/dsl.odin#L1985-L1996) — `ENTRY POINT` (`L1985–L1996`)

```odin
1985 | diff_moments :: proc(db: ^Database, moment_a, moment_b: i64, include_tx_meta := false, allocator := context.temp_allocator) -> (res: []Tx_Change, err: Error) {
1986 | 	rc := database_root_cursor(db).read_cursor  // <== [calls database_root_cursor]
1987 | 	history := read_array_list_init(rc) or_return  // <== [calls read_array_list_init]
1988 | 	ca_maybe := array_list_get_cursor(history, moment_a) or_return  // <== [calls array_list_get_cursor]
1989 | 	cb_maybe := array_list_get_cursor(history, moment_b) or_return  // <== [calls array_list_get_cursor]
1990 | 	ca, oka := ca_maybe.?
1991 | 	cb, okb := cb_maybe.?
1992 | 	if !oka || !okb {
1993 | 		return nil, .Key_Not_Found
1994 | 	}
1995 | 	return diff_cursors(ca, cb, include_tx_meta, allocator)  // <== [calls diff_cursors]
1996 | }
```

#### [`diff_cursors`](../../xitdb/dsl.odin#L1998-L2003) — `DEPTH 1` (`L1998–L2003`)

```odin
1998 | diff_cursors :: proc(cur_a, cur_b: Read_Cursor, include_tx_meta := false, allocator := context.temp_allocator) -> (res: []Tx_Change, err: Error) {
1999 | 	changes := make([dynamic]Tx_Change, 0, 8, allocator)
2000 | 	visited := make(map[[2]i64]bool, 16, context.temp_allocator)
2001 | 	_diff_recursive(cur_a, cur_b, "", include_tx_meta, &changes, &visited, allocator) or_return  // <== [calls _diff_recursive]
2002 | 	return changes[:], nil
2003 | }
```

#### [`_diff_recursive`](../../xitdb/dsl.odin#L2005-L2209) — `DEPTH 2` (`L2005–L2209`)

```odin
2005 | @(private = "file")
2006 | _diff_recursive :: proc(
2007 | 	cur_a, cur_b: Read_Cursor,
2008 | 	prefix: string,
2009 | 	include_tx_meta: bool,
2010 | 	changes: ^[dynamic]Tx_Change,
2011 | 	visited: ^map[[2]i64]bool,
2012 | 	allocator: runtime.Allocator,
2013 | ) -> Error {
2014 | 	slot_a := cursor_slot(cur_a) or_return  // <== [calls cursor_slot]
2015 | 	slot_b := cursor_slot(cur_b) or_return  // <== [calls cursor_slot]
2016 | 
2017 | 	if slot_a == slot_b {
2018 | 		return nil
2019 | 	}
2020 | 
2021 | 	if _is_collection_tag(slot_a.tag) || _is_collection_tag(slot_b.tag) {  // <== [calls _is_collection_tag]
2022 | 		off_a := slot_a.value if _is_collection_tag(slot_a.tag) else -1  // <== [calls _is_collection_tag]
2023 | 		off_b := slot_b.value if _is_collection_tag(slot_b.tag) else -1  // <== [calls _is_collection_tag]
2024 | 		pair := [2]i64{off_a, off_b}
2025 | 		if visited[pair] {
2026 | 			return nil
2027 | 		}
2028 | 		visited[pair] = true
2029 | 		if off_b != -1 {
2030 | 			visited[[2]i64{-1, off_b}] = true
2031 | 		}
2032 | 	}
2033 | 
2034 | 	empty_cur := Read_Cursor{
2035 | 		slot_ptr = Slot_Pointer{position = nil, slot = Slot{}},
2036 | 		db       = cur_b.db,
2037 | 	}
2038 | 
2039 | 	if slot_a.tag == .None && (slot_b.tag == .Hash_Map || slot_b.tag == .Counted_Hash_Map || slot_b.tag == .Sorted_Map) {
2040 | 		sigil := "." if slot_b.tag == .Hash_Map else ("#" if slot_b.tag == .Counted_Hash_Map else "$")
2041 | 		it_b := cursor_iterator(cur_b) or_return  // <== [calls cursor_iterator]
2042 | 		for {
2043 | 			cb_maybe := cursor_iterator_next(&it_b) or_return  // <== [calls cursor_iterator_next]
2044 | 			cb, ok := cb_maybe.?
2045 | 			if !ok {
2046 | 				break
2047 | 			}
2048 | 			kv_b := cursor_read_kv_pair(cb, context.temp_allocator) or_return  // <== [calls cursor_read_kv_pair]
2049 | 			k_str := cursor_read_string(kv_b.key_cursor, 0, context.temp_allocator) or_return  // <== [calls cursor_read_string]
2050 | 			if !include_tx_meta && len(prefix) == 0 && k_str == "__tx" {
2051 | 				continue
2052 | 			}
2053 | 			child_path := fmt.aprintf("%s%s%s", prefix, sigil, k_str, allocator = allocator)
2054 | 			val_b_slot := cursor_slot(kv_b.value_cursor) or_return  // <== [calls cursor_slot]
2055 | 			if _is_collection_tag(val_b_slot.tag) && !visited[[2]i64{-1, val_b_slot.value}] {  // <== [calls _is_collection_tag]
2056 | 				if len(prefix) == 0 && (val_b_slot.tag == .Array_List || val_b_slot.tag == .Linked_Array_List) {
2057 | 					delete(child_path, allocator)
2058 | 					sub_prefix := fmt.aprintf("%s%s%s", prefix, sigil, k_str, allocator = context.temp_allocator)
2059 | 					_diff_recursive(empty_cur, kv_b.value_cursor, sub_prefix, include_tx_meta, changes, visited, allocator) or_return
2060 | 				} else {
2061 | 					append(changes, Tx_Change{op = .Put, path_str = child_path, old_slot = Slot{}, new_slot = val_b_slot})
2062 | 				}
2063 | 			} else {
2064 | 				append(changes, Tx_Change{op = .Put, path_str = child_path, old_slot = Slot{}, new_slot = val_b_slot})
2065 | 			}
2066 | 		}
2067 | 		return nil
2068 | 	}
2069 | 
2070 | 	if slot_a.tag == .None && (slot_b.tag == .Array_List || slot_b.tag == .Linked_Array_List) {
2071 | 		cnt_b := cursor_count(cur_b) or_return  // <== [calls cursor_count]
2072 | 		is_linked := slot_b.tag == .Linked_Array_List
2073 | 		for i: i64 = 0; i < cnt_b; i += 1 {
2074 | 			step := ll(i) if is_linked else al(i)  // <== [calls ll, al]
2075 | 			eb_maybe := read_steps_cursor(cur_b, []Path_Step{step}) or_return  // <== [calls read_steps_cursor]
2076 | 			eb_slot := cursor_slot(eb_maybe.?) or_return  // <== [calls cursor_slot]
2077 | 			child_path := fmt.aprintf(is_linked ? "%s[[%d]]" : "%s[%d]", prefix, i, allocator = allocator)
2078 | 			append(changes, Tx_Change{op = .Append, path_str = child_path, old_slot = Slot{}, new_slot = eb_slot})
2079 | 		}
2080 | 		return nil
2081 | 	}
2082 | 
2083 | 	if slot_a.tag == slot_b.tag {
2084 | 		#partial switch slot_a.tag {
2085 | 		case .Hash_Map, .Counted_Hash_Map:
2086 | 			sigil := "." if slot_a.tag == .Hash_Map else "#"
2087 | 			map_a := Read_Hash_Map{cursor = cur_a}
2088 | 			map_b := Read_Hash_Map{cursor = cur_b}
2089 | 
2090 | 			it_a := cursor_iterator(cur_a) or_return  // <== [calls cursor_iterator]
2091 | 			for {
2092 | 				ca_maybe := cursor_iterator_next(&it_a) or_return  // <== [calls cursor_iterator_next]
2093 | 				ca, ok := ca_maybe.?
2094 | 				if !ok {
2095 | 					break
2096 | 				}
2097 | 				kv_a := cursor_read_kv_pair(ca, context.temp_allocator) or_return  // <== [calls cursor_read_kv_pair]
2098 | 				k_str := cursor_read_string(kv_a.key_cursor, 0, context.temp_allocator) or_return  // <== [calls cursor_read_string]
2099 | 				if !include_tx_meta && len(prefix) == 0 && k_str == "__tx" {
2100 | 					continue
2101 | 				}
2102 | 				vb_maybe := hash_map_get_cursor(map_b, k_str) or_return  // <== [calls hash_map_get_cursor]
2103 | 				if vb_cur, has_b := vb_maybe.?; has_b {
2104 | 					sub_prefix := fmt.aprintf("%s%s%s", prefix, sigil, k_str, allocator = context.temp_allocator)
2105 | 					_diff_recursive(kv_a.value_cursor, vb_cur, sub_prefix, include_tx_meta, changes, visited, allocator) or_return
2106 | 				} else {
2107 | 					child_path := fmt.aprintf("%s%s%s", prefix, sigil, k_str, allocator = allocator)
2108 | 					val_a_slot := cursor_slot(kv_a.value_cursor) or_return  // <== [calls cursor_slot]
2109 | 					append(changes, Tx_Change{op = .Remove, path_str = child_path, old_slot = val_a_slot, new_slot = Slot{}})
2110 | 				}
2111 | 			}
2112 | 
2113 | 			it_b := cursor_iterator(cur_b) or_return  // <== [calls cursor_iterator]
2114 | 			for {
2115 | 				cb_maybe := cursor_iterator_next(&it_b) or_return  // <== [calls cursor_iterator_next]
2116 | 				cb, ok := cb_maybe.?
2117 | 				if !ok {
2118 | 					break
2119 | 				}
2120 | 				kv_b := cursor_read_kv_pair(cb, context.temp_allocator) or_return  // <== [calls cursor_read_kv_pair]
2121 | 				k_str := cursor_read_string(kv_b.key_cursor, 0, context.temp_allocator) or_return  // <== [calls cursor_read_string]
2122 | 				if !include_tx_meta && len(prefix) == 0 && k_str == "__tx" {
2123 | 					continue
2124 | 				}
2125 | 				va_maybe := hash_map_get_cursor(map_a, k_str) or_return  // <== [calls hash_map_get_cursor]
2126 | 				if va_maybe == nil {
2127 | 					val_b_slot := cursor_slot(kv_b.value_cursor) or_return  // <== [calls cursor_slot]
2128 | 					child_path := fmt.aprintf("%s%s%s", prefix, sigil, k_str, allocator = allocator)
2129 | 					append(changes, Tx_Change{op = .Put, path_str = child_path, old_slot = Slot{}, new_slot = val_b_slot})
2130 | 				}
2131 | 			}
2132 | 			return nil
2133 | 
2134 | 		case .Sorted_Map:
2135 | 			sm_a := Read_Sorted_Map{cursor = cur_a}
2136 | 			sm_b := Read_Sorted_Map{cursor = cur_b}
2137 | 			it_a := cursor_iterator(cur_a) or_return  // <== [calls cursor_iterator]
2138 | 			for {
2139 | 				ca_maybe := cursor_iterator_next(&it_a) or_return  // <== [calls cursor_iterator_next]
2140 | 				ca, ok := ca_maybe.?
2141 | 				if !ok {
2142 | 					break
2143 | 				}
2144 | 				kv_a := cursor_read_kv_pair(ca, context.temp_allocator) or_return  // <== [calls cursor_read_kv_pair]
2145 | 				k_str := cursor_read_string(kv_a.key_cursor, 0, context.temp_allocator) or_return  // <== [calls cursor_read_string]
2146 | 				vb_maybe := sorted_map_get_cursor(sm_b, k_str) or_return  // <== [calls sorted_map_get_cursor]
2147 | 				if vb_cur, has_b := vb_maybe.?; has_b {
2148 | 					sub_prefix := fmt.aprintf("%s$%s", prefix, k_str, allocator = context.temp_allocator)
2149 | 					_diff_recursive(kv_a.value_cursor, vb_cur, sub_prefix, include_tx_meta, changes, visited, allocator) or_return
2150 | 				} else {
2151 | 					child_path := fmt.aprintf("%s$%s", prefix, k_str, allocator = allocator)
2152 | 					val_a_slot := cursor_slot(kv_a.value_cursor) or_return  // <== [calls cursor_slot]
2153 | 					append(changes, Tx_Change{op = .Remove, path_str = child_path, old_slot = val_a_slot, new_slot = Slot{}})
2154 | 				}
2155 | 			}
2156 | 			it_b := cursor_iterator(cur_b) or_return  // <== [calls cursor_iterator]
2157 | 			for {
2158 | 				cb_maybe := cursor_iterator_next(&it_b) or_return  // <== [calls cursor_iterator_next]
2159 | 				cb, ok := cb_maybe.?
2160 | 				if !ok {
2161 | 					break
2162 | 				}
2163 | 				kv_b := cursor_read_kv_pair(cb, context.temp_allocator) or_return  // <== [calls cursor_read_kv_pair]
2164 | 				k_str := cursor_read_string(kv_b.key_cursor, 0, context.temp_allocator) or_return  // <== [calls cursor_read_string]
2165 | 				va_maybe := sorted_map_get_cursor(sm_a, k_str) or_return  // <== [calls sorted_map_get_cursor]
2166 | 				if va_maybe == nil {
2167 | 					val_b_slot := cursor_slot(kv_b.value_cursor) or_return  // <== [calls cursor_slot]
2168 | 					child_path := fmt.aprintf("%s$%s", prefix, k_str, allocator = allocator)
2169 | 					append(changes, Tx_Change{op = .Put, path_str = child_path, old_slot = Slot{}, new_slot = val_b_slot})
2170 | 				}
2171 | 			}
2172 | 			return nil
2173 | 
2174 | 		case .Array_List, .Linked_Array_List:
2175 | 			cnt_a := cursor_count(cur_a) or_return  // <== [calls cursor_count]
2176 | 			cnt_b := cursor_count(cur_b) or_return  // <== [calls cursor_count]
2177 | 			common := min(cnt_a, cnt_b)
2178 | 			is_linked := slot_a.tag == .Linked_Array_List
2179 | 			for i: i64 = 0; i < common; i += 1 {
2180 | 				step := ll(i) if is_linked else al(i)  // <== [calls ll, al]
2181 | 				ea_maybe := read_steps_cursor(cur_a, []Path_Step{step}) or_return  // <== [calls read_steps_cursor]
2182 | 				eb_maybe := read_steps_cursor(cur_b, []Path_Step{step}) or_return  // <== [calls read_steps_cursor]
2183 | 				sub_prefix := fmt.aprintf(is_linked ? "%s[[%d]]" : "%s[%d]", prefix, i, allocator = context.temp_allocator)
2184 | 				_diff_recursive(ea_maybe.?, eb_maybe.?, sub_prefix, include_tx_meta, changes, visited, allocator) or_return
2185 | 			}
2186 | 			if cnt_b > cnt_a {
2187 | 				for i := cnt_a; i < cnt_b; i += 1 {
2188 | 					step := ll(i) if is_linked else al(i)  // <== [calls ll, al]
2189 | 					eb_maybe := read_steps_cursor(cur_b, []Path_Step{step}) or_return  // <== [calls read_steps_cursor]
2190 | 					eb_slot := cursor_slot(eb_maybe.?) or_return  // <== [calls cursor_slot]
2191 | 					child_path := fmt.aprintf(is_linked ? "%s[[%d]]" : "%s[%d]", prefix, i, allocator = allocator)
2192 | 					append(changes, Tx_Change{op = .Append, path_str = child_path, old_slot = Slot{}, new_slot = eb_slot})
2193 | 				}
2194 | 			} else if cnt_b < cnt_a {
2195 | 				cloned_prefix := strings.clone(prefix, allocator)
2196 | 				append(changes, Tx_Change{op = .Slice, path_str = cloned_prefix, old_slot = slot_a, new_slot = slot_b})
2197 | 			}
2198 | 			return nil
2199 | 		}
2200 | 	}
2201 | 
2202 | 	op: Tx_Op_Kind = .Put
2203 | 	if slot_b.tag == .None && !slot_b.full {
2204 | 		op = .Remove
2205 | 	}
2206 | 	cloned_prefix := strings.clone(prefix, allocator)
2207 | 	append(changes, Tx_Change{op = op, path_str = cloned_prefix, old_slot = slot_a, new_slot = slot_b})
2208 | 	return nil
2209 | }
```

### `xitdb/hamt.odin` (3 procedures · 333 lines: [`L15–L240`](../../xitdb/hamt.odin#L15-L240), [`L345–L383`](../../xitdb/hamt.odin#L345-L383), [`L385–L452`](../../xitdb/hamt.odin#L385-L452))

#### [`read_map_slot`](../../xitdb/hamt.odin#L15-L240) — `DEPTH 4` (`L15–L240`)

```odin
  15 | read_map_slot :: proc(
  16 | 	db: ^Database,
  17 | 	index_pos: i64,
  18 | 	key_hash: []u8,
  19 | 	key_offset: u8,
  20 | 	write_mode: Write_Mode,
  21 | 	target: Hash_Map_Get_Target,
  22 | 	frozen_at: i64,
  23 | ) -> (res: Hash_Map_Get_Result, err: Error) {
  24 | 	index_pos := index_pos
  25 | 	key_offset := key_offset
  26 | 	max_offset := (int(db.header.hash_size) * 8) / BIT_COUNT
  27 | 
  28 | 	for {
  29 | 		if int(key_offset) > max_offset {
  30 | 			return {}, .Key_Offset_Exceeded
  31 | 		}
  32 | 
  33 | 		i := hamt_nibble(key_hash, key_offset)  // <== [calls hamt_nibble]
  34 | 		slot_pos := index_pos + i64(SLOT_LENGTH * i)
  35 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  36 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
  37 | 		ptr := slot.value
  38 | 
  39 | 		#partial switch slot.tag {
  40 | 		case .None:
  41 | 			switch write_mode {
  42 | 			case .Read_Only:
  43 | 				return {}, .Key_Not_Found
  44 | 			case .Read_Write:
  45 | 				hash_pos := core_length(db.core) or_return  // <== [calls core_length]
  46 | 				core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
  47 | 				key_slot_pos := hash_pos + i64(db.header.hash_size)
  48 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
  49 | 				kv_pair := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
  50 | 				kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
  51 | 
  52 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
  53 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  54 | 				core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
  55 | 
  56 | 				next_slot_ptr: Slot_Pointer
  57 | 				switch _ in target {
  58 | 				case Hash_Map_Get_KV_Pair:
  59 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
  60 | 				case Hash_Map_Get_Key:
  61 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
  62 | 				case Hash_Map_Get_Value:
  63 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
  64 | 				}
  65 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
  66 | 			}
  67 | 
  68 | 		case .Index:
  69 | 			next_ptr := ptr
  70 | 			if write_mode == .Read_Write {
  71 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
  72 | 				if next_ptr != ptr {
  73 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  74 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
  75 | 				}
  76 | 			}
  77 | 			index_pos = next_ptr
  78 | 			key_offset += 1
  79 | 			continue
  80 | 
  81 | 		case .KV_Pair:
  82 | 			hash_size := int(db.header.hash_size)
  83 | 			kv_len := hash_size + SLOT_LENGTH * 2
  84 | 			stack_hash: [64]u8 = ---
  85 | 			kv_pair: Key_Value_Pair
  86 | 			hash_matches: bool
  87 | 
  88 | 			if kv_slice, in_mem, slice_err := core_slice_at(db.core, ptr, kv_len); in_mem {  // <== [calls core_slice_at]
  89 | 				if slice_err != nil {
  90 | 					return {}, slice_err
  91 | 				}
  92 | 				key_slot := slot_from_slice_raw(kv_slice[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  93 | 				tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
  94 | 				val_slot := slot_from_slice_raw(kv_slice[hash_size + SLOT_LENGTH : kv_len])  // <== [calls slot_from_slice_raw]
  95 | 				tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
  96 | 				hash_matches = bytes.equal(kv_slice[:hash_size], key_hash)
  97 | 				if hash_matches && write_mode == .Read_Only {
  98 | 					key_slot_pos := ptr + i64(hash_size)
  99 | 					value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 100 | 					next_slot_ptr: Slot_Pointer
 101 | 					switch _ in target {
 102 | 					case Hash_Map_Get_KV_Pair:
 103 | 						next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 104 | 					case Hash_Map_Get_Key:
 105 | 						next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = key_slot}
 106 | 					case Hash_Map_Get_Value:
 107 | 						next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = val_slot}
 108 | 					}
 109 | 					return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 110 | 				}
 111 | 				if !hash_matches && write_mode == .Read_Only {
 112 | 					return {}, .Key_Not_Found
 113 | 				}
 114 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 115 | 				copy(hash_buf, kv_slice[:hash_size])
 116 | 				kv_pair = Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}
 117 | 			} else {
 118 | 				core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 119 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 120 | 				kv_pair = kv_pair_read_buf(db.core, hash_buf) or_return  // <== [calls kv_pair_read_buf]
 121 | 				hash_matches = bytes.equal(kv_pair.hash, key_hash)
 122 | 			}
 123 | 
 124 | 			if hash_matches {
 125 | 				if write_mode == .Read_Write {
 126 | 					old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 127 | 					if old {
 128 | 						hash_pos := core_length(db.core) or_return  // <== [calls core_length]
 129 | 						core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
 130 | 						key_slot_pos := hash_pos + i64(hash_size)
 131 | 						value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 132 | 						kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
 133 | 
 134 | 						next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 135 | 						core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 136 | 						core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
 137 | 
 138 | 						next_slot_ptr: Slot_Pointer
 139 | 						switch _ in target {
 140 | 						case Hash_Map_Get_KV_Pair:
 141 | 							next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
 142 | 						case Hash_Map_Get_Key:
 143 | 							next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 144 | 						case Hash_Map_Get_Value:
 145 | 							next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 146 | 						}
 147 | 						return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 148 | 					}
 149 | 				}
 150 | 
 151 | 				key_slot_pos := ptr + i64(hash_size)
 152 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 153 | 				next_slot_ptr: Slot_Pointer
 154 | 				switch _ in target {
 155 | 				case Hash_Map_Get_KV_Pair:
 156 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 157 | 				case Hash_Map_Get_Key:
 158 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 159 | 				case Hash_Map_Get_Value:
 160 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 161 | 				}
 162 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 163 | 			}
 164 | 
 165 | 			// Hash collision - different keys
 166 | 			switch write_mode {
 167 | 			case .Read_Only:
 168 | 				return {}, .Key_Not_Found
 169 | 			case .Read_Write:
 170 | 				diff_offset := int(key_offset) + 1
 171 | 				for diff_offset < max_offset {
 172 | 					if hamt_nibble(kv_pair.hash, u8(diff_offset)) != hamt_nibble(key_hash, u8(diff_offset)) {  // <== [calls hamt_nibble]
 173 | 						break
 174 | 					}
 175 | 					diff_offset += 1
 176 | 				}
 177 | 				if diff_offset >= max_offset {
 178 | 					return {}, .Key_Offset_Exceeded
 179 | 				}
 180 | 
 181 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 182 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 183 | 				cur_index_pos := first_index_pos
 184 | 
 185 | 				for off in int(key_offset) + 1 ..< diff_offset {
 186 | 					nib := hamt_nibble(key_hash, u8(off))  // <== [calls hamt_nibble]
 187 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 188 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 189 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 190 | 					copy(mid_block[SLOT_LENGTH * nib : SLOT_LENGTH * (nib + 1)], sb[:])
 191 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 192 | 					cur_index_pos = child_index_pos
 193 | 				}
 194 | 
 195 | 				next_i := hamt_nibble(kv_pair.hash, u8(diff_offset))  // <== [calls hamt_nibble]
 196 | 				new_i := hamt_nibble(key_hash, u8(diff_offset))  // <== [calls hamt_nibble]
 197 | 				hash_pos := cur_index_pos + INDEX_BLOCK_SIZE
 198 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 199 | 				key_slot_pos := hash_pos + i64(hash_size)
 200 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 201 | 
 202 | 				if hash_size <= 64 {
 203 | 					combined: [INDEX_BLOCK_SIZE + 64 + SLOT_LENGTH * 2]u8
 204 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 205 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 206 | 					copy(combined[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 207 | 					copy(combined[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 208 | 					copy(combined[INDEX_BLOCK_SIZE : INDEX_BLOCK_SIZE + hash_size], key_hash)
 209 | 					core_write_all(db.core, combined[:INDEX_BLOCK_SIZE + kv_len]) or_return  // <== [calls core_write_all]
 210 | 				} else {
 211 | 					new_block: [INDEX_BLOCK_SIZE]u8
 212 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 213 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 214 | 					copy(new_block[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 215 | 					copy(new_block[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 216 | 					core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 217 | 					new_kv := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
 218 | 					kv_pair_write(new_kv, db.core) or_return  // <== [calls kv_pair_write]
 219 | 				}
 220 | 
 221 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 222 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 223 | 
 224 | 				next_slot_ptr: Slot_Pointer
 225 | 				switch _ in target {
 226 | 				case Hash_Map_Get_KV_Pair:
 227 | 					next_slot_ptr = Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH * new_i), slot = next_slot}
 228 | 				case Hash_Map_Get_Key:
 229 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = Slot{}}
 230 | 				case Hash_Map_Get_Value:
 231 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = Slot{}}
 232 | 				}
 233 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
 234 | 			}
 235 | 
 236 | 		case:
 237 | 			return {}, .Unexpected_Tag
 238 | 		}
 239 | 	}
 240 | }
```

#### [`read_array_list_slot_append`](../../xitdb/hamt.odin#L345-L383) — `DEPTH 4` (`L345–L383`)

```odin
 345 | read_array_list_slot_append :: proc(
 346 | 	db: ^Database,
 347 | 	header: Array_List_Header,
 348 | 	write_mode: Write_Mode,
 349 | 	frozen_at: i64,
 350 | ) -> (res: Array_List_Append_Result, err: Error) {
 351 | 	index_pos := header.ptr
 352 | 	key := header.size
 353 | 
 354 | 	prev_shift := radix_shift(key - 1)  // <== [calls radix_shift]
 355 | 	next_shift := radix_shift(key)  // <== [calls radix_shift]
 356 | 
 357 | 	if prev_shift != next_shift {
 358 | 		// Root overflow
 359 | 		next_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 360 | 		core_seek_to(db.core, next_index_pos) or_return  // <== [calls core_seek_to]
 361 | 		new_block: [INDEX_BLOCK_SIZE]u8
 362 | 		sb := slot_to_bytes(Slot{value = index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 363 | 		copy(new_block[:SLOT_LENGTH], sb[:])
 364 | 		core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 365 | 		index_pos = next_index_pos
 366 | 	}
 367 | 
 368 | 	slot_ptr := read_array_list_slot(db, index_pos, key, next_shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 369 | 	pos, pos_ok := slot_ptr.position.?
 370 | 	if !pos_ok {
 371 | 		return {}, .Cursor_Not_Writeable
 372 | 	}
 373 | 	// Clear values left by a rollback or slice
 374 | 	if slot_ptr.slot != (Slot{}) {
 375 | 		slot_ptr = slot_pointer_with_slot(slot_ptr, Slot{})  // <== [calls slot_pointer_with_slot]
 376 | 		core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
 377 | 		core_write_slot(db.core, slot_ptr.slot) or_return  // <== [calls core_write_slot]
 378 | 	}
 379 | 	return Array_List_Append_Result{
 380 | 		header   = Array_List_Header{ptr = index_pos, size = header.size + 1},
 381 | 		slot_ptr = slot_ptr,
 382 | 	}, nil
 383 | }
```

#### [`read_array_list_slot`](../../xitdb/hamt.odin#L385-L452) — `DEPTH 4` (`L385–L452`)

```odin
 385 | read_array_list_slot :: proc(
 386 | 	db: ^Database,
 387 | 	index_pos: i64,
 388 | 	key: i64,
 389 | 	shift: u8,
 390 | 	write_mode: Write_Mode,
 391 | 	frozen_at: i64,
 392 | ) -> (res: Slot_Pointer, err: Error) {
 393 | 	if shift >= MAX_BRANCH_LENGTH {
 394 | 		return {}, .Max_Shift_Exceeded
 395 | 	}
 396 | 
 397 | 	index_pos := index_pos
 398 | 	shift := shift
 399 | 	for {
 400 | 		i := (key >> (u64(shift) * BIT_COUNT)) & i64(MASK)
 401 | 		slot_pos := index_pos + i64(SLOT_LENGTH) * i
 402 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 403 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 404 | 
 405 | 		if shift == 0 {
 406 | 			return Slot_Pointer{position = slot_pos, slot = slot}, nil
 407 | 		}
 408 | 
 409 | 		ptr := slot.value
 410 | 
 411 | 		#partial switch slot.tag {
 412 | 		case .None:
 413 | 			switch write_mode {
 414 | 			case .Read_Only:
 415 | 				return {}, .Key_Not_Found
 416 | 			case .Read_Write:
 417 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 418 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 419 | 				cur_index_pos := first_index_pos
 420 | 				for s := shift - 1; s > 0; s -= 1 {
 421 | 					child_i := (key >> (u64(s) * BIT_COUNT)) & i64(MASK)
 422 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 423 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 424 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 425 | 					copy(mid_block[int(child_i) * SLOT_LENGTH : (int(child_i) + 1) * SLOT_LENGTH], sb[:])
 426 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 427 | 					cur_index_pos = child_index_pos
 428 | 				}
 429 | 				empty_block: [INDEX_BLOCK_SIZE]u8
 430 | 				core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 431 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 432 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 433 | 				leaf_i := key & i64(MASK)
 434 | 				return Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH) * leaf_i, slot = Slot{}}, nil
 435 | 			}
 436 | 		case .Index:
 437 | 			next_ptr := ptr
 438 | 			if write_mode == .Read_Write {
 439 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
 440 | 				if next_ptr != ptr {
 441 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 442 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 443 | 				}
 444 | 			}
 445 | 			index_pos = next_ptr
 446 | 			shift -= 1
 447 | 			continue
 448 | 		case:
 449 | 			return {}, .Unexpected_Tag
 450 | 		}
 451 | 	}
 452 | }
```

### `xitdb/types.odin` (29 procedures · 261 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L865–L869`](../../xitdb/types.odin#L865-L869), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L915–L917`](../../xitdb/types.odin#L915-L917), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051), [`L1065–L1067`](../../xitdb/types.odin#L1065-L1067), [`L1069–L1074`](../../xitdb/types.odin#L1069-L1074), [`L1076–L1084`](../../xitdb/types.odin#L1076-L1084), [`L1092–L1097`](../../xitdb/types.odin#L1092-L1097), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1116–L1118`](../../xitdb/types.odin#L1116-L1118), [`L1130–L1139`](../../xitdb/types.odin#L1130-L1139), [`L1141–L1143`](../../xitdb/types.odin#L1141-L1143), [`L1149–L1183`](../../xitdb/types.odin#L1149-L1183), [`L1186–L1198`](../../xitdb/types.odin#L1186-L1198), [`L1200–L1226`](../../xitdb/types.odin#L1200-L1226), [`L1293–L1302`](../../xitdb/types.odin#L1293-L1302), [`L1329–L1331`](../../xitdb/types.odin#L1329-L1331), [`L1339–L1350`](../../xitdb/types.odin#L1339-L1350), [`L1408–L1413`](../../xitdb/types.odin#L1408-L1413), [`L1416–L1421`](../../xitdb/types.odin#L1416-L1421))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 3` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_with_full`](../../xitdb/types.odin#L865-L869) — `DEPTH 4` (`L865–L869`)

```odin
 865 | slot_with_full :: proc(s: Slot, full: bool) -> Slot {
 866 | 	res := s
 867 | 	res.full = full
 868 | 	return res
 869 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 4` (`L871–L877`)

```odin
 871 | slot_to_bytes :: #force_inline proc(s: Slot) -> [SLOT_LENGTH]u8 {
 872 | 	buf: [SLOT_LENGTH]u8 = ---
 873 | 	full_bit := u8(0x80) if s.full else u8(0)
 874 | 	buf[0] = full_bit | (u8(s.tag) & 0x7f)
 875 | 	endian.unchecked_put_u64be(buf[1:9], u64(s.value))
 876 | 	return buf
 877 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 4` (`L880–L890`)

```odin
 880 | slot_from_bytes_raw :: #force_inline proc(buf: [SLOT_LENGTH]u8) -> Slot {
 881 | 	b := buf
 882 | 	full := (b[0] & 0x80) != 0
 883 | 	raw_tag := b[0] & 0x7f
 884 | 	val := endian.unchecked_get_u64be(b[1:9])
 885 | 	return Slot{
 886 | 		value = i64(val),
 887 | 		tag   = Tag(raw_tag),
 888 | 		full  = full,
 889 | 	}
 890 | }
```

#### [`slot_from_slice_raw`](../../xitdb/types.odin#L892-L901) — `DEPTH 4` (`L892–L901`)

```odin
 892 | slot_from_slice_raw :: #force_inline proc(b: []u8) -> Slot #no_bounds_check {
 893 | 	full := (b[0] & 0x80) != 0
 894 | 	raw_tag := b[0] & 0x7f
 895 | 	val := endian.unchecked_get_u64be(b[1:9])
 896 | 	return Slot{
 897 | 		value = i64(val),
 898 | 		tag   = Tag(raw_tag),
 899 | 		full  = full,
 900 | 	}
 901 | }
```

#### [`slot_pointer_with_slot`](../../xitdb/types.odin#L915-L917) — `DEPTH 3` (`L915–L917`)

```odin
 915 | slot_pointer_with_slot :: proc(sp: Slot_Pointer, s: Slot) -> Slot_Pointer {
 916 | 	return Slot_Pointer{position = sp.position, slot = s}
 917 | }
```

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 5` (`L985–L991`)

```odin
 985 | root_header_to_bytes :: proc(rh: Root_Header) -> [ROOT_HEADER_LENGTH]u8 {
 986 | 	buf: [ROOT_HEADER_LENGTH]u8
 987 | 	slot_bytes := slot_to_bytes(rh.root)  // <== [calls slot_to_bytes]
 988 | 	copy(buf[0:9], slot_bytes[:])
 989 | 	endian.put_u64(buf[9:17], .Big, u64(rh.file_size))
 990 | 	return buf
 991 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 3` (`L993–L1003`)

```odin
 993 | root_header_from_bytes :: proc(buf: [ROOT_HEADER_LENGTH]u8) -> Root_Header {
 994 | 	b := buf
 995 | 	slot_buf: [SLOT_LENGTH]u8
 996 | 	copy(slot_buf[:], b[0:9])
 997 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
 998 | 	file_size, _ := endian.get_u64(b[9:17], .Big)
 999 | 	return Root_Header{
1000 | 		file_size = i64(file_size),
1001 | 		root      = root,
1002 | 	}
1003 | }
```

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 4` (`L1012–L1020`)

```odin
1012 | compute_root_trailer_checksum :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> u64 {
1013 | 	data: [33]u8
1014 | 	endian.put_u64(data[0:8], .Big, file_id)
1015 | 	endian.put_u64(data[8:16], .Big, u64(position))
1016 | 	slot_bytes := slot_to_bytes(root)  // <== [calls slot_to_bytes]
1017 | 	copy(data[16:25], slot_bytes[:])
1018 | 	endian.put_u64(data[25:33], .Big, commit_id)
1019 | 	return hash.crc64_xz(data[:])
1020 | }
```

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 4` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 4` (`L1030–L1037`)

```odin
1030 | root_trailer_to_bytes :: proc(rt: Root_Trailer) -> [ROOT_TRAILER_LENGTH]u8 {
1031 | 	buf: [ROOT_TRAILER_LENGTH]u8
1032 | 	slot_bytes := slot_to_bytes(rt.root)  // <== [calls slot_to_bytes]
1033 | 	copy(buf[0:9], slot_bytes[:])
1034 | 	endian.put_u64(buf[9:17], .Big, rt.commit_id)
1035 | 	endian.put_u64(buf[17:25], .Big, rt.checksum)
1036 | 	return buf
1037 | }
```

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 4` (`L1039–L1051`)

```odin
1039 | root_trailer_from_bytes :: proc(buf: [ROOT_TRAILER_LENGTH]u8) -> Root_Trailer {
1040 | 	b := buf
1041 | 	slot_buf: [SLOT_LENGTH]u8
1042 | 	copy(slot_buf[:], b[0:9])
1043 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
1044 | 	commit_id, _ := endian.get_u64(b[9:17], .Big)
1045 | 	checksum, _ := endian.get_u64(b[17:25], .Big)
1046 | 	return Root_Trailer{
1047 | 		checksum  = checksum,
1048 | 		commit_id = commit_id,
1049 | 		root      = root,
1050 | 	}
1051 | }
```

#### [`array_list_header_with_ptr`](../../xitdb/types.odin#L1065-L1067) — `DEPTH 4` (`L1065–L1067`)

```odin
1065 | array_list_header_with_ptr :: proc(h: Array_List_Header, ptr: i64) -> Array_List_Header {
1066 | 	return Array_List_Header{ptr = ptr, size = h.size}
1067 | }
```

#### [`array_list_header_to_bytes`](../../xitdb/types.odin#L1069-L1074) — `DEPTH 4` (`L1069–L1074`)

```odin
1069 | array_list_header_to_bytes :: #force_inline proc(h: Array_List_Header) -> [ARRAY_LIST_HEADER_LENGTH]u8 {
1070 | 	buf: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
1071 | 	endian.unchecked_put_u64be(buf[0:8], u64(h.size))
1072 | 	endian.unchecked_put_u64be(buf[8:16], u64(h.ptr))
1073 | 	return buf
1074 | }
```

#### [`array_list_header_from_bytes`](../../xitdb/types.odin#L1076-L1084) — `DEPTH 4` (`L1076–L1084`)

```odin
1076 | array_list_header_from_bytes :: #force_inline proc(buf: [ARRAY_LIST_HEADER_LENGTH]u8) -> (res: Array_List_Header, err: Error) {
1077 | 	b := buf
1078 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1079 | 	ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1080 | 	if size < 0 || ptr < 0 {
1081 | 		return {}, .Expected_Unsigned_Long
1082 | 	}
1083 | 	return Array_List_Header{ptr = ptr, size = size}, nil
1084 | }
```

#### [`btree_header_to_bytes`](../../xitdb/types.odin#L1092-L1097) — `DEPTH 4` (`L1092–L1097`)

```odin
1092 | btree_header_to_bytes :: #force_inline proc(h: BTree_Header) -> [BTREE_HEADER_LENGTH]u8 {
1093 | 	buf: [BTREE_HEADER_LENGTH]u8 = ---
1094 | 	endian.unchecked_put_u64be(buf[0:8], u64(h.size))
1095 | 	endian.unchecked_put_u64be(buf[8:16], u64(h.root_ptr))
1096 | 	return buf
1097 | }
```

#### [`btree_header_from_bytes`](../../xitdb/types.odin#L1099-L1107) — `DEPTH 4` (`L1099–L1107`)

```odin
1099 | btree_header_from_bytes :: #force_inline proc(buf: [BTREE_HEADER_LENGTH]u8) -> (res: BTree_Header, err: Error) {
1100 | 	b := buf
1101 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1102 | 	root_ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1103 | 	if size < 0 || root_ptr < 0 {
1104 | 		return {}, .Expected_Unsigned_Long
1105 | 	}
1106 | 	return BTree_Header{root_ptr = root_ptr, size = size}, nil
1107 | }
```

#### [`kv_pair_length`](../../xitdb/types.odin#L1116-L1118) — `DEPTH 6` (`L1116–L1118`)

```odin
1116 | kv_pair_length :: proc(hash_size: int) -> int {
1117 | 	return hash_size + SLOT_LENGTH * 2
1118 | }
```

#### [`kv_pair_from_bytes`](../../xitdb/types.odin#L1130-L1139) — `DEPTH 5` (`L1130–L1139`)

```odin
1130 | kv_pair_from_bytes :: proc(b: []u8, hash_size: int, allocator := context.allocator) -> Key_Value_Pair {
1131 | 	h: []u8
1132 | 	if hash_size > 0 {
1133 | 		h = make([]u8, hash_size, allocator)
1134 | 		copy(h, b[:hash_size])
1135 | 	}
1136 | 	key_slot := slot_from_slice_raw(b[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1137 | 	val_slot := slot_from_slice_raw(b[hash_size + SLOT_LENGTH : hash_size + SLOT_LENGTH * 2])  // <== [calls slot_from_slice_raw]
1138 | 	return Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = h}
1139 | }
```

#### [`kv_pair_write`](../../xitdb/types.odin#L1141-L1143) — `DEPTH 5` (`L1141–L1143`)

```odin
1141 | kv_pair_write :: proc(kv: Key_Value_Pair, c: ^Core) -> Error {
1142 | 	return encode_kv_pair(c, .KV_Pair, kv)  // <== [calls encode_kv_pair]
1143 | }
```

#### [`decode_kv_pair`](../../xitdb/types.odin#L1149-L1183) — `DEPTH 4` (`L1149–L1183`)

```odin
1149 | decode_kv_pair :: proc(c: ^Core, tag: Tag, hash_size: int, allocator := context.allocator) -> (kv: Key_Value_Pair, err: Error) {
1150 | 	#partial switch tag {
1151 | 	case .KV_Pair:
1152 | 		kv_len := kv_pair_length(hash_size)  // <== [calls kv_pair_length]
1153 | 		if kv_len <= 128 {
1154 | 			stack_buf: [128]u8 = ---
1155 | 			b := stack_buf[:kv_len]
1156 | 			core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1157 | 			kv = kv_pair_from_bytes(b, hash_size, allocator)  // <== [calls kv_pair_from_bytes]
1158 | 		} else {
1159 | 			b := make([]u8, kv_len, context.temp_allocator)
1160 | 			core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1161 | 			kv = kv_pair_from_bytes(b, hash_size, allocator)  // <== [calls kv_pair_from_bytes]
1162 | 		}
1163 | 	case .Sorted_KV_Pair:
1164 | 		b: [SORTED_KEY_VALUE_LEN]u8 = ---
1165 | 		core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
1166 | 		kv = kv_pair_from_bytes(b[:], 0, allocator)  // <== [calls kv_pair_from_bytes]
1167 | 	case:
1168 | 		return {}, .Unexpected_Tag
1169 | 	}
1170 | 	if err := tag_validate(kv.key_slot.tag); err != nil {  // <== [calls tag_validate]
1171 | 		if kv.hash != nil {
1172 | 			delete(kv.hash, allocator)
1173 | 		}
1174 | 		return {}, err
1175 | 	}
1176 | 	if err := tag_validate(kv.value_slot.tag); err != nil {  // <== [calls tag_validate]
1177 | 		if kv.hash != nil {
1178 | 			delete(kv.hash, allocator)
1179 | 		}
1180 | 		return {}, err
1181 | 	}
1182 | 	return kv, nil
1183 | }
```

#### [`kv_pair_read_buf`](../../xitdb/types.odin#L1186-L1198) — `DEPTH 5` (`L1186–L1198`)

```odin
1186 | kv_pair_read_buf :: proc(c: ^Core, hash_buf: []u8) -> (kv: Key_Value_Pair, err: Error) {
1187 | 	hash_size := len(hash_buf)
1188 | 	kv_len := kv_pair_length(hash_size)  // <== [calls kv_pair_length]
1189 | 	stack_buf: [128]u8 = ---
1190 | 	b := stack_buf[:kv_len] if kv_len <= len(stack_buf) else make([]u8, kv_len, context.temp_allocator)
1191 | 	core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1192 | 	copy(hash_buf, b[:hash_size])
1193 | 	key_slot := slot_from_slice_raw(b[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1194 | 	tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
1195 | 	val_slot := slot_from_slice_raw(b[hash_size + SLOT_LENGTH : hash_size + SLOT_LENGTH * 2])  // <== [calls slot_from_slice_raw]
1196 | 	tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
1197 | 	return Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}, nil
1198 | }
```

#### [`encode_kv_pair`](../../xitdb/types.odin#L1200-L1226) — `DEPTH 6` (`L1200–L1226`)

```odin
1200 | encode_kv_pair :: proc(c: ^Core, tag: Tag, kv: Key_Value_Pair) -> Error {
1201 | 	#partial switch tag {
1202 | 	case .KV_Pair:
1203 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1204 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1205 | 		total := len(kv.hash) + SLOT_LENGTH * 2
1206 | 		if total <= 128 {
1207 | 			buf: [128]u8 = ---
1208 | 			copy(buf[:len(kv.hash)], kv.hash)
1209 | 			copy(buf[len(kv.hash):len(kv.hash) + SLOT_LENGTH], kb[:])
1210 | 			copy(buf[len(kv.hash) + SLOT_LENGTH:total], vb[:])
1211 | 			return core_write_all(c, buf[:total])  // <== [calls core_write_all]
1212 | 		}
1213 | 		core_write_all(c, kv.hash) or_return  // <== [calls core_write_all]
1214 | 		core_write_all(c, kb[:]) or_return  // <== [calls core_write_all]
1215 | 		return core_write_all(c, vb[:])  // <== [calls core_write_all]
1216 | 	case .Sorted_KV_Pair:
1217 | 		buf: [SORTED_KEY_VALUE_LEN]u8 = ---
1218 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1219 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1220 | 		copy(buf[:SLOT_LENGTH], kb[:])
1221 | 		copy(buf[SLOT_LENGTH:], vb[:])
1222 | 		return core_write_all(c, buf[:])  // <== [calls core_write_all]
1223 | 	case:
1224 | 		return .Unexpected_Tag
1225 | 	}
1226 | }
```

#### [`sorted_node_subtree_count`](../../xitdb/types.odin#L1293-L1302) — `DEPTH 5` (`L1293–L1302`)

```odin
1293 | sorted_node_subtree_count :: proc(n: Sorted_Node) -> i64 {
1294 | 	if n.kind == .Leaf {
1295 | 		return i64(n.num)
1296 | 	}
1297 | 	total: i64 = 0
1298 | 	for i in 0 ..< n.num {
1299 | 		total += n.counts[i]
1300 | 	}
1301 | 	return total
1302 | }
```

#### [`is_key_only_entry`](../../xitdb/types.odin#L1329-L1331) — `DEPTH 5` (`L1329–L1331`)

```odin
1329 | is_key_only_entry :: #force_inline proc(entry: Slot) -> bool {
1330 | 	return entry.tag == .Bytes || entry.tag == .Short_Bytes
1331 | }
```

#### [`bytes_is_short`](../../xitdb/types.odin#L1339-L1350) — `DEPTH 4` (`L1339–L1350`)

```odin
1339 | bytes_is_short :: proc(b: Bytes) -> bool {
1340 | 	total_size := 6 if b.format_tag != nil else 8
1341 | 	if len(b.value) > total_size {
1342 | 		return false
1343 | 	}
1344 | 	for ch in b.value {
1345 | 		if ch == 0 {
1346 | 			return false
1347 | 		}
1348 | 	}
1349 | 	return true
1350 | }
```

#### [`hamt_nibble`](../../xitdb/types.odin#L1408-L1413) — `DEPTH 5` (`L1408–L1413`)

```odin
1408 | hamt_nibble :: #force_inline proc(key_hash: []u8, key_offset: u8) -> int {
1409 | 	hash_size := len(key_hash)
1410 | 	byte_idx := hash_size - 1 - int(key_offset >> 1)
1411 | 	shift := (key_offset & 1) << 2
1412 | 	return int((key_hash[byte_idx] >> shift) & 0x0F)
1413 | }
```

#### [`radix_shift`](../../xitdb/types.odin#L1416-L1421) — `DEPTH 4` (`L1416–L1421`)

```odin
1416 | radix_shift :: #force_inline proc(key: i64) -> u8 {
1417 | 	if key < SLOT_COUNT {
1418 | 		return 0
1419 | 	}
1420 | 	return u8((63 - intrinsics.count_leading_zeros(u64(key))) >> 2)
1421 | }
```

