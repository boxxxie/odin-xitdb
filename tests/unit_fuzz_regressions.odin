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
