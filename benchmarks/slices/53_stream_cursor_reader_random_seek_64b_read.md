# #53. `Stream: Cursor_Reader random seek + 64B read` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1727-L1742`)](../bench_xitdb.odin#L1727-L1742) · [Zig Harness (`bench_xitdb.zig#L1856-L1871`)](../bench_xitdb.zig#L1856-L1871)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **3** | 3.0 ± 0.0 | 0.0% | 3.0 | 333,333,333 | - | **9.33x Odin** (`z = 126.0`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 28 | 28.2 ± 0.4 | 1.6% | 28.8 | 35,714,286 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1727-L1742`](../bench_xitdb.odin#L1727-L1742))

```odin
1727 | 		// Random-access seek + 64B read across the 1 MB blob (`cursor_reader_seek_to`)
1728 | 		seek_ops := n
1729 | 		small_buf: [64]u8
1730 | 		t_rseek := time.now()
1731 | 		for i in 0 ..< seek_ops {
1732 | 			off := i64((i * 4099) % (chunks_count * 4096 - 64))
1733 | 			_ = xitdb.cursor_reader_seek_to(&reader, off)
1734 | 			_ = xitdb.cursor_reader_read_fully(&reader, small_buf[:])
1735 | 		}
1736 | 		elapsed_rseek := time.since(t_rseek)
1737 | 
1738 | 		print_result(Bench_Result{
1739 | 			name    = "Stream: Cursor_Reader random seek + 64B read",
1740 | 			ops     = seek_ops,
1741 | 			elapsed = elapsed_rseek,
1742 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1856-L1871`](../bench_xitdb.zig#L1856-L1871))

```zig
1856 |         // Random-access seek + 64B read across the 1 MB blob (`cursor_reader_seek_to`)
1857 |         const seek_ops = n;
1858 |         var small_buf: [64]u8 = undefined;
1859 |         const t_rseek = std.Io.Clock.awake.now(io);
1860 |         for (0..seek_ops) |i| {
1861 |             const off: u64 = @intCast((i * 4099) % (chunks_count * 4096 - 64));
1862 |             try reader.seekTo(off);
1863 |             try reader.interface.readSliceAll(&small_buf);
1864 |         }
1865 |         const elapsed_rseek = t_rseek.untilNow(io, .awake).nanoseconds;
1866 | 
1867 |         try printResult(stdout, .{
1868 |             .name = "Stream: Cursor_Reader random seek + 64B read",
1869 |             .ops = seek_ops,
1870 |             .elapsed_ns = elapsed_rseek,
1871 |         });
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

### Reached Odin Procedures (`5` procedures across `2` files · `111` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader_seek_to` | **Entry Point** (`depth 0`) | 7 | [`xitdb/cursor.odin#L538-L544`](../../xitdb/cursor.odin#L538-L544) |
| `xitdb/cursor.odin` | `cursor_reader_read_fully` | **Entry Point** (`depth 0`) | 17 | [`xitdb/cursor.odin#L520-L536`](../../xitdb/cursor.odin#L520-L536) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_reader_read_fully`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_reader_read_fully`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
