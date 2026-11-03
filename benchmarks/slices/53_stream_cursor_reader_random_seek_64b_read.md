# #53. `Stream: Cursor_Reader random seek + 64B read` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1727-L1742`)](../bench_xitdb.odin#L1727-L1742) · [Zig Harness (`bench_xitdb.zig#L1856-L1871`)](../bench_xitdb.zig#L1856-L1871)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **6** | 6.4 ± 0.9 | 14.0% | 7.6 | 166,666,667 | - | **4.67x Odin** (`z = 48.7`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 28 | 28.2 ± 0.4 | 1.6% | 28.8 | 35,714,286 | - | Baseline |

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
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`5` procedures across `2` files · `103` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader_seek_to` | **Entry Point** (`depth 0`) | 7 | [`xitdb/cursor.odin#L506-L512`](../../xitdb/cursor.odin#L506-L512) |
| `xitdb/cursor.odin` | `cursor_reader_read_fully` | **Entry Point** (`depth 0`) | 9 | [`xitdb/cursor.odin#L496-L504`](../../xitdb/cursor.odin#L496-L504) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_reader_read_fully`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_reader_read_fully`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
