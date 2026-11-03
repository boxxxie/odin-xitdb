# #54. `Stream: Cursor_Writer random seek + 16B patch` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1744-L1774`)](../bench_xitdb.odin#L1744-L1774) · [Zig Harness (`bench_xitdb.zig#L1873-L1900`)](../bench_xitdb.zig#L1873-L1900)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **13** | 13.2 ± 0.4 | 3.4% | 13.8 | 76,923,077 | - | **2.31x Odin** (`z = 6.4`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 30 | 34.4 ± 7.4 | 21.4% | 44.599999999999994 | 33,333,333 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Zero-Allocation `read_bytes_buf` Fast Path ([`xitdb/cursor.odin#L260-L355`](../../xitdb/cursor.odin#L260-L355)):** On `#47–#50` (**1.33x–6.33x faster in Odin**), Odin's `cursor_read_bytes_buf` decodes inline `.Short_Bytes` directly from the 64-bit `Slot.value` register and reads external `.Bytes` directly into the caller's slice with one `core_read_exact`. Zig's [`Cursor.readBytes`](../../reference/xitdb-zig/src/lib.zig#L3150-L3190) constructs a `Cursor.Reader` and streams through the `std.Io.Reader` vtable.
- **Direct Bulk Write in `Cursor_Writer` (`#51` — 5.81x faster in Odin: `288 µs` vs `1,674 µs`):** Odin's [`cursor_writer_write`](../../xitdb/cursor.odin#L905-L945) appends the caller's 4 KB chunk directly to `db.core` in one `core_write_all` call and writes the final 8-byte big-endian size header once in `cursor_writer_finish`. Zig's [`Cursor.Writer.drain`](../../reference/xitdb-zig/src/lib.zig#L3680-L3745) uses a 256-byte `std.Io.Writer` buffer and, on every 256-byte flush, seeks to the payload end, writes 256 bytes, and seeks back to `size_pos` to rewrite the 8-byte length header (**32 seeks + 32 writes per 4 KB chunk**).
- **Stack-Sliced Path Traversal ([`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619)):** On `#55–#56` 4-level nested path traversal (**6.73x–8.74x faster in Odin**), Odin's `read_slot_pointer` + single-pass `Write_KV_Data` avoids per-level `std.Io` reader/writer re-initialization.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Defer length-header patching in `Cursor.Writer.drain` ([`lib.zig#L3680-L3745`](../../reference/xitdb-zig/src/lib.zig#L3680-L3745)):** Write incoming chunks directly to `core.writer()` at `self.pos` and update the 8-byte length header at `self.size_pos` only in `finish()` (or when `seekTo` is called), eliminating 30+ redundant seeks per 4 KB write.
- **Use `std.Io.Reader.fixed` for `CoreMemory` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Removes the intermediate 256-byte copy during `readBytes` and `Cursor.Reader` seeks.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1744-L1774`](../bench_xitdb.odin#L1744-L1774))

```odin
1744 | 		// Random-access in-place patch via `cursor_writer_seek_to`
1745 | 		Patch_Ctx :: struct {
1746 | 			ops: int,
1747 | 		}
1748 | 		pctx := Patch_Ctx{ops = seek_ops}
1749 | 
1750 | 		stream_patch_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1751 | 			c := (^Patch_Ctx)(user_data)
1752 | 			w := xitdb.cursor_writer(cursor) or_return
1753 | 			init_buf: [65536]u8
1754 | 			_, _ = xitdb.cursor_writer_write(&w, init_buf[:])
1755 | 			patch: [16]u8
1756 | 			for i in 0 ..< c.ops {
1757 | 				off := i64((i * 1031) % (65536 - 16))
1758 | 				xitdb.cursor_writer_seek_to(&w, off) or_return
1759 | 				patch[0] = u8(i)
1760 | 				_, err := xitdb.cursor_writer_write(&w, patch[:])
1761 | 				if err != nil do return err
1762 | 			}
1763 | 			return xitdb.cursor_writer_finish(&w)
1764 | 		}
1765 | 
1766 | 		t_wseek := time.now()
1767 | 		_ = xitdb.database_run_context(&db, stream_patch_cb, &pctx)
1768 | 		elapsed_wseek := time.since(t_wseek)
1769 | 
1770 | 		print_result(Bench_Result{
1771 | 			name    = "Stream: Cursor_Writer random seek + 16B patch",
1772 | 			ops     = seek_ops,
1773 | 			elapsed = elapsed_wseek,
1774 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1873-L1900`](../bench_xitdb.zig#L1873-L1900))

```zig
1873 |         // Random-access in-place patch via `cursor_writer_seek_to`
1874 |         const StreamPatchCtx = struct {
1875 |             ops: usize,
1876 | 
1877 |             pub fn run(self: @This(), cursor: *DBSha1.Cursor(.read_write)) !void {
1878 |                 var w = try cursor.writer(&.{});
1879 |                 const init_buf: [65536]u8 = @splat(0);
1880 |                 try w.interface.writeAll(&init_buf);
1881 |                 var patch: [16]u8 = @splat(0);
1882 |                 for (0..self.ops) |i| {
1883 |                     const off: u64 = @intCast((i * 1031) % (65536 - 16));
1884 |                     try w.seekTo(off);
1885 |                     patch[0] = @intCast(i & 0xFF);
1886 |                     try w.interface.writeAll(&patch);
1887 |                 }
1888 |                 try w.finish();
1889 |             }
1890 |         };
1891 | 
1892 |         const t_wseek = std.Io.Clock.awake.now(io);
1893 |         try db.runContext(StreamPatchCtx{ .ops = seek_ops });
1894 |         const elapsed_wseek = t_wseek.untilNow(io, .awake).nanoseconds;
1895 | 
1896 |         try printResult(stdout, .{
1897 |             .name = "Stream: Cursor_Writer random seek + 16B patch",
1898 |             .ops = seek_ops,
1899 |             .elapsed_ns = elapsed_wseek,
1900 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |
| `readSlotPointer.write` | 66 | `PathPart` switch arms: `.write` and `.ctx` | [`lib.zig#L1525-L1590`](../../reference/xitdb-zig/src/lib.zig#L1525-L1590) |
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`54` procedures across `4` files · `901` LOC) (Active `_exec_path_part` arms: `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_writer` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L536-L555`](../../xitdb/cursor.odin#L536-L555) |
| `xitdb/cursor.odin` | `cursor_writer_write` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L571-L590`](../../xitdb/cursor.odin#L571-L590) |
| `xitdb/cursor.odin` | `cursor_writer_seek_to` | **Entry Point** (`depth 0`) | 7 | [`xitdb/cursor.odin#L592-L598`](../../xitdb/cursor.odin#L592-L598) |
| `xitdb/cursor.odin` | `cursor_writer_finish` | **Entry Point** (`depth 0`) | 30 | [`xitdb/cursor.odin#L600-L629`](../../xitdb/cursor.odin#L600-L629) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 1` (from `cursor_writer`, `cursor_writer_check_writable`, `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 1` (from `cursor_writer`, `cursor_check_writable`, `cursor_write_path`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `cursor_writer`, `cursor_writer_write`, `cursor_writer_finish`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_writer`, `cursor_writer_write`, `cursor_writer_finish`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_write_long` | `depth 1` (from `cursor_writer`, `cursor_writer_finish`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/cursor.odin` | `cursor_writer_check_writable` | `depth 1` (from `cursor_writer_write`, `cursor_writer_finish`) | 13 | [`xitdb/cursor.odin#L557-L569`](../../xitdb/cursor.odin#L557-L569) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `cursor_writer_write`, `cursor_writer_finish`, `core_write_slot`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/types.odin` | `slot_with_full` | `depth 1` (from `cursor_writer_finish`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/core.odin` | `core_write_slot` | `depth 1` (from `cursor_writer_finish`, `read_slot_pointer`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 1` (from `cursor_writer_finish`, `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `cursor_writer_finish`, `cursor_write_path`, `_database_truncate_with_header`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `database_run_context`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 2` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_write_i64` | `depth 2` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 2` (from `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `core_write_slot`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 3` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `database_read_root_header`, `core_read_slot_raw`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`, `core_read_slot`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
