#+vet unused shadowing using-stmt style semicolon tabs
package xitdb_tests

import "base:runtime"
import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import xitdb "../xitdb"

@(private = "file")
SIM_FUZZ_SEED :: #config(ODIN_FUZZ_SEED, u64(0x5849544442_2026))
@(private = "file")
SIM_FUZZ_OPS :: #config(ODIN_FUZZ_OPS, 200)

@(private = "file")
Sim_Op_Kind :: enum u8 {
	HM_Put,
	HM_Remove,
	CHM_Put,
	CHM_Remove,
	SM_Put,
	SM_Remove,
	Arr_Append,
	Arr_Put,
	Arr_Slice,
	LL_Append,
	LL_Insert,
	LL_Put,
	LL_Remove,
	LL_Slice,
	HS_Put,
	HS_Remove,
	CHS_Put,
	CHS_Remove,
	SS_Put,
	SS_Remove,
}

@(private = "file")
Sim_Op :: struct {
	kind:   Sim_Op_Kind,
	key:    string,
	val:    string,
	index:  i64,
	offset: i64,
	size:   i64,
}

@(private = "file")
Sim_Batch :: struct {
	ops: []Sim_Op,
}

@(private = "file")
Sim_Moment :: struct {
	hm:  map[string]string,
	chm: map[string]string,
	sm:  map[string]string,
	arr: [dynamic]string,
	ll:  [dynamic]string,
	hs:  map[string]struct{},
	chs: map[string]struct{},
	ss:  map[string]struct{},
}

@(private = "file")
_empty_moment :: proc() -> Sim_Moment {
	return Sim_Moment{
		hm  = make(map[string]string, 8),
		chm = make(map[string]string, 8),
		sm  = make(map[string]string, 8),
		arr = make([dynamic]string, 0, 8),
		ll  = make([dynamic]string, 0, 8),
		hs  = make(map[string]struct{}, 8),
		chs = make(map[string]struct{}, 8),
		ss  = make(map[string]struct{}, 8),
	}
}

@(private = "file")
_clone_moment :: proc(src: Sim_Moment) -> Sim_Moment {
	dst := _empty_moment()
	for k, v in src.hm {
		dst.hm[strings.clone(k)] = strings.clone(v)
	}
	for k, v in src.chm {
		dst.chm[strings.clone(k)] = strings.clone(v)
	}
	for k, v in src.sm {
		dst.sm[strings.clone(k)] = strings.clone(v)
	}
	for v in src.arr {
		append(&dst.arr, strings.clone(v))
	}
	for v in src.ll {
		append(&dst.ll, strings.clone(v))
	}
	for k in src.hs {
		dst.hs[strings.clone(k)] = {}
	}
	for k in src.chs {
		dst.chs[strings.clone(k)] = {}
	}
	for k in src.ss {
		dst.ss[strings.clone(k)] = {}
	}
	return dst
}

@(private = "file")
_destroy_moment :: proc(m: ^Sim_Moment) {
	for k, v in m.hm {
		delete(k)
		delete(v)
	}
	delete(m.hm)
	for k, v in m.chm {
		delete(k)
		delete(v)
	}
	delete(m.chm)
	for k, v in m.sm {
		delete(k)
		delete(v)
	}
	delete(m.sm)
	for v in m.arr {
		delete(v)
	}
	delete(m.arr)
	for v in m.ll {
		delete(v)
	}
	delete(m.ll)
	for k in m.hs {
		delete(k)
	}
	delete(m.hs)
	for k in m.chs {
		delete(k)
	}
	delete(m.chs)
	for k in m.ss {
		delete(k)
	}
	delete(m.ss)
}

@(private = "file")
_map_put_owned :: proc(m: ^map[string]string, k, v: string) {
	if k in m {
		old_k, old_v := delete_key(m, k)
		delete(old_k)
		delete(old_v)
	}
	m[strings.clone(k)] = strings.clone(v)
}

@(private = "file")
_map_del_owned :: proc(m: ^map[string]string, k: string) {
	if k in m {
		old_k, old_v := delete_key(m, k)
		delete(old_k)
		delete(old_v)
	}
}

@(private = "file")
_set_put_owned :: proc(s: ^map[string]struct{}, k: string) {
	if k in s {
		return
	}
	s[strings.clone(k)] = {}
}

@(private = "file")
_set_del_owned :: proc(s: ^map[string]struct{}, k: string) {
	if k in s {
		old_k, _ := delete_key(s, k)
		delete(old_k)
	}
}

@(private = "file")
_sim_key :: proc(rng: runtime.Random_Generator) -> string {
	bucket := rand.int_max(3, rng)
	switch bucket {
	case 0:
		idx := rand.int_max(10, rng)
		return fmt.tprintf("k%d", idx)
	case 1:
		idx := rand.int_max(40, rng)
		return fmt.tprintf("pfx_%02d", idx)
	case:
		idx := rand.int_max(16, rng)
		return fmt.tprintf("long_external_key_prefix_%02d", idx)
	}
}

@(private = "file")
_sim_val :: proc(step: int, op_idx: int, rng: runtime.Random_Generator) -> string {
	switch rand.int_max(3, rng) {
	case 0:
		return fmt.tprintf("v%d_%d", step, op_idx)
	case 1:
		return fmt.tprintf("s%d", rand.int_max(99, rng))
	case:
		return fmt.tprintf("external_payload_value_%d_%d_abcdef", step, op_idx)
	}
}

@(private = "file")
_apply_model_op :: proc(m: ^Sim_Moment, op: Sim_Op) {
	switch op.kind {
	case .HM_Put:
		_map_put_owned(&m.hm, op.key, op.val)
	case .HM_Remove:
		_map_del_owned(&m.hm, op.key)
	case .CHM_Put:
		_map_put_owned(&m.chm, op.key, op.val)
	case .CHM_Remove:
		_map_del_owned(&m.chm, op.key)
	case .SM_Put:
		_map_put_owned(&m.sm, op.key, op.val)
	case .SM_Remove:
		_map_del_owned(&m.sm, op.key)
	case .Arr_Append:
		append(&m.arr, strings.clone(op.val))
	case .Arr_Put:
		idx := int(op.index)
		delete(m.arr[idx])
		m.arr[idx] = strings.clone(op.val)
	case .Arr_Slice:
		sz := int(op.size)
		for i in sz ..< len(m.arr) {
			delete(m.arr[i])
		}
		resize(&m.arr, sz)
	case .LL_Append:
		append(&m.ll, strings.clone(op.val))
	case .LL_Insert:
		idx := int(op.index)
		inject_at(&m.ll, idx, strings.clone(op.val))
	case .LL_Put:
		idx := int(op.index)
		delete(m.ll[idx])
		m.ll[idx] = strings.clone(op.val)
	case .LL_Remove:
		idx := int(op.index)
		delete(m.ll[idx])
		ordered_remove(&m.ll, idx)
	case .LL_Slice:
		off := int(op.offset)
		sz := int(op.size)
		for i in 0 ..< off {
			delete(m.ll[i])
		}
		for i in (off + sz) ..< len(m.ll) {
			delete(m.ll[i])
		}
		if off > 0 {
			copy(m.ll[:sz], m.ll[off : off + sz])
		}
		resize(&m.ll, sz)
	case .HS_Put:
		_set_put_owned(&m.hs, op.key)
	case .HS_Remove:
		_set_del_owned(&m.hs, op.key)
	case .CHS_Put:
		_set_put_owned(&m.chs, op.key)
	case .CHS_Remove:
		_set_del_owned(&m.chs, op.key)
	case .SS_Put:
		_set_put_owned(&m.ss, op.key)
	case .SS_Remove:
		_set_del_owned(&m.ss, op.key)
	}
}

@(private = "file")
_apply_sim_batch_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
	batch := (^Sim_Batch)(user_data)
	moment := xitdb.write_hash_map_init(cursor^) or_return

	for op in batch.ops {
		switch op.kind {
		case .HM_Put:
			c := xitdb.hash_map_put_cursor(&moment, "hm") or_return
			hm := xitdb.write_hash_map_init(c) or_return
			xitdb.hash_map_put(&hm, op.key, op.val) or_return
		case .HM_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "hm") or_return
			hm := xitdb.write_hash_map_init(c) or_return
			_, _ = xitdb.hash_map_remove(&hm, op.key)
		case .CHM_Put:
			c := xitdb.hash_map_put_cursor(&moment, "chm") or_return
			chm := xitdb.write_counted_hash_map_init(c) or_return
			xitdb.hash_map_put(&chm.write_hash_map, op.key, op.val) or_return
		case .CHM_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "chm") or_return
			chm := xitdb.write_counted_hash_map_init(c) or_return
			_, _ = xitdb.hash_map_remove(&chm.write_hash_map, op.key)
		case .SM_Put:
			c := xitdb.hash_map_put_cursor(&moment, "sm") or_return
			sm := xitdb.write_sorted_map_init(c) or_return
			xitdb.sorted_map_put(&sm, op.key, op.val) or_return
		case .SM_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "sm") or_return
			sm := xitdb.write_sorted_map_init(c) or_return
			_, _ = xitdb.sorted_map_remove(&sm, op.key)
		case .Arr_Append:
			c := xitdb.hash_map_put_cursor(&moment, "arr") or_return
			arr := xitdb.write_array_list_init(c) or_return
			xitdb.array_list_append(&arr, op.val) or_return
		case .Arr_Put:
			c := xitdb.hash_map_put_cursor(&moment, "arr") or_return
			arr := xitdb.write_array_list_init(c) or_return
			xitdb.array_list_put(&arr, op.index, op.val) or_return
		case .Arr_Slice:
			c := xitdb.hash_map_put_cursor(&moment, "arr") or_return
			arr := xitdb.write_array_list_init(c) or_return
			xitdb.array_list_slice(&arr, op.size) or_return
		case .LL_Append:
			c := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(c) or_return
			xitdb.linked_array_list_append(&ll, op.val) or_return
		case .LL_Insert:
			c := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(c) or_return
			xitdb.linked_array_list_insert(&ll, op.index, op.val) or_return
		case .LL_Put:
			c := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(c) or_return
			xitdb.linked_array_list_put(&ll, op.index, op.val) or_return
		case .LL_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(c) or_return
			xitdb.linked_array_list_remove(&ll, op.index) or_return
		case .LL_Slice:
			c := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(c) or_return
			xitdb.linked_array_list_slice(&ll, op.offset, op.size) or_return
		case .HS_Put:
			c := xitdb.hash_map_put_cursor(&moment, "hs") or_return
			hs := xitdb.write_hash_set_init(c) or_return
			xitdb.hash_set_put(&hs, op.key) or_return
		case .HS_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "hs") or_return
			hs := xitdb.write_hash_set_init(c) or_return
			_, _ = xitdb.hash_set_remove(&hs, op.key)
		case .CHS_Put:
			c := xitdb.hash_map_put_cursor(&moment, "chs") or_return
			chs := xitdb.write_counted_hash_set_init(c) or_return
			xitdb.hash_set_put(&chs.write_hash_set, op.key) or_return
		case .CHS_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "chs") or_return
			chs := xitdb.write_counted_hash_set_init(c) or_return
			_, _ = xitdb.hash_set_remove(&chs.write_hash_set, op.key)
		case .SS_Put:
			c := xitdb.hash_map_put_cursor(&moment, "ss") or_return
			ss := xitdb.write_sorted_set_init(c) or_return
			xitdb.sorted_set_put(&ss, op.key) or_return
		case .SS_Remove:
			c := xitdb.hash_map_put_cursor(&moment, "ss") or_return
			ss := xitdb.write_sorted_set_init(c) or_return
			_, _ = xitdb.sorted_set_remove(&ss, op.key)
		}
	}
	return nil
}

@(private = "file")
_gen_op :: proc(m: ^Sim_Moment, step: int, op_idx: int, rng: runtime.Random_Generator) -> Sim_Op {
	pick := rand.int_max(20, rng)
	kind := Sim_Op_Kind(pick)

	switch kind {
	case .Arr_Put:
		if len(m.arr) == 0 {
			kind = .Arr_Append
		} else {
			return Sim_Op{
				kind  = .Arr_Put,
				val   = _sim_val(step, op_idx, rng),
				index = i64(rand.int_max(len(m.arr), rng)),
			}
		}
	case .Arr_Slice:
		if len(m.arr) == 0 {
			kind = .Arr_Append
		} else {
			return Sim_Op{
				kind = .Arr_Slice,
				size = i64(rand.int_max(len(m.arr) + 1, rng)),
			}
		}
	case .LL_Insert:
		if len(m.ll) == 0 {
			kind = .LL_Append
		} else {
			return Sim_Op{
				kind  = .LL_Insert,
				val   = _sim_val(step, op_idx, rng),
				index = i64(rand.int_max(len(m.ll), rng)),
			}
		}
	case .LL_Put:
		if len(m.ll) == 0 {
			kind = .LL_Append
		} else {
			return Sim_Op{
				kind  = .LL_Put,
				val   = _sim_val(step, op_idx, rng),
				index = i64(rand.int_max(len(m.ll), rng)),
			}
		}
	case .LL_Remove:
		if len(m.ll) == 0 {
			kind = .LL_Append
		} else {
			return Sim_Op{
				kind  = .LL_Remove,
				index = i64(rand.int_max(len(m.ll), rng)),
			}
		}
	case .LL_Slice:
		if len(m.ll) == 0 {
			kind = .LL_Append
		} else {
			off := rand.int_max(len(m.ll), rng)
			rem := len(m.ll) - off
			sz := rand.int_max(rem + 1, rng)
			return Sim_Op{
				kind   = .LL_Slice,
				offset = i64(off),
				size   = i64(sz),
			}
		}
	case .HM_Put, .HM_Remove, .CHM_Put, .CHM_Remove, .SM_Put, .SM_Remove,
	     .Arr_Append, .LL_Append, .HS_Put, .HS_Remove, .CHS_Put, .CHS_Remove,
	     .SS_Put, .SS_Remove:
	}

	return Sim_Op{
		kind = kind,
		key  = _sim_key(rng),
		val  = _sim_val(step, op_idx, rng),
	}
}

@(private = "file")
_verify_moment_matches_oracle :: proc(t: ^testing.T, db: ^xitdb.Database, moment_idx: i64, m: Sim_Moment) {
	rc := xitdb.database_root_cursor(db).read_cursor
	hist, herr := xitdb.read_array_list_init(rc)
	testing.expect_value(t, herr, nil)

	cur_maybe, cerr := xitdb.array_list_get_cursor(hist, moment_idx)
	testing.expect_value(t, cerr, nil)
	moment_cur, ok_m := cur_maybe.?
	testing.expect(t, ok_m)
	if !ok_m {
		return
	}
	moment_hm, mh_err := xitdb.read_hash_map_init(moment_cur)
	testing.expect_value(t, mh_err, nil)

	// 1. Hash_Map
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "hm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			hm, hm_err := xitdb.read_hash_map_init(sub_cur)
			testing.expect_value(t, hm_err, nil)
			_verify_hash_map_like(t, hm, m.hm, false)
		} else {
			testing.expect_value(t, len(m.hm), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	// 2. Counted_Hash_Map
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "chm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			chm, chm_err := xitdb.read_counted_hash_map_init(sub_cur)
			testing.expect_value(t, chm_err, nil)
			cnt, cnt_err := xitdb.counted_hash_map_count(chm)
			testing.expect_value(t, cnt_err, nil)
			testing.expect_value(t, cnt, i64(len(m.chm)))
			_verify_hash_map_like(t, chm.read_hash_map, m.chm, true)
		} else {
			testing.expect_value(t, len(m.chm), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	// 3. Sorted_Map (order, rank, index lookup, forward/reverse iterators, seek)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "sm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			sm, sm_err := xitdb.read_sorted_map_init(sub_cur)
			testing.expect_value(t, sm_err, nil)
			_verify_sorted_map(t, sm, m.sm)
		} else {
			testing.expect_value(t, len(m.sm), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	// 4. Array_List (count, index, forward/reverse iterator)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "arr"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			arr, arr_err := xitdb.read_array_list_init(sub_cur)
			testing.expect_value(t, arr_err, nil)
			_verify_array_list(t, arr, m.arr[:])
		} else {
			testing.expect_value(t, len(m.arr), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	// 5. Linked_Array_List (count, index, forward/reverse iterator)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "ll"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			ll, ll_err := xitdb.read_linked_array_list_init(sub_cur)
			testing.expect_value(t, ll_err, nil)
			_verify_linked_list(t, ll, m.ll[:])
		} else {
			testing.expect_value(t, len(m.ll), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	// 6. Hash_Set / Counted_Hash_Set / Sorted_Set
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "hs"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			hs, hs_err := xitdb.read_hash_set_init(sub_cur)
			testing.expect_value(t, hs_err, nil)
			_verify_hash_set_like(t, hs, m.hs)
		} else {
			testing.expect_value(t, len(m.hs), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "chs"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			chs, chs_err := xitdb.read_counted_hash_set_init(sub_cur)
			testing.expect_value(t, chs_err, nil)
			cnt, cnt_err := xitdb.counted_hash_set_count(chs)
			testing.expect_value(t, cnt_err, nil)
			testing.expect_value(t, cnt, i64(len(m.chs)))
			_verify_hash_set_like(t, chs.read_hash_set, m.chs)
		} else {
			testing.expect_value(t, len(m.chs), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}

	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "ss"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			ss, ss_err := xitdb.read_sorted_set_init(sub_cur)
			testing.expect_value(t, ss_err, nil)
			_verify_sorted_set(t, ss, m.ss)
		} else {
			testing.expect_value(t, len(m.ss), 0)
		}
	} else {
		testing.expect_value(t, serr, nil)
	}
}

@(private = "file")
_verify_hash_map_like :: proc(t: ^testing.T, hm: xitdb.Read_Hash_Map, expected: map[string]string, _is_counted: bool) {
	for k, v in expected {
		vc_maybe, gerr := xitdb.hash_map_get_cursor(hm, k)
		testing.expect_value(t, gerr, nil)
		vc, ok := vc_maybe.?
		testing.expect(t, ok)
		if ok {
			got, rerr := xitdb.cursor_read_string(vc, 0, context.temp_allocator)
			testing.expect_value(t, rerr, nil)
			testing.expect_value(t, got, v)
		}
	}

	fwd := make([dynamic]string, 0, len(expected), context.temp_allocator)
	it, ierr := xitdb.hash_map_iterator(hm)
	testing.expect_value(t, ierr, nil)
	for {
		item_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		v, verr := xitdb.cursor_read_string(kv.value_cursor, 0, context.temp_allocator)
		testing.expect_value(t, verr, nil)
		testing.expect_value(t, expected[k], v)
		append(&fwd, k)
	}
	testing.expect_value(t, len(fwd), len(expected))

	rev := make([dynamic]string, 0, len(expected), context.temp_allocator)
	rit, rierr := xitdb.hash_map_iterator_reverse(hm)
	testing.expect_value(t, rierr, nil)
	for {
		item_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		append(&rev, k)
	}
	testing.expect_value(t, len(rev), len(fwd))
	if len(rev) == len(fwd) {
		for i in 0 ..< len(fwd) {
			testing.expect_value(t, rev[i], fwd[len(fwd) - 1 - i])
		}
	}
}

@(private = "file")
_verify_sorted_map :: proc(t: ^testing.T, sm: xitdb.Read_Sorted_Map, expected: map[string]string) {
	cnt, cnt_err := xitdb.sorted_map_count(sm)
	testing.expect_value(t, cnt_err, nil)
	testing.expect_value(t, cnt, i64(len(expected)))

	sorted_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	for k in expected {
		append(&sorted_keys, k)
	}
	slice.sort(sorted_keys[:])

	it, ierr := xitdb.sorted_map_iterator(sm)
	testing.expect_value(t, ierr, nil)
	idx := 0
	for {
		item_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		v, verr := xitdb.cursor_read_string(kv.value_cursor, 0, context.temp_allocator)
		testing.expect_value(t, verr, nil)
		testing.expect(t, idx < len(sorted_keys))
		if idx < len(sorted_keys) {
			testing.expect_value(t, k, sorted_keys[idx])
			testing.expect_value(t, v, expected[sorted_keys[idx]])
		}
		idx += 1
	}
	testing.expect_value(t, idx, len(sorted_keys))

	// Verify reverse iterator order
	rit, rierr := xitdb.sorted_map_iterator_reverse(sm)
	testing.expect_value(t, rierr, nil)
	ridx := len(sorted_keys) - 1
	for {
		item_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		testing.expect(t, ridx >= 0)
		if ridx >= 0 {
			testing.expect_value(t, k, sorted_keys[ridx])
		}
		ridx -= 1
	}
	testing.expect_value(t, ridx, -1)

	// Verify rank, index lookup, and seek bounds
	for k, i in sorted_keys {
		rk, rkerr := xitdb.sorted_map_rank(sm, k)
		testing.expect_value(t, rkerr, nil)
		testing.expect_value(t, rk, i64(i))

		ikv_maybe, ikerr := xitdb.sorted_map_get_index_kv_pair(sm, i64(i), context.temp_allocator)
		testing.expect_value(t, ikerr, nil)
		ikv, has_ikv := ikv_maybe.?
		testing.expect(t, has_ikv)
		if has_ikv {
			ik, kerr := xitdb.cursor_read_string(ikv.key_cursor, 0, context.temp_allocator)
			testing.expect_value(t, kerr, nil)
			testing.expect_value(t, ik, k)
		}
	}

	if len(sorted_keys) > 0 {
		mid_key := sorted_keys[len(sorted_keys) / 2]
		sit, sierr := xitdb.sorted_map_iterator_from_string(sm, mid_key)
		testing.expect_value(t, sierr, nil)
		first_maybe, fnerr := xitdb.cursor_iterator_next(&sit)
		testing.expect_value(t, fnerr, nil)
		if first, ok_f := first_maybe.?; ok_f {
			kv, kverr := xitdb.cursor_read_kv_pair(first, context.temp_allocator)
			testing.expect_value(t, kverr, nil)
			fk, fkerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
			testing.expect_value(t, fkerr, nil)
			testing.expect_value(t, fk, mid_key)
		} else {
			testing.expect(t, false)
		}

		rsit, rsierr := xitdb.sorted_map_iterator_reverse_from_string(sm, mid_key, true)
		testing.expect_value(t, rsierr, nil)
		rlast_maybe, rperr := xitdb.cursor_iterator_prev(&rsit)
		testing.expect_value(t, rperr, nil)
		if rlast, ok_r := rlast_maybe.?; ok_r {
			kv, kverr := xitdb.cursor_read_kv_pair(rlast, context.temp_allocator)
			testing.expect_value(t, kverr, nil)
			rk, rkerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
			testing.expect_value(t, rkerr, nil)
			testing.expect_value(t, rk, mid_key)
		} else {
			testing.expect(t, false)
		}
	}
}

@(private = "file")
_verify_array_list :: proc(t: ^testing.T, arr: xitdb.Read_Array_List, expected: []string) {
	cnt, cnt_err := xitdb.array_list_count(arr)
	testing.expect_value(t, cnt_err, nil)
	testing.expect_value(t, cnt, i64(len(expected)))

	for exp_v, idx in expected {
		c_maybe, gerr := xitdb.array_list_get_cursor(arr, i64(idx))
		testing.expect_value(t, gerr, nil)
		c, ok := c_maybe.?
		testing.expect(t, ok)
		if ok {
			got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
			testing.expect_value(t, rerr, nil)
			testing.expect_value(t, got, exp_v)
		}
	}

	it, ierr := xitdb.array_list_iterator(arr)
	testing.expect_value(t, ierr, nil)
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, idx < len(expected))
		if idx < len(expected) {
			testing.expect_value(t, got, expected[idx])
		}
		idx += 1
	}
	testing.expect_value(t, idx, len(expected))

	rit, rierr := xitdb.array_list_iterator_reverse(arr)
	testing.expect_value(t, rierr, nil)
	ridx := len(expected) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, ridx >= 0)
		if ridx >= 0 {
			testing.expect_value(t, got, expected[ridx])
		}
		ridx -= 1
	}
	testing.expect_value(t, ridx, -1)
}

@(private = "file")
_verify_linked_list :: proc(t: ^testing.T, ll: xitdb.Read_Linked_Array_List, expected: []string) {
	cnt, cnt_err := xitdb.linked_array_list_count(ll)
	testing.expect_value(t, cnt_err, nil)
	testing.expect_value(t, cnt, i64(len(expected)))

	for exp_v, idx in expected {
		c_maybe, gerr := xitdb.linked_array_list_get_cursor(ll, i64(idx))
		testing.expect_value(t, gerr, nil)
		c, ok := c_maybe.?
		testing.expect(t, ok)
		if ok {
			got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
			testing.expect_value(t, rerr, nil)
			testing.expect_value(t, got, exp_v)
		}
	}

	it, ierr := xitdb.linked_array_list_iterator(ll)
	testing.expect_value(t, ierr, nil)
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, idx < len(expected))
		if idx < len(expected) {
			testing.expect_value(t, got, expected[idx])
		}
		idx += 1
	}
	testing.expect_value(t, idx, len(expected))

	rit, rierr := xitdb.linked_array_list_iterator_reverse(ll)
	testing.expect_value(t, rierr, nil)
	ridx := len(expected) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, ridx >= 0)
		if ridx >= 0 {
			testing.expect_value(t, got, expected[ridx])
		}
		ridx -= 1
	}
	testing.expect_value(t, ridx, -1)
}

@(private = "file")
_verify_hash_set_like :: proc(t: ^testing.T, hs: xitdb.Read_Hash_Set, expected: map[string]struct{}) {
	for k in expected {
		c_maybe, gerr := xitdb.hash_set_get_cursor(hs, k)
		testing.expect_value(t, gerr, nil)
		_, ok := c_maybe.?
		testing.expect(t, ok)
	}

	fwd_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	it, ierr := xitdb.hash_set_iterator(hs)
	testing.expect_value(t, ierr, nil)
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, rerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		testing.expect(t, k in expected)
		append(&fwd_keys, k)
	}
	testing.expect_value(t, len(fwd_keys), len(expected))

	rev_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	rit, rierr := xitdb.hash_set_iterator_reverse(hs)
	testing.expect_value(t, rierr, nil)
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, rerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, rerr, nil)
		append(&rev_keys, k)
	}
	testing.expect_value(t, len(rev_keys), len(fwd_keys))
	if len(rev_keys) == len(fwd_keys) {
		for i in 0 ..< len(fwd_keys) {
			testing.expect_value(t, rev_keys[i], fwd_keys[len(fwd_keys) - 1 - i])
		}
	}
}

@(private = "file")
_verify_sorted_set :: proc(t: ^testing.T, ss: xitdb.Read_Sorted_Set, expected: map[string]struct{}) {
	cnt, cnt_err := xitdb.sorted_set_count(ss)
	testing.expect_value(t, cnt_err, nil)
	testing.expect_value(t, cnt, i64(len(expected)))

	sorted_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	for k in expected {
		append(&sorted_keys, k)
	}
	slice.sort(sorted_keys[:])

	it, ierr := xitdb.sorted_set_iterator(ss)
	testing.expect_value(t, ierr, nil)
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		testing.expect_value(t, nerr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		testing.expect(t, idx < len(sorted_keys))
		if idx < len(sorted_keys) {
			testing.expect_value(t, k, sorted_keys[idx])
		}
		idx += 1
	}
	testing.expect_value(t, idx, len(sorted_keys))

	rit, rierr := xitdb.sorted_set_iterator_reverse(ss)
	testing.expect_value(t, rierr, nil)
	ridx := len(sorted_keys) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		testing.expect_value(t, perr, nil)
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		testing.expect_value(t, kverr, nil)
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		testing.expect_value(t, kerr, nil)
		testing.expect(t, ridx >= 0)
		if ridx >= 0 {
			testing.expect_value(t, k, sorted_keys[ridx])
		}
		ridx -= 1
	}
	testing.expect_value(t, ridx, -1)
}

@(private = "file")
_verify_diff_collection_parity :: proc(
	t: ^testing.T,
	db: ^xitdb.Database,
	m_a: i64,
	m_b: i64,
	oracle_a: Sim_Moment,
	oracle_b: Sim_Moment,
) {
	rc := xitdb.database_root_cursor(db).read_cursor
	hist, herr := xitdb.read_array_list_init(rc)
	testing.expect_value(t, herr, nil)

	ca_maybe, ca_err := xitdb.array_list_get_cursor(hist, m_a)
	testing.expect_value(t, ca_err, nil)
	cb_maybe, cb_err := xitdb.array_list_get_cursor(hist, m_b)
	testing.expect_value(t, cb_err, nil)
	ca, oka := ca_maybe.?
	cb, okb := cb_maybe.?
	if !oka || !okb {
		testing.expect(t, false)
		return
	}

	hma, hma_err := xitdb.read_hash_map_init(ca)
	testing.expect_value(t, hma_err, nil)
	hmb, hmb_err := xitdb.read_hash_map_init(cb)
	testing.expect_value(t, hmb_err, nil)

	for bucket in ([?]string{"hm", "sm"}) {
		suba_maybe, sa_err := xitdb.hash_map_get_cursor(hma, bucket)
		testing.expect_value(t, sa_err, nil)
		subb_maybe, sb_err := xitdb.hash_map_get_cursor(hmb, bucket)
		testing.expect_value(t, sb_err, nil)

		suba, has_a := suba_maybe.?
		subb, has_b := subb_maybe.?
		if !has_a || !has_b {
			continue
		}

		changes, derr := xitdb.diff_collection(suba, subb, context.temp_allocator)
		testing.expect_value(t, derr, nil)

		map_a := oracle_a.hm if bucket == "hm" else oracle_a.sm
		map_b := oracle_b.hm if bucket == "hm" else oracle_b.sm

		expected_count := 0
		for k, va in map_a {
			vb, exists_b := map_b[k]
			if !exists_b || vb != va {
				expected_count += 1
			}
		}
		for k in map_b {
			if !(k in map_a) {
				expected_count += 1
			}
		}
		testing.expect_value(t, len(changes), expected_count)

		for chg in changes {
			k := string(chg.key)
			va, in_a := map_a[k]
			vb, in_b := map_b[k]
			switch chg.op {
			case .Added:
				testing.expect(t, !in_a && in_b)
			case .Removed:
				testing.expect(t, in_a && !in_b)
			case .Changed:
				testing.expect(t, in_a && in_b && va != vb)
			}
		}
	}
}

@(private = "file")
_run_simulation :: proc(t: ^testing.T, seed: u64, num_ops: int, hasher: xitdb.Hasher, tag: string) {
	defer free_all(context.temp_allocator)

	rng_state := rand.create(seed)
	rng := runtime.default_random_generator(&rng_state)

	mem_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
	defer xitdb.core_destroy(&mem_core)
	mem_db, mem_err := xitdb.database_init(&mem_core, hasher)
	testing.expect_value(t, mem_err, nil)

	tmp_dir, td_err := os.temp_directory(context.temp_allocator)
	testing.expect_value(t, td_err, nil)
	bf_path := fmt.tprintf("%s/xitdb_sim_%s_%d.xit", tmp_dir, tag, seed)
	_ = os.remove(bf_path)
	bf_core, bf_open_err := xitdb.core_buffered_file_open(
		bf_path,
		4096,
		{.Read, .Write, .Create, .Trunc},
		false,
		context.allocator,
	)
	testing.expect_value(t, bf_open_err, nil)
	defer {
		_ = xitdb.core_destroy(&bf_core, close_file = true)
		_ = os.remove(bf_path)
	}
	bf_db, bf_err := xitdb.database_init(&bf_core, hasher)
	testing.expect_value(t, bf_err, nil)

	moments := make([dynamic]Sim_Moment, 0, num_ops)
	defer {
		for &m in moments {
			_destroy_moment(&m)
		}
		delete(moments)
	}

	for step in 0 ..< num_ops {
		defer free_all(context.temp_allocator)

		base_idx := -1
		base_slot := xitdb.Slot{}
		next_model: Sim_Moment
		if len(moments) == 0 {
			next_model = _empty_moment()
		} else {
			if rand.int_max(5, rng) == 0 {
				base_idx = rand.int_max(len(moments), rng)
			} else {
				base_idx = len(moments) - 1
			}
			next_model = _clone_moment(moments[base_idx])

			m_rc := xitdb.database_root_cursor(&mem_db).read_cursor
			m_hist, mh_err := xitdb.read_array_list_init(m_rc)
			testing.expect_value(t, mh_err, nil)
			slot_maybe, s_err := xitdb.array_list_get_slot(m_hist, i64(base_idx))
			testing.expect_value(t, s_err, nil)
			slot_ok := false
			base_slot, slot_ok = slot_maybe.?
			testing.expect(t, slot_ok)
		}

		batch_len := 1 + rand.int_max(4, rng)
		ops_buf: [4]Sim_Op
		for j in 0 ..< batch_len {
			op := _gen_op(&next_model, step, j, rng)
			ops_buf[j] = op
			_apply_model_op(&next_model, op)
		}
		batch := Sim_Batch{ops = ops_buf[:batch_len]}

		m_root := xitdb.database_root_cursor(&mem_db)
		m_hist_w, mhw_err := xitdb.write_array_list_init(m_root)
		testing.expect_value(t, mhw_err, nil)
		tx_m_err := xitdb.array_list_append_context(&m_hist_w, base_slot, _apply_sim_batch_cb, &batch)
		testing.expect_value(t, tx_m_err, nil)

		bf_base_slot := xitdb.Slot{}
		if base_idx >= 0 {
			b_rc := xitdb.database_root_cursor(&bf_db).read_cursor
			b_hist, bh_err := xitdb.read_array_list_init(b_rc)
			testing.expect_value(t, bh_err, nil)
			bs_maybe, bs_err := xitdb.array_list_get_slot(b_hist, i64(base_idx))
			testing.expect_value(t, bs_err, nil)
			bs_ok := false
			bf_base_slot, bs_ok = bs_maybe.?
			testing.expect(t, bs_ok)
		}
		b_root := xitdb.database_root_cursor(&bf_db)
		b_hist_w, bhw_err := xitdb.write_array_list_init(b_root)
		testing.expect_value(t, bhw_err, nil)
		tx_b_err := xitdb.array_list_append_context(&b_hist_w, bf_base_slot, _apply_sim_batch_cb, &batch)
		testing.expect_value(t, tx_b_err, nil)

		append(&moments, next_model)
		new_idx := i64(len(moments) - 1)

		_verify_moment_matches_oracle(t, &mem_db, new_idx, moments[len(moments) - 1])
		_verify_moment_matches_oracle(t, &bf_db, new_idx, moments[len(moments) - 1])

		// Check historical moment retention on random prior snapshot
		if len(moments) > 2 {
			hist_check := rand.int_max(len(moments) - 1, rng)
			_verify_moment_matches_oracle(t, &mem_db, i64(hist_check), moments[hist_check])
		}

		// Periodic overlay, compaction, and collection diff verification
		if step > 0 && step % 25 == 0 {
			committed_sz, csz_err := xitdb.database_committed_size(&mem_db)
			testing.expect_value(t, csz_err, nil)

			ov_core, ov_err := xitdb.core_overlay_init(&mem_core, committed_sz, context.allocator)
			testing.expect_value(t, ov_err, nil)
			ov_db, ov_derr := xitdb.database_init(&ov_core, hasher)
			testing.expect_value(t, ov_derr, nil)

			ov_model := _clone_moment(moments[len(moments) - 1])
			ov_op := Sim_Op{kind = .SM_Put, key = "overlay_only_key", val = "overlay_only_val"}
			_apply_model_op(&ov_model, ov_op)
			ov_ops := [1]Sim_Op{ov_op}
			ov_batch := Sim_Batch{ops = ov_ops[:]}

			ov_root := xitdb.database_root_cursor(&ov_db)
			ov_hist_w, ohw_err := xitdb.write_array_list_init(ov_root)
			testing.expect_value(t, ohw_err, nil)
			ov_latest_maybe, ol_err := xitdb.array_list_get_slot(ov_hist_w.read_array_list, -1)
			testing.expect_value(t, ol_err, nil)
			ov_base := ov_latest_maybe.?
			ov_tx_err := xitdb.array_list_append_context(&ov_hist_w, ov_base, _apply_sim_batch_cb, &ov_batch)
			testing.expect_value(t, ov_tx_err, nil)

			_verify_moment_matches_oracle(t, &ov_db, -1, ov_model)
			_verify_moment_matches_oracle(t, &mem_db, -1, moments[len(moments) - 1])
			_destroy_moment(&ov_model)
			_ = xitdb.core_destroy(&ov_core)

			// Compaction preserves latest moment cleanly
			comp_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
			comp_db, comp_err := xitdb.database_compact(&mem_db, &comp_core)
			testing.expect_value(t, comp_err, nil)
			_verify_moment_matches_oracle(t, &comp_db, 0, moments[len(moments) - 1])
			_ = xitdb.core_destroy(&comp_core)

			// Collection diff parity between two moments
			m_a := rand.int_max(len(moments), rng)
			m_b := rand.int_max(len(moments), rng)
			_verify_diff_collection_parity(t, &mem_db, i64(m_a), i64(m_b), moments[m_a], moments[m_b])
		}
	}
}

@(test)
fuzz_sim_differential_collections_iterators_overlay_and_compaction :: proc(t: ^testing.T) {
	_run_simulation(t, SIM_FUZZ_SEED, SIM_FUZZ_OPS, xitdb.sha1_hasher(), "sha1")
}

@(test)
fuzz_sim_multi_seed_sha256_and_branching_histories :: proc(t: ^testing.T) {
	per_seed_ops := max(30, SIM_FUZZ_OPS / 3)
	for s, idx in ([?]u64{0x1111_2222_3333_4444, 0xCAFE_BABE_DEAD_BEEF, 0x0123_4567_89AB_CDEF}) {
		_run_simulation(t, s, per_seed_ops, xitdb.sha256_hasher(), fmt.tprintf("sha256_%d", idx))
	}
}
