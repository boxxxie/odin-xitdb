# #50. `Bytes: Tagged External Bytes read_bytes_buf` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1658-L1667`)](../bench_xitdb.odin#L1658-L1667) · [Zig Harness (`bench_xitdb.zig#L1789-L1798`)](../bench_xitdb.zig#L1789-L1798)

- **Touched Library Scope:** **12** procedures across **4** `xitdb/*.odin` files (**238** lines of library code)
- **Direct Benchmark Entry Points:** `cursor_read_bytes_buf`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1658-L1667`)

```odin
1658 | 		t_thp := time.now()
1659 | 		for _ in 0 ..< reads {
1660 | 			obj, _ := xitdb.cursor_read_bytes_buf(t_hp_cur.?, stack_buf[:])
1661 | 			assert(len(obj.value) == 32 && len(obj.format_tag) == 2)
1662 | 		}
1663 | 		print_result(Bench_Result{
1664 | 			name    = "Bytes: Tagged External Bytes read_bytes_buf",
1665 | 			ops     = reads,
1666 | 			elapsed = time.since(t_thp),
1667 | 		})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1789-L1798</code>)</strong></summary>

```zig
1789 |         const t_thp = std.Io.Clock.awake.now(io);
1790 |         for (0..reads) |_| {
1791 |             const obj = try t_hp_cur.readBytesObject(&stack_buf);
1792 |             std.debug.assert(obj.value.len == 32 and obj.format_tag != null);
1793 |         }
1794 |         try printResult(stdout, .{
1795 |             .name = "Bytes: Tagged External Bytes read_bytes_buf",
1796 |             .ops = reads,
1797 |             .elapsed_ns = t_thp.untilNow(io, .awake).nanoseconds,
1798 |         });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
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

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Bytes: Tagged External Bytes read_bytes_buf`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/core.odin` (5 procedures · 118 lines: [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L494–L500`](../../xitdb/core.odin#L494-L500), [`L509–L532`](../../xitdb/core.odin#L509-L532))

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

#### [`core_read_long`](../../xitdb/core.odin#L494-L500) — `DEPTH 1` (`L494–L500`)

```odin
 494 | core_read_long :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 495 | 	res = core_read_i64(c) or_return  // <== [calls core_read_i64]
 496 | 	if res < 0 {
 497 | 		return 0, Xitdb_Error.Expected_Unsigned_Long
 498 | 	}
 499 | 	return res, nil
 500 | }
```

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 2` (`L509–L532`)

```odin
 509 | core_read_i64 :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 510 | 	#partial switch &v in c {
 511 | 	case Core_Memory:
 512 | 		end_pos := v.pos + 8
 513 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 514 | 			v.pos = i64(len(v.buf))
 515 | 			return 0, Xitdb_Error.Unexpected_EOF
 516 | 		}
 517 | 		res = i64(endian.unchecked_get_u64be(v.buf[int(v.pos):int(end_pos)]))
 518 | 		v.pos = end_pos
 519 | 		return res, nil
 520 | 	case Core_Buffered_File:
 521 | 		buf_len := i64(len(v.memory.buf))
 522 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + 8 <= v.memory_pos + buf_len {
 523 | 			mem_off := int(v.pos - v.memory_pos)
 524 | 			res = i64(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
 525 | 			v.pos += 8
 526 | 			return res, nil
 527 | 		}
 528 | 	}
 529 | 	b: [8]u8 = ---
 530 | 	core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
 531 | 	return i64(endian.unchecked_get_u64be(b[:])), nil
 532 | }
```

### `xitdb/cursor.odin` (2 procedures · 78 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L297–L363`](../../xitdb/cursor.odin#L297-L363))

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 1` (`L46–L56`)

```odin
  46 | cursor_resolved :: proc(c: Read_Cursor) -> (res: Slot_Pointer, err: Error) {
  47 | 	if is_root(c.slot_ptr) {  // <== [calls is_root]
  48 | 		header := database_read_root_header(c.db) or_return  // <== [calls database_read_root_header]
  49 | 		if header.file_size < ROOT_TRAILER_LENGTH {
  50 | 			return {}, .Invalid_Database
  51 | 		}
  52 | 		position := header.file_size - ROOT_TRAILER_LENGTH
  53 | 		return Slot_Pointer{position = position, slot = header.root}, nil
  54 | 	}
  55 | 	return c.slot_ptr, nil
  56 | }
```

#### [`cursor_read_bytes_buf`](../../xitdb/cursor.odin#L297-L363) — `ENTRY POINT` (`L297–L363`)

```odin
 297 | cursor_read_bytes_buf :: proc(c: Read_Cursor, buffer: []u8) -> (res: Bytes, err: Error) {
 298 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 299 | 	#partial switch slot_ptr.slot.tag {
 300 | 	case .None:
 301 | 		if len(buffer) == 0 {
 302 | 			return Bytes{value = buffer}, nil
 303 | 		}
 304 | 		return {}, .End_Of_Stream
 305 | 
 306 | 	case .Bytes:
 307 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 308 | 		value_size := core_read_long(c.db.core) or_return  // <== [calls core_read_long]
 309 | 		if value_size > i64(len(buffer)) {
 310 | 			return {}, .Stream_Too_Long
 311 | 		}
 312 | 		if slot_ptr.slot.full {
 313 | 			if value_size + 2 <= i64(len(buffer)) {
 314 | 				combined := buffer[:value_size + 2]
 315 | 				core_read_exact(c.db.core, combined) or_return  // <== [calls core_read_exact]
 316 | 				return Bytes{
 317 | 					value      = combined[:value_size],
 318 | 					format_tag = combined[value_size : value_size + 2],
 319 | 				}, nil
 320 | 			}
 321 | 			value := buffer[:value_size]
 322 | 			core_read_exact(c.db.core, value) or_return  // <== [calls core_read_exact]
 323 | 			ft := make([]u8, 2, context.temp_allocator)
 324 | 			core_read_exact(c.db.core, ft) or_return  // <== [calls core_read_exact]
 325 | 			return Bytes{value = value, format_tag = ft}, nil
 326 | 		}
 327 | 		value := buffer[:value_size]
 328 | 		core_read_exact(c.db.core, value) or_return  // <== [calls core_read_exact]
 329 | 		return Bytes{value = value}, nil
 330 | 
 331 | 	case .Short_Bytes:
 332 | 		buf: [8]u8
 333 | 		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
 334 | 		total_size: i64 = 6 if slot_ptr.slot.full else 8
 335 | 		value_size: i64 = 0
 336 | 		for b in buf {
 337 | 			if b == 0 || value_size == total_size {
 338 | 				break
 339 | 			}
 340 | 			value_size += 1
 341 | 		}
 342 | 		if value_size > i64(len(buffer)) {
 343 | 			return {}, .Stream_Too_Long
 344 | 		}
 345 | 		copy(buffer[:value_size], buf[:value_size])
 346 | 		format_tag: []u8
 347 | 		if slot_ptr.slot.full {
 348 | 			if value_size + 2 <= i64(len(buffer)) {
 349 | 				buffer[value_size] = buf[total_size]
 350 | 				buffer[value_size + 1] = buf[total_size + 1]
 351 | 				format_tag = buffer[value_size : value_size + 2]
 352 | 			} else {
 353 | 				ft := make([]u8, 2, context.temp_allocator)
 354 | 				copy(ft, buf[total_size : total_size + 2])
 355 | 				format_tag = ft
 356 | 			}
 357 | 		}
 358 | 		return Bytes{value = buffer[:value_size], format_tag = format_tag}, nil
 359 | 
 360 | 	case:
 361 | 		return {}, .Unexpected_Tag
 362 | 	}
 363 | }
```

### `xitdb/database.odin` (2 procedures · 14 lines: [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L416–L421`](../../xitdb/database.odin#L416-L421))

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 2` (`L370–L377`)

```odin
 370 | database_read_root_header :: proc(db: ^Database) -> (res: Root_Header, err: Error) {
 371 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 372 | 	b: [ROOT_HEADER_LENGTH]u8
 373 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 374 | 	header := root_header_from_bytes(b)  // <== [calls root_header_from_bytes]
 375 | 	tag_validate(header.root.tag) or_return  // <== [calls tag_validate]
 376 | 	return header, nil
 377 | }
```

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 2` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

### `xitdb/types.odin` (3 procedures · 28 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L993–L1003`](../../xitdb/types.odin#L993-L1003))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 4` (`L880–L890`)

```odin
 880 | slot_from_bytes_raw :: #force_inline proc(buf: [SLOT_LENGTH]u8) -> Slot {
 881 | 	b := buf
 882 | 	full := (b[0] & 0x80) != 0
 883 | 	raw_tag := b[0] & 0x7f
 884 | 	val := endian.unchecked_get_u64be(b[1:9])
 885 | 	return Slot{
 886 | 		value = i64(val),
 887 | 		tag   = Tag(raw_tag),
 888 | 		full  = full,
 889 | 	}
 890 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 3` (`L993–L1003`)

```odin
 993 | root_header_from_bytes :: proc(buf: [ROOT_HEADER_LENGTH]u8) -> Root_Header {
 994 | 	b := buf
 995 | 	slot_buf: [SLOT_LENGTH]u8
 996 | 	copy(slot_buf[:], b[0:9])
 997 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
 998 | 	file_size, _ := endian.get_u64(b[9:17], .Big)
 999 | 	return Root_Header{
1000 | 		file_size = i64(file_size),
1001 | 		root      = root,
1002 | 	}
1003 | }
```

