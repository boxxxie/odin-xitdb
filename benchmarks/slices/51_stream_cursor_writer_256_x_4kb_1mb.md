# #51. `Stream: Cursor_Writer (256 x 4KB = 1MB)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1670-L1707`)](../bench_xitdb.odin#L1670-L1707) · [Zig Harness (`bench_xitdb.zig#L1801-L1836`)](../bench_xitdb.zig#L1801-L1836)

- **Touched Library Scope:** **66** procedures across **4** `xitdb/*.odin` files (**1346** lines of library code)
- **Direct Benchmark Entry Points:** `core_memory_init`, `core_destroy`, `database_init`, `sha1_hasher`, `cursor_writer`, `cursor_writer_write`, `cursor_writer_finish`, `database_run_context`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1670-L1707`)

```odin
1670 | 	// 5c. Streaming `Cursor_Writer` & `Cursor_Reader` (1 MB payload in 4 KB chunks)
1671 | 	{
1672 | 		core: xitdb.Core = xitdb.core_memory_init()
1673 | 		defer xitdb.core_destroy(&core)
1674 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1675 | 
1676 | 		chunks_count := 256 // 256 * 4 KB = 1 MB
1677 | 		Stream_Ctx :: struct {
1678 | 			chunks_count: int,
1679 | 			blob_rc:      xitdb.Read_Cursor,
1680 | 		}
1681 | 		sctx := Stream_Ctx{chunks_count = chunks_count}
1682 | 
1683 | 		stream_write_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1684 | 			c := (^Stream_Ctx)(user_data)
1685 | 			w := xitdb.cursor_writer(cursor) or_return
1686 | 			chunk: [4096]u8
1687 | 			for i in 0 ..< c.chunks_count {
1688 | 				chunk[0] = u8(i)
1689 | 				_, err := xitdb.cursor_writer_write(&w, chunk[:])
1690 | 				if err != nil do return err
1691 | 			}
1692 | 			xitdb.cursor_writer_finish(&w) or_return
1693 | 			c.blob_rc = cursor.read_cursor
1694 | 			return nil
1695 | 		}
1696 | 
1697 | 		t_sw := time.now()
1698 | 		_ = xitdb.database_run_context(&db, stream_write_cb, &sctx)
1699 | 		elapsed_sw := time.since(t_sw)
1700 | 		sz_sw, _ := xitdb.database_committed_size(&db)
1701 | 
1702 | 		print_result(Bench_Result{
1703 | 			name       = "Stream: Cursor_Writer (256 x 4KB = 1MB)",
1704 | 			ops        = chunks_count,
1705 | 			elapsed    = elapsed_sw,
1706 | 			bytes_used = sz_sw,
1707 | 		})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1801-L1836</code>)</strong></summary>

```zig
1801 |     // 5c. Streaming `Cursor_Writer` & `Cursor_Reader` (1 MB payload in 4 KB chunks)
1802 |     {
1803 |         var buffer = std.Io.Writer.Allocating.init(allocator);
1804 |         defer buffer.deinit();
1805 |         var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1806 | 
1807 |         const chunks_count: usize = 256; // 256 * 4 KB = 1 MB
1808 |         var blob_rc: DBSha1.Cursor(.read_only) = undefined;
1809 | 
1810 |         const StreamWriteCtx = struct {
1811 |             chunks_count: usize,
1812 |             blob_rc_out: *DBSha1.Cursor(.read_only),
1813 | 
1814 |             pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
1815 |                 var w = try cursor.writer(&.{});
1816 |                 var chunk: [4096]u8 = @splat(0);
1817 |                 for (0..self.chunks_count) |i| {
1818 |                     chunk[0] = @intCast(i & 0xFF);
1819 |                     try w.interface.writeAll(&chunk);
1820 |                 }
1821 |                 try w.finish();
1822 |                 self.blob_rc_out.* = cursor.readOnly();
1823 |             }
1824 |         };
1825 | 
1826 |         const t_sw = std.Io.Clock.awake.now(io);
1827 |         try db.runContext(StreamWriteCtx{ .chunks_count = chunks_count, .blob_rc_out = &blob_rc });
1828 |         const elapsed_sw = t_sw.untilNow(io, .awake).nanoseconds;
1829 |         const sz_sw = try db.committedSize();
1830 | 
1831 |         try printResult(stdout, .{
1832 |             .name = "Stream: Cursor_Writer (256 x 4KB = 1MB)",
1833 |             .ops = chunks_count,
1834 |             .elapsed_ns = elapsed_sw,
1835 |             .bytes_used = sz_sw,
1836 |         });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/cursor.odin` | `cursor_writer` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L536-L555`](../../xitdb/cursor.odin#L536-L555) |
| `xitdb/cursor.odin` | `cursor_writer_write` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L571-L590`](../../xitdb/cursor.odin#L571-L590) |
| `xitdb/cursor.odin` | `cursor_writer_finish` | **Entry Point** (`depth 0`) | 30 | [`xitdb/cursor.odin#L600-L629`](../../xitdb/cursor.odin#L600-L629) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `cursor_writer`, `cursor_writer_write`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `cursor_writer`, `cursor_writer_write`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `cursor_writer_write`, `cursor_writer_finish`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `cursor_writer_finish`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 1` (from `cursor_writer`, `cursor_writer_check_writable`, `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 1` (from `cursor_writer`, `cursor_check_writable`, `cursor_write_path`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/core.odin` | `core_write_long` | `depth 1` (from `cursor_writer`, `cursor_writer_finish`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/cursor.odin` | `cursor_writer_check_writable` | `depth 1` (from `cursor_writer_write`, `cursor_writer_finish`) | 13 | [`xitdb/cursor.odin#L557-L569`](../../xitdb/cursor.odin#L557-L569) |
| `xitdb/types.odin` | `slot_with_full` | `depth 1` (from `cursor_writer_finish`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/core.odin` | `core_write_slot` | `depth 1` (from `cursor_writer_finish`, `read_slot_pointer`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 1` (from `cursor_writer_finish`, `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `database_run_context`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `core_write_slot`, `root_trailer_to_bytes`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 2` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_write_i64` | `depth 2` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 3` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Stream: Cursor_Writer (256 x 4KB = 1MB)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/core.odin` (16 procedures · 376 lines: [`L42–L48`](../../xitdb/core.odin#L42-L48), [`L102–L123`](../../xitdb/core.odin#L102-L123), [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L238–L285`](../../xitdb/core.odin#L238-L285), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437), [`L502–L507`](../../xitdb/core.odin#L502-L507), [`L534–L550`](../../xitdb/core.odin#L534-L550), [`L552–L575`](../../xitdb/core.odin#L552-L575), [`L577–L581`](../../xitdb/core.odin#L577-L581), [`L583–L600`](../../xitdb/core.odin#L583-L600))

#### [`core_memory_init`](../../xitdb/core.odin#L42-L48) — `ENTRY POINT` (`L42–L48`)

```odin
  42 | core_memory_init :: proc(allocator := context.allocator) -> Core {
  43 | 	return Core_Memory{
  44 | 		buf       = make([dynamic]u8, 0, 1024, allocator),
  45 | 		pos       = 0,
  46 | 		allocator = allocator,
  47 | 	}
  48 | }
```

#### [`core_destroy`](../../xitdb/core.odin#L102-L123) — `ENTRY POINT` (`L102–L123`)

```odin
 102 | core_destroy :: proc(c: ^Core, close_file := false) -> Error {
 103 | 	switch &v in c {
 104 | 	case Core_Memory:
 105 | 		delete(v.buf)
 106 | 		v.buf = nil
 107 | 		v.pos = 0
 108 | 	case Core_File:
 109 | 		if close_file && v.file != nil {
 110 | 			os.close(v.file) or_return
 111 | 			v.file = nil
 112 | 		}
 113 | 	case Core_Buffered_File:
 114 | 		_ = _buffered_flush(&v)  // <== [calls _buffered_flush]
 115 | 		delete(v.memory.buf)
 116 | 		v.memory.buf = nil
 117 | 		if close_file && v.file.file != nil {
 118 | 			os.close(v.file.file) or_return
 119 | 			v.file.file = nil
 120 | 		}
 121 | 	}
 122 | 	return nil
 123 | }
```

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 2` (`L125–L142`)

```odin
 125 | @(private)
 126 | _buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
 127 | 	cached_len := bf.file_len
 128 | 	bf.file_len = nil
 129 | 	os.seek(bf.file.file, pos, .Start) or_return
 130 | 	written := 0
 131 | 	for written < len(data) {
 132 | 		n := os.write(bf.file.file, data[written:]) or_return
 133 | 		if n == 0 {
 134 | 			return io.Error.Short_Write
 135 | 		}
 136 | 		written += n
 137 | 	}
 138 | 	if cl, ok := cached_len.?; ok {
 139 | 		bf.file_len = max(cl, pos + i64(len(data)))
 140 | 	}
 141 | 	return nil
 142 | }
```

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 1` (`L144–L151`)

```odin
 144 | @(private)
 145 | _buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
 146 | 	if len(bf.memory.buf) > bf.flushed_len {
 147 | 		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return  // <== [calls _buffered_write_to_file]
 148 | 		bf.flushed_len = len(bf.memory.buf)
 149 | 	}
 150 | 	return nil
 151 | }
```

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 1` (`L153–L174`)

```odin
 153 | core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
 154 | 	switch &v in c {
 155 | 	case Core_Memory:
 156 | 		return i64(len(v.buf)), nil
 157 | 	case Core_File:
 158 | 		return os.file_size(v.file)
 159 | 	case Core_Buffered_File:
 160 | 		flen: i64
 161 | 		if fl, ok := v.file_len.?; ok {
 162 | 			flen = fl
 163 | 		} else {
 164 | 			flen = os.file_size(v.file.file) or_return
 165 | 			v.file_len = flen
 166 | 		}
 167 | 		buf_size := i64(len(v.memory.buf))
 168 | 		if buf_size == 0 {
 169 | 			return flen, nil
 170 | 		}
 171 | 		return max(v.memory_pos + buf_size, flen), nil
 172 | 	}
 173 | 	return 0, .Invalid_Database
 174 | }
```

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 1` (`L176–L192`)

```odin
 176 | core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
 177 | 	if pos < 0 {
 178 | 		return .Expected_Unsigned_Long
 179 | 	}
 180 | 	switch &v in c {
 181 | 	case Core_Memory:
 182 | 		v.pos = pos
 183 | 		return nil
 184 | 	case Core_File:
 185 | 		os.seek(v.file, pos, .Start) or_return
 186 | 		return nil
 187 | 	case Core_Buffered_File:
 188 | 		v.pos = pos
 189 | 		return nil
 190 | 	}
 191 | 	return .Invalid_Database
 192 | }
```

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 1` (`L219–L236`)

```odin
 219 | core_sync :: proc(c: ^Core) -> Error {
 220 | 	switch &v in c {
 221 | 	case Core_Memory:
 222 | 		return nil
 223 | 	case Core_File:
 224 | 		if !v.fsync {
 225 | 			return nil
 226 | 		}
 227 | 		return os.sync(v.file)
 228 | 	case Core_Buffered_File:
 229 | 		_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 230 | 		if !v.file.fsync {
 231 | 			return nil
 232 | 		}
 233 | 		return os.sync(v.file.file)
 234 | 	}
 235 | 	return .Invalid_Database
 236 | }
```

#### [`core_set_length`](../../xitdb/core.odin#L238-L285) — `DEPTH 4` (`L238–L285`)

```odin
 238 | core_set_length :: proc(c: ^Core, new_len: i64) -> Error {
 239 | 	if new_len < 0 {
 240 | 		return .Expected_Unsigned_Long
 241 | 	}
 242 | 	switch &v in c {
 243 | 	case Core_Memory:
 244 | 		if new_len > i64(len(v.buf)) {
 245 | 			return Xitdb_Error.Invalid_Offset
 246 | 		}
 247 | 		resize(&v.buf, int(new_len))
 248 | 		if v.pos > new_len {
 249 | 			v.pos = new_len
 250 | 		}
 251 | 		return nil
 252 | 	case Core_File:
 253 | 		err := os.truncate(v.file, new_len)
 254 | 		if err != nil {
 255 | 			// Read-only file handles ignore setLength just like Zig/Go xitdb.
 256 | 			return nil
 257 | 		}
 258 | 		pos := os.seek(v.file, 0, .Current) or_return
 259 | 		if pos > new_len {
 260 | 			os.seek(v.file, new_len, .Start) or_return
 261 | 		}
 262 | 		return nil
 263 | 	case Core_Buffered_File:
 264 | 		buf_size := i64(len(v.memory.buf))
 265 | 		if new_len <= v.memory_pos {
 266 | 			clear(&v.memory.buf)
 267 | 			v.flushed_len = 0
 268 | 		} else if new_len < v.memory_pos + buf_size {
 269 | 			new_buf_len := int(new_len - v.memory_pos)
 270 | 			resize(&v.memory.buf, new_buf_len)
 271 | 			if v.flushed_len > new_buf_len {
 272 | 				v.flushed_len = new_buf_len
 273 | 			}
 274 | 		}
 275 | 		v.file_len = nil
 276 | 		if err := os.truncate(v.file.file, new_len); err == nil {
 277 | 			v.file_len = new_len
 278 | 		}
 279 | 		if v.pos > new_len {
 280 | 			v.pos = new_len
 281 | 		}
 282 | 		return nil
 283 | 	}
 284 | 	return .Invalid_Database
 285 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 4` (`L288–L323`)

```odin
 288 | core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
 289 | 	if len(p) == 0 {
 290 | 		return 0, nil
 291 | 	}
 292 | 	switch &v in c {
 293 | 	case Core_Memory:
 294 | 		if v.pos >= i64(len(v.buf)) {
 295 | 			return 0, io.Error.EOF
 296 | 		}
 297 | 		avail := int(i64(len(v.buf)) - v.pos)
 298 | 		to_read := min(len(p), avail)
 299 | 		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
 300 | 		v.pos += i64(to_read)
 301 | 		return to_read, nil
 302 | 	case Core_File:
 303 | 		return os.read(v.file, p)
 304 | 	case Core_Buffered_File:
 305 | 		buf_len := i64(len(v.memory.buf))
 306 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
 307 | 			mem_off := int(v.pos - v.memory_pos)
 308 | 			size := min(len(p), int(buf_len) - mem_off)
 309 | 			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
 310 | 			v.pos += i64(size)
 311 | 			return size, nil
 312 | 		}
 313 | 		os.seek(v.file.file, v.pos, .Start) or_return
 314 | 		max_size := len(p)
 315 | 		if buf_len > 0 && v.pos < v.memory_pos {
 316 | 			max_size = min(len(p), int(v.memory_pos - v.pos))
 317 | 		}
 318 | 		n, err := os.read(v.file.file, p[:max_size])
 319 | 		v.pos += i64(n)
 320 | 		return n, err
 321 | 	}
 322 | 	return 0, .Invalid_Database
 323 | }
```

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 3` (`L326–L359`)

```odin
 326 | core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
 327 | 	if len(p) == 0 {
 328 | 		return nil
 329 | 	}
 330 | 	#partial switch &v in c {
 331 | 	case Core_Memory:
 332 | 		end_pos := v.pos + i64(len(p))
 333 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 334 | 			v.pos = i64(len(v.buf))
 335 | 			return Xitdb_Error.Unexpected_EOF
 336 | 		}
 337 | 		copy(p, v.buf[int(v.pos):int(end_pos)])
 338 | 		v.pos = end_pos
 339 | 		return nil
 340 | 	}
 341 | 	total := 0
 342 | 	for total < len(p) {
 343 | 		n, err := core_read(c, p[total:])  // <== [calls core_read]
 344 | 		total += n
 345 | 		if err != nil {
 346 | 			if err == io.Error.EOF {
 347 | 				if total == len(p) {
 348 | 					return nil
 349 | 				}
 350 | 				return Xitdb_Error.Unexpected_EOF
 351 | 			}
 352 | 			return err
 353 | 		}
 354 | 		if n == 0 {
 355 | 			return Xitdb_Error.Unexpected_EOF
 356 | 		}
 357 | 	}
 358 | 	return nil
 359 | }
```

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 1` (`L362–L437`)

```odin
 362 | core_write_all :: proc(c: ^Core, p: []u8) -> Error {
 363 | 	if len(p) == 0 {
 364 | 		return nil
 365 | 	}
 366 | 	switch &v in c {
 367 | 	case Core_Memory:
 368 | 		old_size := int(len(v.buf))
 369 | 		end_pos := int(v.pos) + len(p)
 370 | 		if end_pos > old_size {
 371 | 			resize(&v.buf, end_pos)
 372 | 		}
 373 | 		copy(v.buf[int(v.pos):end_pos], p)
 374 | 		v.pos = i64(end_pos)
 375 | 		return nil
 376 | 	case Core_File:
 377 | 		written := 0
 378 | 		for written < len(p) {
 379 | 			n := os.write(v.file, p[written:]) or_return
 380 | 			if n == 0 {
 381 | 				return io.Error.Short_Write
 382 | 			}
 383 | 			written += n
 384 | 		}
 385 | 		return nil
 386 | 	case Core_Buffered_File:
 387 | 		n := i64(len(p))
 388 | 		if v.file_len == nil {
 389 | 			fl := os.file_size(v.file.file) or_return
 390 | 			v.file_len = fl
 391 | 		}
 392 | 		buf_size := i64(len(v.memory.buf))
 393 | 		if buf_size > 0 && v.pos + n <= v.memory_pos {
 394 | 			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
 395 | 			// write directly to the file without evicting the hot tail buffer.
 396 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 397 | 			v.pos += n
 398 | 			return nil
 399 | 		}
 400 | 		if buf_size == 0 {
 401 | 			v.memory_pos = v.pos
 402 | 			v.flushed_len = 0
 403 | 		} else if v.pos > v.memory_pos + buf_size ||
 404 | 		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
 405 | 			_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 406 | 			clear(&v.memory.buf)
 407 | 			v.flushed_len = 0
 408 | 			v.memory_pos = v.pos
 409 | 		}
 410 | 		buf_size = i64(len(v.memory.buf))
 411 | 		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
 412 | 			rel_off := int(v.pos - v.memory_pos)
 413 | 			end_off := rel_off + len(p)
 414 | 			if end_off > len(v.memory.buf) {
 415 | 				resize(&v.memory.buf, end_off)
 416 | 			}
 417 | 			copy(v.memory.buf[rel_off:end_off], p)
 418 | 			if rel_off < v.flushed_len {
 419 | 				if end_off <= v.flushed_len {
 420 | 					_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 421 | 				} else {
 422 | 					v.flushed_len = rel_off
 423 | 				}
 424 | 			}
 425 | 		} else {
 426 | 			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
 427 | 				_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 428 | 				clear(&v.memory.buf)
 429 | 				v.flushed_len = 0
 430 | 			}
 431 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 432 | 		}
 433 | 		v.pos += n
 434 | 		return nil
 435 | 	}
 436 | 	return .Invalid_Database
 437 | }
```

#### [`core_write_long`](../../xitdb/core.odin#L502-L507) — `DEPTH 1` (`L502–L507`)

```odin
 502 | core_write_long :: #force_inline proc(c: ^Core, v: i64) -> Error {
 503 | 	if v < 0 {
 504 | 		return Xitdb_Error.Expected_Unsigned_Long
 505 | 	}
 506 | 	return core_write_i64(c, v)  // <== [calls core_write_i64]
 507 | }
```

#### [`core_write_i64`](../../xitdb/core.odin#L534-L550) — `DEPTH 2` (`L534–L550`)

```odin
 534 | core_write_i64 :: #force_inline proc(c: ^Core, v: i64) -> Error {
 535 | 	#partial switch &m in c {
 536 | 	case Core_Memory:
 537 | 		old_size := len(m.buf)
 538 | 		pos := int(m.pos)
 539 | 		end_pos := pos + 8
 540 | 		if end_pos > old_size {
 541 | 			resize(&m.buf, end_pos)
 542 | 		}
 543 | 		endian.unchecked_put_u64be(m.buf[pos:end_pos], u64(v))
 544 | 		m.pos = i64(end_pos)
 545 | 		return nil
 546 | 	}
 547 | 	b: [8]u8 = ---
 548 | 	endian.unchecked_put_u64be(b[:], u64(v))
 549 | 	return core_write_all(c, b[:])  // <== [calls core_write_all]
 550 | }
```

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 3` (`L552–L575`)

```odin
 552 | core_read_slot_raw :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 553 | 	#partial switch &v in c {
 554 | 	case Core_Memory:
 555 | 		end_pos := v.pos + SLOT_LENGTH
 556 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 557 | 			v.pos = i64(len(v.buf))
 558 | 			return {}, Xitdb_Error.Unexpected_EOF
 559 | 		}
 560 | 		s = slot_from_slice_raw(v.buf[int(v.pos):int(end_pos)])  // <== [calls slot_from_slice_raw]
 561 | 		v.pos = end_pos
 562 | 		return s, nil
 563 | 	case Core_Buffered_File:
 564 | 		buf_len := i64(len(v.memory.buf))
 565 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + SLOT_LENGTH <= v.memory_pos + buf_len {
 566 | 			mem_off := int(v.pos - v.memory_pos)
 567 | 			s = slot_from_slice_raw(v.memory.buf[mem_off : mem_off + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
 568 | 			v.pos += SLOT_LENGTH
 569 | 			return s, nil
 570 | 		}
 571 | 	}
 572 | 	buf: [SLOT_LENGTH]u8 = ---
 573 | 	core_read_exact(c, buf[:]) or_return  // <== [calls core_read_exact]
 574 | 	return slot_from_bytes_raw(buf), nil  // <== [calls slot_from_bytes_raw]
 575 | }
```

#### [`core_read_slot`](../../xitdb/core.odin#L577-L581) — `DEPTH 3` (`L577–L581`)

```odin
 577 | core_read_slot :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 578 | 	s = core_read_slot_raw(c) or_return  // <== [calls core_read_slot_raw]
 579 | 	tag_validate(s.tag) or_return  // <== [calls tag_validate]
 580 | 	return s, nil
 581 | }
```

#### [`core_write_slot`](../../xitdb/core.odin#L583-L600) — `DEPTH 1` (`L583–L600`)

```odin
 583 | core_write_slot :: #force_inline proc(c: ^Core, s: Slot) -> Error {
 584 | 	#partial switch &v in c {
 585 | 	case Core_Memory:
 586 | 		old_size := len(v.buf)
 587 | 		pos := int(v.pos)
 588 | 		end_pos := pos + SLOT_LENGTH
 589 | 		if end_pos > old_size {
 590 | 			resize(&v.buf, end_pos)
 591 | 		}
 592 | 		full_bit := u8(0x80) if s.full else u8(0)
 593 | 		v.buf[pos] = full_bit | (u8(s.tag) & 0x7f)
 594 | 		endian.unchecked_put_u64be(v.buf[pos + 1 : end_pos], u64(s.value))
 595 | 		v.pos = i64(end_pos)
 596 | 		return nil
 597 | 	}
 598 | 	buf := slot_to_bytes(s)  // <== [calls slot_to_bytes]
 599 | 	return core_write_all(c, buf[:])  // <== [calls core_write_all]
 600 | }
```

### `xitdb/cursor.odin` (8 procedures · 172 lines: [`L28–L40`](../../xitdb/cursor.odin#L28-L40), [`L97–L105`](../../xitdb/cursor.odin#L97-L105), [`L107–L116`](../../xitdb/cursor.odin#L107-L116), [`L118–L174`](../../xitdb/cursor.odin#L118-L174), [`L536–L555`](../../xitdb/cursor.odin#L536-L555), [`L557–L569`](../../xitdb/cursor.odin#L557-L569), [`L571–L590`](../../xitdb/cursor.odin#L571-L590), [`L600–L629`](../../xitdb/cursor.odin#L600-L629))

#### [`new_write_cursor`](../../xitdb/cursor.odin#L28-L40) — `DEPTH 2` (`L28–L40`)

```odin
  28 | new_write_cursor :: proc(slot_ptr: Slot_Pointer, db: ^Database) -> Write_Cursor {
  29 | 	c := Write_Cursor{
  30 | 		read_cursor = Read_Cursor{
  31 | 			slot_ptr  = slot_ptr,
  32 | 			db        = db,
  33 | 			frozen_at = 0,
  34 | 		},
  35 | 	}
  36 | 	if slot_ptr.position != nil && !is_root(slot_ptr) {  // <== [calls is_root]
  37 | 		c.transaction = db.transaction
  38 | 	}
  39 | 	return c
  40 | }
```

#### [`cursor_check_writable`](../../xitdb/cursor.odin#L97-L105) — `DEPTH 1` (`L97–L105`)

```odin
  97 | cursor_check_writable :: proc(c: ^Write_Cursor) -> Error {
  98 | 	if c.transaction != nil && c.transaction != c.db.transaction {
  99 | 		return .Expired_Transaction
 100 | 	}
 101 | 	if !is_root(c.slot_ptr) && c.transaction == nil && c.db.tx_start == nil {  // <== [calls is_root]
 102 | 		return .Expected_Tx_Start
 103 | 	}
 104 | 	return database_check_frozen_slot(c.db, c.slot_ptr)  // <== [calls database_check_frozen_slot]
 105 | }
```

#### [`cursor_reload_slot`](../../xitdb/cursor.odin#L107-L116) — `DEPTH 2` (`L107–L116`)

```odin
 107 | cursor_reload_slot :: proc(c: ^Write_Cursor) -> Error {
 108 | 	if (c.transaction != nil || c.db.tx_start != nil) && !is_root(c.slot_ptr) {  // <== [calls is_root]
 109 | 		if pos, ok := c.slot_ptr.position.?; ok {
 110 | 			core_seek_to(c.db.core, pos) or_return  // <== [calls core_seek_to]
 111 | 			slot := core_read_slot(c.db.core) or_return  // <== [calls core_read_slot]
 112 | 			c.slot_ptr = slot_pointer_with_slot(c.slot_ptr, slot)  // <== [calls slot_pointer_with_slot]
 113 | 		}
 114 | 	}
 115 | 	return nil
 116 | }
```

#### [`cursor_write_path`](../../xitdb/cursor.odin#L118-L174) — `DEPTH 1` (`L118–L174`)

```odin
 118 | cursor_write_path :: proc(c: ^Write_Cursor, path: []Path_Part) -> (res: Write_Cursor, err: Error) {
 119 | 	cursor_check_writable(c) or_return  // <== [calls cursor_check_writable]
 120 | 	if (c.db.transaction != nil || c.db.tx_start != nil) && is_root(c.slot_ptr) && len(path) > 0 {  // <== [calls is_root]
 121 | 		return {}, .Nested_Top_Level_Write
 122 | 	}
 123 | 
 124 | 	tx_stack: Transaction
 125 | 	starts_transaction := c.db.transaction == nil && is_root(c.slot_ptr)  // <== [calls is_root]
 126 | 	if starts_transaction {
 127 | 		c.db.transaction = &tx_stack
 128 | 	}
 129 | 	defer if starts_transaction {
 130 | 		c.db.transaction = nil
 131 | 	}
 132 | 
 133 | 	err = nil
 134 | 	switch c.slot_ptr.slot.tag {
 135 | 	case .Array_List, .Linked_Array_List, .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
 136 | 		is_init := false
 137 | 		if len(path) > 0 {
 138 | 			_, is_init = init_tag(path[0])  // <== [calls init_tag]
 139 | 		}
 140 | 		if is_init || (c.db.transaction != nil && (c.db.transaction.frozen_at != nil || c.frozen_at != 0)) {
 141 | 			err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 142 | 		}
 143 | 	case .None, .Index, .Bytes, .Short_Bytes, .Uint, .Int, .Float, .KV_Pair, .Sorted_KV_Pair:
 144 | 		err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 145 | 	}
 146 | 	slot_ptr: Slot_Pointer
 147 | 	if err == nil {
 148 | 		slot_ptr, err = read_slot_pointer(c.db, .Read_Write, path, 0, c.slot_ptr, c.frozen_at)  // <== [calls read_slot_pointer]
 149 | 	}
 150 | 	if err != nil {
 151 | 		if c.db.tx_start == nil {
 152 | 			_ = database_truncate(c.db)  // <== [calls database_truncate]
 153 | 		}
 154 | 		return {}, err
 155 | 	}
 156 | 	if c.db.tx_start == nil {
 157 | 		core_sync(c.db.core) or_return  // <== [calls core_sync]
 158 | 	}
 159 | 	ends_with_ctx := false
 160 | 	if len(path) > 0 {
 161 | 		_, ends_with_ctx = path[len(path) - 1].(Context)
 162 | 	}
 163 | 	res = new_write_cursor(slot_ptr, c.db)  // <== [calls new_write_cursor]
 164 | 	res.frozen_at = c.frozen_at
 165 | 	if ends_with_ctx {
 166 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 167 | 		cursor_reload_slot(&res) or_return  // <== [calls cursor_reload_slot]
 168 | 	} else if c.slot_ptr.position != nil && c.slot_ptr.position == slot_ptr.position {
 169 | 		c.slot_ptr = slot_ptr
 170 | 	} else if c.db.transaction == nil || c.db.transaction.frozen_at != nil || c.frozen_at != 0 || c.slot_ptr.slot.tag == .None {
 171 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 172 | 	}
 173 | 	return res, nil
 174 | }
```

#### [`cursor_writer`](../../xitdb/cursor.odin#L536-L555) — `ENTRY POINT` (`L536–L555`)

```odin
 536 | cursor_writer :: proc(c: ^Write_Cursor) -> (res: Cursor_Writer, err: Error) {
 537 | 	cursor_check_writable(c) or_return  // <== [calls cursor_check_writable]
 538 | 	if is_root(c.slot_ptr) {  // <== [calls is_root]
 539 | 		return {}, .Cursor_Not_Writeable
 540 | 	}
 541 | 	if c.db.tx_start == nil {
 542 | 		return {}, .Expected_Tx_Start
 543 | 	}
 544 | 	ptr_pos := core_length(c.db.core) or_return  // <== [calls core_length]
 545 | 	core_seek_to(c.db.core, ptr_pos) or_return  // <== [calls core_seek_to]
 546 | 	core_write_long(c.db.core, 0) or_return  // <== [calls core_write_long]
 547 | 	start_position := core_length(c.db.core) or_return  // <== [calls core_length]
 548 | 	return Cursor_Writer{
 549 | 		parent            = c,
 550 | 		size              = 0,
 551 | 		slot              = Slot{value = ptr_pos, tag = .Bytes},
 552 | 		start_position    = start_position,
 553 | 		relative_position = 0,
 554 | 	}, nil
 555 | }
```

#### [`cursor_writer_check_writable`](../../xitdb/cursor.odin#L557-L569) — `DEPTH 1` (`L557–L569`)

```odin
 557 | cursor_writer_check_writable :: proc(w: ^Cursor_Writer) -> Error {
 558 | 	cursor_check_writable(w.parent) or_return  // <== [calls cursor_check_writable]
 559 | 	if w.parent.db.tx_start == nil {
 560 | 		return .Expected_Tx_Start
 561 | 	}
 562 | 	active := w.parent.db.transaction
 563 | 	if active != nil {
 564 | 		if fa, ok := active.frozen_at.?; ok && w.slot.value < fa {
 565 | 			return .Frozen_Bytes
 566 | 		}
 567 | 	}
 568 | 	return nil
 569 | }
```

#### [`cursor_writer_write`](../../xitdb/cursor.odin#L571-L590) — `ENTRY POINT` (`L571–L590`)

```odin
 571 | cursor_writer_write :: proc(w: ^Cursor_Writer, p: []u8) -> (res: int, err: Error) {
 572 | 	cursor_writer_check_writable(w) or_return  // <== [calls cursor_writer_check_writable]
 573 | 	if w.size < w.relative_position {
 574 | 		return 0, .End_Of_Stream
 575 | 	}
 576 | 	new_position := w.relative_position + i64(len(p))
 577 | 	if new_position > w.size {
 578 | 		end := core_length(w.parent.db.core) or_return  // <== [calls core_length]
 579 | 		if end != w.start_position + w.size {
 580 | 			return 0, .Unexpected_Writer_Position
 581 | 		}
 582 | 	}
 583 | 	core_seek_to(w.parent.db.core, w.start_position + w.relative_position) or_return  // <== [calls core_seek_to]
 584 | 	core_write_all(w.parent.db.core, p) or_return  // <== [calls core_write_all]
 585 | 	w.relative_position = new_position
 586 | 	if w.relative_position > w.size {
 587 | 		w.size = w.relative_position
 588 | 	}
 589 | 	return len(p), nil
 590 | }
```

#### [`cursor_writer_finish`](../../xitdb/cursor.odin#L600-L629) — `ENTRY POINT` (`L600–L629`)

```odin
 600 | cursor_writer_finish :: proc(w: ^Cursor_Writer) -> Error {
 601 | 	cursor_writer_check_writable(w) or_return  // <== [calls cursor_writer_check_writable]
 602 | 	if w.format_tag != nil {
 603 | 		if len(w.format_tag) != 2 {
 604 | 			return .Invalid_Format_Tag_Size
 605 | 		}
 606 | 		w.slot = slot_with_full(w.slot, true)  // <== [calls slot_with_full]
 607 | 		format_tag_pos := core_length(w.parent.db.core) or_return  // <== [calls core_length]
 608 | 		core_seek_to(w.parent.db.core, format_tag_pos) or_return  // <== [calls core_seek_to]
 609 | 		if w.start_position + w.size != format_tag_pos {
 610 | 			return .Unexpected_Writer_Position
 611 | 		}
 612 | 		core_write_all(w.parent.db.core, w.format_tag) or_return  // <== [calls core_write_all]
 613 | 	}
 614 | 	core_seek_to(w.parent.db.core, w.slot.value) or_return  // <== [calls core_seek_to]
 615 | 	core_write_long(w.parent.db.core, w.size) or_return  // <== [calls core_write_long]
 616 | 
 617 | 	position, pos_ok := w.parent.slot_ptr.position.?
 618 | 	if !pos_ok {
 619 | 		return .Cursor_Not_Writeable
 620 | 	}
 621 | 	core_seek_to(w.parent.db.core, position) or_return  // <== [calls core_seek_to]
 622 | 	core_write_slot(w.parent.db.core, w.slot) or_return  // <== [calls core_write_slot]
 623 | 
 624 | 	w.parent.slot_ptr = slot_pointer_with_slot(w.parent.slot_ptr, w.slot)  // <== [calls slot_pointer_with_slot]
 625 | 	if w.parent.db.tx_start == nil {
 626 | 		return core_sync(w.parent.db.core)  // <== [calls core_sync]
 627 | 	}
 628 | 	return nil
 629 | }
```

### `xitdb/database.odin` (21 procedures · 343 lines: [`L13–L18`](../../xitdb/database.odin#L13-L18), [`L182–L235`](../../xitdb/database.odin#L182-L235), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L272–L280`](../../xitdb/database.odin#L272-L280), [`L283–L298`](../../xitdb/database.odin#L283-L298), [`L302–L306`](../../xitdb/database.odin#L302-L306), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L337–L341`](../../xitdb/database.odin#L337-L341), [`L343–L362`](../../xitdb/database.odin#L343-L362), [`L364–L368`](../../xitdb/database.odin#L364-L368), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L379–L382`](../../xitdb/database.odin#L379-L382), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414), [`L416–L421`](../../xitdb/database.odin#L416-L421), [`L423–L438`](../../xitdb/database.odin#L423-L438), [`L440–L460`](../../xitdb/database.odin#L440-L460), [`L503–L515`](../../xitdb/database.odin#L503-L515), [`L552–L619`](../../xitdb/database.odin#L552-L619), [`L621–L1382`](../../xitdb/database.odin#L621-L1382))

#### [`transaction_is_root_position`](../../xitdb/database.odin#L13-L18) — `DEPTH 3` (`L13–L18`)

```odin
  13 | transaction_is_root_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  14 | 	if t == nil || pos == nil || t.root_position == nil {
  15 | 		return false
  16 | 	}
  17 | 	return pos.? == t.root_position.?
  18 | }
```

#### [`database_init`](../../xitdb/database.odin#L182-L235) — `ENTRY POINT` (`L182–L235`)

```odin
 182 | database_init :: proc(core: ^Core, hasher := Hasher{}) -> (db: Database, err: Error) {
 183 | 	h := hasher
 184 | 	if h.hash_proc == nil && h.hash_size == 0 {
 185 | 		h = sha1_hasher()  // <== [calls sha1_hasher]
 186 | 	}
 187 | 
 188 | 	// If buffered file, clear any stale buffer bytes before opening.
 189 | 	#partial switch &bf in core {
 190 | 	case Core_Buffered_File:
 191 | 		clear(&bf.memory.buf)
 192 | 		bf.flushed_len = 0
 193 | 		bf.memory_pos = 0
 194 | 		bf.pos = 0
 195 | 		bf.file_len = nil
 196 | 	}
 197 | 
 198 | 	db.core = core
 199 | 	db.hasher = h
 200 | 	db.tx_start = nil
 201 | 	db.transaction = nil
 202 | 
 203 | 	core_seek_to(core, 0) or_return  // <== [calls core_seek_to]
 204 | 	length := core_length(core) or_return  // <== [calls core_length]
 205 | 
 206 | 	if length == 0 {
 207 | 		file_id := h.file_id
 208 | 		if file_id == 0 {
 209 | 			file_id = _random_u64()  // <== [calls _random_u64]
 210 | 		}
 211 | 		digest_len := h.hash_size
 212 | 		if digest_len == 0 {
 213 | 			digest_len = 20
 214 | 		}
 215 | 		db.header = Header{
 216 | 			file_id      = file_id,
 217 | 			hash_id      = h.id,
 218 | 			hash_size    = digest_len,
 219 | 			version      = VERSION,
 220 | 			padding      = 0,
 221 | 			magic_number = MAGIC_NUMBER,
 222 | 		}
 223 | 		header_write(db.header, core) or_return  // <== [calls header_write]
 224 | 		rh_bytes := root_header_to_bytes(Root_Header{file_size = 0, root = Slot{}})  // <== [calls root_header_to_bytes]
 225 | 		core_write_all(core, rh_bytes[:]) or_return  // <== [calls core_write_all]
 226 | 		database_commit_root(&db, Slot{}, 0) or_return  // <== [calls database_commit_root]
 227 | 		core_sync(core) or_return  // <== [calls core_sync]
 228 | 	} else {
 229 | 		db.header = database_read_and_validate_header(&db) or_return  // <== [calls database_read_and_validate_header]
 230 | 		_ = database_committed_size(&db) or_return  // <== [calls database_committed_size]
 231 | 	}
 232 | 
 233 | 	db.tx_start = nil
 234 | 	return db, nil
 235 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 1` (`L237–L244`)

```odin
 237 | @(private)
 238 | _random_u64 :: proc() -> u64 {
 239 | 	v := rand.uint64()
 240 | 	if v == 0 {
 241 | 		v = 1
 242 | 	}
 243 | 	return v
 244 | }
```

#### [`database_read_and_validate_header`](../../xitdb/database.odin#L272-L280) — `DEPTH 1` (`L272–L280`)

```odin
 272 | database_read_and_validate_header :: proc(db: ^Database) -> (res: Header, err: Error) {
 273 | 	core_seek_to(db.core, 0) or_return  // <== [calls core_seek_to]
 274 | 	header := header_read(db.core) or_return  // <== [calls header_read]
 275 | 	header_validate(header) or_return  // <== [calls header_validate]
 276 | 	if db.hasher.hash_size != 0 && header.hash_size != db.hasher.hash_size {
 277 | 		return {}, .Invalid_Hash_Size
 278 | 	}
 279 | 	return header, nil
 280 | }
```

#### [`database_root_cursor`](../../xitdb/database.odin#L283-L298) — `DEPTH 1` (`L283–L298`)

```odin
 283 | database_root_cursor :: proc(db: ^Database) -> Write_Cursor {
 284 | 	root, err := database_read_root_slot(db)  // <== [calls database_read_root_slot]
 285 | 	if err != nil {
 286 | 		root = Slot{}
 287 | 	}
 288 | 	return Write_Cursor{
 289 | 		read_cursor = Read_Cursor{
 290 | 			slot_ptr = Slot_Pointer{
 291 | 				position = i64(ROOT_HEADER_START),
 292 | 				slot     = root,
 293 | 			},
 294 | 			db        = db,
 295 | 			frozen_at = 0,
 296 | 		},
 297 | 	}
 298 | }
```

#### [`database_run_context`](../../xitdb/database.odin#L302-L306) — `ENTRY POINT` (`L302–L306`)

```odin
 302 | database_run_context :: proc(db: ^Database, fn: Context_Function, user_data: rawptr = nil) -> Error {
 303 | 	rc := database_root_cursor(db)  // <== [calls database_root_cursor]
 304 | 	_, err := cursor_write_path(&rc, []Path_Part{Context{function = fn, user_data = user_data}})  // <== [calls cursor_write_path]
 305 | 	return err
 306 | }
```

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 2` (`L319–L334`)

```odin
 319 | @(private)
 320 | _database_committed_size_with_header :: proc(db: ^Database, header: Root_Header) -> (committed_size: i64, file_size: i64, err: Error) {
 321 | 	minimum_size := i64(ROOT_HEADER_END + ROOT_TRAILER_LENGTH)
 322 | 	if header.file_size < minimum_size {
 323 | 		return 0, 0, .Invalid_Database
 324 | 	}
 325 | 	file_size = core_length(db.core) or_return  // <== [calls core_length]
 326 | 	if file_size < header.file_size {
 327 | 		return 0, 0, .Truncated_Database
 328 | 	}
 329 | 	trailer := database_read_root_trailer(db, header.file_size) or_return  // <== [calls database_read_root_trailer]
 330 | 	if trailer.root != header.root {
 331 | 		return 0, 0, .Invalid_Database
 332 | 	}
 333 | 	return header.file_size, file_size, nil
 334 | }
```

#### [`database_committed_size`](../../xitdb/database.odin#L337-L341) — `DEPTH 1` (`L337–L341`)

```odin
 337 | database_committed_size :: proc(db: ^Database) -> (res: i64, err: Error) {
 338 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 339 | 	committed_size, _ := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 340 | 	return committed_size, nil
 341 | }
```

#### [`_database_truncate_with_header`](../../xitdb/database.odin#L343-L362) — `DEPTH 3` (`L343–L362`)

```odin
 343 | @(private)
 344 | _database_truncate_with_header :: proc(db: ^Database, header: Root_Header) -> (final_size: i64, err: Error) {
 345 | 	committed_size, file_size := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 346 | 	active := db.transaction
 347 | 	if active != nil {
 348 | 		if fa, ok := active.frozen_at.?; ok && fa > committed_size {
 349 | 			if file_size > fa {
 350 | 				core_set_length(db.core, fa) or_return  // <== [calls core_set_length]
 351 | 			}
 352 | 			commit_id := _random_u64()  // <== [calls _random_u64]
 353 | 			database_commit_root(db, header.root, commit_id) or_return  // <== [calls database_commit_root]
 354 | 			core_sync(db.core) or_return  // <== [calls core_sync]
 355 | 			return core_length(db.core)  // <== [calls core_length]
 356 | 		}
 357 | 	}
 358 | 	if file_size > committed_size {
 359 | 		core_set_length(db.core, committed_size) or_return  // <== [calls core_set_length]
 360 | 	}
 361 | 	return committed_size, nil
 362 | }
```

#### [`database_truncate`](../../xitdb/database.odin#L364-L368) — `DEPTH 2` (`L364–L368`)

```odin
 364 | database_truncate :: proc(db: ^Database) -> Error {
 365 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 366 | 	_, err := _database_truncate_with_header(db, header)  // <== [calls _database_truncate_with_header]
 367 | 	return err
 368 | }
```

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 2` (`L370–L377`)

```odin
 370 | database_read_root_header :: proc(db: ^Database) -> (res: Root_Header, err: Error) {
 371 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 372 | 	b: [ROOT_HEADER_LENGTH]u8
 373 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 374 | 	header := root_header_from_bytes(b)  // <== [calls root_header_from_bytes]
 375 | 	tag_validate(header.root.tag) or_return  // <== [calls tag_validate]
 376 | 	return header, nil
 377 | }
```

#### [`database_read_root_slot`](../../xitdb/database.odin#L379-L382) — `DEPTH 2` (`L379–L382`)

```odin
 379 | database_read_root_slot :: proc(db: ^Database) -> (res: Slot, err: Error) {
 380 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 381 | 	return header.root, nil
 382 | }
```

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 3` (`L384–L398`)

```odin
 384 | database_read_root_trailer :: proc(db: ^Database, end: i64) -> (res: Root_Trailer, err: Error) {
 385 | 	if end < ROOT_TRAILER_LENGTH {
 386 | 		return {}, .Invalid_Database
 387 | 	}
 388 | 	trailer_pos := end - ROOT_TRAILER_LENGTH
 389 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 390 | 	b: [ROOT_TRAILER_LENGTH]u8
 391 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 392 | 	trailer := root_trailer_from_bytes(b)  // <== [calls root_trailer_from_bytes]
 393 | 	if trailer.checksum != compute_root_trailer_checksum(db.header.file_id, trailer_pos, trailer.root, trailer.commit_id) {  // <== [calls compute_root_trailer_checksum]
 394 | 		return {}, .Invalid_Database
 395 | 	}
 396 | 	tag_validate(trailer.root.tag) or_return  // <== [calls tag_validate]
 397 | 	return trailer, nil
 398 | }
```

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 1` (`L400–L407`)

```odin
 400 | database_commit_root :: proc(db: ^Database, root: Slot, commit_id: u64) -> Error {
 401 | 	trailer_pos := core_length(db.core) or_return  // <== [calls core_length]
 402 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 403 | 	trailer := root_trailer_to_bytes(new_root_trailer(db.header.file_id, trailer_pos, root, commit_id))  // <== [calls root_trailer_to_bytes, new_root_trailer]
 404 | 	core_write_all(db.core, trailer[:]) or_return  // <== [calls core_write_all]
 405 | 	core_sync(db.core) or_return  // <== [calls core_sync]
 406 | 	return database_write_root_header(db, root)  // <== [calls database_write_root_header]
 407 | }
```

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 2` (`L409–L414`)

```odin
 409 | database_write_root_header :: proc(db: ^Database, root: Slot) -> Error {
 410 | 	file_size := core_length(db.core) or_return  // <== [calls core_length]
 411 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 412 | 	header := root_header_to_bytes(Root_Header{file_size = file_size, root = root})  // <== [calls root_header_to_bytes]
 413 | 	return core_write_all(db.core, header[:])  // <== [calls core_write_all]
 414 | }
```

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 1` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

#### [`init_tag`](../../xitdb/database.odin#L423-L438) — `DEPTH 2` (`L423–L438`)

```odin
 423 | init_tag :: proc(part: Path_Part) -> (res: Tag, err: bool) {
 424 | 	#partial switch p in part {
 425 | 	case Array_List_Init:
 426 | 		return .Array_List, true
 427 | 	case Linked_Array_List_Init:
 428 | 		return .Linked_Array_List, true
 429 | 	case Hash_Map_Init:
 430 | 		if p.counted {
 431 | 			return (.Counted_Hash_Set if p.set else .Counted_Hash_Map), true
 432 | 		}
 433 | 		return (.Hash_Set if p.set else .Hash_Map), true
 434 | 	case Sorted_Map_Init:
 435 | 		return (.Sorted_Set if p.set else .Sorted_Map), true
 436 | 	}
 437 | 	return .None, false
 438 | }
```

#### [`init_part_for`](../../xitdb/database.odin#L440-L460) — `DEPTH 3` (`L440–L460`)

```odin
 440 | init_part_for :: proc(tag: Tag) -> (res: Path_Part, err: bool) {
 441 | 	#partial switch tag {
 442 | 	case .Array_List:
 443 | 		return Array_List_Init{}, true
 444 | 	case .Linked_Array_List:
 445 | 		return Linked_Array_List_Init{}, true
 446 | 	case .Hash_Map:
 447 | 		return Hash_Map_Init{counted = false, set = false}, true
 448 | 	case .Hash_Set:
 449 | 		return Hash_Map_Init{counted = false, set = true}, true
 450 | 	case .Counted_Hash_Map:
 451 | 		return Hash_Map_Init{counted = true, set = false}, true
 452 | 	case .Counted_Hash_Set:
 453 | 		return Hash_Map_Init{counted = true, set = true}, true
 454 | 	case .Sorted_Map:
 455 | 		return Sorted_Map_Init{set = false}, true
 456 | 	case .Sorted_Set:
 457 | 		return Sorted_Map_Init{set = true}, true
 458 | 	}
 459 | 	return nil, false
 460 | }
```

#### [`database_check_frozen_slot`](../../xitdb/database.odin#L503-L515) — `DEPTH 2` (`L503–L515`)

```odin
 503 | database_check_frozen_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer) -> Error {
 504 | 	active := db.transaction
 505 | 	if active != nil {
 506 | 		if fa, ok := active.frozen_at.?; ok {
 507 | 			if pos, pok := slot_ptr.position.?; pok {
 508 | 				if pos < fa && !transaction_is_root_position(active, slot_ptr.position) {  // <== [calls transaction_is_root_position]
 509 | 					return .Frozen_Slot
 510 | 				}
 511 | 			}
 512 | 		}
 513 | 	}
 514 | 	return nil
 515 | }
```

#### [`read_slot_pointer`](../../xitdb/database.odin#L552-L619) — `DEPTH 2` (`L552–L619`)

```odin
 552 | read_slot_pointer :: proc(
 553 | 	db: ^Database,
 554 | 	write_mode: Write_Mode,
 555 | 	path: []Path_Part,
 556 | 	path_i: int,
 557 | 	slot_ptr: Slot_Pointer,
 558 | 	frozen_at: i64,
 559 | ) -> (res: Slot_Pointer, err: Error) {
 560 | 	if path_i == len(path) {
 561 | 		if write_mode == .Read_Only && slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
 562 | 			return {}, .Key_Not_Found
 563 | 		}
 564 | 		return slot_ptr, nil
 565 | 	}
 566 | 	if write_mode == .Read_Write {
 567 | 		database_check_frozen_slot(db, slot_ptr) or_return  // <== [calls database_check_frozen_slot]
 568 | 	}
 569 | 	part := path[path_i]
 570 | 
 571 | 	// Every write that starts at the root is a transaction.
 572 | 	if is_root(slot_ptr) {  // <== [calls is_root]
 573 | 		root_header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 574 | 		root := root_header.root
 575 | 
 576 | 		if write_mode == .Read_Only {
 577 | 			return read_slot_pointer(db, write_mode, path, path_i, Slot_Pointer{position = nil, slot = root}, frozen_at)
 578 | 		}
 579 | 
 580 | 		// Initializing an already-initialized root is free.
 581 | 		if len(path) - path_i == 1 && root.tag != .None {
 582 | 			if tag, ok := init_tag(part); ok && tag == root.tag {  // <== [calls init_tag]
 583 | 				_ = _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 584 | 				return Slot_Pointer{position = i64(ROOT_HEADER_START), slot = root}, nil
 585 | 			}
 586 | 		}
 587 | 
 588 | 		scratch_pos := _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 589 | 		db.tx_start = scratch_pos
 590 | 		defer db.tx_start = nil
 591 | 
 592 | 		if db.transaction != nil {
 593 | 			db.transaction.root_position = scratch_pos
 594 | 			db.transaction.scratch_position = scratch_pos
 595 | 		}
 596 | 
 597 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 598 | 		core_write_slot(db.core, root) or_return  // <== [calls core_write_slot]
 599 | 		root_ptr := Slot_Pointer{position = scratch_pos, slot = root}
 600 | 
 601 | 		if init_p, ok := init_part_for(root.tag); ok {  // <== [calls init_part_for]
 602 | 			root_ptr = read_slot_pointer(db, write_mode, []Path_Part{init_p}, 0, root_ptr, frozen_at) or_return
 603 | 		}
 604 | 
 605 | 		result := read_slot_pointer(db, write_mode, path, path_i, root_ptr, frozen_at) or_return
 606 | 
 607 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 608 | 		next_root := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 609 | 		commit_id := _random_u64()  // <== [calls _random_u64]
 610 | 		database_commit_root(db, next_root, commit_id) or_return  // <== [calls database_commit_root]
 611 | 
 612 | 		if rpos, ok := result.position.?; ok && rpos == scratch_pos {
 613 | 			result = Slot_Pointer{position = i64(ROOT_HEADER_START), slot = next_root}
 614 | 		}
 615 | 		return result, nil
 616 | 	}
 617 | 
 618 | 	return _exec_path_part(db, part, write_mode, path, path_i, slot_ptr, frozen_at)  // <== [calls _exec_path_part]
 619 | }
```

#### [`_exec_path_part`](../../xitdb/database.odin#L621-L1382) — `DEPTH 3` (`L621–L1382`) — Active `Path_Part` arms: `Context`

```odin
 621 | @(private)
 622 | _exec_path_part :: proc(
 623 | 	db: ^Database,
 624 | 	part: Path_Part,
 625 | 	write_mode: Write_Mode,
 626 | 	path: []Path_Part,
 627 | 	path_i: int,
 628 | 	slot_ptr: Slot_Pointer,
 629 | 	frozen_at: i64,
 630 | ) -> (res: Slot_Pointer, err: Error) {
 631 | 	slot_ptr := slot_ptr
 632 | 
 633 | 	switch p in part {
   ... | 	// ... [lines 634–1361: untouched Path_Part arms omitted] ...
1362 | 	case Context:
1363 | 		if write_mode == .Read_Only {
1364 | 			return {}, .Write_Not_Allowed
1365 | 		}
1366 | 		if path_i != len(path) - 1 {
1367 | 			return {}, .Path_Part_Must_Be_At_End
1368 | 		}
1369 | 		clean_sp := slot_ptr
1370 | 		if clean_sp.slot.tag == .KV_Pair && clean_sp.slot.full {
1371 | 			clean_sp.slot.full = false
1372 | 		}
1373 | 		next_cursor := new_write_cursor(clean_sp, db)  // <== [calls new_write_cursor]
1374 | 		next_cursor.frozen_at = frozen_at
1375 | 		if p.function != nil {
1376 | 			p.function(&next_cursor, p.user_data) or_return
1377 | 		}
1378 | 		return next_cursor.slot_ptr, nil
1379 | 	}
1380 | 
1381 | 	return {}, .Unreachable
1382 | }
```

### `xitdb/types.odin` (21 procedures · 455 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L175–L353`](../../xitdb/types.odin#L175-L353), [`L571–L691`](../../xitdb/types.odin#L571-L691), [`L825–L834`](../../xitdb/types.odin#L825-L834), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L865–L869`](../../xitdb/types.odin#L865-L869), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L915–L917`](../../xitdb/types.odin#L915-L917), [`L929–L937`](../../xitdb/types.odin#L929-L937), [`L939–L950`](../../xitdb/types.odin#L939-L950), [`L952–L966`](../../xitdb/types.odin#L952-L966), [`L968–L972`](../../xitdb/types.odin#L968-L972), [`L974–L977`](../../xitdb/types.odin#L974-L977), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`sha1_transf_hw`](../../xitdb/types.odin#L175-L353) — `DEPTH 2` (`L175–L353`)

```odin
 175 | 	@(private = "file", enable_target_feature = "sse2,ssse3,sse4.1,sha")
 176 | 	sha1_transf_hw :: proc "contextless" (state: ^[5]u32, data: []u8) #no_bounds_check {
 177 | 		// Load initial state: state[0..3] = A, B, C, D; state[4] = E
 178 | 		abcd := intrinsics.unaligned_load((^x86.__m128i)(&state[0]))
 179 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B) // lane 3..0 = A, B, C, D
 180 | 		e0 := x86._mm_set_epi32(i32(state[4]), 0, 0, 0)
 181 | 
 182 | 		data := data
 183 | 		for len(data) >= 64 {
 184 | 			abcd_save := abcd
 185 | 			e0_save := e0
 186 | 
 187 | 			// Rounds 0..3
 188 | 			msg0 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[0:])))
 189 | 			msg0 = x86._mm_shuffle_epi8(msg0, SHA1_SHUF_MASK)
 190 | 			e0 = x86._mm_add_epi32(e0, msg0)
 191 | 			e1 := abcd
 192 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 193 | 
 194 | 			// Rounds 4..7
 195 | 			msg1 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[16:])))
 196 | 			msg1 = x86._mm_shuffle_epi8(msg1, SHA1_SHUF_MASK)
 197 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 198 | 			e0 = abcd
 199 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 200 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 201 | 
 202 | 			// Rounds 8..11
 203 | 			msg2 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[32:])))
 204 | 			msg2 = x86._mm_shuffle_epi8(msg2, SHA1_SHUF_MASK)
 205 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 206 | 			e1 = abcd
 207 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 208 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 209 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 210 | 
 211 | 			// Rounds 12..15
 212 | 			msg3 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[48:])))
 213 | 			msg3 = x86._mm_shuffle_epi8(msg3, SHA1_SHUF_MASK)
 214 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 215 | 			e0 = abcd
 216 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 217 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 218 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 219 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 220 | 
 221 | 			// Rounds 16..19
 222 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 223 | 			e1 = abcd
 224 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 225 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 226 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 227 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 228 | 
 229 | 			// Rounds 20..23
 230 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 231 | 			e0 = abcd
 232 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 233 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 234 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 235 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 236 | 
 237 | 			// Rounds 24..27
 238 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 239 | 			e1 = abcd
 240 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 241 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 242 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 243 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 244 | 
 245 | 			// Rounds 28..31
 246 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 247 | 			e0 = abcd
 248 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 249 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 250 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 251 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 252 | 
 253 | 			// Rounds 32..35
 254 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 255 | 			e1 = abcd
 256 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 257 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 258 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 259 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 260 | 
 261 | 			// Rounds 36..39
 262 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 263 | 			e0 = abcd
 264 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 265 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 266 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 267 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 268 | 
 269 | 			// Rounds 40..43
 270 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 271 | 			e1 = abcd
 272 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 273 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 274 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 275 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 276 | 
 277 | 			// Rounds 44..47
 278 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 279 | 			e0 = abcd
 280 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 281 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 282 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 283 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 284 | 
 285 | 			// Rounds 48..51
 286 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 287 | 			e1 = abcd
 288 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 289 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 290 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 291 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 292 | 
 293 | 			// Rounds 52..55
 294 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 295 | 			e0 = abcd
 296 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 297 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 298 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 299 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 300 | 
 301 | 			// Rounds 56..59
 302 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 303 | 			e1 = abcd
 304 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 305 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 306 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 307 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 308 | 
 309 | 			// Rounds 60..63
 310 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 311 | 			e0 = abcd
 312 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 313 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 314 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 315 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 316 | 
 317 | 			// Rounds 64..67
 318 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 319 | 			e1 = abcd
 320 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 321 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 322 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 323 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 324 | 
 325 | 			// Rounds 68..71
 326 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 327 | 			e0 = abcd
 328 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 329 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 330 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 331 | 
 332 | 			// Rounds 72..75
 333 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 334 | 			e1 = abcd
 335 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 336 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 337 | 
 338 | 			// Rounds 76..79
 339 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 340 | 			e0 = abcd
 341 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 342 | 
 343 | 			// Combine state
 344 | 			e0 = x86._mm_sha1nexte_epu32(e0, e0_save)
 345 | 			abcd = x86._mm_add_epi32(abcd, abcd_save)
 346 | 
 347 | 			data = data[64:]
 348 | 		}
 349 | 
 350 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B)
 351 | 		intrinsics.unaligned_store((^x86.__m128i)(&state[0]), abcd)
 352 | 		state[4] = u32(x86._mm_extract_epi32(e0, 3))
 353 | 	}
```

#### [`sha1_sum_into`](../../xitdb/types.odin#L571-L691) — `DEPTH 1` (`L571–L691`)

```odin
 571 | sha1_sum_into :: proc(data: []u8, out: []u8) #no_bounds_check {
 572 | 	state := [5]u32{
 573 | 		0x67452301,
 574 | 		0xEFCDAB89,
 575 | 		0x98BADCFE,
 576 | 		0x10325476,
 577 | 		0xC3D2E1F0,
 578 | 	}
 579 | 
 580 | 	when ODIN_ARCH == .amd64 {
 581 | 		if _has_sha_ni {
 582 | 			full_len := len(data) & ~int(63)
 583 | 			if full_len > 0 {
 584 | 				sha1_transf_hw(&state, data[:full_len])  // <== [calls sha1_transf_hw]
 585 | 			}
 586 | 			rem := len(data) - full_len
 587 | 			bit_len := u64(len(data)) * 8
 588 | 			if rem < 56 {
 589 | 				tail: [64]u8
 590 | 				copy(tail[:rem], data[full_len:])
 591 | 				tail[rem] = 0x80
 592 | 				endian.unchecked_put_u64be(tail[56:64], bit_len)
 593 | 				sha1_transf_hw(&state, tail[0:64])  // <== [calls sha1_transf_hw]
 594 | 			} else {
 595 | 				tail: [128]u8
 596 | 				copy(tail[:rem], data[full_len:])
 597 | 				tail[rem] = 0x80
 598 | 				endian.unchecked_put_u64be(tail[120:128], bit_len)
 599 | 				sha1_transf_hw(&state, tail[0:128])  // <== [calls sha1_transf_hw]
 600 | 			}
 601 | 			endian.unchecked_put_u32be(out[0:4], state[0])
 602 | 			endian.unchecked_put_u32be(out[4:8], state[1])
 603 | 			endian.unchecked_put_u32be(out[8:12], state[2])
 604 | 			endian.unchecked_put_u32be(out[12:16], state[3])
 605 | 			endian.unchecked_put_u32be(out[16:20], state[4])
 606 | 			return
 607 | 		}
 608 | 	}
 609 | 
 610 | 	h0, h1, h2, h3, h4 := state[0], state[1], state[2], state[3], state[4]
 611 | 
 612 | 	rol32 :: #force_inline proc(x: u32, n: uint) -> u32 {
 613 | 		return (x << n) | (x >> (32 - n))
 614 | 	}
 615 | 
 616 | 	process_block :: proc(block: []u8, h0, h1, h2, h3, h4: ^u32) {
 617 | 		w: [80]u32
 618 | 		for i in 0 ..< 16 {
 619 | 			v, _ := endian.get_u32(block[i * 4:i * 4 + 4], .Big)
 620 | 			w[i] = v
 621 | 		}
 622 | 		for i in 16 ..< 80 {
 623 | 			x := w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16]
 624 | 			w[i] = (x << 1) | (x >> 31)
 625 | 		}
 626 | 
 627 | 		a := h0^
 628 | 		b := h1^
 629 | 		c := h2^
 630 | 		d := h3^
 631 | 		e := h4^
 632 | 
 633 | 		for i in 0 ..< 80 {
 634 | 			f, k: u32
 635 | 			if i < 20 {
 636 | 				f = (b & c) | ((~b) & d)
 637 | 				k = 0x5A827999
 638 | 			} else if i < 40 {
 639 | 				f = b ~ c ~ d
 640 | 				k = 0x6ED9EBA1
 641 | 			} else if i < 60 {
 642 | 				f = (b & c) | (b & d) | (c & d)
 643 | 				k = 0x8F1BBCDC
 644 | 			} else {
 645 | 				f = b ~ c ~ d
 646 | 				k = 0xCA62C1D6
 647 | 			}
 648 | 			temp := ((a << 5) | (a >> 27)) + f + e + k + w[i]
 649 | 			e = d
 650 | 			d = c
 651 | 			c = (b << 30) | (b >> 2)
 652 | 			b = a
 653 | 			a = temp
 654 | 		}
 655 | 
 656 | 		h0^ += a
 657 | 		h1^ += b
 658 | 		h2^ += c
 659 | 		h3^ += d
 660 | 		h4^ += e
 661 | 	}
 662 | 
 663 | 	i := 0
 664 | 	for i + 64 <= len(data) {
 665 | 		process_block(data[i:i + 64], &h0, &h1, &h2, &h3, &h4)
 666 | 		i += 64
 667 | 	}
 668 | 
 669 | 	rem := len(data) - i
 670 | 	bit_len := u64(len(data)) * 8
 671 | 	if rem < 56 {
 672 | 		tail: [64]u8
 673 | 		copy(tail[:rem], data[i:])
 674 | 		tail[rem] = 0x80
 675 | 		endian.put_u64(tail[56:64], .Big, bit_len)
 676 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 677 | 	} else {
 678 | 		tail: [128]u8
 679 | 		copy(tail[:rem], data[i:])
 680 | 		tail[rem] = 0x80
 681 | 		endian.put_u64(tail[120:128], .Big, bit_len)
 682 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 683 | 		process_block(tail[64:128], &h0, &h1, &h2, &h3, &h4)
 684 | 	}
 685 | 
 686 | 	endian.put_u32(out[0:4], .Big, h0)
 687 | 	endian.put_u32(out[4:8], .Big, h1)
 688 | 	endian.put_u32(out[8:12], .Big, h2)
 689 | 	endian.put_u32(out[12:16], .Big, h3)
 690 | 	endian.put_u32(out[16:20], .Big, h4)
 691 | }
```

#### [`sha1_hasher`](../../xitdb/types.odin#L825-L834) — `ENTRY POINT` (`L825–L834`)

```odin
 825 | sha1_hasher :: proc(id: u32 = 0, file_id: u64 = 0) -> Hasher {
 826 | 	return Hasher{
 827 | 		hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
 828 | 			sha1_sum_into(data, out_hash)  // <== [calls sha1_sum_into]
 829 | 		},
 830 | 		hash_size = 20,
 831 | 		id        = id,
 832 | 		file_id   = file_id,
 833 | 	}
 834 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 3` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_with_full`](../../xitdb/types.odin#L865-L869) — `DEPTH 1` (`L865–L869`)

```odin
 865 | slot_with_full :: proc(s: Slot, full: bool) -> Slot {
 866 | 	res := s
 867 | 	res.full = full
 868 | 	return res
 869 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 2` (`L871–L877`)

```odin
 871 | slot_to_bytes :: #force_inline proc(s: Slot) -> [SLOT_LENGTH]u8 {
 872 | 	buf: [SLOT_LENGTH]u8 = ---
 873 | 	full_bit := u8(0x80) if s.full else u8(0)
 874 | 	buf[0] = full_bit | (u8(s.tag) & 0x7f)
 875 | 	endian.unchecked_put_u64be(buf[1:9], u64(s.value))
 876 | 	return buf
 877 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 4` (`L880–L890`)

```odin
 880 | slot_from_bytes_raw :: #force_inline proc(buf: [SLOT_LENGTH]u8) -> Slot {
 881 | 	b := buf
 882 | 	full := (b[0] & 0x80) != 0
 883 | 	raw_tag := b[0] & 0x7f
 884 | 	val := endian.unchecked_get_u64be(b[1:9])
 885 | 	return Slot{
 886 | 		value = i64(val),
 887 | 		tag   = Tag(raw_tag),
 888 | 		full  = full,
 889 | 	}
 890 | }
```

#### [`slot_from_slice_raw`](../../xitdb/types.odin#L892-L901) — `DEPTH 4` (`L892–L901`)

```odin
 892 | slot_from_slice_raw :: #force_inline proc(b: []u8) -> Slot #no_bounds_check {
 893 | 	full := (b[0] & 0x80) != 0
 894 | 	raw_tag := b[0] & 0x7f
 895 | 	val := endian.unchecked_get_u64be(b[1:9])
 896 | 	return Slot{
 897 | 		value = i64(val),
 898 | 		tag   = Tag(raw_tag),
 899 | 		full  = full,
 900 | 	}
 901 | }
```

#### [`slot_pointer_with_slot`](../../xitdb/types.odin#L915-L917) — `DEPTH 1` (`L915–L917`)

```odin
 915 | slot_pointer_with_slot :: proc(sp: Slot_Pointer, s: Slot) -> Slot_Pointer {
 916 | 	return Slot_Pointer{position = sp.position, slot = s}
 917 | }
```

#### [`header_validate`](../../xitdb/types.odin#L929-L937) — `DEPTH 2` (`L929–L937`)

```odin
 929 | header_validate :: proc(h: Header) -> Error {
 930 | 	if h.magic_number != MAGIC_NUMBER {
 931 | 		return .Invalid_Database
 932 | 	}
 933 | 	if h.version != VERSION {
 934 | 		return .Invalid_Version
 935 | 	}
 936 | 	return nil
 937 | }
```

#### [`header_to_bytes`](../../xitdb/types.odin#L939-L950) — `DEPTH 2` (`L939–L950`)

```odin
 939 | header_to_bytes :: proc(h: Header) -> [HEADER_LENGTH]u8 {
 940 | 	buf: [HEADER_LENGTH]u8
 941 | 	buf[0] = h.magic_number[0]
 942 | 	buf[1] = h.magic_number[1]
 943 | 	buf[2] = h.magic_number[2]
 944 | 	buf[3] = h.padding
 945 | 	endian.put_u16(buf[4:6], .Big, h.version)
 946 | 	endian.put_u16(buf[6:8], .Big, h.hash_size)
 947 | 	endian.put_u32(buf[8:12], .Big, h.hash_id)
 948 | 	endian.put_u64(buf[12:20], .Big, h.file_id)
 949 | 	return buf
 950 | }
```

#### [`header_from_bytes`](../../xitdb/types.odin#L952-L966) — `DEPTH 3` (`L952–L966`)

```odin
 952 | header_from_bytes :: proc(buf: [HEADER_LENGTH]u8) -> Header {
 953 | 	b := buf
 954 | 	version, _ := endian.get_u16(b[4:6], .Big)
 955 | 	hash_size, _ := endian.get_u16(b[6:8], .Big)
 956 | 	hash_id, _ := endian.get_u32(b[8:12], .Big)
 957 | 	file_id, _ := endian.get_u64(b[12:20], .Big)
 958 | 	return Header{
 959 | 		magic_number = {b[0], b[1], b[2]},
 960 | 		padding      = b[3],
 961 | 		version      = version,
 962 | 		hash_size    = hash_size,
 963 | 		hash_id      = hash_id,
 964 | 		file_id      = file_id,
 965 | 	}
 966 | }
```

#### [`header_read`](../../xitdb/types.odin#L968-L972) — `DEPTH 2` (`L968–L972`)

```odin
 968 | header_read :: proc(r: ^Core) -> (h: Header, err: Error) {
 969 | 	buf: [HEADER_LENGTH]u8
 970 | 	core_read_exact(r, buf[:]) or_return  // <== [calls core_read_exact]
 971 | 	return header_from_bytes(buf), nil  // <== [calls header_from_bytes]
 972 | }
```

#### [`header_write`](../../xitdb/types.odin#L974-L977) — `DEPTH 1` (`L974–L977`)

```odin
 974 | header_write :: proc(h: Header, w: ^Core) -> Error {
 975 | 	buf := header_to_bytes(h)  // <== [calls header_to_bytes]
 976 | 	return core_write_all(w, buf[:])  // <== [calls core_write_all]
 977 | }
```

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 1` (`L985–L991`)

```odin
 985 | root_header_to_bytes :: proc(rh: Root_Header) -> [ROOT_HEADER_LENGTH]u8 {
 986 | 	buf: [ROOT_HEADER_LENGTH]u8
 987 | 	slot_bytes := slot_to_bytes(rh.root)  // <== [calls slot_to_bytes]
 988 | 	copy(buf[0:9], slot_bytes[:])
 989 | 	endian.put_u64(buf[9:17], .Big, u64(rh.file_size))
 990 | 	return buf
 991 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 3` (`L993–L1003`)

```odin
 993 | root_header_from_bytes :: proc(buf: [ROOT_HEADER_LENGTH]u8) -> Root_Header {
 994 | 	b := buf
 995 | 	slot_buf: [SLOT_LENGTH]u8
 996 | 	copy(slot_buf[:], b[0:9])
 997 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
 998 | 	file_size, _ := endian.get_u64(b[9:17], .Big)
 999 | 	return Root_Header{
1000 | 		file_size = i64(file_size),
1001 | 		root      = root,
1002 | 	}
1003 | }
```

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 3` (`L1012–L1020`)

```odin
1012 | compute_root_trailer_checksum :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> u64 {
1013 | 	data: [33]u8
1014 | 	endian.put_u64(data[0:8], .Big, file_id)
1015 | 	endian.put_u64(data[8:16], .Big, u64(position))
1016 | 	slot_bytes := slot_to_bytes(root)  // <== [calls slot_to_bytes]
1017 | 	copy(data[16:25], slot_bytes[:])
1018 | 	endian.put_u64(data[25:33], .Big, commit_id)
1019 | 	return hash.crc64_xz(data[:])
1020 | }
```

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 2` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 2` (`L1030–L1037`)

```odin
1030 | root_trailer_to_bytes :: proc(rt: Root_Trailer) -> [ROOT_TRAILER_LENGTH]u8 {
1031 | 	buf: [ROOT_TRAILER_LENGTH]u8
1032 | 	slot_bytes := slot_to_bytes(rt.root)  // <== [calls slot_to_bytes]
1033 | 	copy(buf[0:9], slot_bytes[:])
1034 | 	endian.put_u64(buf[9:17], .Big, rt.commit_id)
1035 | 	endian.put_u64(buf[17:25], .Big, rt.checksum)
1036 | 	return buf
1037 | }
```

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 4` (`L1039–L1051`)

```odin
1039 | root_trailer_from_bytes :: proc(buf: [ROOT_TRAILER_LENGTH]u8) -> Root_Trailer {
1040 | 	b := buf
1041 | 	slot_buf: [SLOT_LENGTH]u8
1042 | 	copy(slot_buf[:], b[0:9])
1043 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
1044 | 	commit_id, _ := endian.get_u64(b[9:17], .Big)
1045 | 	checksum, _ := endian.get_u64(b[17:25], .Big)
1046 | 	return Root_Trailer{
1047 | 		checksum  = checksum,
1048 | 		commit_id = commit_id,
1049 | 		root      = root,
1050 | 	}
1051 | }
```

