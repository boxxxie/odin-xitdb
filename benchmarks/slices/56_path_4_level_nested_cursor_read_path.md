# #56. `Path: 4-level nested cursor_read_path` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1832-L1853`)](../bench_xitdb.odin#L1832-L1853) · [Zig Harness (`bench_xitdb.zig#L1951-L1972`)](../bench_xitdb.zig#L1951-L1972)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **142** | 142.2 ± 1.5 | 1.0% | 143.8 | 7,042,254 | - | **5.11x Odin** (`z = 74.3`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 726 | 734.6 ± 17.8 | 2.4% | 757.6 | 1,377,410 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L285-L340`](../../xitdb/cursor.odin#L285-L340)):** On `#48` & `#50` (**4.00x–5.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs separate unbuffered reads (`value_size`, `value`, and `format_tag`).
- **Reallocation-Safe Dynamic `core_slice_at` in `Cursor_Reader` & Pre-Sized Writes (`#51–#53` — 1.51x–8.67x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L527-L629) and [`Cursor_Reader`](../../xitdb/cursor.odin#L430-L523) resolve `core_slice_at` dynamically at each read call (remaining 100% safe across mid-stream buffer reallocations or window shifts) and copy slices directly without vtable chains, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches.
- **Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 4.54x–5.11x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Odin's single-pass `Write_KV_Data` and direct slice reads compound across all 4 levels.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).
- **Resolve `self.parent.db.core.buffer.written()` dynamically inside `Cursor.Reader.stream` (`#52–#53`):** Never cache a slice into `CoreMemory.buffer` when opening `Cursor.Reader` (which dangles if a subsequent write reallocates `CoreMemory.buffer`); instead, slice `written()` dynamically inside `stream`.
- **Apply Guides 01–04:** Batch node I/O, binary search, and single-pass KV writes automatically accelerate `#55–#56` without changing `readSlotPointer`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1832-L1853`](../bench_xitdb.odin#L1832-L1853))

```odin
1832 | 		rc := xitdb.database_root_cursor(&db).read_cursor
1833 | 		skey := transmute([]u8)string("deep-sorted-key")
1834 | 		read_parts := []xitdb.Path_Part{
1835 | 			xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = h_root}},
1836 | 			xitdb.Array_List_Get{index = 0},
1837 | 			xitdb.Linked_Array_List_Get{index = 0},
1838 | 			xitdb.Sorted_Map_Get{target = xitdb.Sorted_Map_Get_Value{key = skey}},
1839 | 		}
1840 | 
1841 | 		t_dr := time.now()
1842 | 		for _ in 0 ..< path_ops {
1843 | 			mc, _ := xitdb.cursor_read_path(rc, read_parts)
1844 | 			v, _ := xitdb.cursor_read_uint(mc.?)
1845 | 			assert(v == u64(path_ops - 1))
1846 | 		}
1847 | 		elapsed_dr := time.since(t_dr)
1848 | 
1849 | 		print_result(Bench_Result{
1850 | 			name    = "Path: 4-level nested cursor_read_path",
1851 | 			ops     = path_ops,
1852 | 			elapsed = elapsed_dr,
1853 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1951-L1972`](../bench_xitdb.zig#L1951-L1972))

```zig
1951 |         const rc = db.rootCursor().readOnly();
1952 |         const skey = "deep-sorted-key";
1953 |         const read_parts = [_]DBSha1.PathPart(void){
1954 |             .{ .hash_map_get = .{ .value = h_root } },
1955 |             .{ .array_list_get = 0 },
1956 |             .{ .linked_array_list_get = 0 },
1957 |             .{ .sorted_map_get = .{ .value = skey } },
1958 |         };
1959 | 
1960 |         const t_dr = std.Io.Clock.awake.now(io);
1961 |         for (0..path_ops) |_| {
1962 |             const mc = (try rc.readPath(void, &read_parts)).?;
1963 |             const v = try mc.readUint();
1964 |             std.debug.assert(v == @as(u64, @intCast(path_ops - 1)));
1965 |         }
1966 |         const elapsed_dr = t_dr.untilNow(io, .awake).nanoseconds;
1967 | 
1968 |         try printResult(stdout, .{
1969 |             .name = "Path: 4-level nested cursor_read_path",
1970 |             .ops = path_ops,
1971 |             .elapsed_ns = elapsed_dr,
1972 |         });
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

### Reached Odin Procedures (`18` procedures across `4` files · `1056` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/cursor.odin` | `cursor_read_path` | **Entry Point** (`depth 0`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L201-L210`](../../xitdb/cursor.odin#L201-L210) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_path`, `cursor_read_uint`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 1` (from `cursor_read_path`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `read_slot_pointer`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 2` (from `read_slot_pointer`) | 24 | [`xitdb/core.odin#L539-L562`](../../xitdb/core.odin#L539-L562) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 2` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
