package xitdb_benchmarks

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import lua "../xitdb/luajit"
import xitdb "../xitdb"

// Expose `record_bench(name, ops, elapsed_ns[, bytes_used])` to Lua benchmark scripts
@(private = "file")
_l_record_bench :: proc "c" (L: ^lua.State) -> c.int {
	context = runtime.default_context()
	name := strings.clone(string(lua.L_checkstring(L, 1)), context.temp_allocator)
	ops := int(lua.L_checkinteger(L, 2))
	elapsed_ns := i64(lua.L_checkinteger(L, 3))
	bytes_used := i64(lua.L_optinteger(L, 4, 0))

	print_result(Bench_Result{
		name       = name,
		ops        = ops,
		elapsed    = time.Duration(elapsed_ns),
		bytes_used = bytes_used,
	})
	return 0
}

@(private = "file")
_run_lua_bench_chunk :: proc(script: string, n: int, temp_dir: string = ".") {
	L := xitdb.lua_new_state()
	defer lua.close(L)

	lua.pushinteger(L, lua.Integer(n))
	lua.setglobal(L, "BENCH_N")

	c_dir := fmt.ctprintf("%s", temp_dir)
	lua.pushstring(L, c_dir)
	lua.setglobal(L, "BENCH_TEMP_DIR")

	lua.pushcfunction(L, _l_record_bench)
	lua.setglobal(L, "record_bench")

	ok, err_msg := xitdb.lua_exec_string(L, script, "bench_lua")
	if !ok {
		fmt.eprintf("Lua benchmark error: %s\n", err_msg)
		os.exit(1)
	}
}

// ----------------------------------------------------------------------------
// 1. HAMT (`Hash_Map`) Bulk Insert, Point Lookup & Branched Moment Commits (13)
// ----------------------------------------------------------------------------

bench_hamt_lua :: proc(n: int) {
	_run_lua_bench_chunk(`
		local n = BENCH_N
		local db = xitdb.open_memory("sha1")
		local history = xitdb.write_array_list(db:root_cursor())

		local keys = {}
		for i = 0, n - 1 do
			keys[i + 1] = string.format("user-key-%06d", i)
		end

		-- 1a. Bulk insert N keys in a single moment transaction
		local t0 = xitdb.now_ns()
		history:append_context(function(cursor)
			local m = xitdb.write_hash_map(cursor)
			for idx = 1, n do
				m:put(keys[idx], idx - 1)
			end
		end)
		local elapsed_insert = xitdb.now_ns() - t0
		local size_after_insert = db:committed_size()
		record_bench("HAMT Hash_Map bulk put (1 tx)", n, elapsed_insert, size_after_insert)

		-- 1b. Point lookup N keys from Moment 0 (with SHA-1 vs pre-hashed digest)
		local m0 = xitdb.read_hash_map(history:get_cursor(0))
		local t1 = xitdb.now_ns()
		for idx = 1, n do
			local vc = m0:get_cursor(keys[idx])
			local v = vc:read_uint()
			assert(v == idx - 1)
		end
		record_bench("HAMT Hash_Map point lookup (with SHA-1)", n, xitdb.now_ns() - t1, 0)

		local digests = {}
		for idx = 1, n do
			digests[idx] = db:digest(keys[idx])
		end

		local t1_pre = xitdb.now_ns()
		for idx = 1, n do
			local vc = m0:get_cursor_by_hash(digests[idx])
			local v = vc:read_uint()
			assert(v == idx - 1)
		end
		record_bench("HAMT Hash_Map lookup (pre-hashed digest)", n, xitdb.now_ns() - t1_pre, 0)

		-- 1c. Incremental branched moments (CoW structural sharing on 500 commits)
		local branch_commits = 500
		local t2 = xitdb.now_ns()
		for i = 0, branch_commits - 1 do
			local k = keys[(i % n) + 1]
			local val = n + i
			local prev_slot = history:get_slot(-1)
			history:append_context(prev_slot, function(cursor)
				local m = xitdb.write_hash_map(cursor)
				m:put(k, val)
			end)
		end
		local elapsed_branch = xitdb.now_ns() - t2
		local size_after_branch = db:committed_size()
		record_bench("HAMT CoW branched moment commits", branch_commits, elapsed_branch, size_after_branch - size_after_insert)

		-- 1d. HAMT key removal & branch shortening (remove half of the keys in 1 tx)
		local remove_count = math.floor(n / 2)
		local m0_slot = history:get_slot(0)
		local t3 = xitdb.now_ns()
		history:append_context(m0_slot, function(cursor)
			local m = xitdb.write_hash_map(cursor)
			for idx = 1, remove_count do
				m:remove(keys[idx])
			end
		end)
		record_bench("HAMT Hash_Map remove & branch shortening", remove_count, xitdb.now_ns() - t3, 0)

		-- 1e. HAMT unordered full-tree iterator scan
		local t4 = xitdb.now_ns()
		local hit = m0:iterator()
		local hcnt = 0
		while hit:next() ~= nil do
			hcnt = hcnt + 1
		end
		assert(hcnt == n)
		record_bench("HAMT Hash_Map unordered iterator scan", n, xitdb.now_ns() - t4, 0)

		-- 1f. HAMT in-place key overwrite (same tx, updating existing value slots)
		local t5 = xitdb.now_ns()
		history:append_context(m0_slot, function(cursor)
			local m = xitdb.write_hash_map(cursor)
			for idx = 1, n do
				m:put(keys[idx], (idx - 1) + 1000000)
			end
		end)
		record_bench("HAMT Hash_Map in-place overwrite (1 tx)", n, xitdb.now_ns() - t5, 0)

		-- 1g. Counted_Hash_Map bulk put + O(1) count tracking vs remove
		local t6 = xitdb.now_ns()
		history:append_context(function(cursor)
			local cm = xitdb.write_counted_hash_map(cursor)
			for idx = 1, n do
				cm:put(keys[idx], idx - 1)
			end
		end)
		local elapsed_cput = xitdb.now_ns() - t6
		local cm_slot = history:get_slot(-1)
		local rcm = xitdb.read_counted_hash_map(history:get_cursor(-1))
		assert(rcm:count() == n)
		record_bench("HAMT Counted_Hash_Map bulk put (1 tx)", n, elapsed_cput, 0)

		local t7 = xitdb.now_ns()
		history:append_context(cm_slot, function(cursor)
			local cm = xitdb.write_counted_hash_map(cursor)
			for idx = 1, remove_count do
				cm:remove(keys[idx])
			end
		end)
		record_bench("HAMT Counted_Hash_Map remove", remove_count, xitdb.now_ns() - t7, 0)

		-- 1h. HAMT deep suffix-collision splitting (10 shared trailing nibbles = 5 bytes) & collapse
		local coll_n = 500
		local coll_hashes = {}
		local prefix_zeros = string.rep("\0", 12)
		local suffix_5b = string.char(0xEE, 0xDD, 0xCC, 0xBB, 0xAA)
		for i = 0, coll_n - 1 do
			local b12 = bit.band(i * 73, 0xFF)
			local b13 = bit.band(bit.rshift(i, 8), 0xFF)
			local b14 = bit.band(i, 0xFF)
			coll_hashes[i + 1] = prefix_zeros .. string.char(b12, b13, b14) .. suffix_5b
		end

		local t8 = xitdb.now_ns()
		history:append_context(function(cursor)
			local m = xitdb.write_hash_map(cursor)
			for idx = 1, coll_n do
				m:put_key_and_value(coll_hashes[idx], idx - 1, idx - 1)
			end
		end)
		record_bench("HAMT deep suffix-collision put (depth 10+)", coll_n, xitdb.now_ns() - t8, 0)

		local coll_slot = history:get_slot(-1)
		local t9 = xitdb.now_ns()
		history:append_context(coll_slot, function(cursor)
			local m = xitdb.write_hash_map(cursor)
			for idx = 1, coll_n do
				m:remove_by_hash(coll_hashes[idx])
			end
		end)
		record_bench("HAMT deep suffix-collision branch collapse", coll_n, xitdb.now_ns() - t9, 0)

		-- 1i. Counted_Hash_Set key-only put & lookup
		local t10 = xitdb.now_ns()
		history:append_context(function(cursor)
			local cs = xitdb.write_counted_hash_set(cursor)
			for idx = 1, n do
				cs:put(keys[idx])
			end
		end)
		record_bench("HAMT Counted_Hash_Set key-only put (1 tx)", n, xitdb.now_ns() - t10, 0)

		local rcset = xitdb.read_counted_hash_set(history:get_cursor(-1))
		assert(rcset:count() == n)
		local t11 = xitdb.now_ns()
		for idx = 1, n do
			local kc = rcset:get_cursor(keys[idx])
			assert(kc ~= nil)
		end
		record_bench("HAMT Counted_Hash_Set membership check", n, xitdb.now_ns() - t11, 0)

		db:close()
	`, n)
}

// ----------------------------------------------------------------------------
// 2. Radix Trie (`Array_List`) vs Count-Augmented B-Tree (`Linked_Array_List`) (14)
// ----------------------------------------------------------------------------

bench_lists_lua :: proc(n: int) {
	_run_lua_bench_chunk(`
		local n = BENCH_N

		-- 2a. Array_List (16-way Radix Trie)
		do
			local db = xitdb.open_memory("sha1")
			local history = xitdb.write_array_list(db:root_cursor())

			local t0 = xitdb.now_ns()
			history:append_context(function(cursor)
				local list = xitdb.write_array_list(cursor)
				for i = 0, n - 1 do
					list:append(i)
				end
			end)
			local elapsed_append = xitdb.now_ns() - t0
			local sz = db:committed_size()
			record_bench("Array_List (Radix Trie) append", n, elapsed_append, sz)

			local rlist = xitdb.read_array_list(history:get_cursor(0))

			local t1 = xitdb.now_ns()
			for i = 0, n - 1 do
				local ic = rlist:get_cursor(i)
				assert(ic:read_uint() == i)
			end
			record_bench("Array_List (Radix Trie) random get", n, xitdb.now_ns() - t1, 0)

			local t2 = xitdb.now_ns()
			local it = rlist:iterator()
			local cnt = 0
			while true do
				local c = it:next()
				if c == nil then break end
				c:read_uint()
				cnt = cnt + 1
			end
			assert(cnt == n)
			record_bench("Array_List (Radix Trie) iterator scan", n, xitdb.now_ns() - t2, 0)

			local m0_arr_slot = history:get_slot(0)
			local t3 = xitdb.now_ns()
			history:append_context(m0_arr_slot, function(cursor)
				local list = xitdb.write_array_list(cursor)
				for i = 0, n - 1 do
					list:put(i, i + 1000000)
				end
			end)
			record_bench("Array_List (Radix Trie) in-place put", n, xitdb.now_ns() - t3, 0)

			local t4 = xitdb.now_ns()
			for i = 0, n - 1 do
				local ait = rlist:iterator_from(i)
				for _ = 1, 10 do
					if ait:next() == nil then break end
				end
			end
			record_bench("Array_List (Radix Trie) index-seek page(10)", n, xitdb.now_ns() - t4, 0)

			local slice_iters = 500
			local t5 = xitdb.now_ns()
			for _ = 1, slice_iters do
				history:append_context(m0_arr_slot, function(cursor)
					local list = xitdb.write_array_list(cursor)
					list:slice(10)
				end)
			end
			record_bench("Array_List (Radix Trie) depth-collapse slice", slice_iters, xitdb.now_ns() - t5, 0)

			db:close()
		end

		-- 2b. Linked_Array_List (Count-Augmented B-Tree)
		do
			local db = xitdb.open_memory("sha1")
			local history = xitdb.write_array_list(db:root_cursor())

			local t0 = xitdb.now_ns()
			history:append_context(function(cursor)
				local list = xitdb.write_linked_array_list(cursor)
				for i = 0, n - 1 do
					list:append(i)
				end
			end)
			local elapsed_append = xitdb.now_ns() - t0
			local sz = db:committed_size()
			record_bench("Linked_Array_List (B-Tree) append", n, elapsed_append, sz)

			local rlist = xitdb.read_linked_array_list(history:get_cursor(0))

			local t1 = xitdb.now_ns()
			for i = 0, n - 1 do
				local ic = rlist:get_cursor(i)
				assert(ic:read_uint() == i)
			end
			record_bench("Linked_Array_List (B-Tree) random get", n, xitdb.now_ns() - t1, 0)

			local t2 = xitdb.now_ns()
			local it = rlist:iterator()
			local cnt = 0
			while true do
				local c = it:next()
				if c == nil then break end
				c:read_uint()
				cnt = cnt + 1
			end
			assert(cnt == n)
			record_bench("Linked_Array_List (B-Tree) iterator scan", n, xitdb.now_ns() - t2, 0)

			local mid_ops = 500
			local m0_slot = history:get_slot(0)
			local t3 = xitdb.now_ns()
			history:append_context(m0_slot, function(cursor)
				local list = xitdb.write_linked_array_list(cursor)
				for i = 0, mid_ops - 1 do
					local c_len = list:count()
					list:insert(math.floor(c_len / 2), i)
				end
			end)
			record_bench("Linked_Array_List (B-Tree) middle insert", mid_ops, xitdb.now_ns() - t3, 0)

			local m1_slot = history:get_slot(1)
			local t4 = xitdb.now_ns()
			history:append_context(m1_slot, function(cursor)
				local list = xitdb.write_linked_array_list(cursor)
				for _ = 1, mid_ops do
					local c_len = list:count()
					list:remove(math.floor(c_len / 2))
				end
			end)
			record_bench("Linked_Array_List (B-Tree) middle remove", mid_ops, xitdb.now_ns() - t4, 0)

			local rope_iters = 200
			local t5 = xitdb.now_ns()
			history:append_context(m0_slot, function(cursor)
				local list = xitdb.write_linked_array_list(cursor)
				for _ = 1, rope_iters do
					list:concat(m0_slot)
					local c_len = list:count()
					list:slice(math.floor(c_len / 4), math.floor(c_len / 2))
				end
			end)
			record_bench("Linked_Array_List (B-Tree) concat + slice", rope_iters * 2, xitdb.now_ns() - t5, 0)

			local t6 = xitdb.now_ns()
			history:append_context(m0_slot, function(cursor)
				local list = xitdb.write_linked_array_list(cursor)
				for i = 0, n - 1 do
					list:put(i, i + 1000000)
				end
			end)
			record_bench("Linked_Array_List (B-Tree) in-place put", n, xitdb.now_ns() - t6, 0)

			local t7 = xitdb.now_ns()
			for i = 0, n - 1 do
				local lit = rlist:iterator_from(i)
				for _ = 1, 10 do
					if lit:next() == nil then break end
				end
			end
			record_bench("Linked_Array_List (B-Tree) index-seek page(10)", n, xitdb.now_ns() - t7, 0)

			db:close()
		end
	`, n)
}

// ----------------------------------------------------------------------------
// 3. B+Tree (`Sorted_Map`) Out-of-Order Insert, Key Lookup, Rank & Scan (11)
// ----------------------------------------------------------------------------

bench_sorted_map_lua :: proc(n: int) {
	_run_lua_bench_chunk(`
		local n = BENCH_N
		local db = xitdb.open_memory("sha1")
		local history = xitdb.write_array_list(db:root_cursor())

		local keys = {}
		for i = 0, n - 1 do
			local perm = (i * 1999 + 73) % n
			keys[i + 1] = string.format("skey-%06d", perm)
		end

		local t0 = xitdb.now_ns()
		history:append_context(function(cursor)
			local sm = xitdb.write_sorted_map(cursor)
			for idx = 1, n do
				sm:put(keys[idx], idx - 1)
			end
		end)
		local elapsed_put = xitdb.now_ns() - t0
		local sz = db:committed_size()
		record_bench("Sorted_Map (B+Tree) out-of-order put", n, elapsed_put, sz)

		local sm = xitdb.read_sorted_map(history:get_cursor(0))

		local t1 = xitdb.now_ns()
		for idx = 1, n do
			local vc = sm:get_cursor(keys[idx])
			assert(vc:read_uint() == idx - 1)
		end
		record_bench("Sorted_Map (B+Tree) key lookup", n, xitdb.now_ns() - t1, 0)

		local t2 = xitdb.now_ns()
		for idx = 1, n do
			local rk = sm:rank(keys[idx])
			assert(rk >= 0 and rk < n)
		end
		record_bench("Sorted_Map (B+Tree) rank query", n, xitdb.now_ns() - t2, 0)

		local t3 = xitdb.now_ns()
		local it = sm:iterator()
		local cnt = 0
		while it:next() ~= nil do
			cnt = cnt + 1
		end
		assert(cnt == n)
		record_bench("Sorted_Map (B+Tree) ordered scan", n, xitdb.now_ns() - t3, 0)

		local t4 = xitdb.now_ns()
		for idx = 1, n do
			local rit = sm:iterator_from(keys[idx])
			for _ = 1, 10 do
				if rit:next() == nil then break end
			end
		end
		record_bench("Sorted_Map (B+Tree) lower-bound page(10)", n, xitdb.now_ns() - t4, 0)

		local rem_count = math.floor(n / 2)
		local m0_slot = history:get_slot(0)
		local t5 = xitdb.now_ns()
		history:append_context(m0_slot, function(cursor)
			local wsm = xitdb.write_sorted_map(cursor)
			for idx = 1, rem_count do
				wsm:remove(keys[idx])
			end
		end)
		record_bench("Sorted_Map (B+Tree) remove & rebalance", rem_count, xitdb.now_ns() - t5, 0)

		local t6 = xitdb.now_ns()
		for i = 0, n - 1 do
			local kc, vc = sm:get_index_kv_pair(i)
			assert(kc ~= nil and vc ~= nil)
		end
		record_bench("Sorted_Map (B+Tree) get_index select", n, xitdb.now_ns() - t6, 0)

		local t7 = xitdb.now_ns()
		for i = 0, n - 1 do
			local iit = sm:iterator_from_index(i)
			for _ = 1, 10 do
				if iit:next() == nil then break end
			end
		end
		record_bench("Sorted_Map (B+Tree) index-seek page(10)", n, xitdb.now_ns() - t7, 0)

		local t8 = xitdb.now_ns()
		history:append_context(m0_slot, function(cursor)
			local wsm = xitdb.write_sorted_map(cursor)
			for idx = 1, n do
				wsm:put(keys[idx], (idx - 1) + 1000000)
			end
		end)
		record_bench("Sorted_Map (B+Tree) in-place overwrite", n, xitdb.now_ns() - t8, 0)

		local sz_before_sset = db:committed_size()
		local t9 = xitdb.now_ns()
		history:append_context(function(cursor)
			local ss = xitdb.write_sorted_set(cursor)
			for idx = 1, n do
				ss:put(keys[idx])
			end
		end)
		local elapsed_sset_put = xitdb.now_ns() - t9
		local sz_after_sset = db:committed_size()
		record_bench("Sorted_Set (B+Tree) key-only put (1 tx)", n, elapsed_sset_put, sz_after_sset - sz_before_sset)

		local rss = xitdb.read_sorted_set(history:get_cursor(-1))
		local t10 = xitdb.now_ns()
		for idx = 1, n do
			assert(rss:contains(keys[idx]))
		end
		record_bench("Sorted_Set (B+Tree) contains lookup", n, xitdb.now_ns() - t10, 0)

		db:close()
	`, n)
}

// ----------------------------------------------------------------------------
// 4. Compaction & Incremental Replication Throughput (6)
// ----------------------------------------------------------------------------

bench_compaction_and_replication_lua :: proc(moments_count: int) {
	_run_lua_bench_chunk(`
		local moments_count = BENCH_N
		local db = xitdb.open_memory("sha1")
		local history = xitdb.write_array_list(db:root_cursor())

		local k_names = {}
		for j = 0, 9 do
			k_names[j + 1] = string.format("k-%02d", j)
		end

		for i = 0, moments_count - 1 do
			local base_slot = nil
			if i > 0 then
				base_slot = history:get_slot(-1)
			end
			history:append_context(base_slot, function(cursor)
				local m = xitdb.write_hash_map(cursor)
				for j = 0, 9 do
					m:put(k_names[j + 1], i * 10 + j)
				end
			end)
		end

		-- 4a. Replicate all moments to a fresh secondary replica
		local rep_db = xitdb.open_memory("sha1")
		local t0 = xitdb.now_ns()
		local rep_state = rep_db:replica_state()
		local start_off = db:replication_start(rep_state)
		local end_off = db:committed_size()
		local payload = db:read_committed_bytes(start_off, end_off)
		rep_db:apply_replicated_bytes(start_off, payload)
		record_bench("Replication (genesis -> 200 moments)", moments_count, xitdb.now_ns() - t0, end_off)

		-- 4a-delta. Incremental delta replication (100 single-moment commits synced incrementally)
		local delta_commits = 100
		local t_delta = 0
		local delta_bytes = 0
		for i = 0, delta_commits - 1 do
			local idx = moments_count + i
			local s_prev = history:get_slot(-1)
			history:append_context(s_prev, function(cursor)
				local m = xitdb.write_hash_map(cursor)
				for j = 0, 9 do
					m:put(k_names[j + 1], idx * 10 + j)
				end
			end)

			local td0 = xitdb.now_ns()
			local d_state = rep_db:replica_state()
			local d_start = db:replication_start(d_state)
			local d_end = db:committed_size()
			local d_payload = db:read_committed_bytes(d_start, d_end)
			rep_db:apply_replicated_bytes(d_start, d_payload)
			t_delta = t_delta + (xitdb.now_ns() - td0)
			delta_bytes = delta_bytes + (d_end - d_start)
		end
		record_bench("Replication (incremental 1-moment delta)", delta_commits, t_delta, delta_bytes)

		-- 4b. Prune to latest 1 moment & compact database (Memory_Offset_Map)
		history:slice(1)
		local comp_db = xitdb.open_memory("sha1")
		local t1 = xitdb.now_ns()
		local om = xitdb.memory_offset_map()
		db:compact(comp_db, om)
		local elapsed_compact = xitdb.now_ns() - t1
		om:close()
		record_bench("Compaction (Memory_Offset_Map, 200 -> 1)", 1, elapsed_compact, comp_db:committed_size())

		-- 4c. Compact using disk-backed File_Offset_Map
		local comp_db2 = xitdb.open_memory("sha1")
		local om_db = xitdb.open_memory("sha1")
		local file_om = xitdb.file_offset_map(om_db)
		local t2 = xitdb.now_ns()
		db:compact(comp_db2, file_om)
		local elapsed_file_compact = xitdb.now_ns() - t2
		file_om:close()
		om_db:close()
		record_bench("Compaction (File_Offset_Map, 200 -> 1)", 1, elapsed_file_compact, comp_db2:committed_size())

		-- 4d. Heterogeneous DAG Compaction
		do
			local dag_db = xitdb.open_memory("sha1")
			dag_db:run_context(function(cursor)
				local root_map = xitdb.write_counted_hash_map(cursor)

				local al = xitdb.write_array_list(root_map:put_cursor("array_list"))
				for i = 0, 199 do
					al:append(string.format("arr-item-%04d-payload", i))
				end
				local al_slot = al:slot()

				local lal = xitdb.write_linked_array_list(root_map:put_cursor("linked_list"))
				for i = 0, 199 do
					lal:append(i)
				end
				local lal_slot = lal:slot()

				local sm = xitdb.write_sorted_map(root_map:put_cursor("sorted_map"))
				for i = 0, 199 do
					sm:put(string.format("skey-%04d", (i * 73) % 200), i)
				end
				local sm_slot = sm:slot()

				for alias_i = 0, 4 do
					root_map:put(string.format("alias-al-%d", alias_i), al_slot)
					root_map:put(string.format("alias-lal-%d", alias_i), lal_slot)
					root_map:put(string.format("alias-sm-%d", alias_i), sm_slot)
				end
			end)

			local dag_comp_db = xitdb.open_memory("sha1")
			local dag_om = xitdb.memory_offset_map()
			local t_dag = xitdb.now_ns()
			dag_db:compact(dag_comp_db, dag_om)
			local elapsed_dag = xitdb.now_ns() - t_dag
			dag_om:close()
			record_bench("Compaction (Heterogeneous DAG + dedup)", 1, elapsed_dag, dag_comp_db:committed_size())

			-- 4f. Post-compaction replica resync
			local resync_rep_db = xitdb.open_memory("sha1")
			local orig_end = dag_db:committed_size()
			local orig_bytes = dag_db:read_committed_bytes(0, orig_end)
			resync_rep_db:apply_replicated_bytes(0, orig_bytes)

			local t_resync = xitdb.now_ns()
			local r_state = resync_rep_db:replica_state()
			local resync_start = dag_comp_db:replication_start(r_state)
			assert(resync_start == 0)
			local comp_end = dag_comp_db:committed_size()
			local comp_payload = dag_comp_db:read_committed_bytes(resync_start, comp_end)
			resync_rep_db:apply_replicated_bytes(resync_start, comp_payload)
			local elapsed_resync = xitdb.now_ns() - t_resync
			record_bench("Replication (Post-compaction resync)", 1, elapsed_resync, #comp_payload)

			resync_rep_db:close()
			dag_comp_db:close()
			dag_db:close()
		end

		comp_db2:close()
		comp_db:close()
		rep_db:close()
		db:close()
	`, moments_count)
}

// ----------------------------------------------------------------------------
// 5. Hasher Comparison (`SHA-1` 20B vs `SHA-256` 32B) & Byte Storage Paths (13)
// ----------------------------------------------------------------------------

bench_hashers_and_byte_streams_lua :: proc(n: int) {
	_run_lua_bench_chunk(`
		local n = BENCH_N
		local keys = {}
		for i = 0, n - 1 do
			keys[i + 1] = string.format("hash-bench-key-%06d", i)
		end

		-- 5a. SHA-1 (20B) vs SHA-256 (32B) HAMT insert & footprint
		for _, algo in ipairs({"sha1", "sha256"}) do
			local db = xitdb.open_memory(algo)
			local history = xitdb.write_array_list(db:root_cursor())
			local t0 = xitdb.now_ns()
			history:append_context(function(cursor)
				local m = xitdb.write_hash_map(cursor)
				for idx = 1, n do
					m:put(keys[idx], idx - 1)
				end
			end)
			local elapsed = xitdb.now_ns() - t0
			local sz = db:committed_size()
			local label = (algo == "sha1") and "Hasher: SHA-1 (20B) HAMT put" or "Hasher: SHA-256 (32B) HAMT put"
			record_bench(label, n, elapsed, sz)
			db:close()
		end

		-- 5b. Inline Short_Bytes (<= 8B) vs External Bytes (> 8B) reads
		do
			local db = xitdb.open_memory("sha1")
			local m = xitdb.write_hash_map(db:root_cursor())
			m:put("inline", "8bytes!!")
			m:put("heap", "heap-allocated-32-byte-string!!!")

			local inline_cur = m:get_cursor("inline")
			local heap_cur = m:get_cursor("heap")
			local reads = n * 5

			local t_in = xitdb.now_ns()
			for _ = 1, reads do
				local v = inline_cur:read_bytes()
				assert(#v == 8)
			end
			record_bench("Bytes: Inline Short_Bytes read_bytes_buf", reads, xitdb.now_ns() - t_in, 0)

			local t_hp = xitdb.now_ns()
			for _ = 1, reads do
				local v = heap_cur:read_bytes()
				assert(#v == 32)
			end
			record_bench("Bytes: External Bytes read_bytes_buf", reads, xitdb.now_ns() - t_hp, 0)

			m:put("tagged_inline", xitdb.bytes("6bytes", "js"))
			m:put("tagged_heap", xitdb.bytes("heap-allocated-32-byte-string!!!", "md"))
			local t_in_cur = m:get_cursor("tagged_inline")
			local t_hp_cur = m:get_cursor("tagged_heap")

			local t_tin = xitdb.now_ns()
			for _ = 1, reads do
				local v, tag = t_in_cur:read_bytes()
				assert(#v == 6 and #tag == 2)
			end
			record_bench("Bytes: Tagged Short_Bytes read_bytes_buf", reads, xitdb.now_ns() - t_tin, 0)

			local t_thp = xitdb.now_ns()
			for _ = 1, reads do
				local v, tag = t_hp_cur:read_bytes()
				assert(#v == 32 and #tag == 2)
			end
			record_bench("Bytes: Tagged External Bytes read_bytes_buf", reads, xitdb.now_ns() - t_thp, 0)
			db:close()
		end

		-- 5c. Streaming Cursor_Writer & Cursor_Reader (1 MB payload in 4 KB chunks)
		do
			local db = xitdb.open_memory("sha1")
			local chunks_count = 256
			local chunk_tail = string.rep("\0", 4095)
			local blob_rc = nil

			local t_sw = xitdb.now_ns()
			db:run_context(function(cursor)
				local w = cursor:writer()
				for i = 0, chunks_count - 1 do
					w:write(string.char(bit.band(i, 0xFF)) .. chunk_tail)
				end
				w:finish()
				blob_rc = cursor:read_only()
			end)
			local elapsed_sw = xitdb.now_ns() - t_sw
			local sz_sw = db:committed_size()
			record_bench("Stream: Cursor_Writer (256 x 4KB = 1MB)", chunks_count, elapsed_sw, sz_sw)

			local t_sr = xitdb.now_ns()
			local reader = blob_rc:reader()
			local read_chunks = 0
			while true do
				local b = reader:read(4096)
				if b == nil then break end
				read_chunks = read_chunks + 1
			end
			assert(read_chunks == chunks_count)
			record_bench("Stream: Cursor_Reader (256 x 4KB = 1MB)", chunks_count, xitdb.now_ns() - t_sr, 0)

			local seek_ops = n
			local limit_off = chunks_count * 4096 - 64
			local t_rseek = xitdb.now_ns()
			for i = 0, seek_ops - 1 do
				local off = (i * 4099) % limit_off
				reader:seek_to(off)
				local b = reader:read(64)
				assert(#b == 64)
			end
			record_bench("Stream: Cursor_Reader random seek + 64B read", seek_ops, xitdb.now_ns() - t_rseek, 0)

			local init_buf = string.rep("\0", 65536)
			local patch_tail = string.rep("\0", 15)
			local patch_limit = 65536 - 16
			local t_wseek = xitdb.now_ns()
			db:run_context(function(cursor)
				local w = cursor:writer()
				w:write(init_buf)
				for i = 0, seek_ops - 1 do
					local off = (i * 1031) % patch_limit
					w:seek_to(off)
					w:write(string.char(bit.band(i, 0xFF)) .. patch_tail)
				end
				w:finish()
			end)
			record_bench("Stream: Cursor_Writer random seek + 16B patch", seek_ops, xitdb.now_ns() - t_wseek, 0)
			db:close()
		end

		-- 5d. Deeply Nested Multi-Part Atomic Path Traversal (4 nested collections)
		do
			local db = xitdb.open_memory("sha1")
			local path_ops = 500
			local h_root = db:digest("tenant")

			local init_parts = {
				{op = "hash_map_init"},
				{op = "hash_map_get_value", hash = h_root},
				{op = "array_list_init"},
				{op = "array_list_append"},
				{op = "linked_array_list_init"},
				{op = "linked_array_list_append"},
				{op = "sorted_map_init"},
			}
			local step_parts = {
				{op = "hash_map_get_value", hash = h_root},
				{op = "array_list_get", index = 0},
				{op = "linked_array_list_get", index = 0},
				{op = "sorted_map_get_value", key = "deep-sorted-key"},
				{op = "write", data = 0},
			}

			local t_dw = xitdb.now_ns()
			db:run_context(function(cursor)
				cursor:write_path(init_parts)
				for i = 0, path_ops - 1 do
					step_parts[5].data = i
					cursor:write_path(step_parts)
				end
			end)
			record_bench("Path: 4-level nested cursor_write_path", path_ops, xitdb.now_ns() - t_dw, 0)

			local rc = db:root_cursor():read_only()
			local read_parts = {
				{op = "hash_map_get_value", hash = h_root},
				{op = "array_list_get", index = 0},
				{op = "linked_array_list_get", index = 0},
				{op = "sorted_map_get_value", key = "deep-sorted-key"},
			}
			local t_dr = xitdb.now_ns()
			for _ = 1, path_ops do
				local mc = rc:read_path(read_parts)
				assert(mc:read_uint() == path_ops - 1)
			end
			record_bench("Path: 4-level nested cursor_read_path", path_ops, xitdb.now_ns() - t_dr, 0)
			db:close()
		end

		-- 5e. Full KV-Pair Inspection Scan (read_kv_pair)
		do
			local db = xitdb.open_memory("sha1")
			local history = xitdb.write_array_list(db:root_cursor())
			history:append_context(function(cursor)
				local m = xitdb.write_hash_map(cursor)
				for idx = 1, n do
					m:put(keys[idx], idx - 1)
				end
			end)

			local rm = xitdb.read_hash_map(history:get_cursor(0))
			local kv_cnt = 0
			local t_kv = xitdb.now_ns()
			local it = rm:iterator()
			while true do
				local cur = it:next()
				if cur == nil then break end
				local kc, vc = cur:read_kv_pair()
				local k_bytes = kc:read_bytes()
				local v_uint = vc:read_uint()
				assert(#k_bytes > 0 and v_uint < n)
				kv_cnt = kv_cnt + 1
			end
			assert(kv_cnt == n)
			record_bench("Cursor: Full KV-pair scan (read_kv_pair)", n, xitdb.now_ns() - t_kv, 0)
			db:close()
		end
	`, n)
}

// ----------------------------------------------------------------------------
// 6. Storage Backends (`Core_Memory` vs `Core_Buffered_File` vs `Core_File`) (6)
// ----------------------------------------------------------------------------

bench_backends_lua :: proc(commits: int) {
	temp_dir, td_err := os.temp_directory(context.temp_allocator)
	if td_err != nil || len(temp_dir) == 0 {
		temp_dir = "."
	}

	_run_lua_bench_chunk(`
		local commits = BENCH_N
		local temp_dir = BENCH_TEMP_DIR

		local function run_commits(db)
			local history = xitdb.write_array_list(db:root_cursor())
			for i = 0, commits - 1 do
				local base = nil
				if i > 0 then
					base = history:get_slot(-1)
				end
				history:append_context(base, function(cursor)
					local m = xitdb.write_hash_map(cursor)
					m:put("counter", i)
					m:put("label", "benchmark-payload-string")
				end)
			end
		end

		-- 6a. Core_Memory
		do
			local db = xitdb.open_memory("sha1")
			local t0 = xitdb.now_ns()
			run_commits(db)
			local elapsed = xitdb.now_ns() - t0
			local sz = db:committed_size()
			record_bench("Backend: Core_Memory commits", commits, elapsed, sz)
			db:close()
		end

		-- 6b. Core_Buffered_File (64 KB buffer, fsync = false)
		do
			local path = temp_dir .. "/xitdb_lua_bench_buffered.db"
			os.remove(path)
			local db = xitdb.open_buffered_file(path, 65536, {hash = "sha1", truncate = true, fsync = false})
			local t0 = xitdb.now_ns()
			run_commits(db)
			local elapsed = xitdb.now_ns() - t0
			local sz = db:committed_size()
			record_bench("Backend: Core_Buffered_File commits", commits, elapsed, sz)
			db:close()
			os.remove(path)
		end

		-- 6c. Core_File (unbuffered OS syscalls, fsync = false)
		do
			local path = temp_dir .. "/xitdb_lua_bench_file.db"
			os.remove(path)
			local db = xitdb.open_file(path, {hash = "sha1", truncate = true, fsync = false})
			local t0 = xitdb.now_ns()
			run_commits(db)
			local elapsed = xitdb.now_ns() - t0
			local sz = db:committed_size()
			record_bench("Backend: Core_File (unbuffered) commits", commits, elapsed, sz)
			db:close()
			os.remove(path)
		end

		-- 6d. Mid-transaction database_freeze + CoW subtree cloning & transaction rollback truncation
		do
			local db = xitdb.open_memory("sha1")
			local t_fc = xitdb.now_ns()
			db:run_context(function(cursor)
				local top = xitdb.write_hash_map(cursor)
				local base_map = xitdb.write_hash_map(top:put_cursor("base"))
				for j = 0, 15 do
					base_map:put(string.format("k-%02d", j), j)
				end
				local base_slot = base_map:slot()

				for i = 0, commits - 1 do
					db:freeze()
					local fork_key = string.format("fork-%04d", i)
					top:put(fork_key, base_slot)
					local fork_map = xitdb.write_hash_map(top:put_cursor(fork_key))
					fork_map:put("k-00", 1000 + i)
				end
			end)
			record_bench("Tx: Mid-tx database_freeze + CoW clone", commits, xitdb.now_ns() - t_fc, 0)

			local size_before_rb = db:committed_size()
			local t_rb = xitdb.now_ns()
			for _ = 1, commits do
				local ok = pcall(function()
					db:run_context(function(cursor)
						local top = xitdb.write_hash_map(cursor)
						top:put("temp-1", 1)
						top:put("temp-2", "uncommitted-payload-bytes")
						return false
					end)
				end)
				assert(not ok)
			end
			local elapsed_rb = xitdb.now_ns() - t_rb
			assert(db:committed_size() == size_before_rb)
			record_bench("Tx: Aborted transaction rollback truncate", commits, elapsed_rb, 0)

			-- 6e. Database re-open & trailer checksum verify
			local reopen_ops = commits * 10
			local t_reopen = xitdb.now_ns()
			for _ = 1, reopen_ops do
				db:reopen()
				local rc = db:root_cursor()
				assert(rc:tag() == "Hash_Map")
			end
			record_bench("DB: Re-open & trailer checksum verify", reopen_ops, xitdb.now_ns() - t_reopen, 0)
			db:close()
		end
	`, commits, temp_dir)
}

// ----------------------------------------------------------------------------
// 7. 5-Layer DSL & Datalog Engine Benchmarks (12)
// ----------------------------------------------------------------------------

run_dsl_benchmarks_lua :: proc(_: int = 0) {
	_run_lua_bench_chunk(`
		local db = xitdb.open_memory("sha1")
		local N = 500

		-- 1. Layer 2: Datomic-style Tx commits with secondary index maintenance (tx_index_on)
		do
			local t0 = xitdb.now_ns()
			local tx = db:tx_init(nil, false)
			tx:doc("Benchmark seed 500 indexed users and cyclic dependency graph")
			tx:index_on("users", "username", "username->id")

			for i = 0, N - 1 do
				local id_str = string.format("u%04d", i)
				local uname = string.format("user_%04d", i)
				local dept = (i % 3 ~= 0) and "eng" or "design"
				local age = 22 + (i % 40)

				tx:put(string.format('.users[%q].username', id_str), uname)
				tx:put(string.format('.users[%q].dept', id_str), dept)
				tx:put(string.format('.users[%q].age', id_str), age)
				if i % 10 == 0 then
					tx:put(string.format('.users[%q].roles%%"suspended"', id_str), "suspended")
				end
			end

			for i = 0, 31 do
				local src = string.format("pkg_%02d", i)
				local dst = string.format("pkg_%02d", (i + 1) % 32)
				tx:put(string.format('.deps[%q]^%q', src, dst), dst)
			end

			local rep0 = tx:commit()
			record_bench("DSL Layer 2: Tx Commit + Secondary Index (N=500)", N, xitdb.now_ns() - t0, rep0.commit_size)
		end

		-- 2. Layer 1: String Path Selector point lookups
		do
			local t0 = xitdb.now_ns()
			for i = 0, N - 1 do
				local sel = string.format('@-1.users["u%04d"].age', i)
				local val = db:get_uint(sel)
				assert(val >= 22)
			end
			record_bench("DSL Layer 1: String Selector get_uint (N=500)", N, xitdb.now_ns() - t0, 0)
		end

		-- 3. Layer 3: Lua Table marshal & unmarshal + Datomic pull
		do
			local dto = {
				username = "alice",
				dept     = "eng",
				age      = 31,
				["bio,tag=md"] = "# Principal Systems Engineer",
				["[[todos]]"]  = {"Design DSL", "Optimize B+Tree pushdown", "Write benchmarks"},
				["^tags"]      = {"odin", "xitdb", "datalog"},
			}
			local M = 200
			local t0 = xitdb.now_ns()
			local tx = db:tx_init(-1, false)
			tx:with_cursor(function(cursor)
				local m = xitdb.write_hash_map(cursor)
				local profiles = xitdb.write_hash_map(m:put_cursor("profiles"))
				for i = 0, M - 1 do
					local k = string.format("p%03d", i)
					local pcur = profiles:put_cursor(k)
					pcur:marshal(dto)
				end
			end)
			tx:commit()
			record_bench("DSL Layer 3: Struct marshal (N=200)", M, xitdb.now_ns() - t0, 0)

			local t1 = xitdb.now_ns()
			for i = 0, M - 1 do
				local out = db:unmarshal(string.format('@-1.profiles["p%03d"]', i))
				assert(out.age == 31)
			end
			record_bench("DSL Layer 3: Struct unmarshal (N=200)", M, xitdb.now_ns() - t1, 0)

			local t2 = xitdb.now_ns()
			for i = 0, M - 1 do
				local pv = db:pull(string.format('@-1.profiles["p%03d"]', i), "{username, age, todos[0..2]}")
				assert(pv ~= nil and pv.username == "alice")
			end
			record_bench("DSL Layer 3: Datomic pull projection (N=200)", M, xitdb.now_ns() - t2, 0)
		end

		-- 4. Layer 4: O(1) Subtree-Skipping diff_moments & history_of
		do
			local tx = db:tx_init(-1, false)
			tx:put('.users["u0042"].age', 99):commit()

			local Q = 200
			local t0 = xitdb.now_ns()
			for _ = 1, Q do
				local diffs = db:diff_moments(1, 2, false)
				assert(#diffs == 1)
			end
			record_bench("DSL Layer 4: diff_moments (1 of 700 mutated)", Q, xitdb.now_ns() - t0, 0)

			local t1 = xitdb.now_ns()
			for _ = 1, Q do
				local hist = db:history_of('.users["u0042"].age')
				assert(#hist == 2)
			end
			record_bench("DSL Layer 4: history_of lineage (3 moments)", Q, xitdb.now_ns() - t1, 0)
		end

		-- 5. Layer 5: Datalog B+Tree Prefix Pushdown, Grouped Aggregations & Cycle-Safe reach
		do
			local Q = 100
			local q_prefix = [[
				find ?id, ?name, ?age
				where
					$username->id[?name] = ?id
					starts_with(?name, "user_025")
					.users[?id].age = ?age
					not .users[?id].roles%"suspended"
			]]
			local t0 = xitdb.now_ns()
			for _ = 1, Q do
				local res = db:query_datalog(q_prefix, -1)
				assert(#res.rows == 9)
			end
			record_bench("DSL Layer 5: Datalog B+Tree Prefix + Join", Q, xitdb.now_ns() - t0, 0)

			local A = 25
			local q_agg = [[
				find ?dept, count(?id), min(?age), max(?age), sum(?age)
				where
					.users[?id].dept = ?dept
					.users[?id].age = ?age
			]]
			local t1 = xitdb.now_ns()
			for _ = 1, A do
				local res = db:query_datalog(q_agg, -1)
				assert(#res.rows == 2)
			end
			record_bench("DSL Layer 5: Datalog Grouped Aggs (N=500)", A, xitdb.now_ns() - t1, 0)

			local R = 100
			local q_reach = [[
				find ?target, ?hops
				where
					?start == "pkg_00"
					reach(?start, ?target, ?hops, .deps[?start]^?target)
			]]
			local t2 = xitdb.now_ns()
			for _ = 1, R do
				local res = db:query_datalog(q_reach, -1)
				assert(#res.rows == 32)
			end
			record_bench("DSL Layer 5: Datalog Cycle-Safe reach (32-ring)", R, xitdb.now_ns() - t2, 0)
		end

		-- 6. Layer 2 & 3/4: Secondary Index Stale-Key Eviction & Cyclic Graph pull + diff
		do
			local U = 200
			local t0 = xitdb.now_ns()
			local tx_evict = db:tx_init(-1, false)
			tx_evict:index_on("users", "username", "username->id")
			for i = 0, U - 1 do
				local id_str = string.format("u%04d", i)
				local new_uname = string.format("renamed_%04d", i)
				tx_evict:put(string.format('.users[%q].username', id_str), new_uname)
			end
			tx_evict:commit()
			record_bench("DSL Layer 2: Secondary Index Evict+Update (N=200)", U, xitdb.now_ns() - t0, 0)

			local tx_cyc = db:tx_init(-1, true)
			tx_cyc:with_cursor(function(cursor)
				local moment = xitdb.write_hash_map(cursor)
				local m_slot = moment:slot()
				moment:put("self", m_slot)

				local ma = xitdb.write_hash_map(moment:put_cursor("node_a"))
				ma:put("label", "A")

				local mb = xitdb.write_hash_map(moment:put_cursor("node_b"))
				mb:put("label", "B")

				local mb_slot = mb:slot()
				ma:put("peer", mb_slot)
				local ma_slot = ma:slot()
				mb:put("peer", ma_slot)
			end)
			local rep_cyc = tx_cyc:commit()

			local tx_cyc2 = db:tx_init(-1, false)
			tx_cyc2:put(".node_a.label", "A_v2")
			local rep_cyc2 = tx_cyc2:commit()

			local C = 200
			local node_a_cur = db:select_cursor("@-1.node_a")
			local t1 = xitdb.now_ns()
			for _ = 1, C do
				local pv = node_a_cur:pull("*")
				assert(pv ~= nil)
				local diffs = db:diff_moments(rep_cyc.moment_index, rep_cyc2.moment_index, false)
				assert(#diffs == 1)
			end
			record_bench("DSL Layer 3/4: Cyclic Graph pull + diff (N=200)", C, xitdb.now_ns() - t1, 0)
		end

		db:close()
	`, 0)
}
