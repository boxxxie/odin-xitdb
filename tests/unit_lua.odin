package xitdb_tests

import "core:os"
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
