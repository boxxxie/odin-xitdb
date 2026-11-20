package xitdb_tests

import "base:runtime"
import "core:testing"
import lua "../xitdb/luajit"
import xitdb "../xitdb"

// ============================================================================
// Unit Tests for `xitdb/lua.odin` (`tests/unit_lua.odin`)
// ============================================================================

@(test)
unit_lua_standalone_memory_file_and_buffered_file_lifecycle :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	L := xitdb.lua_new_state(nil)
	testing.expect(t, L != nil)
	defer lua.close(L)

	ok, err_msg := xitdb.lua_exec_string(L, `
		-- 0. Verify LuaJIT 2.1 JIT engine & FFI are active
		assert(type(jit) == "table" and jit.status() == true, "Expected LuaJIT JIT compiler to be enabled")
		assert(string.sub(jit.version, 1, 6) == "LuaJIT", "Expected LuaJIT runtime")
		assert(type(require("ffi")) == "table", "Expected LuaJIT FFI library")

		-- 1. Standalone in-memory DB with SHA-256 hasher
		local mem_db = xitdb.open_memory("sha256")
		assert(#mem_db:digest("hello") == 32)
		local tx = mem_db:tx_init(nil, false)
		tx:put(".key", "sha256-ok"):commit()
		assert(mem_db:get_string("@0.key") == "sha256-ok")
		mem_db:close()

		-- 2. File-backed DB & Buffered-file DB round-trip
		local fpath = xitdb.temp_path("unit_file.xit")
		xitdb.remove_file(fpath)
		local fdb = xitdb.open_file(fpath, {truncate = true})
		fdb:tx_init(nil, false):put(".persisted", xitdb.uint(12345)):commit()
		fdb:close()

		local bfdb = xitdb.open_buffered_file(fpath, 4096)
		assert(bfdb:get_uint("@0.persisted") == 12345)
		bfdb:tx_init(-1, false):put(".persisted", xitdb.uint(67890)):commit()
		bfdb:reopen()
		assert(bfdb:get_uint("@1.persisted") == 67890)
		bfdb:close()
		xitdb.remove_file(fpath)
	`, "unit_lua_lifecycle")
	if !ok {
		testing.expectf(t, false, "unit_lua_lifecycle failed: %s", err_msg)
	}
}

@(test)
unit_lua_error_handling_and_transaction_abort_rollback :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	db, err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, err, nil)

	L := xitdb.lua_new_state(&db)
	defer lua.close(L)

	ok, err_msg := xitdb.lua_exec_string(L, `
		db:tx_init(nil, false):put(".x", "initial"):commit()
		local size_before = db:committed_size()

		-- Returning false or raising error inside run_context rolls back uncommitted writes
		local status, _ = pcall(function()
			db:run_context(function(root)
				local hist = xitdb.write_array_list(root)
				hist:append("uncommitted")
				error("simulated lua failure")
			end)
		end)
		assert(status == false)
		assert(db:committed_size() == size_before)

		-- Attempting to write to a read-only cursor raises a clean Lua error
		local rc = db:select_cursor("@0.x")
		local w_ok, _ = pcall(function()
			rc:write("illegal")
		end)
		assert(w_ok == false)
	`, "unit_lua_errors")
	if !ok {
		testing.expectf(t, false, "unit_lua_errors failed: %s", err_msg)
	}
}

@(test)
unit_lua_deep_recursive_unmarshal_small_stack_and_oom_safety :: proc(t: ^testing.T) {
	MIXED_DEPTH :: 40

	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)
	defer free_all(context.temp_allocator)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	tx0 := xitdb.tx_init(&db, base_moment = nil, allocator = context.allocator)
	defer xitdb.tx_destroy(&tx0)
	xitdb.tx_with_cursor(&tx0, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		cur := xitdb.hash_map_put_cursor(&moment, "chain") or_return
		for level in 0 ..< MIXED_DEPTH {
			switch level % 5 {
			case 0:
				hm := xitdb.write_hash_map_init(cur) or_return
				cur = xitdb.hash_map_put_cursor(&hm, "next") or_return
			case 1:
				chm := xitdb.write_counted_hash_map_init(cur) or_return
				cur = xitdb.hash_map_put_cursor(&chm.write_hash_map, "next") or_return
			case 2:
				sm := xitdb.write_sorted_map_init(cur) or_return
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
		xitdb.hash_map_put(&leaf_hm, "leaf", "lua-v2") or_return

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
		return nil
	})
	rep0, err0 := xitdb.tx_commit(&tx0)
	testing.expect_value(t, err0, nil)
	defer xitdb.tx_report_destroy(&rep0, context.allocator)

	chain_maybe, cm_err := xitdb.select_cursor(&db, "@0.chain")
	testing.expect_value(t, cm_err, nil)
	chain_cur, has_chain := chain_maybe.?
	testing.expect(t, has_chain, "Expected @0.chain cursor")
	if !has_chain {
		return
	}

	Worker_Args :: struct {
		t:         ^testing.T,
		db:        ^xitdb.Database,
		chain_cur: xitdb.Read_Cursor,
	}

	args := Worker_Args{
		t         = t,
		db        = &db,
		chain_cur = chain_cur,
	}

	worker :: proc(raw: rawptr) {
		defer free_all(context.temp_allocator)
		a := (^Worker_Args)(raw)

		L := xitdb.lua_new_state(a.db)
		testing.expect(a.t, L != nil)
		if L == nil {
			return
		}
		defer lua.close(L)

		ok, err_msg := xitdb.lua_exec_string(L, `
			local cur = db:unmarshal("@0.chain")
			for level = 0, 39 do
				local rem = level % 5
				if rem == 0 or rem == 1 then
					assert(type(cur) == "table" and cur.next ~= nil, "Expected map next at level " .. tostring(level))
					cur = cur.next
				elseif rem == 2 then
					assert(type(cur) == "table" and cur.m_next ~= nil, "Expected sorted map m_next at level " .. tostring(level))
					cur = cur.m_next
				else
					assert(type(cur) == "table" and cur[1] == "pad" and cur[2] ~= nil, "Expected list child at level " .. tostring(level))
					cur = cur[2]
				end
			end
			assert(type(cur) == "table")
			assert(cur.leaf == "lua-v2")
			assert(type(cur.hs) == "table" and #cur.hs == 2)
			assert(type(cur.chs) == "table" and #cur.chs == 2)
			assert(type(cur.ss) == "table" and #cur.ss == 2)
		`, "unit_lua_deep_unmarshal")
		if !ok {
			testing.expectf(a.t, false, "unit_lua_deep_unmarshal failed: %s", err_msg)
		}

		// Verify OOM during pooled iterator acquisition fails cleanly and restores the Lua stack top.
		top_before := lua.gettop(L)
		prev_alloc := context.allocator
		context.allocator = runtime.nil_allocator()
		oom_err := xitdb.lua_unmarshal_cursor(L, a.chain_cur)
		context.allocator = prev_alloc
		testing.expect_value(a.t, oom_err, xitdb.Xitdb_Error.Write_Failed)
		testing.expect_value(a.t, lua.gettop(L), top_before)
	}

	_run_on_small_stack(t, 512 * 1024, worker, &args)
}
