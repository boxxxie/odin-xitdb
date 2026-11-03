# #56. `Path: 4-level nested cursor_read_path` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1832-L1853`)](../bench_xitdb.odin#L1832-L1853) · [Zig Harness (`bench_xitdb.zig#L1951-L1972`)](../bench_xitdb.zig#L1951-L1972)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **148** | 147.6 ± 4.2 | 2.8% | 151.6 | 6,756,757 | - | **8.74x Odin** (`z = 242.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,293 | 1,293.0 ± 9.7 | 0.8% | 1,305.4 | 773,395 | - | Baseline |

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
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`18` procedures across `4` files · `1049` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/cursor.odin` | `cursor_read_path` | **Entry Point** (`depth 0`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_path`, `cursor_read_uint`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 1` (from `cursor_read_path`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_read_root_slot`, `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `read_slot_pointer`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 2` (from `read_slot_pointer`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 2` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
