package fuzz_wire

import "base:runtime"
import xitdb "xitdb:."

@(export)
LLVMFuzzerTestOneInput :: proc "c" (data: [^]u8, size: uint) -> i32 {
	context = runtime.default_context()
	defer free_all(context.temp_allocator)

	if data == nil || size > 65536 {
		return 0
	}

	buf := make([dynamic]u8, int(size), int(size), context.allocator)
	if size > 0 {
		copy(buf[:], data[:size])
	}

	core: xitdb.Core = xitdb.Core_Memory{
		buf       = buf,
		pos       = 0,
		max_size  = i64(size) + 65536,
		allocator = context.allocator,
	}
	defer xitdb.core_destroy(&core)

	hasher := xitdb.sha1_hasher()
	if size >= 8 && buf[6] == 0 && buf[7] == 32 {
		hasher = xitdb.sha256_hasher()
	}

	_, _ = xitdb.header_read_and_validate(&core, hasher.hash_size)

	db, init_err := xitdb.database_init(&core, hasher)
	if init_err != nil {
		return 0
	}

	_, _ = xitdb.database_read_root_header(&db)
	_, _ = xitdb.database_read_root_slot(&db)
	_, _ = xitdb.database_committed_size(&db)
	_, _ = xitdb.database_replica_state(&db)

	if mc, merr := xitdb.select_cursor(&db, "@-1"); merr == nil {
		if cur, ok := mc.?; ok {
			_, _ = xitdb.pull(cur, "*", context.temp_allocator)
		}
	}
	_, _ = xitdb.diff_moments(&db, 0, -1, true, context.temp_allocator)

	target_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&target_core)
	if tm, ok := &target_core.(xitdb.Core_Memory); ok {
		tm.max_size = 256 * 1024
	}
	_, _ = xitdb.database_compact(&db, &target_core)

	return 0
}
