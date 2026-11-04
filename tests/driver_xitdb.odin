package xitdb_tests

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import xitdb "../xitdb"

// ============================================================================
// Layer 3: Protocol Drivers (`driver_xitdb.odin`)
// ============================================================================
// The only test layer that interacts directly with `xitdb` structs, cursors,
// storage cores, transactions, and wire primitives. Exposes composable,
// single-purpose operations to Layer 2 (`dsl_xitdb.odin`).

Suite_Ctx :: struct {
	t:               ^testing.T,
	backend_kind:    Backend_Kind,
	db_path:         string,
	compact_path:    string,
	offset_map_path: string,
	primary_core:    xitdb.Core,
	primary_db:      xitdb.Database,
	has_primary:     bool,
	replica_core:    xitdb.Core,
	replica_db:      xitdb.Database,
	has_replica:     bool,
	compacted_core:  xitdb.Core,
	compacted_db:    xitdb.Database,
	has_compacted:   bool,
	last_err:        xitdb.Error,
	last_sync_start: i64,
}

Backend_Kind :: enum {
	Memory,
	File,
	Buffered_File,
}

Key_Value :: struct {
	key: string,
	val: string,
}

Key_Int :: struct {
	key: string,
	val: i64,
}

Key_Uint :: struct {
	key: string,
	val: u64,
}

Key_Float :: struct {
	key: string,
	val: f64,
}

Tagged_Text :: struct {
	key:        string,
	text:       string,
	format_tag: string,
}

driver_init_ctx :: proc(t: ^testing.T, backend: Backend_Kind = .Memory) -> Suite_Ctx {
	return Suite_Ctx{
		t            = t,
		backend_kind = backend,
	}
}

driver_destroy_ctx :: proc(ctx: ^Suite_Ctx) {
	if ctx.has_compacted {
		_ = xitdb.core_destroy(&ctx.compacted_core, true)
		ctx.has_compacted = false
	}
	if ctx.has_replica {
		_ = xitdb.core_destroy(&ctx.replica_core, true)
		ctx.has_replica = false
	}
	if ctx.has_primary {
		_ = xitdb.core_destroy(&ctx.primary_core, true)
		ctx.has_primary = false
	}
	if len(ctx.db_path) > 0 {
		_ = os.remove(ctx.db_path)
	}
	if len(ctx.compact_path) > 0 {
		_ = os.remove(ctx.compact_path)
	}
	if len(ctx.offset_map_path) > 0 {
		_ = os.remove(ctx.offset_map_path)
	}
	free_all(context.temp_allocator)
}

@(private = "file")
driver_temp_path :: proc(t: ^testing.T, suffix: string) -> string {
	dir, err := os.temp_directory(context.temp_allocator)
	if err != nil || len(dir) == 0 {
		dir = "."
	}
	return fmt.tprintf("%s/xitdb_atdd_%p_%s", dir, t, suffix)
}

driver_open_primary :: proc(ctx: ^Suite_Ctx, hash_algo: string = "sha1", buffer_size: i64 = 512) {
	hasher: xitdb.Hasher
	if hash_algo == "sha2" || hash_algo == "sha256" {
		hasher = xitdb.sha256_hasher(xitdb.string_to_id("sha2"))
	} else {
		hasher = xitdb.sha1_hasher(xitdb.string_to_id("sha1"))
	}

	switch ctx.backend_kind {
	case .Memory:
		ctx.primary_core = xitdb.core_memory_init()
	case .File:
		ctx.db_path = driver_temp_path(ctx.t, "main.db")
		_ = os.remove(ctx.db_path)
		c, open_err := xitdb.core_file_open(ctx.db_path, {.Read, .Write, .Create, .Trunc}, false)
		testing.expect_value(ctx.t, open_err, nil)
		ctx.primary_core = c
	case .Buffered_File:
		ctx.db_path = driver_temp_path(ctx.t, "buf.db")
		_ = os.remove(ctx.db_path)
		c, open_err := xitdb.core_buffered_file_open(ctx.db_path, buffer_size, {.Read, .Write, .Create, .Trunc}, false)
		testing.expect_value(ctx.t, open_err, nil)
		ctx.primary_core = c
	}
	ctx.has_primary = true

	db, err := xitdb.database_init(&ctx.primary_core, hasher)
	testing.expect_value(ctx.t, err, nil)
	ctx.primary_db = db
}

driver_open_fixture :: proc(ctx: ^Suite_Ctx, relative_path: string) {
	data, read_err := os.read_entire_file(relative_path, context.temp_allocator)
	if read_err != nil {
		// Fallback when test runner working directory is `tests/`
		trimmed := strings.trim_prefix(relative_path, "tests/")
		data, read_err = os.read_entire_file(trimmed, context.temp_allocator)
	}
	testing.expect(ctx.t, read_err == nil, "Failed to read database fixture")
	if read_err != nil do return

	ctx.primary_core = xitdb.core_memory_from_bytes(data)
	ctx.has_primary = true

	db, err := xitdb.database_init(&ctx.primary_core, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, err, nil)
	ctx.primary_db = db
}

driver_active_db :: proc(ctx: ^Suite_Ctx, target: Db_Target = .Primary) -> ^xitdb.Database {
	switch target {
	case .Primary:
		return &ctx.primary_db
	case .Replica:
		return &ctx.replica_db
	case .Compacted:
		return &ctx.compacted_db
	}
	return &ctx.primary_db
}

Db_Target :: enum {
	Primary,
	Replica,
	Compacted,
}

// ----------------------------------------------------------------------------
// Moment & History Operations
// ----------------------------------------------------------------------------

driver_history_count :: proc(ctx: ^Suite_Ctx, target: Db_Target = .Primary) -> i64 {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	history, err := xitdb.read_array_list_init(rc.read_cursor)
	testing.expect_value(ctx.t, err, nil)
	cnt, cerr := xitdb.array_list_count(history)
	testing.expect_value(ctx.t, cerr, nil)
	return cnt
}

driver_committed_size :: proc(ctx: ^Suite_Ctx, target: Db_Target = .Primary) -> i64 {
	db := driver_active_db(ctx, target)
	sz, err := xitdb.database_committed_size(db)
	testing.expect_value(ctx.t, err, nil)
	return sz
}

driver_read_moment_map :: proc(ctx: ^Suite_Ctx, moment_index: i64, target: Db_Target = .Primary) -> xitdb.Read_Hash_Map {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	history, err := xitdb.read_array_list_init(rc.read_cursor)
	testing.expect_value(ctx.t, err, nil)

	mc_maybe, mc_err := xitdb.array_list_get_cursor(history, moment_index)
	testing.expect_value(ctx.t, mc_err, nil)
	mc, ok := mc_maybe.?
	testing.expect(ctx.t, ok, "Expected moment cursor to exist")

	moment, m_err := xitdb.read_hash_map_init(mc)
	testing.expect_value(ctx.t, m_err, nil)
	return moment
}

Moment_Mutation_Op :: union {
	Op_Put_String,
	Op_Put_Int,
	Op_Put_Uint,
	Op_Put_Float,
	Op_Put_Tagged,
	Op_Stream_Tagged,
	Op_Remove_Key,
	Op_Put_Array_List,
	Op_Update_Array_List_Item,
	Op_Slice_Array_List,
	Op_Put_Linked_List,
	Op_Insert_Linked_List,
	Op_Remove_Linked_List,
	Op_Slice_Linked_List,
	Op_Concat_Linked_List,
	Op_Put_Counted_Map,
	Op_Put_Hash_Set,
	Op_Put_Counted_Set,
	Op_Put_Sorted_Map,
	Op_Remove_Sorted_Map,
	Op_Put_Sorted_Set,
	Op_Fail_With,
}

Op_Put_String :: struct {
	key: string,
	val: string,
}

Op_Put_Int :: struct {
	key: string,
	val: i64,
}

Op_Put_Uint :: struct {
	key: string,
	val: u64,
}

Op_Put_Float :: struct {
	key: string,
	val: f64,
}

Op_Put_Tagged :: struct {
	key:        string,
	val:        string,
	format_tag: string,
}

Op_Stream_Tagged :: struct {
	key:        string,
	chunks:     []string,
	format_tag: string,
}

Op_Remove_Key :: struct {
	key: string,
}

Op_Put_Array_List :: struct {
	key:   string,
	items: []string,
}

Op_Update_Array_List_Item :: struct {
	key:   string,
	index: i64,
	val:   string,
}

Op_Slice_Array_List :: struct {
	key:  string,
	size: i64,
}

Op_Put_Linked_List :: struct {
	key:   string,
	items: []string,
}

Op_Insert_Linked_List :: struct {
	key:   string,
	index: i64,
	val:   string,
}

Op_Remove_Linked_List :: struct {
	key:   string,
	index: i64,
}

Op_Slice_Linked_List :: struct {
	key:    string,
	offset: i64,
	size:   i64,
}

Op_Concat_Linked_List :: struct {
	target_key: string,
	source_key: string,
}

Op_Put_Counted_Map :: struct {
	key:     string,
	entries: []Key_Uint,
}

Op_Put_Hash_Set :: struct {
	key:     string,
	members: []string,
}

Op_Put_Counted_Set :: struct {
	key:     string,
	members: []string,
}

Op_Put_Sorted_Map :: struct {
	key:     string,
	entries: []Key_Uint,
}

Op_Remove_Sorted_Map :: struct {
	key:          string,
	keys_to_drop: []string,
}

Op_Put_Sorted_Set :: struct {
	key:     string,
	members: []string,
}

Op_Fail_With :: struct {
	err: xitdb.Xitdb_Error,
}

@(private = "file")
_Moment_Tx_Payload :: struct {
	ops: []Moment_Mutation_Op,
}

@(private = "file")
_execute_moment_ops_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
	payload := (^_Moment_Tx_Payload)(user_data)
	moment := xitdb.write_hash_map_init(cursor^) or_return

	for op in payload.ops {
		switch o in op {
		case Op_Put_String:
			xitdb.hash_map_put(&moment, o.key, o.val) or_return

		case Op_Put_Int:
			xitdb.hash_map_put(&moment, o.key, o.val) or_return

		case Op_Put_Uint:
			xitdb.hash_map_put(&moment, o.key, o.val) or_return

		case Op_Put_Float:
			xitdb.hash_map_put(&moment, o.key, o.val) or_return

		case Op_Put_Tagged:
			xitdb.hash_map_put(&moment, o.key, xitdb.new_tagged_string(o.val, transmute([]u8)o.format_tag)) or_return

		case Op_Stream_Tagged:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			writer := xitdb.cursor_writer(&sc) or_return
			if len(o.format_tag) > 0 {
				writer.format_tag = transmute([]u8)o.format_tag
			}
			for chunk in o.chunks {
				_, w_err := xitdb.cursor_writer_write(&writer, transmute([]u8)chunk)
				if w_err != nil do return w_err
			}
			xitdb.cursor_writer_finish(&writer) or_return

		case Op_Remove_Key:
			removed := xitdb.hash_map_remove(&moment, o.key) or_return
			if !removed {
				return .Key_Not_Found
			}

		case Op_Put_Array_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_array_list_init(lc) or_return
			for item in o.items {
				xitdb.array_list_append(&list, item) or_return
			}

		case Op_Update_Array_List_Item:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_array_list_init(lc) or_return
			xitdb.array_list_put(&list, o.index, o.val) or_return

		case Op_Slice_Array_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_array_list_init(lc) or_return
			xitdb.array_list_slice(&list, o.size) or_return

		case Op_Put_Linked_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_linked_array_list_init(lc) or_return
			for item in o.items {
				xitdb.linked_array_list_append(&list, item) or_return
			}

		case Op_Insert_Linked_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_linked_array_list_init(lc) or_return
			xitdb.linked_array_list_insert(&list, o.index, o.val) or_return

		case Op_Remove_Linked_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_linked_array_list_init(lc) or_return
			xitdb.linked_array_list_remove(&list, o.index) or_return

		case Op_Slice_Linked_List:
			lc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			list := xitdb.write_linked_array_list_init(lc) or_return
			xitdb.linked_array_list_slice(&list, o.offset, o.size) or_return

		case Op_Concat_Linked_List:
			src_slot_maybe := xitdb.hash_map_get_slot(moment.read_hash_map, o.source_key) or_return
			src_slot, has_src := src_slot_maybe.?
			if !has_src do return .Key_Not_Found
			lc := xitdb.hash_map_put_cursor(&moment, o.target_key) or_return
			list := xitdb.write_linked_array_list_init(lc) or_return
			xitdb.linked_array_list_concat(&list, src_slot) or_return

		case Op_Put_Counted_Map:
			mc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			cm := xitdb.write_counted_hash_map_init(mc) or_return
			for entry in o.entries {
				xitdb.hash_map_put(&cm, entry.key, entry.val) or_return
			}

		case Op_Put_Hash_Set:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			hs := xitdb.write_hash_set_init(sc) or_return
			for m in o.members {
				xitdb.hash_set_put(&hs, m) or_return
			}

		case Op_Put_Counted_Set:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			cs := xitdb.write_counted_hash_set_init(sc) or_return
			for m in o.members {
				xitdb.hash_set_put(&cs, m) or_return
			}

		case Op_Put_Sorted_Map:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			sm := xitdb.write_sorted_map_init(sc) or_return
			for entry in o.entries {
				xitdb.sorted_map_put(&sm, entry.key, entry.val) or_return
			}

		case Op_Remove_Sorted_Map:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			sm := xitdb.write_sorted_map_init(sc) or_return
			for k in o.keys_to_drop {
				removed := xitdb.sorted_map_remove(&sm, k) or_return
				if !removed do return .Key_Not_Found
			}

		case Op_Put_Sorted_Set:
			sc := xitdb.hash_map_put_cursor(&moment, o.key) or_return
			ss := xitdb.write_sorted_set_init(sc) or_return
			for m in o.members {
				xitdb.sorted_set_put(&ss, m) or_return
			}

		case Op_Fail_With:
			return o.err
		}
	}
	return nil
}

driver_commit_moment :: proc(ctx: ^Suite_Ctx, base_moment: Maybe(i64), ops: []Moment_Mutation_Op, target: Db_Target = .Primary) -> xitdb.Error {
	payload := _Moment_Tx_Payload{ops = ops}
	return driver_run_moment_tx(ctx, base_moment, _execute_moment_ops_cb, &payload, target)
}

driver_run_moment_tx :: proc(ctx: ^Suite_Ctx, base_moment: Maybe(i64), cb: xitdb.Context_Function, user_data: rawptr = nil, target: Db_Target = .Primary) -> xitdb.Error {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	history, err := xitdb.write_array_list_init(rc)
	if err != nil {
		ctx.last_err = err
		return err
	}

	base_slot := xitdb.Slot{}
	if bm_idx, has_base := base_moment.?; has_base {
		slot_maybe, s_err := xitdb.array_list_get_slot(history, bm_idx)
		if s_err != nil {
			ctx.last_err = s_err
			return s_err
		}
		if s, ok := slot_maybe.?; ok {
			base_slot = s
		}
	}

	tx_err := xitdb.array_list_append_context(&history, base_slot, cb, user_data)
	ctx.last_err = tx_err
	return tx_err
}

driver_slice_history :: proc(ctx: ^Suite_Ctx, keep_count: i64) {
	rc := xitdb.database_root_cursor(&ctx.primary_db)
	history, err := xitdb.write_array_list_init(rc)
	testing.expect_value(ctx.t, err, nil)
	s_err := xitdb.array_list_slice(&history, keep_count)
	testing.expect_value(ctx.t, s_err, nil)
}

// ----------------------------------------------------------------------------
// Compaction & Replication Operations
// ----------------------------------------------------------------------------

driver_sync_to_replica :: proc(ctx: ^Suite_Ctx) {
	if !ctx.has_replica {
		ctx.replica_core = xitdb.core_memory_init()
		ctx.has_replica = true
		rep_db, err := xitdb.database_init(&ctx.replica_core, xitdb.sha1_hasher())
		testing.expect_value(ctx.t, err, nil)
		ctx.replica_db = rep_db
	}

	rep_state, rs_err := xitdb.database_replica_state(&ctx.replica_db)
	testing.expect_value(ctx.t, rs_err, nil)

	start_offset, st_err := xitdb.database_replication_start(&ctx.primary_db, rep_state)
	testing.expect_value(ctx.t, st_err, nil)
	ctx.last_sync_start = start_offset

	committed_end, ce_err := xitdb.database_committed_size(&ctx.primary_db)
	testing.expect_value(ctx.t, ce_err, nil)

	payload, rd_err := xitdb.database_read_committed_bytes(&ctx.primary_db, start_offset, committed_end, context.temp_allocator)
	testing.expect_value(ctx.t, rd_err, nil)

	ap_err := xitdb.database_apply_replicated_bytes(&ctx.replica_db, start_offset, payload)
	testing.expect_value(ctx.t, ap_err, nil)
}

driver_compact_primary :: proc(ctx: ^Suite_Ctx, use_file_offset_map: bool = false) {
	if ctx.backend_kind == .Memory && !use_file_offset_map {
		ctx.compacted_core = xitdb.core_memory_init()
		ctx.has_compacted = true

		offset_map: xitdb.Offset_Map = xitdb.memory_offset_map_init()
		defer xitdb.offset_map_destroy(&offset_map)

		comp_db, err := xitdb.database_compact(&ctx.primary_db, &ctx.compacted_core, &offset_map)
		testing.expect_value(ctx.t, err, nil)
		ctx.compacted_db = comp_db
		return
	}

	if ctx.has_compacted {
		_ = xitdb.core_destroy(&ctx.compacted_core, true)
	}
	ctx.compact_path = driver_temp_path(ctx.t, "compact.db")
	_ = os.remove(ctx.compact_path)
	comp_core, c_err := xitdb.core_file_open(ctx.compact_path, {.Read, .Write, .Create, .Trunc}, false)
	testing.expect_value(ctx.t, c_err, nil)
	ctx.compacted_core = comp_core
	ctx.has_compacted = true

	if use_file_offset_map {
		ctx.offset_map_path = driver_temp_path(ctx.t, "om.db")
		_ = os.remove(ctx.offset_map_path)
		{
			om_core, om_err := xitdb.core_file_open(ctx.offset_map_path, {.Read, .Write, .Create, .Trunc}, false)
			testing.expect_value(ctx.t, om_err, nil)
			defer _ = xitdb.core_destroy(&om_core, true)

			om_db, db_err := xitdb.database_init(&om_core, xitdb.sha1_hasher())
			testing.expect_value(ctx.t, db_err, nil)
			om_rc := xitdb.database_root_cursor(&om_db)
			file_om, fom_err := xitdb.file_offset_map_init(om_rc)
			testing.expect_value(ctx.t, fom_err, nil)
			offset_map: xitdb.Offset_Map = file_om

			comp_db, comp_err := xitdb.database_compact(&ctx.primary_db, &ctx.compacted_core, &offset_map)
			testing.expect_value(ctx.t, comp_err, nil)
			ctx.compacted_db = comp_db
		}
		_ = os.remove(ctx.offset_map_path)
	} else {
		offset_map: xitdb.Offset_Map = xitdb.memory_offset_map_init()
		defer xitdb.offset_map_destroy(&offset_map)
		comp_db, comp_err := xitdb.database_compact(&ctx.primary_db, &ctx.compacted_core, &offset_map)
		testing.expect_value(ctx.t, comp_err, nil)
		ctx.compacted_db = comp_db
	}
}

// ----------------------------------------------------------------------------
// Granular Assertions on Moments & Collections
// ----------------------------------------------------------------------------

@(private = "file")
_moment_require_cursor :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, target: Db_Target = .Primary) -> (xitdb.Read_Cursor, bool) {
	moment := driver_read_moment_map(ctx, moment_idx, target)
	cur_maybe, err := xitdb.hash_map_get_cursor(moment, key)
	testing.expect_value(ctx.t, err, nil)
	cur, ok := cur_maybe.?
	testing.expectf(ctx.t, ok, "Expected key %q in moment %d", key, moment_idx)
	return cur, ok
}

driver_assert_string_slice :: proc(t: ^testing.T, actual: []string, expected: []string) {
	testing.expect_value(t, len(actual), len(expected))
	for exp, i in expected {
		if i < len(actual) {
			testing.expect_value(t, actual[i], exp)
		}
	}
}

driver_assert_moment_string :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected: string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return

	actual, r_err := xitdb.cursor_read_string(cur, 4096, context.temp_allocator)
	testing.expect_value(ctx.t, r_err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_moment_slot_tag :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_tag: xitdb.Tag, target: Db_Target = .Primary) {
	moment := driver_read_moment_map(ctx, moment_idx, target)
	slot_maybe, err := xitdb.hash_map_get_slot(moment, key)
	testing.expect_value(ctx.t, err, nil)
	slot, ok := slot_maybe.?
	testing.expectf(ctx.t, ok, "Expected slot for key %q in moment %d", key, moment_idx)
	if !ok do return
	testing.expect_value(ctx.t, slot.tag, expected_tag)
}

driver_assert_moment_key_absent :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, target: Db_Target = .Primary) {
	moment := driver_read_moment_map(ctx, moment_idx, target)
	cur_maybe, err := xitdb.hash_map_get_cursor(moment, key)
	testing.expect_value(ctx.t, err, nil)
	testing.expectf(ctx.t, cur_maybe == nil, "Expected key %q to be absent in moment %d", key, moment_idx)
}

driver_assert_moment_int :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected: i64, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	actual, r_err := xitdb.cursor_read_int(cur)
	testing.expect_value(ctx.t, r_err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_moment_uint :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected: u64, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	actual, r_err := xitdb.cursor_read_uint(cur)
	testing.expect_value(ctx.t, r_err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_moment_float :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected: f64, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	actual, r_err := xitdb.cursor_read_float(cur)
	testing.expect_value(ctx.t, r_err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_moment_tagged_text :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_text: string, expected_tag: string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	obj, r_err := xitdb.cursor_read_bytes_object(cur, 4096, context.temp_allocator)
	testing.expect_value(ctx.t, r_err, nil)
	testing.expect_value(ctx.t, string(obj.value), expected_text)
	testing.expect_value(ctx.t, string(obj.format_tag), expected_tag)

	// Dual-representation check: also verify streaming reader produces identical bytes
	reader, sr_err := xitdb.cursor_reader(cur)
	testing.expect_value(ctx.t, sr_err, nil)
	streamed, sa_err := xitdb.cursor_reader_read_all(&reader, context.temp_allocator)
	testing.expect_value(ctx.t, sa_err, nil)
	testing.expect_value(ctx.t, string(streamed), expected_text)
}

driver_assert_moment_array_list :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_items: []string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	list, l_err := xitdb.read_array_list_init(cur)
	testing.expect_value(ctx.t, l_err, nil)

	cnt, c_err := xitdb.array_list_count(list)
	testing.expect_value(ctx.t, c_err, nil)
	testing.expect_value(ctx.t, cnt, i64(len(expected_items)))

	for expected, idx in expected_items {
		item_cur_maybe, ic_err := xitdb.array_list_get_cursor(list, i64(idx))
		testing.expect_value(ctx.t, ic_err, nil)
		actual, s_err := xitdb.cursor_read_string(item_cur_maybe.?, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, s_err, nil)
		testing.expect_value(ctx.t, actual, expected)
	}
}

driver_assert_moment_nested_map_uint :: proc(ctx: ^Suite_Ctx, moment_idx: i64, list_key: string, list_index: i64, map_key: string, expected: u64, target: Db_Target = .Primary) {
	list_cur, ok := _moment_require_cursor(ctx, moment_idx, list_key, target)
	if !ok do return
	list, l_err := xitdb.read_array_list_init(list_cur)
	testing.expect_value(ctx.t, l_err, nil)

	elem_cur_maybe, ec_err := xitdb.array_list_get_cursor(list, list_index)
	testing.expect_value(ctx.t, ec_err, nil)
	nested_map, nm_err := xitdb.read_hash_map_init(elem_cur_maybe.?)
	testing.expect_value(ctx.t, nm_err, nil)

	val_cur_maybe, vc_err := xitdb.hash_map_get_cursor(nested_map, map_key)
	testing.expect_value(ctx.t, vc_err, nil)
	actual, u_err := xitdb.cursor_read_uint(val_cur_maybe.?)
	testing.expect_value(ctx.t, u_err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_moment_linked_list :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_items: []string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	list, l_err := xitdb.read_linked_array_list_init(cur)
	testing.expect_value(ctx.t, l_err, nil)

	cnt, c_err := xitdb.linked_array_list_count(list)
	testing.expect_value(ctx.t, c_err, nil)
	testing.expect_value(ctx.t, cnt, i64(len(expected_items)))

	for expected, idx in expected_items {
		item_cur_maybe, ic_err := xitdb.linked_array_list_get_cursor(list, i64(idx))
		testing.expect_value(ctx.t, ic_err, nil)
		actual, s_err := xitdb.cursor_read_string(item_cur_maybe.?, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, s_err, nil)
		testing.expect_value(ctx.t, actual, expected)
	}

	// Cross-cutting invariant: B-Tree iterator yields identical sequence as index lookup
	it, it_err := xitdb.linked_array_list_iterator(list)
	testing.expect_value(ctx.t, it_err, nil)
	iter_idx := 0
	for {
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		c, has_c := c_maybe.?
		if !has_c do break
		val, _ := xitdb.cursor_read_string(c, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, val, expected_items[iter_idx])
		iter_idx += 1
	}
	testing.expect_value(ctx.t, iter_idx, len(expected_items))
}

driver_assert_moment_counted_map_count :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	cm, cm_err := xitdb.read_counted_hash_map_init(cur)
	testing.expect_value(ctx.t, cm_err, nil)
	cnt, cnt_err := xitdb.counted_hash_map_count(cm)
	testing.expect_value(ctx.t, cnt_err, nil)
	testing.expect_value(ctx.t, cnt, expected_count)
}

driver_assert_moment_hash_set_contains :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_members: []string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	hs, hs_err := xitdb.read_hash_set_init(cur)
	testing.expect_value(ctx.t, hs_err, nil)
	for m in expected_members {
		m_cur_maybe, m_err := xitdb.hash_set_get_cursor(hs, m)
		testing.expect_value(ctx.t, m_err, nil)
		testing.expectf(ctx.t, m_cur_maybe != nil, "Expected member %q in HashSet %q", m, key)
		// Verify key text round-trips
		actual_key, k_err := xitdb.cursor_read_string(m_cur_maybe.?, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, k_err, nil)
		testing.expect_value(ctx.t, actual_key, m)
	}
}

driver_assert_moment_counted_set :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64, expected_members: []string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	cs, cs_err := xitdb.read_counted_hash_set_init(cur)
	testing.expect_value(ctx.t, cs_err, nil)
	cnt, cnt_err := xitdb.counted_hash_set_count(cs)
	testing.expect_value(ctx.t, cnt_err, nil)
	testing.expect_value(ctx.t, cnt, expected_count)

	for m in expected_members {
		m_cur_maybe, m_err := xitdb.hash_set_get_cursor(cs.read_hash_set, m)
		testing.expect_value(ctx.t, m_err, nil)
		testing.expectf(ctx.t, m_cur_maybe != nil, "Expected member %q in CountedHashSet %q", m, key)
	}
}

driver_assert_moment_sorted_set :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_sorted_members: []string, target: Db_Target = .Primary) {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return
	ss, ss_err := xitdb.read_sorted_set_init(cur)
	testing.expect_value(ctx.t, ss_err, nil)

	cnt, cnt_err := xitdb.sorted_set_count(ss)
	testing.expect_value(ctx.t, cnt_err, nil)
	testing.expect_value(ctx.t, cnt, i64(len(expected_sorted_members)))

	for m, idx in expected_sorted_members {
		contains, c_err := xitdb.sorted_set_contains(ss, m)
		testing.expect_value(ctx.t, c_err, nil)
		testing.expect(ctx.t, contains, "Expected SortedSet to contain member")

		rk, rk_err := xitdb.sorted_set_rank(ss, m)
		testing.expect_value(ctx.t, rk_err, nil)
		testing.expect_value(ctx.t, rk, i64(idx))

		idx_kv_maybe, ic_err := xitdb.sorted_set_get_index_kv_pair(ss, i64(idx), context.temp_allocator)
		testing.expect_value(ctx.t, ic_err, nil)
		actual_m, m_err := xitdb.cursor_read_string(idx_kv_maybe.?.key_cursor, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, m_err, nil)
		testing.expect_value(ctx.t, actual_m, m)
	}
}

driver_assert_moment_sorted_map :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64, target: Db_Target = .Primary) -> xitdb.Read_Sorted_Map {
	cur, ok := _moment_require_cursor(ctx, moment_idx, key, target)
	if !ok do return {}
	sm, sm_err := xitdb.read_sorted_map_init(cur)
	testing.expect_value(ctx.t, sm_err, nil)

	cnt, cnt_err := xitdb.sorted_map_count(sm)
	testing.expect_value(ctx.t, cnt_err, nil)
	testing.expect_value(ctx.t, cnt, expected_count)

	// Cross-cutting invariant: Sorted_Map iterator always yields keys in strict lexicographical order
	it, it_err := xitdb.sorted_map_iterator(sm)
	testing.expect_value(ctx.t, it_err, nil)
	prev := ""
	iter_count: i64 = 0
	for {
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		c, ok := c_maybe.?
		if !ok do break
		kv, kv_err := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		testing.expect_value(ctx.t, kv_err, nil)
		k_str, k_err := xitdb.cursor_read_string(kv.key_cursor, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, k_err, nil)
		if prev != "" {
			testing.expectf(ctx.t, prev < k_str, "SortedMap invariant violated: %q >= %q", prev, k_str)
		}
		// Verify rank(k_str) == iter_count and get_index_kv_pair(iter_count) == k_str
		rk, rk_err := xitdb.sorted_map_rank(sm, k_str)
		testing.expect_value(ctx.t, rk_err, nil)
		testing.expect_value(ctx.t, rk, iter_count)

		idx_kv_maybe, idx_err := xitdb.sorted_map_get_index_kv_pair(sm, iter_count, context.temp_allocator)
		testing.expect_value(ctx.t, idx_err, nil)
		idx_k, _ := xitdb.cursor_read_string(idx_kv_maybe.?.key_cursor, 4096, context.temp_allocator)
		testing.expect_value(ctx.t, idx_k, k_str)

		prev = k_str
		iter_count += 1
	}
	testing.expect_value(ctx.t, iter_count, expected_count)
	return sm
}

// ----------------------------------------------------------------------------
// Extended Driver Operations: Freeze, Lifetimes, Range Iterators, Divergence,
// Cycles, Top-Level Collections & Corrupt Wire Guards
// ----------------------------------------------------------------------------

driver_open_primary_with_file_id :: proc(ctx: ^Suite_Ctx, file_id: u64, hash_algo: string = "sha1") {
	ctx.primary_core = xitdb.core_memory_init()
	ctx.has_primary = true
	h := xitdb.sha1_hasher(xitdb.string_to_id(hash_algo), file_id)
	db, err := xitdb.database_init(&ctx.primary_core, h)
	testing.expect_value(ctx.t, err, nil)
	ctx.primary_db = db
}

driver_write_root_uint :: proc(ctx: ^Suite_Ctx, val: u64, target: Db_Target = .Primary) {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	err := xitdb.cursor_write(&rc, val)
	testing.expect_value(ctx.t, err, nil)
}

driver_write_root_string :: proc(ctx: ^Suite_Ctx, val: string, target: Db_Target = .Primary) {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	err := xitdb.cursor_write(&rc, val)
	testing.expect_value(ctx.t, err, nil)
}

driver_assert_root_uint :: proc(ctx: ^Suite_Ctx, expected: u64, target: Db_Target = .Primary) {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	actual, err := xitdb.cursor_read_uint(rc.read_cursor)
	testing.expect_value(ctx.t, err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_root_string :: proc(ctx: ^Suite_Ctx, expected: string, target: Db_Target = .Primary) {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	actual, err := xitdb.cursor_read_string(rc.read_cursor, 4096, context.temp_allocator)
	testing.expect_value(ctx.t, err, nil)
	testing.expect_value(ctx.t, actual, expected)
}

driver_assert_root_empty :: proc(ctx: ^Suite_Ctx, target: Db_Target = .Primary) {
	db := driver_active_db(ctx, target)
	rc := xitdb.database_root_cursor(db)
	slot, err := xitdb.cursor_slot(rc.read_cursor)
	testing.expect_value(ctx.t, err, nil)
	testing.expect(ctx.t, xitdb.slot_empty(slot), "Expected root slot to be empty")
}

driver_verify_replication_divergence :: proc(primary: ^Suite_Ctx, replica_holder: ^Suite_Ctx, expect_delta_rejection: bool) {
	rep_state, rs_err := xitdb.database_replica_state(&replica_holder.replica_db)
	testing.expect_value(primary.t, rs_err, nil)

	start_offset, st_err := xitdb.database_replication_start(&primary.primary_db, rep_state)
	testing.expect_value(primary.t, st_err, nil)
	testing.expect_value(primary.t, start_offset, i64(0))

	if expect_delta_rejection {
		rep_size := rep_state.committed_size
		p_size, _ := xitdb.database_committed_size(&primary.primary_db)
		bad_delta, _ := xitdb.database_read_committed_bytes(&primary.primary_db, rep_size, p_size, context.temp_allocator)
		reject_err := xitdb.database_apply_replicated_bytes(&replica_holder.replica_db, rep_size, bad_delta)
		testing.expect_value(primary.t, reject_err, xitdb.Xitdb_Error.Invalid_Database)
	}
}

// Exercise mid-transaction `database_freeze` on both collection slots and streaming bytes
driver_verify_freeze_protection_and_survival :: proc(ctx: ^Suite_Ctx, initial_val: i64, post_freeze_val: i64, stream_len: int) {
	Freeze_State :: struct {
		ctx:             ^Suite_Ctx,
		initial_val:     i64,
		post_freeze_val: i64,
		stream_len:      int,
		frozen_bytes_rc: xitdb.Read_Cursor,
	}
	state := Freeze_State{
		ctx             = ctx,
		initial_val     = initial_val,
		post_freeze_val = post_freeze_val,
		stream_len      = stream_len,
	}

	cb1 :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		st := (^Freeze_State)(user_data)
		t := st.ctx.t
		m := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&m, "v", st.initial_val) or_return

		child_cur := xitdb.hash_map_put_cursor(&m, "child") or_return
		child := xitdb.write_hash_map_init(child_cur) or_return
		xitdb.hash_map_put(&child, "v", st.initial_val + 1) or_return

		frozen_snap, _ := xitdb.read_hash_map_init(xitdb.Read_Cursor{
			slot_ptr = m.cursor.slot_ptr,
			db       = cursor.db,
		})

		// Freeze everything written so far in this transaction
		xitdb.database_freeze(cursor.db) or_return

		// Writing through the pre-freeze child cursor must fail with .Frozen_Slot
		frozen_err := xitdb.hash_map_put(&child, "v", i64(999))
		testing.expect_value(t, frozen_err, xitdb.Xitdb_Error.Frozen_Slot)

		// Writing through `m` (the root of the moment) triggers copy-on-write
		xitdb.hash_map_put(&m, "v", st.post_freeze_val) or_return
		new_child_cur := xitdb.hash_map_put_cursor(&m, "child") or_return
		new_child := xitdb.write_hash_map_init(new_child_cur) or_return
		xitdb.hash_map_put(&new_child, "v", st.post_freeze_val + 1) or_return

		// Verify the frozen snapshot still reads `initial_val`
		fv_cur_maybe, _ := xitdb.hash_map_get_cursor(frozen_snap, "v")
		fv, _ := xitdb.cursor_read_int(fv_cur_maybe.?)
		testing.expect_value(t, fv, st.initial_val)

		fc_cur_maybe, _ := xitdb.hash_map_get_cursor(frozen_snap, "child")
		fc_map, _ := xitdb.read_hash_map_init(fc_cur_maybe.?)
		fcv_cur_maybe, _ := xitdb.hash_map_get_cursor(fc_map, "v")
		fcv, _ := xitdb.cursor_read_int(fcv_cur_maybe.?)
		testing.expect_value(t, fcv, st.initial_val + 1)

		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb1, &state), nil)

	// Now test freezing a streaming writer, then aborting the transaction:
	// frozen bytes must survive rollback!
	cb2 :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		st := (^Freeze_State)(user_data)
		t := st.ctx.t
		writer := xitdb.cursor_writer(cursor) or_return
		zeros := make([]u8, st.stream_len, context.temp_allocator)
		_, _ = xitdb.cursor_writer_write(&writer, zeros)
		xitdb.cursor_writer_finish(&writer) or_return

		st.frozen_bytes_rc = xitdb.Read_Cursor{
			slot_ptr = cursor.slot_ptr,
			db       = cursor.db,
		}
		xitdb.database_freeze(cursor.db) or_return

		// Attempting to mutate or finish the frozen writer must return .Frozen_Bytes
		_ = xitdb.cursor_writer_seek_to(&writer, 0)
		_, w_err := xitdb.cursor_writer_write(&writer, []u8{99})
		testing.expect_value(t, w_err, xitdb.Xitdb_Error.Frozen_Bytes)
		f_err := xitdb.cursor_writer_finish(&writer)
		testing.expect_value(t, f_err, xitdb.Xitdb_Error.Frozen_Bytes)

		// Abort transaction intentionally
		return .Write_Failed
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb2, &state), xitdb.Xitdb_Error.Write_Failed)

	// Verify frozen bytes remain readable even after the transaction rolled back
	surviving_bytes, sb_err := xitdb.cursor_read_bytes(state.frozen_bytes_rc, 4096, context.temp_allocator)
	testing.expect_value(ctx.t, sb_err, nil)
	testing.expect_value(ctx.t, len(surviving_bytes), stream_len)
}

// Exercise `.Nested_Top_Level_Write` and `.Expired_Transaction` guards
driver_verify_expired_and_nested_transaction_guards :: proc(ctx: ^Suite_Ctx) {
	rc := xitdb.database_root_cursor(&ctx.primary_db)
	history, err := xitdb.write_array_list_init(rc)
	testing.expect_value(ctx.t, err, nil)

	Guard_State :: struct {
		ctx:            ^Suite_Ctx,
		history:        ^xitdb.Write_Array_List,
		escaped_map:    xitdb.Write_Hash_Map,
		escaped_writer: xitdb.Cursor_Writer,
	}
	st := Guard_State{ctx = ctx, history = &history}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Guard_State)(user_data)
		t := s.ctx.t
		m := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&m, "v", i64(1)) or_return
		s.escaped_map = m

		bc := xitdb.hash_map_put_cursor(&m, "bytes") or_return
		w := xitdb.cursor_writer(&bc) or_return
		_, _ = xitdb.cursor_writer_write(&w, []u8{1, 2, 3, 4})
		xitdb.cursor_writer_finish(&w) or_return
		s.escaped_writer = w

		// Attempting a top-level write on `history` inside an active root transaction must fail
		nested_err1 := xitdb.array_list_append(s.history, i64(999))
		testing.expect_value(t, nested_err1, xitdb.Xitdb_Error.Nested_Top_Level_Write)

		nested_err2 := xitdb.array_list_slice(s.history, 0)
		testing.expect_value(t, nested_err2, xitdb.Xitdb_Error.Nested_Top_Level_Write)

		return nil
	}

	testing.expect_value(ctx.t, xitdb.array_list_append_context(&history, xitdb.Slot{}, cb, &st), nil)

	// Using escaped cursors/writers after transaction commits must fail with .Expired_Transaction
	exp_err1 := xitdb.hash_map_put(&st.escaped_map, "v", i64(999))
	testing.expect_value(ctx.t, exp_err1, xitdb.Xitdb_Error.Expired_Transaction)

	_, exp_err2 := xitdb.cursor_writer_write(&st.escaped_writer, []u8{1})
	testing.expect_value(ctx.t, exp_err2, xitdb.Xitdb_Error.Expired_Transaction)

	exp_err3 := xitdb.cursor_writer_finish(&st.escaped_writer)
	testing.expect_value(ctx.t, exp_err3, xitdb.Xitdb_Error.Expired_Transaction)
}

@(private = "file")
_assert_range_iterator_suffix :: proc(t: ^testing.T, it: ^xitdb.Cursor_Iterator, resolved_start: i64, total_count: i64) {
	expected_idx := resolved_start
	for {
		c_maybe, n_err := xitdb.cursor_iterator_next(it)
		testing.expect_value(t, n_err, nil)
		c, ok := c_maybe.?
		if !ok do break
		actual, _ := xitdb.cursor_read_string(c, 64, context.temp_allocator)
		expected_str := fmt.tprintf("item-%03d", expected_idx)
		testing.expect_value(t, actual, expected_str)
		expected_idx += 1
	}
	testing.expect_value(t, expected_idx, total_count)
}

// Verify `iterator_from` on Array_List and Linked_Array_List for positive, negative, and out-of-bounds indices
driver_verify_indexed_range_iterators :: proc(ctx: ^Suite_Ctx, moment_idx: i64, array_key: string, linked_key: string, total_count: i64, start_indices: []i64, out_of_bounds_indices: []i64) {
	al_cur, ok_al := _moment_require_cursor(ctx, moment_idx, array_key)
	ll_cur, ok_ll := _moment_require_cursor(ctx, moment_idx, linked_key)
	if !ok_al || !ok_ll do return

	al, _ := xitdb.read_array_list_init(al_cur)
	ll, _ := xitdb.read_linked_array_list_init(ll_cur)

	for start in start_indices {
		resolved := start if start >= 0 else total_count + start

		it_al, err_al := xitdb.array_list_iterator_from(al, start)
		testing.expect_value(ctx.t, err_al, nil)
		_assert_range_iterator_suffix(ctx.t, &it_al, resolved, total_count)

		it_ll, err_ll := xitdb.linked_array_list_iterator_from(ll, start)
		testing.expect_value(ctx.t, err_ll, nil)
		_assert_range_iterator_suffix(ctx.t, &it_ll, resolved, total_count)
	}

	for oob in out_of_bounds_indices {
		it_al, err1 := xitdb.array_list_iterator_from(al, oob)
		testing.expect_value(ctx.t, err1, nil)
		c1, _ := xitdb.cursor_iterator_next(&it_al)
		testing.expect(ctx.t, c1 == nil, "Expected empty Array_List iterator for out-of-bounds start")

		it_ll, err2 := xitdb.linked_array_list_iterator_from(ll, oob)
		testing.expect_value(ctx.t, err2, nil)
		c2, _ := xitdb.cursor_iterator_next(&it_ll)
		testing.expect(ctx.t, c2 == nil, "Expected empty Linked_Array_List iterator for out-of-bounds start")
	}
}

// Verify Sorted_Map lower-bound key iteration (`iterator_from_string`) and index iteration (`iterator_from_index`)
driver_verify_sorted_map_range_iterators :: proc(ctx: ^Suite_Ctx, moment_idx: i64, map_key: string, lower_bound_key: string, expected_first_key: string, start_index: i64, expected_index_key: string) {
	sm_cur, ok := _moment_require_cursor(ctx, moment_idx, map_key)
	if !ok do return
	sm, _ := xitdb.read_sorted_map_init(sm_cur)

	// Lower-bound key iterator
	{
		it, err := xitdb.sorted_map_iterator_from_string(sm, lower_bound_key)
		testing.expect_value(ctx.t, err, nil)
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		kv, _ := xitdb.cursor_read_kv_pair(c_maybe.?, context.temp_allocator)
		actual_key, _ := xitdb.cursor_read_string(kv.key_cursor, 64, context.temp_allocator)
		testing.expect_value(ctx.t, actual_key, expected_first_key)
	}

	// Start index iterator (supports negative index too)
	{
		it, err := xitdb.sorted_map_iterator_from_index(sm, start_index)
		testing.expect_value(ctx.t, err, nil)
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		kv, _ := xitdb.cursor_read_kv_pair(c_maybe.?, context.temp_allocator)
		actual_key, _ := xitdb.cursor_read_string(kv.key_cursor, 64, context.temp_allocator)
		testing.expect_value(ctx.t, actual_key, expected_index_key)
	}
}

// Create cyclic self-references and mutual map references in a new moment
driver_commit_cyclic_moment :: proc(ctx: ^Suite_Ctx, base_moment: i64) {
	cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		// Self-reference: moment["self"] -> moment
		m_slot := xitdb.hash_map_slot(moment.read_hash_map) or_return
		xitdb.hash_map_put(&moment, "self", m_slot) or_return

		// Cyclic list: cyclic_list[0] -> cyclic_list
		cl_cur := xitdb.hash_map_put_cursor(&moment, "cyclic-list") or_return
		cl := xitdb.write_array_list_init(cl_cur) or_return
		cl_slot := xitdb.array_list_slot(cl.read_array_list) or_return
		xitdb.array_list_append(&cl, cl_slot) or_return

		// Mutually recursive maps: map_a["map-b"] -> map_b AND map_b["map-a"] -> map_a
		ma_cur := xitdb.hash_map_put_cursor(&moment, "map-a") or_return
		ma := xitdb.write_hash_map_init(ma_cur) or_return
		mb_cur := xitdb.hash_map_put_cursor(&moment, "map-b") or_return
		mb := xitdb.write_hash_map_init(mb_cur) or_return

		mb_slot := xitdb.hash_map_slot(mb.read_hash_map) or_return
		xitdb.hash_map_put(&ma, "map-b", mb_slot) or_return

		ma_slot := xitdb.hash_map_slot(ma.read_hash_map) or_return
		xitdb.hash_map_put(&mb, "map-a", ma_slot) or_return
		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, base_moment, cb, nil), nil)
}

driver_assert_compacted_cycles_preserve_identity :: proc(ctx: ^Suite_Ctx, moment_idx: i64) {
	moment := driver_read_moment_map(ctx, moment_idx, .Compacted)
	moment_slot, _ := xitdb.hash_map_slot(moment)

	self_slot_maybe, _ := xitdb.hash_map_get_slot(moment, "self")
	testing.expect_value(ctx.t, self_slot_maybe.?, moment_slot)

	cl_cur_maybe, _ := xitdb.hash_map_get_cursor(moment, "cyclic-list")
	cl, _ := xitdb.read_array_list_init(cl_cur_maybe.?)
	cl_slot, _ := xitdb.array_list_slot(cl)
	cl_elem0_slot_maybe, _ := xitdb.array_list_get_slot(cl, 0)
	testing.expect_value(ctx.t, cl_elem0_slot_maybe.?, cl_slot)

	ma_cur_maybe, _ := xitdb.hash_map_get_cursor(moment, "map-a")
	ma, _ := xitdb.read_hash_map_init(ma_cur_maybe.?)
	ma_slot, _ := xitdb.hash_map_slot(ma)

	mb_cur_maybe, _ := xitdb.hash_map_get_cursor(ma, "map-b")
	mb, _ := xitdb.read_hash_map_init(mb_cur_maybe.?)
	ma_back_slot_maybe, _ := xitdb.hash_map_get_slot(mb, "map-a")
	testing.expect_value(ctx.t, ma_back_slot_maybe.?, ma_slot)
}

driver_verify_top_level_hash_map_and_linked_list :: proc(ctx: ^Suite_Ctx) {
	// Top-level Hash_Map root
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

		m, err := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))
		testing.expect_value(ctx.t, err, nil)
		testing.expect_value(ctx.t, xitdb.hash_map_put(&m, "foo", "foo_val"), nil)
		testing.expect_value(ctx.t, xitdb.hash_map_put(&m, "bar", "bar_val"), nil)

		// Every top-level write is its own transaction, so a nested cursor returned by
		// `hash_map_put_cursor` on a top-level map expires immediately
		inner_cur, ic_err := xitdb.hash_map_put_cursor(&m, "inner")
		testing.expect_value(ctx.t, ic_err, nil)
		_, exp_err := xitdb.write_hash_map_init(inner_cur)
		testing.expect_value(ctx.t, exp_err, xitdb.Xitdb_Error.Expired_Transaction)

		// Compacting a top-level Hash_Map root preserves all keys
		comp_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&comp_core)
		comp_db, c_err := xitdb.database_compact(&db, &comp_core)
		testing.expect_value(ctx.t, c_err, nil)

		rm, _ := xitdb.read_hash_map_init(xitdb.database_root_cursor(&comp_db).read_cursor)
		fc_maybe, _ := xitdb.hash_map_get_cursor(rm, "foo")
		f_val, _ := xitdb.cursor_read_string(fc_maybe.?, 64, context.temp_allocator)
		testing.expect_value(ctx.t, f_val, "foo_val")
	}

	// Top-level Linked_Array_List root
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

		ll, err := xitdb.write_linked_array_list_init(xitdb.database_root_cursor(&db))
		testing.expect_value(ctx.t, err, nil)
		testing.expect_value(ctx.t, xitdb.linked_array_list_append(&ll, u64(42)), nil)
		cnt, _ := xitdb.linked_array_list_count(ll)
		testing.expect_value(ctx.t, cnt, i64(1))
	}
}

driver_verify_custom_64bit_hasher_collisions :: proc(ctx: ^Suite_Ctx, h1, h2, h3: [8]u8, v1, v2, v3: u64) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	u64_hasher := xitdb.Hasher{
		hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
			copy(out_hash, data[:min(len(data), 8)])
		},
		hash_size = 8,
		id        = xitdb.string_to_id("u64h"),
	}

	db, err := xitdb.database_init(&core, u64_hasher)
	testing.expect_value(ctx.t, err, nil)

	m, m_err := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))
	testing.expect_value(ctx.t, m_err, nil)

	h1_b, h2_b, h3_b := h1, h2, h3
	testing.expect_value(ctx.t, xitdb.hash_map_put_by_hash(&m, h1_b[:], v1), nil)
	testing.expect_value(ctx.t, xitdb.hash_map_put_by_hash(&m, h2_b[:], v2), nil)
	testing.expect_value(ctx.t, xitdb.hash_map_put_by_hash(&m, h3_b[:], v3), nil)

	c1_maybe, _ := xitdb.hash_map_get_cursor_by_hash(m, h1_b[:])
	actual1, _ := xitdb.cursor_read_uint(c1_maybe.?)
	testing.expect_value(ctx.t, actual1, v1)

	c2_maybe, _ := xitdb.hash_map_get_cursor_by_hash(m, h2_b[:])
	actual2, _ := xitdb.cursor_read_uint(c2_maybe.?)
	testing.expect_value(ctx.t, actual2, v2)

	c3_maybe, _ := xitdb.hash_map_get_cursor_by_hash(m, h3_b[:])
	actual3, _ := xitdb.cursor_read_uint(c3_maybe.?)
	testing.expect_value(ctx.t, actual3, v3)

	rem1, _ := xitdb.hash_map_remove_by_hash(&m, h1_b[:])
	testing.expect(ctx.t, rem1, "Expected h1 to be removed")
	c1_after, _ := xitdb.hash_map_get_cursor_by_hash(m, h1_b[:])
	testing.expect(ctx.t, c1_after == nil, "Expected h1 to be absent after removal")
}

driver_verify_sorted_map_write_guards_and_dedup :: proc(ctx: ^Suite_Ctx, key1, key2: string, initial_v1, updated_v1, v2: u64) {
	sm, _ := xitdb.write_sorted_map_init(xitdb.database_root_cursor(&ctx.primary_db))

	testing.expect_value(ctx.t, xitdb.sorted_map_put(&sm, key1, initial_v1), nil)
	testing.expect_value(ctx.t, xitdb.sorted_map_put(&sm, key2, v2), nil)

	// Re-putting an existing key replaces its value without incrementing count
	testing.expect_value(ctx.t, xitdb.sorted_map_put(&sm, key1, updated_v1), nil)
	cnt, _ := xitdb.sorted_map_count(sm)
	testing.expect_value(ctx.t, cnt, i64(2))

	c1_maybe, _ := xitdb.sorted_map_get_cursor(sm, key1)
	actual_v1, _ := xitdb.cursor_read_uint(c1_maybe.?)
	testing.expect_value(ctx.t, actual_v1, updated_v1)

	// Positional index access (`Sorted_Map_Get_Index`) is strictly read-only (.Write_Not_Allowed)
	_, idx_write_err := xitdb.cursor_write_path(&sm.write_cursor, []xitdb.Path_Part{
		xitdb.Sorted_Map_Get_Index{index = 0},
	})
	testing.expect_value(ctx.t, idx_write_err, xitdb.Xitdb_Error.Write_Not_Allowed)

	// Key slots inside Sorted_Map cannot be overwritten via low-level path API (.Cursor_Not_Writeable)
	_, key_write_err := xitdb.cursor_write_path(&sm.write_cursor, []xitdb.Path_Part{
		xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_Key{key = transmute([]u8)key1}},
		xitdb.Write_Data{data = "x"},
	})
	testing.expect_value(ctx.t, key_write_err, xitdb.Xitdb_Error.Cursor_Not_Writeable)

	// Entry in Sorted_Map uses `.Sorted_KV_Pair` tag (no hash stored on disk)
	entry_slot_maybe, _ := xitdb.cursor_read_path_slot(sm.cursor, []xitdb.Path_Part{
		xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_KV_Pair{key = transmute([]u8)key1}},
	})
	testing.expect_value(ctx.t, entry_slot_maybe.?.tag, xitdb.Tag.Sorted_KV_Pair)
}

// ----------------------------------------------------------------------------
// Scenarios 17–26: Unfinished Trailing Garbage, Cursor Freeze Cloning,
// Secondary Indexing & Prefix Autocomplete, HAMT Branch Splitting/Shortening,
// Inline vs External Bytes Thresholds, Radix-Trie Root Overflow, B-Tree Matrix,
// Bytes-Keyed Collections, Multi-Handle File Reads & Streaming Reader Seek
// ----------------------------------------------------------------------------

driver_append_trailing_garbage :: proc(ctx: ^Suite_Ctx, garbage_bytes: []u8) {
	end_pos, err := xitdb.core_length(&ctx.primary_core)
	testing.expect_value(ctx.t, err, nil)
	testing.expect_value(ctx.t, xitdb.core_seek_to(&ctx.primary_core, end_pos), nil)
	testing.expect_value(ctx.t, xitdb.core_write_all(&ctx.primary_core, garbage_bytes), nil)
	testing.expect_value(ctx.t, xitdb.core_sync(&ctx.primary_core), nil)
}

driver_verify_reopen_with_trailing_garbage_and_truncate_on_write :: proc(ctx: ^Suite_Ctx, committed_before_garbage: i64, garbage_len: i64, next_key: string, next_val: string) {
	raw_len, _ := xitdb.core_length(&ctx.primary_core)
	testing.expect_value(ctx.t, raw_len, committed_before_garbage + garbage_len)

	// Re-initializing Database over a Core with trailing uncommitted bytes succeeds without truncating on open
	reopened_db, init_err := xitdb.database_init(&ctx.primary_core, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init_err, nil)
	ctx.primary_db = reopened_db

	// If backed by a file, opening a second read-only Core_File handle also succeeds cleanly
	if len(ctx.db_path) > 0 {
		ro_core, ro_err := xitdb.core_file_open(ctx.db_path, {.Read}, false)
		testing.expect_value(ctx.t, ro_err, nil)
		defer _ = xitdb.core_destroy(&ro_core, true)

		ro_db, ro_db_err := xitdb.database_init(&ro_core, xitdb.sha1_hasher())
		testing.expect_value(ctx.t, ro_db_err, nil)
		ro_committed, rc_err := xitdb.database_committed_size(&ro_db)
		testing.expect_value(ctx.t, rc_err, nil)
		testing.expect_value(ctx.t, ro_committed, committed_before_garbage)
	}

	// Executing the next write transaction automatically truncates the trailing garbage first
	tx_err := driver_commit_moment(ctx, 0, []Moment_Mutation_Op{
		Op_Put_String{key = next_key, val = next_val},
	})
	testing.expect_value(ctx.t, tx_err, nil)

	new_committed, _ := xitdb.database_committed_size(&ctx.primary_db)
	new_raw_len, _ := xitdb.core_length(&ctx.primary_core)
	testing.expect_value(ctx.t, new_committed, new_raw_len)
}

driver_verify_collection_cloning_and_cursor_freeze :: proc(ctx: ^Suite_Ctx, initial_fruits: []string, initial_cities: []string, extra_unfrozen_city: string, extra_frozen_cities: []string) {
	// Moment 0: create `fruits`
	given_committed_moment(ctx, Op_Put_Array_List{key = "fruits", items = initial_fruits})

	// Moment 1: clone `fruits` (from Moment 0) -> `food` (automatic CoW across moments),
	// and test intra-transaction cloning both WITHOUT `cursor_freeze` (mutates both)
	// and WITH `cursor_freeze` (isolates original from clone).
	Clone_State :: struct {
		ctx:                 ^Suite_Ctx,
		initial_cities:      []string,
		extra_unfrozen_city: string,
		extra_frozen_cities: []string,
	}
	st := Clone_State{
		ctx                 = ctx,
		initial_cities      = initial_cities,
		extra_unfrozen_city = extra_unfrozen_city,
		extra_frozen_cities = extra_frozen_cities,
	}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Clone_State)(user_data)
		moment := xitdb.write_hash_map_init(cursor^) or_return

		// 1. Cross-moment clone: `food` initialized from Moment 0's `fruits` slot
		fruits_slot_maybe := xitdb.hash_map_get_slot(moment.read_hash_map, "fruits") or_return
		xitdb.hash_map_put(&moment, "food", fruits_slot_maybe.?) or_return
		food_cur := xitdb.hash_map_put_cursor(&moment, "food") or_return
		food_list := xitdb.write_array_list_init(food_cur) or_return
		xitdb.array_list_append(&food_list, "eggs") or_return
		xitdb.array_list_append(&food_list, "rice") or_return

		// 2. Intra-transaction clone WITHOUT `cursor_freeze`: mutating `shared_clone` also mutates `shared_orig`
		so_cur := xitdb.hash_map_put_cursor(&moment, "shared_orig") or_return
		so_list := xitdb.write_array_list_init(so_cur) or_return
		for c in s.initial_cities {
			xitdb.array_list_append(&so_list, c) or_return
		}
		so_slot := xitdb.array_list_slot(so_list.read_array_list) or_return
		xitdb.hash_map_put(&moment, "shared_clone", so_slot) or_return
		sc_cur := xitdb.hash_map_put_cursor(&moment, "shared_clone") or_return
		sc_list := xitdb.write_array_list_init(sc_cur) or_return
		xitdb.array_list_append(&sc_list, s.extra_unfrozen_city) or_return

		// 3. Intra-transaction clone WITH `cursor_freeze`: `big-cities` remains untouched when `cities` is mutated
		bc_cur := xitdb.hash_map_put_cursor(&moment, "big-cities") or_return
		bc_list := xitdb.write_array_list_init(bc_cur) or_return
		for c in s.initial_cities {
			xitdb.array_list_append(&bc_list, c) or_return
		}
		bc_slot := xitdb.array_list_slot(bc_list.read_array_list) or_return
		xitdb.hash_map_put(&moment, "cities", bc_slot) or_return
		cities_cur := xitdb.hash_map_put_cursor(&moment, "cities") or_return
		xitdb.cursor_freeze(&cities_cur) or_return
		cities_list := xitdb.write_array_list_init(cities_cur) or_return
		for c in s.extra_frozen_cities {
			xitdb.array_list_append(&cities_list, c) or_return
		}
		return nil
	}

	err := driver_run_moment_tx(ctx, 0, cb, &st)
	testing.expect_value(ctx.t, err, nil)
}

User_Seed :: struct {
	id:       string,
	username: string,
}

driver_seed_users_with_secondary_index :: proc(ctx: ^Suite_Ctx, users: []User_Seed) {
	Seed_State :: struct {
		users: []User_Seed,
	}
	st := Seed_State{users = users}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Seed_State)(user_data)
		moment := xitdb.write_hash_map_init(cursor^) or_return

		users_cur := xitdb.hash_map_put_cursor(&moment, "users") or_return
		users_map := xitdb.write_hash_map_init(users_cur) or_return

		idx_cur := xitdb.hash_map_put_cursor(&moment, "username->id") or_return
		idx_map := xitdb.write_sorted_map_init(idx_cur) or_return

		for u in s.users {
			uc := xitdb.hash_map_put_cursor(&users_map, u.id) or_return
			um := xitdb.write_hash_map_init(uc) or_return
			xitdb.hash_map_put(&um, "username", u.username) or_return
			xitdb.sorted_map_put(&idx_map, u.username, u.id) or_return
		}
		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)
}

driver_query_paginated_usernames :: proc(ctx: ^Suite_Ctx, moment_idx: i64, page_size: i64, page_index: i64) -> []string {
	moment := driver_read_moment_map(ctx, moment_idx)
	users_cur_maybe, _ := xitdb.hash_map_get_cursor(moment, "users")
	users_map, _ := xitdb.read_hash_map_init(users_cur_maybe.?)

	idx_cur_maybe, _ := xitdb.hash_map_get_cursor(moment, "username->id")
	idx_map, _ := xitdb.read_sorted_map_init(idx_cur_maybe.?)

	it, err := xitdb.sorted_map_iterator_from_index(idx_map, page_size * page_index)
	testing.expect_value(ctx.t, err, nil)

	results := make([dynamic]string, 0, page_size, context.temp_allocator)
	for i: i64 = 0; i < page_size; i += 1 {
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		c, ok := c_maybe.?
		if !ok do break

		kv, _ := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		user_id, _ := xitdb.cursor_read_string(kv.value_cursor, 64, context.temp_allocator)

		u_cur_maybe, _ := xitdb.hash_map_get_cursor(users_map, user_id)
		u_map, _ := xitdb.read_hash_map_init(u_cur_maybe.?)
		uname_cur_maybe, _ := xitdb.hash_map_get_cursor(u_map, "username")
		uname, _ := xitdb.cursor_read_string(uname_cur_maybe.?, 64, context.temp_allocator)
		append(&results, uname)
	}
	return results[:]
}

driver_query_prefix_usernames :: proc(ctx: ^Suite_Ctx, moment_idx: i64, prefix: string) -> []string {
	moment := driver_read_moment_map(ctx, moment_idx)
	idx_cur_maybe, _ := xitdb.hash_map_get_cursor(moment, "username->id")
	idx_map, _ := xitdb.read_sorted_map_init(idx_cur_maybe.?)

	it, err := xitdb.sorted_map_iterator_from_string(idx_map, prefix)
	testing.expect_value(ctx.t, err, nil)

	results := make([dynamic]string, 0, 8, context.temp_allocator)
	for {
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		c, ok := c_maybe.?
		if !ok do break

		kv, _ := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		uname, _ := xitdb.cursor_read_string(kv.key_cursor, 64, context.temp_allocator)
		if !strings.has_prefix(uname, prefix) {
			break
		}
		append(&results, uname)
	}
	return results[:]
}

driver_verify_hamt_branch_splitting_and_shortening :: proc(ctx: ^Suite_Ctx, base_key: string, conflict_2byte_seed: string, conflict_4byte_seed: string) {
	h_base := xitdb.database_digest_string(&ctx.primary_db, base_key, context.temp_allocator)

	// Construct a 2-byte suffix collision hash and a 4-byte suffix collision hash
	// (HAMT indexes from the least-significant nibble of `hash[len(hash)-1]` upward)
	h_c2_raw := xitdb.database_digest_string(&ctx.primary_db, conflict_2byte_seed, context.temp_allocator)
	h_c2 := slice.clone(h_c2_raw, context.temp_allocator)
	h_c2[len(h_c2) - 1] = h_base[len(h_base) - 1]
	h_c2[len(h_c2) - 2] = h_base[len(h_base) - 2]

	h_c4_raw := xitdb.database_digest_string(&ctx.primary_db, conflict_4byte_seed, context.temp_allocator)
	h_c4 := slice.clone(h_c4_raw, context.temp_allocator)
	h_c4[len(h_c4) - 1] = h_base[len(h_base) - 1]
	h_c4[len(h_c4) - 2] = h_base[len(h_base) - 2]
	h_c4[len(h_c4) - 3] = h_base[len(h_base) - 3]
	h_c4[len(h_c4) - 4] = h_base[len(h_base) - 4]

	top_nibble := int(h_base[len(h_base) - 1] & 0x0f)

	Hamt_Conflict_State :: struct {
		ctx:    ^Suite_Ctx,
		h_base: []u8,
		h_c2:   []u8,
		h_c4:   []u8,
		step:   int,
	}
	st := Hamt_Conflict_State{ctx = ctx, h_base = h_base, h_c2 = h_c2, h_c4 = h_c4}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Hamt_Conflict_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		switch s.step {
		case 0:
			xitdb.hash_map_put_by_hash(&m, s.h_base, "val_base") or_return
		case 1:
			xitdb.hash_map_put_by_hash(&m, s.h_c2, "val_c2") or_return
			xitdb.hash_map_put_by_hash(&m, s.h_c4, "val_c4") or_return
		case 2:
			_, err := xitdb.hash_map_remove_by_hash(&m, s.h_c2)
			return err
		case 3:
			_, err := xitdb.hash_map_remove_by_hash(&m, s.h_c4)
			return err
		case 4:
			// Cap `Core_Memory.max_size` partway through splitting the 8 shared nibbles of `h_c4`,
			// catch `.Write_Failed`, restore `max_size`, and still commit the transaction
			mem := &(&s.ctx.primary_core).(xitdb.Core_Memory)
			cur_len := i64(len(mem.buf))
			saved_max := mem.max_size
			mem.max_size = cur_len + xitdb.INDEX_BLOCK_SIZE * 2
			split_err := xitdb.hash_map_put_by_hash(&m, s.h_c4, "should_fail")
			mem.max_size = saved_max
			testing.expect_value(s.ctx.t, split_err, xitdb.Xitdb_Error.Write_Failed)
		}
		return nil
	}

	// Moment 0: insert `base_key` only -> top-level HAMT slot at `top_nibble` is `.KV_Pair`
	st.step = 0
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)
	m0 := driver_read_moment_map(ctx, 0)
	slot_m0 := _read_hamt_root_slot(ctx, m0, top_nibble)
	testing.expect_value(ctx.t, slot_m0.tag, xitdb.Tag.KV_Pair)

	// Moment 1: insert 2-byte and 4-byte colliding keys -> top-level HAMT slot splits into `.Index`
	st.step = 1
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 0, cb, &st), nil)
	m1 := driver_read_moment_map(ctx, 1)
	slot_m1 := _read_hamt_root_slot(ctx, m1, top_nibble)
	testing.expect_value(ctx.t, slot_m1.tag, xitdb.Tag.Index)

	// Moment 2: remove the 2-byte colliding key -> still `.Index` because the 4-byte collision remains
	st.step = 2
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 1, cb, &st), nil)
	m2 := driver_read_moment_map(ctx, 2)
	slot_m2 := _read_hamt_root_slot(ctx, m2, top_nibble)
	testing.expect_value(ctx.t, slot_m2.tag, xitdb.Tag.Index)

	c2_in_m2, _ := xitdb.hash_map_get_cursor_by_hash(m2, h_c2)
	testing.expect(ctx.t, c2_in_m2 == nil, "Expected 2-byte conflict key to be absent in Moment 2")
	c4_in_m2, _ := xitdb.hash_map_get_cursor_by_hash(m2, h_c4)
	v4_m2, _ := xitdb.cursor_read_string(c4_in_m2.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, v4_m2, "val_c4")

	// Moment 3: remove the 4-byte colliding key -> multi-level branch collapses back to `.KV_Pair` at top level!
	st.step = 3
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 2, cb, &st), nil)
	m3 := driver_read_moment_map(ctx, 3)
	slot_m3 := _read_hamt_root_slot(ctx, m3, top_nibble)
	testing.expect_value(ctx.t, slot_m3.tag, xitdb.Tag.KV_Pair)

	base_in_m3, _ := xitdb.hash_map_get_cursor_by_hash(m3, h_base)
	vbase_m3, _ := xitdb.cursor_read_string(base_in_m3.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, vbase_m3, "val_base")
	c4_in_m3, _ := xitdb.hash_map_get_cursor_by_hash(m3, h_c4)
	testing.expect(ctx.t, c4_in_m3 == nil, "Expected 4-byte conflict key to be absent in Moment 3")

	// Historical Moment 1 still has all 3 colliding keys intact
	c2_in_m1, _ := xitdb.hash_map_get_cursor_by_hash(m1, h_c2)
	v2_m1, _ := xitdb.cursor_read_string(c2_in_m1.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, v2_m1, "val_c2")

	// Moment 4: a nested `.Max_Size_Exceeded` partway through splitting `h_c4` (caught inside the
	// transaction callback) must leave `h_base` and its `.KV_Pair` slot intact
	st.step = 4
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 3, cb, &st), nil)
	m4 := driver_read_moment_map(ctx, 4)
	slot_m4 := _read_hamt_root_slot(ctx, m4, top_nibble)
	testing.expect_value(ctx.t, slot_m4.tag, xitdb.Tag.KV_Pair)
	base_in_m4, _ := xitdb.hash_map_get_cursor_by_hash(m4, h_base)
	vbase_m4, _ := xitdb.cursor_read_string(base_in_m4.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, vbase_m4, "val_base")
	c4_in_m4, _ := xitdb.hash_map_get_cursor_by_hash(m4, h_c4)
	testing.expect(ctx.t, c4_in_m4 == nil, "Expected failed collision-split key to be absent in Moment 4")
}

@(private = "file")
_read_hamt_root_slot :: proc(ctx: ^Suite_Ctx, m: xitdb.Read_Hash_Map, slot_idx: int) -> xitdb.Slot {
	map_slot, err := xitdb.hash_map_slot(m)
	testing.expect_value(ctx.t, err, nil)
	slot_offset := map_slot.value + i64(slot_idx * xitdb.SLOT_LENGTH)
	testing.expect_value(ctx.t, xitdb.core_seek_to(&ctx.primary_core, slot_offset), nil)
	s, s_err := xitdb.core_read_slot(&ctx.primary_core)
	testing.expect_value(ctx.t, s_err, nil)
	return s
}

Inline_Bytes_Check :: struct {
	key:           string,
	val:           string,
	format_tag:    string,
	expected_tag:  xitdb.Tag,
	expected_full: bool,
	expected_size: i64,
}

driver_verify_inline_short_bytes_and_tagged_thresholds :: proc(ctx: ^Suite_Ctx, checks: []Inline_Bytes_Check) {
	ops := make([dynamic]Moment_Mutation_Op, 0, len(checks), context.temp_allocator)
	for chk in checks {
		if len(chk.format_tag) > 0 {
			append(&ops, Op_Put_Tagged{key = chk.key, val = chk.val, format_tag = chk.format_tag})
		} else {
			append(&ops, Op_Put_String{key = chk.key, val = chk.val})
		}
	}
	given_committed_moment(ctx, ..ops[:])

	moment := driver_read_moment_map(ctx, 0)
	for chk in checks {
		cur_maybe, err := xitdb.hash_map_get_cursor(moment, chk.key)
		testing.expect_value(ctx.t, err, nil)
		cur := cur_maybe.?

		slot, _ := xitdb.cursor_slot(cur)
		testing.expect_value(ctx.t, slot.tag, chk.expected_tag)
		testing.expect_value(ctx.t, slot.full, chk.expected_full)

		cnt, c_err := xitdb.cursor_count(cur)
		testing.expect_value(ctx.t, c_err, nil)
		testing.expect_value(ctx.t, cnt, chk.expected_size)

		// Also verify zero-allocation `cursor_read_bytes_buf`
		stack_buf: [64]u8
		buf_obj, b_err := xitdb.cursor_read_bytes_buf(cur, stack_buf[:])
		testing.expect_value(ctx.t, b_err, nil)
		testing.expect_value(ctx.t, string(buf_obj.value), chk.val)
		testing.expect_value(ctx.t, string(buf_obj.format_tag), chk.format_tag)

		// And verify `cursor_read_bytes_buf` returns `.Stream_Too_Long` if buffer is 1 byte too small
		if chk.expected_size > 0 {
			tiny_buf := stack_buf[:chk.expected_size - 1]
			_, tiny_err := xitdb.cursor_read_bytes_buf(cur, tiny_buf)
			testing.expect_value(ctx.t, tiny_err, xitdb.Xitdb_Error.Stream_Too_Long)
		}
	}

	// Verify `cursor_write_if_empty` preserves existing slot value when non-empty, and writes when `.None`
	If_Empty_State :: struct {
		ctx: ^Suite_Ctx,
	}
	iest := If_Empty_State{ctx = ctx}

	ie_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^If_Empty_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		c1 := xitdb.hash_map_put_cursor(&m, "if_empty_key") or_return
		xitdb.cursor_write_if_empty(&c1, "first_write") or_return
		slot_after_first, _ := xitdb.cursor_slot(c1.read_cursor)

		// Second `cursor_write_if_empty` on the same non-empty cursor is a no-op
		xitdb.cursor_write_if_empty(&c1, "second_write_ignored") or_return
		slot_after_second, _ := xitdb.cursor_slot(c1.read_cursor)
		testing.expect_value(s.ctx.t, slot_after_second, slot_after_first)
		return nil
	}
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 0, ie_cb, &iest), nil)
	driver_assert_moment_string(ctx, 1, "if_empty_key", "first_write")
}

driver_verify_radix_trie_root_overflow_and_sparse_none_slots :: proc(ctx: ^Suite_Ctx, total_items: int, slice_down_to: i64, sparse_nil_index: i64) {
	items := make([]string, total_items, context.temp_allocator)
	for i in 0 ..< total_items {
		items[i] = fmt.tprintf("elem-%02d", i)
	}

	// Commit `total_items` (e.g. 33 = SLOT_COUNT*2 + 1) to trigger radix-trie root overflow (`shift > 0`)
	given_committed_moment(ctx, Op_Put_Array_List{key = "radix", items = items})
	driver_assert_moment_array_list(ctx, 0, "radix", items)

	// Slice down to `slice_down_to` (e.g. 16 = SLOT_COUNT) in Moment 1 -> collapses root back to single level
	// and write `nil` (`.None`) into `sparse_nil_index` while preserving list count
	Sparse_State :: struct {
		slice_down_to:    i64,
		sparse_nil_index: i64,
	}
	st := Sparse_State{slice_down_to = slice_down_to, sparse_nil_index = sparse_nil_index}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Sparse_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		lc := xitdb.hash_map_put_cursor(&m, "radix") or_return
		list := xitdb.write_array_list_init(lc) or_return
		xitdb.array_list_slice(&list, s.slice_down_to) or_return
		xitdb.array_list_put(&list, s.sparse_nil_index, nil) or_return
		return nil
	}
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 0, cb, &st), nil)

	// Verify Moment 1 has `slice_down_to` items, index >= `slice_down_to` is nil,
	// `sparse_nil_index` has a `.None` slot, and `array_list_iterator` yields all `slice_down_to` slots cleanly
	m1 := driver_read_moment_map(ctx, 1)
	al_cur_maybe, _ := xitdb.hash_map_get_cursor(m1, "radix")
	al, _ := xitdb.read_array_list_init(al_cur_maybe.?)

	cnt, _ := xitdb.array_list_count(al)
	testing.expect_value(ctx.t, cnt, slice_down_to)

	oob_slot, _ := xitdb.array_list_get_slot(al, slice_down_to)
	testing.expect(ctx.t, oob_slot == nil, "Expected slot at sliced boundary to be nil")

	nil_slot_maybe, _ := xitdb.array_list_get_slot(al, sparse_nil_index)
	testing.expect(ctx.t, nil_slot_maybe != nil, "Expected explicit nil write to produce a full .None slot")
	testing.expect_value(ctx.t, nil_slot_maybe.?.tag, xitdb.Tag.None)
	testing.expect_value(ctx.t, nil_slot_maybe.?.full, true)

	it, it_err := xitdb.array_list_iterator(al)
	testing.expect_value(ctx.t, it_err, nil)
	iter_cnt: i64 = 0
	for {
		c_maybe, n_err := xitdb.cursor_iterator_next(&it)
		testing.expect_value(ctx.t, n_err, nil)
		c, ok := c_maybe.?
		if !ok do break
		s, _ := xitdb.cursor_slot(c)
		if iter_cnt == sparse_nil_index {
			testing.expect_value(ctx.t, s.tag, xitdb.Tag.None)
		} else {
			actual, _ := xitdb.cursor_read_string(c, 64, context.temp_allocator)
			testing.expect_value(ctx.t, actual, items[iter_cnt])
		}
		iter_cnt += 1
	}
	testing.expect_value(ctx.t, iter_cnt, slice_down_to)
}

driver_verify_btree_linked_list_structural_operations :: proc(ctx: ^Suite_Ctx, item_count: int, slice_offset: i64, slice_size: i64, insert_idx: i64, inserted_val: string, remove_idx: i64) {
	items := make([]string, item_count, context.temp_allocator)
	for i in 0 ..< item_count {
		items[i] = fmt.tprintf("node-%03d", i)
	}

	// Moment 0: populate `list` with `item_count` items (spanning multiple B-Tree leaves)
	given_committed_moment(ctx, Op_Put_Linked_List{key = "list", items = items})
	driver_assert_moment_linked_list(ctx, 0, "list", items)

	// Moment 1: self-concat `list` with itself (`item_count * 2` items), then slice `(slice_offset, slice_size)`,
	// insert `inserted_val` at `insert_idx`, and remove `remove_idx`.
	upon_branching_moment(
		ctx,
		0,
		Op_Concat_Linked_List{target_key = "list", source_key = "list"},
		Op_Slice_Linked_List{key = "list", offset = slice_offset, size = slice_size},
		Op_Insert_Linked_List{key = "list", index = insert_idx, val = inserted_val},
		Op_Remove_Linked_List{key = "list", index = remove_idx},
	)

	// Build expected sequence in Odin slice to verify exact parity
	doubled := make([dynamic]string, 0, item_count * 2, context.temp_allocator)
	append(&doubled, ..items)
	append(&doubled, ..items)

	sliced := make([dynamic]string, 0, slice_size + 1, context.temp_allocator)
	for i in slice_offset ..< slice_offset + slice_size {
		append(&sliced, doubled[i])
	}
	inject_at(&sliced, int(insert_idx), inserted_val)
	ordered_remove(&sliced, int(remove_idx))

	driver_assert_moment_linked_list(ctx, 1, "list", sliced[:])

	// Also verify out-of-bounds index lookup returns `nil` without error
	m1 := driver_read_moment_map(ctx, 1)
	ll_cur_maybe, _ := xitdb.hash_map_get_cursor(m1, "list")
	ll, _ := xitdb.read_linked_array_list_init(ll_cur_maybe.?)
	oob_cur, oob_err := xitdb.linked_array_list_get_cursor(ll, i64(len(sliced)))
	testing.expect_value(ctx.t, oob_err, nil)
	testing.expect(ctx.t, oob_cur == nil, "Expected out-of-bounds Linked_Array_List lookup to return nil")
}

driver_verify_bytes_keyed_collections_and_kv_inspection :: proc(ctx: ^Suite_Ctx, raw_key_a: []u8, raw_key_b: []u8, val_a: string, val_b: string) {
	Bytes_Key_State :: struct {
		ctx:       ^Suite_Ctx,
		raw_key_a: []u8,
		raw_key_b: []u8,
		val_a:     string,
		val_b:     string,
	}
	st := Bytes_Key_State{
		ctx       = ctx,
		raw_key_a = raw_key_a,
		raw_key_b = raw_key_b,
		val_a     = val_a,
		val_b     = val_b,
	}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Bytes_Key_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return

		// 1. Bytes-keyed Counted_Hash_Map (including duplicate key update & removal)
		cm_cur := xitdb.hash_map_put_cursor(&m, "bytes_map") or_return
		cm := xitdb.write_counted_hash_map_init(cm_cur) or_return
		xitdb.hash_map_put_bytes(&cm, xitdb.new_bytes(s.raw_key_a), "initial_a") or_return
		xitdb.hash_map_put_bytes(&cm, xitdb.new_bytes(s.raw_key_a), s.val_a) or_return // overwrite existing key
		xitdb.hash_map_put_bytes(&cm, xitdb.new_bytes(s.raw_key_b), s.val_b) or_return

		// 2. Bytes-keyed Counted_Hash_Set (including duplicate member & removal)
		cs_cur := xitdb.hash_map_put_cursor(&m, "bytes_set") or_return
		cs := xitdb.write_counted_hash_set_init(cs_cur) or_return
		xitdb.hash_set_put_bytes(&cs, xitdb.new_bytes(s.raw_key_a)) or_return
		xitdb.hash_set_put_bytes(&cs, xitdb.new_bytes(s.raw_key_a)) or_return // idempotent re-add
		xitdb.hash_set_put_bytes(&cs, xitdb.new_bytes(s.raw_key_b)) or_return
		rem, rem_err := xitdb.hash_set_remove_by_bytes(&cs, xitdb.new_bytes(s.raw_key_b))
		if rem_err != nil do return rem_err
		testing.expect(s.ctx.t, rem, "Expected raw_key_b to be removed from Counted_Hash_Set")

		// Removing a non-existent key returns `false, nil`
		rem_missing, rm_err := xitdb.hash_set_remove_by_bytes(&cs, xitdb.new_bytes([]u8{0xff, 0xfe}))
		if rm_err != nil do return rm_err
		testing.expect(s.ctx.t, !rem_missing, "Expected removing absent key to return false")

		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)

	// Read back using `hash_map_get_cursor_by_bytes`, `hash_map_get_key_cursor_by_bytes`, `hash_map_get_kv_pair_by_bytes`
	m0 := driver_read_moment_map(ctx, 0)
	cm_cur_maybe, _ := xitdb.hash_map_get_cursor(m0, "bytes_map")
	cm, _ := xitdb.read_counted_hash_map_init(cm_cur_maybe.?)

	cm_cnt, _ := xitdb.counted_hash_map_count(cm)
	testing.expect_value(ctx.t, cm_cnt, i64(2))

	val_cur_maybe, _ := xitdb.hash_map_get_cursor_by_bytes(cm.read_hash_map, raw_key_a)
	actual_val_a, _ := xitdb.cursor_read_string(val_cur_maybe.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, actual_val_a, val_a)

	key_cur_maybe, _ := xitdb.hash_map_get_key_cursor_by_bytes(cm.read_hash_map, raw_key_a)
	actual_key_a, _ := xitdb.cursor_read_bytes(key_cur_maybe.?, 64, context.temp_allocator)
	testing.expect(ctx.t, slice.equal(actual_key_a, raw_key_a), "Expected key cursor bytes to match raw_key_a")

	kv_maybe, _ := xitdb.hash_map_get_kv_pair_by_bytes(cm.read_hash_map, raw_key_b, context.temp_allocator)
	expected_hash_b := xitdb.database_digest(&ctx.primary_db, raw_key_b, context.temp_allocator)
	testing.expect(ctx.t, slice.equal(kv_maybe.?.hash, expected_hash_b), "Expected KV pair hash to match digest(raw_key_b)")

	// Verify Counted_Hash_Set has count 1 and contains `raw_key_a` but not `raw_key_b`
	cs_cur_maybe, _ := xitdb.hash_map_get_cursor(m0, "bytes_set")
	cs, _ := xitdb.read_counted_hash_set_init(cs_cur_maybe.?)
	cs_cnt, _ := xitdb.counted_hash_set_count(cs)
	testing.expect_value(ctx.t, cs_cnt, i64(1))

	sa_cur_maybe, _ := xitdb.hash_set_get_cursor_by_bytes(cs.read_hash_set, xitdb.new_bytes(raw_key_a))
	testing.expect(ctx.t, sa_cur_maybe != nil, "Expected raw_key_a in Counted_Hash_Set")
	sb_cur_maybe, _ := xitdb.hash_set_get_cursor_by_bytes(cs.read_hash_set, xitdb.new_bytes(raw_key_b))
	testing.expect(ctx.t, sb_cur_maybe == nil, "Expected raw_key_b to be absent from Counted_Hash_Set")
}

driver_verify_reopen_compacted_file_and_interleaved_readers :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key1: string, expected1: string, key2: string, expected2: string) {
	// Close the compacted file handle and re-open it from disk on two independent Core_File descriptors
	testing.expect(ctx.t, ctx.has_compacted && len(ctx.compact_path) > 0, "Expected compacted file database on disk")
	_ = xitdb.core_destroy(&ctx.compacted_core, true)
	ctx.has_compacted = false

	handle_a, err_a := xitdb.core_file_open(ctx.compact_path, {.Read}, false)
	testing.expect_value(ctx.t, err_a, nil)
	defer _ = xitdb.core_destroy(&handle_a, true)

	handle_b, err_b := xitdb.core_file_open(ctx.compact_path, {.Read}, false)
	testing.expect_value(ctx.t, err_b, nil)
	defer _ = xitdb.core_destroy(&handle_b, true)

	db_a, init_a := xitdb.database_init(&handle_a, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init_a, nil)

	db_b, init_b := xitdb.database_init(&handle_b, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init_b, nil)

	// Interleave reads across db_a and db_b to verify independent OS file descriptors don't interfere
	rc_a := xitdb.database_root_cursor(&db_a)
	hist_a, _ := xitdb.read_array_list_init(rc_a.read_cursor)
	mc_a, _ := xitdb.array_list_get_cursor(hist_a, moment_idx)
	m_a, _ := xitdb.read_hash_map_init(mc_a.?)

	rc_b := xitdb.database_root_cursor(&db_b)
	hist_b, _ := xitdb.read_array_list_init(rc_b.read_cursor)
	mc_b, _ := xitdb.array_list_get_cursor(hist_b, moment_idx)
	m_b, _ := xitdb.read_hash_map_init(mc_b.?)

	c1_a, _ := xitdb.hash_map_get_cursor(m_a, key1)
	c2_b, _ := xitdb.hash_map_get_cursor(m_b, key2)

	r1, _ := xitdb.cursor_reader(c1_a.?)
	r2, _ := xitdb.cursor_reader(c2_b.?)

	// Alternate 1-byte reads from r1 (handle_a) and r2 (handle_b)
	b1: [1]u8
	b2: [1]u8
	testing.expect_value(ctx.t, xitdb.cursor_reader_read_fully(&r1, b1[:]), nil)
	testing.expect_value(ctx.t, xitdb.cursor_reader_read_fully(&r2, b2[:]), nil)
	testing.expect_value(ctx.t, b1[0], expected1[0])
	testing.expect_value(ctx.t, b2[0], expected2[0])

	rest1, _ := xitdb.cursor_reader_read_all(&r1, context.temp_allocator)
	rest2, _ := xitdb.cursor_reader_read_all(&r2, context.temp_allocator)
	testing.expect_value(ctx.t, string(rest1), expected1[1:])
	testing.expect_value(ctx.t, string(rest2), expected2[1:])
}

driver_verify_post_compaction_replica_resync :: proc(ctx: ^Suite_Ctx) {
	// 1. Primary has 5 committed moments and is synced to Secondary
	given_committed_moments_count(
		ctx,
		5,
		Op_Put_String{key = "status", val = "pre-compact"},
		Op_Put_Array_List{key = "items", items = []string{"a", "b", "c"}},
	)
	upon_replicating_to_secondary(ctx)
	then_last_sync_started_at_genesis(ctx)
	then_history_has_moments(ctx, 5, on = .Replica)

	// 2. Primary prunes history down to 1 moment and compacts into a fresh image
	upon_retaining_latest_moments(ctx, 1)
	upon_compacting_database(ctx)
	then_compacted_footprint_is_smaller(ctx)

	// Promote compacted database to be the active primary (simulating primary swap after compaction)
	state, state_err := xitdb.database_replica_state(&ctx.replica_db)
	testing.expect_value(ctx.t, state_err, nil)

	start_offset, start_err := xitdb.database_replication_start(&ctx.compacted_db, state)
	testing.expect_value(ctx.t, start_err, nil)
	testing.expect_value(ctx.t, start_offset, i64(0))

	compacted_end, _ := xitdb.database_committed_size(&ctx.compacted_db)
	payload, p_err := xitdb.database_read_committed_bytes(&ctx.compacted_db, start_offset, compacted_end, context.temp_allocator)
	testing.expect_value(ctx.t, p_err, nil)
	testing.expect_value(ctx.t, xitdb.database_apply_replicated_bytes(&ctx.replica_db, start_offset, payload), nil)

	// Replica now has the 1 compacted moment and smaller footprint
	then_history_has_moments(ctx, 1, on = .Replica)
	then_moment_has_string(ctx, 0, "status", "pre-compact", on = .Replica)
	then_moment_has_array_list(ctx, 0, "items", []string{"a", "b", "c"}, on = .Replica)

	// 3. Subsequent commit on the compacted primary replicates incrementally (start_offset > 0) onto the resynced replica
	upon_branching_compacted_moment(ctx, 0, Op_Put_String{key = "status", val = "post-compact-delta"})

	state2, _ := xitdb.database_replica_state(&ctx.replica_db)
	delta_offset, d_err := xitdb.database_replication_start(&ctx.compacted_db, state2)
	testing.expect_value(ctx.t, d_err, nil)
	testing.expect(ctx.t, delta_offset > 0, "Expected incremental delta sync after post-compaction resync")

	compacted_end2, _ := xitdb.database_committed_size(&ctx.compacted_db)
	delta_bytes, _ := xitdb.database_read_committed_bytes(&ctx.compacted_db, delta_offset, compacted_end2, context.temp_allocator)
	testing.expect_value(ctx.t, xitdb.database_apply_replicated_bytes(&ctx.replica_db, delta_offset, delta_bytes), nil)

	then_history_has_moments(ctx, 2, on = .Replica)
	then_moment_has_string(ctx, 1, "status", "post-compact-delta", on = .Replica)
}

driver_verify_multi_tier_btree_in_place_and_cursor_freeze_isolation :: proc(ctx: ^Suite_Ctx, item_count: int) {
	Freeze_BTree_State :: struct {
		ctx:        ^Suite_Ctx,
		item_count: int,
	}
	st := Freeze_BTree_State{ctx = ctx, item_count = item_count}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Freeze_BTree_State)(user_data)
		root := xitdb.write_hash_map_init(cursor^) or_return

		// 1. Build a multi-tier Sorted_Map (40 keys: "k0010" .. "k0049") and Linked_Array_List (40 items)
		sm_cur := xitdb.hash_map_put_cursor(&root, "live_map") or_return
		sm := xitdb.write_sorted_map_init(sm_cur) or_return

		ll_cur := xitdb.hash_map_put_cursor(&root, "live_list") or_return
		ll := xitdb.write_linked_array_list_init(ll_cur) or_return

		for i in 0 ..< s.item_count {
			k := fmt.tprintf("k%04d", i + 10)
			xitdb.sorted_map_put(&sm, k, u64(i)) or_return
			xitdb.linked_array_list_append(&ll, fmt.tprintf("item-%02d", i)) or_return
		}

		// In-place overwrites before freeze (exercises `btree_reusable == true` fast paths)
		xitdb.sorted_map_put(&sm, "k0010", u64(1000)) or_return
		xitdb.sorted_map_put(&sm, "k0001", u64(999)) or_return // new minimum key -> updates branch keys[0] separator!
		xitdb.linked_array_list_put(&ll, 0, "item-00-updated") or_return
		xitdb.linked_array_list_put(&ll, i64(s.item_count - 1), "item-last-updated") or_return

		// 2. Clone both multi-tier structures into `frozen_map` and `frozen_list` and freeze their cursors
		sm_slot := xitdb.sorted_map_slot(sm.read_sorted_map) or_return
		frozen_sm_cur := xitdb.hash_map_put_cursor(&root, "frozen_map") or_return
		xitdb.cursor_write(&frozen_sm_cur, sm_slot) or_return
		xitdb.cursor_freeze(&sm.write_cursor) or_return

		ll_slot := xitdb.linked_array_list_slot(ll.read_linked_array_list) or_return
		frozen_ll_cur := xitdb.hash_map_put_cursor(&root, "frozen_list") or_return
		xitdb.cursor_write(&frozen_ll_cur, ll_slot) or_return
		xitdb.cursor_freeze(&ll.write_cursor) or_return

		// 3. Mutate `sm` and `ll` after `cursor_freeze` (exercises `btree_reusable == false` CoW path at branch & leaf tiers)
		xitdb.sorted_map_put(&sm, "k0010", u64(2000)) or_return
		xitdb.sorted_map_put(&sm, "k0000", u64(888)) or_return
		_, _ = xitdb.sorted_map_remove(&sm, "k0015")

		xitdb.linked_array_list_put(&ll, 0, "item-00-post-freeze") or_return
		xitdb.linked_array_list_insert(&ll, 5, "inserted-post-freeze") or_return
		xitdb.linked_array_list_remove(&ll, 20) or_return

		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)

	m0 := driver_read_moment_map(ctx, 0)

	// Verify `frozen_map` retained pre-freeze state (count = item_count + 1, k0010 = 1000, k0001 = 999, k0000 absent, k0015 present)
	fsm_cur, _ := xitdb.hash_map_get_cursor(m0, "frozen_map")
	fsm, _ := xitdb.read_sorted_map_init(fsm_cur.?)
	fsm_cnt, _ := xitdb.sorted_map_count(fsm)
	testing.expect_value(ctx.t, fsm_cnt, i64(item_count + 1))

	fk10_cur, _ := xitdb.sorted_map_get_cursor(fsm, "k0010")
	fk10_val, _ := xitdb.cursor_read_uint(fk10_cur.?)
	testing.expect_value(ctx.t, fk10_val, u64(1000))

	fk01_cur, _ := xitdb.sorted_map_get_cursor(fsm, "k0001")
	fk01_val, _ := xitdb.cursor_read_uint(fk01_cur.?)
	testing.expect_value(ctx.t, fk01_val, u64(999))

	fk00_cur, _ := xitdb.sorted_map_get_cursor(fsm, "k0000")
	testing.expect(ctx.t, fk00_cur == nil, "Expected k0000 to be absent in frozen_map")

	fk15_cur, _ := xitdb.sorted_map_get_cursor(fsm, "k0015")
	testing.expect(ctx.t, fk15_cur != nil, "Expected k0015 to remain present in frozen_map")

	// Verify `live_map` reflects post-freeze mutations (k0010 = 2000, k0000 = 888, k0015 removed)
	lsm_cur, _ := xitdb.hash_map_get_cursor(m0, "live_map")
	lsm, _ := xitdb.read_sorted_map_init(lsm_cur.?)
	lsm_cnt, _ := xitdb.sorted_map_count(lsm)
	testing.expect_value(ctx.t, lsm_cnt, i64(item_count + 1))

	lk10_cur, _ := xitdb.sorted_map_get_cursor(lsm, "k0010")
	lk10_val, _ := xitdb.cursor_read_uint(lk10_cur.?)
	testing.expect_value(ctx.t, lk10_val, u64(2000))

	lk00_cur, _ := xitdb.sorted_map_get_cursor(lsm, "k0000")
	lk00_val, _ := xitdb.cursor_read_uint(lk00_cur.?)
	testing.expect_value(ctx.t, lk00_val, u64(888))

	lk15_cur, _ := xitdb.sorted_map_get_cursor(lsm, "k0015")
	testing.expect(ctx.t, lk15_cur == nil, "Expected k0015 to be removed from live_map")

	// Verify `frozen_list` vs `live_list` isolation
	fll_cur, _ := xitdb.hash_map_get_cursor(m0, "frozen_list")
	fll, _ := xitdb.read_linked_array_list_init(fll_cur.?)
	fll_0, _ := xitdb.linked_array_list_get_cursor(fll, 0)
	fll_0_str, _ := xitdb.cursor_read_string(fll_0.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, fll_0_str, "item-00-updated")

	fll_last, _ := xitdb.linked_array_list_get_cursor(fll, i64(item_count - 1))
	fll_last_str, _ := xitdb.cursor_read_string(fll_last.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, fll_last_str, "item-last-updated")

	lll_cur, _ := xitdb.hash_map_get_cursor(m0, "live_list")
	lll, _ := xitdb.read_linked_array_list_init(lll_cur.?)
	lll_0, _ := xitdb.linked_array_list_get_cursor(lll, 0)
	lll_0_str, _ := xitdb.cursor_read_string(lll_0.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, lll_0_str, "item-00-post-freeze")

	lll_5, _ := xitdb.linked_array_list_get_cursor(lll, 5)
	lll_5_str, _ := xitdb.cursor_read_string(lll_5.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, lll_5_str, "inserted-post-freeze")
}

driver_verify_sorted_set_multi_tier_lifecycle :: proc(ctx: ^Suite_Ctx, total_members: int, remove_count: int) {
	Sorted_Set_State :: struct {
		ctx:           ^Suite_Ctx,
		total_members: int,
		remove_count:  int,
		step:          int,
	}
	st := Sorted_Set_State{ctx = ctx, total_members = total_members, remove_count = remove_count, step = 0}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Sorted_Set_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		sc := xitdb.hash_map_put_cursor(&m, "members") or_return
		ss := xitdb.write_sorted_set_init(sc) or_return

		if s.step == 0 {
			for i in 0 ..< s.total_members {
				perm := (i * 19 + 7) % s.total_members
				member := fmt.tprintf("member-%03d", perm)
				xitdb.sorted_set_put(&ss, member) or_return
				if i % 5 == 0 {
					// Idempotent duplicate member insertion
					xitdb.sorted_set_put(&ss, member) or_return
				}
			}
		} else {
			for i in 0 ..< s.remove_count {
				member := fmt.tprintf("member-%03d", i)
				removed, r_err := xitdb.sorted_set_remove(&ss, member)
				if r_err != nil do return r_err
				testing.expect(s.ctx.t, removed, "Expected existing Sorted_Set member to be removed")
			}
			// Removing an absent member returns `false, nil`
			removed_absent, ra_err := xitdb.sorted_set_remove(&ss, "member-999-absent")
			if ra_err != nil do return ra_err
			testing.expect(s.ctx.t, !removed_absent, "Expected absent Sorted_Set member removal to return false")
		}
		return nil
	}

	// Moment 0: insert `total_members` out-of-order into Sorted_Set
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)

	expected_m0 := make([]string, total_members, context.temp_allocator)
	for i in 0 ..< total_members {
		expected_m0[i] = fmt.tprintf("member-%03d", i)
	}
	driver_assert_moment_sorted_set(ctx, 0, "members", expected_m0)

	// Verify `sorted_set_iterator_from_string` and negative `sorted_set_iterator_from_index` on Moment 0
	m0 := driver_read_moment_map(ctx, 0)
	ss_cur0, _ := xitdb.hash_map_get_cursor(m0, "members")
	ss0, _ := xitdb.read_sorted_set_init(ss_cur0.?)

	it_key, ik_err := xitdb.sorted_set_iterator_from_string(ss0, "member-020")
	testing.expect_value(ctx.t, ik_err, nil)
	first_key_cur, _ := xitdb.cursor_iterator_next(&it_key)
	first_kv, _ := xitdb.cursor_read_kv_pair(first_key_cur.?, context.temp_allocator)
	first_str, _ := xitdb.cursor_read_string(first_kv.key_cursor, 64, context.temp_allocator)
	testing.expect_value(ctx.t, first_str, "member-020")

	it_neg, in_err := xitdb.sorted_set_iterator_from_index(ss0, -5)
	testing.expect_value(ctx.t, in_err, nil)
	neg_cur, _ := xitdb.cursor_iterator_next(&it_neg)
	neg_kv, _ := xitdb.cursor_read_kv_pair(neg_cur.?, context.temp_allocator)
	neg_str, _ := xitdb.cursor_read_string(neg_kv.key_cursor, 64, context.temp_allocator)
	testing.expect_value(ctx.t, neg_str, fmt.tprintf("member-%03d", total_members - 5))

	// Also verify negative index lookup via `sorted_set_get_index_kv_pair(ss0, -1)`
	last_kv, l_err := xitdb.sorted_set_get_index_kv_pair(ss0, -1, context.temp_allocator)
	testing.expect_value(ctx.t, l_err, nil)
	last_str, _ := xitdb.cursor_read_string(last_kv.?.key_cursor, 64, context.temp_allocator)
	testing.expect_value(ctx.t, last_str, fmt.tprintf("member-%03d", total_members - 1))

	// Moment 1: remove `remove_count` members to trigger B+Tree leaf/branch merges
	st.step = 1
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 0, cb, &st), nil)

	remaining := total_members - remove_count
	expected_m1 := make([]string, remaining, context.temp_allocator)
	for i in 0 ..< remaining {
		expected_m1[i] = fmt.tprintf("member-%03d", i + remove_count)
	}
	driver_assert_moment_sorted_set(ctx, 1, "members", expected_m1)
}

driver_verify_linked_array_list_edge_boundaries :: proc(ctx: ^Suite_Ctx, initial_count: int) {
	Edge_List_State :: struct {
		ctx:           ^Suite_Ctx,
		initial_count: int,
	}
	st := Edge_List_State{ctx = ctx, initial_count = initial_count}

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Edge_List_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		lc := xitdb.hash_map_put_cursor(&m, "list") or_return
		ll := xitdb.write_linked_array_list_init(lc) or_return

		for i in 0 ..< s.initial_count {
			xitdb.linked_array_list_append(&ll, fmt.tprintf("item-%02d", i)) or_return
		}

		// 1. Full-range slice `(0, initial_count)` preserves all items
		xitdb.linked_array_list_slice(&ll, 0, i64(s.initial_count)) or_return
		cnt_full, _ := xitdb.linked_array_list_count(ll.read_linked_array_list)
		testing.expect_value(s.ctx.t, cnt_full, i64(s.initial_count))

		// 2. Out-of-bounds slice, insert, remove, and put return `.Key_Not_Found` without corrupting the list
		testing.expect_value(s.ctx.t, xitdb.linked_array_list_slice(&ll, 10, i64(s.initial_count)), xitdb.Xitdb_Error.Key_Not_Found)
		testing.expect_value(s.ctx.t, xitdb.linked_array_list_slice(&ll, -1, 5), xitdb.Xitdb_Error.Key_Not_Found)
		testing.expect_value(s.ctx.t, xitdb.linked_array_list_insert(&ll, i64(s.initial_count + 1), "oob"), xitdb.Xitdb_Error.Key_Not_Found)
		testing.expect_value(s.ctx.t, xitdb.linked_array_list_remove(&ll, i64(s.initial_count)), xitdb.Xitdb_Error.Key_Not_Found)
		testing.expect_value(s.ctx.t, xitdb.linked_array_list_put(&ll, -i64(s.initial_count + 1), "neg_oob"), xitdb.Xitdb_Error.Key_Not_Found)

		// 3. Slice to 0 elements (`size == 0`) collapses the B-Tree root and resets count to 0
		xitdb.linked_array_list_slice(&ll, 0, 0) or_return
		cnt_zero, _ := xitdb.linked_array_list_count(ll.read_linked_array_list)
		testing.expect_value(s.ctx.t, cnt_zero, i64(0))

		// 4. Appending onto the emptied Linked_Array_List rebuilds cleanly from a fresh root
		xitdb.linked_array_list_append(&ll, "rebuilt-0") or_return
		xitdb.linked_array_list_append(&ll, "rebuilt-1") or_return
		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb, &st), nil)
	driver_assert_moment_linked_list(ctx, 0, "list", []string{"rebuilt-0", "rebuilt-1"})
}

driver_verify_sorted_set_key_only_entries_and_map_reinterpretation :: proc(ctx: ^Suite_Ctx) {
	cb_m0 :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Suite_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		sc := xitdb.hash_map_put_cursor(&m, "tags") or_return
		ss := xitdb.write_sorted_set_init(sc) or_return

		// Insert short key (<= 8 bytes -> .Short_Bytes) and long key (> 8 bytes -> .Bytes)
		xitdb.sorted_set_put(&ss, "short") or_return
		xitdb.sorted_set_put(&ss, "longer-sorted-set-key") or_return

		// Verify leaf entries are stored directly as .Short_Bytes / .Bytes (not .Sorted_KV_Pair)
		it := xitdb.sorted_set_iterator(ss.read_sorted_set) or_return
		cur0, _ := xitdb.cursor_iterator_next(&it)
		testing.expect_value(c.t, cur0.?.slot_ptr.slot.tag, xitdb.Tag.Bytes) // "longer-sorted-set-key" sorts before "short"
		kv0 := xitdb.cursor_read_kv_pair(cur0.?, context.temp_allocator) or_return
		testing.expect_value(c.t, kv0.value_cursor.slot_ptr.slot.tag, xitdb.Tag.None)
		testing.expect_value(c.t, kv0.key_cursor.slot_ptr.position, nil)
		testing.expect_value(c.t, kv0.value_cursor.slot_ptr.position, nil)

		cur1, _ := xitdb.cursor_iterator_next(&it)
		testing.expect_value(c.t, cur1.?.slot_ptr.slot.tag, xitdb.Tag.Short_Bytes) // "short"
		return nil
	}

	cb_m1 :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Suite_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		sc := xitdb.hash_map_put_cursor(&m, "tags") or_return

		// Reinterpret the existing Sorted_Set as a Write_Sorted_Map and assign a value to "short"
		sm := xitdb.write_sorted_map_init(sc) or_return
		xitdb.sorted_map_put(&sm, "short", u64(42)) or_return

		// Reinterpret back as a Write_Sorted_Set and verify duplicate put on an existing key-value entry leaves its value intact
		ss := xitdb.write_sorted_set_init(sc) or_return
		xitdb.sorted_set_put(&ss, "short") or_return

		val_cur, _ := xitdb.sorted_map_get_cursor(sm.read_sorted_map, "short")
		val, _ := xitdb.cursor_read_uint(val_cur.?)
		testing.expect_value(c.t, val, u64(42))

		// While "longer-sorted-set-key" remains a key-only entry with an empty (.None) value
		long_val_slot, _ := xitdb.sorted_map_get_slot(sm.read_sorted_map, "longer-sorted-set-key")
		testing.expect(c.t, long_val_slot == nil, "Expected key-only entry to have no value in Sorted_Map")
		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, nil, cb_m0, ctx), nil)
	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, 0, cb_m1, ctx), nil)

	// Compact and verify both key-only and promoted key-value entries survive compaction
	driver_compact_primary(ctx, false)
	cm1 := driver_read_moment_map(ctx, 0, .Compacted)
	tags_cur, _ := xitdb.hash_map_get_cursor(cm1, "tags")
	csm, _ := xitdb.read_sorted_map_init(tags_cur.?)
	s_cur, _ := xitdb.sorted_map_get_cursor(csm, "short")
	s_val, _ := xitdb.cursor_read_uint(s_cur.?)
	testing.expect_value(ctx.t, s_val, u64(42))

	css, _ := xitdb.read_sorted_set_init(tags_cur.?)
	has_long, _ := xitdb.sorted_set_contains(css, "longer-sorted-set-key")
	testing.expect(ctx.t, has_long, "Expected key-only entry to survive compaction")
}

driver_verify_linked_array_list_append_context :: proc(ctx: ^Suite_Ctx) {
	cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		m := xitdb.write_hash_map_init(cursor^) or_return
		lc := xitdb.hash_map_put_cursor(&m, "events") or_return
		ll := xitdb.write_linked_array_list_init(lc) or_return

		xitdb.linked_array_list_append_context(&ll, xitdb.Slot{}, proc(item_cur: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			ev := xitdb.write_hash_map_init(item_cur^) or_return
			xitdb.hash_map_put(&ev, "kind", "login") or_return
			xitdb.hash_map_put(&ev, "seq", u64(1)) or_return
			return nil
		}) or_return

		xitdb.linked_array_list_append_context(&ll, xitdb.Slot{}, proc(item_cur: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			ev := xitdb.write_hash_map_init(item_cur^) or_return
			xitdb.hash_map_put(&ev, "kind", "logout") or_return
			xitdb.hash_map_put(&ev, "seq", u64(2)) or_return
			return nil
		}) or_return
		return nil
	}

	testing.expect_value(ctx.t, driver_run_moment_tx(ctx, -1, cb, nil), nil)

	m_last := driver_read_moment_map(ctx, -1)
	ev_cur, _ := xitdb.hash_map_get_cursor(m_last, "events")
	ll, _ := xitdb.read_linked_array_list_init(ev_cur.?)
	cnt, _ := xitdb.linked_array_list_count(ll)
	testing.expect_value(ctx.t, cnt, i64(2))

	item1_cur, _ := xitdb.linked_array_list_get_cursor(ll, 1)
	item1_map, _ := xitdb.read_hash_map_init(item1_cur.?)
	kind_cur, _ := xitdb.hash_map_get_cursor(item1_map, "kind")
	kind_str, _ := xitdb.cursor_read_string(kind_cur.?, 64, context.temp_allocator)
	testing.expect_value(ctx.t, kind_str, "logout")
}

driver_verify_cursor_reader_reallocation_window_shift_and_truncation :: proc(ctx: ^Suite_Ctx) {
	// 1. In-memory database: hold a Cursor_Reader across multiple large writes that force
	// `Core_Memory.buf` reallocation (`cap(buf)` grows multiple times)
	mem_core: xitdb.Core = xitdb.core_memory_init()
	defer _ = xitdb.core_destroy(&mem_core)

	mem_db, init_err := xitdb.database_init(&mem_core, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init_err, nil)

	expected_payload := "0123456789abcdef-initial-payload-held-across-reallocation-and-commits-xyz"

	Seed_State :: struct {
		payload: string,
	}
	seed_st := Seed_State{payload = expected_payload}
	seed_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Seed_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&m, "target", s.payload) or_return
		xitdb.hash_map_put(&m, "short_target", "inline8!") or_return
		return nil
	}
	testing.expect_value(ctx.t, xitdb.database_run_context(&mem_db, seed_cb, &seed_st), nil)

	// Open a Cursor_Reader on `"target"` (.Bytes) and `"short_target"` (.Short_Bytes) BEFORE growing the buffer
	rc0 := xitdb.database_root_cursor(&mem_db)
	m0, _ := xitdb.read_hash_map_init(rc0.read_cursor)

	target_cur, _ := xitdb.hash_map_get_cursor(m0, "target")
	reader, r_err := xitdb.cursor_reader(target_cur.?)
	testing.expect_value(ctx.t, r_err, nil)

	short_cur, _ := xitdb.hash_map_get_cursor(m0, "short_target")
	short_reader, sr_err := xitdb.cursor_reader(short_cur.?)
	testing.expect_value(ctx.t, sr_err, nil)

	// Read first 16 bytes before reallocation
	prefix_buf: [16]u8
	testing.expect_value(ctx.t, xitdb.cursor_reader_read_fully(&reader, prefix_buf[:]), nil)
	testing.expect_value(ctx.t, string(prefix_buf[:]), expected_payload[:16])

	initial_cap := cap((&mem_core.(xitdb.Core_Memory)).buf)

	// Perform multiple large transactions that grow `Core_Memory.buf` well past `initial_cap` (forcing reallocations)
	Grow_State :: struct {
		round: int,
		blob:  string,
	}
	big_blob_bytes := make([]u8, 65536, context.temp_allocator)
	for i in 0 ..< len(big_blob_bytes) {
		big_blob_bytes[i] = u8('A' + (i % 26))
	}
	grow_st := Grow_State{blob = string(big_blob_bytes)}
	grow_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		g := (^Grow_State)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for j in 0 ..< 4 {
			k := fmt.tprintf("grow_%d_%d", g.round, j)
			xitdb.hash_map_put(&m, k, g.blob) or_return
		}
		return nil
	}
	for round in 0 ..< 3 {
		grow_st.round = round
		testing.expect_value(ctx.t, xitdb.database_run_context(&mem_db, grow_cb, &grow_st), nil)
	}

	new_cap := cap((&mem_core.(xitdb.Core_Memory)).buf)
	testing.expect(ctx.t, new_cap > initial_cap * 4, "Expected Core_Memory.buf to reallocate to a much larger capacity")

	// Continue reading the remaining bytes from the pre-existing `reader` after reallocation
	rest_bytes, rest_err := xitdb.cursor_reader_read_all(&reader, context.temp_allocator)
	testing.expect_value(ctx.t, rest_err, nil)
	testing.expect_value(ctx.t, string(rest_bytes), expected_payload[16:])

	// Seek back to 0 on the same `reader` and read the entire payload again
	testing.expect_value(ctx.t, xitdb.cursor_reader_seek_to(&reader, 0), nil)
	full_bytes, full_err := xitdb.cursor_reader_read_all(&reader, context.temp_allocator)
	testing.expect_value(ctx.t, full_err, nil)
	testing.expect_value(ctx.t, string(full_bytes), expected_payload)

	// Verify `short_reader` also reads cleanly
	short_bytes, sb_err := xitdb.cursor_reader_read_all(&short_reader, context.temp_allocator)
	testing.expect_value(ctx.t, sb_err, nil)
	testing.expect_value(ctx.t, string(short_bytes), "inline8!")

	// Truncating `mem_core` below `reader.start_position + reader.size` causes subsequent reads to return `.Unexpected_EOF`
	testing.expect_value(ctx.t, xitdb.core_set_length(&mem_core, reader.start_position + 5), nil)
	testing.expect_value(ctx.t, xitdb.cursor_reader_seek_to(&reader, 0), nil)
	trunc_buf: [16]u8
	_, trunc_read_err := xitdb.cursor_reader_read(&reader, trunc_buf[:])
	testing.expect_value(ctx.t, trunc_read_err, xitdb.Xitdb_Error.Unexpected_EOF)
	testing.expect_value(ctx.t, xitdb.cursor_reader_read_fully(&reader, trunc_buf[:]), xitdb.Xitdb_Error.Unexpected_EOF)

	// 2. Buffered file database: hold a `Cursor_Reader` while large writes flush and shift `memory_pos` past `start_position`
	bf_path := driver_temp_path(ctx.t, "reader_window_shift.xit")
	defer _ = os.remove(bf_path)

	bf_core, bf_open_err := xitdb.core_buffered_file_open(bf_path, 256, {.Read, .Write, .Create, .Trunc})
	testing.expect_value(ctx.t, bf_open_err, nil)
	defer _ = xitdb.core_destroy(&bf_core, true)

	bf_db, bf_init_err := xitdb.database_init(&bf_core, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, bf_init_err, nil)
	testing.expect_value(ctx.t, xitdb.database_run_context(&bf_db, seed_cb, &seed_st), nil)

	bf_rc0 := xitdb.database_root_cursor(&bf_db)
	bf_m0, _ := xitdb.read_hash_map_init(bf_rc0.read_cursor)
	bf_target_cur, _ := xitdb.hash_map_get_cursor(bf_m0, "target")

	bf_reader, bf_r_err := xitdb.cursor_reader(bf_target_cur.?)
	testing.expect_value(ctx.t, bf_r_err, nil)
	testing.expect_value(ctx.t, xitdb.cursor_reader_read_fully(&bf_reader, prefix_buf[:]), nil)
	testing.expect_value(ctx.t, string(prefix_buf[:]), expected_payload[:16])

	// Commit large data so `Core_Buffered_File` flushes and shifts its tail window far past `bf_reader.start_position`
	grow_st.round = 10
	testing.expect_value(ctx.t, xitdb.database_run_context(&bf_db, grow_cb, &grow_st), nil)

	bf_rest, bf_rest_err := xitdb.cursor_reader_read_all(&bf_reader, context.temp_allocator)
	testing.expect_value(ctx.t, bf_rest_err, nil)
	testing.expect_value(ctx.t, string(bf_rest), expected_payload[16:])
}

driver_verify_buffered_file_multi_handle_alternating_commits :: proc(ctx: ^Suite_Ctx, commit_values: []string) {
	shared_path := driver_temp_path(ctx.t, "multi_handle_buffered.xit")
	defer _ = os.remove(shared_path)

	// Open two independent `Core_Buffered_File` handles on the same OS file (simulating two processes under a file lock)
	c1, err1 := xitdb.core_buffered_file_open(shared_path, 4096, {.Read, .Write, .Create, .Trunc})
	testing.expect_value(ctx.t, err1, nil)
	defer _ = xitdb.core_destroy(&c1, true)

	db1, init1 := xitdb.database_init(&c1, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init1, nil)

	c2, err2 := xitdb.core_buffered_file_open(shared_path, 4096, {.Read, .Write})
	testing.expect_value(ctx.t, err2, nil)
	defer _ = xitdb.core_destroy(&c2, true)

	db2, init2 := xitdb.database_init(&c2, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init2, nil)

	Append_State :: struct {
		val: string,
	}
	append_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		s := (^Append_State)(user_data)
		list := xitdb.write_array_list_init(cursor^) or_return
		return xitdb.array_list_append(&list, s.val)
	}

	read_all_on_handle :: proc(t: ^testing.T, db: ^xitdb.Database) -> []string {
		rc := xitdb.database_root_cursor(db)
		list, err := xitdb.read_array_list_init(rc.read_cursor)
		testing.expect_value(t, err, nil)
		cnt, _ := xitdb.array_list_count(list)
		res := make([]string, cnt, context.temp_allocator)
		for i: i64 = 0; i < cnt; i += 1 {
			mc, g_err := xitdb.array_list_get_cursor(list, i)
			testing.expect_value(t, g_err, nil)
			val, s_err := xitdb.cursor_read_string(mc.?, 64, context.temp_allocator)
			testing.expect_value(t, s_err, nil)
			res[i] = val
		}
		return res
	}

	// Alternate commits between `db1` and `db2`, reading on the opposite handle before and after each commit
	for val, idx in commit_values {
		writer_db := &db1 if idx % 2 == 0 else &db2
		reader_db := &db2 if idx % 2 == 0 else &db1

		// Pre-commit read on both handles (exercises `core_length` / `read_root_cursor` before writing)
		pre_vals := read_all_on_handle(ctx.t, writer_db)
		driver_assert_string_slice(ctx.t, pre_vals, commit_values[:idx])

		st := Append_State{val = val}
		testing.expect_value(ctx.t, xitdb.database_run_context(writer_db, append_cb, &st), nil)

		// Post-commit read on both the writer handle and the peer handle
		writer_vals := read_all_on_handle(ctx.t, writer_db)
		driver_assert_string_slice(ctx.t, writer_vals, commit_values[:idx + 1])

		peer_vals := read_all_on_handle(ctx.t, reader_db)
		driver_assert_string_slice(ctx.t, peer_vals, commit_values[:idx + 1])
	}

	// Open a fresh third handle from disk and verify all commits `commit_values` are durable (`1 2 3 4`, never `1 3`)
	c3, err3 := xitdb.core_buffered_file_open(shared_path, 4096, {.Read})
	testing.expect_value(ctx.t, err3, nil)
	defer _ = xitdb.core_destroy(&c3, true)

	db3, init3 := xitdb.database_init(&c3, xitdb.sha1_hasher())
	testing.expect_value(ctx.t, init3, nil)

	fresh_vals := read_all_on_handle(ctx.t, &db3)
	driver_assert_string_slice(ctx.t, fresh_vals, commit_values)
}

driver_verify_fast_path_corruption_and_truncation_guards :: proc(ctx: ^Suite_Ctx) {
	// Test both `.Memory` (in-memory `core_slice_at` fast path) and `.File` (seek+read path)
	for is_memory in ([]bool{true, false}) {
		file_path := driver_temp_path(ctx.t, "corrupt_guards.xit")
		defer if !is_memory do _ = os.remove(file_path)

		core: xitdb.Core
		if is_memory {
			core = xitdb.core_memory_init()
		} else {
			fcore, ferr := xitdb.core_file_open(file_path, {.Read, .Write, .Create, .Trunc}, true)
			testing.expect_value(ctx.t, ferr, nil)
			core = fcore
		}
		defer _ = xitdb.core_destroy(&core, true)

		db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
		testing.expect_value(ctx.t, init_err, nil)

		// Seed a 20-element Linked_Array_List (2-tier B-Tree with Branch -> 2 Leaves),
		// a 20-element Sorted_Map (2-tier B+Tree with Branch -> 2 Leaves),
		// and a Hash_Map
		Seed_Corrupt_State :: struct {}
		sc_st := Seed_Corrupt_State{}
		seed_cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			root := xitdb.write_hash_map_init(cursor^) or_return
			ll_cur := xitdb.hash_map_put_cursor(&root, "ll") or_return
			ll := xitdb.write_linked_array_list_init(ll_cur) or_return
			sm_cur := xitdb.hash_map_put_cursor(&root, "sm") or_return
			sm := xitdb.write_sorted_map_init(sm_cur) or_return
			hm_cur := xitdb.hash_map_put_cursor(&root, "hm") or_return
			hm := xitdb.write_hash_map_init(hm_cur) or_return

			for i in 0 ..< 20 {
				k := fmt.tprintf("k%02d", i)
				xitdb.linked_array_list_append(&ll, k) or_return
				xitdb.sorted_map_put(&sm, k, u64(i)) or_return
				xitdb.hash_map_put(&hm, k, u64(i)) or_return
			}
			return nil
		}
		testing.expect_value(ctx.t, xitdb.database_run_context(&db, seed_cb, &sc_st), nil)

		rc := xitdb.database_root_cursor(&db)
		m0, _ := xitdb.read_hash_map_init(rc.read_cursor)

		ll_cur, _ := xitdb.hash_map_get_cursor(m0, "ll")
		ll, _ := xitdb.read_linked_array_list_init(ll_cur.?)
		ll_slot, _ := xitdb.linked_array_list_slot(ll)

		sm_cur, _ := xitdb.hash_map_get_cursor(m0, "sm")
		sm, _ := xitdb.read_sorted_map_init(sm_cur.?)
		sm_slot, _ := xitdb.sorted_map_slot(sm)

		hm_cur, _ := xitdb.hash_map_get_cursor(m0, "hm")
		hm, _ := xitdb.read_hash_map_init(hm_cur.?)
		hm_slot, _ := xitdb.hash_map_slot(hm)

		// Read B-Tree header of `ll` ([0..8] = size, [8..16] = root_ptr)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_slot.value + 8), nil)
		ll_root_ptr, _ := xitdb.core_read_i64(&core)

		// Read B+Tree header of `sm` ([0..8] = size, [8..16] = root_ptr)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_slot.value + 8), nil)
		sm_root_ptr, _ := xitdb.core_read_i64(&core)

		// 1. Corrupt `ll` branch `counts[0]` from 8 to 15 so `rank = 10` routes to child 0 (`num = 8`) with `rem = 10 >= num`:
		// Verify `linked_array_list_get_cursor(ll, 10)` returns `.Invalid_BTree_Node`
		ll_counts0_pos := ll_root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + xitdb.SLOT_LENGTH * xitdb.BTREE_SLOT_COUNT
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_counts0_pos), nil)
		orig_ll_cnt0, _ := xitdb.core_read_i64(&core)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_counts0_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_i64(&core, 15), nil)

		_, ll_rem_err := xitdb.linked_array_list_get_cursor(ll, 10)
		testing.expect_value(ctx.t, ll_rem_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		// Restore `ll` `counts[0]`
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_counts0_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_i64(&core, orig_ll_cnt0), nil)

		// 2. Corrupt `sm` branch `counts[0]` from 8 to 15 so `rank = 10` routes to child 0 (`num = 8`) with `rem = 10 >= num`:
		// Verify `sorted_map_get_index_cursor(sm, 10)` returns `.Invalid_BTree_Node`
		sm_counts0_pos := sm_root_ptr + xitdb.BTREE_NODE_HEADER_SIZE + xitdb.SLOT_LENGTH * 2 * xitdb.BTREE_SLOT_COUNT
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_counts0_pos), nil)
		orig_sm_cnt0, _ := xitdb.core_read_i64(&core)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_counts0_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_i64(&core, 15), nil)

		_, sm_rem_err := xitdb.sorted_map_get_index_kv_pair(sm, 10)
		testing.expect_value(ctx.t, sm_rem_err, xitdb.Xitdb_Error.Invalid_BTree_Node)

		// Restore `sm` `counts[0]`
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_counts0_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_i64(&core, orig_sm_cnt0), nil)

		// 3. Corrupt a slot tag byte (`0x63` = 99) in `ll` child 0 leaf slot 0:
		// Verify `linked_array_list_get_cursor(ll, 0)` and `linked_array_list_iterator` return `.Unexpected_Tag`
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_root_ptr + xitdb.BTREE_NODE_HEADER_SIZE), nil)
		ll_child0_slot, _ := xitdb.core_read_slot(&core)
		ll_leaf0_tag_pos := ll_child0_slot.value + xitdb.BTREE_NODE_HEADER_SIZE
		orig_ll_tag_byte: [1]u8
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_read_exact(&core, orig_ll_tag_byte[:]), nil)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, []u8{99}), nil)

		_, ll_tag_err := xitdb.linked_array_list_get_cursor(ll, 0)
		testing.expect_value(ctx.t, ll_tag_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, ll_from_err := xitdb.linked_array_list_iterator_from(ll, 0)
		testing.expect_value(ctx.t, ll_from_err, xitdb.Xitdb_Error.Unexpected_Tag)
		ll_it, ll_it_init_err := xitdb.linked_array_list_iterator(ll)
		testing.expect_value(ctx.t, ll_it_init_err, nil)
		_, ll_iter_err := xitdb.cursor_iterator_next(&ll_it)
		testing.expect_value(ctx.t, ll_iter_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, ll_node_err := xitdb.read_btree_node(&db, ll_child0_slot.value)
		testing.expect_value(ctx.t, ll_node_err, xitdb.Xitdb_Error.Unexpected_Tag)

		// Restore `ll` leaf tag byte
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, ll_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, orig_ll_tag_byte[:]), nil)

		// 4. Corrupt a slot tag byte (`99`) in `sm` child 0 leaf slot 0:
		// Verify `sorted_map_get_cursor(sm, "k00")`, `sorted_map_get_index_kv_pair(sm, 0)`, `sorted_map_rank(sm, "k00")`,
		// `sorted_map_iterator_from_index(sm, 0)`, `sorted_map_iterator_from_string(sm, "k00")`, and `cursor_iterator_next`
		// all return `.Unexpected_Tag`
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_root_ptr + xitdb.BTREE_NODE_HEADER_SIZE), nil)
		sm_child0_slot, _ := xitdb.core_read_slot(&core)
		sm_leaf0_tag_pos := sm_child0_slot.value + xitdb.BTREE_NODE_HEADER_SIZE
		orig_sm_tag_byte: [1]u8
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_read_exact(&core, orig_sm_tag_byte[:]), nil)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, []u8{99}), nil)

		_, sm_get_err := xitdb.sorted_map_get_cursor(sm, "k00")
		testing.expect_value(ctx.t, sm_get_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, sm_idx_err := xitdb.sorted_map_get_index_kv_pair(sm, 0)
		testing.expect_value(ctx.t, sm_idx_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, sm_rank_err := xitdb.sorted_map_rank(sm, "k00")
		testing.expect_value(ctx.t, sm_rank_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, sm_from_idx_err := xitdb.sorted_map_iterator_from_index(sm, 0)
		testing.expect_value(ctx.t, sm_from_idx_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, sm_from_key_err := xitdb.sorted_map_iterator_from_string(sm, "k00")
		testing.expect_value(ctx.t, sm_from_key_err, xitdb.Xitdb_Error.Unexpected_Tag)
		sm_it, sm_it_init_err := xitdb.sorted_map_iterator(sm)
		testing.expect_value(ctx.t, sm_it_init_err, nil)
		_, sm_iter_err := xitdb.cursor_iterator_next(&sm_it)
		testing.expect_value(ctx.t, sm_iter_err, xitdb.Xitdb_Error.Unexpected_Tag)
		_, sm_node_err := xitdb.read_sorted_node(&db, sm_child0_slot.value)
		testing.expect_value(ctx.t, sm_node_err, xitdb.Xitdb_Error.Unexpected_Tag)

		// Restore `sm` leaf tag byte
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, sm_leaf0_tag_pos), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, orig_sm_tag_byte[:]), nil)

		// 5. Corrupt a slot tag byte (`99`) in `hm` root index block:
		// Verify `hash_map_iterator(hm)` returns `.Unexpected_Tag`
		orig_hm_tag_byte: [1]u8
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		testing.expect_value(ctx.t, xitdb.core_read_exact(&core, orig_hm_tag_byte[:]), nil)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, []u8{99}), nil)

		_, hm_iter_err := xitdb.hash_map_iterator(hm)
		testing.expect_value(ctx.t, hm_iter_err, xitdb.Xitdb_Error.Unexpected_Tag)

		// Restore `hm` tag byte
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, orig_hm_tag_byte[:]), nil)

		// 5b. Corrupt `hm` root index block into a self-referential `.Index` cycle:
		// Verify `hash_map_get_cursor` and `remove_map_slot` return `.Key_Offset_Exceeded` without out-of-bounds panic
		orig_hm_block: [xitdb.INDEX_BLOCK_SIZE]u8
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		testing.expect_value(ctx.t, xitdb.core_read_exact(&core, orig_hm_block[:]), nil)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		for _ in 0 ..< xitdb.SLOT_COUNT {
			testing.expect_value(ctx.t, xitdb.core_write_slot(&core, xitdb.Slot{value = hm_slot.value, tag = .Index}), nil)
		}
		_, hm_cycle_get_err := xitdb.hash_map_get_cursor(hm, "alpha")
		testing.expect_value(ctx.t, hm_cycle_get_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)
		cycle_hash := make([]u8, int(db.header.hash_size), context.temp_allocator)
		_, hm_cycle_rem_err := xitdb.remove_map_slot(&db, hm_slot.value, cycle_hash, 0, 0)
		testing.expect_value(ctx.t, hm_cycle_rem_err, xitdb.Xitdb_Error.Key_Offset_Exceeded)
		testing.expect_value(ctx.t, xitdb.core_seek_to(&core, hm_slot.value), nil)
		testing.expect_value(ctx.t, xitdb.core_write_all(&core, orig_hm_block[:]), nil)

		// 6. Mid-node truncation of `sm` child 0 leaf (truncate right in the middle of the 146-byte leaf block):
		// Verify `read_sorted_node` and `sorted_map_iterator` return `.Unexpected_EOF`
		testing.expect_value(ctx.t, xitdb.core_set_length(&core, sm_child0_slot.value + 30), nil)
		_, sm_trunc_node_err := xitdb.read_sorted_node(&db, sm_child0_slot.value)
		testing.expect_value(ctx.t, sm_trunc_node_err, xitdb.Xitdb_Error.Unexpected_EOF)
		_, sm_trunc_err := xitdb.sorted_map_iterator(sm)
		testing.expect_value(ctx.t, sm_trunc_err, xitdb.Xitdb_Error.Unexpected_EOF)
	}
}





