# #54. `Stream: Cursor_Writer random seek + 16B patch` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1744-L1774`)](../bench_xitdb.odin#L1744-L1774) · [Zig Harness (`bench_xitdb.zig#L1873-L1900`)](../bench_xitdb.zig#L1873-L1900)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **13** | 13.4 ± 0.5 | 4.1% | 14.0 | 76,923,077 | - | **2.15x Odin** (`z = 43.3`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 28 | 28.4 ± 0.5 | 1.9% | 29.0 | 35,714,286 | - | Baseline |

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
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`54` procedures across `4` files · `881` LOC) (Active `_exec_path_part` arms: `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_writer` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L558-L577`](../../xitdb/cursor.odin#L558-L577) |
| `xitdb/cursor.odin` | `cursor_writer_write` | **Entry Point** (`depth 0`) | 20 | [`xitdb/cursor.odin#L593-L612`](../../xitdb/cursor.odin#L593-L612) |
| `xitdb/cursor.odin` | `cursor_writer_seek_to` | **Entry Point** (`depth 0`) | 7 | [`xitdb/cursor.odin#L614-L620`](../../xitdb/cursor.odin#L614-L620) |
| `xitdb/cursor.odin` | `cursor_writer_finish` | **Entry Point** (`depth 0`) | 30 | [`xitdb/cursor.odin#L622-L651`](../../xitdb/cursor.odin#L622-L651) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L301-L305`](../../xitdb/database.odin#L301-L305) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 1` (from `cursor_writer`, `cursor_writer_check_writable`, `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 1` (from `cursor_writer`, `cursor_check_writable`, `cursor_write_path`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `cursor_writer`, `cursor_writer_write`, `cursor_writer_finish`) | 21 | [`xitdb/core.odin#L153-L173`](../../xitdb/core.odin#L153-L173) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_writer`, `cursor_writer_write`, `cursor_writer_finish`) | 17 | [`xitdb/core.odin#L175-L191`](../../xitdb/core.odin#L175-L191) |
| `xitdb/core.odin` | `core_write_long` | `depth 1` (from `cursor_writer`, `cursor_writer_finish`) | 6 | [`xitdb/core.odin#L481-L486`](../../xitdb/core.odin#L481-L486) |
| `xitdb/cursor.odin` | `cursor_writer_check_writable` | `depth 1` (from `cursor_writer_write`, `cursor_writer_finish`) | 13 | [`xitdb/cursor.odin#L579-L591`](../../xitdb/cursor.odin#L579-L591) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `cursor_writer_write`, `cursor_writer_finish`, `core_write_slot`) | 55 | [`xitdb/core.odin#L362-L416`](../../xitdb/core.odin#L362-L416) |
| `xitdb/types.odin` | `slot_with_full` | `depth 1` (from `cursor_writer_finish`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/core.odin` | `core_write_slot` | `depth 1` (from `cursor_writer_finish`, `read_slot_pointer`) | 18 | [`xitdb/core.odin#L562-L579`](../../xitdb/core.odin#L562-L579) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 1` (from `cursor_writer_finish`, `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `cursor_writer_finish`, `cursor_write_path`, `_database_truncate_with_header`) | 18 | [`xitdb/core.odin#L218-L235`](../../xitdb/core.odin#L218-L235) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `database_run_context`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 2` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_write_i64` | `depth 2` (from `core_write_long`) | 17 | [`xitdb/core.odin#L513-L529`](../../xitdb/core.odin#L513-L529) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 2` (from `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L143-L151`](../../xitdb/core.odin#L143-L151) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L124-L141`](../../xitdb/core.odin#L124-L141) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `core_write_slot`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 3` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `database_read_root_slot`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L556-L560`](../../xitdb/core.odin#L556-L560) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L531-L554`](../../xitdb/core.odin#L531-L554) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `database_read_root_header`, `core_read_slot_raw`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`, `core_read_slot`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L237-L278`](../../xitdb/core.odin#L237-L278) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L281-L323`](../../xitdb/core.odin#L281-L323) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
