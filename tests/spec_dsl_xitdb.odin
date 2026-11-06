package xitdb_tests

import "core:testing"
import xitdb "../xitdb"

User_Profile_DTO :: struct {
	username: string   `xitdb:"username"`,
	age:      u64      `xitdb:"age"`,
	bio:      string   `xitdb:"bio,tag=md"`,
	todos:    []string `xitdb:"[[todos]]"`,
	tags:     []string `xitdb:"^tags"`,
}

@(test)
spec_datomic_tx_metadata_path_selectors_and_temporal_history :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// 1. Commit Moment 0 via Datomic-style Tx builder with doc, instant, metadata, and secondary index rule
	tx0 := xitdb.tx_init(&ctx.primary_db, base_moment = nil, track_changes = true)
	xitdb.tx_doc(&tx0, "Seed initial users and fruit inventory")
	xitdb.tx_instant(&tx0, 1700000000)
	xitdb.tx_meta(&tx0, "author", "paul")
	xitdb.tx_index_on(&tx0, "users", "username", "username->id")

	_ = xitdb.tx_put(&tx0, ".users[\"101\"].username", "dan")
	_ = xitdb.tx_put(&tx0, ".users[\"101\"].age", u64(25))
	_ = xitdb.tx_put(&tx0, ".users[\"102\"].username", "dave")
	_ = xitdb.tx_append(&tx0, ".fruits", "apple")
	_ = xitdb.tx_append(&tx0, ".fruits", "pear")

	rep0, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)
	testing.expect_value(t, rep0.moment_index, i64(0))
	testing.expect(t, len(rep0.changes) >= 4, "Expected recorded changes in Tx_Report")

	// 2. Commit Moment 1 via Declarative Script DSL (with fork + savepoint)
	rep1, err1 := xitdb.transact_script(&ctx.primary_db, `
		branch @-1 {
			doc "Promote dan, fork backup_fruits, and mutate live fruits"
			instant 1700000500
			meta "ticket" = "XIT-42"

			fork .fruits -> .backup_fruits
			savepoint
			put .users["101"].age = 26u
			put .fruits[0] = "lemon"
			append .fruits = "grape"
		}
	`)
	testing.expect_value(t, err1, nil)
	testing.expect_value(t, rep1.moment_index, i64(1))

	// 3. Query historical state & reified __tx metadata via String Selector DSL
	doc0, _ := xitdb.get_string(&ctx.primary_db, "@0.__tx.doc")
	author0, _ := xitdb.get_string(&ctx.primary_db, "@0.__tx.author")
	age0, _ := xitdb.get_uint(&ctx.primary_db, "@0.users[\"101\"].age")
	age1, _ := xitdb.get_uint(&ctx.primary_db, "@-1.users[\"101\"].age")
	ticket1, _ := xitdb.get_string(&ctx.primary_db, "@1.__tx.ticket")
	backup0, _ := xitdb.get_string(&ctx.primary_db, "@1.backup_fruits[0]")
	live0, _ := xitdb.get_string(&ctx.primary_db, "@1.fruits[0]")

	testing.expect_value(t, doc0, "Seed initial users and fruit inventory")
	testing.expect_value(t, author0, "paul")
	testing.expect_value(t, age0, u64(25))
	testing.expect_value(t, age1, u64(26))
	testing.expect_value(t, ticket1, "XIT-42")
	testing.expect_value(t, backup0, "apple") // isolated by `cursor_freeze`!
	testing.expect_value(t, live0, "lemon")

	// 4. Query secondary index prefix, page & O(log N) range count
	da_hits, _ := xitdb.query_prefix(rep1.after, "username->id", "da")
	testing.expect_value(t, len(da_hits), 2)
	testing.expect_value(t, da_hits[0].key, "dan")
	testing.expect_value(t, da_hits[1].key, "dave")

	page_hits, _ := xitdb.query_page(rep1.after, "username->id", 0, 1)
	testing.expect_value(t, len(page_hits), 1)
	testing.expect_value(t, page_hits[0].key, "dan")

	da_count, _ := xitdb.query_count_range(rep1.after, "username->id", "da", "dz")
	testing.expect_value(t, da_count, i64(2))

	// 5. Inspect temporal lineage (`history_of`) of `.users["101"].age` across moments
	age_history, h_err := xitdb.history_of(&ctx.primary_db, ".users[\"101\"].age")
	testing.expect_value(t, h_err, nil)
	testing.expect_value(t, len(age_history), 2)
	testing.expect_value(t, age_history[0].moment_index, i64(0))
	testing.expect_value(t, age_history[0].tx_doc, "Seed initial users and fruit inventory")
	testing.expect_value(t, age_history[1].moment_index, i64(1))
	testing.expect_value(t, age_history[1].tx_doc, "Promote dan, fork backup_fruits, and mutate live fruits")
}

@(test)
spec_struct_marshal_unmarshal_and_datomic_pull_projection :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	input_dto := User_Profile_DTO{
		username = "alice",
		age      = 31,
		bio      = "# Systems Engineer",
		todos    = {"Write Odin DSL", "Run ATDD suite"},
		tags     = {"zig", "odin", "clojure"},
	}

	// 1. Marshal native Odin struct with collection & format tags into Moment 0
	tx := xitdb.tx_init(&ctx.primary_db, base_moment = nil)
	xitdb.tx_with_cursor(&tx, proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		dto := (^User_Profile_DTO)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		p_cur := xitdb.hash_map_put_cursor(&m, "profile") or_return
		return xitdb.marshal(&p_cur, dto^)
	}, &input_dto)
	rep, err := xitdb.tx_commit(&tx)
	testing.expect_value(t, err, nil)

	// 2. Verify struct tags created a Tagged Bytes ("md"), Linked_Array_List ("todos"), and Sorted_Set ("tags")
	prof_cur_maybe, _ := xitdb.select_cursor(&ctx.primary_db, "@0.profile")
	prof_cur := prof_cur_maybe.?
	bio_cur_maybe, _ := xitdb.select_cursor(&ctx.primary_db, "@0.profile.bio")
	bio_obj, bio_err := xitdb.cursor_read_bytes_object(bio_cur_maybe.?, 0, context.temp_allocator)
	testing.expect_value(t, bio_err, nil)
	testing.expect_value(t, string(bio_obj.value), "# Systems Engineer")
	testing.expect_value(t, string(bio_obj.format_tag), "md")

	roundtrip, u_err := xitdb.unmarshal(User_Profile_DTO, prof_cur, context.temp_allocator)
	testing.expect_value(t, u_err, nil)
	testing.expect_value(t, roundtrip.username, "alice")
	testing.expect_value(t, roundtrip.age, u64(31))
	testing.expect_value(t, roundtrip.bio, "# Systems Engineer")
	driver_assert_string_slice(t, roundtrip.todos, []string{"Write Odin DSL", "Run ATDD suite"})
	// Sorted_Set (`^tags`) automatically yields sorted order on unmarshal!
	driver_assert_string_slice(t, roundtrip.tags, []string{"clojure", "odin", "zig"})

	// 3. Datomic-style `pull` with nested selection and range slicing `[0..1]`
	pulled, p_err := xitdb.pull(rep.after.cursor, "{.profile{username, age, todos[0..1]}}")
	testing.expect_value(t, p_err, nil)

	prof_val, has_prof := xitdb.pull_get(pulled, "profile")
	testing.expect(t, has_prof, "Expected profile in pull result")
	uname_val, _ := xitdb.pull_get(prof_val, "username")
	testing.expect_value(t, uname_val.(string), "alice")

	todos_val, _ := xitdb.pull_get(prof_val, "todos")
	todos_list := todos_val.(xitdb.Pull_List)
	testing.expect_value(t, len(todos_list), 1)
	testing.expect_value(t, todos_list[0].(string), "Write Odin DSL")
}

@(test)
spec_datalog_unification_across_btree_indexes_hash_maps_and_negated_sets :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// GIVEN 4 users indexed in `$username->id` with roles in a `Hash_Set` and ages in `.users`
	tx := xitdb.tx_init(&ctx.primary_db, base_moment = nil)
	xitdb.tx_doc(&tx, "Seed users with roles and secondary username index")
	xitdb.tx_index_on(&tx, "users", "username", "username->id")

	_ = xitdb.tx_put(&tx, ".users[\"101\"].username", "dan")
	_ = xitdb.tx_put(&tx, ".users[\"101\"].age", u64(28))
	_ = xitdb.tx_put(&tx, ".users[\"101\"].roles%\"admin\"", "admin")

	_ = xitdb.tx_put(&tx, ".users[\"102\"].username", "dave")
	_ = xitdb.tx_put(&tx, ".users[\"102\"].age", u64(34))
	_ = xitdb.tx_put(&tx, ".users[\"102\"].roles%\"editor\"", "editor")

	_ = xitdb.tx_put(&tx, ".users[\"103\"].username", "daria")
	_ = xitdb.tx_put(&tx, ".users[\"103\"].age", u64(30))
	_ = xitdb.tx_put(&tx, ".users[\"103\"].roles%\"suspended\"", "suspended")

	_ = xitdb.tx_put(&tx, ".users[\"104\"].username", "alice")
	_ = xitdb.tx_put(&tx, ".users[\"104\"].age", u64(40))
	_ = xitdb.tx_put(&tx, ".users[\"104\"].roles%\"admin\"", "admin")

	_, err := xitdb.tx_commit(&tx)
	testing.expect_value(t, err, nil)

	// UPON running a Datalog query that seeks prefix "da" on `$username->id`, joins `.users[?id]`,
	// filters `?age >= 28u`, and excludes suspended users via `not .users[?id].roles%"suspended"`
	res, q_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?id, ?name, ?age
		where
			$username->id[?name] = ?id
			starts_with(?name, "da")
			.users[?id].age = ?age
			?age >= 28u
			not .users[?id].roles%"suspended"
	`)
	testing.expect_value(t, q_err, nil)

	// THEN only "dan" (101) and "dave" (102) match in lexicographical index order ("daria" is excluded by `not`, "alice" by prefix)
	names := xitdb.datalog_column_strings(res, "?name")
	ids := xitdb.datalog_column_strings(res, "?id")
	driver_assert_string_slice(t, names, []string{"dan", "dave"})
	driver_assert_string_slice(t, ids, []string{"101", "102"})
}

@(test)
spec_temporal_datalog_unification_across_moments_and_tx_metadata :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// GIVEN 3 moments committed by different authors with evolving user ages
	_, _ = xitdb.transact_script(&ctx.primary_db, `
		branch none {
			doc "Initial seed by paul"
			meta "author" = "paul"
			put .users["101"].username = "dan"
			put .users["101"].age = 25u
			put .users["102"].username = "alice"
			put .users["102"].age = 30u
		}
	`)

	_, _ = xitdb.transact_script(&ctx.primary_db, `
		branch @-1 {
			doc "Automated background job"
			meta "author" = "bot"
			put .users["102"].age = 31u
		}
	`)

	_, _ = xitdb.transact_script(&ctx.primary_db, `
		branch @-1 {
			doc "Promote dan and increment age"
			meta "author" = "paul"
			put .users["101"].age = 26u
		}
	`)

	// 1. Query across all moments `@?m` to find commits authored by "paul" and their documentation
	audit_res, a_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?m, ?doc
		where
			@?m.__tx.author = "paul"
			@?m.__tx.doc = ?doc
	`)
	testing.expect_value(t, a_err, nil)
	testing.expect_value(t, len(audit_res.rows), 2)

	m0_val, _ := xitdb.datalog_row_get(audit_res, 0, "?m")
	m2_val, _ := xitdb.datalog_row_get(audit_res, 1, "?m")
	testing.expect_value(t, m0_val.(i64), i64(0))
	testing.expect_value(t, m2_val.(i64), i64(2))

	docs := xitdb.datalog_column_strings(audit_res, "?doc")
	driver_assert_string_slice(t, docs, []string{
		"Initial seed by paul",
		"Promote dan and increment age",
	})

	// 2. Temporal join between `@0` and `@2` to find users whose age increased
	diff_res, d_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?name, ?old_age, ?new_age
		where
			@0.users[?id].username = ?name
			@0.users[?id].age = ?old_age
			@2.users[?id].age = ?new_age
			?new_age > ?old_age
	`)
	testing.expect_value(t, d_err, nil)
	testing.expect_value(t, len(diff_res.rows), 2)
}

@(test)
spec_datalog_grouped_and_global_aggregations :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	_, err := xitdb.transact_script(&ctx.primary_db, `
		branch none {
			doc "Seed employees across engineering and design departments"
			put .users["101"].name = "dan"
			put .users["101"].dept = "eng"
			put .users["101"].age  = 28u

			put .users["102"].name = "alice"
			put .users["102"].dept = "eng"
			put .users["102"].age  = 40u

			put .users["103"].name = "dave"
			put .users["103"].dept = "eng"
			put .users["103"].age  = 34u

			put .users["104"].name = "sarah"
			put .users["104"].dept = "design"
			put .users["104"].age  = 31u

			put .users["105"].name = "bob"
			put .users["105"].dept = "design"
			put .users["105"].age  = 25u
		}
	`)
	testing.expect_value(t, err, nil)

	// 1. Grouped aggregations by `?dept`
	grouped_res, g_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?dept, count(?id), min(?age), max(?age), sum(?age)
		where
			.users[?id].dept = ?dept
			.users[?id].age = ?age
	`)
	testing.expect_value(t, g_err, nil)
	testing.expect_value(t, len(grouped_res.rows), 2)

	for r_idx in 0 ..< len(grouped_res.rows) {
		dept_val, _ := xitdb.datalog_row_get(grouped_res, r_idx, "?dept")
		cnt_val, _  := xitdb.datalog_row_get(grouped_res, r_idx, "count(?id)")
		min_val, _  := xitdb.datalog_row_get(grouped_res, r_idx, "min(?age)")
		max_val, _  := xitdb.datalog_row_get(grouped_res, r_idx, "max(?age)")
		sum_val, _  := xitdb.datalog_row_get(grouped_res, r_idx, "sum(?age)")

		if dept_val.(string) == "eng" {
			testing.expect_value(t, cnt_val.(u64), u64(3))
			testing.expect_value(t, min_val.(u64), u64(28))
			testing.expect_value(t, max_val.(u64), u64(40))
			testing.expect_value(t, sum_val.(u64), u64(102))
		} else {
			testing.expect_value(t, dept_val.(string), "design")
			testing.expect_value(t, cnt_val.(u64), u64(2))
			testing.expect_value(t, min_val.(u64), u64(25))
			testing.expect_value(t, max_val.(u64), u64(31))
			testing.expect_value(t, sum_val.(u64), u64(56))
		}
	}

	// 2. Global aggregations across all matching records
	global_res, gl_err := xitdb.query_datalog(&ctx.primary_db, `
		find count(?id), min(?age), max(?age), sum(?age)
		where
			.users[?id].age = ?age
	`)
	testing.expect_value(t, gl_err, nil)
	testing.expect_value(t, len(global_res.rows), 1)

	total_cnt, _ := xitdb.datalog_row_get(global_res, 0, "count(?id)")
	total_sum, _ := xitdb.datalog_row_get(global_res, 0, "sum(?age)")
	testing.expect_value(t, total_cnt.(u64), u64(5))
	testing.expect_value(t, total_sum.(u64), u64(158))
}

@(test)
spec_datalog_transitive_reach_and_cycle_safe_graph_traversal :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// GIVEN an org hierarchy ("dan" -> "sarah" -> "alice" -> "cto")
	// AND a cyclic package dependency graph in Sorted_Sets ("app" -> "http" -> "net" -> "core" -> "http")
	_, err := xitdb.transact_script(&ctx.primary_db, `
		branch none {
			doc "Seed org hierarchy and cyclic package dependency graph"
			put .org["dan"].manager   = "sarah"
			put .org["sarah"].manager = "alice"
			put .org["alice"].manager = "cto"

			put .deps["app"]^"http"  = "http"
			put .deps["http"]^"net"  = "net"
			put .deps["net"]^"core"  = "core"
			put .deps["core"]^"http" = "http"
		}
	`)
	testing.expect_value(t, err, nil)

	// 1. Transitive management chain for "dan" with hop count `?hops`
	chain_res, c_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?ancestor, ?hops
		where
			?emp == "dan"
			reach(?emp, ?ancestor, ?hops, .org[?emp].manager = ?ancestor)
	`)
	testing.expect_value(t, c_err, nil)
	testing.expect_value(t, len(chain_res.rows), 3)

	ancestors := xitdb.datalog_column_strings(chain_res, "?ancestor")
	driver_assert_string_slice(t, ancestors, []string{"sarah", "alice", "cto"})

	h0, _ := xitdb.datalog_row_get(chain_res, 0, "?hops")
	h1, _ := xitdb.datalog_row_get(chain_res, 1, "?hops")
	h2, _ := xitdb.datalog_row_get(chain_res, 2, "?hops")
	testing.expect_value(t, h0.(u64), u64(1))
	testing.expect_value(t, h1.(u64), u64(2))
	testing.expect_value(t, h2.(u64), u64(3))

	// 2. Cycle-safe transitive closure from "app" over `.deps[?p]^?d` terminates cleanly in 3 unique dependencies
	deps_res, d_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?dep, ?hops
		where
			?pkg == "app"
			reach(?pkg, ?dep, ?hops, .deps[?pkg]^?dep)
	`)
	testing.expect_value(t, d_err, nil)
	testing.expect_value(t, len(deps_res.rows), 3)
	trans_deps := xitdb.datalog_column_strings(deps_res, "?dep")
	driver_assert_string_slice(t, trans_deps, []string{"http", "net", "core"})

	// 3. Detect packages that participate in a dependency cycle (`reach(?p, ?p, ...)`)
	cycle_res, cy_err := xitdb.query_datalog(&ctx.primary_db, `
		find ?p
		where
			reach(?p, ?d, .deps[?p]^?d)
			?p == ?d
	`)
	testing.expect_value(t, cy_err, nil)
	cyclic_pkgs := xitdb.datalog_column_strings(cycle_res, "?p")
	testing.expect_value(t, len(cyclic_pkgs), 3) // "http", "net", "core" (while "app" is not in the cycle!)
}

@(test)
spec_dsl_error_guards_savepoint_survival_and_counted_collections :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// 1. Malformed selectors, invalid 2-byte format tags, and bad Datalog syntax return clean errors
	_, sel_err1 := xitdb.parse_selector("@abc.users")
	testing.expect_value(t, sel_err1, xitdb.Xitdb_Error.Invalid_Range)

	_, sel_err2 := xitdb.parse_selector("@-1.users[\"unclosed]")
	testing.expect_value(t, sel_err2, xitdb.Xitdb_Error.Invalid_Range)

	_, sel_err3 := xitdb.parse_selector("@-1.todos[[0]")
	testing.expect_value(t, sel_err3, xitdb.Xitdb_Error.Invalid_Range)

	_, tag_err := xitdb.transact_script(&ctx.primary_db, `
		branch none {
			put .doc = "# Title"^^markdown
		}
	`)
	testing.expect_value(t, tag_err, xitdb.Xitdb_Error.Invalid_Format_Tag_Size)

	_, dlog_err := xitdb.parse_datalog("SELECT * FROM users")
	testing.expect_value(t, dlog_err, xitdb.Xitdb_Error.Invalid_Range)

	// 2. Counted_Hash_Map (#), Counted_Hash_Set (#%), and Linked_Array_List ([[i]]) insert/remove
	tx := xitdb.tx_init(&ctx.primary_db, base_moment = nil)
	_ = xitdb.tx_put(&tx, "#metrics[\"views\"]", u64(100))
	_ = xitdb.tx_put(&tx, "#metrics[\"clicks\"]", u64(25))
	_ = xitdb.tx_put(&tx, ".visitors#%\"u1\"", "u1")
	_ = xitdb.tx_put(&tx, ".visitors#%\"u2\"", "u2")
	_ = xitdb.tx_put(&tx, ".queue[[0]]", "first")
	_ = xitdb.tx_put(&tx, ".queue[[1]]", "third")
	_ = xitdb.tx_insert(&tx, ".queue", 1, "second")

	_, commit_err := xitdb.tx_commit(&tx)
	testing.expect_value(t, commit_err, nil)

	views, v_err := xitdb.get_uint(&ctx.primary_db, "@0#metrics[\"views\"]")
	testing.expect_value(t, v_err, nil)
	testing.expect_value(t, views, u64(100))

	then_moment_has_counted_map_size(&ctx, 0, "metrics", 2)
	then_moment_has_counted_set(&ctx, 0, "visitors", 2, []string{"u1", "u2"})
	then_moment_has_linked_list(&ctx, 0, "queue", []string{"first", "second", "third"})

	// Remove middle element from Linked_Array_List and 1 member from Counted_Hash_Set in Moment 1
	tx1 := xitdb.tx_init(&ctx.primary_db, base_moment = 0)
	_ = xitdb.tx_rm(&tx1, ".queue[[1]]")
	_ = xitdb.tx_rm(&tx1, ".visitors#%\"u1\"")
	_, err1 := xitdb.tx_commit(&tx1)
	testing.expect_value(t, err1, nil)

	then_moment_has_linked_list(&ctx, 1, "queue", []string{"first", "third"})
	then_moment_has_counted_set(&ctx, 1, "visitors", 1, []string{"u2"})

	// 3. Path_Step formatting round-trip with special characters
	steps := []xitdb.Path_Step{
		xitdb.hm("users"),
		xitdb.hm("user.101"),
		xitdb.chm("login count"),
		xitdb.ll(2),
	}
	formatted := xitdb.format_steps(steps)
	reparsed, rp_err := xitdb.parse_steps(formatted)
	testing.expect_value(t, rp_err, nil)
	testing.expect_value(t, len(reparsed), 4)
	testing.expect_value(t, reparsed[1].key, "user.101")
	testing.expect_value(t, reparsed[2].kind, xitdb.Step_Kind.Counted_Hash_Map_Key)
	testing.expect_value(t, reparsed[3].index, i64(2))
}

@(test)
spec_concurrent_dsl_selectors_pull_diff_and_datalog_queries :: proc(t: ^testing.T) {
	for backend in Backend_Kind {
		ctx := driver_init_ctx(t)
		defer driver_destroy_ctx(&ctx)

		// GIVEN a database on Memory, File, or Buffered_File with 2 moments committed via `transact_script`
		given_database_initialized_with(&ctx, backend)
		upon_transacting_dsl_script(&ctx, `
			branch none {
				doc "Moment 0 seed"
				meta "author" = "alice"
				put .users["u1"].name = "Alice"
				put .users["u1"].dept = "eng"
				put .users["u1"].age  = 30u
				put .users["u2"].name = "Bob"
				put .users["u2"].dept = "eng"
				put .users["u2"].age  = 25u
				put .users["u3"].name = "Carol"
				put .users["u3"].dept = "design"
				put .users["u3"].age  = 28u
				put $catalog["item-a"] = "Alpha"
				put $catalog["item-b"] = "Beta"
				put #counters["reqs"] = 100u
				put .org["Bob"].manager = "Alice"
				put .org["Carol"].manager = "Bob"
			}
		`)
		upon_transacting_dsl_script(&ctx, `
			branch @-1 {
				doc "Moment 1 update"
				meta "author" = "bob"
				put .users["u1"].age  = 31u
				put .users["u2"].age  = 26u
				put $catalog["item-c"] = "Gamma"
				put #counters["reqs"] = 250u
			}
		`)

		// THEN 8 worker threads can simultaneously execute selector lookups, diff_moments / history_of
		// temporal queries, and Datalog joins/aggregations/reach queries across moments without seek interference
		then_concurrent_dsl_workers_observe_consistent_snapshots(
			&ctx,
			worker_count = 8,
			expect = DSL_Concurrent_Expectations{
				uint_selectors = []Key_Uint{
					{`@0.users["u1"].age`, 30},
					{`@1.users["u1"].age`, 31},
					{`@1#counters["reqs"]`, 250},
				},
				string_selectors = []Key_Value{
					{`@0.__tx.author`, "alice"},
					{`@1.__tx.author`, "bob"},
					{`@1$catalog["item-b"]`, "Beta"},
					{`@1$catalog["item-c"]`, "Gamma"},
				},
				expected_min_diffs       = 2,
				history_path             = `.users["u1"].age`,
				expected_history_moments = 2,
				datalog_agg_query = `
					find ?dept, count(?u), sum(?age)
					where
						@1.users[?u].dept = ?dept
						@1.users[?u].age = ?age
				`,
				expected_agg_rows = 2,
				datalog_reach_query = `
					find ?mgr, ?hops
					where
						?emp == "Carol"
						reach(?emp, ?mgr, ?hops, @1.org[?emp].manager = ?mgr)
				`,
				expected_reach_ancestors = []string{"Bob", "Alice"},
			},
			sentinel_pos = 999999,
		)
	}
}
