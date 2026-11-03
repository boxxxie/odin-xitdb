# #48. `Bytes: External Bytes read_bytes_buf` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1629-L1638`)](../bench_xitdb.odin#L1629-L1638) · [Zig Harness (`bench_xitdb.zig#L1754-L1763`)](../bench_xitdb.zig#L1754-L1763)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **9** | 9.0 ± 0.0 | 0.0% | 9.0 | 111,111,111 | - | **4.33x Odin** (`z = 42.4`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 39 | 39.0 ± 1.6 | 4.1% | 40.8 | 25,641,026 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1629-L1638`](../bench_xitdb.odin#L1629-L1638))

```odin
1629 | 		t_hp := time.now()
1630 | 		for _ in 0 ..< reads {
1631 | 			obj, _ := xitdb.cursor_read_bytes_buf(heap_cur.?, stack_buf[:])
1632 | 			assert(len(obj.value) == 32)
1633 | 		}
1634 | 		print_result(Bench_Result{
1635 | 			name    = "Bytes: External Bytes read_bytes_buf",
1636 | 			ops     = reads,
1637 | 			elapsed = time.since(t_hp),
1638 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1754-L1763`](../bench_xitdb.zig#L1754-L1763))

```zig
1754 |         const t_hp = std.Io.Clock.awake.now(io);
1755 |         for (0..reads) |_| {
1756 |             const obj = try heap_cur.readBytesObject(&stack_buf);
1757 |             std.debug.assert(obj.value.len == 32);
1758 |         }
1759 |         try printResult(stdout, .{
1760 |             .name = "Bytes: External Bytes read_bytes_buf",
1761 |             .ops = reads,
1762 |             .elapsed_ns = t_hp.untilNow(io, .awake).nanoseconds,
1763 |         });
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

### Reached Odin Procedures (`12` procedures across `4` files · `238` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_read_bytes_buf` | **Entry Point** (`depth 0`) | 67 | [`xitdb/cursor.odin#L297-L363`](../../xitdb/cursor.odin#L297-L363) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_bytes_buf`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_read_bytes_buf`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_long` | `depth 1` (from `cursor_read_bytes_buf`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_read_bytes_buf`, `database_read_root_header`, `core_read_i64`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read_i64` | `depth 2` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
