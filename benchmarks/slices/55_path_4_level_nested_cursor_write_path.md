# #55. `Path: 4-level nested cursor_write_path` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1777-L1830`)](../bench_xitdb.odin#L1777-L1830) · [Zig Harness (`bench_xitdb.zig#L1903-L1949`)](../bench_xitdb.zig#L1903-L1949)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **230** | 230.8 ± 1.9 | 0.8% | 233.4 | 4,347,826 | - | **6.73x Odin** (`z = 80.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,548 | 1,565.2 ± 37.0 | 2.4% | 1,612.2 | 645,995 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L285-L340`](../../xitdb/cursor.odin#L285-L340)):** On `#48` & `#50` (**4.33x–6.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs 3 separate unbuffered reads (`value_size`, `value`, and a redundant `seekTo` + `readSliceAll` for the 2-byte `format_tag` that already immediately follows `value`).
- **Zero-Vtable Stream Reads & Pre-Sized Writes (`#51–#53` — 3.5x–5.8x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L527-L629) and [`Cursor_Reader`](../../xitdb/cursor.odin#L430-L523) read/append slices directly against `Core_Memory.buf`, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches and grows `Writer.Allocating` geometrically from 0 to 1 MB.
- **Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 6.73x–8.74x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Zig's time here is dominated by `readBTreeNode` (18 `takeInt`s at level 3) and `readSortedNode` + linear scan (at level 4).

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).
- **Return `.fixed(slice)` in `Cursor.reader()` when `comptime db_kind == .memory` ([`lib.zig#L3370-L3385`](../../reference/xitdb-zig/src/lib.zig#L3370-L3385)):** Setting `interface = .fixed(slice)` and `pos = size` makes `Cursor.Reader.seekTo` (`lib.zig#L2971-L2981`) and `readSliceAll` pure pointer arithmetic with zero vtable calls!
- **Apply Guides 01–03:** Fixing `CoreMemory.Reader`, `BTreeNode` batch I/O, and `SortedMap` binary search automatically resolves the `6.7x–8.7x` gap on `#55–#56` without changing `readSlotPointer`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1777-L1830`](../bench_xitdb.odin#L1777-L1830))

```odin
1777 | 	// 5d. Deeply Nested Multi-Part Atomic Path Traversal (`cursor_write_path` & `cursor_read_path` across 4 nested collections)
1778 | 	{
1779 | 		core: xitdb.Core = xitdb.core_memory_init()
1780 | 		defer xitdb.core_destroy(&core)
1781 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1782 | 
1783 | 		path_ops := 500
1784 | 		h_root := xitdb.database_digest_string(&db, "tenant", context.temp_allocator)
1785 | 		h_leaf := xitdb.database_digest_string(&db, "metric", context.temp_allocator)
1786 | 
1787 | 		Deep_Ctx :: struct {
1788 | 			ops:    int,
1789 | 			h_root: []u8,
1790 | 			h_leaf: []u8,
1791 | 		}
1792 | 		dctx := Deep_Ctx{ops = path_ops, h_root = h_root, h_leaf = h_leaf}
1793 | 
1794 | 		deep_write_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1795 | 			c := (^Deep_Ctx)(user_data)
1796 | 			// Initialize 4-level hierarchy: Hash_Map -> Array_List -> Linked_Array_List -> Sorted_Map
1797 | 			_, err := xitdb.cursor_write_path(cursor, []xitdb.Path_Part{
1798 | 				xitdb.Hash_Map_Init{counted = false, set = false},
1799 | 				xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = c.h_root}},
1800 | 				xitdb.Array_List_Init{},
1801 | 				xitdb.Array_List_Append{},
1802 | 				xitdb.Linked_Array_List_Init{},
1803 | 				xitdb.Linked_Array_List_Append{},
1804 | 				xitdb.Sorted_Map_Init{set = false},
1805 | 			})
1806 | 			if err != nil do return err
1807 | 
1808 | 			skey := transmute([]u8)string("deep-sorted-key")
1809 | 			for i in 0 ..< c.ops {
1810 | 				_, err = xitdb.cursor_write_path(cursor, []xitdb.Path_Part{
1811 | 					xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = c.h_root}},
1812 | 					xitdb.Array_List_Get{index = 0},
1813 | 					xitdb.Linked_Array_List_Get{index = 0},
1814 | 					xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_Value{key = skey}},
1815 | 					xitdb.Write_Data{data = u64(i)},
1816 | 				})
1817 | 				if err != nil do return err
1818 | 			}
1819 | 			return nil
1820 | 		}
1821 | 
1822 | 		t_dw := time.now()
1823 | 		_ = xitdb.database_run_context(&db, deep_write_cb, &dctx)
1824 | 		elapsed_dw := time.since(t_dw)
1825 | 
1826 | 		print_result(Bench_Result{
1827 | 			name    = "Path: 4-level nested cursor_write_path",
1828 | 			ops     = path_ops,
1829 | 			elapsed = elapsed_dw,
1830 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1903-L1949`](../bench_xitdb.zig#L1903-L1949))

```zig
1903 |     // 5d. Deeply Nested Multi-Part Atomic Path Traversal (`cursor_write_path` & `cursor_read_path` across 4 nested collections)
1904 |     {
1905 |         var buffer = std.Io.Writer.Allocating.init(allocator);
1906 |         defer buffer.deinit();
1907 |         var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1908 | 
1909 |         const path_ops: usize = 500;
1910 |         const h_root = hashSha1("tenant");
1911 | 
1912 |         const DeepWriteCtx = struct {
1913 |             ops: usize,
1914 |             h_root: HashInt,
1915 | 
1916 |             pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
1917 |                 // Initialize 4-level hierarchy: Hash_Map -> Array_List -> Linked_Array_List -> Sorted_Map
1918 |                 _ = try cursor.writePath(void, &.{
1919 |                     .{ .hash_map_init = .{ .counted = false, .set = false } },
1920 |                     .{ .hash_map_get = .{ .value = self.h_root } },
1921 |                     .array_list_init,
1922 |                     .array_list_append,
1923 |                     .linked_array_list_init,
1924 |                     .linked_array_list_append,
1925 |                     .{ .sorted_map_init = .{ .set = false } },
1926 |                 });
1927 | 
1928 |                 const skey = "deep-sorted-key";
1929 |                 for (0..self.ops) |i| {
1930 |                     _ = try cursor.writePath(void, &.{
1931 |                         .{ .hash_map_get = .{ .value = self.h_root } },
1932 |                         .{ .array_list_get = 0 },
1933 |                         .{ .linked_array_list_get = 0 },
1934 |                         .{ .sorted_map_get = .{ .value = skey } },
1935 |                         .{ .write = .{ .uint = @intCast(i) } },
1936 |                     });
1937 |                 }
1938 |             }
1939 |         };
1940 | 
1941 |         const t_dw = std.Io.Clock.awake.now(io);
1942 |         try db.runContext(DeepWriteCtx{ .ops = path_ops, .h_root = h_root });
1943 |         const elapsed_dw = t_dw.untilNow(io, .awake).nanoseconds;
1944 | 
1945 |         try printResult(stdout, .{
1946 |             .name = "Path: 4-level nested cursor_write_path",
1947 |             .ops = path_ops,
1948 |             .elapsed_ns = elapsed_dw,
1949 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |
| `readSlotPointer.write` | 66 | `PathPart` switch arms: `.write` and `.ctx` | [`lib.zig#L1525-L1590`](../../reference/xitdb-zig/src/lib.zig#L1525-L1590) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`61` procedures across `4` files · `1245` LOC) (Active `_exec_path_part` arms: `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/database.odin` | `database_digest_string` | **Entry Point** (`depth 0`) | 3 | [`xitdb/database.odin#L255-L257`](../../xitdb/database.odin#L255-L257) |
| `xitdb/cursor.odin` | `cursor_write_path` | **Entry Point** (`depth 0`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `cursor_write_path`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_digest` | `depth 1` (from `database_digest_string`) | 7 | [`xitdb/database.odin#L247-L253`](../../xitdb/database.odin#L247-L253) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 1` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 1` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `init_tag` | `depth 1` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 1` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 1` (from `cursor_write_path`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 1` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 1` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `core_write_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 2` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_read_slot` | `depth 2` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 2` (from `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 2` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 2` (from `read_slot_pointer`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 2` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 2` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 2` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 3` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 3` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
