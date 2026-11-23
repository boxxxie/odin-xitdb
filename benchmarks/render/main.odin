package bench_render

import "core:encoding/json"
import "core:fmt"
import "core:math"
import vmem "core:mem/virtual"
import "core:os"
import "core:strings"

DEFAULT_HUGI_BIN :: "/home/pauli/.local/bin/hugi"
DEFAULT_DB_PATH :: "benchmarks/history.hugidb"
RENDERS_DIR :: "benchmarks/renders"
README_PATH :: "benchmarks/README.md"

PALETTE :: [7]string{
	"#58a6ff",
	"#3fb950",
	"#f78166",
	"#d2a8ff",
	"#ffa657",
	"#79c0ff",
	"#ff7b72",
}

Group_Meta :: struct {
	key:   string,
	title: string,
	desc:  string,
}

GROUP_META :: [7]Group_Meta{
	{"hamt", "`hamt` — Copy-on-Write 32-Way HAMT `Hash_Map`, `Counted_Hash_Map` & `Counted_Hash_Set`", "Bulk puts, point lookups (with SHA-1 and pre-hashed digest), CoW branched moments, remove & branch shortening, and unordered scans."},
	{"lists", "`lists` — `Array_List` (32-Way Radix Trie) & `Linked_Array_List` (B-Tree)", "Append, random `get`, iterator scans, middle insert/remove, concatenation/slicing, and index-seek pagination."},
	{"sorted_map", "`sorted_map` — Persistent B+Tree `Sorted_Map` & `Sorted_Set`", "Out-of-order puts, key lookup, `O(log N)` rank/index select, ordered scans, lower-bound pagination, and rebalancing removal."},
	{"compaction", "`compaction` — History Compaction & Incremental Delta Replication", "Genesis-to-200 replication, incremental moment deltas, in-memory & file offset-map compaction, heterogeneous DAG dedup, and post-compaction resync."},
	{"hashers", "`hashers` — Cryptographic Hashers, Inline Bytes, Streams & Nested Paths", "SHA-1 vs SHA-256 HAMT puts, inline short bytes vs external slot reads, 1 MB cursor streams, and 4-level nested path reads/writes."},
	{"backends", "`backends` — `Core_Memory`, `Core_Buffered_File` & `Core_File` Commits", "Backend commit throughput, mid-tx `database_freeze` CoW clones, rollback truncation, and trailer checksum verification."},
	{"dsl", "`dsl` — 5-Layer Path Selector, Reflection, Diff & Datalog Engine", "String selectors, secondary indexes (`tx_index_on`), struct `marshal`/`unmarshal`/`pull`, structural `diff_moments`, and cycle-safe `query_datalog`."},
}

Hugi_Record :: struct {
	commit:             string,
	lang:               string,
	group_name:         string,
	name:               string,
	full_name:          string,
	samples:            int,
	p50_ns:             f64,
	p95_ns:             f64,
	cv_pct:             f64,
	ops_per_sec:        f64,
	mb_per_sec:         f64,
	allocs_per_op:      f64,
	alloc_bytes_per_op: f64,
}

Svg_Tick_View :: struct {
	pos:      string,
	text_pos: string,
	label:    string,
}

Bar_View :: struct {
	label:    string,
	text_y:   string,
	rect_y:   string,
	width:    string,
	val_x:    string,
	val_y:    string,
	val_text: string,
	color:    string,
}

Bar_Chart_View :: struct {
	title:       string,
	subtitle:    string,
	width:       int,
	height:      int,
	pad_l:       int,
	pad_t:       int,
	pw:          int,
	ph:          int,
	plot_bottom: int,
	label_x:     int,
	x_label_y:   int,
	x_ticks:     []Svg_Tick_View,
	bars:        []Bar_View,
}

Three_Bar_Group_View :: struct {
	label:       string,
	label_y:     string,
	odin_y:      string,
	odin_w:      string,
	odin_val_x:  string,
	odin_text_y: string,
	odin_val:    string,
	lua_y:       string,
	lua_w:       string,
	lua_val_x:   string,
	lua_text_y:  string,
	lua_val:     string,
	zig_y:       string,
	zig_w:       string,
	zig_val_x:   string,
	zig_text_y:  string,
	zig_val:     string,
	badge_y:     string,
	speedup:     string,
}

Three_Bar_Chart_View :: struct {
	title:       string,
	subtitle:    string,
	odin_color:  string,
	lua_color:   string,
	zig_color:   string,
	width:       int,
	height:      int,
	pad_l:       int,
	pad_t:       int,
	pw:          int,
	ph:          int,
	plot_bottom: int,
	label_x:     int,
	x_label_y:   int,
	badge_x:     int,
	x_ticks:     []Svg_Tick_View,
	groups:      []Three_Bar_Group_View,
}

Report_Row_View :: struct {
	name:   string,
	median: string,
	p95:    string,
	ops:    string,
	cv:     string,
	vs_zig: string,
	vs_lua: string,
	allocs: string,
}

Report_Group_View :: struct {
	title:    string,
	desc:     string,
	has_desc: bool,
	count:    int,
	rows:     []Report_Row_View,
}

Suite_Report_View :: struct {
	commit:            string,
	total_benchmarks:  int,
	lua_count:         int,
	zig_count:         int,
	total_samples_str: string,
	group_count:       int,
	groups:            []Report_Group_View,
}

Bar_Spec :: struct {
	full_name: string,
	label:     string,
	color:     string,
}

Three_Spec :: struct {
	name:  string,
	label: string,
}

three_bar_chart_tmpl := compiled("templates/three_bar_chart.runa.twig", Three_Bar_Chart_View)
bar_chart_tmpl := compiled("templates/bar_chart.runa.twig", Bar_Chart_View)
suite_report_tmpl := compiled("templates/suite_report.runa.twig", Suite_Report_View)

@(require_results)
fmt_commas_u64 :: proc(val: u64, allocator := context.allocator) -> string {
	buf: [32]byte
	pos := len(buf)
	v := val
	digits := 0
	if v == 0 {
		pos -= 1
		buf[pos] = '0'
	} else {
		for v > 0 {
			if digits > 0 && digits % 3 == 0 {
				pos -= 1
				buf[pos] = ','
			}
			pos -= 1
			buf[pos] = byte('0' + (v % 10))
			v /= 10
			digits += 1
		}
	}
	return strings.clone(string(buf[pos:]), allocator)
}

@(require_results)
fmt_ns :: proc(ns: f64, allocator := context.allocator) -> string {
	if ns < 1.0 {
		return fmt.aprintf("%.2f ps", ns * 1000.0, allocator = allocator)
	}
	if ns < 1_000.0 {
		return fmt.aprintf("%.2f ns", ns, allocator = allocator)
	}
	if ns < 1_000_000.0 {
		return fmt.aprintf("%.2f us", ns / 1_000.0, allocator = allocator)
	}
	if ns < 1_000_000_000.0 {
		return fmt.aprintf("%.2f ms", ns / 1_000_000.0, allocator = allocator)
	}
	return fmt.aprintf("%.3f s", ns / 1_000_000_000.0, allocator = allocator)
}

@(require_results)
fmt_axis_ns :: proc(ns: f64, allocator := context.allocator) -> string {
	if ns <= 0 {
		return strings.clone("0", allocator)
	}
	raw := fmt_ns(ns, context.temp_allocator)
	if s, ok := strings.replace_all(raw, ".000 ", " ", context.temp_allocator); ok {
		raw = s
	}
	if s, ok := strings.replace_all(raw, ".00 ", " ", context.temp_allocator); ok {
		raw = s
	}
	return strings.clone(raw, allocator)
}

@(require_results)
fmt_bytes :: proc(b: f64, allocator := context.allocator) -> string {
	if b < 1024.0 {
		return fmt.aprintf("%.0f B", b, allocator = allocator)
	}
	if b < 1024.0 * 1024.0 {
		return fmt.aprintf("%.2f KiB", b / 1024.0, allocator = allocator)
	}
	return fmt.aprintf("%.2f MiB", b / (1024.0 * 1024.0), allocator = allocator)
}

@(require_results)
fmt_tp_or_ops :: proc(rec: Hugi_Record, allocator := context.allocator) -> string {
	if rec.mb_per_sec >= 1024.0 {
		return fmt.aprintf("%.2f GB/s", rec.mb_per_sec / 1024.0, allocator = allocator)
	}
	if rec.mb_per_sec > 0 {
		return fmt.aprintf("%.1f MB/s", rec.mb_per_sec, allocator = allocator)
	}
	if rec.ops_per_sec >= 1_000_000_000.0 {
		return fmt.aprintf("%.2fB/s", rec.ops_per_sec / 1_000_000_000.0, allocator = allocator)
	}
	if rec.ops_per_sec >= 1_000_000.0 {
		return fmt.aprintf("%.2fM/s", rec.ops_per_sec / 1_000_000.0, allocator = allocator)
	}
	if rec.ops_per_sec >= 1_000.0 {
		return fmt.aprintf("%.1fK/s", rec.ops_per_sec / 1_000.0, allocator = allocator)
	}
	return fmt.aprintf("%.0f/s", rec.ops_per_sec, allocator = allocator)
}

@(require_results)
exec_hugi :: proc(args: []string, allocator := context.allocator) -> (stdout: []byte, ok: bool) {
	hugi_bin := DEFAULT_HUGI_BIN if os.exists(DEFAULT_HUGI_BIN) else "hugi"
	cmd := make([dynamic]string, 0, len(args) + 1, context.temp_allocator)
	append(&cmd, hugi_bin)
	for a in args {
		append(&cmd, a)
	}
	state, out, stderr, exec_err := os.process_exec(os.Process_Desc{command = cmd[:]}, allocator)
	if exec_err != nil && hugi_bin != "hugi" {
		delete(out, allocator)
		delete(stderr, allocator)
		cmd[0] = "hugi"
		state, out, stderr, exec_err = os.process_exec(os.Process_Desc{command = cmd[:]}, allocator)
	}
	defer delete(stderr, allocator)
	if exec_err != nil || !state.success {
		delete(out, allocator)
		return nil, false
	}
	return out, true
}

@(require_results)
latest_commit_from_hugi :: proc(db_path: string, allocator := context.allocator) -> (string, bool) {
	out, ok := exec_hugi({"history", "--db", db_path, "--limit", "1"}, context.temp_allocator)
	if !ok {
		return "", false
	}
	for line in strings.split_lines(string(out), context.temp_allocator) {
		t := strings.trim_space(line)
		if len(t) == 0 || strings.has_prefix(t, "Commit") || strings.has_prefix(t, "-") {
			continue
		}
		if idx := strings.index_byte(t, '|'); idx > 0 {
			return strings.clone(strings.trim_space(t[:idx]), allocator), true
		}
	}
	return "", false
}

@(require_results)
render_three_bar_svg :: proc(
	title: string,
	subtitle: string,
	specs: []Three_Spec,
	odin_map: map[string]Hugi_Record,
	lua_map: map[string]Hugi_Record,
	zig_map: map[string]Hugi_Record,
	out_path: string,
	allocator := context.allocator,
) -> bool {
	width, pad_l, pad_r, pad_t, pad_b, row_h := 980, 260, 260, 92, 42, 48
	Matched :: struct {
		spec: Three_Spec,
		odin: Hugi_Record,
		lua:  Hugi_Record,
		zig:  Hugi_Record,
	}
	matched := make([dynamic]Matched, 0, len(specs), allocator)
	min_v, max_v := max(f64), 0.0
	for sp in specs {
		or, ok_o := odin_map[sp.name]
		lr, ok_l := lua_map[sp.name]
		zr, ok_z := zig_map[sp.name]
		if ok_o && ok_l && ok_z && or.p50_ns > 0 && lr.p50_ns > 0 && zr.p50_ns > 0 {
			append(&matched, Matched{sp, or, lr, zr})
			min_v = min(min_v, min(or.p50_ns, min(lr.p50_ns, zr.p50_ns)))
			max_v = max(max_v, max(or.p50_ns, max(lr.p50_ns, zr.p50_ns)))
		}
	}
	if len(matched) == 0 || max_v <= 0 {
		return false
	}

	ph := len(matched) * row_h + 14
	height := pad_t + ph + pad_b
	pw := width - pad_l - pad_r
	lo := int(math.floor(math.log10(min_v)))
	hi := int(math.ceil(math.log10(max_v)))
	if lo == hi { hi += 1 }

	x_ticks := make([]Svg_Tick_View, hi - lo + 1, allocator)
	for e := lo; e <= hi; e += 1 {
		t := f64(e - lo) / f64(hi - lo)
		x_ticks[e - lo] = Svg_Tick_View{
			pos   = fmt.aprintf("%.1f", f64(pad_l) + t * f64(pw), allocator = allocator),
			label = fmt_axis_ns(math.pow10(f64(e)), allocator),
		}
	}

	groups := make([]Three_Bar_Group_View, len(matched), allocator)
	for item, idx in matched {
		ry := f64(pad_t + 8 + idx * row_h)
		to := (math.log10(item.odin.p50_ns) - f64(lo)) / f64(hi - lo)
		tl := (math.log10(item.lua.p50_ns) - f64(lo)) / f64(hi - lo)
		tz := (math.log10(item.zig.p50_ns) - f64(lo)) / f64(hi - lo)
		wo := max(4.0, to * f64(pw))
		wl := max(4.0, tl * f64(pw))
		wz := max(4.0, tz * f64(pw))
		ratio := item.zig.p50_ns / item.odin.p50_ns

		groups[idx] = Three_Bar_Group_View{
			label       = item.spec.label,
			label_y     = fmt.aprintf("%.1f", ry + 23.0, allocator = allocator),
			odin_y      = fmt.aprintf("%.1f", ry + 2.0, allocator = allocator),
			odin_w      = fmt.aprintf("%.1f", wo, allocator = allocator),
			odin_val_x  = fmt.aprintf("%.1f", f64(pad_l) + wo + 8.0, allocator = allocator),
			odin_text_y = fmt.aprintf("%.1f", ry + 10.5, allocator = allocator),
			odin_val    = fmt_ns(item.odin.p50_ns, allocator),
			lua_y       = fmt.aprintf("%.1f", ry + 14.5, allocator = allocator),
			lua_w       = fmt.aprintf("%.1f", wl, allocator = allocator),
			lua_val_x   = fmt.aprintf("%.1f", f64(pad_l) + wl + 8.0, allocator = allocator),
			lua_text_y  = fmt.aprintf("%.1f", ry + 23.0, allocator = allocator),
			lua_val     = fmt_ns(item.lua.p50_ns, allocator),
			zig_y       = fmt.aprintf("%.1f", ry + 27.0, allocator = allocator),
			zig_w       = fmt.aprintf("%.1f", wz, allocator = allocator),
			zig_val_x   = fmt.aprintf("%.1f", f64(pad_l) + wz + 8.0, allocator = allocator),
			zig_text_y  = fmt.aprintf("%.1f", ry + 35.5, allocator = allocator),
			zig_val     = fmt_ns(item.zig.p50_ns, allocator),
			badge_y     = fmt.aprintf("%.1f", ry + 23.0, allocator = allocator),
			speedup     = fmt.aprintf("%.2fx vs Zig", ratio, allocator = allocator),
		}
	}

	view := Three_Bar_Chart_View{
		title       = title,
		subtitle    = subtitle,
		odin_color  = PALETTE[1],
		lua_color   = PALETTE[0],
		zig_color   = PALETTE[2],
		width       = width,
		height      = height,
		pad_l       = pad_l,
		pad_t       = pad_t,
		pw          = pw,
		ph          = ph,
		plot_bottom = pad_t + ph,
		label_x     = pad_l - 10,
		x_label_y   = pad_t + ph + 18,
		badge_x     = width - 18,
		x_ticks     = x_ticks,
		groups      = groups,
	}
	sb := strings.builder_make(0, three_bar_chart_tmpl.approx_bytes, context.temp_allocator)
	if _, err := three_bar_chart_tmpl.with(strings.to_writer(&sb), view); err != nil {
		return false
	}
	return os.write_entire_file(out_path, transmute([]byte)strings.to_string(sb)) == nil
}

@(require_results)
render_bar_svg :: proc(
	title: string,
	subtitle: string,
	specs: []Bar_Spec,
	by_name: map[string]Hugi_Record,
	out_path: string,
	allocator := context.allocator,
) -> bool {
	width, pad_l, pad_r, pad_t, pad_b, row_h := 960, 290, 210, 68, 42, 34
	matched := make([dynamic]struct{ spec: Bar_Spec, rec: Hugi_Record }, 0, len(specs), allocator)
	min_v, max_v := max(f64), 0.0
	for sp in specs {
		if rec, ok := by_name[sp.full_name]; ok && rec.p50_ns > 0 {
			append(&matched, struct{ spec: Bar_Spec, rec: Hugi_Record }{sp, rec})
			min_v = min(min_v, rec.p50_ns)
			max_v = max(max_v, rec.p50_ns)
		}
	}
	if len(matched) == 0 || max_v <= 0 {
		return false
	}

	ph := len(matched) * row_h + 12
	height := pad_t + ph + pad_b
	pw := width - pad_l - pad_r
	lo := int(math.floor(math.log10(min_v)))
	hi := int(math.ceil(math.log10(max_v)))
	if lo == hi { hi += 1 }

	x_ticks := make([]Svg_Tick_View, hi - lo + 1, allocator)
	for e := lo; e <= hi; e += 1 {
		t := f64(e - lo) / f64(hi - lo)
		x_ticks[e - lo] = Svg_Tick_View{
			pos   = fmt.aprintf("%.1f", f64(pad_l) + t * f64(pw), allocator = allocator),
			label = fmt_axis_ns(math.pow10(f64(e)), allocator),
		}
	}

	bars := make([]Bar_View, len(matched), allocator)
	for item, idx in matched {
		ry := pad_t + 10 + idx * row_h
		t := (math.log10(item.rec.p50_ns) - f64(lo)) / f64(hi - lo)
		w_bar := max(4.0, t * f64(pw))
		dur := fmt_ns(item.rec.p50_ns, context.temp_allocator)
		tp := fmt_tp_or_ops(item.rec, context.temp_allocator)
		bars[idx] = Bar_View{
			label    = item.spec.label,
			text_y   = fmt.aprintf("%.1f", f64(ry) + 16.0, allocator = allocator),
			rect_y   = fmt.aprintf("%.1f", f64(ry) + 3.0, allocator = allocator),
			width    = fmt.aprintf("%.1f", w_bar, allocator = allocator),
			val_x    = fmt.aprintf("%.1f", f64(pad_l) + w_bar + 8.0, allocator = allocator),
			val_y    = fmt.aprintf("%.1f", f64(ry) + 17.0, allocator = allocator),
			val_text = fmt.aprintf("%s (%s)", dur, tp, allocator = allocator),
			color    = item.spec.color,
		}
	}

	view := Bar_Chart_View{
		title       = title,
		subtitle    = subtitle,
		width       = width,
		height      = height,
		pad_l       = pad_l,
		pad_t       = pad_t,
		pw          = pw,
		ph          = ph,
		plot_bottom = pad_t + ph,
		label_x     = pad_l - 10,
		x_label_y   = pad_t + ph + 18,
		x_ticks     = x_ticks,
		bars        = bars,
	}
	sb := strings.builder_make(0, bar_chart_tmpl.approx_bytes, context.temp_allocator)
	if _, err := bar_chart_tmpl.with(strings.to_writer(&sb), view); err != nil {
		return false
	}
	return os.write_entire_file(out_path, transmute([]byte)strings.to_string(sb)) == nil
}

@(require_results)
build_suite_report_view :: proc(
	odin_recs: []Hugi_Record,
	lua_recs: []Hugi_Record,
	zig_recs: []Hugi_Record,
	commit: string,
	allocator := context.allocator,
) -> Suite_Report_View {
	lua_map := make(map[string]Hugi_Record, len(lua_recs), context.temp_allocator)
	for rec in lua_recs { lua_map[rec.name] = rec }
	zig_map := make(map[string]Hugi_Record, len(zig_recs), context.temp_allocator)
	for rec in zig_recs { zig_map[rec.name] = rec }

	grouped := make(map[string][dynamic]Hugi_Record, context.temp_allocator)
	extra := make([dynamic]string, context.temp_allocator)
	total_samples := u64(0)
	for rec in odin_recs {
		total_samples += u64(max(rec.samples, 0))
		g := rec.group_name if len(rec.group_name) > 0 else "default"
		if g not_in grouped {
			grouped[g] = make([dynamic]Hugi_Record, context.temp_allocator)
			known := false
			for gm in GROUP_META { if gm.key == g { known = true; break } }
			if !known { append(&extra, g) }
		}
		append(&grouped[g], rec)
	}
	ordered := make([dynamic]string, 0, len(grouped), context.temp_allocator)
	for gm in GROUP_META { if gm.key in grouped { append(&ordered, gm.key) } }
	for eg in extra { append(&ordered, eg) }

	groups := make([]Report_Group_View, len(ordered), allocator)
	for gkey, gi in ordered {
		recs := grouped[gkey][:]
		title, desc := gkey, ""
		for gm in GROUP_META { if gm.key == gkey { title, desc = gm.title, gm.desc; break } }
		rows := make([]Report_Row_View, len(recs), allocator)
		for rec, ri in recs {
			alloc_str: string
			if rec.allocs_per_op > 0 || rec.alloc_bytes_per_op > 0 {
				alloc_str = fmt.aprintf("%.1f (%s)", rec.allocs_per_op, fmt_bytes(rec.alloc_bytes_per_op, context.temp_allocator), allocator = allocator)
			} else {
				alloc_str = strings.clone("**0**", allocator)
			}
			vs_zig := strings.clone("—", allocator)
			if zr, ok := zig_map[rec.name]; ok && zr.p50_ns > 0 && rec.p50_ns > 0 {
				vs_zig = fmt.aprintf("**%.2fx** (%s)", zr.p50_ns / rec.p50_ns, fmt_ns(zr.p50_ns, context.temp_allocator), allocator = allocator)
			}
			vs_lua := strings.clone("—", allocator)
			if lr, ok := lua_map[rec.name]; ok && lr.p50_ns > 0 && rec.p50_ns > 0 {
				vs_lua = fmt.aprintf("**%.2fx** (%s)", lr.p50_ns / rec.p50_ns, fmt_ns(lr.p50_ns, context.temp_allocator), allocator = allocator)
			}
			rows[ri] = Report_Row_View{
				name   = strings.clone(rec.name, allocator),
				median = fmt_ns(rec.p50_ns, allocator),
				p95    = fmt_ns(rec.p95_ns, allocator),
				ops    = fmt_tp_or_ops(rec, allocator),
				cv     = fmt.aprintf("%.1f%%", rec.cv_pct, allocator = allocator),
				vs_zig = vs_zig,
				vs_lua = vs_lua,
				allocs = alloc_str,
			}
		}
		groups[gi] = Report_Group_View{
			title    = strings.clone(title, allocator),
			desc     = strings.clone(desc, allocator),
			has_desc = len(desc) > 0,
			count    = len(recs),
			rows     = rows,
		}
	}
	return Suite_Report_View{
		commit            = strings.clone(commit, allocator),
		total_benchmarks  = len(odin_recs),
		lua_count         = len(lua_recs),
		zig_count         = len(zig_recs),
		total_samples_str = fmt_commas_u64(total_samples, allocator),
		group_count       = len(groups),
		groups            = groups,
	}
}

@(require_results)
render_all :: proc(db_path: string, commit_arg: string, allocator := context.allocator) -> bool {
	if !os.exists(db_path) {
		return false
	}
	arena: vmem.Arena
	if vmem.arena_init_growing(&arena) != nil { return false }
	defer vmem.arena_destroy(&arena)
	arena_alloc := vmem.arena_allocator(&arena)

	commit := commit_arg
	if len(commit) == 0 {
		c, ok := latest_commit_from_hugi(db_path, arena_alloc)
		if !ok { return false }
		commit = c
	}

	raw_odin, ok_odin := exec_hugi({"export", "--db", db_path, "--commit", commit, "--lang", "odin", "--format", "json", "--out", "-"}, arena_alloc)
	if !ok_odin { return false }
	odin_recs: []Hugi_Record
	if json.unmarshal(raw_odin, &odin_recs, allocator = arena_alloc) != nil || len(odin_recs) == 0 {
		return false
	}

	raw_lua, ok_lua := exec_hugi({"export", "--db", db_path, "--commit", commit, "--lang", "lua", "--format", "json", "--out", "-"}, arena_alloc)
	if !ok_lua { return false }
	lua_recs: []Hugi_Record
	if json.unmarshal(raw_lua, &lua_recs, allocator = arena_alloc) != nil || len(lua_recs) == 0 {
		return false
	}

	raw_zig, ok_zig := exec_hugi({"export", "--db", db_path, "--commit", commit, "--lang", "zig", "--format", "json", "--out", "-"}, arena_alloc)
	if !ok_zig { return false }
	zig_recs: []Hugi_Record
	if json.unmarshal(raw_zig, &zig_recs, allocator = arena_alloc) != nil || len(zig_recs) == 0 {
		return false
	}

	if !os.exists(RENDERS_DIR) && os.make_directory(RENDERS_DIR) != nil {
		return false
	}

	odin_map := make(map[string]Hugi_Record, len(odin_recs), arena_alloc)
	for rec in odin_recs { odin_map[rec.name] = rec }
	lua_map := make(map[string]Hugi_Record, len(lua_recs), arena_alloc)
	for rec in lua_recs { lua_map[rec.name] = rec }
	zig_map := make(map[string]Hugi_Record, len(zig_recs), arena_alloc)
	for rec in zig_recs { zig_map[rec.name] = rec }

	sub := fmt.tprintf("Commit %s · Core_Memory · -o:speed -microarch:native", commit)

	t1 := [?]Three_Spec{
		{"HAMT Hash_Map point lookup (with SHA-1)", "HAMT point lookup (SHA-1)"},
		{"HAMT Hash_Map lookup (pre-hashed digest)", "HAMT lookup (pre-hashed)"},
		{"HAMT Hash_Map bulk put (1 tx)", "HAMT bulk put (1 tx)"},
		{"HAMT Hash_Map unordered iterator scan", "HAMT unordered scan"},
		{"Array_List (Radix Trie) random get", "Array_List random get"},
		{"Array_List (Radix Trie) append", "Array_List append"},
		{"Linked_Array_List (B-Tree) append", "Linked_Array_List append"},
		{"Sorted_Map (B+Tree) key lookup", "Sorted_Map key lookup"},
		{"Sorted_Map (B+Tree) out-of-order put", "Sorted_Map out-of-order put"},
		{"Stream: Cursor_Reader (256 x 4KB = 1MB)", "Cursor_Reader 1MB stream"},
		{"Backend: Core_Memory commits", "Core_Memory commits"},
	}
	if !render_three_bar_svg("Core Collections: Odin vs LuaJIT 2.1 vs Reference Zig", sub, t1[:], odin_map, lua_map, zig_map, fmt.tprintf("%s/odin_vs_zig_vs_lua_core.svg", RENDERS_DIR), arena_alloc) {
		return false
	}

	s2 := [?]Bar_Spec{
		{"Stream: Cursor_Reader random seek + 64B read", "Cursor_Reader seek + 64B read", PALETTE[1]},
		{"Bytes: Inline Short_Bytes read_bytes_buf", "Inline Short_Bytes read", PALETTE[1]},
		{"Bytes: External Bytes read_bytes_buf", "External Bytes read", PALETTE[1]},
		{"Array_List (Radix Trie) iterator scan", "Array_List iterator scan", PALETTE[5]},
		{"Linked_Array_List (B-Tree) iterator scan", "Linked_Array_List scan", PALETTE[5]},
		{"Sorted_Map (B+Tree) ordered scan", "Sorted_Map ordered scan", PALETTE[5]},
		{"Stream: Cursor_Writer random seek + 16B patch", "Cursor_Writer seek + 16B patch", PALETTE[0]},
		{"HAMT Hash_Map unordered iterator scan", "HAMT unordered scan", PALETTE[0]},
		{"Array_List (Radix Trie) random get", "Array_List random get", PALETTE[0]},
		{"HAMT Hash_Map lookup (pre-hashed digest)", "HAMT lookup (pre-hashed)", PALETTE[0]},
		{"HAMT Hash_Map point lookup (with SHA-1)", "HAMT lookup (SHA-1)", PALETTE[3]},
		{"Cursor: Full KV-pair scan (read_kv_pair)", "Cursor KV-pair scan", PALETTE[3]},
		{"Path: 4-level nested cursor_write_path", "4-level cursor_write_path", PALETTE[4]},
		{"Sorted_Map (B+Tree) rank query", "Sorted_Map rank query", PALETTE[4]},
		{"Sorted_Map (B+Tree) lower-bound page(10)", "Sorted_Map lower-bound page", PALETTE[2]},
	}
	if !render_bar_svg("Odin Sub-Microsecond Collection, Cursor & Stream Fast Paths", sub, s2[:], odin_map, fmt.tprintf("%s/odin_collection_latency.svg", RENDERS_DIR), arena_alloc) {
		return false
	}

	s3 := [?]Bar_Spec{
		{"DB: Re-open & trailer checksum verify", "DB re-open & checksum verify", PALETTE[1]},
		{"Replication (genesis -> 200 moments)", "Replication (0 -> 200 moments)", PALETTE[1]},
		{"Tx: Aborted transaction rollback truncate", "Tx abort rollback truncate", PALETTE[5]},
		{"DSL Layer 1: String Selector get_uint (N=500)", "DSL Layer 1 get_uint (N=500)", PALETTE[5]},
		{"Replication (incremental 1-moment delta)", "Replication (1-moment delta)", PALETTE[0]},
		{"Backend: Core_Memory commits", "Core_Memory commits", PALETTE[0]},
		{"DSL Layer 4: history_of lineage (3 moments)", "DSL history_of (3 moments)", PALETTE[0]},
		{"DSL Layer 3: Datomic pull projection (N=200)", "DSL Datomic pull (N=200)", PALETTE[0]},
		{"Compaction (Memory_Offset_Map, 200 -> 1)", "Compaction (Memory_Map, 200->1)", PALETTE[3]},
		{"DSL Layer 5: Datalog B+Tree Prefix + Join", "Datalog B+Tree Prefix + Join", PALETTE[3]},
		{"Backend: Core_Buffered_File commits", "Core_Buffered_File commits", PALETTE[4]},
		{"DSL Layer 5: Datalog Cycle-Safe reach (32-ring)", "Datalog reach (32-ring)", PALETTE[4]},
		{"Backend: Core_File (unbuffered) commits", "Core_File (unbuffered) commits", PALETTE[2]},
		{"DSL Layer 4: diff_moments (1 of 700 mutated)", "DSL diff_moments (1/700)", PALETTE[2]},
		{"DSL Layer 5: Datalog Grouped Aggs (N=500)", "Datalog Grouped Aggs (N=500)", PALETTE[6]},
	}
	if !render_bar_svg("Compaction, Replication, Backends & 5-Layer DSL / Datalog", sub, s3[:], odin_map, fmt.tprintf("%s/compaction_backends_and_dsl.svg", RENDERS_DIR), arena_alloc) {
		return false
	}

	rep := build_suite_report_view(odin_recs, lua_recs, zig_recs, commit, arena_alloc)
	sb := strings.builder_make(0, suite_report_tmpl.approx_bytes, allocator)
	defer strings.builder_destroy(&sb)
	if _, err := suite_report_tmpl.with(strings.to_writer(&sb), rep); err != nil { return false }
	if os.write_entire_file(README_PATH, transmute([]byte)strings.to_string(sb)) != nil { return false }

	fmt.printfln("bench_render: rendered 3 SVGs and %d Odin (+%d LuaJIT, +%d Zig) rows -> %s", rep.total_benchmarks, rep.lua_count, rep.zig_count, README_PATH)
	free_all(context.temp_allocator)
	return true
}

main :: proc() {
	commit := ""
	args := os.args[1:] if len(os.args) > 1 else nil
	for i := 0; i < len(args); i += 1 {
		if args[i] == "--commit" && i + 1 < len(args) {
			commit = args[i + 1]
			i += 1
		}
	}
	if !render_all(DEFAULT_DB_PATH, commit, context.allocator) {
		os.exit(1)
	}
}
