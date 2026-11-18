#+vet unused shadowing using-stmt style semicolon tabs
package xitdb_tests

import "core:c"
import "core:encoding/endian"
import "core:fmt"
import "core:strings"
import "core:testing"
import lua "../xitdb/luajit"
import xitdb "../xitdb"

// ============================================================================
// Deterministic Regressions Promoted from libFuzzer + ASan + Differential Fuzzing
// ============================================================================

@(test)
unit_fuzz_regression_dsl_selector_roundtrip_escaping :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// 1. Exact libFuzzer crash-dcb0e8fb selector: leading '@0', raw high bytes (>= 0x80), and trailing '"'
	fuzz_sel := "@0.\x8c\x8c\x8c\x8c[\"101\"]#metrics[\"views\"]$catalog[\"apple\"].fruits[-1].toodin\""
	steps1, err1 := xitdb.parse_steps(fuzz_sel, context.temp_allocator)
	testing.expect_value(t, err1, nil)
	formatted := xitdb.format_steps(steps1, context.temp_allocator)
	steps2, err2 := xitdb.parse_steps(formatted, context.temp_allocator)
	testing.expect_value(t, err2, nil)
	testing.expect_value(t, len(steps2), len(steps1))
	for i in 0 ..< min(len(steps1), len(steps2)) {
		testing.expect_value(t, steps2[i].kind, steps1[i].kind)
		testing.expect_value(t, steps2[i].key, steps1[i].key)
		testing.expect_value(t, steps2[i].index, steps1[i].index)
	}

	// 2. Round-trip keys with quotes, backslashes, control whitespace, Unicode NBSP, empty keys, and sigils
	edge_keys := []string{
		`toodin"`,
		`a\"b\\c`,
		"it's\na\r\tkey",
		"",
		" lead",
		"trail ",
		"foo\u00a0",
		"@0",
		"{a,b}",
		".[]$#%^",
	}
	for k in edge_keys {
		orig := []xitdb.Path_Step{
			xitdb.hm(k),
			xitdb.chm(k),
			xitdb.sm(k),
			xitdb.hs(k),
			xitdb.chs(k),
			xitdb.ss(k),
		}
		fmt_str := xitdb.format_steps(orig, context.temp_allocator)
		reparsed, rp_err := xitdb.parse_steps(fmt_str, context.temp_allocator)
		testing.expect_value(t, rp_err, nil)
		testing.expect_value(t, len(reparsed), len(orig))
		for i in 0 ..< min(len(orig), len(reparsed)) {
			testing.expect_value(t, reparsed[i].kind, orig[i].kind)
			testing.expect_value(t, reparsed[i].key, orig[i].key)
		}
	}

	// 3. Datalog step parsing preserves unescaped bracketed keys
	dq, derr := xitdb.parse_datalog(`find ?v where .users["a\"b\\c"] = ?v`, context.temp_allocator)
	testing.expect_value(t, derr, nil)
	testing.expect_value(t, len(dq.clauses), 1)
	if len(dq.clauses) == 1 && len(dq.clauses[0].steps) >= 2 {
		testing.expect_value(t, dq.clauses[0].steps[1].lit_key, `a"b\c`)
	}
}

@(test)
unit_fuzz_regression_datalog_leading_where_and_deep_reach_no_panic :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// 1. Exact libFuzzer crash-a48aa104 category: inputs starting with "where" must not slice [5:0]
	bad_queries := []string{
		"where",
		"whereh\"n]#metrics[\"vietricEC @-1 {\n  @0.users[dewme] = ?id\n",
		"where .users[?id] = ?v",
		"find where ?x = 1",
	}
	for qstr in bad_queries {
		_, perr := xitdb.parse_datalog(qstr, context.temp_allocator)
		testing.expect_value(t, perr, xitdb.Xitdb_Error.Invalid_Range)
	}
	_, empty_where_err := xitdb.parse_datalog("find ?x where", context.temp_allocator)
	testing.expect_value(t, empty_where_err, nil)

	// 2. Deeply nested reach(...) exceeds recursion guard safely without stack overflow
	b := strings.builder_make(context.temp_allocator)
	for _ in 0 ..< 24 {
		strings.write_string(&b, "reach(?a, ?b, ")
	}
	strings.write_string(&b, ".edge[?a] = ?b")
	for _ in 0 ..< 24 {
		strings.write_byte(&b, ')')
	}
	deep_q := fmt.tprintf("find ?a, ?b where %s", strings.to_string(b))
	_, derr := xitdb.parse_datalog(deep_q, context.temp_allocator)
	testing.expect_value(t, derr, xitdb.Xitdb_Error.Invalid_Range)

	// 3. query_datalog propagates parse_datalog error cleanly against an initialized DB
	core := xitdb.core_memory_init(reserve_size = 0)
	defer xitdb.core_destroy(&core)
	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)
	_, qerr := xitdb.query_datalog(&db, "where .users[?k] = ?v", -1, context.temp_allocator)
	testing.expect_value(t, qerr, xitdb.Xitdb_Error.Invalid_Range)
}

@(test)
unit_fuzz_regression_dsl_pull_huge_range_no_oom :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core := xitdb.core_memory_init(reserve_size = 0)
	defer xitdb.core_destroy(&core)
	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx := xitdb.tx_init(&db, nil, false, context.temp_allocator)
	testing.expect_value(t, xitdb.tx_append(&tx, ".fruits", "apple"), nil)
	testing.expect_value(t, xitdb.tx_append(&tx, ".fruits", "pear"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, ".ll[[0]]", "node0"), nil)
	_, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)

	mc, merr := xitdb.select_cursor(&db, "@-1")
	testing.expect_value(t, merr, nil)
	cur, has_cur := mc.?
	testing.expect(t, has_cur)

	// Huge upper bound caps pre-allocation and terminates at list length without OOM
	pv, perr := xitdb.pull(cur, "{.fruits[0..99999999999]}", context.temp_allocator)
	testing.expect_value(t, perr, nil)
	if list_v, ok := xitdb.pull_get(pv, "fruits"); ok {
		pl, is_list := list_v.(xitdb.Pull_List)
		testing.expect(t, is_list)
		testing.expect_value(t, len(pl), 2)
	} else {
		testing.expect(t, false)
	}

	pv_ll, pll_err := xitdb.pull(cur, "{.ll[0..99999999999]}", context.temp_allocator)
	testing.expect_value(t, pll_err, nil)
	if list_v, ok := xitdb.pull_get(pv_ll, "ll"); ok {
		pl, is_list := list_v.(xitdb.Pull_List)
		testing.expect(t, is_list)
		testing.expect_value(t, len(pl), 1)
	} else {
		testing.expect(t, false)
	}

	// Reversed range produces empty Pull_List cleanly
	pv_empty, pe_err := xitdb.pull(cur, "{.fruits[5..2]}", context.temp_allocator)
	testing.expect_value(t, pe_err, nil)
	if list_v, ok := xitdb.pull_get(pv_empty, "fruits"); ok {
		pl, is_list := list_v.(xitdb.Pull_List)
		testing.expect(t, is_list)
		testing.expect_value(t, len(pl), 0)
	} else {
		testing.expect(t, false)
	}

	// Negative start index is rejected cleanly
	_, neg_err := xitdb.pull(cur, "{.fruits[-5..2]}", context.temp_allocator)
	testing.expect_value(t, neg_err, xitdb.Xitdb_Error.Invalid_Range)
}

@(test)
unit_fuzz_regression_tx_invalid_selector_and_escaped_keys_zero_leaks :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core := xitdb.core_memory_init(reserve_size = 0)
	defer xitdb.core_destroy(&core)
	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	// 1. Direct Tx API with persistent context.allocator must not leak on failed parse_steps / tx_fork or escaped keys
	{
		tx := xitdb.tx_init(&db, nil, false, context.allocator)
		defer xitdb.tx_destroy(&tx)

		testing.expect_value(t, xitdb.tx_put(&tx, ".users.a[unclosed.b", u64(30)), xitdb.Xitdb_Error.Invalid_Range)
		testing.expect_value(t, xitdb.tx_fork(&tx, ".users", ".bad[unclosed"), xitdb.Xitdb_Error.Invalid_Range)
		testing.expect_value(t, xitdb.tx_put(&tx, `.users["es\"c\\aped"].age`, u64(30)), nil)

		rep, cerr := xitdb.tx_commit(&tx)
		defer xitdb.tx_report_destroy(&rep, context.allocator)
		testing.expect_value(t, cerr, nil)
	}

	val, gerr := xitdb.get_uint(&db, `@0.users["es\"c\\aped"].age`)
	testing.expect_value(t, gerr, nil)
	testing.expect_value(t, val, u64(30))

	// 2. Exact fuzz_lua leak-e2a607da snippet: failing tx:put inside Lua must release Tx memory on pcall error
	L := xitdb.lua_new_state(&db)
	testing.expect(t, L != nil)
	defer lua.close(L)

	lua_src := "local tx = db:tx_init(nil, false)\n" +
		"tx:put(\".usesss[sssssrs.alic#e&age\", xitdb.uint(30)):commit()\n"
	load_status := lua.L_loadbufferx(L, raw_data(lua_src), c.size_t(len(lua_src)), "regression", "t")
	testing.expect_value(t, load_status, lua.Status.OK)
	call_status := lua.pcall(L, 0, 0, 0)
	testing.expect(t, lua.Status(call_status) != .OK)
}

@(test)
unit_fuzz_regression_wire_corrupt_bytes_length_and_cyclic_nodes_no_oom :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// Build a valid DB with >8-byte .Bytes value, Sorted_Map (>8-byte key), Hash_Map, and multi-leaf Linked_Array_List
	src_core := xitdb.core_memory_init(reserve_size = 0)
	defer xitdb.core_destroy(&src_core)
	src_db, derr := xitdb.database_init(&src_core, xitdb.sha1_hasher())
	testing.expect_value(t, derr, nil)

	tx := xitdb.tx_init(&src_db, nil, false, context.temp_allocator)
	testing.expect_value(t, xitdb.tx_put(&tx, ".doc", "long_document_payload_123456"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, "$sm[\"long_sorted_key_0001\"]", "val1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, "$sm[\"long_sorted_key_0002\"]", "val2"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, ".hm.alpha", "v1"), nil)
	for i in 0 ..< 20 {
		testing.expect_value(t, xitdb.tx_put(&tx, fmt.tprintf(".ll[[%d]]", i), fmt.tprintf("item-%d", i)), nil)
	}
	_, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)

	doc_cur, dc_err := xitdb.select_cursor(&src_db, "@0.doc")
	testing.expect_value(t, dc_err, nil)
	doc_slot := doc_cur.?.slot_ptr.slot
	testing.expect_value(t, doc_slot.tag, xitdb.Tag.Bytes)

	sm_cur, smc_err := xitdb.select_cursor(&src_db, "@0$sm")
	testing.expect_value(t, smc_err, nil)
	sm_col, sm_init_err := xitdb.read_sorted_map_init(sm_cur.?)
	testing.expect_value(t, sm_init_err, nil)
	first_kv_maybe, fkv_err := xitdb.sorted_map_get_index_kv_pair(sm_col, 0, context.temp_allocator)
	testing.expect_value(t, fkv_err, nil)
	sm_key_slot := first_kv_maybe.?.key_cursor.slot_ptr.slot
	testing.expect_value(t, sm_key_slot.tag, xitdb.Tag.Bytes)

	hm_cur, hmc_err := xitdb.select_cursor(&src_db, "@0.hm")
	testing.expect_value(t, hmc_err, nil)
	ll_cur, llc_err := xitdb.select_cursor(&src_db, "@0.ll")
	testing.expect_value(t, llc_err, nil)
	ll_hb: [xitdb.BTREE_HEADER_LENGTH]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&src_core, ll_cur.?.slot_ptr.slot.value, ll_hb[:]), nil)
	ll_header, ll_herr := xitdb.btree_header_from_bytes(ll_hb)
	testing.expect_value(t, ll_herr, nil)

	seed_bytes := xitdb.core_memory_bytes(&src_core)

	// 1. Mutate .Bytes 8-byte length prefix to 31,162,395,050 (fuzz_wire OOM) and -1 without OOM
	for bad_len in ([?]u64{31_162_395_050, max(u64)}) {
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		endian.put_u64(mut[doc_slot.value : doc_slot.value + 8], .Big, bad_len)
		endian.put_u64(mut[sm_key_slot.value : sm_key_slot.value + 8], .Big, bad_len)

		c := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&c)
		db, db_err := xitdb.database_init(&c, xitdb.sha1_hasher())
		testing.expect_value(t, db_err, nil)

		dc, derr1 := xitdb.select_cursor(&db, "@0.doc")
		testing.expect_value(t, derr1, nil)
		_, read_err := xitdb.cursor_read_bytes_object(dc.?, 0, context.temp_allocator)
		testing.expect(t, read_err != nil)

		if rdr, rdr_err := xitdb.cursor_reader(dc.?); rdr_err == nil {
			_, all_err := xitdb.cursor_reader_read_all(&rdr, context.temp_allocator)
			testing.expect(t, all_err != nil)
		}

		smc, sm_err1 := xitdb.select_cursor(&db, "@0$sm")
		testing.expect_value(t, sm_err1, nil)
		sm_read, sm_rerr := xitdb.read_sorted_map_init(smc.?)
		testing.expect_value(t, sm_rerr, nil)
		_, cmp_err := xitdb.sorted_map_get_cursor(sm_read, "long_sorted_key_0001")
		testing.expect_value(t, cmp_err, xitdb.Xitdb_Error.Unexpected_EOF)

		mc, mc_err := xitdb.select_cursor(&db, "@-1")
		testing.expect_value(t, mc_err, nil)
		_, pull_err := xitdb.pull(mc.?, "*", context.temp_allocator)
		testing.expect(t, pull_err != nil)

		dst_core := xitdb.core_memory_init(reserve_size = 0)
		defer xitdb.core_destroy(&dst_core)
		_, comp_err := xitdb.database_compact(&db, &dst_core)
		testing.expect(t, comp_err != nil)
	}

	// 2. Self-cyclic HAMT .Index block stops cleanly instead of stack-overflowing
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		hm_pos := hm_cur.?.slot_ptr.slot.value
		self_idx := xitdb.slot_to_bytes(xitdb.Slot{value = hm_pos, tag = .Index})
		copy(mut[hm_pos : hm_pos + xitdb.SLOT_LENGTH], self_idx[:])

		c := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&c)
		db, db_err := xitdb.database_init(&c, xitdb.sha1_hasher())
		testing.expect_value(t, db_err, nil)

		hrc, herr := xitdb.select_cursor(&db, "@0.hm")
		testing.expect_value(t, herr, nil)
		it, it_err := xitdb.cursor_iterator(hrc.?)
		testing.expect_value(t, it_err, nil)
		loop_err: xitdb.Error
		for _ in 0 ..< 64 {
			_, nerr := xitdb.cursor_iterator_next(&it)
			if nerr != nil {
				loop_err = nerr
				break
			}
		}
		testing.expect_value(t, loop_err, xitdb.Xitdb_Error.Max_Shift_Exceeded)

		empty_cur := xitdb.Read_Cursor{db = &db}
		_, diff_err := xitdb.diff_collection(empty_cur, hrc.?, context.temp_allocator)
		testing.expect_value(t, diff_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)
	}

	// 3. Self-cyclic B-Tree .Branch node stops cleanly with .Max_Shift_Exceeded
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		root_ptr := ll_header.root_ptr
		self_child := xitdb.slot_to_bytes(xitdb.Slot{value = root_ptr, tag = .Index})
		first_child_pos := root_ptr + xitdb.BTREE_NODE_HEADER_SIZE
		copy(mut[first_child_pos : first_child_pos + xitdb.SLOT_LENGTH], self_child[:])

		c := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&c)
		db, db_err := xitdb.database_init(&c, xitdb.sha1_hasher())
		testing.expect_value(t, db_err, nil)

		lrc, lerr := xitdb.select_cursor(&db, "@0.ll")
		testing.expect_value(t, lerr, nil)
		ll_read, ll_init_err := xitdb.read_linked_array_list_init(lrc.?)
		testing.expect_value(t, ll_init_err, nil)

		_, get_err := xitdb.linked_array_list_get_cursor(ll_read, 0)
		testing.expect_value(t, get_err, xitdb.Xitdb_Error.Max_Shift_Exceeded)

		it, it_err := xitdb.linked_array_list_iterator(ll_read)
		testing.expect_value(t, it_err, nil)
		loop_err: xitdb.Error
		for _ in 0 ..< 64 {
			_, nerr := xitdb.cursor_iterator_next(&it)
			if nerr != nil {
				loop_err = nerr
				break
			}
		}
		testing.expect_value(t, loop_err, xitdb.Xitdb_Error.Max_Shift_Exceeded)
	}
}

@(test)
unit_fuzz_regression_negative_slot_values_and_core_bounds :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// 1. Core_Memory & Core_Overlay reject negative & signed-overflow positions cleanly
	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, init_err := xitdb.database_init(&cm, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx := xitdb.tx_init(&db, nil, true, context.allocator)
	defer xitdb.tx_destroy(&tx)
	testing.expect_value(t, xitdb.tx_put(&tx, ".doc", "negative_slot_bounds_test_payload"), nil)
	rep, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, len(rep.changes), 1)
	doc_offset := rep.changes[0].new_slot.value
	xitdb.tx_report_destroy(&rep, context.allocator)

	committed_sz, csz_err := xitdb.database_committed_size(&db)
	testing.expect_value(t, csz_err, nil)
	ov_core, ov_err := xitdb.core_overlay_init(&cm, committed_sz, context.allocator)
	testing.expect_value(t, ov_err, nil)
	defer xitdb.core_destroy(&ov_core)

	cores := [?]^xitdb.Core{&cm, &ov_core}
	neg_positions := [?]i64{-1, -8, -1024, min(i64)}
	eof_positions := [?]i64{max(i64) - 4, max(i64)}
	for core_ptr in cores {
		for bad_pos in neg_positions {
			small: [16]u8
			testing.expect_value(t, xitdb.core_read_exact_at(core_ptr, bad_pos, small[:]), xitdb.Xitdb_Error.Expected_Unsigned_Long)
			_, byte_err := xitdb.core_read_byte_at(core_ptr, bad_pos)
			testing.expect_value(t, byte_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
			_, i64_err := xitdb.core_read_i64_at(core_ptr, bad_pos)
			testing.expect_value(t, i64_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
			_, slot_err := xitdb.core_read_slot_raw_at(core_ptr, bad_pos)
			testing.expect_value(t, slot_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
			_, blk_err := xitdb.core_read_block_at(core_ptr, bad_pos, small[:])
			testing.expect_value(t, blk_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
			var_buf: [16]u8
			_, short_err := xitdb.core_read_short_at(core_ptr, bad_pos, var_buf[:])
			testing.expect_value(t, short_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
		}
		for bad_pos in eof_positions {
			small: [16]u8
			testing.expect_value(t, xitdb.core_read_exact_at(core_ptr, bad_pos, small[:]), xitdb.Xitdb_Error.Unexpected_EOF)
			_, byte_err := xitdb.core_read_byte_at(core_ptr, bad_pos)
			testing.expect_value(t, byte_err, xitdb.Xitdb_Error.Unexpected_EOF)
			_, i64_err := xitdb.core_read_i64_at(core_ptr, bad_pos)
			testing.expect_value(t, i64_err, xitdb.Xitdb_Error.Unexpected_EOF)
			_, slot_err := xitdb.core_read_slot_raw_at(core_ptr, bad_pos)
			testing.expect_value(t, slot_err, xitdb.Xitdb_Error.Unexpected_EOF)
			blk, blk_err := xitdb.core_read_block_at(core_ptr, bad_pos, small[:])
			testing.expect_value(t, blk_err, nil)
			testing.expect_value(t, len(blk), 0)
			var_buf: [16]u8
			short_blk, short_err := xitdb.core_read_short_at(core_ptr, bad_pos, var_buf[:])
			testing.expect_value(t, short_err, nil)
			testing.expect_value(t, len(short_blk), 0)
		}
	}

	// 2. Negative & overflowing Slot.value in cursor_read_bytes_object / buf / cursor_reader & compactor
	for neg_val in ([?]i64{-1, -8, min(i64)}) {
		bad_cur := xitdb.Read_Cursor{
			slot_ptr = xitdb.Slot_Pointer{slot = xitdb.Slot{value = neg_val, tag = .Bytes}},
			db       = &db,
		}
		_, obj_err := xitdb.cursor_read_bytes_object(bad_cur, 0, context.allocator)
		testing.expect_value(t, obj_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
		out_buf: [8]u8
		_, buf_err := xitdb.cursor_read_bytes_buf(bad_cur, out_buf[:])
		testing.expect_value(t, buf_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
		_, rdr_err := xitdb.cursor_reader(bad_cur)
		testing.expect_value(t, rdr_err, xitdb.Xitdb_Error.Expected_Unsigned_Long)
	}

	// Mutate a valid wire DB's .doc Bytes Slot.value to -8 in raw bytes and compact
	raw_bytes := xitdb.core_memory_bytes(&cm)
	mut := make([]u8, len(raw_bytes), context.temp_allocator)
	copy(mut, raw_bytes)

	dc_maybe, dc_err := xitdb.select_cursor(&db, "@0.doc")
	testing.expect_value(t, dc_err, nil)
	slot_pos, has_pos := dc_maybe.?.slot_ptr.position.?
	testing.expect(t, has_pos)
	testing.expect(t, doc_offset > 0)
	neg_slot := xitdb.slot_to_bytes(xitdb.Slot{value = -8, tag = .Bytes})
	copy(mut[slot_pos : slot_pos + xitdb.SLOT_LENGTH], neg_slot[:])

	mut_core := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&mut_core)
	mut_db, mdb_err := xitdb.database_init(&mut_core, xitdb.sha1_hasher())
	testing.expect_value(t, mdb_err, nil)

	dst_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&dst_core)
	_, comp_err := xitdb.database_compact(&mut_db, &dst_core)
	testing.expect(t, comp_err != nil)

	// 3. cursor_reader rejects inflated byte lengths (preventing seek+read overflow)
	mut_len := make([]u8, len(raw_bytes), context.temp_allocator)
	copy(mut_len, raw_bytes)
	endian.put_u64(mut_len[doc_offset : doc_offset + 8], .Big, u64(max(i64) - 5))
	len_core := xitdb.core_memory_init_from_bytes(mut_len, context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&len_core)
	len_db, ldb_err := xitdb.database_init(&len_core, xitdb.sha1_hasher())
	testing.expect_value(t, ldb_err, nil)
	len_cur, _ := xitdb.select_cursor(&len_db, "@0.doc")
	_, inflated_rdr_err := xitdb.cursor_reader(len_cur.?)
	testing.expect_value(t, inflated_rdr_err, xitdb.Xitdb_Error.Unexpected_EOF)

	// Direct overflow check on Cursor_Reader.read / read_fully
	ov_rdr := xitdb.Cursor_Reader{
		parent            = dc_maybe.?,
		size              = max(i64),
		start_position    = doc_offset + 8,
		relative_position = max(i64) - 2,
	}
	tmp_read: [4]u8
	_, ov_r_err := xitdb.cursor_reader_read(&ov_rdr, tmp_read[:])
	testing.expect_value(t, ov_r_err, xitdb.Xitdb_Error.Unexpected_EOF)
	ov_rf_err := xitdb.cursor_reader_read_fully(&ov_rdr, tmp_read[:1])
	testing.expect_value(t, ov_rf_err, xitdb.Xitdb_Error.Unexpected_EOF)
}

@(test)
unit_fuzz_regression_lua_commit_error_uaf_and_reuse_guards :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&core)
	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	L := xitdb.lua_new_state(&db)
	testing.expect(t, L != nil)
	defer lua.close(L)

	ok, err_msg := xitdb.lua_exec_string(L, `
		-- 1. Failed tx:commit() via with_cursor must preserve error string cleanly after Tx cleanup
		-- and reject subsequent mutations or double-commit calls on the same Tx userdata.
		local tx = db:tx_init(nil, false)
		tx:put(".seeded", "ok")
		tx:with_cursor(function(cur)
			error("sentinel_callback_boom")
		end)
		local ok_commit, err_commit = pcall(function() return tx:commit() end)
		assert(ok_commit == false, "expected tx:commit to fail")
		assert(type(err_commit) == "string" and string.find(err_commit, "sentinel_callback_boom", 1, true) ~= nil,
			"expected callback error message intact, got: " .. tostring(err_commit))

		local ok_put_after, _ = pcall(function() tx:put(".after", "bad") end)
		assert(ok_put_after == false, "expected tx:put after failed commit to error")
		local ok_recommit, _ = pcall(function() tx:commit() end)
		assert(ok_recommit == false, "expected second tx:commit after failure to error")

		-- 2. Uncommitted Tx with pending with_cursor collected via GC must not leak callback holders
		do
			local orphan = db:tx_init(nil, false)
			orphan:with_cursor(function(cur) end)
		end
		collectgarbage("collect")
		collectgarbage("collect")
	`, "lua_commit_error_uaf")
	if !ok {
		testing.expectf(t, false, "lua commit error regression failed: %s", err_msg)
	}
}

@(test)
unit_fuzz_regression_diff_corrupt_array_count_and_btree_write_guards :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// Build seed DB with Array_List, Linked_Array_List, and multi-tier Sorted_Map (height >= 2 Branch)
	src_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&src_core)
	src_db, derr := xitdb.database_init(&src_core, xitdb.sha1_hasher())
	testing.expect_value(t, derr, nil)

	tx0 := xitdb.tx_init(&src_db, nil, false, context.allocator)
	testing.expect_value(t, xitdb.tx_append(&tx0, ".arr", "a0"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".ll[[0]]", "l0"), nil)
	for i in 0 ..< 24 {
		testing.expect_value(t, xitdb.tx_put(&tx0, fmt.tprintf("$sm[\"k_%02d\"]", i), fmt.tprintf("v_%02d", i)), nil)
	}
	rep0, cerr0 := xitdb.tx_commit(&tx0)
	xitdb.tx_destroy(&tx0)
	testing.expect_value(t, cerr0, nil)
	xitdb.tx_report_destroy(&rep0, context.allocator)

	tx1 := xitdb.tx_init(&src_db, -1, false, context.allocator)
	testing.expect_value(t, xitdb.tx_append(&tx1, ".arr", "a1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, ".ll[[1]]", "l1"), nil)
	rep1, cerr1 := xitdb.tx_commit(&tx1)
	xitdb.tx_destroy(&tx1)
	testing.expect_value(t, cerr1, nil)
	xitdb.tx_report_destroy(&rep1, context.allocator)

	arr_c, _ := xitdb.select_cursor(&src_db, "@1.arr")
	ll_c, _ := xitdb.select_cursor(&src_db, "@1.ll")
	sm_c, _ := xitdb.select_cursor(&src_db, "@1$sm")

	ll_hb: [xitdb.BTREE_HEADER_LENGTH]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&src_core, ll_c.?.slot_ptr.slot.value, ll_hb[:]), nil)
	ll_hdr, _ := xitdb.btree_header_from_bytes(ll_hb)

	sm_hb: [xitdb.BTREE_HEADER_LENGTH]u8
	testing.expect_value(t, xitdb.core_read_exact_at(&src_core, sm_c.?.slot_ptr.slot.value, sm_hb[:]), nil)
	sm_hdr, _ := xitdb.btree_header_from_bytes(sm_hb)

	seed_bytes := xitdb.core_memory_bytes(&src_core)

	// 1. Corrupted 1_000_000_000 header.size on moment 1's Array_List & Linked_Array_List must not spin/OOM in diff_moments
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		arr_pos := arr_c.?.slot_ptr.slot.value
		ll_pos := ll_c.?.slot_ptr.slot.value
		endian.put_u64(mut[arr_pos : arr_pos + 8], .Big, 1_000_000_000)
		endian.put_u64(mut[ll_pos : ll_pos + 8], .Big, 1_000_000_000)

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		diffs, diff_err := xitdb.diff_moments(&mdb, 0, 1, false, context.allocator)
		testing.expect_value(t, diff_err, nil)
		testing.expect(t, len(diffs) <= 8)
		xitdb.diff_changes_destroy(diffs, context.allocator)
	}

	// 2. Self-cyclic Sorted_Map .Branch root stops safely on writes/removals (no stack overflow)
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		root_ptr := sm_hdr.root_ptr
		self_child := xitdb.slot_to_bytes(xitdb.Slot{value = root_ptr, tag = .Index})
		first_child_pos := root_ptr + xitdb.BTREE_NODE_HEADER_SIZE
		copy(mut[first_child_pos : first_child_pos + xitdb.SLOT_LENGTH], self_child[:])

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		wtx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&wtx)
		testing.expect_value(t, xitdb.tx_put(&wtx, `$sm["k_00"]`, "mutated"), nil)
		wrep, werr := xitdb.tx_commit(&wtx)
		xitdb.tx_report_destroy(&wrep, context.allocator)
		testing.expect_value(t, werr, xitdb.Xitdb_Error.Max_Shift_Exceeded)

		rtx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&rtx)
		testing.expect_value(t, xitdb.tx_rm(&rtx, `$sm["k_00"]`), nil)
		rrep, rerr := xitdb.tx_commit(&rtx)
		xitdb.tx_report_destroy(&rrep, context.allocator)
		testing.expect_value(t, rerr, xitdb.Xitdb_Error.Max_Shift_Exceeded)
	}

	// 3. num == 0 corrupted .Branch node in Sorted_Map & Linked_Array_List rejects writes cleanly
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		// Force Sorted_Map root and Linked_Array_List root to kind=Branch(1), num=0
		mut[sm_hdr.root_ptr] = u8(xitdb.BTree_Node_Kind.Branch)
		mut[sm_hdr.root_ptr + 1] = 0
		mut[ll_hdr.root_ptr] = u8(xitdb.BTree_Node_Kind.Branch)
		mut[ll_hdr.root_ptr + 1] = 0

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		sm_tx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&sm_tx)
		testing.expect_value(t, xitdb.tx_put(&sm_tx, `$sm["k_00"]`, "v"), nil)
		sm_rep, sm_err := xitdb.tx_commit(&sm_tx)
		xitdb.tx_report_destroy(&sm_rep, context.allocator)
		testing.expect_value(t, sm_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		ll_tx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&ll_tx)
		testing.expect_value(t, xitdb.tx_insert(&ll_tx, ".ll", 0, "x"), nil)
		ll_rep, ll_err := xitdb.tx_commit(&ll_tx)
		xitdb.tx_report_destroy(&ll_rep, context.allocator)
		testing.expect_value(t, ll_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
	}
}

@(test)
unit_fuzz_regression_deep_hamt_diff_over_32_nibbles :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// Custom 32-byte (64-nibble) hasher whose first 24 bytes (48 nibbles) are identical across all keys,
	// forcing HAMT depth >= 48 nibbles (> the buggy 32-nibble limit before our fix).
	deep_hasher := xitdb.Hasher{
		hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
			for b_i in 0 ..< len(out_hash) {
				out_hash[b_i] = 0
			}
			tail_pos := 24
			for j := 0; j < len(data) && tail_pos + j < len(out_hash); j += 1 {
				out_hash[tail_pos + j] = data[j]
			}
		},
		hash_size = 32,
		id        = xitdb.string_to_id("dh48"),
	}

	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, derr := xitdb.database_init(&cm, deep_hasher)
	testing.expect_value(t, derr, nil)

	tx0 := xitdb.tx_init(&db, nil, false, context.allocator)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".m.alpha", "1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".m.bravo", "2"), nil)
	rep0, cerr0 := xitdb.tx_commit(&tx0)
	xitdb.tx_destroy(&tx0)
	testing.expect_value(t, cerr0, nil)
	xitdb.tx_report_destroy(&rep0, context.allocator)

	tx1 := xitdb.tx_init(&db, -1, false, context.allocator)
	testing.expect_value(t, xitdb.tx_put(&tx1, ".m.alpha", "1_updated"), nil)
	testing.expect_value(t, xitdb.tx_rm(&tx1, ".m.bravo"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, ".m.charlie", "3"), nil)
	rep1, cerr1 := xitdb.tx_commit(&tx1)
	xitdb.tx_destroy(&tx1)
	testing.expect_value(t, cerr1, nil)
	xitdb.tx_report_destroy(&rep1, context.allocator)

	c0, _ := xitdb.select_cursor(&db, "@0.m")
	c1, _ := xitdb.select_cursor(&db, "@1.m")
	changes, diff_err := xitdb.diff_collection(c0.?, c1.?, context.allocator)
	testing.expect_value(t, diff_err, nil)
	defer {
		for ch in changes {
			delete(ch.key, context.allocator)
		}
		delete(changes, context.allocator)
	}
	testing.expect_value(t, len(changes), 3)
}

@(test)
unit_fuzz_regression_dsl_persistent_allocator_and_where_boundaries :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// 1. Datalog "where" keyword requires whitespace boundaries (must not match inside ?somewhere / ?where)
	{
		q1, err1 := xitdb.parse_datalog(`find ?somewhere where .users[?id] = ?somewhere`, context.allocator)
		testing.expect_value(t, err1, nil)
		xitdb.datalog_query_destroy(&q1)

		q2, err2 := xitdb.parse_datalog("find ?where\nwhere\n.users[\"a\\\"b\"] = ?where", context.allocator)
		testing.expect_value(t, err2, nil)
		xitdb.datalog_query_destroy(&q2)

		q3, err3 := xitdb.parse_datalog("find ?a, ?b where reach(?a, ?b, .edge[?a] = ?b)", context.allocator)
		testing.expect_value(t, err3, nil)
		xitdb.datalog_query_destroy(&q3)

		for bad_q in ([]string{
			"find ?x wherein .a = ?x",
			"find ?somewhere",
			"where .users[?x] = 1",
			"find ?v where .users[\"a\\\"b\"] = ?v\nreach(?a, ?b, .edge[?a] = ?b, extra1, extra2)",
		}) {
			_, berr := xitdb.parse_datalog(bad_q, context.allocator)
			testing.expect_value(t, berr, xitdb.Xitdb_Error.Invalid_Range)
		}
	}

	// 2. parse_selector / parse_steps with escaped keys + mid-parse errors on persistent context.allocator
	{
		sel, serr := xitdb.parse_selector(`@0.users["es\"c\\aped"].age`, context.allocator)
		testing.expect_value(t, serr, nil)
		xitdb.selector_destroy(&sel, context.allocator)

		steps, perr := xitdb.parse_steps(`.users["a\"b\\c"].items[0]`, context.allocator)
		testing.expect_value(t, perr, nil)
		xitdb.steps_destroy(steps, context.allocator)

		_, bad_steps_err := xitdb.parse_steps(`.users["es\"c"].bad[unclosed`, context.allocator)
		testing.expect_value(t, bad_steps_err, xitdb.Xitdb_Error.Invalid_Range)
	}

	// 3. Pull, history_of, query_prefix, query_page, and mid-range pull error cleanup on context.allocator
	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, derr := xitdb.database_init(&cm, xitdb.sha1_hasher())
	testing.expect_value(t, derr, nil)

	tx := xitdb.tx_init(&db, nil, false, context.allocator)
	xitdb.tx_doc(&tx, "persistent alloc test")
	testing.expect_value(t, xitdb.tx_append(&tx, ".items", "first_long_item_string"), nil)
	testing.expect_value(t, xitdb.tx_append(&tx, ".items", "second_long_item_string"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, "$idx[\"alpha_key\"]", "va"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, "$idx[\"alpha_two\"]", "vb"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, "$idx[\"zeta_key\"]", "vz"), nil)
	rep, cerr := xitdb.tx_commit(&tx)
	xitdb.tx_destroy(&tx)
	testing.expect_value(t, cerr, nil)
	xitdb.tx_report_destroy(&rep, context.allocator)

	mc, _ := xitdb.select_cursor(&db, "@0")
	pv, perr := xitdb.pull(mc.?, "{.items[0..2], $idx}", context.allocator)
	testing.expect_value(t, perr, nil)
	xitdb.pull_value_destroy(pv, context.allocator)

	hist, herr := xitdb.history_of(&db, ".items", context.allocator)
	testing.expect_value(t, herr, nil)
	xitdb.history_entries_destroy(hist, context.allocator)

	hm_col, hm_err := xitdb.read_hash_map_init(mc.?)
	testing.expect_value(t, hm_err, nil)
	prefix_hits, pfx_err := xitdb.query_prefix(hm_col, "idx", "alpha", context.allocator)
	testing.expect_value(t, pfx_err, nil)
	testing.expect_value(t, len(prefix_hits), 2)
	xitdb.index_hits_destroy(prefix_hits, context.allocator)

	page_hits, pg_err := xitdb.query_page(hm_col, "idx", 0, 2, context.allocator)
	testing.expect_value(t, pg_err, nil)
	testing.expect_value(t, len(page_hits), 2)
	xitdb.index_hits_destroy(page_hits, context.allocator)

	// Corrupt element [1] of `.items` so _pull_range succeeds on [0] ("first_long_item_string")
	// and fails mid-range on [1], verifying partial heap allocations are cleaned up.
	item1_c, i1_err := xitdb.select_cursor(&db, "@0.items[1]")
	testing.expect_value(t, i1_err, nil)
	i1_pos := item1_c.?.slot_ptr.position.?
	raw := xitdb.core_memory_bytes(&cm)
	mut := make([]u8, len(raw), context.temp_allocator)
	copy(mut, raw)
	bad_elem := xitdb.slot_to_bytes(xitdb.Slot{value = -8, tag = .Bytes})
	copy(mut[i1_pos : i1_pos + xitdb.SLOT_LENGTH], bad_elem[:])

	mut_core := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&mut_core)
	mut_db, mdb_err := xitdb.database_init(&mut_core, xitdb.sha1_hasher())
	testing.expect_value(t, mdb_err, nil)

	mut_mc, _ := xitdb.select_cursor(&mut_db, "@0")
	_, bad_pull_err := xitdb.pull(mut_mc.?, "{.items[0..2]}", context.allocator)
	testing.expect(t, bad_pull_err != nil)
}
