# #52. `Stream: Cursor_Reader (256 x 4KB = 1MB)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1709-L1725`)](../bench_xitdb.odin#L1709-L1725) · [Zig Harness (`bench_xitdb.zig#L1838-L1854`)](../bench_xitdb.zig#L1838-L1854)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **52** | 52.6 ± 0.9 | 1.7% | 53.8 | 19,230,769 | - | **1.60x Odin** (`z = 29.7`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 83 | 82.6 ± 2.1 | 2.5% | 84.0 | 12,048,193 | - | Baseline |

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
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`14` procedures across `4` files · `233` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader` | **Entry Point** (`depth 0`) | 38 | [`xitdb/cursor.odin#L443-L480`](../../xitdb/cursor.odin#L443-L480) |
| `xitdb/cursor.odin` | `cursor_reader_read` | **Entry Point** (`depth 0`) | 13 | [`xitdb/cursor.odin#L482-L494`](../../xitdb/cursor.odin#L482-L494) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_reader`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_reader`, `cursor_reader_read`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_long` | `depth 1` (from `cursor_reader`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/core.odin` | `core_position` | `depth 1` (from `cursor_reader`) | 11 | [`xitdb/core.odin#L194-L204`](../../xitdb/core.odin#L194-L204) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_reader_read`, `database_read_root_header`, `core_read_i64`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read_i64` | `depth 2` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
