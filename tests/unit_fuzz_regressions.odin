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
		testing.expect_value(t, loop_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)

		empty_cur := xitdb.Read_Cursor{db = &db}
		_, diff_err := xitdb.diff_collection(empty_cur, hrc.?, context.temp_allocator)
		testing.expect_value(t, diff_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)
	}

	// 3. Self-cyclic B-Tree .Branch node stops cleanly with .Invalid_BTree_Node
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
		testing.expect_value(t, get_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		_, it_err := xitdb.linked_array_list_iterator(ll_read)
		testing.expect_value(t, it_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
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

	// 1. Corrupted 1_000_000_000 header.size on moment 1's Array_List & Linked_Array_List must fail cleanly without spin/OOM in diff_moments
	{
		mut_arr := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut_arr, seed_bytes)
		arr_pos := arr_c.?.slot_ptr.slot.value
		endian.put_u64(mut_arr[arr_pos : arr_pos + 8], .Big, 1_000_000_000)

		mc_arr := xitdb.core_memory_init_from_bytes(mut_arr, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&mc_arr)
		mdb_arr, mda_err := xitdb.database_init(&mc_arr, xitdb.sha1_hasher())
		testing.expect_value(t, mda_err, nil)

		arr_diffs, arr_diff_err := xitdb.diff_moments(&mdb_arr, 0, 1, false, context.allocator)
		testing.expect_value(t, arr_diff_err, xitdb.Xitdb_Error.Unexpected_Tag)
		xitdb.diff_changes_destroy(arr_diffs, context.allocator)

		mut_ll := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut_ll, seed_bytes)
		ll_pos := ll_c.?.slot_ptr.slot.value
		endian.put_u64(mut_ll[ll_pos : ll_pos + 8], .Big, 1_000_000_000)

		mc_ll := xitdb.core_memory_init_from_bytes(mut_ll, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&mc_ll)
		mdb_ll, mdl_err := xitdb.database_init(&mc_ll, xitdb.sha1_hasher())
		testing.expect_value(t, mdl_err, nil)

		ll_diffs, ll_diff_err := xitdb.diff_moments(&mdb_ll, 0, 1, false, context.allocator)
		testing.expect_value(t, ll_diff_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
		xitdb.diff_changes_destroy(ll_diffs, context.allocator)
	}

	// 2. Self-cyclic Sorted_Map .Branch root stops safely on writes/removals (no stack overflow)
	{
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		root_ptr := sm_hdr.root_ptr
		self_child := xitdb.slot_to_bytes(xitdb.Slot{value = root_ptr, tag = .Index})
		first_child_pos := root_ptr + xitdb.BTREE_NODE_HEADER_SIZE
		copy(mut[first_child_pos : first_child_pos + xitdb.SLOT_LENGTH], self_child[:])

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		wtx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&wtx)
		testing.expect_value(t, xitdb.tx_put(&wtx, `$sm["k_00"]`, "mutated"), nil)
		wrep, werr := xitdb.tx_commit(&wtx)
		xitdb.tx_report_destroy(&wrep, context.allocator)
		testing.expect_value(t, werr, xitdb.Xitdb_Error.Invalid_BTree_Node)

		rtx := xitdb.tx_init(&mdb, 1, false, context.allocator)
		defer xitdb.tx_destroy(&rtx)
		testing.expect_value(t, xitdb.tx_rm(&rtx, `$sm["k_00"]`), nil)
		rrep, rerr := xitdb.tx_commit(&rtx)
		xitdb.tx_report_destroy(&rrep, context.allocator)
		testing.expect_value(t, rerr, xitdb.Xitdb_Error.Invalid_BTree_Node)
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

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
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

	// Unified 64-level Cursor_Iterator must also traverse >32-nibble HAMTs forward & reverse
	for rc in ([?]xitdb.Read_Cursor{c0.?, c1.?}) {
		fwd_it, fwd_err := xitdb.cursor_iterator(rc)
		testing.expect_value(t, fwd_err, nil)
		fwd_cnt := 0
		for {
			elem, nerr := xitdb.cursor_iterator_next(&fwd_it)
			testing.expect_value(t, nerr, nil)
			if elem == nil {
				break
			}
			fwd_cnt += 1
		}
		testing.expect_value(t, fwd_cnt, 2)

		rev_it, rev_err := xitdb.cursor_iterator_reverse(rc)
		testing.expect_value(t, rev_err, nil)
		rev_cnt := 0
		for {
			elem, perr := xitdb.cursor_iterator_prev(&rev_it)
			testing.expect_value(t, perr, nil)
			if elem == nil {
				break
			}
			rev_cnt += 1
		}
		testing.expect_value(t, rev_cnt, 2)
	}
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

@(test)
unit_fuzz_regression_btree_sibling_cycles_concat_max_size_and_shrink :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// Build 40-item Linked_Array_List (ll), 40-item Sorted_Map (sm), and 300-item height-2 Linked_Array_List (big_ll)
	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, init_err := xitdb.database_init(&cm, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx := xitdb.tx_init(&db, nil, false, context.allocator)
	defer xitdb.tx_destroy(&tx)
	for i in 0 ..< 40 {
		testing.expect_value(t, xitdb.tx_put(&tx, fmt.tprintf(".ll[[%d]]", i), fmt.tprintf("l_%02d", i)), nil)
		testing.expect_value(t, xitdb.tx_put(&tx, fmt.tprintf(`$sm["k_%02d"]`, i), fmt.tprintf("v_%02d", i)), nil)
	}
	for i in 0 ..< 300 {
		testing.expect_value(t, xitdb.tx_put(&tx, fmt.tprintf(".big[[%d]]", i), i64(i)), nil)
	}
	testing.expect_value(t, xitdb.tx_put(&tx, `.concat_b[[0]]`, "b0"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, `.concat_b[[1]]`, "b1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, `.height1[[0]]`, "h0"), nil)
	for i in 1 ..< 20 {
		testing.expect_value(t, xitdb.tx_put(&tx, fmt.tprintf(`.height1[[%d]]`, i), fmt.tprintf("h%d", i)), nil)
	}
	rep, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)
	xitdb.tx_report_destroy(&rep, context.allocator)

	ll_c, _ := xitdb.select_cursor(&db, "@0.ll")
	sm_c, _ := xitdb.select_cursor(&db, "@0$sm")
	big_c, _ := xitdb.select_cursor(&db, "@0.big")
	cb_c, _ := xitdb.select_cursor(&db, "@0.concat_b")

	read_hdr :: proc(c: ^xitdb.Core, hdr_pos: i64) -> xitdb.BTree_Header {
		hb: [xitdb.BTREE_HEADER_LENGTH]u8
		_ = xitdb.core_read_exact_at(c, hdr_pos, hb[:])
		h, _ := xitdb.btree_header_from_bytes(hb)
		return h
	}

	ll_hdr := read_hdr(&cm, ll_c.?.slot_ptr.slot.value)
	sm_hdr := read_hdr(&cm, sm_c.?.slot_ptr.slot.value)
	big_hdr := read_hdr(&cm, big_c.?.slot_ptr.slot.value)
	_ = read_hdr(&cm, cb_c.?.slot_ptr.slot.value)
	seed := xitdb.core_memory_bytes(&cm)

	// 1. children[cycle_idx] sibling cycle in Linked_Array_List & Sorted_Map rejects on horizontal step (forward & reverse)
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)

		ll_root, ll_rerr := xitdb.read_btree_node(&db, ll_hdr.root_ptr)
		testing.expect_value(t, ll_rerr, nil)
		testing.expect(t, ll_root.kind == .Branch && ll_root.num >= 3, "Expected >= 3 leaves in 40-item Linked_Array_List")
		ll_cycle_idx := ll_root.num - 2
		ll_child_pos := ll_hdr.root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + i64(ll_cycle_idx) * xitdb.SLOT_LENGTH
		ll_self := xitdb.slot_to_bytes(xitdb.Slot{value = ll_hdr.root_ptr, tag = .Index})
		copy(mut[ll_child_pos : ll_child_pos + xitdb.SLOT_LENGTH], ll_self[:])

		sm_root, sm_rerr := xitdb.read_sorted_node(&db, sm_hdr.root_ptr)
		testing.expect_value(t, sm_rerr, nil)
		testing.expect(t, sm_root.kind == .Branch && sm_root.num >= 3, "Expected >= 3 leaves in 40-item Sorted_Map")
		sm_cycle_idx := sm_root.num - 2
		sm_child_pos := sm_hdr.root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + i64(sm_cycle_idx) * xitdb.SLOT_LENGTH
		sm_self := xitdb.slot_to_bytes(xitdb.Slot{value = sm_hdr.root_ptr, tag = .Index})
		copy(mut[sm_child_pos : sm_child_pos + xitdb.SLOT_LENGTH], sm_self[:])

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		mlc, _ := xitdb.select_cursor(&mdb, "@0.ll")
		ll_fwd, ll_fi_err := xitdb.cursor_iterator(mlc.?)
		testing.expect_value(t, ll_fi_err, nil)
		ll_before_cycle: i64 = 0
		for k in 0 ..< ll_cycle_idx {
			ll_before_cycle += ll_root.counts[k]
		}
		for _ in 0 ..< ll_before_cycle {
			elem, step_err := xitdb.cursor_iterator_next(&ll_fwd)
			testing.expect_value(t, step_err, nil)
			testing.expect(t, elem != nil, "Expected valid Linked_Array_List items before cycle")
		}
		_, ll_cycle_err := xitdb.cursor_iterator_next(&ll_fwd)
		testing.expect_value(t, ll_cycle_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, ll_fwd.index, ll_before_cycle)

		ll_rev, ll_ri_err := xitdb.cursor_iterator_reverse(mlc.?)
		testing.expect_value(t, ll_ri_err, nil)
		last_cnt := ll_root.counts[ll_root.num - 1]
		for _ in 0 ..< last_cnt {
			elem, step_err := xitdb.cursor_iterator_prev(&ll_rev)
			testing.expect_value(t, step_err, nil)
			testing.expect(t, elem != nil, "Expected valid tail leaf before cycle in reverse")
		}
		_, ll_rcycle_err := xitdb.cursor_iterator_prev(&ll_rev)
		testing.expect_value(t, ll_rcycle_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, ll_rev.index, i64(40) - last_cnt)

		msc, _ := xitdb.select_cursor(&mdb, "@0$sm")
		sm_fwd, sm_fi_err := xitdb.cursor_iterator(msc.?)
		testing.expect_value(t, sm_fi_err, nil)
		sm_before_cycle: i64 = 0
		for k in 0 ..< sm_cycle_idx {
			sm_before_cycle += sm_root.counts[k]
		}
		for _ in 0 ..< sm_before_cycle {
			elem, step_err := xitdb.cursor_iterator_next(&sm_fwd)
			testing.expect_value(t, step_err, nil)
			testing.expect(t, elem != nil, "Expected valid Sorted_Map items before cycle")
		}
		_, sm_cycle_err := xitdb.cursor_iterator_next(&sm_fwd)
		testing.expect_value(t, sm_cycle_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, sm_fwd.index, sm_before_cycle)

		sm_rev, sm_ri_err := xitdb.cursor_iterator_reverse(msc.?)
		testing.expect_value(t, sm_ri_err, nil)
		sm_last_cnt := sm_root.counts[sm_root.num - 1]
		for _ in 0 ..< sm_last_cnt {
			elem, step_err := xitdb.cursor_iterator_prev(&sm_rev)
			testing.expect_value(t, step_err, nil)
			testing.expect(t, elem != nil, "Expected valid Sorted_Map tail leaf before cycle in reverse")
		}
		_, sm_rcycle_err := xitdb.cursor_iterator_prev(&sm_rev)
		testing.expect_value(t, sm_rcycle_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
	}

	// 2. sorted_reverse_from_key when leaf_count == 0 && before > 0 (valid stale-separator leaf + height validation on parent step)
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		sm_root_pre, _ := xitdb.read_sorted_node(&mdb, sm_hdr.root_ptr)
		leaf1_pre, _ := xitdb.read_sorted_node(&mdb, sm_root_pre.children[1].value)
		k0_slot, _ := xitdb.sorted_entry_key_slot(&mdb, leaf1_pre.entries[0])
		k0_rc := xitdb.Read_Cursor{slot_ptr = xitdb.Slot_Pointer{slot = k0_slot}, db = &mdb}
		sep_key, _ := xitdb.cursor_read_string(k0_rc, 0, context.temp_allocator)

		// Delete sep_key so branch sep[1] remains equal to sep_key while leaf1's first key is now > sep_key
		dtx := xitdb.tx_init(&mdb, 0, false, context.allocator)
		defer xitdb.tx_destroy(&dtx)
		testing.expect_value(t, xitdb.tx_rm(&dtx, fmt.tprintf(`$sm["%s"]`, sep_key)), nil)
		drep, dcerr := xitdb.tx_commit(&dtx)
		testing.expect_value(t, dcerr, nil)
		xitdb.tx_report_destroy(&drep, context.allocator)

		msc2, _ := xitdb.select_cursor(&mdb, "@1$sm")
		rit, rerr := xitdb.cursor_iterator_sorted_reverse_from_key(msc2.?, transmute([]u8)sep_key, true)
		testing.expect_value(t, rerr, nil)
		testing.expect_value(t, rit.index, sm_root_pre.counts[0])
		testing.expect(t, rit.stack_len >= 2 && rit.stack[0].shift == 1, "Expected leaf pushed even when leaf_count == 0 && before > 0")

		got_cnt := 0
		for {
			cur_m, perr := xitdb.cursor_iterator_prev(&rit)
			testing.expect_value(t, perr, nil)
			if cur_m == nil {
				break
			}
			got_cnt += 1
		}
		testing.expect_value(t, i64(got_cnt), sm_root_pre.counts[0])
	}

	// 3. Linked_Array_List.concat rejects under-counted root and height-2 + height-1 cycle in children[last]
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		endian.put_u64(mut[cb_c.?.slot_ptr.slot.value : cb_c.?.slot_ptr.slot.value + 8], .Big, 1) // real leaf has 2

		big_root, br_err := xitdb.read_btree_node(&db, big_hdr.root_ptr)
		testing.expect_value(t, br_err, nil)
		testing.expect(t, big_root.kind == .Branch, "Expected height-2 branch on 300-item big_ll")
		last_slot_pos := big_hdr.root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + i64(big_root.num - 1) * xitdb.SLOT_LENGTH
		big_self := xitdb.slot_to_bytes(xitdb.Slot{value = big_hdr.root_ptr, tag = .Index})
		copy(mut[last_slot_pos : last_slot_pos + xitdb.SLOT_LENGTH], big_self[:])

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		Concat_Ctx :: struct {
			target_key: string,
			source_key: string,
		}
		concat_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c_ctx := (^Concat_Ctx)(user_data)
			hm := xitdb.write_hash_map_init(cursor^) or_return
			src_slot := (xitdb.hash_map_get_slot(hm.read_hash_map, c_ctx.source_key) or_return).?
			wlc := xitdb.hash_map_put_cursor(&hm, c_ctx.target_key) or_return
			wl := xitdb.write_linked_array_list_init(wlc) or_return
			return xitdb.linked_array_list_concat(&wl, src_slot)
		}

		history, _ := xitdb.write_array_list_init(xitdb.database_root_cursor(&mdb))
		m0_slot, _ := xitdb.array_list_get_slot(history.read_array_list, 0)

		// Under-counted concat target B
		c1 := Concat_Ctx{target_key = "ll", source_key = "concat_b"}
		concat_err1 := xitdb.array_list_append_context(&history, m0_slot.?, concat_cb, &c1)
		testing.expect_value(t, concat_err1, xitdb.Xitdb_Error.Invalid_BTree_Node)

		// Height-2 + height-1 join where big.children[last] cycles back to big_root
		c2 := Concat_Ctx{target_key = "big", source_key = "height1"}
		concat_err2 := xitdb.array_list_append_context(&history, m0_slot.?, concat_cb, &c2)
		testing.expect_value(t, concat_err2, xitdb.Xitdb_Error.Invalid_BTree_Node)
	}

	// 4. Sorted_Map.put at header.size == max(i64) allows overwrite, rejects new key without writing orphans
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		sm_pos := sm_c.?.slot_ptr.slot.value
		sm_root, _ := xitdb.read_sorted_node(&db, sm_hdr.root_ptr)
		// Inflate counts[0] so total branch count == max(i64) - 1? Set both header.size and counts[0] cleanly:
		sum_rest: i64 = 0
		for j in 1 ..< sm_root.num {
			sum_rest += sm_root.counts[j]
		}
		endian.put_u64(mut[sm_pos : sm_pos + 8], .Big, u64(max(i64)))
		cnt0_pos := sm_hdr.root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + xitdb.SLOT_LENGTH * 2 * xitdb.BTREE_SLOT_COUNT
		endian.put_u64(mut[cnt0_pos : cnt0_pos + 8], .Big, u64(max(i64) - sum_rest))

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, md_err := xitdb.database_init(&mc, xitdb.sha1_hasher())
		testing.expect_value(t, md_err, nil)

		// New key fails BEFORE writing any new nodes
		new_tx := xitdb.tx_init(&mdb, 0, false, context.allocator)
		defer xitdb.tx_destroy(&new_tx)
		len_before, _ := xitdb.core_length(&mc)
		testing.expect_value(t, xitdb.tx_put(&new_tx, `$sm["z_brand_new_key"]`, "val"), nil)
		nrep, nerr := xitdb.tx_commit(&new_tx)
		xitdb.tx_report_destroy(&nrep, context.allocator)
		testing.expect_value(t, nerr, xitdb.Xitdb_Error.Invalid_BTree_Node)
		len_after, _ := xitdb.core_length(&mc)
		// Only root tx rollback truncated back to len_before
		testing.expect_value(t, len_after, len_before)

		// Overwrite existing key in untouched rightmost leaf succeeds
		ov_tx := xitdb.tx_init(&mdb, 0, false, context.allocator)
		defer xitdb.tx_destroy(&ov_tx)
		testing.expect_value(t, xitdb.tx_put(&ov_tx, `$sm["k_39"]`, "updated"), nil)
		orep, oerr := xitdb.tx_commit(&ov_tx)
		testing.expect_value(t, oerr, nil)
		xitdb.tx_report_destroy(&orep, context.allocator)
	}

	// 5. remove(-1) root-shrink loop validates untouched sibling subtree count
	{
		lcm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&lcm)
		ldb, lerr := xitdb.database_init(&lcm, xitdb.sha1_hasher())
		testing.expect_value(t, lerr, nil)
		ltx := xitdb.tx_init(&ldb, nil, false, context.allocator)
		defer xitdb.tx_destroy(&ltx)
		for i in 0 ..< 17 {
			testing.expect_value(t, xitdb.tx_put(&ltx, fmt.tprintf(".rlist[[%d]]", i), i64(i)), nil)
		}
		lrep, lcerr := xitdb.tx_commit(&ltx)
		testing.expect_value(t, lcerr, nil)
		xitdb.tx_report_destroy(&lrep, context.allocator)

		rl_c, _ := xitdb.select_cursor(&ldb, "@0.rlist")
		rl_hdr := read_hdr(&lcm, rl_c.?.slot_ptr.slot.value)
		rl_root, _ := xitdb.read_btree_node(&ldb, rl_hdr.root_ptr)
		testing.expect_value(t, rl_root.num, 2)

		// Make leaf1 have num = 1 so removing last item hits btree_drop_child(&node, 1) -> root.num == 1,
		// while corrupting sibling leaf0.num downward so promoted sibling subtree_count != header.size - 1.
		lseed := xitdb.core_memory_bytes(&lcm)
		lmut := make([]u8, len(lseed), context.temp_allocator)
		copy(lmut, lseed)
		leaf0_ptr := rl_root.children[0].value
		leaf1_ptr := rl_root.children[1].value
		orig_c0 := rl_root.counts[0]
		endian.put_u64(lmut[rl_c.?.slot_ptr.slot.value : rl_c.?.slot_ptr.slot.value + 8], .Big, u64(orig_c0 + 1))
		cnt1_pos := rl_hdr.root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + xitdb.SLOT_LENGTH * xitdb.BTREE_SLOT_COUNT + 8
		endian.put_u64(lmut[cnt1_pos : cnt1_pos + 8], .Big, 1)
		lmut[leaf1_ptr + 1] = 1
		// Corrupt sibling leaf0 header count downward by 1 (leaving trailing slots untouched? Read validates trailing slots so set leaf0.num = orig_c0 - 1 and zero last slot)
		lmut[leaf0_ptr + 1] = u8(orig_c0 - 1)
		last_leaf0_slot := leaf0_ptr + xitdb.BTREE_NODE_HEADER_SIZE + (orig_c0 - 1) * xitdb.SLOT_LENGTH
		for b in 0 ..< xitdb.SLOT_LENGTH {
			lmut[last_leaf0_slot + i64(b)] = 0
		}

		lmc := xitdb.core_memory_init_from_bytes(lmut, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&lmc)
		lmdb, lm_err := xitdb.database_init(&lmc, xitdb.sha1_hasher())
		testing.expect_value(t, lm_err, nil)

		rem_cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			whm := xitdb.write_hash_map_init(cursor^) or_return
			wrl_c := xitdb.hash_map_put_cursor(&whm, "rlist") or_return
			wrl := xitdb.write_linked_array_list_init(wrl_c) or_return
			return xitdb.linked_array_list_remove(&wrl, -1)
		}
		history, _ := xitdb.write_array_list_init(xitdb.database_root_cursor(&lmdb))
		m0_slot, _ := xitdb.array_list_get_slot(history.read_array_list, 0)
		rem_err := xitdb.array_list_append_context(&history, m0_slot.?, rem_cb, nil)
		testing.expect_value(t, rem_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
	}
}

@(test)
unit_fuzz_regression_array_list_counted_map_and_sorted_empty_fast_paths :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, init_err := xitdb.database_init(&cm, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx := xitdb.tx_init(&db, nil, false, context.allocator)
	defer xitdb.tx_destroy(&tx)
	for i in 0 ..< 20 {
		testing.expect_value(t, xitdb.tx_append(&tx, ".al20", fmt.tprintf("a_%02d", i)), nil)
	}
	for i in 0 ..< 3 {
		testing.expect_value(t, xitdb.tx_append(&tx, ".al3", fmt.tprintf("s_%02d", i)), nil)
	}
	testing.expect_value(t, xitdb.tx_put(&tx, `#chm["k1"]`, "v1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, `#chm["k2"]`, "v2"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, `#empty_chm["tmp"]`, "gone"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx, `$empty_sm["tmp"]`, "gone"), nil)
	// Slice al20_sliced -> 5 + append empty unwritten slot -> valid sliced Array_List (keep al20 at size 20!)
	for i in 0 ..< 20 {
		testing.expect_value(t, xitdb.tx_append(&tx, ".al20_sliced", fmt.tprintf("p_%d", i)), nil)
	}
	testing.expect_value(t, xitdb.tx_slice(&tx, ".al20_sliced", 5), nil)
	rep, cerr := xitdb.tx_commit(&tx)
	testing.expect_value(t, cerr, nil)
	xitdb.tx_report_destroy(&rep, context.allocator)

	// Remove "tmp" in moment 1 so empty_chm and empty_sm exist on disk with size == 0
	tx1 := xitdb.tx_init(&db, 0, false, context.allocator)
	defer xitdb.tx_destroy(&tx1)
	testing.expect_value(t, xitdb.tx_rm(&tx1, `#empty_chm["tmp"]`), nil)
	testing.expect_value(t, xitdb.tx_rm(&tx1, `$empty_sm["tmp"]`), nil)
	rep1, cerr1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, cerr1, nil)
	xitdb.tx_report_destroy(&rep1, context.allocator)

	// Valid sliced Array_List + trailing full=true empty slot iterates forward & reverse without error
	{
		slice_app_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			tp := (^testing.T)(user_data)
			whm := xitdb.write_hash_map_init(cursor^) or_return
			wal_c := xitdb.hash_map_put_cursor(&whm, "al20_sliced") or_return
			wal := xitdb.write_array_list_init(wal_c) or_return
			_, app_err := xitdb.array_list_append_cursor(&wal)
			testing.expect_value(tp, app_err, nil)

			fwd, fi_err := xitdb.cursor_iterator(wal.cursor)
			testing.expect_value(tp, fi_err, nil)
			testing.expect_value(tp, fwd.size, i64(6))
			fcnt := 0
			for {
				cur, nerr := xitdb.cursor_iterator_next(&fwd)
				testing.expect_value(tp, nerr, nil)
				if cur == nil {
					break
				}
				fcnt += 1
			}
			testing.expect_value(tp, fcnt, 6)

			rev, ri_err := xitdb.cursor_iterator_reverse(wal.cursor)
			testing.expect_value(tp, ri_err, nil)
			testing.expect_value(tp, rev.size, i64(6))
			rcnt := 0
			for {
				cur, perr := xitdb.cursor_iterator_prev(&rev)
				testing.expect_value(tp, perr, nil)
				if cur == nil {
					break
				}
				rcnt += 1
			}
			testing.expect_value(tp, rcnt, 6)
			return nil
		}
		history, _ := xitdb.write_array_list_init(xitdb.database_root_cursor(&db))
		m1_slot, _ := xitdb.array_list_get_slot(history.read_array_list, 1)
		testing.expect_value(t, xitdb.array_list_append_context(&history, m1_slot.?, slice_app_cb, t), nil)
	}

	al20_c, _ := xitdb.select_cursor(&db, "@1.al20")
	al3_c, _ := xitdb.select_cursor(&db, "@1.al3")
	chm_c, _ := xitdb.select_cursor(&db, "@1.chm")
	echm_c, _ := xitdb.select_cursor(&db, "@1.empty_chm")
	esm_c, _ := xitdb.select_cursor(&db, "@1.empty_sm")
	seed := xitdb.core_memory_bytes(&cm)

	// 1. Array_List corrupted downward & upward header.size
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		// Downward: 20-item shift=1 trie corrupted to size=5 -> sh=0 leaf check hits .Index tag
		endian.put_u64(mut[al20_c.?.slot_ptr.slot.value : al20_c.?.slot_ptr.slot.value + 8], .Big, 5)
		// Upward: 3-item shift=0 leaf corrupted to size=5 -> yields 3 then slot 3 empty -> Unexpected_Tag
		endian.put_u64(mut[al3_c.?.slot_ptr.slot.value : al3_c.?.slot_ptr.slot.value + 8], .Big, 5)

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, _ := xitdb.database_init(&mc, xitdb.sha1_hasher())

		mal20, _ := xitdb.select_cursor(&mdb, "@1.al20")
		_, down_err := xitdb.cursor_iterator(mal20.?)
		testing.expect_value(t, down_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, down_rev_err := xitdb.cursor_iterator_reverse(mal20.?)
		testing.expect_value(t, down_rev_err, xitdb.Xitdb_Error.Unexpected_Tag)

		mal3, _ := xitdb.select_cursor(&mdb, "@1.al3")
		al3_it, up_init_err := xitdb.cursor_iterator(mal3.?)
		testing.expect_value(t, up_init_err, nil)
		for _ in 0 ..< 3 {
			_, e := xitdb.cursor_iterator_next(&al3_it)
			testing.expect_value(t, e, nil)
		}
		_, up_err := xitdb.cursor_iterator_next(&al3_it)
		testing.expect_value(t, up_err, xitdb.Xitdb_Error.Unexpected_Tag)
		testing.expect_value(t, al3_it.index, i64(3))
	}

	// 2. Counted_Hash_Map: empty decode skip, inflated-count premature exhaustion (fwd/rev), mid-walk index preservation
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		// Empty map (count == 0): overwrite slot 0 tag byte with 99 -> init must skip decode and succeed
		mut[echm_c.?.slot_ptr.slot.value + 8] = 99
		// Inflate chm (2 real entries) count to 5
		endian.put_u64(mut[chm_c.?.slot_ptr.slot.value : chm_c.?.slot_ptr.slot.value + 8], .Big, 5)

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, _ := xitdb.database_init(&mc, xitdb.sha1_hasher())

		mechm, _ := xitdb.select_cursor(&mdb, "@1.empty_chm")
		efwd, efi_err := xitdb.cursor_iterator(mechm.?)
		testing.expect_value(t, efi_err, nil)
		testing.expect_value(t, efwd.size, i64(0))
		ef_next, ef_err := xitdb.cursor_iterator_next(&efwd)
		testing.expect_value(t, ef_err, nil)
		testing.expect(t, ef_next == nil, "Expected nil on empty counted map")

		erev, eri_err := xitdb.cursor_iterator_reverse(mechm.?)
		testing.expect_value(t, eri_err, nil)
		er_prev, er_err := xitdb.cursor_iterator_prev(&erev)
		testing.expect_value(t, er_err, nil)
		testing.expect(t, er_prev == nil, "Expected nil on empty counted map reverse")

		mchm, _ := xitdb.select_cursor(&mdb, "@1.chm")
		cfwd, cfi_err := xitdb.cursor_iterator(mchm.?)
		testing.expect_value(t, cfi_err, nil)
		testing.expect_value(t, cfwd.size, i64(5))
		for _ in 0 ..< 2 {
			_, e := xitdb.cursor_iterator_next(&cfwd)
			testing.expect_value(t, e, nil)
		}
		_, c_prem_err := xitdb.cursor_iterator_next(&cfwd)
		testing.expect_value(t, c_prem_err, xitdb.Xitdb_Error.Invalid_Database)
		testing.expect_value(t, cfwd.index, i64(2))

		crev, cri_err := xitdb.cursor_iterator_reverse(mchm.?)
		testing.expect_value(t, cri_err, nil)
		testing.expect_value(t, crev.index, i64(5))
		for _ in 0 ..< 2 {
			_, e := xitdb.cursor_iterator_prev(&crev)
			testing.expect_value(t, e, nil)
		}
		_, cr_prem_err := xitdb.cursor_iterator_prev(&crev)
		testing.expect_value(t, cr_prem_err, xitdb.Xitdb_Error.Invalid_Database)
		testing.expect_value(t, crev.index, i64(3))
	}

	// 3. Sorted_Map header.size == 0 fast-paths ignore unreadable root_ptr
	{
		mut := make([]u8, len(seed), context.temp_allocator)
		copy(mut, seed)
		esm_pos := esm_c.?.slot_ptr.slot.value
		endian.put_u64(mut[esm_pos + 8 : esm_pos + 16], .Big, 0x7fff_ffff_ffff_0000)

		mc := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 1024 * 1024)
		defer xitdb.core_destroy(&mc)
		mdb, _ := xitdb.database_init(&mc, xitdb.sha1_hasher())

		mesm, _ := xitdb.select_cursor(&mdb, "@1$empty_sm")
		rsm, _ := xitdb.read_sorted_map_init(mesm.?)
		g, gerr := xitdb.sorted_map_get_cursor(rsm, "k")
		testing.expect_value(t, gerr, nil)
		testing.expect(t, g == nil, "Expected nil from empty Sorted_Map get")
		rk, rerr := xitdb.sorted_map_rank(rsm, "k")
		testing.expect_value(t, rerr, nil)
		testing.expect_value(t, rk, i64(0))

		_, f_err := xitdb.sorted_map_iterator(rsm)
		testing.expect_value(t, f_err, nil)
		_, rv_err := xitdb.sorted_map_iterator_reverse(rsm)
		testing.expect_value(t, rv_err, nil)
		_, fk_err := xitdb.sorted_map_iterator_from_string(rsm, "k")
		testing.expect_value(t, fk_err, nil)
		_, rk_err := xitdb.sorted_map_iterator_reverse_from_string(rsm, "k")
		testing.expect_value(t, rk_err, nil)
		_, fi_err := xitdb.sorted_map_iterator_from_index(rsm, 0)
		testing.expect_value(t, fi_err, nil)
		_, ri_err := xitdb.sorted_map_iterator_reverse_from_index(rsm, 0)
		testing.expect_value(t, ri_err, nil)

		sm_rm_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			tp := (^testing.T)(user_data)
			whm := xitdb.write_hash_map_init(cursor^) or_return
			wsm_c := xitdb.hash_map_put_cursor(&whm, "empty_sm") or_return
			wsm := xitdb.write_sorted_map_init(wsm_c) or_return
			removed, rm_err := xitdb.sorted_map_remove(&wsm, "k")
			testing.expect_value(tp, removed, false)
			testing.expect_value(tp, rm_err, nil)
			_, raw_rm_err := xitdb.cursor_write_path(&wsm.write_cursor, []xitdb.Path_Part{xitdb.Sorted_Map_Remove{key = transmute([]u8)string("k")}})
			testing.expect_value(tp, raw_rm_err, xitdb.Xitdb_Error.Key_Not_Found)
			return nil
		}
		history, _ := xitdb.write_array_list_init(xitdb.database_root_cursor(&mdb))
		m1_slot, _ := xitdb.array_list_get_slot(history.read_array_list, 1)
		testing.expect_value(t, xitdb.array_list_append_context(&history, m1_slot.?, sm_rm_cb, t), nil)
	}
}

@(test)
unit_fuzz_regression_diff_collection_scratch_allocator_no_leaks :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&cm)
	db, derr := xitdb.database_init(&cm, xitdb.sha1_hasher())
	testing.expect_value(t, derr, nil)

	// Moment 0: populate Hash_Map (.hm) and >20-entry Sorted_Map ($sm)
	tx0 := xitdb.tx_init(&db, nil, false, context.allocator)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".hm.keep", "same"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".hm.update", "v1"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx0, ".hm.drop", "gone"), nil)
	for i in 0 ..< 24 {
		path := fmt.tprintf(`$sm["long_key_%02d"]`, i)
		testing.expect_value(t, xitdb.tx_put(&tx0, path, i64(i)), nil)
	}
	rep0, cerr0 := xitdb.tx_commit(&tx0)
	xitdb.tx_destroy(&tx0)
	testing.expect_value(t, cerr0, nil)
	xitdb.tx_report_destroy(&rep0, context.allocator)

	// Moment 1: mutate subsets of both collections to force leaf/block comparisons
	tx1 := xitdb.tx_init(&db, -1, false, context.allocator)
	testing.expect_value(t, xitdb.tx_put(&tx1, ".hm.update", "v2"), nil)
	testing.expect_value(t, xitdb.tx_rm(&tx1, ".hm.drop"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, ".hm.added", "new"), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, `$sm["long_key_00"]`, i64(100)), nil)
	testing.expect_value(t, xitdb.tx_rm(&tx1, `$sm["long_key_05"]`), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, `$sm["long_key_12"]`, i64(200)), nil)
	testing.expect_value(t, xitdb.tx_rm(&tx1, `$sm["long_key_19"]`), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, `$sm["long_key_24_extra"]`, i64(24)), nil)
	testing.expect_value(t, xitdb.tx_put(&tx1, `$sm["long_key_25_extra"]`, i64(25)), nil)
	rep1, cerr1 := xitdb.tx_commit(&tx1)
	xitdb.tx_destroy(&tx1)
	testing.expect_value(t, cerr1, nil)
	xitdb.tx_report_destroy(&rep1, context.allocator)

	free_changes :: proc(changes: []xitdb.Collection_Change) {
		for ch in changes {
			delete(ch.key, context.allocator)
		}
		delete(changes, context.allocator)
	}

	empty_cur := xitdb.Read_Cursor{
		slot_ptr = xitdb.Slot_Pointer{slot = xitdb.Slot{}},
		db       = &db,
	}
	hm0, ok_hm0 := xitdb.select_cursor(&db, "@0.hm")
	hm1, ok_hm1 := xitdb.select_cursor(&db, "@1.hm")
	sm0, ok_sm0 := xitdb.select_cursor(&db, "@0$sm")
	sm1, ok_sm1 := xitdb.select_cursor(&db, "@1$sm")
	testing.expect(t, ok_hm0 == nil && ok_hm1 == nil && ok_sm0 == nil && ok_sm1 == nil, "Expected cursors to resolve")

	// 1. Empty <-> Hash_Map (_diff_hash_maps `entries` scratch path)
	stats: xitdb.Diff_Stats
	ch_empty_hm, err_eh := xitdb.diff_collection_with_stats(empty_cur, hm0.?, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_eh, nil)
	testing.expect_value(t, len(ch_empty_hm), 3)
	free_changes(ch_empty_hm)

	ch_hm_empty, err_he := xitdb.diff_collection_with_stats(hm0.?, empty_cur, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_he, nil)
	testing.expect_value(t, len(ch_hm_empty), 3)
	free_changes(ch_hm_empty)

	// 2. Hash_Map <-> Hash_Map (_diff_index_blocks `ea`/`eb` + `_collect_slot` `hash` scratch path)
	ch_hm, err_hm := xitdb.diff_collection_with_stats(hm0.?, hm1.?, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_hm, nil)
	testing.expect_value(t, len(ch_hm), 3)
	free_changes(ch_hm)

	// 3. Empty <-> Sorted_Map and Sorted_Map <-> Sorted_Map (`key_b` per-iteration scratch path)
	ch_empty_sm, err_es := xitdb.diff_collection_with_stats(empty_cur, sm0.?, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_es, nil)
	testing.expect_value(t, len(ch_empty_sm), 24)
	free_changes(ch_empty_sm)

	ch_sm_empty, err_se := xitdb.diff_collection_with_stats(sm0.?, empty_cur, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_se, nil)
	testing.expect_value(t, len(ch_sm_empty), 24)
	free_changes(ch_sm_empty)

	ch_sm, err_sm := xitdb.diff_collection_with_stats(sm0.?, sm1.?, &stats, context.allocator, context.allocator)
	testing.expect_value(t, err_sm, nil)
	testing.expect_value(t, len(ch_sm), 6)
	testing.expect(t, stats.keys_decoded > 0, "Expected keys_decoded > 0 during sorted map diff")
	free_changes(ch_sm)
}

@(test)
unit_unified_depth_hamt_and_btree_64_levels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	// -------------------------------------------------------------------------
	// 1. 64-nibble HAMT boundary (keys share 63 leading zero nibbles, differ at nibble 63)
	// -------------------------------------------------------------------------
	{
		nibble64_hasher := xitdb.Hasher{
			hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
				for idx in 0 ..< len(out_hash) {
					out_hash[idx] = 0
				}
				if len(data) > 0 {
					// hamt_nibble reads from the end; nibble 63 is the high nibble of byte 0.
					out_hash[0] = (data[0] & 0x0F) << 4
				}
			},
			hash_size = 32,
			id        = xitdb.string_to_id("dh64"),
		}

		cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
		defer _ = xitdb.core_destroy(&cm)
		db, derr := xitdb.database_init(&cm, nibble64_hasher)
		testing.expect_value(t, derr, nil)

		tx0 := xitdb.tx_init(&db, nil, false, context.allocator)
		testing.expect_value(t, xitdb.tx_put(&tx0, ".m.a", "v_a"), nil)
		testing.expect_value(t, xitdb.tx_put(&tx0, ".m.b", "v_b"), nil)
		rep0, cerr0 := xitdb.tx_commit(&tx0)
		xitdb.tx_destroy(&tx0)
		testing.expect_value(t, cerr0, nil)
		xitdb.tx_report_destroy(&rep0, context.allocator)

		tx1 := xitdb.tx_init(&db, -1, false, context.allocator)
		testing.expect_value(t, xitdb.tx_put(&tx1, ".m.a", "v_a2"), nil)
		rep1, cerr1 := xitdb.tx_commit(&tx1)
		xitdb.tx_destroy(&tx1)
		testing.expect_value(t, cerr1, nil)
		xitdb.tx_report_destroy(&rep1, context.allocator)

		m0_rc, m0_err := xitdb.select_cursor(&db, "@0.m")
		m1_rc, m1_err := xitdb.select_cursor(&db, "@1.m")
		testing.expect(t, m0_err == nil && m1_err == nil, "Expected 64-nibble HAMT cursors")

		hm1, hm1_err := xitdb.read_hash_map_init(m1_rc.?)
		testing.expect_value(t, hm1_err, nil)
		a_rc, a_err := xitdb.hash_map_get_cursor(hm1, "a")
		testing.expect_value(t, a_err, nil)
		a_str, a_serr := xitdb.cursor_read_string(a_rc.?, 0, context.temp_allocator)
		testing.expect_value(t, a_serr, nil)
		testing.expect_value(t, a_str, "v_a2")

		fwd_it, fwd_err := xitdb.cursor_iterator(m1_rc.?)
		testing.expect_value(t, fwd_err, nil)
		fwd_cnt := 0
		for {
			elem, nerr := xitdb.cursor_iterator_next(&fwd_it)
			testing.expect_value(t, nerr, nil)
			if elem == nil {
				break
			}
			fwd_cnt += 1
		}
		testing.expect_value(t, fwd_cnt, 2)

		rev_it, rev_err := xitdb.cursor_iterator_reverse(m1_rc.?)
		testing.expect_value(t, rev_err, nil)
		rev_cnt := 0
		for {
			elem, perr := xitdb.cursor_iterator_prev(&rev_it)
			testing.expect_value(t, perr, nil)
			if elem == nil {
				break
			}
			rev_cnt += 1
		}
		testing.expect_value(t, rev_cnt, 2)

		changes, diff_err := xitdb.diff_collection(m0_rc.?, m1_rc.?, context.allocator)
		testing.expect_value(t, diff_err, nil)
		testing.expect_value(t, len(changes), 1)
		if len(changes) == 1 {
			testing.expect_value(t, string(changes[0].key), "a")
			testing.expect_value(t, changes[0].op, xitdb.Collection_Change_Op.Changed)
		}
		for ch in changes {
			delete(ch.key, context.allocator)
		}
		delete(changes, context.allocator)

		// Exercise _collect_index_block down to depth 63 and _collect_slot at depth 64
		empty_hamt := xitdb.Read_Cursor{db = &db}
		added_changes, add_diff_err := xitdb.diff_collection(empty_hamt, m1_rc.?, context.allocator)
		testing.expect_value(t, add_diff_err, nil)
		testing.expect_value(t, len(added_changes), 2)
		for ach in added_changes {
			testing.expect_value(t, ach.op, xitdb.Collection_Change_Op.Added)
			delete(ach.key, context.allocator)
		}
		delete(added_changes, context.allocator)
	}

	// -------------------------------------------------------------------------
	// 2. Self-cyclic SHA-256 HAMT block fails cleanly with .Key_Offset_Exceeded
	// -------------------------------------------------------------------------
	{
		seed_cm := xitdb.core_memory_init(context.allocator, reserve_size = 0)
		defer _ = xitdb.core_destroy(&seed_cm)
		seed_db, serr := xitdb.database_init(&seed_cm, xitdb.sha256_hasher())
		testing.expect_value(t, serr, nil)

		tx := xitdb.tx_init(&seed_db, nil, false, context.allocator)
		testing.expect_value(t, xitdb.tx_put(&tx, ".hm.a", "va"), nil)
		testing.expect_value(t, xitdb.tx_put(&tx, ".hm.b", "vb"), nil)
		rep, cerr := xitdb.tx_commit(&tx)
		xitdb.tx_destroy(&tx)
		testing.expect_value(t, cerr, nil)
		xitdb.tx_report_destroy(&rep, context.allocator)

		hm_seed_rc, hms_err := xitdb.select_cursor(&seed_db, "@0.hm")
		testing.expect_value(t, hms_err, nil)
		hm_pos := hm_seed_rc.?.slot_ptr.slot.value

		seed_bytes := seed_cm.(xitdb.Core_Memory).buf[:]
		mut := make([]u8, len(seed_bytes), context.temp_allocator)
		copy(mut, seed_bytes)
		self_idx := xitdb.slot_to_bytes(xitdb.Slot{value = hm_pos, tag = .Index})
		for slot_i in 0 ..< xitdb.SLOT_COUNT {
			off := int(hm_pos) + slot_i * xitdb.SLOT_LENGTH
			copy(mut[off : off + xitdb.SLOT_LENGTH], self_idx[:])
		}

		c := xitdb.core_memory_init_from_bytes(mut, context.allocator, reserve_size = 0)
		defer _ = xitdb.core_destroy(&c)
		db, derr := xitdb.database_init(&c, xitdb.sha256_hasher())
		testing.expect_value(t, derr, nil)

		hrc, herr := xitdb.select_cursor(&db, "@0.hm")
		testing.expect_value(t, herr, nil)
		hm, hm_err := xitdb.read_hash_map_init(hrc.?)
		testing.expect_value(t, hm_err, nil)

		_, get_err := xitdb.hash_map_get_cursor(hm, "a")
		testing.expect_value(t, get_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)

		fwd_it, fi_err := xitdb.cursor_iterator(hrc.?)
		testing.expect_value(t, fi_err, nil)
		fwd_err: xitdb.Error
		for _ in 0 ..< 80 {
			_, nerr := xitdb.cursor_iterator_next(&fwd_it)
			if nerr != nil {
				fwd_err = nerr
				break
			}
		}
		testing.expect_value(t, fwd_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)

		rev_it, ri_err := xitdb.cursor_iterator_reverse(hrc.?)
		testing.expect_value(t, ri_err, nil)
		rev_err: xitdb.Error
		for _ in 0 ..< 80 {
			_, perr := xitdb.cursor_iterator_prev(&rev_it)
			if perr != nil {
				rev_err = perr
				break
			}
		}
		testing.expect_value(t, rev_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)

		empty_cur := xitdb.Read_Cursor{db = &db}
		_, diff_err := xitdb.diff_collection(empty_cur, hrc.?, context.temp_allocator)
		testing.expect_value(t, diff_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)
	}

	// -------------------------------------------------------------------------
	// 3. 64-level vs 65-level B-Tree boundary (Linked_Array_List & Sorted_Map)
	// -------------------------------------------------------------------------
	Build_Chain_Cfg :: struct {
		branches: int,
	}

	build_deep_btrees_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		cfg := (^Build_Chain_Cfg)(user_data)
		db_ptr := cursor.read_cursor.db
		moment := xitdb.write_hash_map_init(cursor^) or_return

		ll_cur := xitdb.hash_map_put_cursor(&moment, "ll") or_return
		ll := xitdb.write_linked_array_list_init(ll_cur) or_return
		xitdb.linked_array_list_append(&ll, "v0") or_return
		xitdb.linked_array_list_append(&ll, "v1") or_return

		sm_cur := xitdb.hash_map_put_cursor(&moment, "sm") or_return
		sm := xitdb.write_sorted_map_init(sm_cur) or_return
		xitdb.sorted_map_put(&sm, "k0", "s0") or_return
		xitdb.sorted_map_put(&sm, "k1", "s1") or_return

		ll_hdr_pos := ll.write_cursor.slot_ptr.slot.value
		ll_hb: [xitdb.BTREE_HEADER_LENGTH]u8
		xitdb.core_read_exact_at(db_ptr.core, ll_hdr_pos, ll_hb[:]) or_return
		ll_hdr := xitdb.btree_header_from_bytes(ll_hb) or_return
		ll_root := ll_hdr.root_ptr
		for _ in 0 ..< cfg.branches {
			node := xitdb.BTree_Node{kind = .Branch, num = 1}
			node.children[0] = xitdb.Slot{value = ll_root, tag = .Index}
			node.counts[0] = ll_hdr.size
			ll_root = xitdb.write_btree_node(db_ptr, node) or_return
		}
		xitdb.core_seek_to(db_ptr.core, ll_hdr_pos) or_return
		new_ll_hb := xitdb.btree_header_to_bytes(xitdb.BTree_Header{root_ptr = ll_root, size = ll_hdr.size})
		xitdb.core_write_all(db_ptr.core, new_ll_hb[:]) or_return

		sm_hdr_pos := sm.write_cursor.slot_ptr.slot.value
		sm_hb: [xitdb.BTREE_HEADER_LENGTH]u8
		xitdb.core_read_exact_at(db_ptr.core, sm_hdr_pos, sm_hb[:]) or_return
		sm_hdr := xitdb.btree_header_from_bytes(sm_hb) or_return
		sm_root := sm_hdr.root_ptr
		for _ in 0 ..< cfg.branches {
			node := xitdb.Sorted_Node{kind = .Branch, num = 1}
			node.children[0] = xitdb.Slot{value = sm_root, tag = .Index}
			node.counts[0] = sm_hdr.size
			sm_root = xitdb.write_sorted_node(db_ptr, node) or_return
		}
		xitdb.core_seek_to(db_ptr.core, sm_hdr_pos) or_return
		new_sm_hb := xitdb.btree_header_to_bytes(xitdb.BTree_Header{root_ptr = sm_root, size = sm_hdr.size})
		xitdb.core_write_all(db_ptr.core, new_sm_hb[:]) or_return
		return nil
	}

	read_btree_header_at :: proc(t_ptr: ^testing.T, db_ptr: ^xitdb.Database, rc: xitdb.Read_Cursor) -> xitdb.BTree_Header {
		hb: [xitdb.BTREE_HEADER_LENGTH]u8
		rerr := xitdb.core_read_exact_at(db_ptr.core, rc.slot_ptr.slot.value, hb[:])
		testing.expect_value(t_ptr, rerr, nil)
		hdr, herr := xitdb.btree_header_from_bytes(hb)
		testing.expect_value(t_ptr, herr, nil)
		return hdr
	}

	// 3a. 64 levels (63 branches + 1 leaf): reads, iterators, writes, small-stack diff, and root collapse succeed
	{
		cm64 := xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&cm64)
		db64, d64_err := xitdb.database_init(&cm64, xitdb.sha1_hasher())
		testing.expect_value(t, d64_err, nil)

		cfg64 := Build_Chain_Cfg{branches = 63}
		tx0 := xitdb.tx_init(&db64, nil, false, context.allocator)
		xitdb.tx_with_cursor(&tx0, build_deep_btrees_cb, &cfg64)
		rep0, c0_err := xitdb.tx_commit(&tx0)
		xitdb.tx_destroy(&tx0)
		testing.expect_value(t, c0_err, nil)
		xitdb.tx_report_destroy(&rep0, context.allocator)

		ll0_rc, ll0_err := xitdb.select_cursor(&db64, "@0.ll")
		sm0_rc, sm0_err := xitdb.select_cursor(&db64, "@0$sm")
		testing.expect(t, ll0_err == nil && sm0_err == nil, "Expected 64-level collections at @0")

		ll0_hdr := read_btree_header_at(t, &db64, ll0_rc.?)
		sm0_hdr := read_btree_header_at(t, &db64, sm0_rc.?)
		ll0_h, ll0_herr := xitdb.btree_height(&db64, ll0_hdr.root_ptr)
		sm0_h, sm0_herr := xitdb.btree_height(&db64, sm0_hdr.root_ptr)
		testing.expect_value(t, ll0_herr, nil)
		testing.expect_value(t, ll0_h, 63)
		testing.expect_value(t, sm0_herr, nil)
		testing.expect_value(t, sm0_h, 63)

		ll0, ll0_ierr := xitdb.read_linked_array_list_init(ll0_rc.?)
		testing.expect_value(t, ll0_ierr, nil)
		ll_v1_cur, ll_v1_err := xitdb.linked_array_list_get_cursor(ll0, 1)
		testing.expect_value(t, ll_v1_err, nil)
		ll_v1_str, ll_v1_serr := xitdb.cursor_read_string(ll_v1_cur.?, 0, context.temp_allocator)
		testing.expect_value(t, ll_v1_serr, nil)
		testing.expect_value(t, ll_v1_str, "v1")

		sm0, sm0_ierr := xitdb.read_sorted_map_init(sm0_rc.?)
		testing.expect_value(t, sm0_ierr, nil)
		sm_k1_cur, sm_k1_err := xitdb.sorted_map_get_cursor(sm0, "k1")
		testing.expect_value(t, sm_k1_err, nil)
		sm_k1_str, sm_k1_serr := xitdb.cursor_read_string(sm_k1_cur.?, 0, context.temp_allocator)
		testing.expect_value(t, sm_k1_serr, nil)
		testing.expect_value(t, sm_k1_str, "s1")

		rk1, rk1_err := xitdb.sorted_map_rank(sm0, "k1")
		testing.expect_value(t, rk1_err, nil)
		testing.expect_value(t, rk1, i64(1))

		it := new(xitdb.Cursor_Iterator)
		defer free(it)

		// Linked_Array_List forward/reverse/seek iterators at depth 64
		testing.expect_value(t, xitdb.cursor_iterator_init(it, ll0_rc.?), nil)
		ll_fwd_cnt := 0
		for {
			elem, nerr := xitdb.cursor_iterator_next(it)
			testing.expect_value(t, nerr, nil)
			if elem == nil {
				break
			}
			ll_fwd_cnt += 1
		}
		testing.expect_value(t, ll_fwd_cnt, 2)

		testing.expect_value(t, xitdb.cursor_iterator_reverse_init(it, ll0_rc.?), nil)
		ll_rev_cnt := 0
		for {
			elem, perr := xitdb.cursor_iterator_prev(it)
			testing.expect_value(t, perr, nil)
			if elem == nil {
				break
			}
			ll_rev_cnt += 1
		}
		testing.expect_value(t, ll_rev_cnt, 2)

		expect_ll_item_str :: proc(t_ptr: ^testing.T, cur_maybe: Maybe(xitdb.Read_Cursor), expected: string) {
			c, ok := cur_maybe.?
			testing.expect(t_ptr, ok, "Expected Linked_Array_List seek cursor")
			if ok {
				s, serr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
				testing.expect_value(t_ptr, serr, nil)
				testing.expect_value(t_ptr, s, expected)
			}
		}

		expect_sm_kv_str :: proc(t_ptr: ^testing.T, cur_maybe: Maybe(xitdb.Read_Cursor), exp_key, exp_val: string) {
			c, ok := cur_maybe.?
			testing.expect(t_ptr, ok, "Expected Sorted_Map seek cursor")
			if ok {
				kc, vc, kerr := xitdb.cursor_read_kv_pair_slots(c)
				testing.expect_value(t_ptr, kerr, nil)
				ks, kserr := xitdb.cursor_read_string(kc, 0, context.temp_allocator)
				vs, vserr := xitdb.cursor_read_string(vc, 0, context.temp_allocator)
				testing.expect_value(t_ptr, kserr, nil)
				testing.expect_value(t_ptr, vserr, nil)
				testing.expect_value(t_ptr, ks, exp_key)
				testing.expect_value(t_ptr, vs, exp_val)
			}
		}

		testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_from_index_init(it, ll0_rc.?, 1), nil)
		ll_seek_c, ll_seek_err := xitdb.cursor_iterator_next(it)
		testing.expect_value(t, ll_seek_err, nil)
		expect_ll_item_str(t, ll_seek_c, "v1")

		testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, ll0_rc.?, 0), nil)
		ll_rseek_c, ll_rseek_err := xitdb.cursor_iterator_prev(it)
		testing.expect_value(t, ll_rseek_err, nil)
		expect_ll_item_str(t, ll_rseek_c, "v0")

		// Sorted_Map forward/reverse/seek iterators at depth 64
		testing.expect_value(t, xitdb.cursor_iterator_init(it, sm0_rc.?), nil)
		sm_fwd_cnt := 0
		for {
			elem, nerr := xitdb.cursor_iterator_next(it)
			testing.expect_value(t, nerr, nil)
			if elem == nil {
				break
			}
			sm_fwd_cnt += 1
		}
		testing.expect_value(t, sm_fwd_cnt, 2)

		testing.expect_value(t, xitdb.cursor_iterator_reverse_init(it, sm0_rc.?), nil)
		sm_rev_cnt := 0
		for {
			elem, perr := xitdb.cursor_iterator_prev(it)
			testing.expect_value(t, perr, nil)
			if elem == nil {
				break
			}
			sm_rev_cnt += 1
		}
		testing.expect_value(t, sm_rev_cnt, 2)

		testing.expect_value(t, xitdb.cursor_iterator_sorted_from_index_init(it, sm0_rc.?, 1), nil)
		sm_si_c, sm_si_err := xitdb.cursor_iterator_next(it)
		testing.expect_value(t, sm_si_err, nil)
		expect_sm_kv_str(t, sm_si_c, "k1", "s1")

		testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, sm0_rc.?, 1), nil)
		sm_sri_c, sm_sri_err := xitdb.cursor_iterator_prev(it)
		testing.expect_value(t, sm_sri_err, nil)
		expect_sm_kv_str(t, sm_sri_c, "k1", "s1")

		testing.expect_value(t, xitdb.cursor_iterator_sorted_from_key_init(it, sm0_rc.?, transmute([]u8)string("k1")), nil)
		sm_sk_c, sm_sk_err := xitdb.cursor_iterator_next(it)
		testing.expect_value(t, sm_sk_err, nil)
		expect_sm_kv_str(t, sm_sk_c, "k1", "s1")

		testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, sm0_rc.?, transmute([]u8)string("k1")), nil)
		sm_srk_c, sm_srk_err := xitdb.cursor_iterator_prev(it)
		testing.expect_value(t, sm_srk_err, nil)
		expect_sm_kv_str(t, sm_srk_c, "k1", "s1")

		// Moment 1: overwrite across frozen 64-level spines
		tx1 := xitdb.tx_init(&db64, -1, false, context.allocator)
		tx1_cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			moment := xitdb.write_hash_map_init(cursor^) or_return
			sm_w := xitdb.write_sorted_map_init(xitdb.hash_map_put_cursor(&moment, "sm") or_return) or_return
			xitdb.sorted_map_put(&sm_w, "k0", "s0_v2") or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&moment, "ll") or_return) or_return
			xitdb.linked_array_list_put(&ll_w, 1, "v1_v2") or_return
			return nil
		}
		xitdb.tx_with_cursor(&tx1, tx1_cb)
		rep1, c1_err := xitdb.tx_commit(&tx1)
		xitdb.tx_destroy(&tx1)
		testing.expect_value(t, c1_err, nil)
		xitdb.tx_report_destroy(&rep1, context.allocator)

		sm1_rc, sm1_err := xitdb.select_cursor(&db64, "@1$sm")
		testing.expect_value(t, sm1_err, nil)

		// Diff two path-copied 64-level Sorted_Maps on a 512 KiB small stack
		Diff_Worker_Args :: struct {
			t: ^testing.T,
			a: xitdb.Read_Cursor,
			b: xitdb.Read_Cursor,
		}
		diff_worker :: proc(raw: rawptr) {
			w := (^Diff_Worker_Args)(raw)
			changes, derr := xitdb.diff_collection(w.a, w.b, context.allocator)
			testing.expect_value(w.t, derr, nil)
			testing.expect_value(w.t, len(changes), 1)
			if len(changes) == 1 {
				testing.expect_value(w.t, changes[0].op, xitdb.Collection_Change_Op.Changed)
				testing.expect_value(w.t, string(changes[0].key), "k0")
			}
			for ch in changes {
				delete(ch.key, context.allocator)
			}
			delete(changes, context.allocator)
		}
		diff_args := Diff_Worker_Args{t = t, a = sm0_rc.?, b = sm1_rc.?}
		_run_on_small_stack(t, 512 * 1024, diff_worker, &diff_args)

		// Moment 2: remove from 64-level Linked_Array_List, collapsing all 63 single-child branches
		tx2 := xitdb.tx_init(&db64, -1, false, context.allocator)
		tx2_cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			moment := xitdb.write_hash_map_init(cursor^) or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&moment, "ll") or_return) or_return
			xitdb.linked_array_list_remove(&ll_w, 0) or_return
			return nil
		}
		xitdb.tx_with_cursor(&tx2, tx2_cb)
		rep2, c2_err := xitdb.tx_commit(&tx2)
		xitdb.tx_destroy(&tx2)
		testing.expect_value(t, c2_err, nil)
		xitdb.tx_report_destroy(&rep2, context.allocator)

		ll2_rc, ll2_err := xitdb.select_cursor(&db64, "@2.ll")
		testing.expect_value(t, ll2_err, nil)
		ll2_hdr := read_btree_header_at(t, &db64, ll2_rc.?)
		testing.expect_value(t, ll2_hdr.size, i64(1))
		ll2_h, ll2_herr := xitdb.btree_height(&db64, ll2_hdr.root_ptr)
		testing.expect_value(t, ll2_herr, nil)
		testing.expect_value(t, ll2_h, 0)
		ll2_val, ll2_verr := xitdb.get_string(&db64, "@2.ll[[0]]", context.temp_allocator)
		testing.expect_value(t, ll2_verr, nil)
		testing.expect_value(t, ll2_val, "v1_v2")
	}

	// 3b. 65 levels (64 branches + 1 leaf): every read, write, seek, iterator, and diff returns .Invalid_BTree_Node
	{
		cm65 := xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&cm65)
		db65, d65_err := xitdb.database_init(&cm65, xitdb.sha1_hasher())
		testing.expect_value(t, d65_err, nil)

		cfg65 := Build_Chain_Cfg{branches = 64}
		tx65 := xitdb.tx_init(&db65, nil, false, context.allocator)
		xitdb.tx_with_cursor(&tx65, build_deep_btrees_cb, &cfg65)
		rep65, c65_err := xitdb.tx_commit(&tx65)
		xitdb.tx_destroy(&tx65)
		testing.expect_value(t, c65_err, nil)
		xitdb.tx_report_destroy(&rep65, context.allocator)

		ll65_rc, ll65_err := xitdb.select_cursor(&db65, "@0.ll")
		sm65_rc, sm65_err := xitdb.select_cursor(&db65, "@0$sm")
		testing.expect(t, ll65_err == nil && sm65_err == nil, "Expected 65-level root cursors")

		ll65_hdr := read_btree_header_at(t, &db65, ll65_rc.?)
		sm65_hdr := read_btree_header_at(t, &db65, sm65_rc.?)
		_, ll65_herr := xitdb.btree_height(&db65, ll65_hdr.root_ptr)
		_, sm65_herr := xitdb.btree_height(&db65, sm65_hdr.root_ptr)
		testing.expect_value(t, ll65_herr, xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, sm65_herr, xitdb.Xitdb_Error.Invalid_BTree_Node)

		ll65, ll65_ierr := xitdb.read_linked_array_list_init(ll65_rc.?)
		testing.expect_value(t, ll65_ierr, nil)
		_, ll65_get_err := xitdb.linked_array_list_get_cursor(ll65, 0)
		testing.expect_value(t, ll65_get_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		sm65, sm65_ierr := xitdb.read_sorted_map_init(sm65_rc.?)
		testing.expect_value(t, sm65_ierr, nil)
		_, sm65_get_err := xitdb.sorted_map_get_cursor(sm65, "k0")
		testing.expect_value(t, sm65_get_err, xitdb.Xitdb_Error.Invalid_BTree_Node)
		_, sm65_rank_err := xitdb.sorted_map_rank(sm65, "k0")
		testing.expect_value(t, sm65_rank_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		it65 := new(xitdb.Cursor_Iterator)
		defer free(it65)
		testing.expect_value(t, xitdb.cursor_iterator_init(it65, ll65_rc.?), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_reverse_init(it65, ll65_rc.?), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_from_index_init(it65, ll65_rc.?, 0), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it65, ll65_rc.?, 0), xitdb.Xitdb_Error.Invalid_BTree_Node)

		testing.expect_value(t, xitdb.cursor_iterator_init(it65, sm65_rc.?), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_reverse_init(it65, sm65_rc.?), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_sorted_from_index_init(it65, sm65_rc.?, 0), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_index_init(it65, sm65_rc.?, 0), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_sorted_from_key_init(it65, sm65_rc.?, transmute([]u8)string("k0")), xitdb.Xitdb_Error.Invalid_BTree_Node)
		testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_key_init(it65, sm65_rc.?, transmute([]u8)string("k0")), xitdb.Xitdb_Error.Invalid_BTree_Node)

		empty65 := xitdb.Read_Cursor{db = &db65}
		_, diff65_err := xitdb.diff_collection(empty65, sm65_rc.?, context.temp_allocator)
		testing.expect_value(t, diff65_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		expect_65_write_err :: proc(t_ptr: ^testing.T, db_ptr: ^xitdb.Database, fn: xitdb.Context_Function) {
			tx := xitdb.tx_init(db_ptr, -1, false, context.allocator)
			xitdb.tx_with_cursor(&tx, fn)
			rep, cerr := xitdb.tx_commit(&tx)
			xitdb.tx_destroy(&tx)
			xitdb.tx_report_destroy(&rep, context.allocator)
			testing.expect_value(t_ptr, cerr, xitdb.Xitdb_Error.Invalid_BTree_Node)
		}

		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&m, "ll") or_return) or_return
			return xitdb.linked_array_list_put(&ll_w, 0, "x")
		})
		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&m, "ll") or_return) or_return
			return xitdb.linked_array_list_insert(&ll_w, 0, "x")
		})
		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&m, "ll") or_return) or_return
			return xitdb.linked_array_list_remove(&ll_w, 0)
		})
		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			ll_w := xitdb.write_linked_array_list_init(xitdb.hash_map_put_cursor(&m, "ll") or_return) or_return
			return xitdb.linked_array_list_slice(&ll_w, 0, 1)
		})
		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			sm_w := xitdb.write_sorted_map_init(xitdb.hash_map_put_cursor(&m, "sm") or_return) or_return
			return xitdb.sorted_map_put(&sm_w, "k0", "x")
		})
		expect_65_write_err(t, &db65, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			m := xitdb.write_hash_map_init(cursor^) or_return
			sm_w := xitdb.write_sorted_map_init(xitdb.hash_map_put_cursor(&m, "sm") or_return) or_return
			_, rerr := xitdb.sorted_map_remove(&sm_w, "k0")
			return rerr
		})
	}
}
