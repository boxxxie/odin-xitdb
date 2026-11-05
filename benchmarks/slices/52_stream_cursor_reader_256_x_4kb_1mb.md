# #52. `Stream: Cursor_Reader (256 x 4KB = 1MB)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1709-L1725`)](../bench_xitdb.odin#L1709-L1725) · [Zig Harness (`bench_xitdb.zig#L1838-L1854`)](../bench_xitdb.zig#L1838-L1854)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **51** | 51.0 ± 1.0 | 2.0% | 52.0 | 19,607,843 | - | **1.51x Odin** (`z = 10.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 77 | 76.0 ± 5.4 | 7.1% | 82.6 | 12,987,013 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1709-L1725`](../bench_xitdb.odin#L1709-L1725))

```odin
1709 | 		t_sr := time.now()
1710 | 		reader, _ := xitdb.cursor_reader(sctx.blob_rc)
1711 | 		read_buf: [4096]u8
1712 | 		read_chunks := 0
1713 | 		for {
1714 | 			nr, _ := xitdb.cursor_reader_read(&reader, read_buf[:])
1715 | 			if nr == 0 do break
1716 | 			read_chunks += 1
1717 | 		}
1718 | 		assert(read_chunks == chunks_count)
1719 | 		elapsed_sr := time.since(t_sr)
1720 | 
1721 | 		print_result(Bench_Result{
1722 | 			name    = "Stream: Cursor_Reader (256 x 4KB = 1MB)",
1723 | 			ops     = chunks_count,
1724 | 			elapsed = elapsed_sr,
1725 | 		})
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

### Reached Odin Procedures (`15` procedures across `4` files · `266` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader` | **Entry Point** (`depth 0`) | 39 | [`xitdb/cursor.odin#L444-L482`](../../xitdb/cursor.odin#L444-L482) |
| `xitdb/cursor.odin` | `cursor_reader_read` | **Entry Point** (`depth 0`) | 21 | [`xitdb/cursor.odin#L484-L504`](../../xitdb/cursor.odin#L484-L504) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_reader`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_reader`, `cursor_reader_read`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_long` | `depth 1` (from `cursor_reader`) | 7 | [`xitdb/core.odin#L488-L494`](../../xitdb/core.odin#L488-L494) |
| `xitdb/core.odin` | `core_position` | `depth 1` (from `cursor_reader`) | 11 | [`xitdb/core.odin#L194-L204`](../../xitdb/core.odin#L194-L204) |
| `xitdb/core.odin` | `core_slice_at` | `depth 1` (from `cursor_reader_read`) | 17 | [`xitdb/core.odin#L435-L451`](../../xitdb/core.odin#L435-L451) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_reader_read`, `database_read_root_header`, `core_read_i64`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/core.odin` | `core_read_i64` | `depth 2` (from `core_read_long`) | 24 | [`xitdb/core.odin#L503-L526`](../../xitdb/core.odin#L503-L526) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
