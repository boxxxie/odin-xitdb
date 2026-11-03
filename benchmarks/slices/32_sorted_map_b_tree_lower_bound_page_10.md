# #32. `Sorted_Map (B+Tree) lower-bound page(10)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1197-L1212`)](../bench_xitdb.odin#L1197-L1212) · [Zig Harness (`bench_xitdb.zig#L1221-L1235`)](../bench_xitdb.zig#L1221-L1235)

- **Touched Library Scope:** **27** procedures across **6** `xitdb/*.odin` files (**528** lines of library code)
- **Direct Benchmark Entry Points:** `sorted_map_iterator_from_string`, `cursor_iterator_next`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1197-L1212`)

```odin
1197 | 	// 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
1198 | 	t4 := time.now()
1199 | 	for k in keys {
1200 | 		rit, _ := xitdb.sorted_map_iterator_from_string(sm, k)
1201 | 		for _ in 0 ..< 10 {
1202 | 			c_maybe, _ := xitdb.cursor_iterator_next(&rit)
1203 | 			if c_maybe == nil do break
1204 | 		}
1205 | 	}
1206 | 	elapsed_range_seek := time.since(t4)
1207 | 
1208 | 	print_result(Bench_Result{
1209 | 		name    = "Sorted_Map (B+Tree) lower-bound page(10)",
1210 | 		ops     = n,
1211 | 		elapsed = elapsed_range_seek,
1212 | 	})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1221-L1235</code>)</strong></summary>

```zig
1221 |     // 3b. Lower-bound range seek (`sorted_map_iterator_from_string`) + 10-item page read
1222 |     const t4 = std.Io.Clock.awake.now(io);
1223 |     for (keys) |k| {
1224 |         var rit = try sm.iteratorFrom(k);
1225 |         for (0..10) |_| {
1226 |             if ((try rit.next()) == null) break;
1227 |         }
1228 |     }
1229 |     const elapsed_range_seek = t4.untilNow(io, .awake).nanoseconds;
1230 | 
1231 |     try printResult(stdout, .{
1232 |         .name = "Sorted_Map (B+Tree) lower-bound page(10)",
1233 |         .ops = n,
1234 |         .elapsed_ns = elapsed_range_seek,
1235 |     });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_iterator_from_string` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L702-L704`](../../xitdb/collections.odin#L702-L704) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_key` | `depth 1` (from `sorted_map_iterator_from_string`) | 98 | [`xitdb/cursor.odin#L852-L949`](../../xitdb/cursor.odin#L852-L949) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 12 | [`xitdb/cursor.odin#L779-L790`](../../xitdb/cursor.odin#L779-L790) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator_sorted_from_key`, `_sorted_header`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator_sorted_from_key`, `_sorted_header`, `compare_key`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 2` (from `cursor_iterator_sorted_from_key`, `_init_btree_iter_level`, `core_read_slot_raw`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 2` (from `cursor_iterator_sorted_from_key`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 3` (from `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `_sorted_header`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 3` (from `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/core.odin` | `core_slice_at` | `depth 3` (from `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `sorted_entry_key_slot`, `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `sorted_entry_key_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/core.odin` | `core_read_i64` | `depth 3` (from `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/database.odin` | `is_root` | `depth 4` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 4` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `_fill_slot_block_from`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 5` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Sorted_Map (B+Tree) lower-bound page(10)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/btree.odin` (2 procedures · 73 lines: [`L1129–L1141`](../../xitdb/btree.odin#L1129-L1141), [`L1150–L1209`](../../xitdb/btree.odin#L1150-L1209))

#### [`sorted_entry_key_slot`](../../xitdb/btree.odin#L1129-L1141) — `DEPTH 2` (`L1129–L1141`)

```odin
1129 | sorted_entry_key_slot :: #force_inline proc(db: ^Database, entry: Slot) -> (res: Slot, err: Error) {
1130 | 	if is_key_only_entry(entry) {  // <== [calls is_key_only_entry]
1131 | 		return entry, nil
1132 | 	}
1133 | 	if s_slice, in_mem, slice_err := core_slice_at(db.core, entry.value, SLOT_LENGTH); in_mem {  // <== [calls core_slice_at]
1134 | 		if slice_err != nil {
1135 | 			return {}, slice_err
1136 | 		}
1137 | 		return slot_from_slice_raw(s_slice), nil  // <== [calls slot_from_slice_raw]
1138 | 	}
1139 | 	core_seek_to(db.core, entry.value) or_return  // <== [calls core_seek_to]
1140 | 	return core_read_slot_raw(db.core)  // <== [calls core_read_slot_raw]
1141 | }
```

#### [`compare_key`](../../xitdb/btree.odin#L1150-L1209) — `DEPTH 2` (`L1150–L1209`)

```odin
1150 | compare_key :: proc(db: ^Database, key_slot: Slot, target: []u8) -> (res: int, err: Error) {
1151 | 	#partial switch key_slot.tag {
1152 | 	case .Short_Bytes:
1153 | 		buf: [8]u8 = ---
1154 | 		endian.unchecked_put_u64be(buf[:], u64(key_slot.value))
1155 | 		total := 6 if key_slot.full else 8
1156 | 		length := total
1157 | 		for i in 0 ..< total {
1158 | 			if buf[i] == 0 {
1159 | 				length = i
1160 | 				break
1161 | 			}
1162 | 		}
1163 | 		return bytes.compare(buf[:length], target), nil
1164 | 	case .Bytes:
1165 | 		#partial switch &v in db.core {
1166 | 		case Core_Memory:
1167 | 			pos := int(key_slot.value)
1168 | 			if pos < 0 || pos + 8 > len(v.buf) {
1169 | 				return 0, Xitdb_Error.Unexpected_EOF
1170 | 			}
1171 | 			length := int(endian.unchecked_get_u64be(v.buf[pos : pos + 8]))
1172 | 			if length < 0 || pos + 8 + length > len(v.buf) {
1173 | 				return 0, Xitdb_Error.Unexpected_EOF
1174 | 			}
1175 | 			return bytes.compare(v.buf[pos + 8 : pos + 8 + length], target), nil
1176 | 		case Core_Buffered_File:
1177 | 			buf_len := i64(len(v.memory.buf))
1178 | 			if buf_len > 0 && key_slot.value >= v.memory_pos && key_slot.value + 8 <= v.memory_pos + buf_len {
1179 | 				mem_off := int(key_slot.value - v.memory_pos)
1180 | 				length := int(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
1181 | 				if length >= 0 && mem_off + 8 + length <= int(buf_len) {
1182 | 					return bytes.compare(v.memory.buf[mem_off + 8 : mem_off + 8 + length], target), nil
1183 | 				}
1184 | 			}
1185 | 		}
1186 | 		core_seek_to(db.core, key_slot.value) or_return  // <== [calls core_seek_to]
1187 | 		length := core_read_i64(db.core) or_return  // <== [calls core_read_i64]
1188 | 		read_len := min(int(length), len(target))
1189 | 		if read_len <= 256 {
1190 | 			stack_buf: [256]u8 = ---
1191 | 			key_bytes := stack_buf[:read_len]
1192 | 			core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1193 | 			c := bytes.compare(key_bytes, target[:read_len])
1194 | 			if c != 0 {
1195 | 				return c, nil
1196 | 			}
1197 | 			return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1198 | 		}
1199 | 		key_bytes := make([]u8, read_len, context.temp_allocator)
1200 | 		core_read_exact(db.core, key_bytes) or_return  // <== [calls core_read_exact]
1201 | 		c := bytes.compare(key_bytes, target[:read_len])
1202 | 		if c != 0 {
1203 | 			return c, nil
1204 | 		}
1205 | 		return -1 if int(length) < len(target) else (1 if int(length) > len(target) else 0), nil
1206 | 	case:
1207 | 		return 0, .Unexpected_Tag
1208 | 	}
1209 | }
```

### `xitdb/collections.odin` (1 procedures · 3 lines: [`L702–L704`](../../xitdb/collections.odin#L702-L704))

#### [`sorted_map_iterator_from_string`](../../xitdb/collections.odin#L702-L704) — `ENTRY POINT` (`L702–L704`)

```odin
 702 | sorted_map_iterator_from_string :: proc(m: Read_Sorted_Map, start_key: string) -> (res: Cursor_Iterator, err: Error) {
 703 | 	return cursor_iterator_sorted_from_key(m.cursor, transmute([]u8)start_key)  // <== [calls cursor_iterator_sorted_from_key]
 704 | }
```

### `xitdb/core.odin` (6 procedures · 152 lines: [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L441–L457`](../../xitdb/core.odin#L441-L457), [`L509–L532`](../../xitdb/core.odin#L509-L532), [`L552–L575`](../../xitdb/core.odin#L552-L575))

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 2` (`L176–L192`)

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

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 3` (`L288–L323`)

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

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 2` (`L326–L359`)

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

#### [`core_slice_at`](../../xitdb/core.odin#L441-L457) — `DEPTH 3` (`L441–L457`)

```odin
 441 | core_slice_at :: #force_inline proc(c: ^Core, pos: i64, n: int) -> (slice: []u8, in_mem: bool, err: Error) {
 442 | 	#partial switch &v in c {
 443 | 	case Core_Memory:
 444 | 		p := int(pos)
 445 | 		if p < 0 || p + n > len(v.buf) {
 446 | 			return nil, true, Xitdb_Error.Unexpected_EOF
 447 | 		}
 448 | 		return v.buf[p : p + n], true, nil
 449 | 	case Core_Buffered_File:
 450 | 		buf_len := i64(len(v.memory.buf))
 451 | 		if buf_len > 0 && pos >= v.memory_pos && pos + i64(n) <= v.memory_pos + buf_len {
 452 | 			mem_off := int(pos - v.memory_pos)
 453 | 			return v.memory.buf[mem_off : mem_off + n], true, nil
 454 | 		}
 455 | 	}
 456 | 	return nil, false, nil
 457 | }
```

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 3` (`L509–L532`)

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

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 3` (`L552–L575`)

```odin
 552 | core_read_slot_raw :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 553 | 	#partial switch &v in c {
 554 | 	case Core_Memory:
 555 | 		end_pos := v.pos + SLOT_LENGTH
 556 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 557 | 			v.pos = i64(len(v.buf))
 558 | 			return {}, Xitdb_Error.Unexpected_EOF
 559 | 		}
 560 | 		s = slot_from_slice_raw(v.buf[int(v.pos):int(end_pos)])  // <== [calls slot_from_slice_raw]
 561 | 		v.pos = end_pos
 562 | 		return s, nil
 563 | 	case Core_Buffered_File:
 564 | 		buf_len := i64(len(v.memory.buf))
 565 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + SLOT_LENGTH <= v.memory_pos + buf_len {
 566 | 			mem_off := int(v.pos - v.memory_pos)
 567 | 			s = slot_from_slice_raw(v.memory.buf[mem_off : mem_off + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
 568 | 			v.pos += SLOT_LENGTH
 569 | 			return s, nil
 570 | 		}
 571 | 	}
 572 | 	buf: [SLOT_LENGTH]u8 = ---
 573 | 	core_read_exact(c, buf[:]) or_return  // <== [calls core_read_exact]
 574 | 	return slot_from_bytes_raw(buf), nil  // <== [calls slot_from_bytes_raw]
 575 | }
```

### `xitdb/cursor.odin` (9 procedures · 233 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L58–L61`](../../xitdb/cursor.odin#L58-L61), [`L648–L668`](../../xitdb/cursor.odin#L648-L668), [`L690–L693`](../../xitdb/cursor.odin#L690-L693), [`L695–L721`](../../xitdb/cursor.odin#L695-L721), [`L779–L790`](../../xitdb/cursor.odin#L779-L790), [`L852–L949`](../../xitdb/cursor.odin#L852-L949), [`L1050–L1083`](../../xitdb/cursor.odin#L1050-L1083), [`L1085–L1106`](../../xitdb/cursor.odin#L1085-L1106))

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 3` (`L46–L56`)

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

#### [`cursor_resolved_cursor`](../../xitdb/cursor.odin#L58-L61) — `DEPTH 2` (`L58–L61`)

```odin
  58 | cursor_resolved_cursor :: proc(c: Read_Cursor) -> (res: Read_Cursor, err: Error) {
  59 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  60 | 	return Read_Cursor{slot_ptr = slot_ptr, db = c.db, frozen_at = c.frozen_at}, nil
  61 | }
```

#### [`_fill_slot_block_from`](../../xitdb/cursor.odin#L648-L668) — `DEPTH 3` (`L648–L668`)

```odin
 648 | @(private)
 649 | _fill_slot_block_from :: proc(cursor: Read_Cursor, position: i64, start_idx: int, end_idx: int, level: ^Iter_Level) -> Error {
 650 | 	level.position = position
 651 | 	level.index = u8(start_idx)
 652 | 	level.count = u8(end_idx)
 653 | 	rem_slots := end_idx - start_idx
 654 | 	if rem_slots <= 0 {
 655 | 		return nil
 656 | 	}
 657 | 	core_seek_to(cursor.db.core, position + i64(start_idx) * SLOT_LENGTH) or_return  // <== [calls core_seek_to]
 658 | 	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 659 | 	core_read_exact(cursor.db.core, index_block_bytes[:rem_slots * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 660 | 	for j in 0 ..< rem_slots {
 661 | 		sb: [SLOT_LENGTH]u8 = ---
 662 | 		copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 663 | 		s := slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 664 | 		tag_validate(s.tag) or_return  // <== [calls tag_validate]
 665 | 		level.block[start_idx + j] = s
 666 | 	}
 667 | 	return nil
 668 | }
```

#### [`_init_iter_level`](../../xitdb/cursor.odin#L690-L693) — `DEPTH 2` (`L690–L693`)

```odin
 690 | @(private)
 691 | _init_iter_level :: proc(cursor: Read_Cursor, position: i64, level: ^Iter_Level) -> Error {
 692 | 	return _fill_slot_block_from(cursor, position, 0, SLOT_COUNT, level)  // <== [calls _fill_slot_block_from]
 693 | }
```

#### [`_init_btree_iter_level`](../../xitdb/cursor.odin#L695-L721) — `DEPTH 2` (`L695–L721`)

```odin
 695 | @(private)
 696 | _init_btree_iter_level :: proc(cursor: Read_Cursor, node_ptr: i64, level: ^Iter_Level) -> Error {
 697 | 	core_seek_to(cursor.db.core, node_ptr) or_return  // <== [calls core_seek_to]
 698 | 	header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
 699 | 	core_read_exact(cursor.db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 700 | 	if header_bytes[0] > u8(BTree_Node_Kind.Branch) {
 701 | 		return .Invalid_BTree_Node_Kind
 702 | 	}
 703 | 	num := int(header_bytes[1])
 704 | 	if num > BTREE_SLOT_COUNT {
 705 | 		return .Invalid_BTree_Node
 706 | 	}
 707 | 	position := node_ptr + BTREE_NODE_HEADER_SIZE
 708 | 	level.position = position
 709 | 	level.index = 0
 710 | 	level.count = u8(num)
 711 | 	if num > 0 {
 712 | 		index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 713 | 		core_read_exact(cursor.db.core, index_block_bytes[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 714 | 		for j in 0 ..< num {
 715 | 			sb: [SLOT_LENGTH]u8 = ---
 716 | 			copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 717 | 			level.block[j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 718 | 		}
 719 | 	}
 720 | 	return nil
 721 | }
```

#### [`_sorted_header`](../../xitdb/cursor.odin#L779-L790) — `DEPTH 2` (`L779–L790`)

```odin
 779 | @(private)
 780 | _sorted_header :: proc(cursor: Read_Cursor) -> (res: BTree_Header, err: Error) {
 781 | 	#partial switch cursor.slot_ptr.slot.tag {
 782 | 	case .Sorted_Map, .Sorted_Set:
 783 | 	case:
 784 | 		return {}, .Unexpected_Tag
 785 | 	}
 786 | 	core_seek_to(cursor.db.core, cursor.slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 787 | 	hb: [BTREE_HEADER_LENGTH]u8 = ---
 788 | 	core_read_exact(cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 789 | 	return btree_header_from_bytes(hb)  // <== [calls btree_header_from_bytes]
 790 | }
```

#### [`cursor_iterator_sorted_from_key`](../../xitdb/cursor.odin#L852-L949) — `DEPTH 1` (`L852–L949`)

```odin
 852 | cursor_iterator_sorted_from_key :: proc(unresolved_cursor: Read_Cursor, start_key: []u8) -> (res: Cursor_Iterator, err: Error) {
 853 | 	cursor := cursor_resolved_cursor(unresolved_cursor) or_return  // <== [calls cursor_resolved_cursor]
 854 | 	res.cursor = cursor
 855 | 	#partial switch cursor.slot_ptr.slot.tag {
 856 | 	case .None:
 857 | 		return res, nil
 858 | 	case .Sorted_Map, .Sorted_Set:
 859 | 	case:
 860 | 		return {}, .Unexpected_Tag
 861 | 	}
 862 | 	header := _sorted_header(cursor) or_return  // <== [calls _sorted_header]
 863 | 	total := header.size
 864 | 	node_ptr := header.root_ptr
 865 | 	before: i64 = 0
 866 | 	for {
 867 | 		core_seek_to(cursor.db.core, node_ptr) or_return  // <== [calls core_seek_to]
 868 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
 869 | 		core_read_exact(cursor.db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 870 | 		kind_int := header_bytes[0]
 871 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
 872 | 			return {}, .Invalid_BTree_Node_Kind
 873 | 		}
 874 | 		num := int(header_bytes[1])
 875 | 		if num > BTREE_SLOT_COUNT {
 876 | 			return {}, .Invalid_BTree_Node
 877 | 		}
 878 | 		position := node_ptr + BTREE_NODE_HEADER_SIZE
 879 | 		level := &res.stack[res.stack_len]
 880 | 		if BTree_Node_Kind(kind_int) == .Leaf {
 881 | 			if num > 0 {
 882 | 				index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 883 | 				core_read_exact(cursor.db.core, index_block_bytes[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 884 | 				for j in 0 ..< num {
 885 | 					sb: [SLOT_LENGTH]u8 = ---
 886 | 					copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 887 | 					level.block[j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 888 | 				}
 889 | 			}
 890 | 			lo := 0
 891 | 			hi := num
 892 | 			for lo < hi {
 893 | 				mid := int(uint(lo + hi) >> 1)
 894 | 				entry_slot := level.block[mid]
 895 | 				key_slot := sorted_entry_key_slot(cursor.db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
 896 | 				cmp := compare_key(cursor.db, key_slot, start_key) or_return  // <== [calls compare_key]
 897 | 				if cmp == 0 {
 898 | 					lo = mid
 899 | 					break
 900 | 				} else if cmp < 0 {
 901 | 					lo = mid + 1
 902 | 				} else {
 903 | 					hi = mid
 904 | 				}
 905 | 			}
 906 | 			before += i64(lo)
 907 | 			level.position = position
 908 | 			level.index = u8(lo)
 909 | 			level.count = u8(num)
 910 | 			res.stack_len += 1
 911 | 			break
 912 | 		}
 913 | 		branch_buf: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
 914 | 		core_read_exact(cursor.db.core, branch_buf[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
 915 | 		lo := 1
 916 | 		hi := num
 917 | 		sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
 918 | 		for lo < hi {
 919 | 			mid := int(uint(lo + hi) >> 1)
 920 | 			sb: [SLOT_LENGTH]u8 = ---
 921 | 			copy(sb[:], branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])
 922 | 			sep_slot := slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 923 | 			c := compare_key(cursor.db, sep_slot, start_key) or_return  // <== [calls compare_key]
 924 | 			if c <= 0 {
 925 | 				lo = mid + 1
 926 | 			} else {
 927 | 				hi = mid
 928 | 			}
 929 | 		}
 930 | 		i := lo - 1
 931 | 		counts_off := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
 932 | 		for k in 0 ..< i {
 933 | 			before += i64(endian.unchecked_get_u64be(branch_buf[counts_off + k * 8 : counts_off + (k + 1) * 8]))
 934 | 		}
 935 | 		for j in i ..< num {
 936 | 			sb: [SLOT_LENGTH]u8 = ---
 937 | 			copy(sb[:], branch_buf[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 938 | 			level.block[j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 939 | 		}
 940 | 		level.position = position
 941 | 		level.index = u8(i)
 942 | 		level.count = u8(num)
 943 | 		res.stack_len += 1
 944 | 		node_ptr = level.block[i].value
 945 | 	}
 946 | 	res.size = total
 947 | 	res.index = before
 948 | 	return res, nil
 949 | }
```

#### [`_iterator_next_internal`](../../xitdb/cursor.odin#L1050-L1083) — `DEPTH 1` (`L1050–L1083`)

```odin
1050 | @(private)
1051 | _iterator_next_internal :: proc(it: ^Cursor_Iterator, node_offset: i64) -> (res: Maybe(Read_Cursor), err: Error) {
1052 | 	for it.stack_len > 0 {
1053 | 		level := &it.stack[it.stack_len - 1]
1054 | 		if level.index >= level.count {
1055 | 			it.stack_len -= 1
1056 | 			if it.stack_len > 0 {
1057 | 				it.stack[it.stack_len - 1].index += 1
1058 | 			}
1059 | 			continue
1060 | 		}
1061 | 		next_slot := level.block[level.index]
1062 | 		if next_slot.tag == .Index {
1063 | 			if node_offset == BTREE_NODE_HEADER_SIZE {
1064 | 				_init_btree_iter_level(it.cursor, next_slot.value, &it.stack[it.stack_len]) or_return  // <== [calls _init_btree_iter_level]
1065 | 			} else {
1066 | 				_init_iter_level(it.cursor, next_slot.value, &it.stack[it.stack_len]) or_return  // <== [calls _init_iter_level]
1067 | 			}
1068 | 			it.stack_len += 1
1069 | 			continue
1070 | 		}
1071 | 		slot_idx := level.index
1072 | 		level.index += 1
1073 | 		if !slot_empty(next_slot) {  // <== [calls slot_empty]
1074 | 			position := level.position + i64(slot_idx) * SLOT_LENGTH
1075 | 			return Read_Cursor{
1076 | 				slot_ptr  = Slot_Pointer{position = position, slot = next_slot},
1077 | 				db        = it.cursor.db,
1078 | 				frozen_at = it.cursor.frozen_at,
1079 | 			}, nil
1080 | 		}
1081 | 	}
1082 | 	return nil, nil
1083 | }
```

#### [`cursor_iterator_next`](../../xitdb/cursor.odin#L1085-L1106) — `ENTRY POINT` (`L1085–L1106`)

```odin
1085 | cursor_iterator_next :: proc(it: ^Cursor_Iterator) -> (res: Maybe(Read_Cursor), err: Error) {
1086 | 	#partial switch it.cursor.slot_ptr.slot.tag {
1087 | 	case .None:
1088 | 		return nil, nil
1089 | 	case .Array_List:
1090 | 		if it.index == it.size {
1091 | 			return nil, nil
1092 | 		}
1093 | 		it.index += 1
1094 | 		return _iterator_next_internal(it, 0)  // <== [calls _iterator_next_internal]
1095 | 	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
1096 | 		if it.index == it.size {
1097 | 			return nil, nil
1098 | 		}
1099 | 		it.index += 1
1100 | 		return _iterator_next_internal(it, BTREE_NODE_HEADER_SIZE)  // <== [calls _iterator_next_internal]
1101 | 	case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
1102 | 		return _iterator_next_internal(it, 0)  // <== [calls _iterator_next_internal]
1103 | 	case:
1104 | 		return nil, .Unexpected_Tag
1105 | 	}
1106 | }
```

### `xitdb/database.odin` (2 procedures · 14 lines: [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L416–L421`](../../xitdb/database.odin#L416-L421))

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 4` (`L370–L377`)

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

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 4` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

### `xitdb/types.odin` (7 procedures · 53 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1329–L1331`](../../xitdb/types.odin#L1329-L1331))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 4` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 2` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 2` (`L880–L890`)

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

#### [`slot_from_slice_raw`](../../xitdb/types.odin#L892-L901) — `DEPTH 3` (`L892–L901`)

```odin
 892 | slot_from_slice_raw :: #force_inline proc(b: []u8) -> Slot #no_bounds_check {
 893 | 	full := (b[0] & 0x80) != 0
 894 | 	raw_tag := b[0] & 0x7f
 895 | 	val := endian.unchecked_get_u64be(b[1:9])
 896 | 	return Slot{
 897 | 		value = i64(val),
 898 | 		tag   = Tag(raw_tag),
 899 | 		full  = full,
 900 | 	}
 901 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 5` (`L993–L1003`)

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

#### [`btree_header_from_bytes`](../../xitdb/types.odin#L1099-L1107) — `DEPTH 3` (`L1099–L1107`)

```odin
1099 | btree_header_from_bytes :: #force_inline proc(buf: [BTREE_HEADER_LENGTH]u8) -> (res: BTree_Header, err: Error) {
1100 | 	b := buf
1101 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1102 | 	root_ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1103 | 	if size < 0 || root_ptr < 0 {
1104 | 		return {}, .Expected_Unsigned_Long
1105 | 	}
1106 | 	return BTree_Header{root_ptr = root_ptr, size = size}, nil
1107 | }
```

#### [`is_key_only_entry`](../../xitdb/types.odin#L1329-L1331) — `DEPTH 3` (`L1329–L1331`)

```odin
1329 | is_key_only_entry :: #force_inline proc(entry: Slot) -> bool {
1330 | 	return entry.tag == .Bytes || entry.tag == .Short_Bytes
1331 | }
```

