package xitdb_tests

import "base:runtime"
import "core:slice"
import "core:strings"
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

@(test)
unit_user_dsl_secondary_index_stale_key_eviction_and_heap_allocator_cleanup :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// 1. Seed users with `tx_index_on` using explicit `context.allocator` (checked for leaks by `odin test`)
	{
		tx0 := xitdb.tx_init(&db, base_moment = nil, track_changes = true, allocator = context.allocator)
		defer xitdb.tx_destroy(&tx0)

		xitdb.tx_doc(&tx0, "Seed users with explicit heap allocator")
		xitdb.tx_index_on(&tx0, "users", "username", "username->id")
		_ = xitdb.tx_put(&tx0, ".users[\"101\"].username", "dan")
		_ = xitdb.tx_put(&tx0, ".users[\"102\"].username", "dave")

		rep0, err0 := xitdb.tx_commit(&tx0)
		defer xitdb.tx_report_destroy(&rep0, context.allocator)
		testing.expect_value(t, err0, nil)
		testing.expect_value(t, len(rep0.changes), 2)
	}

	// 2. Rename "dan" -> "daniel" and remove user "102" ("dave")
	{
		tx1 := xitdb.tx_init(&db, base_moment = -1, track_changes = true, allocator = context.allocator)
		defer xitdb.tx_destroy(&tx1)

		xitdb.tx_doc(&tx1, "Rename dan to daniel and delete user 102")
		xitdb.tx_index_on(&tx1, "users", "username", "username->id")
		_ = xitdb.tx_put(&tx1, ".users[\"101\"].username", "daniel")
		_ = xitdb.tx_rm(&tx1, ".users[\"102\"]")

		rep1, err1 := xitdb.tx_commit(&tx1)
		defer xitdb.tx_report_destroy(&rep1, context.allocator)
		testing.expect_value(t, err1, nil)

		// Verify stale keys "dan" and "dave" were evicted from `$username->id` and only "daniel" -> "101" remains
		hits, q_err := xitdb.query_prefix(rep1.after, "username->id", "da", context.temp_allocator)
		testing.expect_value(t, q_err, nil)
		testing.expect_value(t, len(hits), 1)
		testing.expect_value(t, hits[0].key, "daniel")

		old_dan, _ := xitdb.select_cursor(&db, "@1$username->id[\"dan\"]")
		old_dave, _ := xitdb.select_cursor(&db, "@1$username->id[\"dave\"]")
		testing.expect(t, old_dan == nil, "Expected stale key 'dan' to be evicted from secondary index")
		testing.expect(t, old_dave == nil, "Expected deleted user key 'dave' to be evicted from secondary index")
	}
}

@(test)
unit_user_dsl_cyclic_graph_pull_and_diff_safety :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// Moment 0: baseline moment
	tx0 := xitdb.tx_init(&db, base_moment = nil)
	_ = xitdb.tx_put(&tx0, ".title", "baseline")
	_, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)

	// Moment 1: introduce cyclic self-reference, cyclic Array_List, and mutually recursive maps
	// while `track_changes = true` is enabled (which runs `diff_cursors` at commit time)
	tx1 := xitdb.tx_init(&db, base_moment = 0, track_changes = true)
	xitdb.tx_doc(&tx1, "Introduce cyclic slots")
	xitdb.tx_with_cursor(&tx1, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		m_slot := xitdb.hash_map_slot(moment.read_hash_map) or_return
		xitdb.hash_map_put(&moment, "self", m_slot) or_return

		cl_cur := xitdb.hash_map_put_cursor(&moment, "cyclic_list") or_return
		cl := xitdb.write_array_list_init(cl_cur) or_return
		cl_slot := xitdb.array_list_slot(cl.read_array_list) or_return
		xitdb.array_list_append(&cl, cl_slot) or_return

		ma_cur := xitdb.hash_map_put_cursor(&moment, "map_a") or_return
		ma := xitdb.write_hash_map_init(ma_cur) or_return
		xitdb.hash_map_put(&ma, "name", "Node A") or_return

		mb_cur := xitdb.hash_map_put_cursor(&moment, "map_b") or_return
		mb := xitdb.write_hash_map_init(mb_cur) or_return
		xitdb.hash_map_put(&mb, "name", "Node B") or_return

		mb_slot := xitdb.hash_map_slot(mb.read_hash_map) or_return
		xitdb.hash_map_put(&ma, "peer", mb_slot) or_return

		ma_slot := xitdb.hash_map_slot(ma.read_hash_map) or_return
		xitdb.hash_map_put(&mb, "peer", ma_slot) or_return
		return nil
	})

	rep1, err1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, err1, nil)
	testing.expect(t, len(rep1.changes) > 0, "Expected cyclic commit to record changes without infinite recursion")

	// 1. Wildcard `pull(rep1.after.cursor, "*")` terminates cleanly and breaks cycles with `nil`
	pulled, p_err := xitdb.pull(rep1.after.cursor, "*", context.temp_allocator)
	testing.expect_value(t, p_err, nil)
	title_pv, has_title := xitdb.pull_get(pulled, "title")
	testing.expect(t, has_title, "Expected title in pulled cyclic moment")
	testing.expect_value(t, title_pv.(string), "baseline")

	self_pv, has_self := xitdb.pull_get(pulled, "self")
	testing.expect(t, has_self, "Expected self key in pulled map")
	testing.expect(t, self_pv == nil, "Expected cyclic self back-reference to resolve to nil")

	// 2. Moment 2: branch from cyclic Moment 1, mutate a scalar, and run `diff_moments(&db, 1, 2)`
	tx2 := xitdb.tx_init(&db, base_moment = 1, track_changes = true)
	_ = xitdb.tx_put(&tx2, ".title", "updated-with-cycles-present")
	_, err2 := xitdb.tx_commit(&tx2)
	testing.expect_value(t, err2, nil)

	diffs, d_err := xitdb.diff_moments(&db, 1, 2, false, context.temp_allocator)
	testing.expect_value(t, d_err, nil)
	testing.expect_value(t, len(diffs), 1)
	testing.expect_value(t, diffs[0].path_str, ".title")
}

@(test)
unit_user_dsl_deep_recursive_pull_and_diff_small_stack_safety :: proc(t: ^testing.T) {
	MIXED_DEPTH :: 40
	RANGE_DEPTH :: 60

	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	// Moment 0: iteratively construct a 40-level mixed-collection spine (`chain`),
	// a 60-level range-slice spine (`range_chain`), and top-level lists/scalar.
	// `track_changes = true` on genesis also covers `_diff_recursive`'s `.None -> map/list` branches.
	tx0 := xitdb.tx_init(&db, base_moment = nil, track_changes = true, allocator = context.allocator)
	defer xitdb.tx_destroy(&tx0)
	xitdb.tx_with_cursor(&tx0, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&moment, "scalar", u64(7)) or_return

		top_al_cur := xitdb.hash_map_put_cursor(&moment, "top_al") or_return
		top_al := xitdb.write_array_list_init(top_al_cur) or_return
		xitdb.array_list_append(&top_al, "a0") or_return
		xitdb.array_list_append(&top_al, "a1") or_return

		top_ll_cur := xitdb.hash_map_put_cursor(&moment, "top_ll") or_return
		top_ll := xitdb.write_linked_array_list_init(top_ll_cur) or_return
		xitdb.linked_array_list_append(&top_ll, "l0") or_return
		xitdb.linked_array_list_append(&top_ll, "l1") or_return

		cur := xitdb.hash_map_put_cursor(&moment, "chain") or_return
		for level in 0 ..< MIXED_DEPTH {
			switch level % 5 {
			case 0:
				hm := xitdb.write_hash_map_init(cur) or_return
				xitdb.hash_map_put(&hm, "keep", "ok") or_return
				if level == 0 {
					xitdb.hash_map_put(&hm, "drop", "bye") or_return
				}
				cur = xitdb.hash_map_put_cursor(&hm, "next") or_return
			case 1:
				chm := xitdb.write_counted_hash_map_init(cur) or_return
				xitdb.hash_map_put(&chm, "keep", "ok") or_return
				cur = xitdb.hash_map_put_cursor(&chm.write_hash_map, "next") or_return
			case 2:
				sm := xitdb.write_sorted_map_init(cur) or_return
				xitdb.sorted_map_put(&sm, "a_keep", "ok") or_return
				if level == 2 {
					xitdb.sorted_map_put(&sm, "z_drop", "bye") or_return
				}
				cur = xitdb.sorted_map_put_cursor(&sm, "m_next") or_return
			case 3:
				al := xitdb.write_array_list_init(cur) or_return
				xitdb.array_list_append(&al, "pad") or_return
				cur = xitdb.array_list_append_cursor(&al) or_return
			case 4:
				ll := xitdb.write_linked_array_list_init(cur) or_return
				xitdb.linked_array_list_append(&ll, "pad") or_return
				cur = xitdb.linked_array_list_append_cursor(&ll) or_return
			}
		}

		leaf_hm := xitdb.write_hash_map_init(cur) or_return
		xitdb.hash_map_put(&leaf_hm, "leaf", "v1") or_return
		hs_cur := xitdb.hash_map_put_cursor(&leaf_hm, "hs") or_return
		hs := xitdb.write_hash_set_init(hs_cur) or_return
		xitdb.hash_set_put(&hs, "t1") or_return
		xitdb.hash_set_put(&hs, "t2") or_return
		chs_cur := xitdb.hash_map_put_cursor(&leaf_hm, "chs") or_return
		chs := xitdb.write_counted_hash_set_init(chs_cur) or_return
		xitdb.hash_set_put(&chs, "t1") or_return
		xitdb.hash_set_put(&chs, "t2") or_return
		ss_cur := xitdb.hash_map_put_cursor(&leaf_hm, "ss") or_return
		ss := xitdb.write_sorted_set_init(ss_cur) or_return
		xitdb.sorted_set_put(&ss, "t1") or_return
		xitdb.sorted_set_put(&ss, "t2") or_return

		rcur := xitdb.hash_map_put_cursor(&moment, "range_chain") or_return
		for level in 0 ..< RANGE_DEPTH {
			hm := xitdb.write_hash_map_init(rcur) or_return
			items_cur := xitdb.hash_map_put_cursor(&hm, "items") or_return
			if level % 2 == 0 {
				al := xitdb.write_array_list_init(items_cur) or_return
				xitdb.array_list_append(&al, "skip") or_return
				xitdb.array_list_append(&al, xitdb.Slot{}) or_return
				xitdb.array_list_append(&al, "tail") or_return
				rcur = xitdb.array_list_put_cursor(&al, 1) or_return
			} else {
				ll := xitdb.write_linked_array_list_init(items_cur) or_return
				xitdb.linked_array_list_append(&ll, "skip") or_return
				xitdb.linked_array_list_append(&ll, xitdb.Slot{}) or_return
				xitdb.linked_array_list_append(&ll, "tail") or_return
				rcur = xitdb.linked_array_list_put_cursor(&ll, 1) or_return
			}
		}
		range_leaf := xitdb.write_hash_map_init(rcur) or_return
		xitdb.hash_map_put(&range_leaf, "leaf", "range-bottom") or_return
		return nil
	})
	rep0, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)
	defer xitdb.tx_report_destroy(&rep0, context.allocator)

	// Moment 1: branch from Moment 0 and mutate top-level nodes + the 40-level leaf
	tx1 := xitdb.tx_init(&db, base_moment = 0, allocator = context.allocator)
	defer xitdb.tx_destroy(&tx1)
	xitdb.tx_with_cursor(&tx1, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		cur := xitdb.hash_map_put_cursor(&moment, "chain") or_return
		for level in 0 ..< MIXED_DEPTH {
			switch level % 5 {
			case 0:
				hm := xitdb.write_hash_map_init(cur) or_return
				if level == 0 {
					_ = xitdb.hash_map_remove(&hm, "drop") or_return
					xitdb.hash_map_put(&hm, "added", "new_hm") or_return
				}
				cur = xitdb.hash_map_put_cursor(&hm, "next") or_return
			case 1:
				chm := xitdb.write_counted_hash_map_init(cur) or_return
				cur = xitdb.hash_map_put_cursor(&chm.write_hash_map, "next") or_return
			case 2:
				sm := xitdb.write_sorted_map_init(cur) or_return
				if level == 2 {
					_ = xitdb.sorted_map_remove(&sm, "z_drop") or_return
					xitdb.sorted_map_put(&sm, "z_added", "new_sm") or_return
				}
				cur = xitdb.sorted_map_put_cursor(&sm, "m_next") or_return
			case 3:
				al := xitdb.write_array_list_init(cur) or_return
				if level == 3 {
					xitdb.array_list_append(&al, "appended_al") or_return
				}
				cur = xitdb.array_list_put_cursor(&al, 1) or_return
			case 4:
				ll := xitdb.write_linked_array_list_init(cur) or_return
				if level == 4 {
					xitdb.linked_array_list_append(&ll, "appended_ll") or_return
				}
				cur = xitdb.linked_array_list_put_cursor(&ll, 1) or_return
			}
		}
		leaf_hm := xitdb.write_hash_map_init(cur) or_return
		xitdb.hash_map_put(&leaf_hm, "leaf", "v2") or_return
		return nil
	})
	rep1, err1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, err1, nil)
	defer xitdb.tx_report_destroy(&rep1, context.allocator)

	chain_m1_maybe, cm1_err := xitdb.select_cursor(&db, "@1.chain")
	testing.expect_value(t, cm1_err, nil)
	chain_m1_cur, has_cm1 := chain_m1_maybe.?
	testing.expect(t, has_cm1, "Expected @1.chain cursor")

	range_cur_maybe, rc_err := xitdb.select_cursor(&db, "@1.range_chain")
	testing.expect_value(t, rc_err, nil)
	range_root_cur, has_rc := range_cur_maybe.?
	testing.expect(t, has_rc, "Expected @1.range_chain cursor")

	if !has_cm1 || !has_rc {
		return
	}

	pb := strings.builder_make(0, RANGE_DEPTH * 16 + 16, context.allocator)
	defer strings.builder_destroy(&pb)
	for _ in 0 ..< RANGE_DEPTH {
		strings.write_string(&pb, "{.items[1..2]")
	}
	strings.write_string(&pb, "{leaf}")
	for _ in 0 ..< RANGE_DEPTH {
		strings.write_byte(&pb, '}')
	}

	Worker_Args :: struct {
		t:              ^testing.T,
		db:             ^xitdb.Database,
		m0_root:        xitdb.Read_Cursor,
		chain_m1_cur:   xitdb.Read_Cursor,
		range_root_cur: xitdb.Read_Cursor,
		range_pattern:  string,
	}

	args := Worker_Args{
		t              = t,
		db             = &db,
		m0_root        = rep0.after.cursor,
		chain_m1_cur   = chain_m1_cur,
		range_root_cur = range_root_cur,
		range_pattern  = strings.to_string(pb),
	}

	worker :: proc(raw: rawptr) {
		defer free_all(context.temp_allocator)
		a := (^Worker_Args)(raw)

		has_change :: proc(diffs: []xitdb.Tx_Change, op: xitdb.Tx_Op_Kind, path: string) -> bool {
			for d in diffs {
				if d.op == op && d.path_str == path {
					return true
				}
			}
			return false
		}

		// 1. Forward deep structural diff across 40 levels
		diffs_fwd, df_err := xitdb.diff_moments(a.db, 0, 1, false, context.allocator)
		defer xitdb.diff_changes_destroy(diffs_fwd, context.allocator)
		testing.expect_value(a.t, df_err, nil)
		testing.expect_value(a.t, len(diffs_fwd), 7)
		testing.expect(a.t, has_change(diffs_fwd, .Remove, ".chain.drop"), "Expected .chain.drop removal")
		testing.expect(a.t, has_change(diffs_fwd, .Put,    ".chain.added"), "Expected .chain.added put")
		testing.expect(a.t, has_change(diffs_fwd, .Remove, ".chain.next#next$z_drop"), "Expected .chain.next#next$z_drop removal")
		testing.expect(a.t, has_change(diffs_fwd, .Put,    ".chain.next#next$z_added"), "Expected .chain.next#next$z_added put")
		testing.expect(a.t, has_change(diffs_fwd, .Append, ".chain.next#next$m_next[2]"), "Expected Array_List append diff")
		testing.expect(a.t, has_change(diffs_fwd, .Append, ".chain.next#next$m_next[1][[2]]"), "Expected Linked_Array_List append diff")

		found_leaf_fwd := false
		for d in diffs_fwd {
			if d.op == .Put && strings.has_suffix(d.path_str, ".leaf") && len(d.path_str) > MIXED_DEPTH {
				found_leaf_fwd = true
				break
			}
		}
		testing.expect(a.t, found_leaf_fwd, "Expected 40-level leaf Put diff")

		// 2. Reverse deep structural diff across 40 levels (exercises .Slice path)
		diffs_rev, dr_err := xitdb.diff_moments(a.db, 1, 0, false, context.allocator)
		defer xitdb.diff_changes_destroy(diffs_rev, context.allocator)
		testing.expect_value(a.t, dr_err, nil)
		testing.expect_value(a.t, len(diffs_rev), 7)
		testing.expect(a.t, has_change(diffs_rev, .Slice, ".chain.next#next$m_next"), "Expected Array_List Slice in reverse diff")
		testing.expect(a.t, has_change(diffs_rev, .Slice, ".chain.next#next$m_next[1]"), "Expected Linked_Array_List Slice in reverse diff")

		// 3. Deep recursive wildcard pull across 40 levels of all collection families
		pv, p_err := xitdb.pull(a.chain_m1_cur, "*", context.allocator)
		defer xitdb.pull_value_destroy(pv, context.allocator)
		testing.expect_value(a.t, p_err, nil)

		cur_pv := pv
		for level in 0 ..< MIXED_DEPTH {
			switch level % 5 {
			case 0, 1:
				next_pv, ok := xitdb.pull_get(cur_pv, "next")
				testing.expectf(a.t, ok, "Missing 'next' at wildcard level %d", level)
				if !ok {
					return
				}
				cur_pv = next_pv
			case 2:
				next_pv, ok := xitdb.pull_get(cur_pv, "m_next")
				testing.expectf(a.t, ok, "Missing 'm_next' at wildcard level %d", level)
				if !ok {
					return
				}
				cur_pv = next_pv
			case 3, 4:
				list_pv, is_list := cur_pv.(xitdb.Pull_List)
				testing.expectf(a.t, is_list && len(list_pv) >= 2, "Expected Pull_List >= 2 at wildcard level %d", level)
				if !is_list || len(list_pv) < 2 {
					return
				}
				cur_pv = list_pv[1]
			}
		}
		leaf_pv, has_leaf := xitdb.pull_get(cur_pv, "leaf")
		testing.expect(a.t, has_leaf, "Missing leaf value in deep wildcard pull")
		if has_leaf {
			leaf_str, is_str := leaf_pv.(string)
			testing.expect(a.t, is_str, "Expected string at deep wildcard leaf")
			if is_str {
				testing.expect_value(a.t, leaf_str, "v2")
			}
		}
		for set_key in ([?]string{"hs", "chs", "ss"}) {
			set_pv, has_set := xitdb.pull_get(cur_pv, set_key)
			testing.expectf(a.t, has_set, "Missing set %s at leaf", set_key)
			if has_set {
				set_list, is_list := set_pv.(xitdb.Pull_List)
				testing.expectf(a.t, is_list && len(set_list) == 2, "Expected 2 elements in leaf set %s", set_key)
			}
		}

		// 4. Deep recursive range pull across 60 levels of alternating Array_List / Linked_Array_List
		rpv, rp_err := xitdb.pull(a.range_root_cur, a.range_pattern, context.allocator)
		defer xitdb.pull_value_destroy(rpv, context.allocator)
		testing.expect_value(a.t, rp_err, nil)

		cur_rpv := rpv
		for level in 0 ..< RANGE_DEPTH {
			items_pv, ok := xitdb.pull_get(cur_rpv, "items")
			testing.expectf(a.t, ok, "Missing 'items' at range level %d", level)
			if !ok {
				return
			}
			items_list, is_list := items_pv.(xitdb.Pull_List)
			testing.expectf(a.t, is_list && len(items_list) == 1, "Expected 1 sliced item at range level %d", level)
			if !is_list || len(items_list) != 1 {
				return
			}
			cur_rpv = items_list[0]
		}
		rleaf_pv, has_rleaf := xitdb.pull_get(cur_rpv, "leaf")
		testing.expect(a.t, has_rleaf, "Missing leaf in deep range pull")
		if has_rleaf {
			rleaf_str, is_str := rleaf_pv.(string)
			testing.expect(a.t, is_str, "Expected string at deep range leaf")
			if is_str {
				testing.expect_value(a.t, rleaf_str, "range-bottom")
			}
		}

		// 5. _pull_range edge & error-path leak checks under persistent allocator
		oob_pv, oob_err := xitdb.pull(a.range_root_cur, "{.items[99..105]}", context.allocator)
		defer xitdb.pull_value_destroy(oob_pv, context.allocator)
		testing.expect_value(a.t, oob_err, nil)
		if oob_items, ok := xitdb.pull_get(oob_pv, "items"); ok {
			oob_list, is_list := oob_items.(xitdb.Pull_List)
			testing.expect(a.t, is_list && len(oob_list) == 0, "Expected empty Pull_List for out-of-range slice")
		}

		rev_pv, rev_err := xitdb.pull(a.range_root_cur, "{.items[2..1]}", context.allocator)
		defer xitdb.pull_value_destroy(rev_pv, context.allocator)
		testing.expect_value(a.t, rev_err, nil)
		if rev_items, ok := xitdb.pull_get(rev_pv, "items"); ok {
			rev_list, is_list := rev_items.(xitdb.Pull_List)
			testing.expect(a.t, is_list && len(rev_list) == 0, "Expected empty Pull_List for reversed range slice")
		}

		neg_pv, neg_err := xitdb.pull(a.range_root_cur, "{.items[-1..2]}", context.allocator)
		defer xitdb.pull_value_destroy(neg_pv, context.allocator)
		testing.expect_value(a.t, neg_err, xitdb.Xitdb_Error.Invalid_Range)

		bad_pv, bad_err := xitdb.pull(a.m0_root, "{.scalar[0..1]}", context.allocator)
		defer xitdb.pull_value_destroy(bad_pv, context.allocator)
		testing.expect_value(a.t, bad_err, xitdb.Xitdb_Error.Unexpected_Tag)
	}

	_run_on_small_stack(t, 512 * 1024, worker, &args)
}

@(test)
unit_user_dsl_iterator_pool_oom_and_range_edge_guards :: proc(t: ^testing.T) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	// Moment 0: scalar, map, list, and empty instances of all collection families
	tx0 := xitdb.tx_init(&db, base_moment = nil, allocator = context.allocator)
	defer xitdb.tx_destroy(&tx0)
	xitdb.tx_with_cursor(&tx0, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&moment, "scalar", u64(7)) or_return

		m_cur := xitdb.hash_map_put_cursor(&moment, "map") or_return
		m := xitdb.write_hash_map_init(m_cur) or_return
		xitdb.hash_map_put(&m, "a", "1") or_return

		items_cur := xitdb.hash_map_put_cursor(&moment, "items") or_return
		items := xitdb.write_array_list_init(items_cur) or_return
		xitdb.array_list_append(&items, "x") or_return
		xitdb.array_list_append(&items, "y") or_return

		eal_cur := xitdb.hash_map_put_cursor(&moment, "empty_al") or_return
		_ = xitdb.write_array_list_init(eal_cur) or_return
		ell_cur := xitdb.hash_map_put_cursor(&moment, "empty_ll") or_return
		_ = xitdb.write_linked_array_list_init(ell_cur) or_return
		ehm_cur := xitdb.hash_map_put_cursor(&moment, "empty_hm") or_return
		_ = xitdb.write_hash_map_init(ehm_cur) or_return
		esm_cur := xitdb.hash_map_put_cursor(&moment, "empty_sm") or_return
		_ = xitdb.write_sorted_map_init(esm_cur) or_return
		ehs_cur := xitdb.hash_map_put_cursor(&moment, "empty_hs") or_return
		_ = xitdb.write_hash_set_init(ehs_cur) or_return
		return nil
	})
	rep0, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)
	defer xitdb.tx_report_destroy(&rep0, context.allocator)

	// Moment 1: update/add keys and append an item so diff_moments has changes
	tx1 := xitdb.tx_init(&db, base_moment = 0, allocator = context.allocator)
	defer xitdb.tx_destroy(&tx1)
	_ = xitdb.tx_put(&tx1, ".map.a", "2")
	_ = xitdb.tx_put(&tx1, ".map.b", "3")
	_ = xitdb.tx_append(&tx1, ".items", "z")
	rep1, err1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, err1, nil)
	defer xitdb.tx_report_destroy(&rep1, context.allocator)

	m1_cur := rep1.after.cursor
	items_cur_maybe, ic_err := xitdb.select_cursor(&db, "@1.items")
	testing.expect_value(t, ic_err, nil)
	items_cur, has_items := items_cur_maybe.?
	testing.expect(t, has_items, "Expected @1.items cursor")
	if !has_items {
		return
	}

	// 1. _pull_range rejects non-list targets even on zero-length or reversed ranges
	for pat in ([?]string{"{.scalar[0..0]}", "{.scalar[2..1]}", "{.map[0..0]}"}) {
		pv, err := xitdb.pull(m1_cur, pat, context.allocator)
		defer xitdb.pull_value_destroy(pv, context.allocator)
		testing.expect_value(t, err, xitdb.Xitdb_Error.Unexpected_Tag)
	}

	// 2. _pull_wildcard on empty collections returns zero-capacity nil slices without heap allocation
	for list_sel in ([?]string{"@0.empty_al", "@0.empty_ll", "@0.empty_hs"}) {
		cur_maybe, sel_err := xitdb.select_cursor(&db, list_sel)
		testing.expect_value(t, sel_err, nil)
		pv, p_err := xitdb.pull(cur_maybe.?, "*", context.allocator)
		defer xitdb.pull_value_destroy(pv, context.allocator)
		testing.expect_value(t, p_err, nil)
		pl, is_list := pv.(xitdb.Pull_List)
		testing.expectf(t, is_list, "Expected Pull_List for %s", list_sel)
		testing.expect_value(t, len(pl), 0)
		testing.expect(t, raw_data(pl) == nil, "Expected nil backing pointer for empty Pull_List")
	}
	for map_sel in ([?]string{"@0.empty_hm", "@0.empty_sm"}) {
		cur_maybe, sel_err := xitdb.select_cursor(&db, map_sel)
		testing.expect_value(t, sel_err, nil)
		pv, p_err := xitdb.pull(cur_maybe.?, "*", context.allocator)
		defer xitdb.pull_value_destroy(pv, context.allocator)
		testing.expect_value(t, p_err, nil)
		pm, is_map := pv.(xitdb.Pull_Map)
		testing.expectf(t, is_map, "Expected Pull_Map for %s", map_sel)
		testing.expect_value(t, len(pm), 0)
		testing.expect(t, raw_data(pm) == nil, "Expected nil backing pointer for empty Pull_Map")
	}

	// 3. OOM on implicit context.allocator (iterator pool / heap iterator) returns .Write_Failed cleanly
	prev_alloc := context.allocator
	defer context.allocator = prev_alloc

	context.allocator = runtime.nil_allocator()
	oom_pv_wild, oom_wild_err := xitdb.pull(m1_cur, "*", prev_alloc)
	context.allocator = prev_alloc
	defer xitdb.pull_value_destroy(oom_pv_wild, prev_alloc)
	testing.expect_value(t, oom_wild_err, xitdb.Xitdb_Error.Write_Failed)

	context.allocator = runtime.nil_allocator()
	oom_pv_range, oom_range_err := xitdb.pull(m1_cur, "{.items[0..2]}", prev_alloc)
	context.allocator = prev_alloc
	defer xitdb.pull_value_destroy(oom_pv_range, prev_alloc)
	testing.expect_value(t, oom_range_err, xitdb.Xitdb_Error.Write_Failed)

	context.allocator = runtime.nil_allocator()
	oom_diffs, oom_diff_err := xitdb.diff_moments(&db, 0, 1, false, prev_alloc)
	context.allocator = prev_alloc
	defer xitdb.diff_changes_destroy(oom_diffs, prev_alloc)
	testing.expect_value(t, oom_diff_err, xitdb.Xitdb_Error.Write_Failed)

	context.allocator = runtime.nil_allocator()
	oom_slice, oom_unm_err := xitdb.unmarshal([]string, items_cur, prev_alloc)
	context.allocator = prev_alloc
	defer if oom_slice != nil {
		for s in oom_slice {
			if len(s) > 0 {
				delete(s, prev_alloc)
			}
		}
		delete(oom_slice, prev_alloc)
	}
	testing.expect_value(t, oom_unm_err, xitdb.Xitdb_Error.Write_Failed)

	context.allocator = runtime.nil_allocator()
	oom_qres, oom_q_err := xitdb.query_datalog(&db, "find ?k where .map[?k] = ?v", -1, prev_alloc)
	context.allocator = prev_alloc
	defer {
		for row in oom_qres.rows {
			for cell in row {
				xitdb.pull_value_destroy(cell, prev_alloc)
			}
			delete(row, prev_alloc)
		}
		delete(oom_qres.rows, prev_alloc)
		delete(oom_qres.vars, prev_alloc)
	}
	testing.expect_value(t, oom_q_err, xitdb.Xitdb_Error.Write_Failed)

	// 4. OOM on explicit result allocator leaves zero leaks on context.allocator
	res_oom_wild, res_oom_wild_err := xitdb.pull(m1_cur, "*", runtime.nil_allocator())
	defer xitdb.pull_value_destroy(res_oom_wild, runtime.nil_allocator())
	testing.expect_value(t, res_oom_wild_err, xitdb.Xitdb_Error.Write_Failed)

	res_oom_range, res_oom_range_err := xitdb.pull(m1_cur, "{.items[0..2]}", runtime.nil_allocator())
	defer xitdb.pull_value_destroy(res_oom_range, runtime.nil_allocator())
	testing.expect_value(t, res_oom_range_err, xitdb.Xitdb_Error.Write_Failed)

	res_oom_diffs, res_oom_diff_err := xitdb.diff_moments(&db, 0, 1, false, runtime.nil_allocator())
	defer xitdb.diff_changes_destroy(res_oom_diffs, runtime.nil_allocator())
	testing.expect_value(t, res_oom_diff_err, xitdb.Xitdb_Error.Write_Failed)
}
