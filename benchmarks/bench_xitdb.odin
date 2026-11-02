package xitdb_benchmarks

import "core:fmt"
import "core:os"
import "core:time"
import xitdb "../xitdb"

Bench_Result :: struct {
	name:       string,
	ops:        int,
	elapsed:    time.Duration,
	bytes_used: i64,
}

print_header :: proc() {
	fmt.println("========================================================================================================")
	fmt.printf("%-48s | %8s | %10s | %12s | %12s\n", "Benchmark", "Ops", "Total (ms)", "ns/op", "ops/sec")
	fmt.println("--------------------------------------------------------------------------------------------------------")
}

print_result :: proc(r: Bench_Result) {
	total_ns := f64(time.duration_nanoseconds(r.elapsed))
	total_ms := total_ns / 1e6
	ns_per_op := total_ns / f64(max(r.ops, 1))
	ops_per_sec := (f64(r.ops) * 1e9) / max(total_ns, 1.0)
	if r.bytes_used > 0 {
		kb := f64(r.bytes_used) / 1024.0
		fmt.printf(
			"%-48s | % 8d | % 10.2f | % 12.0f | % 12.0f  (%.1f KB)\n",
			r.name,
			r.ops,
			total_ms,
			ns_per_op,
			ops_per_sec,
			kb,
		)
	} else {
		fmt.printf(
			"%-48s | % 8d | % 10.2f | % 12.0f | % 12.0f\n",
			r.name,
			r.ops,
			total_ms,
			ns_per_op,
			ops_per_sec,
		)
	}
}

// ----------------------------------------------------------------------------
// 1. HAMT (`Hash_Map`) Bulk Insert, Point Lookup & Branched Moment Commits
// ----------------------------------------------------------------------------

bench_hamt :: proc(n: int) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	rc := xitdb.database_root_cursor(&db)
	history, _ := xitdb.write_array_list_init(rc)

	keys := make([]string, n, context.temp_allocator)
	for i in 0 ..< n {
		keys[i] = fmt.tprintf("user-key-%06d", i)
	}

	// 1a. Bulk insert N keys in a single moment transaction
	Insert_Ctx :: struct {
		keys: []string,
	}
	ictx := Insert_Ctx{keys = keys}

	insert_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Insert_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.hash_map_put(&m, k, u64(idx)) or_return
		}
		return nil
	}

	t0 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, insert_cb, &ictx)
	elapsed_insert := time.since(t0)
	size_after_insert, _ := xitdb.database_committed_size(&db)

	print_result(Bench_Result{
		name       = "HAMT Hash_Map bulk put (1 tx)",
		ops        = n,
		elapsed    = elapsed_insert,
		bytes_used = size_after_insert,
	})

	// 1b. Point lookup N keys from Moment 0 (with SHA-1 key hashing vs pre-computed digest)
	m0_cur, _ := xitdb.array_list_get_cursor(history, 0)
	m0, _ := xitdb.read_hash_map_init(m0_cur.?)

	t1 := time.now()
	for k, idx in keys {
		vc, _ := xitdb.hash_map_get_cursor(m0, k)
		v, _ := xitdb.cursor_read_uint(vc.?)
		assert(v == u64(idx))
	}
	elapsed_get := time.since(t1)

	print_result(Bench_Result{
		name    = "HAMT Hash_Map point lookup (with SHA-1)",
		ops     = n,
		elapsed = elapsed_get,
	})

	digests := make([][]u8, n, context.temp_allocator)
	for k, idx in keys {
		digests[idx] = xitdb.database_digest_string(&db, k, context.temp_allocator)
	}

	t1_pre := time.now()
	for d, idx in digests {
		vc, _ := xitdb.hash_map_get_cursor_by_hash(m0, d)
		v, _ := xitdb.cursor_read_uint(vc.?)
		assert(v == u64(idx))
	}
	elapsed_get_pre := time.since(t1_pre)

	print_result(Bench_Result{
		name    = "HAMT Hash_Map lookup (pre-hashed digest)",
		ops     = n,
		elapsed = elapsed_get_pre,
	})

	// 1c. Incremental branched moments (CoW structural sharing on 500 commits)
	branch_commits := 500
	Branch_Ctx :: struct {
		key: string,
		val: u64,
	}
	bctx: Branch_Ctx

	branch_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		b := (^Branch_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		return xitdb.hash_map_put(&m, b.key, b.val)
	}

	t2 := time.now()
	for i in 0 ..< branch_commits {
		bctx = Branch_Ctx{
			key = keys[i % len(keys)],
			val = u64(n + i),
		}
		prev_slot, _ := xitdb.array_list_get_slot(history, -1)
		_ = xitdb.array_list_append_context(&history, prev_slot.?, branch_cb, &bctx)
	}
	elapsed_branch := time.since(t2)
	size_after_branch, _ := xitdb.database_committed_size(&db)

	print_result(Bench_Result{
		name       = "HAMT CoW branched moment commits",
		ops        = branch_commits,
		elapsed    = elapsed_branch,
		bytes_used = size_after_branch - size_after_insert,
	})

	// 1d. HAMT key removal & branch shortening (remove half of the keys in 1 tx)
	remove_count := n / 2
	Remove_Hamt_Ctx :: struct {
		keys: []string,
	}
	rhctx := Remove_Hamt_Ctx{keys = keys[:remove_count]}

	remove_hamt_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Remove_Hamt_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for k in c.keys {
			_, err := xitdb.hash_map_remove(&m, k)
			if err != nil do return err
		}
		return nil
	}

	m0_slot, _ := xitdb.array_list_get_slot(history, 0)
	t3 := time.now()
	_ = xitdb.array_list_append_context(&history, m0_slot.?, remove_hamt_cb, &rhctx)
	elapsed_rem := time.since(t3)

	print_result(Bench_Result{
		name    = "HAMT Hash_Map remove & branch shortening",
		ops     = remove_count,
		elapsed = elapsed_rem,
	})

	// 1e. HAMT unordered full-tree iterator scan
	t4 := time.now()
	hit, _ := xitdb.hash_map_iterator(m0)
	hcnt := 0
	for {
		c_maybe, _ := xitdb.cursor_iterator_next(&hit)
		if c_maybe == nil do break
		hcnt += 1
	}
	assert(hcnt == n)
	elapsed_hiter := time.since(t4)

	print_result(Bench_Result{
		name    = "HAMT Hash_Map unordered iterator scan",
		ops     = n,
		elapsed = elapsed_hiter,
	})

	// 1f. HAMT in-place key overwrite (same tx, updating existing value slots)
	Overwrite_Hamt_Ctx :: struct {
		keys: []string,
	}
	ohctx := Overwrite_Hamt_Ctx{keys = keys}

	overwrite_hamt_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Overwrite_Hamt_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.hash_map_put(&m, k, u64(idx + 1_000_000)) or_return
		}
		return nil
	}

	t5 := time.now()
	_ = xitdb.array_list_append_context(&history, m0_slot.?, overwrite_hamt_cb, &ohctx)
	elapsed_overwrite := time.since(t5)

	print_result(Bench_Result{
		name    = "HAMT Hash_Map in-place overwrite (1 tx)",
		ops     = n,
		elapsed = elapsed_overwrite,
	})

	// 1g. Counted_Hash_Map bulk put + O(1) count tracking vs remove
	counted_put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Insert_Ctx)(user_data)
		cm := xitdb.write_counted_hash_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.hash_map_put(&cm, k, u64(idx)) or_return
		}
		return nil
	}

	t6 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, counted_put_cb, &ictx)
	elapsed_cput := time.since(t6)

	cm_slot, _ := xitdb.array_list_get_slot(history, -1)
	cm_cur, _ := xitdb.array_list_get_cursor(history, -1)
	rcm, _ := xitdb.read_counted_hash_map_init(cm_cur.?)
	cm_cnt, _ := xitdb.counted_hash_map_count(rcm)
	assert(cm_cnt == i64(n))

	print_result(Bench_Result{
		name    = "HAMT Counted_Hash_Map bulk put (1 tx)",
		ops     = n,
		elapsed = elapsed_cput,
	})

	counted_rem_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Remove_Hamt_Ctx)(user_data)
		cm := xitdb.write_counted_hash_map_init(cursor^) or_return
		for k in c.keys {
			_, err := xitdb.hash_map_remove(&cm, k)
			if err != nil do return err
		}
		return nil
	}

	t7 := time.now()
	_ = xitdb.array_list_append_context(&history, cm_slot.?, counted_rem_cb, &rhctx)
	elapsed_crem := time.since(t7)

	print_result(Bench_Result{
		name    = "HAMT Counted_Hash_Map remove",
		ops     = remove_count,
		elapsed = elapsed_crem,
	})

	// 1h. HAMT deep suffix-collision splitting (10 shared trailing nibbles = 5 bytes) & collapse
	coll_n := 500
	coll_hashes := make([][]u8, coll_n, context.temp_allocator)
	for i in 0 ..< coll_n {
		h := make([]u8, 20, context.temp_allocator)
		// Share lower 5 bytes (10 trailing nibbles) so every pair collides to depth >= 10
		h[19] = 0xAA
		h[18] = 0xBB
		h[17] = 0xCC
		h[16] = 0xDD
		h[15] = 0xEE
		// Vary bytes 14..0
		h[14] = u8(i & 0xFF)
		h[13] = u8((i >> 8) & 0xFF)
		h[12] = u8((i * 73) & 0xFF)
		coll_hashes[i] = h
	}

	Coll_Ctx :: struct {
		hashes: [][]u8,
	}
	col_ctx := Coll_Ctx{hashes = coll_hashes}

	coll_put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Coll_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for h, idx in c.hashes {
			xitdb.hash_map_put_key_and_value(&m, h, u64(idx), u64(idx)) or_return
		}
		return nil
	}

	t8 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, coll_put_cb, &col_ctx)
	elapsed_coll_put := time.since(t8)

	print_result(Bench_Result{
		name    = "HAMT deep suffix-collision put (depth 10+)",
		ops     = coll_n,
		elapsed = elapsed_coll_put,
	})

	coll_slot, _ := xitdb.array_list_get_slot(history, -1)

	coll_rem_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Coll_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for h in c.hashes {
			_, err := xitdb.hash_map_remove_by_hash(&m, h)
			if err != nil do return err
		}
		return nil
	}

	t9 := time.now()
	_ = xitdb.array_list_append_context(&history, coll_slot.?, coll_rem_cb, &col_ctx)
	elapsed_coll_rem := time.since(t9)

	print_result(Bench_Result{
		name    = "HAMT deep suffix-collision branch collapse",
		ops     = coll_n,
		elapsed = elapsed_coll_rem,
	})

	// 1i. Counted_Hash_Set key-only put (`Hash_Map_Get_Key` with `if_empty = true`) & lookup
	cset_put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Insert_Ctx)(user_data)
		cs := xitdb.write_counted_hash_set_init(cursor^) or_return
		for k in c.keys {
			xitdb.hash_set_put(&cs, k) or_return
		}
		return nil
	}

	t10 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, cset_put_cb, &ictx)
	elapsed_cset_put := time.since(t10)

	print_result(Bench_Result{
		name    = "HAMT Counted_Hash_Set key-only put (1 tx)",
		ops     = n,
		elapsed = elapsed_cset_put,
	})

	cset_cur, _ := xitdb.array_list_get_cursor(history, -1)
	rcset, _ := xitdb.read_counted_hash_set_init(cset_cur.?)
	cset_cnt, _ := xitdb.counted_hash_set_count(rcset)
	assert(cset_cnt == i64(n))

	t11 := time.now()
	for k in keys {
		kc, _ := xitdb.hash_set_get_cursor(rcset.read_hash_set, k)
		assert(kc != nil)
	}
	elapsed_cset_get := time.since(t11)

	print_result(Bench_Result{
		name    = "HAMT Counted_Hash_Set membership check",
		ops     = n,
		elapsed = elapsed_cset_get,
	})

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// 2. Radix Trie (`Array_List`) vs Count-Augmented B-Tree (`Linked_Array_List`)
// ----------------------------------------------------------------------------

bench_lists :: proc(n: int) {
	// 2a. Array_List (16-way Radix Trie)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)

		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		List_Ctx :: struct {
			n: int,
		}
		lctx := List_Ctx{n = n}

		append_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^List_Ctx)(user_data)
			list := xitdb.write_array_list_init(cursor^) or_return
			for i in 0 ..< c.n {
				xitdb.array_list_append(&list, u64(i)) or_return
			}
			return nil
		}

		t0 := time.now()
		_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, append_cb, &lctx)
		elapsed_append := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Array_List (Radix Trie) append",
			ops        = n,
			elapsed    = elapsed_append,
			bytes_used = sz,
		})

		l_cur, _ := xitdb.array_list_get_cursor(history, 0)
		rlist, _ := xitdb.read_array_list_init(l_cur.?)

		t1 := time.now()
		for i in 0 ..< n {
			ic, _ := xitdb.array_list_get_cursor(rlist, i64(i))
			v, _ := xitdb.cursor_read_uint(ic.?)
			assert(v == u64(i))
		}
		elapsed_get := time.since(t1)

		print_result(Bench_Result{
			name    = "Array_List (Radix Trie) random get",
			ops     = n,
			elapsed = elapsed_get,
		})

		t2 := time.now()
		it, _ := xitdb.array_list_iterator(rlist)
		cnt := 0
		for {
			c_maybe, _ := xitdb.cursor_iterator_next(&it)
			c, ok := c_maybe.?
			if !ok do break
			_, _ = xitdb.cursor_read_uint(c)
			cnt += 1
		}
		assert(cnt == n)
		elapsed_iter := time.since(t2)

		print_result(Bench_Result{
			name    = "Array_List (Radix Trie) iterator scan",
			ops     = n,
			elapsed = elapsed_iter,
		})

		put_arr_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^List_Ctx)(user_data)
			list := xitdb.write_array_list_init(cursor^) or_return
			for i in 0 ..< c.n {
				xitdb.array_list_put(&list, i64(i), u64(i + 1_000_000)) or_return
			}
			return nil
		}

		m0_arr_slot, _ := xitdb.array_list_get_slot(history, 0)
		t3 := time.now()
		_ = xitdb.array_list_append_context(&history, m0_arr_slot.?, put_arr_cb, &lctx)
		elapsed_put_arr := time.since(t3)

		print_result(Bench_Result{
			name    = "Array_List (Radix Trie) in-place put",
			ops     = n,
			elapsed = elapsed_put_arr,
		})

		t4 := time.now()
		for i in 0 ..< n {
			ait, _ := xitdb.array_list_iterator_from(rlist, i64(i))
			for _ in 0 ..< 10 {
				c_maybe, _ := xitdb.cursor_iterator_next(&ait)
				if c_maybe == nil do break
			}
		}
		elapsed_arr_seek := time.since(t4)

		print_result(Bench_Result{
			name    = "Array_List (Radix Trie) index-seek page(10)",
			ops     = n,
			elapsed = elapsed_arr_seek,
		})

		slice_iters := 500
		slice_arr_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			list := xitdb.write_array_list_init(cursor^) or_return
			return xitdb.array_list_slice(&list, 10)
		}

		t5 := time.now()
		for _ in 0 ..< slice_iters {
			_ = xitdb.array_list_append_context(&history, m0_arr_slot.?, slice_arr_cb, nil)
		}
		elapsed_arr_slice := time.since(t5)

		print_result(Bench_Result{
			name    = "Array_List (Radix Trie) depth-collapse slice",
			ops     = slice_iters,
			elapsed = elapsed_arr_slice,
		})
	}

	// 2b. Linked_Array_List (Count-Augmented B-Tree)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)

		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		List_Ctx :: struct {
			n: int,
		}
		lctx := List_Ctx{n = n}

		append_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^List_Ctx)(user_data)
			list := xitdb.write_linked_array_list_init(cursor^) or_return
			for i in 0 ..< c.n {
				xitdb.linked_array_list_append(&list, u64(i)) or_return
			}
			return nil
		}

		t0 := time.now()
		_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, append_cb, &lctx)
		elapsed_append := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Linked_Array_List (B-Tree) append",
			ops        = n,
			elapsed    = elapsed_append,
			bytes_used = sz,
		})

		l_cur, _ := xitdb.array_list_get_cursor(history, 0)
		rlist, _ := xitdb.read_linked_array_list_init(l_cur.?)

		t1 := time.now()
		for i in 0 ..< n {
			ic, _ := xitdb.linked_array_list_get_cursor(rlist, i64(i))
			v, _ := xitdb.cursor_read_uint(ic.?)
			assert(v == u64(i))
		}
		elapsed_get := time.since(t1)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) random get",
			ops     = n,
			elapsed = elapsed_get,
		})

		t2 := time.now()
		it, _ := xitdb.linked_array_list_iterator(rlist)
		cnt := 0
		for {
			c_maybe, _ := xitdb.cursor_iterator_next(&it)
			c, ok := c_maybe.?
			if !ok do break
			_, _ = xitdb.cursor_read_uint(c)
			cnt += 1
		}
		assert(cnt == n)
		elapsed_iter := time.since(t2)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) iterator scan",
			ops     = n,
			elapsed = elapsed_iter,
		})

		// 2c. B-Tree structural rope ops: middle insert, middle remove, slice (`btree_split`) & concat (`btree_join`)
		mid_ops := 500
		Mid_Ctx :: struct {
			ops: int,
		}
		mctx := Mid_Ctx{ops = mid_ops}

		insert_mid_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Mid_Ctx)(user_data)
			list := xitdb.write_linked_array_list_init(cursor^) or_return
			for i in 0 ..< c.ops {
				cnt, _ := xitdb.linked_array_list_count(list)
				xitdb.linked_array_list_insert(&list, cnt / 2, u64(i)) or_return
			}
			return nil
		}

		m0_slot, _ := xitdb.array_list_get_slot(history, 0)
		t3 := time.now()
		_ = xitdb.array_list_append_context(&history, m0_slot.?, insert_mid_cb, &mctx)
		elapsed_mid_ins := time.since(t3)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) middle insert",
			ops     = mid_ops,
			elapsed = elapsed_mid_ins,
		})

		remove_mid_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Mid_Ctx)(user_data)
			list := xitdb.write_linked_array_list_init(cursor^) or_return
			for _ in 0 ..< c.ops {
				cnt, _ := xitdb.linked_array_list_count(list)
				xitdb.linked_array_list_remove(&list, cnt / 2) or_return
			}
			return nil
		}

		m1_slot, _ := xitdb.array_list_get_slot(history, 1)
		t4 := time.now()
		_ = xitdb.array_list_append_context(&history, m1_slot.?, remove_mid_cb, &mctx)
		elapsed_mid_rem := time.since(t4)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) middle remove",
			ops     = mid_ops,
			elapsed = elapsed_mid_rem,
		})

		Rope_Ctx :: struct {
			base_slot: xitdb.Slot,
			iters:     int,
		}
		rctx := Rope_Ctx{base_slot = m0_slot.?, iters = 200}

		rope_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Rope_Ctx)(user_data)
			list := xitdb.write_linked_array_list_init(cursor^) or_return
			for _ in 0 ..< c.iters {
				xitdb.linked_array_list_concat(&list, c.base_slot) or_return
				cnt, _ := xitdb.linked_array_list_count(list)
				xitdb.linked_array_list_slice(&list, cnt / 4, cnt / 2) or_return
			}
			return nil
		}

		t5 := time.now()
		_ = xitdb.array_list_append_context(&history, m0_slot.?, rope_cb, &rctx)
		elapsed_rope := time.since(t5)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) concat + slice",
			ops     = rctx.iters * 2,
			elapsed = elapsed_rope,
		})

		put_lal_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^List_Ctx)(user_data)
			list := xitdb.write_linked_array_list_init(cursor^) or_return
			for i in 0 ..< c.n {
				xitdb.linked_array_list_put(&list, i64(i), u64(i + 1_000_000)) or_return
			}
			return nil
		}

		t6 := time.now()
		_ = xitdb.array_list_append_context(&history, m0_slot.?, put_lal_cb, &lctx)
		elapsed_put_lal := time.since(t6)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) in-place put",
			ops     = n,
			elapsed = elapsed_put_lal,
		})

		t7 := time.now()
		for i in 0 ..< n {
			lit, _ := xitdb.linked_array_list_iterator_from(rlist, i64(i))
			for _ in 0 ..< 10 {
				c_maybe, _ := xitdb.cursor_iterator_next(&lit)
				if c_maybe == nil do break
			}
		}
		elapsed_lal_seek := time.since(t7)

		print_result(Bench_Result{
			name    = "Linked_Array_List (B-Tree) index-seek page(10)",
			ops     = n,
			elapsed = elapsed_lal_seek,
		})
	}
}

// ----------------------------------------------------------------------------
// 3. B+Tree (`Sorted_Map`) Out-of-Order Insert, Key Lookup, Rank & Scan
// ----------------------------------------------------------------------------

bench_sorted_map :: proc(n: int) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	rc := xitdb.database_root_cursor(&db)
	history, _ := xitdb.write_array_list_init(rc)

	keys := make([]string, n, context.temp_allocator)
	for i in 0 ..< n {
		// Deterministic coprime permutation so insertions hit B+Tree leaves out of order
		perm := (i * 1999 + 73) % n
		keys[i] = fmt.tprintf("skey-%06d", perm)
	}

	Sorted_Ctx :: struct {
		keys: []string,
	}
	sctx := Sorted_Ctx{keys = keys}

	put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Sorted_Ctx)(user_data)
		sm := xitdb.write_sorted_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.sorted_map_put(&sm, k, u64(idx)) or_return
		}
		return nil
	}

	t0 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, put_cb, &sctx)
	elapsed_put := time.since(t0)
	sz, _ := xitdb.database_committed_size(&db)

	print_result(Bench_Result{
		name       = "Sorted_Map (B+Tree) out-of-order put",
		ops        = n,
		elapsed    = elapsed_put,
		bytes_used = sz,
	})

	sm_cur, _ := xitdb.array_list_get_cursor(history, 0)
	sm, _ := xitdb.read_sorted_map_init(sm_cur.?)

	t1 := time.now()
	for k, idx in keys {
		vc, _ := xitdb.sorted_map_get_cursor(sm, k)
		v, _ := xitdb.cursor_read_uint(vc.?)
		assert(v == u64(idx))
	}
	elapsed_get := time.since(t1)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) key lookup",
		ops     = n,
		elapsed = elapsed_get,
	})

	t2 := time.now()
	for k in keys {
		rk, _ := xitdb.sorted_map_rank(sm, k)
		assert(rk >= 0 && rk < i64(n))
	}
	elapsed_rank := time.since(t2)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) rank query",
		ops     = n,
		elapsed = elapsed_rank,
	})

	t3 := time.now()
	it, _ := xitdb.sorted_map_iterator(sm)
	cnt := 0
	for {
		c_maybe, _ := xitdb.cursor_iterator_next(&it)
		if c_maybe == nil do break
		cnt += 1
	}
	assert(cnt == n)
	elapsed_iter := time.since(t3)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) ordered scan",
		ops     = n,
		elapsed = elapsed_iter,
	})

	// 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
	t4 := time.now()
	for k in keys {
		rit, _ := xitdb.sorted_map_iterator_from_string(sm, k)
		for _ in 0 ..< 10 {
			c_maybe, _ := xitdb.cursor_iterator_next(&rit)
			if c_maybe == nil do break
		}
	}
	elapsed_range_seek := time.since(t4)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) lower-bound page(10)",
		ops     = n,
		elapsed = elapsed_range_seek,
	})

	// 3c. Out-of-order B+Tree key removal & node rebalancing/merging
	rem_count := n / 2
	Sorted_Rem_Ctx :: struct {
		keys: []string,
	}
	srctx := Sorted_Rem_Ctx{keys = keys[:rem_count]}

	rem_sorted_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Sorted_Rem_Ctx)(user_data)
		wsm := xitdb.write_sorted_map_init(cursor^) or_return
		for k in c.keys {
			_, err := xitdb.sorted_map_remove(&wsm, k)
			if err != nil do return err
		}
		return nil
	}

	m0_slot, _ := xitdb.array_list_get_slot(history, 0)
	t5 := time.now()
	_ = xitdb.array_list_append_context(&history, m0_slot.?, rem_sorted_cb, &srctx)
	elapsed_rem := time.since(t5)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) remove & rebalance",
		ops     = rem_count,
		elapsed = elapsed_rem,
	})

	// 3d. Order-Statistic B+Tree positional select (`sorted_map_get_index_kv_pair`)
	t6 := time.now()
	for i in 0 ..< n {
		kv_maybe, _ := xitdb.sorted_map_get_index_kv_pair(sm, i64(i))
		assert(kv_maybe != nil)
	}
	elapsed_select := time.since(t6)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) get_index select",
		ops     = n,
		elapsed = elapsed_select,
	})

	// 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
	t7 := time.now()
	for i in 0 ..< n {
		iit, _ := xitdb.sorted_map_iterator_from_index(sm, i64(i))
		for _ in 0 ..< 10 {
			c_maybe, _ := xitdb.cursor_iterator_next(&iit)
			if c_maybe == nil do break
		}
	}
	elapsed_index_seek := time.since(t7)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) index-seek page(10)",
		ops     = n,
		elapsed = elapsed_index_seek,
	})

	// 3f. Sorted_Map in-place overwrite of existing keys (`found == true` in `sorted_put`)
	overwrite_sorted_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Sorted_Ctx)(user_data)
		wsm := xitdb.write_sorted_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.sorted_map_put(&wsm, k, u64(idx + 1_000_000)) or_return
		}
		return nil
	}

	t8 := time.now()
	_ = xitdb.array_list_append_context(&history, m0_slot.?, overwrite_sorted_cb, &sctx)
	elapsed_overwrite := time.since(t8)

	print_result(Bench_Result{
		name    = "Sorted_Map (B+Tree) in-place overwrite",
		ops     = n,
		elapsed = elapsed_overwrite,
	})

	// 3g. Sorted_Set key-only put (`Sorted_Map_Get_Key` without value slot write) & `sorted_set_contains`
	sset_put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Sorted_Ctx)(user_data)
		ss := xitdb.write_sorted_set_init(cursor^) or_return
		for k in c.keys {
			xitdb.sorted_set_put(&ss, k) or_return
		}
		return nil
	}

	t9 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, sset_put_cb, &sctx)
	elapsed_sset_put := time.since(t9)

	print_result(Bench_Result{
		name    = "Sorted_Set (B+Tree) key-only put (1 tx)",
		ops     = n,
		elapsed = elapsed_sset_put,
	})

	ss_cur, _ := xitdb.array_list_get_cursor(history, -1)
	rss, _ := xitdb.read_sorted_set_init(ss_cur.?)

	t10 := time.now()
	for k in keys {
		ok, _ := xitdb.sorted_set_contains(rss, k)
		assert(ok)
	}
	elapsed_sset_contains := time.since(t10)

	print_result(Bench_Result{
		name    = "Sorted_Set (B+Tree) contains lookup",
		ops     = n,
		elapsed = elapsed_sset_contains,
	})

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// 4. Compaction & Incremental Replication Throughput
// ----------------------------------------------------------------------------

bench_compaction_and_replication :: proc(moments_count: int) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	rc := xitdb.database_root_cursor(&db)
	history, _ := xitdb.write_array_list_init(rc)

	Commit_Ctx :: struct {
		idx: int,
	}
	cctx: Commit_Ctx

	commit_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Commit_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for j in 0 ..< 10 {
			k := fmt.tprintf("k-%02d", j)
			xitdb.hash_map_put(&m, k, u64(c.idx * 10 + j)) or_return
		}
		return nil
	}

	for i in 0 ..< moments_count {
		cctx.idx = i
		base_slot := xitdb.Slot{}
		if i > 0 {
			s_maybe, _ := xitdb.array_list_get_slot(history, -1)
			base_slot = s_maybe.?
		}
		_ = xitdb.array_list_append_context(&history, base_slot, commit_cb, &cctx)
	}

	// 4a. Replicate all moments to a fresh secondary replica
	rep_core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&rep_core)
	rep_db, _ := xitdb.database_init(&rep_core, xitdb.sha1_hasher())

	t0 := time.now()
	rep_state, _ := xitdb.database_replica_state(&rep_db)
	start_off, _ := xitdb.database_replication_start(&db, rep_state)
	end_off, _ := xitdb.database_committed_size(&db)
	payload, _ := xitdb.database_read_committed_bytes(&db, start_off, end_off, context.temp_allocator)
	_ = xitdb.database_apply_replicated_bytes(&rep_db, start_off, payload)
	elapsed_rep := time.since(t0)

	print_result(Bench_Result{
		name       = "Replication (genesis -> 200 moments)",
		ops        = moments_count,
		elapsed    = elapsed_rep,
		bytes_used = end_off,
	})

	// 4a-delta. Incremental delta replication (100 single-moment commits synced incrementally)
	delta_commits := 100
	t_delta := time.Duration(0)
	delta_bytes := i64(0)
	delta_buf := make([]u8, 16384, context.temp_allocator)
	for i in 0 ..< delta_commits {
		cctx.idx = moments_count + i
		s_maybe, _ := xitdb.array_list_get_slot(history, -1)
		_ = xitdb.array_list_append_context(&history, s_maybe.?, commit_cb, &cctx)

		td0 := time.now()
		d_state, _ := xitdb.database_replica_state(&rep_db)
		d_start, _ := xitdb.database_replication_start(&db, d_state)
		d_end, _ := xitdb.database_committed_size(&db)
		d_payload, _ := xitdb.database_read_committed_buf(&db, d_start, d_end, delta_buf)
		_ = xitdb.database_apply_replicated_bytes(&rep_db, d_start, d_payload)
		t_delta += time.since(td0)
		delta_bytes += (d_end - d_start)
	}

	print_result(Bench_Result{
		name       = "Replication (incremental 1-moment delta)",
		ops        = delta_commits,
		elapsed    = t_delta,
		bytes_used = delta_bytes,
	})

	// 4b. Prune to latest 1 moment & compact database
	_ = xitdb.array_list_slice(&history, 1)

	comp_core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&comp_core)

	t1 := time.now()
	offset_map: xitdb.Offset_Map = xitdb.memory_offset_map_init()
	defer xitdb.offset_map_destroy(&offset_map)
	comp_db, _ := xitdb.database_compact(&db, &comp_core, &offset_map)
	elapsed_compact := time.since(t1)
	comp_size, _ := xitdb.database_committed_size(&comp_db)

	print_result(Bench_Result{
		name       = "Compaction (Memory_Offset_Map, 200 -> 1)",
		ops        = 1,
		elapsed    = elapsed_compact,
		bytes_used = comp_size,
	})

	// 4c. Compact using disk-backed `File_Offset_Map`
	comp_file_core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&comp_file_core)

	om_core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&om_core)
	om_db, _ := xitdb.database_init(&om_core, xitdb.sha1_hasher())
	om_rc := xitdb.database_root_cursor(&om_db)
	file_om, _ := xitdb.file_offset_map_init(om_rc)
	file_offset_map: xitdb.Offset_Map = file_om

	t2 := time.now()
	comp_db2, _ := xitdb.database_compact(&db, &comp_file_core, &file_offset_map)
	elapsed_file_compact := time.since(t2)
	comp_size2, _ := xitdb.database_committed_size(&comp_db2)

	print_result(Bench_Result{
		name       = "Compaction (File_Offset_Map, 200 -> 1)",
		ops        = 1,
		elapsed    = elapsed_file_compact,
		bytes_used = comp_size2,
	})

	// 4d. Heterogeneous DAG Compaction (`Array_List` + `Linked_Array_List` + `Sorted_Map` + `Counted_Hash_Map` + DAG shared subtrees)
	{
		dag_src_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&dag_src_core)
		dag_db, _ := xitdb.database_init(&dag_src_core, xitdb.sha1_hasher())

		build_dag_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			root_map := xitdb.write_counted_hash_map_init(cursor^) or_return

			// 1. Array_List with 200 items
			al_wc := xitdb.hash_map_put_cursor(&root_map, "array_list") or_return
			al := xitdb.write_array_list_init(al_wc) or_return
			for i in 0 ..< 200 {
				xitdb.array_list_append(&al, fmt.tprintf("arr-item-%04d-payload", i)) or_return
			}
			al_slot := xitdb.array_list_slot(al.read_array_list) or_return

			// 2. Linked_Array_List with 200 items
			lal_wc := xitdb.hash_map_put_cursor(&root_map, "linked_list") or_return
			lal := xitdb.write_linked_array_list_init(lal_wc) or_return
			for i in 0 ..< 200 {
				xitdb.linked_array_list_append(&lal, u64(i)) or_return
			}
			lal_slot := xitdb.linked_array_list_slot(lal.read_linked_array_list) or_return

			// 3. Sorted_Map with 200 items
			sm_wc := xitdb.hash_map_put_cursor(&root_map, "sorted_map") or_return
			sm := xitdb.write_sorted_map_init(sm_wc) or_return
			for i in 0 ..< 200 {
				xitdb.sorted_map_put(&sm, fmt.tprintf("skey-%04d", (i * 73) % 200), u64(i)) or_return
			}
			sm_slot := xitdb.sorted_map_slot(sm.read_sorted_map) or_return

			// 4. DAG structural sharing: reference the same 3 collections under 5 alias keys each
			for alias_i in 0 ..< 5 {
				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-al-%d", alias_i), al_slot) or_return
				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-lal-%d", alias_i), lal_slot) or_return
				xitdb.hash_map_put(&root_map, fmt.tprintf("alias-sm-%d", alias_i), sm_slot) or_return
			}
			return nil
		}

		_ = xitdb.database_run_context(&dag_db, build_dag_cb, nil)

		dag_dst_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&dag_dst_core)
		dag_om: xitdb.Offset_Map = xitdb.memory_offset_map_init()
		defer xitdb.offset_map_destroy(&dag_om)

		t_dag := time.now()
		dag_comp_db, _ := xitdb.database_compact(&dag_db, &dag_dst_core, &dag_om)
		elapsed_dag := time.since(t_dag)
		dag_comp_sz, _ := xitdb.database_committed_size(&dag_comp_db)

		print_result(Bench_Result{
			name       = "Compaction (Heterogeneous DAG + dedup)",
			ops        = 1,
			elapsed    = elapsed_dag,
			bytes_used = dag_comp_sz,
		})

		// 4f. Post-compaction replica resync (`database_replication_start` divergence detection + full replacement sync)
		resync_rep_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&resync_rep_core)
		resync_rep_db, _ := xitdb.database_init(&resync_rep_core, xitdb.sha1_hasher())

		// First sync replica with pre-compaction DAG primary
		orig_end, _ := xitdb.database_committed_size(&dag_db)
		orig_bytes, _ := xitdb.database_read_committed_bytes(&dag_db, 0, orig_end, context.temp_allocator)
		_ = xitdb.database_apply_replicated_bytes(&resync_rep_db, 0, orig_bytes)

		// Now measure resync against the compacted DAG primary (`dag_comp_db`)
		t_resync := time.now()
		rep_state, _ := xitdb.database_replica_state(&resync_rep_db)
		resync_start, _ := xitdb.database_replication_start(&dag_comp_db, rep_state)
		assert(resync_start == 0)
		comp_end, _ := xitdb.database_committed_size(&dag_comp_db)
		comp_payload, _ := xitdb.database_read_committed_buf(&dag_comp_db, resync_start, comp_end, orig_bytes)
		_ = xitdb.database_apply_replicated_bytes(&resync_rep_db, resync_start, comp_payload)
		elapsed_resync := time.since(t_resync)

		print_result(Bench_Result{
			name       = "Replication (Post-compaction resync)",
			ops        = 1,
			elapsed    = elapsed_resync,
			bytes_used = i64(len(comp_payload)),
		})
	}

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// 5. Hasher Comparison (`SHA-1` 20B vs `SHA-256` 32B) & Byte Storage Paths
// ----------------------------------------------------------------------------

bench_hashers_and_byte_streams :: proc(n: int) {
	keys := make([]string, n, context.temp_allocator)
	for i in 0 ..< n {
		keys[i] = fmt.tprintf("hash-bench-key-%06d", i)
	}

	Hash_Ctx :: struct {
		keys: []string,
	}
	hctx := Hash_Ctx{keys = keys}

	put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Hash_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		for k, idx in c.keys {
			xitdb.hash_map_put(&m, k, u64(idx)) or_return
		}
		return nil
	}

	// 5a. SHA-1 (20-byte digest) vs SHA-256 (32-byte digest) HAMT insert & footprint
	for algo in ([]string{"sha1", "sha256"}) {
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)

		hasher := xitdb.sha1_hasher() if algo == "sha1" else xitdb.sha256_hasher()
		db, _ := xitdb.database_init(&core, hasher)
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		t0 := time.now()
		_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, put_cb, &hctx)
		elapsed := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		label := "Hasher: SHA-1 (20B) HAMT put" if algo == "sha1" else "Hasher: SHA-256 (32B) HAMT put"
		print_result(Bench_Result{
			name       = label,
			ops        = n,
			elapsed    = elapsed,
			bytes_used = sz,
		})
	}

	// 5b. Inline `Short_Bytes` (<= 8B) vs External `Bytes` (> 8B) zero-alloc stack reads
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		m, _ := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))

		_ = xitdb.hash_map_put(&m, "inline", "8bytes!!")
		_ = xitdb.hash_map_put(&m, "heap", "heap-allocated-32-byte-string!!!")

		inline_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "inline")
		heap_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "heap")

		reads := n * 5
		stack_buf: [64]u8

		t_in := time.now()
		for _ in 0 ..< reads {
			obj, _ := xitdb.cursor_read_bytes_buf(inline_cur.?, stack_buf[:])
			assert(len(obj.value) == 8)
		}
		print_result(Bench_Result{
			name    = "Bytes: Inline Short_Bytes read_bytes_buf",
			ops     = reads,
			elapsed = time.since(t_in),
		})

		t_hp := time.now()
		for _ in 0 ..< reads {
			obj, _ := xitdb.cursor_read_bytes_buf(heap_cur.?, stack_buf[:])
			assert(len(obj.value) == 32)
		}
		print_result(Bench_Result{
			name    = "Bytes: External Bytes read_bytes_buf",
			ops     = reads,
			elapsed = time.since(t_hp),
		})

		// Format-tagged `Bytes` (`slot.full == true`, 2-byte tag) inline (6B) vs external (32B) read_bytes_buf
		_ = xitdb.hash_map_put(&m, "tagged_inline", xitdb.new_tagged_string("6bytes", transmute([]u8)string("js")))
		_ = xitdb.hash_map_put(&m, "tagged_heap", xitdb.new_tagged_string("heap-allocated-32-byte-string!!!", transmute([]u8)string("md")))

		t_in_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "tagged_inline")
		t_hp_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "tagged_heap")

		t_tin := time.now()
		for _ in 0 ..< reads {
			obj, _ := xitdb.cursor_read_bytes_buf(t_in_cur.?, stack_buf[:])
			assert(len(obj.value) == 6 && len(obj.format_tag) == 2)
		}
		print_result(Bench_Result{
			name    = "Bytes: Tagged Short_Bytes read_bytes_buf",
			ops     = reads,
			elapsed = time.since(t_tin),
		})

		t_thp := time.now()
		for _ in 0 ..< reads {
			obj, _ := xitdb.cursor_read_bytes_buf(t_hp_cur.?, stack_buf[:])
			assert(len(obj.value) == 32 && len(obj.format_tag) == 2)
		}
		print_result(Bench_Result{
			name    = "Bytes: Tagged External Bytes read_bytes_buf",
			ops     = reads,
			elapsed = time.since(t_thp),
		})
	}

	// 5c. Streaming `Cursor_Writer` & `Cursor_Reader` (1 MB payload in 4 KB chunks)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

		chunks_count := 256 // 256 * 4 KB = 1 MB
		Stream_Ctx :: struct {
			chunks_count: int,
			blob_rc:      xitdb.Read_Cursor,
		}
		sctx := Stream_Ctx{chunks_count = chunks_count}

		stream_write_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Stream_Ctx)(user_data)
			w := xitdb.cursor_writer(cursor) or_return
			chunk: [4096]u8
			for i in 0 ..< c.chunks_count {
				chunk[0] = u8(i)
				_, err := xitdb.cursor_writer_write(&w, chunk[:])
				if err != nil do return err
			}
			xitdb.cursor_writer_finish(&w) or_return
			c.blob_rc = cursor.read_cursor
			return nil
		}

		t_sw := time.now()
		_ = xitdb.database_run_context(&db, stream_write_cb, &sctx)
		elapsed_sw := time.since(t_sw)
		sz_sw, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Stream: Cursor_Writer (256 x 4KB = 1MB)",
			ops        = chunks_count,
			elapsed    = elapsed_sw,
			bytes_used = sz_sw,
		})

		t_sr := time.now()
		reader, _ := xitdb.cursor_reader(sctx.blob_rc)
		read_buf: [4096]u8
		read_chunks := 0
		for {
			nr, _ := xitdb.cursor_reader_read(&reader, read_buf[:])
			if nr == 0 do break
			read_chunks += 1
		}
		assert(read_chunks == chunks_count)
		elapsed_sr := time.since(t_sr)

		print_result(Bench_Result{
			name    = "Stream: Cursor_Reader (256 x 4KB = 1MB)",
			ops     = chunks_count,
			elapsed = elapsed_sr,
		})

		// Random-access seek + 64B read across the 1 MB blob (`cursor_reader_seek_to`)
		seek_ops := n
		small_buf: [64]u8
		t_rseek := time.now()
		for i in 0 ..< seek_ops {
			off := i64((i * 4099) % (chunks_count * 4096 - 64))
			_ = xitdb.cursor_reader_seek_to(&reader, off)
			_ = xitdb.cursor_reader_read_fully(&reader, small_buf[:])
		}
		elapsed_rseek := time.since(t_rseek)

		print_result(Bench_Result{
			name    = "Stream: Cursor_Reader random seek + 64B read",
			ops     = seek_ops,
			elapsed = elapsed_rseek,
		})

		// Random-access in-place patch via `cursor_writer_seek_to`
		Patch_Ctx :: struct {
			ops: int,
		}
		pctx := Patch_Ctx{ops = seek_ops}

		stream_patch_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Patch_Ctx)(user_data)
			w := xitdb.cursor_writer(cursor) or_return
			init_buf: [65536]u8
			_, _ = xitdb.cursor_writer_write(&w, init_buf[:])
			patch: [16]u8
			for i in 0 ..< c.ops {
				off := i64((i * 1031) % (65536 - 16))
				xitdb.cursor_writer_seek_to(&w, off) or_return
				patch[0] = u8(i)
				_, err := xitdb.cursor_writer_write(&w, patch[:])
				if err != nil do return err
			}
			return xitdb.cursor_writer_finish(&w)
		}

		t_wseek := time.now()
		_ = xitdb.database_run_context(&db, stream_patch_cb, &pctx)
		elapsed_wseek := time.since(t_wseek)

		print_result(Bench_Result{
			name    = "Stream: Cursor_Writer random seek + 16B patch",
			ops     = seek_ops,
			elapsed = elapsed_wseek,
		})
	}

	// 5d. Deeply Nested Multi-Part Atomic Path Traversal (`cursor_write_path` & `cursor_read_path` across 4 nested collections)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

		path_ops := 500
		h_root := xitdb.database_digest_string(&db, "tenant", context.temp_allocator)
		h_leaf := xitdb.database_digest_string(&db, "metric", context.temp_allocator)

		Deep_Ctx :: struct {
			ops:    int,
			h_root: []u8,
			h_leaf: []u8,
		}
		dctx := Deep_Ctx{ops = path_ops, h_root = h_root, h_leaf = h_leaf}

		deep_write_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Deep_Ctx)(user_data)
			// Initialize 4-level hierarchy: Hash_Map -> Array_List -> Linked_Array_List -> Sorted_Map
			_, err := xitdb.cursor_write_path(cursor, []xitdb.Path_Part{
				xitdb.Hash_Map_Init{counted = false, set = false},
				xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = c.h_root}},
				xitdb.Array_List_Init{},
				xitdb.Array_List_Append{},
				xitdb.Linked_Array_List_Init{},
				xitdb.Linked_Array_List_Append{},
				xitdb.Sorted_Map_Init{set = false},
			})
			if err != nil do return err

			skey := transmute([]u8)string("deep-sorted-key")
			for i in 0 ..< c.ops {
				_, err = xitdb.cursor_write_path(cursor, []xitdb.Path_Part{
					xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = c.h_root}},
					xitdb.Array_List_Get{index = 0},
					xitdb.Linked_Array_List_Get{index = 0},
					xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_Value{key = skey}},
					xitdb.Write_Data{data = u64(i)},
				})
				if err != nil do return err
			}
			return nil
		}

		t_dw := time.now()
		_ = xitdb.database_run_context(&db, deep_write_cb, &dctx)
		elapsed_dw := time.since(t_dw)

		print_result(Bench_Result{
			name    = "Path: 4-level nested cursor_write_path",
			ops     = path_ops,
			elapsed = elapsed_dw,
		})

		rc := xitdb.database_root_cursor(&db).read_cursor
		skey := transmute([]u8)string("deep-sorted-key")
		read_parts := []xitdb.Path_Part{
			xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = h_root}},
			xitdb.Array_List_Get{index = 0},
			xitdb.Linked_Array_List_Get{index = 0},
			xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_Value{key = skey}},
		}

		t_dr := time.now()
		for _ in 0 ..< path_ops {
			mc, _ := xitdb.cursor_read_path(rc, read_parts)
			v, _ := xitdb.cursor_read_uint(mc.?)
			assert(v == u64(path_ops - 1))
		}
		elapsed_dr := time.since(t_dr)

		print_result(Bench_Result{
			name    = "Path: 4-level nested cursor_read_path",
			ops     = path_ops,
			elapsed = elapsed_dr,
		})
	}

	// 5e. Full KV-Pair Inspection Scan (`cursor_read_kv_pair` decoding both key and value cursors across `n` entries)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)
		_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, put_cb, &hctx)

		mc, _ := xitdb.array_list_get_cursor(history.read_array_list, 0)
		rm, _ := xitdb.read_hash_map_init(mc.?)

		key_buf: [64]u8
		kv_cnt := 0
		t_kv := time.now()
		it, _ := xitdb.hash_map_iterator(rm)
		for {
			cur_maybe, _ := xitdb.cursor_iterator_next(&it)
			cur, ok := cur_maybe.?
			if !ok do break
			kv, _ := xitdb.cursor_read_kv_pair(cur, context.temp_allocator)
			k_obj, _ := xitdb.cursor_read_bytes_buf(kv.key_cursor, key_buf[:])
			v_uint, _ := xitdb.cursor_read_uint(kv.value_cursor)
			assert(len(k_obj.value) > 0 && v_uint < u64(n))
			kv_cnt += 1
		}
		assert(kv_cnt == n)
		elapsed_kv := time.since(t_kv)

		print_result(Bench_Result{
			name    = "Cursor: Full KV-pair scan (read_kv_pair)",
			ops     = n,
			elapsed = elapsed_kv,
		})
	}

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// 5. Storage Backends (`Core_Memory` vs `Core_Buffered_File` vs `Core_File`)
// ----------------------------------------------------------------------------

bench_backends :: proc(commits: int) {
	Tx_Ctx :: struct {
		step: int,
	}

	tx_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Tx_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&m, "counter", u64(c.step)) or_return
		xitdb.hash_map_put(&m, "label", "benchmark-payload-string") or_return
		return nil
	}

	// 5a. Core_Memory
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		t0 := time.now()
		tctx: Tx_Ctx
		for i in 0 ..< commits {
			tctx.step = i
			base := xitdb.Slot{}
			if i > 0 {
				s, _ := xitdb.array_list_get_slot(history, -1)
				base = s.?
			}
			_ = xitdb.array_list_append_context(&history, base, tx_cb, &tctx)
		}
		elapsed := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Backend: Core_Memory commits",
			ops        = commits,
			elapsed    = elapsed,
			bytes_used = sz,
		})
	}

	temp_dir, td_err := os.temp_directory(context.temp_allocator)
	if td_err != nil || len(temp_dir) == 0 {
		temp_dir = "."
	}

	// 5b. Core_Buffered_File (64 KB buffer, fsync = false)
	{
		path := fmt.tprintf("%s/xitdb_bench_buffered.db", temp_dir)
		_ = os.remove(path)

		core, _ := xitdb.core_buffered_file_open(path, 65536, {.Read, .Write, .Create, .Trunc}, false)
		defer {
			_ = xitdb.core_destroy(&core, true)
			_ = os.remove(path)
		}

		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		t0 := time.now()
		tctx: Tx_Ctx
		for i in 0 ..< commits {
			tctx.step = i
			base := xitdb.Slot{}
			if i > 0 {
				s, _ := xitdb.array_list_get_slot(history, -1)
				base = s.?
			}
			_ = xitdb.array_list_append_context(&history, base, tx_cb, &tctx)
		}
		elapsed := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Backend: Core_Buffered_File commits",
			ops        = commits,
			elapsed    = elapsed,
			bytes_used = sz,
		})
	}

	// 5c. Core_File (unbuffered OS syscalls, fsync = false)
	{
		path := fmt.tprintf("%s/xitdb_bench_file.db", temp_dir)
		_ = os.remove(path)

		core, _ := xitdb.core_file_open(path, {.Read, .Write, .Create, .Trunc}, false)
		defer {
			_ = xitdb.core_destroy(&core, true)
			_ = os.remove(path)
		}

		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		history, _ := xitdb.write_array_list_init(rc)

		t0 := time.now()
		tctx: Tx_Ctx
		for i in 0 ..< commits {
			tctx.step = i
			base := xitdb.Slot{}
			if i > 0 {
				s, _ := xitdb.array_list_get_slot(history, -1)
				base = s.?
			}
			_ = xitdb.array_list_append_context(&history, base, tx_cb, &tctx)
		}
		elapsed := time.since(t0)
		sz, _ := xitdb.database_committed_size(&db)

		print_result(Bench_Result{
			name       = "Backend: Core_File (unbuffered) commits",
			ops        = commits,
			elapsed    = elapsed,
			bytes_used = sz,
		})
	}

	// 5d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

		Freeze_Ctx :: struct {
			db:    ^xitdb.Database,
			iters: int,
		}
		fctx := Freeze_Ctx{db = &db, iters = commits}

		freeze_cow_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			c := (^Freeze_Ctx)(user_data)
			top := xitdb.write_hash_map_init(cursor^) or_return
			base_wc := xitdb.hash_map_put_cursor(&top, "base") or_return
			base_map := xitdb.write_hash_map_init(base_wc) or_return
			for j in 0 ..< 16 {
				xitdb.hash_map_put(&base_map, fmt.tprintf("k-%02d", j), u64(j)) or_return
			}
			base_slot := xitdb.hash_map_slot(base_map.read_hash_map) or_return

			for i in 0 ..< c.iters {
				xitdb.database_freeze(c.db) or_return
				fork_key := fmt.tprintf("fork-%04d", i)
				xitdb.hash_map_put(&top, fork_key, base_slot) or_return
				fork_wc := xitdb.hash_map_put_cursor(&top, fork_key) or_return
				fork_map := xitdb.write_hash_map_init(fork_wc) or_return
				xitdb.hash_map_put(&fork_map, "k-00", u64(1000 + i)) or_return
			}
			return nil
		}

		t_fc := time.now()
		_ = xitdb.database_run_context(&db, freeze_cow_cb, &fctx)
		elapsed_fc := time.since(t_fc)

		print_result(Bench_Result{
			name    = "Tx: Mid-tx database_freeze + CoW clone",
			ops     = commits,
			elapsed = elapsed_fc,
		})

		rollback_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			top := xitdb.write_hash_map_init(cursor^) or_return
			xitdb.hash_map_put(&top, "temp-1", u64(1)) or_return
			xitdb.hash_map_put(&top, "temp-2", "uncommitted-payload-bytes") or_return
			return .Key_Not_Found // Abort transaction to trigger rollback truncation
		}

		size_before_rb, _ := xitdb.database_committed_size(&db)
		t_rb := time.now()
		for _ in 0 ..< commits {
			err := xitdb.database_run_context(&db, rollback_cb, nil)
			assert(err == .Key_Not_Found)
		}
		elapsed_rb := time.since(t_rb)
		size_after_rb, _ := xitdb.database_committed_size(&db)
		assert(size_after_rb == size_before_rb)

		print_result(Bench_Result{
			name    = "Tx: Aborted transaction rollback truncate",
			ops     = commits,
			elapsed = elapsed_rb,
		})

		// 5e. Database re-open & header/root-trailer checksum validation (`database_init` on populated `Core_Memory`)
		reopen_ops := commits * 10
		t_reopen := time.now()
		for _ in 0 ..< reopen_ops {
			reopened_db, r_err := xitdb.database_init(&core, xitdb.sha1_hasher())
			assert(r_err == nil)
			rc := xitdb.database_root_cursor(&reopened_db)
			assert(rc.slot_ptr.slot.tag == .Hash_Map)
		}
		elapsed_reopen := time.since(t_reopen)

		print_result(Bench_Result{
			name    = "DB: Re-open & trailer checksum verify",
			ops     = reopen_ops,
			elapsed = elapsed_reopen,
		})
	}
	free_all(context.temp_allocator)
}

main :: proc() {
	print_header()
	bench_hamt(2_000)
	bench_lists(2_000)
	bench_sorted_map(2_000)
	bench_compaction_and_replication(200)
	bench_hashers_and_byte_streams(2_000)
	bench_backends(500)
	fmt.println("========================================================================================================")
}
