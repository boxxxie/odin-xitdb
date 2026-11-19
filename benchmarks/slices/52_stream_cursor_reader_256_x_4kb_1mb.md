# #52. `Stream: Cursor_Reader (256 x 4KB = 1MB)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1755-L1771`)](../bench_xitdb.odin#L1755-L1771) · [Zig Harness (`bench_xitdb.zig#L1838-L1854`)](../bench_xitdb.zig#L1838-L1854)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **108** | 109.4 ± 14.6 | 13.3% | 128.8 | 9,259,259 | - | **1.68x Odin** (`z = 2.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 181 | 217.0 ± 85.7 | 39.5% | 332.79999999999995 | 5,524,862 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L298-L364`](../../xitdb/cursor.odin#L298-L364)):** On `#48` & `#50` (**4.00x–5.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs separate unbuffered reads (`value_size`, `value`, and `format_tag`).
- **Reallocation-Safe Dynamic `core_slice_at` in `Cursor_Reader` & Pre-Sized Writes (`#51–#53` — 1.51x–8.67x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L549-L651) and [`Cursor_Reader`](../../xitdb/cursor.odin#L437-L545) resolve `core_slice_at` dynamically at each read call (remaining 100% safe across mid-stream buffer reallocations or window shifts) and copy slices directly without vtable chains, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches.
- **Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 4.69x–4.91x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Odin's single-pass `Write_KV_Data` and direct slice reads compound across all 4 levels.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).
- **Resolve `self.parent.db.core.buffer.written()` dynamically inside `Cursor.Reader.stream` (`#52–#53`):** Never cache a slice into `CoreMemory.buffer` when opening `Cursor.Reader` (which dangles if a subsequent write reallocates `CoreMemory.buffer`); instead, slice `written()` dynamically inside `stream`.
- **Apply Guides 01–04:** Batch node I/O, binary search, and single-pass KV writes automatically accelerate `#55–#56` without changing `readSlotPointer`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1755-L1771`](../bench_xitdb.odin#L1755-L1771))

```odin
1755 | 		t_sr := time.now()
1756 | 		reader, _ := xitdb.cursor_reader(sctx.blob_rc)
1757 | 		read_buf: [4096]u8
1758 | 		read_chunks := 0
1759 | 		for {
1760 | 			nr, _ := xitdb.cursor_reader_read(&reader, read_buf[:])
1761 | 			if nr == 0 do break
1762 | 			read_chunks += 1
1763 | 		}
1764 | 		assert(read_chunks == chunks_count)
1765 | 		elapsed_sr := time.since(t_sr)
1766 | 
1767 | 		print_result(Bench_Result{
1768 | 			name    = "Stream: Cursor_Reader (256 x 4KB = 1MB)",
1769 | 			ops     = chunks_count,
1770 | 			elapsed = elapsed_sr,
1771 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1838-L1854`](../bench_xitdb.zig#L1838-L1854))

```zig
1838 |         const t_sr = std.Io.Clock.awake.now(io);
1839 |         var reader = try blob_rc.reader(&.{});
1840 |         var read_buf: [4096]u8 = undefined;
1841 |         var read_chunks: usize = 0;
1842 |         while (true) {
1843 |             const nr = try reader.interface.readSliceShort(&read_buf);
1844 |             if (nr == 0) break;
1845 |             read_chunks += 1;
1846 |         }
1847 |         std.debug.assert(read_chunks == chunks_count);
1848 |         const elapsed_sr = t_sr.untilNow(io, .awake).nanoseconds;
1849 | 
1850 |         try printResult(stdout, .{
1851 |             .name = "Stream: Cursor_Reader (256 x 4KB = 1MB)",
1852 |             .ops = chunks_count,
1853 |             .elapsed_ns = elapsed_sr,
1854 |         });
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

### Reached Odin Procedures (`21` procedures across `4` files · `400` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader` | **Entry Point** (`depth 0`) | 49 | [`xitdb/cursor.odin#L483-L531`](../../xitdb/cursor.odin#L483-L531) |
| `xitdb/cursor.odin` | `cursor_reader_read` | **Entry Point** (`depth 0`) | 23 | [`xitdb/cursor.odin#L533-L555`](../../xitdb/cursor.odin#L533-L555) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_reader`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 1` (from `cursor_reader`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `cursor_reader`, `database_read_root_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/core.odin` | `core_slice_at` | `depth 1` (from `cursor_reader_read`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 1` (from `cursor_reader_read`, `core_read_i64_at`, `database_read_root_trailer`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `core_read_long_at`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_slice_at`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 2` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/core.odin` | `core_read_at` | `depth 2` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 3` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 3` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
