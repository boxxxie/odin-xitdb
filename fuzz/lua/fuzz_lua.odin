package fuzz_lua

import "base:runtime"
import "core:c"
import "core:c/libc"
import xitdb "xitdb:."
import lua "xitdb:luajit"

when ODIN_OS == .Linux {
	foreign import luajit_lib "system:luajit-5.1"
} else when ODIN_OS == .Darwin {
	foreign import luajit_lib "system:luajit-5.1"
} else when ODIN_OS == .Windows {
	foreign import luajit_lib "system:lua51.lib"
}

@(private = "file")
LUA_MASKRET :: c.int(1 << 1)
@(private = "file")
LUA_MASKCOUNT :: c.int(1 << 3)
@(private = "file")
LUA_MAX_ALLOC_BYTES :: uint(8 * 1024 * 1024)

@(private = "file")
_Lua_Alloc_State :: struct {
	used:  uint,
	limit: uint,
}

@(private = "file")
_bounded_lua_alloc :: proc "c" (ud: rawptr, ptr: rawptr, osize: c.size_t, nsize: c.size_t) -> rawptr {
	state := (^_Lua_Alloc_State)(ud)
	// When ptr == nil, Lua passes an object type tag in osize rather than byte size.
	old_bytes := uint(osize) if ptr != nil else 0
	new_bytes := uint(nsize)

	if new_bytes == 0 {
		if ptr != nil {
			state.used -= min(state.used, old_bytes)
			libc.free(ptr)
		}
		return nil
	}

	if new_bytes > old_bytes {
		delta := new_bytes - old_bytes
		if delta > state.limit || state.used + delta > state.limit {
			return nil
		}
	}

	new_ptr := libc.realloc(ptr, nsize)
	if new_ptr == nil {
		return nil
	}
	state.used = state.used - min(state.used, old_bytes) + new_bytes
	return new_ptr
}

@(private = "file")
Lua_Hook :: #type proc "c" (L: ^lua.State, ar: rawptr)

@(default_calling_convention = "c")
foreign luajit_lib {
	@(link_name = "lua_sethook")
	lua_sethook :: proc(L: ^lua.State, func: Lua_Hook, mask: c.int, count: c.int) -> c.int ---
}

@(private = "file")
_instruction_limit_hook :: proc "c" (L: ^lua.State, _ar: rawptr) {
	// Re-arm every instruction/return so pcall/xpcall/coroutine.resume cannot swallow
	// the error and spin indefinitely until libFuzzer's wall-clock timeout.
	_ = lua_sethook(L, _instruction_limit_hook, LUA_MASKCOUNT | LUA_MASKRET, 1)
	lua.L_error(L, "instruction limit exceeded")
}

@(private = "file")
_sandbox_state :: proc(L: ^lua.State) {
	_ = lua.JIT_setmode(L, 0, lua.LUAJIT_MODE_ENGINE | lua.LUAJIT_MODE_OFF)

	for name in ([?]cstring{
		"os",
		"io",
		"ffi",
		"debug",
		"package",
		"jit",
		"coroutine",
		"xpcall",
		"newproxy",
		"require",
		"loadfile",
		"dofile",
		"load",
		"loadstring",
		"print",
	}) {
		lua.pushnil(L)
		lua.setglobal(L, name)
	}

	lua.getglobal(L, "string")
	if lua.type(L, -1) == .TABLE {
		lua.pushnil(L)
		lua.setfield(L, -2, "rep")
	}
	lua.pop(L, 1)

	lua.getglobal(L, "xitdb")
	if lua.type(L, -1) == .TABLE {
		for fn_name in ([?]cstring{
			"open_file",
			"open_buffered_file",
			"remove_file",
			"load_bytecode",
			"file_offset_map",
			"open_memory",
		}) {
			lua.pushnil(L)
			lua.setfield(L, -2, fn_name)
		}
	}
	lua.pop(L, 1)

	_ = lua_sethook(L, _instruction_limit_hook, LUA_MASKCOUNT, 2000)
}

@(export)
LLVMFuzzerTestOneInput :: proc "c" (data: [^]u8, size: uint) -> i32 {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if data == nil || size == 0 || size > 2048 || data[0] == 0x1b {
		return 0
	}

	core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&core)
	if cm, ok := &core.(xitdb.Core_Memory); ok {
		cm.max_size = 256 * 1024
	}

	db, derr := xitdb.database_init(&core, xitdb.sha1_hasher())
	if derr != nil {
		return 0
	}

	alloc_state := _Lua_Alloc_State{limit = LUA_MAX_ALLOC_BYTES}
	L := lua.newstate(_bounded_lua_alloc, &alloc_state)
	if L != nil {
		lua.L_openlibs(L)
		xitdb.lua_open_xitdb(L)
		xitdb.lua_push_database(L, &db)
		lua.setglobal(L, "db")
	} else {
		// Non-GC64 LuaJIT builds reject custom high-address allocators in lua_newstate.
		L = xitdb.lua_new_state(&db)
	}
	if L == nil {
		return 0
	}
	defer lua.close(L)

	_sandbox_state(L)

	if lua.L_loadbufferx(L, data, c.size_t(size), "fuzz", "t") == .OK {
		_ = lua.pcall(L, 0, 0, 0)
	}

	return 0
}
