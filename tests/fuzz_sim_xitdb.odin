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
Sim_Diag :: struct {
	seed: u64,
	step: int,
	tag:  string,
}

@(private = "file")
_sim_expect :: proc(t: ^testing.T, cond: bool, diag: Sim_Diag, msg: string, loc := #caller_location) -> bool {
	return testing.expectf(t, cond, "[seed=%#x step=%d tag=%s] %s", diag.seed, diag.step, diag.tag, msg, loc = loc)
}

@(private = "file")
_sim_expect_eq :: proc(t: ^testing.T, got, expected: $T, diag: Sim_Diag, label: string, loc := #caller_location) -> bool {
	return testing.expectf(t, got == expected, "[seed=%#x step=%d tag=%s %s] got %v, expected %v", diag.seed, diag.step, diag.tag, label, got, expected, loc = loc)
}

@(private = "file")
_sim_key :: proc(rng: runtime.Random_Generator) -> string {
	bucket := rand.int_max(10, rng)
	switch bucket {
	case 0:
		idx := rand.int_max(10, rng)
		return fmt.tprintf("k%d", idx)
	case 1, 2:
		idx := rand.int_max(40, rng)
		return fmt.tprintf("pfx_%02d", idx)
	case 3:
		idx := rand.int_max(16, rng)
		return fmt.tprintf("long_external_key_prefix_%02d", idx)
	case:
		idx := rand.int_max(600, rng)
		if idx % 5 == 0 {
			return fmt.tprintf("wide_external_key_prefix_%04d_payload", idx)
		}
		return fmt.tprintf("wide_%04d", idx)
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
		if idx < 0 {
			idx += len(m.ll)
		}
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
_gen_op :: proc(m: ^Sim_Moment, step: int, num_ops: int, op_idx: int, rng: runtime.Random_Generator) -> Sim_Op {
	grow_ops := [?]Sim_Op_Kind{
		.HM_Put,
		.CHM_Put,
		.SM_Put,
		.Arr_Append,
		.LL_Append,
		.LL_Insert,
		.HS_Put,
		.CHS_Put,
		.SS_Put,
	}
	shrink_or_update_ops := [?]Sim_Op_Kind{
		.HM_Remove,
		.CHM_Remove,
		.SM_Remove,
		.Arr_Put,
		.Arr_Slice,
		.LL_Put,
		.LL_Remove,
		.LL_Slice,
		.HS_Remove,
		.CHS_Remove,
		.SS_Remove,
	}

	kind: Sim_Op_Kind
	in_growth_phase := step < (num_ops * 2) / 3
	if in_growth_phase {
		if rand.int_max(100, rng) < 88 {
			kind = grow_ops[rand.int_max(len(grow_ops), rng)]
		} else {
			kind = shrink_or_update_ops[rand.int_max(len(shrink_or_update_ops), rng)]
		}
	} else {
		if rand.int_max(100, rng) < 75 {
			kind = shrink_or_update_ops[rand.int_max(len(shrink_or_update_ops), rng)]
		} else {
			kind = grow_ops[rand.int_max(len(grow_ops), rng)]
		}
	}

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
			idx: i64
			edge_pick := rand.int_max(10, rng)
			switch edge_pick {
			case 0, 1:
				idx = 0
			case 2, 3:
				idx = i64(len(m.ll) - 1)
			case 4:
				idx = -1
			case 5:
				idx = -i64(len(m.ll))
			case:
				idx = i64(rand.int_max(len(m.ll), rng))
			}
			return Sim_Op{
				kind  = .LL_Insert,
				val   = _sim_val(step, op_idx, rng),
				index = idx,
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
_sim_expect_ok :: proc(t: ^testing.T, err: xitdb.Error, diag: Sim_Diag, label: string, loc := #caller_location) -> bool {
	return testing.expectf(t, err == nil, "[seed=%#x step=%d tag=%s %s] unexpected error: %v", diag.seed, diag.step, diag.tag, label, err, loc = loc)
}

@(private = "file")
_verify_moment_matches_oracle :: proc(t: ^testing.T, db: ^xitdb.Database, moment_idx: i64, m: Sim_Moment, diag: Sim_Diag) {
	rc := xitdb.database_root_cursor(db).read_cursor
	hist, herr := xitdb.read_array_list_init(rc)
	_sim_expect_ok(t, herr, diag, "root hist init")

	cur_maybe, cerr := xitdb.array_list_get_cursor(hist, moment_idx)
	_sim_expect_ok(t, cerr, diag, "moment get_cursor")
	moment_cur, ok_m := cur_maybe.?
	_sim_expect(t, ok_m, diag, "moment cursor present")
	if !ok_m {
		return
	}
	moment_hm, mh_err := xitdb.read_hash_map_init(moment_cur)
	_sim_expect_ok(t, mh_err, diag, "moment hash_map init")

	// 1. Hash_Map
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "hm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			hm, hm_err := xitdb.read_hash_map_init(sub_cur)
			_sim_expect_ok(t, hm_err, diag, "hm init")
			_verify_hash_map_like(t, hm, m.hm, false, diag)
		} else {
			_sim_expect_eq(t, len(m.hm), 0, diag, "hm absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "hm get_cursor")
	}

	// 2. Counted_Hash_Map
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "chm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			chm, chm_err := xitdb.read_counted_hash_map_init(sub_cur)
			_sim_expect_ok(t, chm_err, diag, "chm init")
			cnt, cnt_err := xitdb.counted_hash_map_count(chm)
			_sim_expect_ok(t, cnt_err, diag, "chm count")
			_sim_expect_eq(t, cnt, i64(len(m.chm)), diag, "chm count eq")
			_verify_hash_map_like(t, chm.read_hash_map, m.chm, true, diag)
		} else {
			_sim_expect_eq(t, len(m.chm), 0, diag, "chm absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "chm get_cursor")
	}

	// 3. Sorted_Map (order, rank, index lookup, forward/reverse iterators, seek)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "sm"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			sm, sm_err := xitdb.read_sorted_map_init(sub_cur)
			_sim_expect_ok(t, sm_err, diag, "sm init")
			_verify_sorted_map(t, sm, m.sm, diag)
		} else {
			_sim_expect_eq(t, len(m.sm), 0, diag, "sm absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "sm get_cursor")
	}

	// 4. Array_List (count, index, forward/reverse iterator)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "arr"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			arr, arr_err := xitdb.read_array_list_init(sub_cur)
			_sim_expect_ok(t, arr_err, diag, "arr init")
			_verify_array_list(t, arr, m.arr[:], diag)
		} else {
			_sim_expect_eq(t, len(m.arr), 0, diag, "arr absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "arr get_cursor")
	}

	// 5. Linked_Array_List (count, index, forward/reverse iterator)
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "ll"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			ll, ll_err := xitdb.read_linked_array_list_init(sub_cur)
			_sim_expect_ok(t, ll_err, diag, "ll init")
			_verify_linked_list(t, ll, m.ll[:], diag)
		} else {
			_sim_expect_eq(t, len(m.ll), 0, diag, "ll absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "ll get_cursor")
	}

	// 6. Hash_Set / Counted_Hash_Set / Sorted_Set
	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "hs"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			hs, hs_err := xitdb.read_hash_set_init(sub_cur)
			_sim_expect_ok(t, hs_err, diag, "hs init")
			_verify_hash_set_like(t, hs, m.hs, diag)
		} else {
			_sim_expect_eq(t, len(m.hs), 0, diag, "hs absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "hs get_cursor")
	}

	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "chs"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			chs, chs_err := xitdb.read_counted_hash_set_init(sub_cur)
			_sim_expect_ok(t, chs_err, diag, "chs init")
			cnt, cnt_err := xitdb.counted_hash_set_count(chs)
			_sim_expect_ok(t, cnt_err, diag, "chs count")
			_sim_expect_eq(t, cnt, i64(len(m.chs)), diag, "chs count eq")
			_verify_hash_set_like(t, chs.read_hash_set, m.chs, diag)
		} else {
			_sim_expect_eq(t, len(m.chs), 0, diag, "chs absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "chs get_cursor")
	}

	if sub_maybe, serr := xitdb.hash_map_get_cursor(moment_hm, "ss"); serr == nil {
		if sub_cur, has_sub := sub_maybe.?; has_sub {
			ss, ss_err := xitdb.read_sorted_set_init(sub_cur)
			_sim_expect_ok(t, ss_err, diag, "ss init")
			_verify_sorted_set(t, ss, m.ss, diag)
		} else {
			_sim_expect_eq(t, len(m.ss), 0, diag, "ss absent len")
		}
	} else {
		_sim_expect_ok(t, serr, diag, "ss get_cursor")
	}
}

@(private = "file")
_verify_hash_map_like :: proc(t: ^testing.T, hm: xitdb.Read_Hash_Map, expected: map[string]string, _is_counted: bool, diag: Sim_Diag) {
	exhaustive_get := len(expected) <= 64 || diag.step % 10 == 0
	get_i := 0
	for k, v in expected {
		if exhaustive_get || get_i % 16 == 0 {
			vc_maybe, gerr := xitdb.hash_map_get_cursor(hm, k)
			_sim_expect_ok(t, gerr, diag, "hm get_cursor")
			vc, ok := vc_maybe.?
			_sim_expect(t, ok, diag, "hm key present")
			if ok {
				got, rerr := xitdb.cursor_read_string(vc, 0, context.temp_allocator)
				_sim_expect_ok(t, rerr, diag, "hm read_string")
				_sim_expect_eq(t, got, v, diag, "hm value eq")
			}
		}
		get_i += 1
	}

	fwd := make([dynamic]string, 0, len(expected), context.temp_allocator)
	it, ierr := xitdb.hash_map_iterator(hm)
	_sim_expect_ok(t, ierr, diag, "hm iterator")
	for {
		item_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "hm iterator next")
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "hm kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "hm kv key")
		v, verr := xitdb.cursor_read_string(kv.value_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, verr, diag, "hm kv val")
		_sim_expect_eq(t, expected[k], v, diag, "hm fwd kv eq")
		append(&fwd, k)
	}
	_sim_expect_eq(t, len(fwd), len(expected), diag, "hm fwd count")

	rev := make([dynamic]string, 0, len(expected), context.temp_allocator)
	rit, rierr := xitdb.hash_map_iterator_reverse(hm)
	_sim_expect_ok(t, rierr, diag, "hm rev iterator")
	for {
		item_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "hm iterator prev")
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "hm rev kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "hm rev kv key")
		append(&rev, k)
	}
	_sim_expect_eq(t, len(rev), len(fwd), diag, "hm rev len")
	if len(rev) == len(fwd) {
		for i in 0 ..< len(fwd) {
			_sim_expect_eq(t, rev[i], fwd[len(fwd) - 1 - i], diag, "hm rev order")
		}
	}
}

@(private = "file")
_verify_sorted_map :: proc(t: ^testing.T, sm: xitdb.Read_Sorted_Map, expected: map[string]string, diag: Sim_Diag) {
	cnt, cnt_err := xitdb.sorted_map_count(sm)
	_sim_expect_ok(t, cnt_err, diag, "sm count")
	_sim_expect_eq(t, cnt, i64(len(expected)), diag, "sm count eq")

	sorted_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	for k in expected {
		append(&sorted_keys, k)
	}
	slice.sort(sorted_keys[:])

	it, ierr := xitdb.sorted_map_iterator(sm)
	_sim_expect_ok(t, ierr, diag, "sm iterator")
	idx := 0
	for {
		item_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "sm iterator next")
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "sm kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "sm kv key")
		v, verr := xitdb.cursor_read_string(kv.value_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, verr, diag, "sm kv val")
		_sim_expect(t, idx < len(sorted_keys), diag, "sm fwd idx in bounds")
		if idx < len(sorted_keys) {
			_sim_expect_eq(t, k, sorted_keys[idx], diag, "sm fwd key eq")
			_sim_expect_eq(t, v, expected[sorted_keys[idx]], diag, "sm fwd val eq")
		}
		idx += 1
	}
	_sim_expect_eq(t, idx, len(sorted_keys), diag, "sm fwd total")

	// Verify reverse iterator order
	rit, rierr := xitdb.sorted_map_iterator_reverse(sm)
	_sim_expect_ok(t, rierr, diag, "sm rev iterator")
	ridx := len(sorted_keys) - 1
	for {
		item_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "sm iterator prev")
		item, has_item := item_maybe.?
		if !has_item {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(item, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "sm rev kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "sm rev kv key")
		_sim_expect(t, ridx >= 0, diag, "sm rev idx >= 0")
		if ridx >= 0 {
			_sim_expect_eq(t, k, sorted_keys[ridx], diag, "sm rev key eq")
		}
		ridx -= 1
	}
	_sim_expect_eq(t, ridx, -1, diag, "sm rev end")

	// Verify rank & index lookup exhaustively for <= 64 keys or every 10th step; edge-sample otherwise
	check_sm_index := proc(t: ^testing.T, sm: xitdb.Read_Sorted_Map, sorted_keys: []string, i: int, diag: Sim_Diag) {
		k := sorted_keys[i]
		rk, rkerr := xitdb.sorted_map_rank(sm, k)
		_sim_expect_ok(t, rkerr, diag, "sm rank")
		_sim_expect_eq(t, rk, i64(i), diag, "sm rank eq")

		ikv_maybe, ikerr := xitdb.sorted_map_get_index_kv_pair(sm, i64(i), context.temp_allocator)
		_sim_expect_ok(t, ikerr, diag, "sm get_index")
		ikv, has_ikv := ikv_maybe.?
		_sim_expect(t, has_ikv, diag, "sm get_index present")
		if has_ikv {
			ik, kerr := xitdb.cursor_read_string(ikv.key_cursor, 0, context.temp_allocator)
			_sim_expect_ok(t, kerr, diag, "sm get_index key")
			_sim_expect_eq(t, ik, k, diag, "sm get_index key eq")
		}
	}
	if len(sorted_keys) <= 64 || diag.step % 10 == 0 {
		for _, i in sorted_keys {
			check_sm_index(t, sm, sorted_keys[:], i, diag)
		}
	} else if len(sorted_keys) > 0 {
		samples := [?]int{0, 1, len(sorted_keys) / 4, len(sorted_keys) / 2, (len(sorted_keys) * 3) / 4, len(sorted_keys) - 1}
		for si in samples {
			if si >= 0 && si < len(sorted_keys) {
				check_sm_index(t, sm, sorted_keys[:], si, diag)
			}
		}
	}

	if len(sorted_keys) > 0 {
		read_iter_first_key :: proc(t: ^testing.T, it: ^xitdb.Cursor_Iterator, diag: Sim_Diag, label: string) -> (key: string, ok: bool) {
			m_c, err := xitdb.cursor_iterator_next(it)
			_sim_expect_ok(t, err, diag, label)
			c, has_c := m_c.?
			if !has_c {
				return "", false
			}
			kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
			_sim_expect_ok(t, kverr, diag, label)
			k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
			_sim_expect_ok(t, kerr, diag, label)
			return k, true
		}
		read_iter_last_key :: proc(t: ^testing.T, it: ^xitdb.Cursor_Iterator, diag: Sim_Diag, label: string) -> (key: string, ok: bool) {
			m_c, err := xitdb.cursor_iterator_prev(it)
			_sim_expect_ok(t, err, diag, label)
			c, has_c := m_c.?
			if !has_c {
				return "", false
			}
			kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
			_sim_expect_ok(t, kverr, diag, label)
			k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
			_sim_expect_ok(t, kerr, diag, label)
			return k, true
		}

		mid_idx := len(sorted_keys) / 2
		mid_key := sorted_keys[mid_idx]
		gap_key := fmt.tprintf("%s\x00", mid_key)

		// 1. Exact key forward + reverse (inclusive = true)
		sit, sierr := xitdb.sorted_map_iterator_from_string(sm, mid_key)
		_sim_expect_ok(t, sierr, diag, "sm seek fwd")
		fk, has_fk := read_iter_first_key(t, &sit, diag, "sm seek fwd")
		_sim_expect(t, has_fk, diag, "sm seek fwd non-empty")
		if has_fk {
			_sim_expect_eq(t, fk, mid_key, diag, "sm seek fwd key eq")
		}

		rsit, rsierr := xitdb.sorted_map_iterator_reverse_from_string(sm, mid_key, true)
		_sim_expect_ok(t, rsierr, diag, "sm seek rev inclusive")
		rk, has_rk := read_iter_last_key(t, &rsit, diag, "sm seek rev inclusive")
		_sim_expect(t, has_rk, diag, "sm seek rev inclusive non-empty")
		if has_rk {
			_sim_expect_eq(t, rk, mid_key, diag, "sm seek rev inclusive key eq")
		}

		// 2. Exact key reverse (inclusive = false)
		rsit_ex, rsex_err := xitdb.sorted_map_iterator_reverse_from_string(sm, mid_key, false)
		_sim_expect_ok(t, rsex_err, diag, "sm seek rev exclusive")
		rk_ex, has_rk_ex := read_iter_last_key(t, &rsit_ex, diag, "sm seek rev exclusive")
		if mid_idx > 0 {
			_sim_expect(t, has_rk_ex, diag, "sm seek rev exclusive has prev")
			if has_rk_ex {
				_sim_expect_eq(t, rk_ex, sorted_keys[mid_idx - 1], diag, "sm seek rev exclusive key eq")
			}
		} else {
			_sim_expect(t, !has_rk_ex, diag, "sm seek rev exclusive empty at index 0")
		}

		// 3. Non-existent gap key (`mid_key + "\x00"`) forward & reverse
		gap_fwd, gf_err := xitdb.sorted_map_iterator_from_string(sm, gap_key)
		_sim_expect_ok(t, gf_err, diag, "sm seek gap fwd")
		gfk, has_gfk := read_iter_first_key(t, &gap_fwd, diag, "sm seek gap fwd")
		if mid_idx + 1 < len(sorted_keys) {
			_sim_expect(t, has_gfk, diag, "sm seek gap fwd has next")
			if has_gfk {
				_sim_expect_eq(t, gfk, sorted_keys[mid_idx + 1], diag, "sm seek gap fwd key eq")
			}
		} else {
			_sim_expect(t, !has_gfk, diag, "sm seek gap fwd empty past end")
		}

		gap_rev, gr_err := xitdb.sorted_map_iterator_reverse_from_string(sm, gap_key, false)
		_sim_expect_ok(t, gr_err, diag, "sm seek gap rev")
		grk, has_grk := read_iter_last_key(t, &gap_rev, diag, "sm seek gap rev")
		_sim_expect(t, has_grk, diag, "sm seek gap rev non-empty")
		if has_grk {
			_sim_expect_eq(t, grk, mid_key, diag, "sm seek gap rev key eq")
		}

		// 4. Out-of-bounds below min & above max
		lo_fwd, lf_err := xitdb.sorted_map_iterator_from_string(sm, "\x00")
		_sim_expect_ok(t, lf_err, diag, "sm seek below min fwd")
		lfk, has_lfk := read_iter_first_key(t, &lo_fwd, diag, "sm seek below min fwd")
		_sim_expect(t, has_lfk, diag, "sm seek below min fwd non-empty")
		if has_lfk {
			_sim_expect_eq(t, lfk, sorted_keys[0], diag, "sm seek below min fwd eq first")
		}

		lo_rev, lr_err := xitdb.sorted_map_iterator_reverse_from_string(sm, "\x00", true)
		_sim_expect_ok(t, lr_err, diag, "sm seek below min rev")
		_, has_lrk := read_iter_last_key(t, &lo_rev, diag, "sm seek below min rev")
		_sim_expect(t, !has_lrk, diag, "sm seek below min rev empty")

		hi_fwd, hf_err := xitdb.sorted_map_iterator_from_string(sm, "\xff\xff\xff\xff")
		_sim_expect_ok(t, hf_err, diag, "sm seek above max fwd")
		_, has_hfk := read_iter_first_key(t, &hi_fwd, diag, "sm seek above max fwd")
		_sim_expect(t, !has_hfk, diag, "sm seek above max fwd empty")

		hi_rev, hr_err := xitdb.sorted_map_iterator_reverse_from_string(sm, "\xff\xff\xff\xff", false)
		_sim_expect_ok(t, hr_err, diag, "sm seek above max rev")
		hrk, has_hrk := read_iter_last_key(t, &hi_rev, diag, "sm seek above max rev")
		_sim_expect(t, has_hrk, diag, "sm seek above max rev non-empty")
		if has_hrk {
			_sim_expect_eq(t, hrk, sorted_keys[len(sorted_keys) - 1], diag, "sm seek above max rev eq last")
		}
	}
}

@(private = "file")
_verify_array_list :: proc(t: ^testing.T, arr: xitdb.Read_Array_List, expected: []string, diag: Sim_Diag) {
	cnt, cnt_err := xitdb.array_list_count(arr)
	_sim_expect_ok(t, cnt_err, diag, "arr count")
	_sim_expect_eq(t, cnt, i64(len(expected)), diag, "arr count eq")

	if len(expected) <= 64 || diag.step % 10 == 0 {
		for exp_v, idx in expected {
			c_maybe, gerr := xitdb.array_list_get_cursor(arr, i64(idx))
			_sim_expect_ok(t, gerr, diag, "arr get_cursor")
			c, ok := c_maybe.?
			_sim_expect(t, ok, diag, "arr get_cursor present")
			if ok {
				got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
				_sim_expect_ok(t, rerr, diag, "arr read_string")
				_sim_expect_eq(t, got, exp_v, diag, "arr elem eq")
			}
		}
	}

	it, ierr := xitdb.array_list_iterator(arr)
	_sim_expect_ok(t, ierr, diag, "arr iterator")
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "arr iterator next")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "arr fwd read_string")
		_sim_expect(t, idx < len(expected), diag, "arr fwd idx in bounds")
		if idx < len(expected) {
			_sim_expect_eq(t, got, expected[idx], diag, "arr fwd elem eq")
		}
		idx += 1
	}
	_sim_expect_eq(t, idx, len(expected), diag, "arr fwd total")

	rit, rierr := xitdb.array_list_iterator_reverse(arr)
	_sim_expect_ok(t, rierr, diag, "arr rev iterator")
	ridx := len(expected) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "arr iterator prev")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "arr rev read_string")
		_sim_expect(t, ridx >= 0, diag, "arr rev idx >= 0")
		if ridx >= 0 {
			_sim_expect_eq(t, got, expected[ridx], diag, "arr rev elem eq")
		}
		ridx -= 1
	}
	_sim_expect_eq(t, ridx, -1, diag, "arr rev end")
}

@(private = "file")
_verify_linked_list :: proc(t: ^testing.T, ll: xitdb.Read_Linked_Array_List, expected: []string, diag: Sim_Diag) {
	cnt, cnt_err := xitdb.linked_array_list_count(ll)
	_sim_expect_ok(t, cnt_err, diag, "ll count")
	_sim_expect_eq(t, cnt, i64(len(expected)), diag, "ll count eq")

	if len(expected) <= 64 || diag.step % 10 == 0 {
		for exp_v, idx in expected {
			c_maybe, gerr := xitdb.linked_array_list_get_cursor(ll, i64(idx))
			_sim_expect_ok(t, gerr, diag, "ll get_cursor")
			c, ok := c_maybe.?
			_sim_expect(t, ok, diag, "ll get_cursor present")
			if ok {
				got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
				_sim_expect_ok(t, rerr, diag, "ll read_string")
				_sim_expect_eq(t, got, exp_v, diag, "ll elem eq")
			}
		}
	}

	it, ierr := xitdb.linked_array_list_iterator(ll)
	_sim_expect_ok(t, ierr, diag, "ll iterator")
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "ll iterator next")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "ll fwd read_string")
		_sim_expect(t, idx < len(expected), diag, "ll fwd idx in bounds")
		if idx < len(expected) {
			_sim_expect_eq(t, got, expected[idx], diag, "ll fwd elem eq")
		}
		idx += 1
	}
	_sim_expect_eq(t, idx, len(expected), diag, "ll fwd total")

	rit, rierr := xitdb.linked_array_list_iterator_reverse(ll)
	_sim_expect_ok(t, rierr, diag, "ll rev iterator")
	ridx := len(expected) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "ll iterator prev")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		got, rerr := xitdb.cursor_read_string(c, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "ll rev read_string")
		_sim_expect(t, ridx >= 0, diag, "ll rev idx >= 0")
		if ridx >= 0 {
			_sim_expect_eq(t, got, expected[ridx], diag, "ll rev elem eq")
		}
		ridx -= 1
	}
	_sim_expect_eq(t, ridx, -1, diag, "ll rev end")
}

@(private = "file")
_verify_hash_set_like :: proc(t: ^testing.T, hs: xitdb.Read_Hash_Set, expected: map[string]struct{}, diag: Sim_Diag) {
	exhaustive_get := len(expected) <= 64 || diag.step % 10 == 0
	get_i := 0
	for k in expected {
		if exhaustive_get || get_i % 16 == 0 {
			c_maybe, gerr := xitdb.hash_set_get_cursor(hs, k)
			_sim_expect_ok(t, gerr, diag, "hs get_cursor")
			_, ok := c_maybe.?
			_sim_expect(t, ok, diag, "hs member present")
		}
		get_i += 1
	}

	fwd_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	it, ierr := xitdb.hash_set_iterator(hs)
	_sim_expect_ok(t, ierr, diag, "hs iterator")
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "hs iterator next")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "hs kv_pair")
		k, rerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "hs kv key")
		_sim_expect(t, k in expected, diag, "hs fwd member expected")
		append(&fwd_keys, k)
	}
	_sim_expect_eq(t, len(fwd_keys), len(expected), diag, "hs fwd count")

	rev_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	rit, rierr := xitdb.hash_set_iterator_reverse(hs)
	_sim_expect_ok(t, rierr, diag, "hs rev iterator")
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "hs iterator prev")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "hs rev kv_pair")
		k, rerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, rerr, diag, "hs rev kv key")
		append(&rev_keys, k)
	}
	_sim_expect_eq(t, len(rev_keys), len(fwd_keys), diag, "hs rev len")
	if len(rev_keys) == len(fwd_keys) {
		for i in 0 ..< len(fwd_keys) {
			_sim_expect_eq(t, rev_keys[i], fwd_keys[len(fwd_keys) - 1 - i], diag, "hs rev order")
		}
	}
}

@(private = "file")
_verify_sorted_set :: proc(t: ^testing.T, ss: xitdb.Read_Sorted_Set, expected: map[string]struct{}, diag: Sim_Diag) {
	cnt, cnt_err := xitdb.sorted_set_count(ss)
	_sim_expect_ok(t, cnt_err, diag, "ss count")
	_sim_expect_eq(t, cnt, i64(len(expected)), diag, "ss count eq")

	sorted_keys := make([dynamic]string, 0, len(expected), context.temp_allocator)
	for k in expected {
		append(&sorted_keys, k)
	}
	slice.sort(sorted_keys[:])

	it, ierr := xitdb.sorted_set_iterator(ss)
	_sim_expect_ok(t, ierr, diag, "ss iterator")
	idx := 0
	for {
		c_maybe, nerr := xitdb.cursor_iterator_next(&it)
		_sim_expect_ok(t, nerr, diag, "ss iterator next")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "ss kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "ss kv key")
		_sim_expect(t, idx < len(sorted_keys), diag, "ss fwd idx in bounds")
		if idx < len(sorted_keys) {
			_sim_expect_eq(t, k, sorted_keys[idx], diag, "ss fwd key eq")
		}
		idx += 1
	}
	_sim_expect_eq(t, idx, len(sorted_keys), diag, "ss fwd total")

	rit, rierr := xitdb.sorted_set_iterator_reverse(ss)
	_sim_expect_ok(t, rierr, diag, "ss rev iterator")
	ridx := len(sorted_keys) - 1
	for {
		c_maybe, perr := xitdb.cursor_iterator_prev(&rit)
		_sim_expect_ok(t, perr, diag, "ss iterator prev")
		c, has_c := c_maybe.?
		if !has_c {
			break
		}
		kv, kverr := xitdb.cursor_read_kv_pair(c, context.temp_allocator)
		_sim_expect_ok(t, kverr, diag, "ss rev kv_pair")
		k, kerr := xitdb.cursor_read_string(kv.key_cursor, 0, context.temp_allocator)
		_sim_expect_ok(t, kerr, diag, "ss rev kv key")
		_sim_expect(t, ridx >= 0, diag, "ss rev idx >= 0")
		if ridx >= 0 {
			_sim_expect_eq(t, k, sorted_keys[ridx], diag, "ss rev key eq")
		}
		ridx -= 1
	}
	_sim_expect_eq(t, ridx, -1, diag, "ss rev end")
}

@(private = "file")
_verify_diff_collection_parity :: proc(
	t: ^testing.T,
	db: ^xitdb.Database,
	m_a: i64,
	m_b: i64,
	oracle_a: Sim_Moment,
	oracle_b: Sim_Moment,
	diag: Sim_Diag,
) {
	rc := xitdb.database_root_cursor(db).read_cursor
	hist, herr := xitdb.read_array_list_init(rc)
	_sim_expect_ok(t, herr, diag, "diff hist init")

	ca_maybe, ca_err := xitdb.array_list_get_cursor(hist, m_a)
	_sim_expect_ok(t, ca_err, diag, "diff get moment a")
	cb_maybe, cb_err := xitdb.array_list_get_cursor(hist, m_b)
	_sim_expect_ok(t, cb_err, diag, "diff get moment b")
	ca, oka := ca_maybe.?
	cb, okb := cb_maybe.?
	if !oka || !okb {
		_sim_expect(t, false, diag, "diff moment cursors present")
		return
	}

	hma, hma_err := xitdb.read_hash_map_init(ca)
	_sim_expect_ok(t, hma_err, diag, "diff hma init")
	hmb, hmb_err := xitdb.read_hash_map_init(cb)
	_sim_expect_ok(t, hmb_err, diag, "diff hmb init")
	empty_cur := xitdb.Read_Cursor{db = db}

	// 1. Structural byte-key `diff_collection` parity across all map & set buckets
	for bucket in ([?]string{"hm", "chm", "sm"}) {
		suba_maybe, sa_err := xitdb.hash_map_get_cursor(hma, bucket)
		_sim_expect_ok(t, sa_err, diag, "diff suba get_cursor")
		subb_maybe, sb_err := xitdb.hash_map_get_cursor(hmb, bucket)
		_sim_expect_ok(t, sb_err, diag, "diff subb get_cursor")

		suba, has_a := suba_maybe.?
		subb, has_b := subb_maybe.?
		if !has_a && !has_b {
			continue
		}

		changes, derr := xitdb.diff_collection(suba if has_a else empty_cur, subb if has_b else empty_cur, context.temp_allocator)
		_sim_expect_ok(t, derr, diag, "diff_collection map")

		map_a := oracle_a.hm if bucket == "hm" else (oracle_a.chm if bucket == "chm" else oracle_a.sm)
		map_b := oracle_b.hm if bucket == "hm" else (oracle_b.chm if bucket == "chm" else oracle_b.sm)

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
		_sim_expect_eq(t, len(changes), expected_count, diag, "diff_collection map count eq")

		for chg in changes {
			k := string(chg.key)
			va, in_a := map_a[k]
			vb, in_b := map_b[k]
			switch chg.op {
			case .Added:
				_sim_expect(t, !in_a && in_b, diag, "diff map Added")
			case .Removed:
				_sim_expect(t, in_a && !in_b, diag, "diff map Removed")
			case .Changed:
				_sim_expect(t, in_a && in_b && va != vb, diag, "diff map Changed")
			}
		}
	}

	for bucket in ([?]string{"hs", "chs", "ss"}) {
		suba_maybe, sa_err := xitdb.hash_map_get_cursor(hma, bucket)
		_sim_expect_ok(t, sa_err, diag, "diff set suba get_cursor")
		subb_maybe, sb_err := xitdb.hash_map_get_cursor(hmb, bucket)
		_sim_expect_ok(t, sb_err, diag, "diff set subb get_cursor")

		suba, has_a := suba_maybe.?
		subb, has_b := subb_maybe.?
		if !has_a && !has_b {
			continue
		}

		changes, derr := xitdb.diff_collection(suba if has_a else empty_cur, subb if has_b else empty_cur, context.temp_allocator)
		_sim_expect_ok(t, derr, diag, "diff_collection set")

		set_a := oracle_a.hs if bucket == "hs" else (oracle_a.chs if bucket == "chs" else oracle_a.ss)
		set_b := oracle_b.hs if bucket == "hs" else (oracle_b.chs if bucket == "chs" else oracle_b.ss)

		expected_count := 0
		for k in set_a {
			if !(k in set_b) {
				expected_count += 1
			}
		}
		for k in set_b {
			if !(k in set_a) {
				expected_count += 1
			}
		}
		_sim_expect_eq(t, len(changes), expected_count, diag, "diff_collection set count eq")

		for chg in changes {
			k := string(chg.key)
			in_a := k in set_a
			in_b := k in set_b
			switch chg.op {
			case .Added:
				_sim_expect(t, !in_a && in_b, diag, "diff set Added")
			case .Removed:
				_sim_expect(t, in_a && !in_b, diag, "diff set Removed")
			case .Changed:
				_sim_expect(t, false, diag, "diff set unexpected Changed")
			}
		}
	}

	// 2. DSL `diff_moments` parity (self-diff == 0 changes, well-formed bucket paths across snapshots)
	self_diffs, sd_err := xitdb.diff_moments(db, m_a, m_a, false, context.temp_allocator)
	_sim_expect_ok(t, sd_err, diag, "diff_moments self")
	_sim_expect_eq(t, len(self_diffs), 0, diag, "diff_moments self count eq 0")

	mdiffs, md_err := xitdb.diff_moments(db, m_a, m_b, false, context.temp_allocator)
	_sim_expect_ok(t, md_err, diag, "diff_moments a vs b")
	for chg in mdiffs {
		valid_bucket := strings.has_prefix(chg.path_str, ".hm") ||
			strings.has_prefix(chg.path_str, ".chm") ||
			strings.has_prefix(chg.path_str, ".sm") ||
			strings.has_prefix(chg.path_str, ".arr") ||
			strings.has_prefix(chg.path_str, ".ll") ||
			strings.has_prefix(chg.path_str, ".hs") ||
			strings.has_prefix(chg.path_str, ".chs") ||
			strings.has_prefix(chg.path_str, ".ss")
		_sim_expect(t, valid_bucket, diag, "diff_moments valid bucket prefix")
	}
}

@(private = "file")
_verify_oob_ll_insert :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
	t := (^testing.T)(user_data)
	moment := xitdb.write_hash_map_init(cursor^) or_return
	if ll_c_maybe, gerr := xitdb.hash_map_get_cursor(moment.read_hash_map, "ll"); gerr == nil {
		if ll_c, ok := ll_c_maybe.?; ok {
			cnt := xitdb.linked_array_list_count(xitdb.read_linked_array_list_init(ll_c) or_return) or_return
			wc := xitdb.hash_map_put_cursor(&moment, "ll") or_return
			ll := xitdb.write_linked_array_list_init(wc) or_return
			oob_err := xitdb.linked_array_list_insert(&ll, cnt, "oob_tail")
			testing.expect_value(t, oob_err, xitdb.Error(.Key_Not_Found))
		}
	}
	empty_c := xitdb.hash_map_put_cursor(&moment, "empty_ll_probe") or_return
	empty_ll := xitdb.write_linked_array_list_init(empty_c) or_return
	empty_err := xitdb.linked_array_list_insert(&empty_ll, 0, "oob_empty")
	testing.expect_value(t, empty_err, xitdb.Error(.Key_Not_Found))
	return .Key_Not_Found // Always rollback this probe transaction
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
	// Allocate on context.allocator (not temp_allocator) so per-step free_all doesn't clobber bf_path!
	bf_path := fmt.aprintf("%s/xitdb_sim_%s_%d.xit", tmp_dir, tag, seed)
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
		rm_err := os.remove(bf_path)
		testing.expect_value(t, rm_err, nil)
		delete(bf_path)
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

	trunk_idx := -1
	peak_sm_keys := 0

	for step in 0 ..< num_ops {
		defer free_all(context.temp_allocator)
		diag := Sim_Diag{seed = seed, step = step, tag = tag}

		base_idx := -1
		base_slot := xitdb.Slot{}
		next_model: Sim_Moment
		is_trunk := true
		if len(moments) == 0 {
			next_model = _empty_moment()
		} else {
			// Advance the main trunk most steps so collections grow past 2Tier/3Tier B+Tree
			// thresholds (>256 keys), while periodically branching from arbitrary historical moments.
			if rand.int_max(7, rng) == 0 {
				is_trunk = false
				base_idx = rand.int_max(len(moments), rng)
			} else {
				base_idx = trunk_idx if trunk_idx >= 0 else len(moments) - 1
			}
			next_model = _clone_moment(moments[base_idx])

			m_rc := xitdb.database_root_cursor(&mem_db).read_cursor
			m_hist, mh_err := xitdb.read_array_list_init(m_rc)
			_sim_expect_ok(t, mh_err, diag, "trunk hist init")
			slot_maybe, s_err := xitdb.array_list_get_slot(m_hist, i64(base_idx))
			_sim_expect_ok(t, s_err, diag, "trunk get_slot")
			slot_ok := false
			base_slot, slot_ok = slot_maybe.?
			_sim_expect(t, slot_ok, diag, "trunk slot present")
		}

		batch_len := 1 + rand.int_max(8, rng)
		ops_buf: [8]Sim_Op
		for j in 0 ..< batch_len {
			op := _gen_op(&next_model, step, num_ops, j, rng)
			ops_buf[j] = op
			_apply_model_op(&next_model, op)
		}
		if len(next_model.sm) > peak_sm_keys {
			peak_sm_keys = len(next_model.sm)
		}
		batch := Sim_Batch{ops = ops_buf[:batch_len]}

		m_root := xitdb.database_root_cursor(&mem_db)
		m_hist_w, mhw_err := xitdb.write_array_list_init(m_root)
		_sim_expect_ok(t, mhw_err, diag, "mem hist write init")
		tx_m_err := xitdb.array_list_append_context(&m_hist_w, base_slot, _apply_sim_batch_cb, &batch)
		_sim_expect_ok(t, tx_m_err, diag, "mem append_context")

		bf_base_slot := xitdb.Slot{}
		if base_idx >= 0 {
			b_rc := xitdb.database_root_cursor(&bf_db).read_cursor
			b_hist, bh_err := xitdb.read_array_list_init(b_rc)
			_sim_expect_ok(t, bh_err, diag, "bf hist init")
			bs_maybe, bs_err := xitdb.array_list_get_slot(b_hist, i64(base_idx))
			_sim_expect_ok(t, bs_err, diag, "bf get_slot")
			bs_ok := false
			bf_base_slot, bs_ok = bs_maybe.?
			_sim_expect(t, bs_ok, diag, "bf slot present")
		}
		b_root := xitdb.database_root_cursor(&bf_db)
		b_hist_w, bhw_err := xitdb.write_array_list_init(b_root)
		_sim_expect_ok(t, bhw_err, diag, "bf hist write init")
		tx_b_err := xitdb.array_list_append_context(&b_hist_w, bf_base_slot, _apply_sim_batch_cb, &batch)
		_sim_expect_ok(t, tx_b_err, diag, "bf append_context")

		append(&moments, next_model)
		new_idx := i64(len(moments) - 1)
		if is_trunk || trunk_idx < 0 {
			trunk_idx = len(moments) - 1
		}

		_verify_moment_matches_oracle(t, &mem_db, new_idx, moments[len(moments) - 1], diag)
		if step < 32 || step % 10 == 0 || step == num_ops - 1 {
			_verify_moment_matches_oracle(t, &bf_db, new_idx, moments[len(moments) - 1], diag)
		}

		// Check historical moment retention on random prior snapshot
		if len(moments) > 2 && (step < 64 || step % 5 == 0) {
			hist_check := rand.int_max(len(moments) - 1, rng)
			_verify_moment_matches_oracle(t, &mem_db, i64(hist_check), moments[hist_check], diag)
		}

		// Periodic overlay, OOB insert rollback, compaction + continued writes, and collection diff verification
		if step > 0 && step % 25 == 0 {
			committed_sz, csz_err := xitdb.database_committed_size(&mem_db)
			_sim_expect_ok(t, csz_err, diag, "committed_size")

			ov_core, ov_err := xitdb.core_overlay_init(&mem_core, committed_sz, context.allocator)
			_sim_expect_ok(t, ov_err, diag, "overlay init")
			ov_db, ov_derr := xitdb.database_init(&ov_core, hasher)
			_sim_expect_ok(t, ov_derr, diag, "overlay db init")

			ov_model := _clone_moment(moments[len(moments) - 1])
			ov_op := Sim_Op{kind = .SM_Put, key = "overlay_only_key", val = "overlay_only_val"}
			_apply_model_op(&ov_model, ov_op)
			ov_ops := [1]Sim_Op{ov_op}
			ov_batch := Sim_Batch{ops = ov_ops[:]}

			ov_root := xitdb.database_root_cursor(&ov_db)
			ov_hist_w, ohw_err := xitdb.write_array_list_init(ov_root)
			_sim_expect_ok(t, ohw_err, diag, "overlay hist write")
			ov_latest_maybe, ol_err := xitdb.array_list_get_slot(ov_hist_w.read_array_list, -1)
			_sim_expect_ok(t, ol_err, diag, "overlay latest slot")
			ov_base := ov_latest_maybe.?

			// Verify OOB LL_Insert (tail & empty list) returns Key_Not_Found without corrupting overlay DB
			oob_probe_err := xitdb.array_list_append_context(&ov_hist_w, ov_base, _verify_oob_ll_insert, t)
			_sim_expect_eq(t, oob_probe_err, xitdb.Error(.Key_Not_Found), diag, "oob ll insert probe")

			ov_tx_err := xitdb.array_list_append_context(&ov_hist_w, ov_base, _apply_sim_batch_cb, &ov_batch)
			_sim_expect_ok(t, ov_tx_err, diag, "overlay append_context")

			_verify_moment_matches_oracle(t, &ov_db, -1, ov_model, diag)
			_verify_moment_matches_oracle(t, &mem_db, -1, moments[len(moments) - 1], diag)
			_destroy_moment(&ov_model)
			_ = xitdb.core_destroy(&ov_core)

			// Compaction preserves latest moment cleanly AND supports continued writes onto the compacted DB
			comp_core := xitdb.core_memory_init(context.allocator, reserve_size = 0)
			comp_db, comp_err := xitdb.database_compact(&mem_db, &comp_core)
			_sim_expect_ok(t, comp_err, diag, "database_compact")
			_verify_moment_matches_oracle(t, &comp_db, 0, moments[len(moments) - 1], diag)

			comp_model := _clone_moment(moments[len(moments) - 1])
			comp_ops: [3]Sim_Op
			for cj in 0 ..< len(comp_ops) {
				cop := _gen_op(&comp_model, step, num_ops, 100 + cj, rng)
				comp_ops[cj] = cop
				_apply_model_op(&comp_model, cop)
			}
			comp_batch := Sim_Batch{ops = comp_ops[:]}
			comp_root := xitdb.database_root_cursor(&comp_db)
			comp_hist_w, chw_err := xitdb.write_array_list_init(comp_root)
			_sim_expect_ok(t, chw_err, diag, "compacted hist write")
			comp_m0_maybe, cm0_err := xitdb.array_list_get_slot(comp_hist_w.read_array_list, 0)
			_sim_expect_ok(t, cm0_err, diag, "compacted moment 0 slot")
			comp_tx_err := xitdb.array_list_append_context(&comp_hist_w, comp_m0_maybe.?, _apply_sim_batch_cb, &comp_batch)
			_sim_expect_ok(t, comp_tx_err, diag, "compacted continued write")

			_verify_moment_matches_oracle(t, &comp_db, 0, moments[len(moments) - 1], diag)
			_verify_moment_matches_oracle(t, &comp_db, 1, comp_model, diag)
			_destroy_moment(&comp_model)
			_ = xitdb.core_destroy(&comp_core)

			// Collection diff parity between two moments
			m_a := rand.int_max(len(moments), rng)
			m_b := rand.int_max(len(moments), rng)
			_verify_diff_collection_parity(t, &mem_db, i64(m_a), i64(m_b), moments[m_a], moments[m_b], diag)
		}
	}

	if num_ops >= 2000 && tag == "sha1" {
		testing.expectf(t, peak_sm_keys > 256, "expected Sorted_Map peak keys > 256 at num_ops=%d to exercise height >= 3 splits/merges, got %d", num_ops, peak_sm_keys)
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

@(test)
fuzz_sim_random_runner_seed :: proc(t: ^testing.T) {
	_run_simulation(t, t.seed, max(25, SIM_FUZZ_OPS / 6), xitdb.sha1_hasher(), "runner_seed")
}
