# #53. `Stream: Cursor_Reader random seek + 64B read` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1727-L1742`)](../bench_xitdb.odin#L1727-L1742) · [Zig Harness (`bench_xitdb.zig#L1856-L1871`)](../bench_xitdb.zig#L1856-L1871)

- **Touched Library Scope:** **5** procedures across **2** `xitdb/*.odin` files (**103** lines of library code)
- **Direct Benchmark Entry Points:** `cursor_reader_seek_to`, `cursor_reader_read_fully`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1727-L1742`)

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

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1856-L1871</code>)</strong></summary>

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
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/cursor.odin` | `cursor_reader_seek_to` | **Entry Point** (`depth 0`) | 7 | [`xitdb/cursor.odin#L506-L512`](../../xitdb/cursor.odin#L506-L512) |
| `xitdb/cursor.odin` | `cursor_reader_read_fully` | **Entry Point** (`depth 0`) | 9 | [`xitdb/cursor.odin#L496-L504`](../../xitdb/cursor.odin#L496-L504) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `cursor_reader_read_fully`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_reader_read_fully`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Stream: Cursor_Reader random seek + 64B read`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/core.odin` (3 procedures · 87 lines: [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359))

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 1` (`L176–L192`)

```odin
 176 | core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
 177 | 	if pos < 0 {
 178 | 		return .Expected_Unsigned_Long
 179 | 	}
 180 | 	switch &v in c {
 181 | 	case Core_Memory:
 182 | 		v.pos = pos
 183 | 		return nil
 184 | 	case Core_File:
 185 | 		os.seek(v.file, pos, .Start) or_return
 186 | 		return nil
 187 | 	case Core_Buffered_File:
 188 | 		v.pos = pos
 189 | 		return nil
 190 | 	}
 191 | 	return .Invalid_Database
 192 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 2` (`L288–L323`)

```odin
 288 | core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
 289 | 	if len(p) == 0 {
 290 | 		return 0, nil
 291 | 	}
 292 | 	switch &v in c {
 293 | 	case Core_Memory:
 294 | 		if v.pos >= i64(len(v.buf)) {
 295 | 			return 0, io.Error.EOF
 296 | 		}
 297 | 		avail := int(i64(len(v.buf)) - v.pos)
 298 | 		to_read := min(len(p), avail)
 299 | 		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
 300 | 		v.pos += i64(to_read)
 301 | 		return to_read, nil
 302 | 	case Core_File:
 303 | 		return os.read(v.file, p)
 304 | 	case Core_Buffered_File:
 305 | 		buf_len := i64(len(v.memory.buf))
 306 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
 307 | 			mem_off := int(v.pos - v.memory_pos)
 308 | 			size := min(len(p), int(buf_len) - mem_off)
 309 | 			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
 310 | 			v.pos += i64(size)
 311 | 			return size, nil
 312 | 		}
 313 | 		os.seek(v.file.file, v.pos, .Start) or_return
 314 | 		max_size := len(p)
 315 | 		if buf_len > 0 && v.pos < v.memory_pos {
 316 | 			max_size = min(len(p), int(v.memory_pos - v.pos))
 317 | 		}
 318 | 		n, err := os.read(v.file.file, p[:max_size])
 319 | 		v.pos += i64(n)
 320 | 		return n, err
 321 | 	}
 322 | 	return 0, .Invalid_Database
 323 | }
```

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 1` (`L326–L359`)

```odin
 326 | core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
 327 | 	if len(p) == 0 {
 328 | 		return nil
 329 | 	}
 330 | 	#partial switch &v in c {
 331 | 	case Core_Memory:
 332 | 		end_pos := v.pos + i64(len(p))
 333 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 334 | 			v.pos = i64(len(v.buf))
 335 | 			return Xitdb_Error.Unexpected_EOF
 336 | 		}
 337 | 		copy(p, v.buf[int(v.pos):int(end_pos)])
 338 | 		v.pos = end_pos
 339 | 		return nil
 340 | 	}
 341 | 	total := 0
 342 | 	for total < len(p) {
 343 | 		n, err := core_read(c, p[total:])  // <== [calls core_read]
 344 | 		total += n
 345 | 		if err != nil {
 346 | 			if err == io.Error.EOF {
 347 | 				if total == len(p) {
 348 | 					return nil
 349 | 				}
 350 | 				return Xitdb_Error.Unexpected_EOF
 351 | 			}
 352 | 			return err
 353 | 		}
 354 | 		if n == 0 {
 355 | 			return Xitdb_Error.Unexpected_EOF
 356 | 		}
 357 | 	}
 358 | 	return nil
 359 | }
```

### `xitdb/cursor.odin` (2 procedures · 16 lines: [`L496–L504`](../../xitdb/cursor.odin#L496-L504), [`L506–L512`](../../xitdb/cursor.odin#L506-L512))

#### [`cursor_reader_read_fully`](../../xitdb/cursor.odin#L496-L504) — `ENTRY POINT` (`L496–L504`)

```odin
 496 | cursor_reader_read_fully :: proc(r: ^Cursor_Reader, buf: []u8) -> Error {
 497 | 	if r.size < r.relative_position || r.size - r.relative_position < i64(len(buf)) {
 498 | 		return .End_Of_Stream
 499 | 	}
 500 | 	core_seek_to(r.parent.db.core, r.start_position + r.relative_position) or_return  // <== [calls core_seek_to]
 501 | 	core_read_exact(r.parent.db.core, buf) or_return  // <== [calls core_read_exact]
 502 | 	r.relative_position += i64(len(buf))
 503 | 	return nil
 504 | }
```

#### [`cursor_reader_seek_to`](../../xitdb/cursor.odin#L506-L512) — `ENTRY POINT` (`L506–L512`)

```odin
 506 | cursor_reader_seek_to :: proc(r: ^Cursor_Reader, position: i64) -> Error {
 507 | 	if position < 0 || position > r.size {
 508 | 		return Xitdb_Error.Invalid_Offset
 509 | 	}
 510 | 	r.relative_position = position
 511 | 	return nil
 512 | }
```

