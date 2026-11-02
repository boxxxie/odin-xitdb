package xitdb_tests

import "core:slice"
import "core:testing"
import xitdb "../xitdb"

// ============================================================================
// Direct Unit & Integration Tests for the User DSL (`xitdb/dsl.odin`)
// ============================================================================

@(test)
unit_user_dsl_selector_sigils_combinators_and_nested_resolution :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, err, nil)

	// 1. Round-trip all 8 Step_Kind combinators through format_steps -> parse_steps
	original_steps := []xitdb.Path_Step{
		xitdb.hm("users"),
		xitdb.hm("user.with.dots"),
		xitdb.chm("metrics"),
		xitdb.sm("catalog"),
		xitdb.al(0),
		xitdb.ll(-1),
		xitdb.hs("admin"),
		xitdb.chs("active"),
		xitdb.ss("odin"),
	}
	formatted := xitdb.format_steps(original_steps, context.temp_allocator)
	parsed, p_err := xitdb.parse_steps(formatted, context.temp_allocator)
	testing.expect_value(t, p_err, nil)
	testing.expect_value(t, len(parsed), len(original_steps))
	for i in 0 ..< len(original_steps) {
		testing.expect_value(t, parsed[i].kind, original_steps[i].kind)
		testing.expect_value(t, parsed[i].key, original_steps[i].key)
		testing.expect_value(t, parsed[i].index, original_steps[i].index)
	}

	// 2. Quoted sigil keys (%"admin", ^"http", #%"u1", $["apple"], #["views"])
	tx := xitdb.tx_init(&db, base_moment = nil)
	_ = xitdb.tx_put(&tx, "$catalog[\"apple\"]", u64(150))
	_ = xitdb.tx_put(&tx, "#metrics[\"views\"]", i64(-42))
	_ = xitdb.tx_put(&tx, ".ratios[\"pi\"]", f64(3.14))
	_ = xitdb.tx_put(&tx, ".roles%\"admin\"", "admin")
	_ = xitdb.tx_put(&tx, ".visitors#%\"u1\"", "u1")
	_ = xitdb.tx_put(&tx, ".deps^\"http\"", "http")
	_ = xitdb.tx_put(&tx, ".arr[0]", "first_arr")
	_ = xitdb.tx_put(&tx, ".linked[[0]]", "first_linked")
	_, tx_err := xitdb.tx_commit(&tx)
	testing.expect_value(t, tx_err, nil)

	// Resolve nested Sorted_Map ($), Counted_Hash_Map (#), Sets (%, #%, ^), and Lists ([], [[]]) inside Moment 0
	price, err_u := xitdb.get_uint(&db, "@0$catalog[\"apple\"]")
	testing.expect_value(t, err_u, nil)
	testing.expect_value(t, price, u64(150))

	views, err_i := xitdb.get_int(&db, "@0#metrics[\"views\"]")
	testing.expect_value(t, err_i, nil)
	testing.expect_value(t, views, i64(-42))

	pi_val, err_f := xitdb.get_float(&db, "@0.ratios[\"pi\"]")
	testing.expect_value(t, err_f, nil)
	testing.expect_value(t, pi_val, f64(3.14))

	role_str, err_r := xitdb.get_string(&db, "@0.roles%\"admin\"")
	testing.expect_value(t, err_r, nil)
	testing.expect_value(t, role_str, "admin")

	vis_str, err_v := xitdb.get_string(&db, "@0.visitors#%\"u1\"")
	testing.expect_value(t, err_v, nil)
	testing.expect_value(t, vis_str, "u1")

	dep_str, err_d := xitdb.get_string(&db, "@0.deps^\"http\"")
	testing.expect_value(t, err_d, nil)
	testing.expect_value(t, dep_str, "http")

	arr_str, err_a := xitdb.get_string(&db, "@0.arr[-1]")
	testing.expect_value(t, err_a, nil)
	testing.expect_value(t, arr_str, "first_arr")

	ll_str, err_l := xitdb.get_string(&db, "@0.linked[[-1]]")
	testing.expect_value(t, err_l, nil)
	testing.expect_value(t, ll_str, "first_linked")

	// 3. Error guards on missing keys, wrong scalar tags, and malformed selectors
	_, missing_err := xitdb.get_string(&db, "@0.nonexistent")
	testing.expect_value(t, missing_err, xitdb.Xitdb_Error.Key_Not_Found)

	_, wrong_tag_err := xitdb.get_uint(&db, "@0.arr[0]")
	testing.expect_value(t, wrong_tag_err, xitdb.Xitdb_Error.Unexpected_Tag)

	for bad_sel in ([]string{"@", "@-", "@abc", ".users[\"unterminated]", ".list[abc]", ".ll[[0]"}) {
		_, bad_err := xitdb.parse_selector(bad_sel)
		testing.expect_value(t, bad_err, xitdb.Xitdb_Error.Invalid_Range)
	}
}

@(test)
unit_user_dsl_tx_wants_tx_meta_gating_fork_and_savepoint :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// 1. Silent Tx (track_changes = false, no doc/instant/meta):
	//    Must NOT write a "__tx" key or run diff_cursors.
	tx0 := xitdb.tx_init(&db, base_moment = nil, track_changes = false)
	xitdb.tx_put_steps(&tx0, {xitdb.hm("k1")}, "v1")
	xitdb.tx_append_steps(&tx0, {xitdb.hm("items")}, "a")
	xitdb.tx_append_steps(&tx0, {xitdb.hm("items")}, "b")
	rep0, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)
	testing.expect_value(t, rep0.moment_index, i64(0))
	testing.expect(t, rep0.tx_meta == nil, "Expected silent Tx to omit __tx map")
	testing.expect_value(t, len(rep0.changes), 0)

	tx_cur0, _ := xitdb.select_cursor(&db, "@0.__tx")
	testing.expect(t, tx_cur0 == nil, "Expected @0.__tx cursor to be absent when wants_tx_meta is false")

	// 2. Tracked Tx (track_changes = true, with doc, instant, meta, fork, and savepoint):
	//    Must write "__tx" and record changes while isolating forked collections.
	tx1 := xitdb.tx_init(&db, base_moment = 0, track_changes = true)
	xitdb.tx_doc(&tx1, "Fork items and update k1")
	xitdb.tx_instant(&tx1, 1700001234)
	xitdb.tx_meta(&tx1, "env", "staging")
	_ = xitdb.tx_fork(&tx1, ".items", ".items_snapshot")
	xitdb.tx_savepoint(&tx1)
	_ = xitdb.tx_put(&tx1, ".k1", "v1_updated")
	_ = xitdb.tx_append(&tx1, ".items", "c")
	rep1, err1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, err1, nil)
	testing.expect_value(t, rep1.moment_index, i64(1))
	testing.expect(t, rep1.tx_meta != nil, "Expected tracked Tx to populate __tx map")
	testing.expect(t, len(rep1.changes) >= 2, "Expected recorded changes in rep1.changes")

	// Verify __tx metadata fields in Moment 1
	doc1, _ := xitdb.get_string(&db, "@1.__tx.doc")
	inst1, _ := xitdb.get_int(&db, "@1.__tx.tx_instant")
	parent1, _ := xitdb.get_int(&db, "@1.__tx.parent")
	env1, _ := xitdb.get_string(&db, "@1.__tx.env")
	testing.expect_value(t, doc1, "Fork items and update k1")
	testing.expect_value(t, inst1, i64(1700001234))
	testing.expect_value(t, parent1, i64(0))
	testing.expect_value(t, env1, "staging")

	// Verify `.items_snapshot` was isolated by `tx_fork` (2 items) while `.items` has 3 items
	snap_cur, _ := xitdb.select_cursor(&db, "@1.items_snapshot")
	live_cur, _ := xitdb.select_cursor(&db, "@1.items")
	snap_cnt, _ := xitdb.cursor_count(snap_cur.?)
	live_cnt, _ := xitdb.cursor_count(live_cur.?)
	testing.expect_value(t, snap_cnt, i64(2))
	testing.expect_value(t, live_cnt, i64(3))
}

@(test)
unit_user_dsl_transact_script_literals_and_ops :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// 1. Genesis script with all literal flavours (u64, i64, negative i64, f64, short/long strings, 2-byte tagged strings)
	_, err0 := xitdb.transact_script(&db, `
		branch genesis {
			doc "Script literal matrix"
			instant 1700000100
			meta "rev" = 1u

			put .u_explicit = 42u
			put .u_bare     = 100
			put .i_explicit = 7i
			put .i_negative = -99
			put .f_val      = 2.71828
			put .short_tag  = "hi"^^js
			put .long_tag   = "long markdown body > 8 bytes"^^md
			put .drop_me    = "temporary"
			append .list    = "one"
			append .list    = "two"
			append .list    = "three"
		}
	`)
	testing.expect_value(t, err0, nil)

	u_exp, _ := xitdb.get_uint(&db, "@0.u_explicit")
	u_bar, _ := xitdb.get_uint(&db, "@0.u_bare")
	i_exp, _ := xitdb.get_int(&db, "@0.i_explicit")
	i_neg, _ := xitdb.get_int(&db, "@0.i_negative")
	f_val, _ := xitdb.get_float(&db, "@0.f_val")
	testing.expect_value(t, u_exp, u64(42))
	testing.expect_value(t, u_bar, u64(100))
	testing.expect_value(t, i_exp, i64(7))
	testing.expect_value(t, i_neg, i64(-99))
	testing.expect_value(t, f_val, f64(2.71828))

	// Check inline Short_Bytes (<= 6 bytes with 2-byte tag) vs external Bytes (> 6 bytes with 2-byte tag)
	short_cur, _ := xitdb.select_cursor(&db, "@0.short_tag")
	short_slot, _ := xitdb.cursor_slot(short_cur.?)
	short_obj, _ := xitdb.cursor_read_bytes_object(short_cur.?, 64, context.temp_allocator)
	testing.expect_value(t, short_slot.tag, xitdb.Tag.Short_Bytes)
	testing.expect_value(t, short_slot.full, true)
	testing.expect_value(t, string(short_obj.value), "hi")
	testing.expect_value(t, string(short_obj.format_tag), "js")

	long_cur, _ := xitdb.select_cursor(&db, "@0.long_tag")
	long_slot, _ := xitdb.cursor_slot(long_cur.?)
	long_obj, _ := xitdb.cursor_read_bytes_object(long_cur.?, 64, context.temp_allocator)
	testing.expect_value(t, long_slot.tag, xitdb.Tag.Bytes)
	testing.expect_value(t, long_slot.full, true)
	testing.expect_value(t, string(long_obj.value), "long markdown body > 8 bytes")
	testing.expect_value(t, string(long_obj.format_tag), "md")

	// 2. Branch @0 and execute `rm` and `slice`
	_, err1 := xitdb.transact_script(&db, `
		branch @0 {
			rm .drop_me
			slice .list 2
		}
	`)
	testing.expect_value(t, err1, nil)

	dropped_cur, _ := xitdb.select_cursor(&db, "@1.drop_me")
	testing.expect(t, dropped_cur == nil, "Expected .drop_me to be removed in @1")
	list_cur, _ := xitdb.select_cursor(&db, "@1.list")
	list_cnt, _ := xitdb.cursor_count(list_cur.?)
	testing.expect_value(t, list_cnt, i64(2))

	// 3. Script syntax error guards
	_, bad_tag_err := xitdb.transact_script(&db, `put .x = "hello"^^invalid_tag_len`)
	testing.expect_value(t, bad_tag_err, xitdb.Xitdb_Error.Invalid_Format_Tag_Size)

	_, bad_cmd_err := xitdb.transact_script(&db, `unknown_command .x = 1`)
	testing.expect_value(t, bad_cmd_err, xitdb.Xitdb_Error.Invalid_Range)
}

@(test)
unit_user_dsl_marshal_unmarshal_types_and_pull_ranges :: proc(t: ^testing.T) {
	Nested_Meta :: struct {
		created_by: string `xitdb:"created_by"`,
		version:    u16    `xitdb:"version"`,
	}

	Full_Record :: struct {
		active:   bool        `xitdb:"active"`,
		score:    i32         `xitdb:"score"`,
		ratio:    f64         `xitdb:"ratio"`,
		raw_data: []u8        `xitdb:"raw_data"`,
		notes:    string      `xitdb:"notes,tag=md"`,
		items:    []string    `xitdb:"items"`,
		queue:    []string    `xitdb:"[[queue]]"`,
		roles:    []string    `xitdb:"%roles"`,
		tags:     []string    `xitdb:"^tags"`,
		meta:     Nested_Meta `xitdb:"meta"`,
		ignored:  string      `xitdb:"-"`,
	}

	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	input := Full_Record{
		active   = true,
		score    = -120,
		ratio    = 0.875,
		raw_data = []u8{0xde, 0xad, 0xbe, 0xef},
		notes    = "# Spec",
		items    = {"a0", "a1", "a2", "a3"},
		queue    = {"q0", "q1", "q2", "q3"},
		roles    = {"admin"},
		tags     = {"zig", "odin", "ash"},
		meta     = Nested_Meta{created_by = "paul", version = 3},
		ignored  = "must_not_persist",
	}

	tx := xitdb.tx_init(&db, base_moment = nil)
	xitdb.tx_with_cursor(&tx, proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		rec := (^Full_Record)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		rcur := xitdb.hash_map_put_cursor(&m, "rec") or_return
		return xitdb.marshal(&rcur, rec^)
	}, &input)
	rep, err := xitdb.tx_commit(&tx)
	testing.expect_value(t, err, nil)

	// Verify `xitdb:"-"` field was skipped
	ignored_cur, _ := xitdb.select_cursor(&db, "@0.rec.ignored")
	testing.expect(t, ignored_cur == nil, "Expected xitdb:\"-\" field to be omitted")

	// Verify `unmarshal` round-trips all scalar, slice, set, linked-list, and nested struct types
	rec_cur, _ := xitdb.select_cursor(&db, "@0.rec")
	out, u_err := xitdb.unmarshal(Full_Record, rec_cur.?, context.temp_allocator)
	testing.expect_value(t, u_err, nil)
	testing.expect_value(t, out.active, true)
	testing.expect_value(t, out.score, i32(-120))
	testing.expect_value(t, out.ratio, f64(0.875))
	testing.expect(t, slice.equal(out.raw_data, []u8{0xde, 0xad, 0xbe, 0xef}), "Expected raw_data bytes to match")
	testing.expect_value(t, out.notes, "# Spec")
	testing.expect_value(t, out.meta.created_by, "paul")
	testing.expect_value(t, out.meta.version, u16(3))
	testing.expect_value(t, out.ignored, "")
	driver_assert_string_slice(t, out.items, []string{"a0", "a1", "a2", "a3"})
	driver_assert_string_slice(t, out.queue, []string{"q0", "q1", "q2", "q3"})
	driver_assert_string_slice(t, out.roles, []string{"admin"})
	driver_assert_string_slice(t, out.tags, []string{"ash", "odin", "zig"}) // Sorted_Set ascending order

	// Verify `pull` range slicing `[1..3]` on both Array_List (`items`) and Linked_Array_List (`queue`)
	pulled, p_err := xitdb.pull(rep.after.cursor, "{.rec{items[1..3], queue[1..3], meta{created_by}}}", context.temp_allocator)
	testing.expect_value(t, p_err, nil)
	rec_pv, _ := xitdb.pull_get(pulled, "rec")

	items_pv, _ := xitdb.pull_get(rec_pv, "items")
	items_list := items_pv.(xitdb.Pull_List)
	testing.expect_value(t, len(items_list), 2)
	testing.expect_value(t, items_list[0].(string), "a1")
	testing.expect_value(t, items_list[1].(string), "a2")

	queue_pv, _ := xitdb.pull_get(rec_pv, "queue")
	queue_list := queue_pv.(xitdb.Pull_List)
	testing.expect_value(t, len(queue_list), 2)
	testing.expect_value(t, queue_list[0].(string), "q1")
	testing.expect_value(t, queue_list[1].(string), "q2")
}

@(test)
unit_user_dsl_diff_moments_history_of_and_btree_queries :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// Moment 0: seed catalog Sorted_Map and initial config
	_, _ = xitdb.transact_script(&db, `
		branch none {
			doc "M0 seed"
			put .config.theme = "dark"
			put .config.font  = "mono"
			put $idx["alice"] = "u1"
			put $idx["bob"]   = "u2"
			put $idx["dan"]   = "u3"
			put $idx["dave"]  = "u4"
			put $idx["sarah"] = "u5"
			append .log       = "e1"
			append .log       = "e2"
		}
	`)

	// Moment 1: mutate unrelated key (.other = "val"); .config.theme does NOT change
	_, _ = xitdb.transact_script(&db, `
		branch @0 {
			doc "M1 unrelated"
			put .other = "val"
		}
	`)

	// Moment 2: mutate .config.theme, remove .config.font, and slice .log to 1 element
	rep2, _ := xitdb.transact_script(&db, `
		branch @1 {
			doc "M2 update theme, drop font, slice log"
			put .config.theme = "light"
			rm .config.font
			slice .log 1
		}
	`)

	// 1. `history_of` on `.config.theme` skips Moment 1 in O(1) and only reports Moment 0 and Moment 2
	hist, h_err := xitdb.history_of(&db, ".config.theme", context.temp_allocator)
	testing.expect_value(t, h_err, nil)
	testing.expect_value(t, len(hist), 2)
	testing.expect_value(t, hist[0].moment_index, i64(0))
	testing.expect_value(t, hist[0].tx_doc, "M0 seed")
	testing.expect_value(t, hist[1].moment_index, i64(2))
	testing.expect_value(t, hist[1].tx_doc, "M2 update theme, drop font, slice log")

	// 2. `diff_moments` between @1 and @2 detects Put (.config.theme), Remove (.config.font), and Slice (.log)
	diffs, d_err := xitdb.diff_moments(&db, 1, 2, false, context.temp_allocator)
	testing.expect_value(t, d_err, nil)
	testing.expect_value(t, len(diffs), 3)

	// 3. Secondary index helpers: `query_prefix`, `query_page`, and `query_count_range`
	prefix_hits, _ := xitdb.query_prefix(rep2.after, "idx", "da", context.temp_allocator)
	testing.expect_value(t, len(prefix_hits), 2)
	testing.expect_value(t, prefix_hits[0].key, "dan")
	testing.expect_value(t, prefix_hits[1].key, "dave")

	page_hits, _ := xitdb.query_page(rep2.after, "idx", offset = 1, limit = 3, allocator = context.temp_allocator)
	testing.expect_value(t, len(page_hits), 3)
	testing.expect_value(t, page_hits[0].key, "bob")
	testing.expect_value(t, page_hits[1].key, "dan")
	testing.expect_value(t, page_hits[2].key, "dave")

	range_cnt, _ := xitdb.query_count_range(rep2.after, "idx", "b", "s")
	testing.expect_value(t, range_cnt, i64(3)) // "bob", "dan", "dave"
}

@(test)
unit_user_dsl_datalog_predicates_pushdown_aggregations_and_reach :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	_, _ = xitdb.transact_script(&db, `
		branch none {
			put $directory["alice"] = "1"
			put $directory["bob"]   = "2"
			put $directory["dan"]   = "3"
			put $directory["dave"]  = "4"

			put .emp["1"].bio   = "systems architect"
			put .emp["1"].bonus = 1500.5
			put .emp["2"].bio   = "ui designer"
			put .emp["2"].bonus = 500.25
			put .emp["3"].bio   = "database engineer"
			put .emp["3"].bonus = 2000.0
			put .emp["4"].bio   = "distributed systems"
			put .emp["4"].bonus = 1250.25

			put .graph["n1"]^"n2" = "n2"
			put .graph["n2"]^"n3" = "n3"
			put .graph["n3"]^"n4" = "n4"
		}
	`)

	// 1. Lower-bound B+Tree pushdown (`?name >= "c"`), `contains(?bio, "systems")`, and `!=` predicate
	res1, err1 := xitdb.query_datalog(&db, `
		find ?name, ?id
		where
			$directory[?name] = ?id
			?name >= "c"
			?name != "dan"
			.emp[?id].bio = ?bio
			contains(?bio, "systems")
	`)
	testing.expect_value(t, err1, nil)
	names1 := xitdb.datalog_column_strings(res1, "?name")
	driver_assert_string_slice(t, names1, []string{"dave"})

	// 2. Float aggregation (`sum`, `min`, `max`) + empty-result global aggregation returning 0
	agg_res, err2 := xitdb.query_datalog(&db, `
		find count(?id), min(?b), max(?b), sum(?b)
		where
			.emp[?id].bonus = ?b
	`)
	testing.expect_value(t, err2, nil)
	testing.expect_value(t, len(agg_res.rows), 1)
	cnt_v, _ := xitdb.datalog_row_get(agg_res, 0, "count(?id)")
	min_v, _ := xitdb.datalog_row_get(agg_res, 0, "min(?b)")
	max_v, _ := xitdb.datalog_row_get(agg_res, 0, "max(?b)")
	sum_v, _ := xitdb.datalog_row_get(agg_res, 0, "sum(?b)")
	testing.expect_value(t, cnt_v.(u64), u64(4))
	testing.expect_value(t, min_v.(f64), f64(500.25))
	testing.expect_value(t, max_v.(f64), f64(2000.0))
	testing.expect_value(t, sum_v.(f64), f64(5251.0))

	empty_agg, err3 := xitdb.query_datalog(&db, `
		find count(?id), sum(?b)
		where
			.emp[?id].bonus = ?b
			?b > 999999.0
	`)
	testing.expect_value(t, err3, nil)
	testing.expect_value(t, len(empty_agg.rows), 1)
	zero_cnt, _ := xitdb.datalog_row_get(empty_agg, 0, "count(?id)")
	zero_sum, _ := xitdb.datalog_row_get(empty_agg, 0, "sum(?b)")
	testing.expect_value(t, zero_cnt.(u64), u64(0))
	testing.expect_value(t, zero_sum.(u64), u64(0))

	// 3. `reach` with pre-bound hop depth (`?hops == 2u`) and all-pairs unbound source
	hop2_res, err4 := xitdb.query_datalog(&db, `
		find ?src, ?dst
		where
			?hops == 2u
			reach(?src, ?dst, ?hops, .graph[?src]^?dst)
	`)
	testing.expect_value(t, err4, nil)
	testing.expect_value(t, len(hop2_res.rows), 2) // (n1 -> n3) and (n2 -> n4)
	srcs := xitdb.datalog_column_strings(hop2_res, "?src")
	dsts := xitdb.datalog_column_strings(hop2_res, "?dst")
	driver_assert_string_slice(t, srcs, []string{"n1", "n2"})
	driver_assert_string_slice(t, dsts, []string{"n3", "n4"})
}
