# #30. `Sorted_Map (B+Tree) rank query` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1167-L1178`)](../bench_xitdb.odin#L1167-L1178) · [Zig Harness (`bench_xitdb.zig#L1193-L1204`)](../bench_xitdb.zig#L1193-L1204)

- **Touched Library Scope:** **20** procedures across **6** `xitdb/*.odin` files (**434** lines of library code)
- **Direct Benchmark Entry Points:** `sorted_map_rank`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1167-L1178`)

```odin
1167 | 	t2 := time.now()
1168 | 	for k in keys {
1169 | 		rk, _ := xitdb.sorted_map_rank(sm, k)
1170 | 		assert(rk >= 0 && rk < i64(n))
1171 | 	}
1172 | 	elapsed_rank := time.since(t2)
1173 | 
1174 | 	print_result(Bench_Result{
1175 | 		name    = "Sorted_Map (B+Tree) rank query",
1176 | 		ops     = n,
1177 | 		elapsed = elapsed_rank,
1178 | 	})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1193-L1204</code>)</strong></summary>

```zig
1193 |     const t2 = std.Io.Clock.awake.now(io);
1194 |     for (keys) |k| {
1195 |         const rk = try sm.rank(k);
1196 |         std.debug.assert(rk < @as(u64, @intCast(n)));
1197 |     }
1198 |     const elapsed_rank = t2.untilNow(io, .awake).nanoseconds;
1199 | 
1200 |     try printResult(stdout, .{
1201 |         .name = "Sorted_Map (B+Tree) rank query",
1202 |         .ops = n,
1203 |         .elapsed_ns = elapsed_rank,
1204 |     });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_rank` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L762-L764`](../../xitdb/collections.odin#L762-L764) |
| `xitdb/collections.odin` | `sorted_map_rank_by_bytes` | `depth 1` (from `sorted_map_rank`) | 11 | [`xitdb/collections.odin#L738-L748`](../../xitdb/collections.odin#L738-L748) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `sorted_map_rank_by_bytes`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `sorted_map_rank_by_bytes`, `sorted_rank`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `sorted_map_rank_by_bytes`, `sorted_rank`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `sorted_map_rank_by_bytes`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `sorted_rank` | `depth 2` (from `sorted_map_rank_by_bytes`) | 120 | [`xitdb/btree.odin#L1441-L1560`](../../xitdb/btree.odin#L1441-L1560) |
| `xitdb/database.odin` | `is_root` | `depth 3` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_slice_at` | `depth 3` (from `sorted_rank`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 3` (from `sorted_rank`, `sorted_entry_key_slot`, `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 3` (from `sorted_rank`) | 13 | [`xitdb/btree.odin#L1129-L1141`](../../xitdb/btree.odin#L1129-L1141) |
| `xitdb/btree.odin` | `compare_key` | `depth 3` (from `sorted_rank`) | 60 | [`xitdb/btree.odin#L1150-L1209`](../../xitdb/btree.odin#L1150-L1209) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 4` (from `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1329-L1331`](../../xitdb/types.odin#L1329-L1331) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 4` (from `sorted_entry_key_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/core.odin` | `core_read_i64` | `depth 4` (from `compare_key`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `root_header_from_bytes`, `core_read_slot_raw`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Sorted_Map (B+Tree) rank query`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/btree.odin` (3 procedures · 193 lines: [`L1129–L1141`](../../xitdb/btree.odin#L1129-L1141), [`L1150–L1209`](../../xitdb/btree.odin#L1150-L1209), [`L1441–L1560`](../../xitdb/btree.odin#L1441-L1560))

#### [`sorted_entry_key_slot`](../../xitdb/btree.odin#L1129-L1141) — `DEPTH 3` (`L1129–L1141`)

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

#### [`compare_key`](../../xitdb/btree.odin#L1150-L1209) — `DEPTH 3` (`L1150–L1209`)

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

#### [`sorted_rank`](../../xitdb/btree.odin#L1441-L1560) — `DEPTH 2` (`L1441–L1560`)

```odin
1441 | sorted_rank :: proc(db: ^Database, root_ptr: i64, key: []u8) -> (res: i64, err: Error) {
1442 | 	node_ptr := root_ptr
1443 | 	rank: i64 = 0
1444 | 	for {
1445 | 		if hdr_slice, in_mem, slice_err := core_slice_at(db.core, node_ptr, BTREE_NODE_HEADER_SIZE); in_mem {  // <== [calls core_slice_at]
1446 | 			if slice_err != nil {
1447 | 				return 0, slice_err
1448 | 			}
1449 | 			kind_int := hdr_slice[0]
1450 | 			if kind_int > u8(BTree_Node_Kind.Branch) {
1451 | 				return 0, .Invalid_BTree_Node_Kind
1452 | 			}
1453 | 			num := int(hdr_slice[1])
1454 | 			if num > BTREE_SLOT_COUNT {
1455 | 				return 0, .Invalid_BTree_Node
1456 | 			}
1457 | 			if BTree_Node_Kind(kind_int) == .Leaf {
1458 | 				entries_slice, _, e_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, num * SLOT_LENGTH)  // <== [calls core_slice_at]
1459 | 				if e_err != nil {
1460 | 					return 0, e_err
1461 | 				}
1462 | 				lo := 0
1463 | 				hi := num
1464 | 				for lo < hi {
1465 | 					mid := int(uint(lo + hi) >> 1)
1466 | 					entry_slot := slot_from_slice_raw(entries_slice[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1467 | 					key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1468 | 					cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1469 | 					if cmp == 0 {
1470 | 						return rank + i64(mid), nil
1471 | 					} else if cmp < 0 {
1472 | 						lo = mid + 1
1473 | 					} else {
1474 | 						hi = mid
1475 | 					}
1476 | 				}
1477 | 				return rank + i64(lo), nil
1478 | 			}
1479 | 			branch_slice, _, b_err := core_slice_at(db.core, node_ptr + BTREE_NODE_HEADER_SIZE, SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8)  // <== [calls core_slice_at]
1480 | 			if b_err != nil {
1481 | 				return 0, b_err
1482 | 			}
1483 | 			lo := 1
1484 | 			hi := num
1485 | 			sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1486 | 			for lo < hi {
1487 | 				mid := int(uint(lo + hi) >> 1)
1488 | 				sep_slot := slot_from_slice_raw(branch_slice[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1489 | 				c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1490 | 				if c <= 0 {
1491 | 					lo = mid + 1
1492 | 				} else {
1493 | 					hi = mid
1494 | 				}
1495 | 			}
1496 | 			i := lo - 1
1497 | 			counts_off := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1498 | 			for k in 0 ..< i {
1499 | 				rank += i64(endian.unchecked_get_u64be(branch_slice[counts_off + k * 8 : counts_off + (k + 1) * 8]))
1500 | 			}
1501 | 			node_ptr = slot_from_slice_raw(branch_slice[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1502 | 			continue
1503 | 		}
1504 | 
1505 | 		core_seek_to(db.core, node_ptr) or_return  // <== [calls core_seek_to]
1506 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
1507 | 		core_read_exact(db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
1508 | 		kind_int := header_bytes[0]
1509 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
1510 | 			return 0, .Invalid_BTree_Node_Kind
1511 | 		}
1512 | 		num := int(header_bytes[1])
1513 | 		if num > BTREE_SLOT_COUNT {
1514 | 			return 0, .Invalid_BTree_Node
1515 | 		}
1516 | 		if BTree_Node_Kind(kind_int) == .Leaf {
1517 | 			entries_buf: [SLOT_LENGTH * BTREE_SLOT_COUNT]u8 = ---
1518 | 			if num > 0 {
1519 | 				core_read_exact(db.core, entries_buf[:num * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
1520 | 			}
1521 | 			lo := 0
1522 | 			hi := num
1523 | 			for lo < hi {
1524 | 				mid := int(uint(lo + hi) >> 1)
1525 | 				entry_slot := slot_from_slice_raw(entries_buf[mid * SLOT_LENGTH : (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1526 | 				key_slot := sorted_entry_key_slot(db, entry_slot) or_return  // <== [calls sorted_entry_key_slot]
1527 | 				cmp := compare_key(db, key_slot, key) or_return  // <== [calls compare_key]
1528 | 				if cmp == 0 {
1529 | 					return rank + i64(mid), nil
1530 | 				} else if cmp < 0 {
1531 | 					lo = mid + 1
1532 | 				} else {
1533 | 					hi = mid
1534 | 				}
1535 | 			}
1536 | 			return rank + i64(lo), nil
1537 | 		}
1538 | 		branch_buf: [(SLOT_LENGTH * 2 + 8) * BTREE_SLOT_COUNT]u8 = ---
1539 | 		core_read_exact(db.core, branch_buf[:SLOT_LENGTH * 2 * BTREE_SLOT_COUNT + num * 8]) or_return  // <== [calls core_read_exact]
1540 | 		lo := 1
1541 | 		hi := num
1542 | 		sep_off := SLOT_LENGTH * BTREE_SLOT_COUNT
1543 | 		for lo < hi {
1544 | 			mid := int(uint(lo + hi) >> 1)
1545 | 			sep_slot := slot_from_slice_raw(branch_buf[sep_off + mid * SLOT_LENGTH : sep_off + (mid + 1) * SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1546 | 			c := compare_key(db, sep_slot, key) or_return  // <== [calls compare_key]
1547 | 			if c <= 0 {
1548 | 				lo = mid + 1
1549 | 			} else {
1550 | 				hi = mid
1551 | 			}
1552 | 		}
1553 | 		i := lo - 1
1554 | 		counts_off := SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
1555 | 		for k in 0 ..< i {
1556 | 			rank += i64(endian.unchecked_get_u64be(branch_buf[counts_off + k * 8 : counts_off + (k + 1) * 8]))
1557 | 		}
1558 | 		node_ptr = slot_from_slice_raw(branch_buf[i * SLOT_LENGTH : (i + 1) * SLOT_LENGTH]).value  // <== [calls slot_from_slice_raw]
1559 | 	}
1560 | }
```

### `xitdb/collections.odin` (2 procedures · 14 lines: [`L738–L748`](../../xitdb/collections.odin#L738-L748), [`L762–L764`](../../xitdb/collections.odin#L762-L764))

#### [`sorted_map_rank_by_bytes`](../../xitdb/collections.odin#L738-L748) — `DEPTH 1` (`L738–L748`)

```odin
 738 | sorted_map_rank_by_bytes :: proc(m: Read_Sorted_Map, key: []u8) -> (res: i64, err: Error) {
 739 | 	slot_ptr := cursor_resolved(m.cursor) or_return  // <== [calls cursor_resolved]
 740 | 	if slot_ptr.slot.tag == .None {
 741 | 		return 0, nil
 742 | 	}
 743 | 	core_seek_to(m.cursor.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 744 | 	hb: [BTREE_HEADER_LENGTH]u8
 745 | 	core_read_exact(m.cursor.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 746 | 	header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 747 | 	return sorted_rank(m.cursor.db, header.root_ptr, key)  // <== [calls sorted_rank]
 748 | }
```

#### [`sorted_map_rank`](../../xitdb/collections.odin#L762-L764) — `ENTRY POINT` (`L762–L764`)

```odin
 762 | sorted_map_rank :: proc(m: Read_Sorted_Map, key: string) -> (res: i64, err: Error) {
 763 | 	return sorted_map_rank_by_bytes(m, transmute([]u8)key)  // <== [calls sorted_map_rank_by_bytes]
 764 | }
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

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 4` (`L509–L532`)

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

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 4` (`L552–L575`)

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

### `xitdb/cursor.odin` (1 procedures · 11 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56))

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 2` (`L46–L56`)

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

### `xitdb/database.odin` (2 procedures · 14 lines: [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L416–L421`](../../xitdb/database.odin#L416-L421))

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 3` (`L370–L377`)

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

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 3` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

### `xitdb/types.odin` (6 procedures · 50 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1329–L1331`](../../xitdb/types.odin#L1329-L1331))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 4` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 5` (`L880–L890`)

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

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 4` (`L993–L1003`)

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

#### [`btree_header_from_bytes`](../../xitdb/types.odin#L1099-L1107) — `DEPTH 2` (`L1099–L1107`)

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

#### [`is_key_only_entry`](../../xitdb/types.odin#L1329-L1331) — `DEPTH 4` (`L1329–L1331`)

```odin
1329 | is_key_only_entry :: #force_inline proc(entry: Slot) -> bool {
1330 | 	return entry.tag == .Bytes || entry.tag == .Short_Bytes
1331 | }
```

