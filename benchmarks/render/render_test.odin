package bench_render

import "core:strings"
import "core:testing"

@(test)
test_render_report_and_three_bar :: proc(t: ^testing.T) {
	odin_recs := [?]Hugi_Record{
		{commit = "69fb307", lang = "odin", group_name = "hamt", name = "HAMT Hash_Map lookup (pre-hashed digest)", full_name = "HAMT Hash_Map lookup (pre-hashed digest)", samples = 5, p50_ns = 61.05, p95_ns = 64.0, cv_pct = 2.0, ops_per_sec = 16_380_000, allocs_per_op = 0, alloc_bytes_per_op = 0},
	}
	lua_recs := [?]Hugi_Record{
		{commit = "69fb307", lang = "lua", group_name = "hamt", name = "HAMT Hash_Map lookup (pre-hashed digest)", full_name = "HAMT Hash_Map lookup (pre-hashed digest)", samples = 5, p50_ns = 114.61, p95_ns = 120.0, cv_pct = 2.0, ops_per_sec = 8_725_000, allocs_per_op = 0, alloc_bytes_per_op = 0},
	}
	zig_recs := [?]Hugi_Record{
		{commit = "69fb307", lang = "zig", group_name = "", name = "HAMT Hash_Map lookup (pre-hashed digest)", full_name = "HAMT Hash_Map lookup (pre-hashed digest)", samples = 5, p50_ns = 321.00, p95_ns = 330.0, cv_pct = 1.5, ops_per_sec = 3_115_000, allocs_per_op = 0, alloc_bytes_per_op = 0},
	}

	rep := build_suite_report_view(odin_recs[:], lua_recs[:], zig_recs[:], "69fb307", context.temp_allocator)
	testing.expect_value(t, rep.total_benchmarks, 1)
	testing.expect_value(t, rep.lua_count, 1)
	testing.expect_value(t, rep.zig_count, 1)
	testing.expect(t, strings.contains(rep.groups[0].rows[0].vs_zig, "5.26x"), "computes Zig speedup ratio")

	sb := strings.builder_make(0, 1024, context.temp_allocator)
	_, err := suite_report_tmpl.with(strings.to_writer(&sb), rep)
	testing.expect(t, err == nil, "suite_report template renders without error")
	out := strings.to_string(sb)
	testing.expect(t, strings.contains(out, "<!-- BEGIN_BENCHMARK_TABLE -->"), "has benchmark table marker")
	free_all(context.temp_allocator)
}
