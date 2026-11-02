package xitdb_benchmarks

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import xitdb "../xitdb"

Bench_Result :: struct {
	name:       string,
	ops:        int,
	elapsed:    time.Duration,
	bytes_used: i64,
}

MAX_GROUP_BENCHES :: 32
MAX_RUNS          :: 256

Bench_Accum :: struct {
	name:       string,
	ops:        int,
	bytes_used: i64,
	samples_ns: [MAX_RUNS]f64,
	samples_ms: [MAX_RUNS]f64,
	count:      int,
}

g_jsonl_file:     ^os.File
g_history_file:   ^os.File
g_bench_rank:     int
g_runs:           int = 5
g_warmup:         int = 1
g_commit_sha:     string = "unknown"
g_run_id:         string = "run-0"
g_append_primary: bool = false
g_save_history:   bool = true
g_jsonl_path:     string = "benchmarks/odin.jsonl"
g_history_path:   string = "benchmarks/history.jsonl"

g_is_warmup:      bool = false
g_group_slot:     int = 0
g_group_count:    int = 0
g_group_accum:    [MAX_GROUP_BENCHES]Bench_Accum

resolve_git_commit :: proc(allocator := context.allocator) -> string {
	head_bytes, err := os.read_entire_file(".git/HEAD", allocator)
	if err != nil {
		return "unknown"
	}
	head_str := strings.trim_space(string(head_bytes))
	if strings.has_prefix(head_str, "ref: ") {
		ref_rel := strings.trim_space(head_str[5:])
		ref_path := fmt.aprintf(".git/%s", ref_rel, allocator = allocator)
		if ref_bytes, r_err := os.read_entire_file(ref_path, allocator); r_err == nil {
			sha := strings.trim_space(string(ref_bytes))
			if len(sha) > 12 {
				return sha[:12]
			}
			return sha
		}
		if packed_bytes, p_err := os.read_entire_file(".git/packed-refs", allocator); p_err == nil {
			lines := strings.split_lines(string(packed_bytes), allocator)
			suffix := fmt.aprintf(" %s", ref_rel, allocator = allocator)
			for line in lines {
				trimmed := strings.trim_space(line)
				if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") || strings.has_prefix(trimmed, "^") {
					continue
				}
				if strings.has_suffix(trimmed, suffix) && len(trimmed) >= 12 {
					return trimmed[:12]
				}
			}
		}
		return "unknown"
	}
	if len(head_str) > 12 {
		return head_str[:12]
	}
	return head_str
}

parse_cli_args :: proc() {
	g_commit_sha = resolve_git_commit()
	unix_sec := i64(time.to_unix_nanoseconds(time.now())) / 1_000_000_000
	g_run_id = fmt.aprintf("run-%d", unix_sec)

	args := os.args[1:]
	i := 0
	for i < len(args) {
		arg := args[i]
		if arg == "--append" || arg == "-append" {
			g_append_primary = true
		} else if arg == "--no-history" || arg == "-no-history" {
			g_save_history = false
		} else if (arg == "--runs" || arg == "-runs") && i + 1 < len(args) {
			if v, ok := strconv.parse_int(args[i + 1]); ok && v > 0 {
				g_runs = clamp(v, 1, MAX_RUNS)
			}
			i += 1
		} else if strings.has_prefix(arg, "--runs=") || strings.has_prefix(arg, "-runs:") {
			eq := strings.index_any(arg, "=:")
			if v, ok := strconv.parse_int(arg[eq + 1:]); ok && v > 0 {
				g_runs = clamp(v, 1, MAX_RUNS)
			}
		} else if (arg == "--warmup" || arg == "-warmup") && i + 1 < len(args) {
			if v, ok := strconv.parse_int(args[i + 1]); ok && v >= 0 {
				g_warmup = v
			}
			i += 1
		} else if strings.has_prefix(arg, "--warmup=") || strings.has_prefix(arg, "-warmup:") {
			eq := strings.index_any(arg, "=:")
			if v, ok := strconv.parse_int(arg[eq + 1:]); ok && v >= 0 {
				g_warmup = v
			}
		} else if (arg == "--commit" || arg == "-commit") && i + 1 < len(args) {
			g_commit_sha = args[i + 1]
			i += 1
		} else if strings.has_prefix(arg, "--commit=") || strings.has_prefix(arg, "-commit:") {
			eq := strings.index_any(arg, "=:")
			g_commit_sha = arg[eq + 1:]
		} else if (arg == "--run-id" || arg == "-run-id") && i + 1 < len(args) {
			g_run_id = args[i + 1]
			i += 1
		} else if strings.has_prefix(arg, "--run-id=") || strings.has_prefix(arg, "-run-id:") {
			eq := strings.index_any(arg, "=:")
			g_run_id = arg[eq + 1:]
		} else if (arg == "--output" || arg == "-output") && i + 1 < len(args) {
			g_jsonl_path = args[i + 1]
			i += 1
		} else if (arg == "--history" || arg == "-history") && i + 1 < len(args) {
			g_history_path = args[i + 1]
			i += 1
		}
		i += 1
	}
}

sort_f64 :: proc(arr: []f64) {
	for i in 1 ..< len(arr) {
		key := arr[i]
		j := i - 1
		for j >= 0 && arr[j] > key {
			arr[j + 1] = arr[j]
			j -= 1
		}
		arr[j + 1] = key
	}
}

calc_percentile :: proc(sorted: []f64, p: f64) -> f64 {
	n := len(sorted)
	if n == 0 do return 0.0
	if n == 1 do return sorted[0]
	pos := p * f64(n - 1)
	lo := int(pos)
	hi := min(lo + 1, n - 1)
	frac := pos - f64(lo)
	return sorted[lo] + frac * (sorted[hi] - sorted[lo])
}

print_header :: proc() {
	fmt.println("=================================================================================================================================================================")
	fmt.printf(
		"  Commit: %s | Lang: odin | Runs: %d (Warmup: %d) | Run ID: %s\n",
		g_commit_sha,
		g_runs,
		g_warmup,
		g_run_id,
	)
	fmt.println("=================================================================================================================================================================")
	fmt.printf(
		"%-48s | %8s | %10s | %10s | %16s | %6s | %8s | %8s | %13s | %11s\n",
		"Benchmark",
		"Ops",
		"Total (ms)",
		"Med (p50)",
		"Mean ± StdDev",
		"CV%",
		"IQR ns",
		"p95 ns",
		"Min..Max ns",
		"ops/sec",
	)
	fmt.println("-----------------------------------------------------------------------------------------------------------------------------------------------------------------")
}

print_result :: proc(r: Bench_Result) {
	if g_is_warmup {
		return
	}
	slot := g_group_slot
	g_group_slot += 1
	if slot >= MAX_GROUP_BENCHES {
		return
	}
	acc := &g_group_accum[slot]
	if acc.count == 0 {
		acc.name = r.name
		acc.ops = r.ops
		acc.bytes_used = r.bytes_used
	} else if r.bytes_used > 0 {
		acc.bytes_used = r.bytes_used
	}
	if acc.count < MAX_RUNS {
		total_ns := f64(max(time.duration_nanoseconds(r.elapsed), 0))
		acc.samples_ms[acc.count] = total_ns / 1e6
		acc.samples_ns[acc.count] = total_ns / f64(max(r.ops, 1))
		acc.count += 1
	}
}

flush_group_results :: proc() {
	sorted_ns: [MAX_RUNS]f64
	sorted_ms: [MAX_RUNS]f64

	for slot in 0 ..< g_group_count {
		acc := &g_group_accum[slot]
		n := acc.count
		if n == 0 do continue

		g_bench_rank += 1
		for i in 0 ..< n {
			sorted_ns[i] = acc.samples_ns[i]
			sorted_ms[i] = acc.samples_ms[i]
		}
		sort_f64(sorted_ns[:n])
		sort_f64(sorted_ms[:n])

		min_ns := sorted_ns[0]
		max_ns := sorted_ns[n - 1]
		median_ns := calc_percentile(sorted_ns[:n], 0.50)
		median_ms := calc_percentile(sorted_ms[:n], 0.50)
		q1_ns := calc_percentile(sorted_ns[:n], 0.25)
		q3_ns := calc_percentile(sorted_ns[:n], 0.75)
		iqr_ns := q3_ns - q1_ns
		p95_ns := calc_percentile(sorted_ns[:n], 0.95)
		p99_ns := calc_percentile(sorted_ns[:n], 0.99)

		sum_ns := 0.0
		for i in 0 ..< n {
			sum_ns += sorted_ns[i]
		}
		mean_ns := sum_ns / f64(n)

		var_sum := 0.0
		for i in 0 ..< n {
			d := sorted_ns[i] - mean_ns
			var_sum += d * d
		}
		variance_ns2 := var_sum / f64(max(n - 1, 1)) if n > 1 else 0.0
		stddev_ns := math.sqrt(variance_ns2)
		cv_pct := (stddev_ns / max(mean_ns, 1e-9)) * 100.0
		ops_per_sec := (f64(acc.ops) * 1e9) / max(median_ns * f64(max(acc.ops, 1)), 1.0)

		mean_sd_str := fmt.tprintf("%s ± %s", fmt.tprintf("%.0f", mean_ns), fmt.tprintf("%.1f", stddev_ns))
		cv_str := fmt.tprintf("%.1f%%", cv_pct)
		iqr_str := fmt.tprintf("%.1f", iqr_ns)
		p95_str := fmt.tprintf("%.0f", p95_ns)
		minmax_str := fmt.tprintf("%.0f..%.0f", min_ns, max_ns)

		if acc.bytes_used > 0 {
			kb := f64(acc.bytes_used) / 1024.0
			fmt.printf(
				"%-48s | % 8d | % 10.2f | % 10.0f | %16s | %6s | %8s | %8s | %13s | % 11.0f  (%.1f KB)\n",
				acc.name,
				acc.ops,
				median_ms,
				median_ns,
				mean_sd_str,
				cv_str,
				iqr_str,
				p95_str,
				minmax_str,
				ops_per_sec,
				kb,
			)
		} else {
			fmt.printf(
				"%-48s | % 8d | % 10.2f | % 10.0f | %16s | %6s | %8s | %8s | %13s | % 11.0f\n",
				acc.name,
				acc.ops,
				median_ms,
				median_ns,
				mean_sd_str,
				cv_str,
				iqr_str,
				p95_str,
				minmax_str,
				ops_per_sec,
			)
		}

		if g_jsonl_file != nil || g_history_file != nil {
			sb := strings.builder_make(context.temp_allocator)
			strings.write_byte(&sb, '[')
			for i in 0 ..< n {
				if i > 0 do strings.write_byte(&sb, ',')
				fmt.sbprintf(&sb, "%.0f", acc.samples_ns[i])
			}
			strings.write_byte(&sb, ']')
			samples_json := strings.to_string(sb)

			line := fmt.tprintf(
				"{{\"rank\":%d,\"lang\":\"odin\",\"commit\":\"%s\",\"run_id\":\"%s\",\"name\":\"%s\",\"ops\":%d,\"runs\":%d,\"warmup\":%d,\"total_ms\":%.3f,\"ns_per_op\":%.0f,\"mean_ns\":%.2f,\"median_ns\":%.2f,\"stddev_ns\":%.2f,\"variance_ns2\":%.2f,\"cv_pct\":%.2f,\"min_ns\":%.0f,\"max_ns\":%.0f,\"iqr_ns\":%.2f,\"p95_ns\":%.0f,\"p99_ns\":%.0f,\"ops_per_sec\":%.0f,\"bytes_used\":%d,\"samples_ns\":%s}}\n",
				g_bench_rank,
				g_commit_sha,
				g_run_id,
				acc.name,
				acc.ops,
				n,
				g_warmup,
				median_ms,
				median_ns,
				mean_ns,
				median_ns,
				stddev_ns,
				variance_ns2,
				cv_pct,
				min_ns,
				max_ns,
				iqr_ns,
				p95_ns,
				p99_ns,
				ops_per_sec,
				acc.bytes_used,
				samples_json,
			)
			if g_jsonl_file != nil {
				_, _ = os.write_string(g_jsonl_file, line)
			}
			if g_history_file != nil {
				_, _ = os.write_string(g_history_file, line)
			}
		}
	}
	free_all(context.temp_allocator)
}

run_group :: proc(group_fn: proc(int), param: int) {
	g_is_warmup = true
	for _ in 0 ..< g_warmup {
		g_group_slot = 0
		group_fn(param)
		free_all(context.temp_allocator)
	}

	g_is_warmup = false
	for i in 0 ..< MAX_GROUP_BENCHES {
		g_group_accum[i] = Bench_Accum{}
	}
	g_group_count = 0
	runs := clamp(g_runs, 1, MAX_RUNS)
	for run_idx in 0 ..< runs {
		g_group_slot = 0
		group_fn(param)
		if g_group_slot > g_group_count {
			g_group_count = g_group_slot
		}
		free_all(context.temp_allocator)
	}
	flush_group_results()
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

	sz_before_sset, _ := xitdb.database_committed_size(&db)
	t9 := time.now()
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, sset_put_cb, &sctx)
	elapsed_sset_put := time.since(t9)
	sz_after_sset, _ := xitdb.database_committed_size(&db)

	print_result(Bench_Result{
		name       = "Sorted_Set (B+Tree) key-only put (1 tx)",
		ops        = n,
		elapsed    = elapsed_sset_put,
		bytes_used = sz_after_sset - sz_before_sset,
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

// ----------------------------------------------------------------------------
// 6. 5-Layer DSL & Datalog Engine Benchmarks
// ----------------------------------------------------------------------------

Bench_User_DTO :: struct {
	username: string   `xitdb:"username"`,
	dept:     string   `xitdb:"dept"`,
	age:      u64      `xitdb:"age"`,
	bio:      string   `xitdb:"bio,tag=md"`,
	todos:    []string `xitdb:"[[todos]]"`,
	tags:     []string `xitdb:"^tags"`,
}

run_dsl_benchmarks :: proc(_: int = 0) {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	context.allocator = context.temp_allocator
	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	N :: 500

	// 1. Layer 2: Datomic-style Tx commits with secondary index maintenance (`tx_index_on`)
	{
		t0 := time.now()
		tx := xitdb.tx_init(&db, base_moment = nil, track_changes = false, allocator = context.temp_allocator)
		xitdb.tx_doc(&tx, "Benchmark seed 500 indexed users and cyclic dependency graph")
		xitdb.tx_index_on(&tx, "users", "username", "username->id")

		for i in 0 ..< N {
			id_str := fmt.tprintf("u%04d", i)
			uname := fmt.tprintf("user_%04d", i)
			dept := "eng" if (i % 3 != 0) else "design"
			age := u64(22 + (i % 40))

			_ = xitdb.tx_put(&tx, fmt.tprintf(".users[%q].username", id_str), uname)
			_ = xitdb.tx_put(&tx, fmt.tprintf(".users[%q].dept", id_str), dept)
			_ = xitdb.tx_put(&tx, fmt.tprintf(".users[%q].age", id_str), age)
			if i % 10 == 0 {
				_ = xitdb.tx_put(&tx, fmt.tprintf(".users[%q].roles%%\"suspended\"", id_str), "suspended")
			}
		}

		// Seed a 32-node cyclic package graph for transitive `reach`
		for i in 0 ..< 32 {
			src := fmt.tprintf("pkg_%02d", i)
			dst := fmt.tprintf("pkg_%02d", (i + 1) % 32)
			_ = xitdb.tx_put(&tx, fmt.tprintf(".deps[%q]^%q", src, dst), dst)
		}

		rep0, err := xitdb.tx_commit(&tx)
		assert(err == nil)
		print_result(Bench_Result{
			name       = "DSL Layer 2: Tx Commit + Secondary Index (N=500)",
			ops        = N,
			elapsed    = time.since(t0),
			bytes_used = rep0.commit_size,
		})
		free_all(context.temp_allocator)
	}

	// 2. Layer 1: String Path Selector point lookups (`@-1.users["u0250"].age`)
	{
		t0 := time.now()
		for i in 0 ..< N {
			sel := fmt.tprintf("@-1.users[\"u%04d\"].age", i)
			val, err := xitdb.get_uint(&db, sel)
			assert(err == nil && val >= 22)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 1: String Selector get_uint (N=500)",
			ops     = N,
			elapsed = time.since(t0),
		})
		free_all(context.temp_allocator)
	}

	// 3. Layer 3: Odin Struct Reflection `marshal` & `unmarshal` + Datomic `pull`
	{
		dto := Bench_User_DTO{
			username = "alice",
			dept     = "eng",
			age      = 31,
			bio      = "# Principal Systems Engineer",
			todos    = {"Design DSL", "Optimize B+Tree pushdown", "Write benchmarks"},
			tags     = {"odin", "xitdb", "datalog"},
		}
		M :: 200
		t0 := time.now()
		tx := xitdb.tx_init(&db, base_moment = -1, allocator = context.temp_allocator)
		Swap_Ctx :: struct {
			dto:   ^Bench_User_DTO,
			count: int,
		}
		sctx := Swap_Ctx{dto = &dto, count = M}
		xitdb.tx_with_cursor(&tx, proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
			sc := (^Swap_Ctx)(user_data)
			m := xitdb.write_hash_map_init(cursor^) or_return
			profiles_cur := xitdb.hash_map_put_cursor(&m, "profiles") or_return
			profiles := xitdb.write_hash_map_init(profiles_cur) or_return
			for i in 0 ..< sc.count {
				k := fmt.tprintf("p%03d", i)
				pcur := xitdb.hash_map_put_cursor(&profiles, k) or_return
				xitdb.marshal(&pcur, sc.dto^) or_return
			}
			return nil
		}, &sctx)
		rep, err := xitdb.tx_commit(&tx)
		assert(err == nil)
		print_result(Bench_Result{
			name    = "DSL Layer 3: Struct marshal (N=200)",
			ops     = M,
			elapsed = time.since(t0),
		})

		t1 := time.now()
		for i in 0 ..< M {
			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
			out, u_err := xitdb.unmarshal(Bench_User_DTO, pcur_maybe.?, context.temp_allocator)
			assert(u_err == nil && out.age == 31)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 3: Struct unmarshal (N=200)",
			ops     = M,
			elapsed = time.since(t1),
		})

		t2 := time.now()
		for i in 0 ..< M {
			pcur_maybe, _ := xitdb.select_cursor(&db, fmt.tprintf("@-1.profiles[\"p%03d\"]", i))
			pv, p_err := xitdb.pull(pcur_maybe.?, "{username, age, todos[0..2]}", context.temp_allocator)
			assert(p_err == nil && pv != nil)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 3: Datomic pull projection (N=200)",
			ops     = M,
			elapsed = time.since(t2),
		})
		_ = rep
		free_all(context.temp_allocator)
	}

	// 4. Layer 4: O(1) Subtree-Skipping `diff_moments` & `history_of`
	{
		// Commit a small delta in Moment 2 (mutating 1 key out of 500 users + 200 profiles)
		tx := xitdb.tx_init(&db, base_moment = -1, allocator = context.temp_allocator)
		_ = xitdb.tx_put(&tx, ".users[\"u0042\"].age", u64(99))
		_, _ = xitdb.tx_commit(&tx)

		Q :: 200
		t0 := time.now()
		for _ in 0 ..< Q {
			diffs, d_err := xitdb.diff_moments(&db, 1, 2, false, context.temp_allocator)
			assert(d_err == nil && len(diffs) == 1)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 4: diff_moments (1 of 700 mutated)",
			ops     = Q,
			elapsed = time.since(t0),
		})

		t1 := time.now()
		for _ in 0 ..< Q {
			hist, h_err := xitdb.history_of(&db, ".users[\"u0042\"].age", context.temp_allocator)
			assert(h_err == nil && len(hist) == 2)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 4: history_of lineage (3 moments)",
			ops     = Q,
			elapsed = time.since(t1),
		})
		free_all(context.temp_allocator)
	}

	// 5. Layer 5: Datalog B+Tree Prefix Pushdown, Grouped Aggregations & Cycle-Safe `reach`
	{
		Q :: 100
		t0 := time.now()
		for _ in 0 ..< Q {
			// Prefix "user_025" matches 10 users ("user_0250".."user_0259") via B+Tree seek
			res, err := xitdb.query_datalog(&db, `
				find ?id, ?name, ?age
				where
					$username->id[?name] = ?id
					starts_with(?name, "user_025")
					.users[?id].age = ?age
					not .users[?id].roles%"suspended"
			`, -1, context.temp_allocator)
			assert(err == nil && len(res.rows) == 9)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 5: Datalog B+Tree Prefix + Join",
			ops     = Q,
			elapsed = time.since(t0),
		})
		free_all(context.temp_allocator)

		A :: 25
		t1 := time.now()
		for _ in 0 ..< A {
			res, err := xitdb.query_datalog(&db, `
				find ?dept, count(?id), min(?age), max(?age), sum(?age)
				where
					.users[?id].dept = ?dept
					.users[?id].age = ?age
			`, -1, context.temp_allocator)
			assert(err == nil && len(res.rows) == 2)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 5: Datalog Grouped Aggs (N=500)",
			ops     = A,
			elapsed = time.since(t1),
		})
		free_all(context.temp_allocator)

		R :: 100
		t2 := time.now()
		for _ in 0 ..< R {
			res, err := xitdb.query_datalog(&db, `
				find ?target, ?hops
				where
					?start == "pkg_00"
					reach(?start, ?target, ?hops, .deps[?start]^?target)
			`, -1, context.temp_allocator)
			assert(err == nil && len(res.rows) == 32)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 5: Datalog Cycle-Safe reach (32-ring)",
			ops     = R,
			elapsed = time.since(t2),
		})
		free_all(context.temp_allocator)
	}

	// 6. Layer 2 & 3/4: Secondary Index Stale-Key Eviction (`tx_index_on` update) & Cyclic Graph `pull` + `diff`
	{
		U :: 200
		t0 := time.now()
		tx_evict := xitdb.tx_init(&db, base_moment = -1, track_changes = false, allocator = context.temp_allocator)
		xitdb.tx_index_on(&tx_evict, "users", "username", "username->id")
		for i in 0 ..< U {
			id_str := fmt.tprintf("u%04d", i)
			new_uname := fmt.tprintf("renamed_%04d", i)
			_ = xitdb.tx_put(&tx_evict, fmt.tprintf(".users[%q].username", id_str), new_uname)
		}
		_, ev_err := xitdb.tx_commit(&tx_evict)
		assert(ev_err == nil)
		print_result(Bench_Result{
			name    = "DSL Layer 2: Secondary Index Evict+Update (N=200)",
			ops     = U,
			elapsed = time.since(t0),
		})
		free_all(context.temp_allocator)

		// Seed cyclic Slot references in a dedicated moment and benchmark cycle-safe `pull` + `diff_moments`
		tx_cyc := xitdb.tx_init(&db, base_moment = -1, track_changes = true, allocator = context.temp_allocator)
		xitdb.tx_with_cursor(&tx_cyc, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
			moment := xitdb.write_hash_map_init(cursor^) or_return
			m_slot := xitdb.hash_map_slot(moment.read_hash_map) or_return
			xitdb.hash_map_put(&moment, "self", m_slot) or_return

			ma_cur := xitdb.hash_map_put_cursor(&moment, "node_a") or_return
			ma := xitdb.write_hash_map_init(ma_cur) or_return
			xitdb.hash_map_put(&ma, "label", "A") or_return

			mb_cur := xitdb.hash_map_put_cursor(&moment, "node_b") or_return
			mb := xitdb.write_hash_map_init(mb_cur) or_return
			xitdb.hash_map_put(&mb, "label", "B") or_return

			mb_slot := xitdb.hash_map_slot(mb.read_hash_map) or_return
			xitdb.hash_map_put(&ma, "peer", mb_slot) or_return
			ma_slot := xitdb.hash_map_slot(ma.read_hash_map) or_return
			xitdb.hash_map_put(&mb, "peer", ma_slot) or_return
			return nil
		})
		rep_cyc, cyc_err := xitdb.tx_commit(&tx_cyc)
		assert(cyc_err == nil)

		tx_cyc2 := xitdb.tx_init(&db, base_moment = -1, track_changes = false, allocator = context.temp_allocator)
		_ = xitdb.tx_put(&tx_cyc2, ".node_a.label", "A_v2")
		rep_cyc2, cyc2_err := xitdb.tx_commit(&tx_cyc2)
		assert(cyc2_err == nil)

		C :: 200
		node_a_cur, _ := xitdb.select_cursor(&db, "@-1.node_a")
		t1 := time.now()
		for _ in 0 ..< C {
			pv, p_err := xitdb.pull(node_a_cur.?, "*", context.temp_allocator)
			assert(p_err == nil && pv != nil)
			diffs, d_err := xitdb.diff_moments(&db, rep_cyc.moment_index, rep_cyc2.moment_index, false, context.temp_allocator)
			assert(d_err == nil && len(diffs) == 1)
		}
		print_result(Bench_Result{
			name    = "DSL Layer 3/4: Cyclic Graph pull + diff (N=200)",
			ops     = C,
			elapsed = time.since(t1),
		})
		free_all(context.temp_allocator)
	}
}

main :: proc() {
	parse_cli_args()

	primary_flags := os.File_Flags{.Write, .Create, .Append} if g_append_primary else os.File_Flags{.Write, .Create, .Trunc}
	if f, err := os.open(g_jsonl_path, primary_flags, os.Permissions_Read_Write_All); err == nil {
		g_jsonl_file = f
	}
	defer if g_jsonl_file != nil {
		os.close(g_jsonl_file)
	}

	if g_save_history && g_history_path != g_jsonl_path {
		if hf, err := os.open(g_history_path, {.Write, .Create, .Append}, os.Permissions_Read_Write_All); err == nil {
			g_history_file = hf
		}
	}
	defer if g_history_file != nil {
		os.close(g_history_file)
	}

	print_header()
	run_group(bench_hamt, 2_000)
	run_group(bench_lists, 2_000)
	run_group(bench_sorted_map, 2_000)
	run_group(bench_compaction_and_replication, 200)
	run_group(bench_hashers_and_byte_streams, 2_000)
	run_group(bench_backends, 500)
	run_group(run_dsl_benchmarks, 0)
	fmt.println("============================================================================================================================================")
}
