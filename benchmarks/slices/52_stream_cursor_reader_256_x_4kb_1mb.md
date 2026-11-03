# #52. `Stream: Cursor_Reader (256 x 4KB = 1MB)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1709-L1725`)](../bench_xitdb.odin#L1709-L1725) · [Zig Harness (`bench_xitdb.zig#L1838-L1854`)](../bench_xitdb.zig#L1838-L1854)

- **Touched Library Scope:** **14** procedures across **4** `xitdb/*.odin` files (**233** lines of library code)
- **Direct Benchmark Entry Points:** `cursor_reader`, `cursor_reader_read`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1709-L1725`)

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

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1838-L1854</code>)</strong></summary>

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
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
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

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Stream: Cursor_Reader (256 x 4KB = 1MB)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/core.odin` (6 procedures · 129 lines: [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L194–L204`](../../xitdb/core.odin#L194-L204), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L494–L500`](../../xitdb/core.odin#L494-L500), [`L509–L532`](../../xitdb/core.odin#L509-L532))

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

#### [`core_position`](../../xitdb/core.odin#L194-L204) — `DEPTH 1` (`L194–L204`)

```odin
 194 | core_position :: proc(c: ^Core) -> (pos: i64, err: Error) {
 195 | 	switch &v in c {
 196 | 	case Core_Memory:
 197 | 		return v.pos, nil
 198 | 	case Core_File:
 199 | 		return os.seek(v.file, 0, .Current)
 200 | 	case Core_Buffered_File:
 201 | 		return v.pos, nil
 202 | 	}
 203 | 	return 0, .Invalid_Database
 204 | }
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

### `xitdb/cursor.odin` (3 procedures · 62 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L443–L480`](../../xitdb/cursor.odin#L443-L480), [`L482–L494`](../../xitdb/cursor.odin#L482-L494))

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

#### [`cursor_reader`](../../xitdb/cursor.odin#L443-L480) — `ENTRY POINT` (`L443–L480`)

```odin
 443 | cursor_reader :: proc(c: Read_Cursor) -> (res: Cursor_Reader, err: Error) {
 444 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 445 | 	#partial switch slot_ptr.slot.tag {
 446 | 	case .Bytes:
 447 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 448 | 		size := core_read_long(c.db.core) or_return  // <== [calls core_read_long]
 449 | 		start_position := core_position(c.db.core) or_return  // <== [calls core_position]
 450 | 		return Cursor_Reader{
 451 | 			parent            = c,
 452 | 			size              = size,
 453 | 			start_position    = start_position,
 454 | 			relative_position = 0,
 455 | 		}, nil
 456 | 	case .Short_Bytes:
 457 | 		buf: [8]u8
 458 | 		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
 459 | 		total_size := 6 if slot_ptr.slot.full else 8
 460 | 		value_size := 0
 461 | 		for b in buf {
 462 | 			if b == 0 || value_size == total_size {
 463 | 				break
 464 | 			}
 465 | 			value_size += 1
 466 | 		}
 467 | 		pos, ok := slot_ptr.position.?
 468 | 		if !ok {
 469 | 			return {}, .Expected_Slot_Position
 470 | 		}
 471 | 		return Cursor_Reader{
 472 | 			parent            = c,
 473 | 			size              = i64(value_size),
 474 | 			start_position    = pos + 1,
 475 | 			relative_position = 0,
 476 | 		}, nil
 477 | 	case:
 478 | 		return {}, .Unexpected_Tag
 479 | 	}
 480 | }
```

#### [`cursor_reader_read`](../../xitdb/cursor.odin#L482-L494) — `ENTRY POINT` (`L482–L494`)

```odin
 482 | cursor_reader_read :: proc(r: ^Cursor_Reader, p: []u8) -> (res: int, err: Error) {
 483 | 	if r.size < r.relative_position {
 484 | 		return 0, .End_Of_Stream
 485 | 	}
 486 | 	core_seek_to(r.parent.db.core, r.start_position + r.relative_position) or_return  // <== [calls core_seek_to]
 487 | 	read_size := min(i64(len(p)), r.size - r.relative_position)
 488 | 	if read_size == 0 {
 489 | 		return 0, nil
 490 | 	}
 491 | 	core_read_exact(r.parent.db.core, p[:read_size]) or_return  // <== [calls core_read_exact]
 492 | 	r.relative_position += read_size
 493 | 	return int(read_size), nil
 494 | }
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

