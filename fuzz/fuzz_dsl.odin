package fuzz_dsl

import "base:runtime"
import xitdb "xitdb:."

@(private = "file")
g_inited: bool
@(private = "file")
g_seed_core: xitdb.Core
@(private = "file")
g_seed_db: xitdb.Database

@(private = "file")
init_seed_db :: proc() {
	if g_inited {
		return
	}
	g_seed_core = xitdb.core_memory_init(runtime.heap_allocator(), reserve_size = 0)
	db, err := xitdb.database_init(&g_seed_core, xitdb.sha1_hasher())
	assert(err == nil)
	g_seed_db = db

	tx := xitdb.tx_init(&g_seed_db, base_moment = nil, track_changes = true, allocator = runtime.heap_allocator())
	defer xitdb.tx_destroy(&tx)
	xitdb.tx_doc(&tx, "seed moment 0")
	xitdb.tx_instant(&tx, 1700000000)
	xitdb.tx_meta(&tx, "author", "fuzzer")
	xitdb.tx_index_on(&tx, "users", "username", "username->id")
	_ = xitdb.tx_put(&tx, `.users["101"].username`, "alice")
	_ = xitdb.tx_put(&tx, `.users["101"].age`, u64(30))
	_ = xitdb.tx_put(&tx, `.users["101"].dept`, "eng")
	_ = xitdb.tx_put(&tx, `#metrics["views"]`, i64(-42))
	_ = xitdb.tx_put(&tx, `$catalog["apple"]`, u64(150))
	_ = xitdb.tx_append(&tx, ".fruits", "apple")
	_ = xitdb.tx_append(&tx, ".fruits", "pear")
	_ = xitdb.tx_put(&tx, ".todos[[0]]", "ship")
	_ = xitdb.tx_insert(&tx, ".todos", 0, "plan")
	_ = xitdb.tx_put(&tx, `.roles%"admin"`, "admin")
	_ = xitdb.tx_put(&tx, `.visitors#%"u1"`, "u1")
	_ = xitdb.tx_put(&tx, `.tags^"odin"`, "odin")
	rep, cerr := xitdb.tx_commit(&tx)
	assert(cerr == nil)
	xitdb.tx_report_destroy(&rep, runtime.heap_allocator())

	tx2 := xitdb.tx_init(&g_seed_db, base_moment = -1, track_changes = true, allocator = runtime.heap_allocator())
	defer xitdb.tx_destroy(&tx2)
	xitdb.tx_doc(&tx2, "seed moment 1")
	xitdb.tx_index_on(&tx2, "users", "username", "username->id")
	_ = xitdb.tx_put(&tx2, `.users["102"].username`, "bob")
	_ = xitdb.tx_put(&tx2, `.users["102"].age`, u64(35))
	_ = xitdb.tx_put(&tx2, `.users["102"].dept`, "ops")
	_ = xitdb.tx_put(&tx2, `.users["101"].age`, u64(31))
	rep2, cerr2 := xitdb.tx_commit(&tx2)
	assert(cerr2 == nil)
	xitdb.tx_report_destroy(&rep2, runtime.heap_allocator())

	g_inited = true
}

@(export)
LLVMFuzzerTestOneInput :: proc "c" (data: [^]u8, size: uint) -> i32 {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if data == nil || size == 0 || size > 4096 {
		return 0
	}

	init_seed_db()

	mode := data[0] % 4
	payload := string(data[1:size])

	switch mode {
	case 0:
		_, _ = xitdb.parse_selector(payload, context.temp_allocator)
		steps, p_err := xitdb.parse_steps(payload, context.temp_allocator)
		if p_err == nil && len(steps) > 0 {
			formatted := xitdb.format_steps(steps, context.temp_allocator)
			steps2, p_err2 := xitdb.parse_steps(formatted, context.temp_allocator)
			assert(p_err2 == nil)
			assert(len(steps2) == len(steps))
			for i in 0 ..< len(steps) {
				assert(steps2[i].kind == steps[i].kind)
				assert(steps2[i].key == steps[i].key)
				assert(steps2[i].index == steps[i].index)
			}
		}
		_, _ = xitdb.select_cursor(&g_seed_db, payload)
		_, _ = xitdb.get_string(&g_seed_db, payload, context.temp_allocator)
		_, _ = xitdb.history_of(&g_seed_db, payload, context.temp_allocator)

	case 1:
		_, _ = xitdb.parse_datalog(payload, context.temp_allocator)
		_, _ = xitdb.query_datalog(&g_seed_db, payload, -1, context.temp_allocator)

	case 2:
		root_rc := xitdb.database_root_cursor(&g_seed_db).read_cursor
		_, _ = xitdb.pull(root_rc, payload, context.temp_allocator)
		if mc, merr := xitdb.select_cursor(&g_seed_db, "@-1"); merr == nil {
			if cur, ok := mc.?; ok {
				_, _ = xitdb.pull(cur, payload, context.temp_allocator)
			}
		}

	case 3:
		seed_bytes := xitdb.core_memory_bytes(&g_seed_core)
		scratch_core := xitdb.core_memory_init_from_bytes(seed_bytes, context.allocator, reserve_size = 0)
		defer xitdb.core_destroy(&scratch_core)
		if cm, ok := &scratch_core.(xitdb.Core_Memory); ok {
			cm.max_size = i64(len(seed_bytes)) + 512 * 1024
		}
		scratch_db, derr := xitdb.database_init(&scratch_core, xitdb.sha1_hasher())
		if derr == nil {
			_, serr := xitdb.transact_script(&scratch_db, payload, context.temp_allocator)
			if serr == nil {
				_, _ = xitdb.diff_moments(&scratch_db, 0, -1, true, context.temp_allocator)
			}
		}
	}

	return 0
}
