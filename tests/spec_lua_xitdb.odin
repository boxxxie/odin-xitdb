package xitdb_tests

import "core:testing"

// ============================================================================
// Layer 1: Lua 5.4 Executable Specifications (`spec_lua_xitdb.odin`)
// ============================================================================
// Verifies that Lua 5.4 scripts and compiled Lua 5.4 bytecode chunks produce
// identical wire formats, cursor semantics, collection invariants, compaction,
// replication, and 5-Layer DSL behavior to Odin and Zig.

@(test)
spec_lua_low_level_cursors_collections_streams_and_cursor_freeze :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// UPON executing a Lua 5.4 transaction that populates all 8 collection types,
	// streams a tagged payload via Cursor_Writer, and clones + freezes a sub-tree
	upon_executing_lua_script(&ctx, `
		db:run_context(function(root)
			local history = xitdb.write_array_list(root)
			history:append_context(function(moment_cur)
				local m = xitdb.write_hash_map(moment_cur)
				m:put("greeting", "hello from lua")
				m:put("answer", xitdb.uint(42))
				m:put("temp", xitdb.int(-15))
				m:put("pi", xitdb.float(3.14159))
				m:put("doc", xitdb.bytes("# Lua Guide", "md"))

				-- Array_List
				local fruits = xitdb.write_array_list(m:put_cursor("fruits"))
				fruits:append("apple")
				fruits:append("pear")
				fruits:append("grape")

				-- Linked_Array_List (count-augmented B-Tree)
				local todos = xitdb.write_linked_array_list(m:put_cursor("todos"))
				todos:append("first")
				todos:append("third")
				todos:insert(1, "second")

				-- Counted_Hash_Map
				local cmap = xitdb.write_counted_hash_map(m:put_cursor("metrics"))
				cmap:put("cpu", xitdb.uint(85))
				cmap:put("mem", xitdb.uint(64))

				-- Hash_Set & Counted_Hash_Set
				local hset = xitdb.write_hash_set(m:put_cursor("roles"))
				hset:put("admin")
				hset:put("editor")

				local cset = xitdb.write_counted_hash_set(m:put_cursor("badges"))
				cset:put("gold")
				cset:put("silver")
				cset:put("bronze")

				-- Sorted_Map & Sorted_Set (B+Tree)
				local smap = xitdb.write_sorted_map(m:put_cursor("scores"))
				smap:put("charlie", xitdb.uint(100))
				smap:put("alice", xitdb.uint(300))
				smap:put("bob", xitdb.uint(200))

				local sset = xitdb.write_sorted_set(m:put_cursor("tags"))
				sset:put("zig")
				sset:put("odin")
				sset:put("lua")

				-- Streamed Bytes with Cursor_Writer + random seek + format tag
				local sc = m:put_cursor("streamed")
				local w = sc:writer()
				w:set_format_tag("tx")
				w:write("hello ")
				w:write("world")
				w:seek_to(6)
				w:write("LUA!!")
				w:finish()

				-- O(1) structural clone + cursor_freeze isolation
				local backup_cur = m:put_cursor("backup_fruits")
				backup_cur:write(fruits:slot())
				fruits:freeze()
				fruits:put(0, "mango")
			end)
		end)
	`)

	// THEN both Odin protocol drivers and Lua read cursors observe exact structural parity
	then_history_has_moments(&ctx, expected_count = 1)
	then_moment_has_string(&ctx, moment_idx = 0, key = "greeting", expected = "hello from lua")
	then_moment_has_scalars(
		&ctx,
		moment_idx = 0,
		expected_int = {"temp", -15},
		expected_uint = {"answer", 42},
		expected_float = {"pi", 3.14159},
	)
	then_moment_has_tagged_document(&ctx, moment_idx = 0, key = "doc", expected_text = "# Lua Guide", expected_tag = "md")
	then_moment_has_tagged_document(&ctx, moment_idx = 0, key = "streamed", expected_text = "hello LUA!!", expected_tag = "tx")
	then_moment_has_array_list(&ctx, moment_idx = 0, key = "fruits", expected_items = {"mango", "pear", "grape"})
	then_moment_has_array_list(&ctx, moment_idx = 0, key = "backup_fruits", expected_items = {"apple", "pear", "grape"})
	then_moment_has_linked_list(&ctx, moment_idx = 0, key = "todos", expected_items = {"first", "second", "third"})
	then_moment_has_counted_map_size(&ctx, moment_idx = 0, key = "metrics", expected_count = 2)
	then_moment_has_set_members(&ctx, moment_idx = 0, key = "roles", expected_members = {"admin", "editor"})
	then_moment_has_counted_set(&ctx, moment_idx = 0, key = "badges", expected_count = 3, expected_members = {"gold", "silver", "bronze"})
	then_moment_has_sorted_set_in_order(&ctx, moment_idx = 0, key = "tags", expected_sorted_members = {"lua", "odin", "zig"})
	then_moment_has_sorted_map_in_order(
		&ctx,
		moment_idx = 0,
		key = "scores",
		expected_count = 3,
		sample_ranks = {{"alice", 0}, {"bob", 1}, {"charlie", 2}},
	)

	// AND Lua iterators, range iterators, rank/select, and Cursor_Reader work directly in Lua
	then_lua_assertion_passes(&ctx, `
		local m_cur = db:select_cursor("@0")
		local m = xitdb.read_hash_map(m_cur)

		-- Cursor_Reader random seek & chunked read
		local r = m:get_cursor("streamed"):reader()
		assert(r:size() == 11)
		r:seek_to(6)
		assert(r:read(5) == "LUA!!")
		r:seek_to(0)
		assert(r:read_all() == "hello LUA!!")

		-- Sorted_Map rank, get_index_kv_pair, and iterator_from
		local sm = xitdb.read_sorted_map(m:get_cursor("scores"))
		assert(sm:count() == 3)
		assert(sm:rank("bob") == 1)
		local k_cur, v_cur = sm:get_index_kv_pair(2)
		assert(k_cur:read_string() == "charlie")
		assert(v_cur:read_uint() == 100)

		local keys_from_b = {}
		for kv_cur in sm:iterator_from("b") do
			local kc, vc = kv_cur:read_kv_pair()
			keys_from_b[#keys_from_b + 1] = kc:read_string() .. ":" .. tostring(vc:read_uint())
		end
		assert(#keys_from_b == 2 and keys_from_b[1] == "bob:200" and keys_from_b[2] == "charlie:100")
	`)
}

@(test)
spec_lua_five_layer_dsl_datalog_pushdown_aggregations_and_reach :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// UPON executing all 5 DSL layers from Lua 5.4
	upon_executing_lua_script(&ctx, `
		-- Layer 2: Programmatic Tx builder with secondary index maintenance & change tracking
		local tx0 = db:tx_init(nil, true)
		tx0:doc("Seed engineering org and cyclic dependencies")
		   :instant(1700000100)
		   :meta("author", "pauli")
		   :index_on("users", "username", "username->id")
		   :put('.users["101"].username', "dan")
		   :put('.users["101"].dept', "eng")
		   :put('.users["101"].age', xitdb.uint(28))
		   :put('.users["101"].roles%"admin"', "admin")
		   :put('.users["102"].username', "dave")
		   :put('.users["102"].dept', "eng")
		   :put('.users["102"].age', xitdb.uint(34))
		   :put('.users["103"].username', "daria")
		   :put('.users["103"].dept', "eng")
		   :put('.users["103"].age', xitdb.uint(30))
		   :put('.users["103"].roles%"suspended"', "suspended")
		   :put('.users["104"].username', "alice")
		   :put('.users["104"].dept', "design")
		   :put('.users["104"].age', xitdb.uint(40))
		   :put('.org["dan"].manager', "dave")
		   :put('.org["dave"].manager', "alice")
		   :put('.deps["app"]^"http"', "http")
		   :put('.deps["http"]^"net"', "net")
		   :put('.deps["net"]^"core"', "core")
		   :put('.deps["core"]^"http"', "http")

		local rep0 = tx0:commit()
		assert(rep0.moment_index == 0)
		assert(#rep0.changes > 0)

		-- Layer 2B: Declarative script DSL + Lua Table Marshal
		local rep1 = db:transact_script([[
			branch @-1 {
				doc "Promote dan in moment 1"
				instant 1700000200
				meta "author" = "pauli"
				put .users["101"].age = 29u
			}
		]])
		assert(rep1.moment_index == 1)

		local tx2 = db:tx_init(-1, false)
		tx2:doc("Marshal nested Lua profile table with sigils")
		   :with_cursor(function(moment_cur)
		       local p_cur = moment_cur:write_path(".profile")
		       p_cur:marshal({
		           username = "odin_lua",
		           level = 99,
		           ["bio,tag=md"] = "# Embedded Lua",
		           ["[[steps]]"] = {"compile", "transact", "query"},
		           ["^langs"] = {"zig", "odin", "lua"},
		           ["$ranks"] = {alpha = 1, beta = 2},
		       })
		   end)
		   :commit()
	`)

	// THEN Layer 1 selectors, Layer 3 pull & unmarshal, Layer 4 diffs/history/B+Tree queries, and Layer 5 Datalog all succeed in Lua
	then_lua_assertion_passes(&ctx, `
		-- Layer 1: Selectors
		assert(db:get_string('@0.__tx.doc') == "Seed engineering org and cyclic dependencies")
		assert(db:get_uint('@0.users["101"].age') == 28)
		assert(db:get_uint('@1.users["101"].age') == 29)
		local bio_val, bio_tag = db:get('@2.profile.bio')
		assert(bio_val == "# Embedded Lua" and bio_tag == "md")

		-- Layer 3: Unmarshal & Datomic pull
		local prof = db:unmarshal('@2.profile')
		assert(prof.username == "odin_lua" and prof.level == 99)
		assert(prof.bio == "# Embedded Lua")
		assert(#prof.steps == 3 and prof.steps[2] == "transact")
		assert(prof.langs[1] == "lua" and prof.langs[2] == "odin" and prof.langs[3] == "zig")
		assert(prof.ranks.alpha == 1 and prof.ranks.beta == 2)

		local pulled = db:pull('@2', '{.profile{username, steps[0..2]}}')
		assert(pulled.profile.username == "odin_lua")
		assert(#pulled.profile.steps == 2 and pulled.profile.steps[1] == "compile" and pulled.profile.steps[2] == "transact")

		-- Layer 4: diff_moments, history_of, query_prefix, query_page, query_count_range
		local diffs = db:diff_moments(0, 1)
		assert(#diffs == 1 and diffs[1].path == '.users.101.age', "diff path was: " .. tostring(diffs[1] and diffs[1].path))

		local hist = db:history_of('.users["101"].age')
		assert(#hist == 2 and hist[1].moment_index == 0 and hist[2].moment_index == 1)

		local da_hits = db:query_prefix(-1, "username->id", "da")
		assert(#da_hits == 3 and da_hits[1].key == "dan" and da_hits[2].key == "daria" and da_hits[3].key == "dave")

		local page_hits = db:query_page(-1, "username->id", 1, 2)
		assert(#page_hits == 2 and page_hits[1].key == "dan" and page_hits[2].key == "daria")

		assert(db:query_count_range(-1, "username->id", "da", "dz") == 3)

		-- Layer 5: Datalog with B+Tree prefix pushdown + negation
		local q1 = db:query_datalog([[
			find ?id, ?name, ?age
			where
				$username->id[?name] = ?id
				starts_with(?name, "da")
				.users[?id].age = ?age
				not .users[?id].roles%"suspended"
		]])
		assert(#q1.rows == 2)
		assert(q1.rows[1]["?name"] == "dan" and q1.rows[1]["?age"] == 29)
		assert(q1.rows[2]["?name"] == "dave" and q1.rows[2]["?age"] == 34)

		-- Layer 5: Grouped aggregations
		local q_agg = db:query_datalog([[
			find ?dept, count(?id), sum(?age)
			where
				.users[?id].dept = ?dept
				.users[?id].age = ?age
		]])
		assert(#q_agg.rows == 2)

		-- Layer 5: Transitive reach over cyclic dependency graph
		local q_reach = db:query_datalog([[
			find ?dep, ?hops
			where
				?pkg == "app"
				reach(?pkg, ?dep, ?hops, .deps[?pkg]^?dep)
		]])
		assert(#q_reach.rows == 3)
		assert(q_reach.rows[1]["?dep"] == "http" and q_reach.rows[1]["?hops"] == 1)
		assert(q_reach.rows[2]["?dep"] == "net"  and q_reach.rows[2]["?hops"] == 2)
		assert(q_reach.rows[3]["?dep"] == "core" and q_reach.rows[3]["?hops"] == 3)
	`)
}

@(test)
spec_lua_bytecode_compilation_storage_in_xitdb_and_execution :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// GIVEN a Lua 5.4 workflow function compiled to binary bytecode (`\x1bLua`)
	// and stored in Moment 0 under `.workflows["enrich_user"]` with format tag `"lu"`
	upon_compiling_and_storing_lua_bytecode(
		&ctx,
		base_moment = -1,
		key = "workflows[\"enrich_user\"]",
		lua_src = `
			local tx = db:tx_init(-1, true)
			tx:doc("Executed from stored Lua 5.4 bytecode inside xitdb")
			  :put('.users["500"].username', "bytecode_runner")
			  :put('.users["500"].score', xitdb.uint(777))
			  :commit()
		`,
		strip_debug = true,
	)

	// AND GIVEN a second Lua script that compiles a closure in-Lua via `xitdb.compile_bytecode`,
	// stores it in `.workflows["compute_bonus"]`, loads it back from the database slot via `xitdb.load_bytecode`,
	// and invokes it
	upon_executing_stored_lua_bytecode(&ctx, "@0.workflows[\"enrich_user\"]")

	upon_executing_lua_script(&ctx, `
		local bc = xitdb.compile_bytecode(function(multiplier)
			local base = db:get_uint('@-1.users["500"].score')
			return base * multiplier
		end, true)
		assert(string.sub(bc, 1, 3) == "\27LJ")

		local tx = db:tx_init(-1, false)
		tx:put('.workflows["compute_bonus"]', xitdb.bytes(bc, "lu")):commit()

		local stored_bc, tag = db:get('@-1.workflows["compute_bonus"]')
		assert(tag == "lu" and stored_bc == bc)

		local fn = xitdb.load_bytecode(stored_bc, "compute_bonus")
		local result = fn(3)
		assert(result == 2331)

		local tx2 = db:tx_init(-1, false)
		tx2:put('.users["500"].bonus', xitdb.uint(result)):commit()
	`)

	// THEN Moment 3 contains the mutations produced by both stored Lua 5.4 bytecode chunks
	then_history_has_moments(&ctx, expected_count = 4)
	then_lua_assertion_passes(&ctx, `
		assert(db:get_string('@1.__tx.doc') == "Executed from stored Lua 5.4 bytecode inside xitdb")
		assert(db:get_string('@-1.users["500"].username') == "bytecode_runner")
		assert(db:get_uint('@-1.users["500"].score') == 777)
		assert(db:get_uint('@-1.users["500"].bonus') == 2331)
	`)
}

@(test)
spec_lua_compaction_and_incremental_replication_convergence :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// UPON running full + incremental byte-range replication and garbage-collecting compaction in Lua 5.4
	upon_executing_lua_script(&ctx, `
		-- 1. Commit 5 moments on primary db, overwriting .counter each time
		for i = 1, 5 do
			local tx = db:tx_init(-1, false)
			tx:put(".counter", xitdb.uint(i * 100))
			  :put(".label", "iter-" .. tostring(i))
			  :commit()
		end

		-- 2. Initial full replication (start_off == 0) into replica
		local replica = xitdb.open_memory()
		local st0 = replica:replica_state()
		local start0 = db:replication_start(st0)
		assert(start0 == 0)
		local payload0 = db:read_committed_bytes(start0, db:committed_size())
		replica:apply_replicated_bytes(start0, payload0)
		assert(replica:get_uint("@-1.counter") == 500)

		-- 3. Commit Moment 5 on primary and replicate only the delta bytes (start1 > 0)
		local tx = db:tx_init(-1, false)
		tx:put(".counter", xitdb.uint(600)):commit()

		local start1 = db:replication_start(replica)
		assert(start1 > 0 and start1 == st0.committed_size or start1 == #payload0)
		local delta = db:read_committed_bytes(start1, db:committed_size())
		replica:apply_replicated_bytes(start1, delta)
		assert(replica:get_uint("@-1.counter") == 600)

		-- 4. Retain only the latest moment via Array_List slice and compact into compacted
		db:run_context(function(root)
			local hist = xitdb.write_array_list(root)
			local latest_slot = hist:get_slot(-1)
			hist:slice(0)
			hist:append(latest_slot)
		end)
		local before_size = db:committed_size()
		local om = xitdb.memory_offset_map()
		local compacted = db:compact(om)
		om:close()
		local after_size = compacted:committed_size()
		assert(after_size < before_size)
		assert(compacted:get_uint("@0.counter") == 600)
		assert(compacted:get_string("@0.label") == "iter-5")

		compacted:close()
		replica:close()
	`)
}
