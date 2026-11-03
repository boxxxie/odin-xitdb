# #35. `Sorted_Map (B+Tree) index-seek page(10)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L1256-L1271`)](../bench_xitdb.odin#L1256-L1271) · [Zig Harness (`bench_xitdb.zig#L1275-L1289`)](../bench_xitdb.zig#L1275-L1289)

- **Touched Library Scope:** **22** procedures across **5** `xitdb/*.odin` files (**368** lines of library code)
- **Direct Benchmark Entry Points:** `sorted_map_iterator_from_index`, `cursor_iterator_next`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L1256-L1271`)

```odin
1256 | 	// 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
1257 | 	t7 := time.now()
1258 | 	for i in 0 ..< n {
1259 | 		iit, _ := xitdb.sorted_map_iterator_from_index(sm, i64(i))
1260 | 		for _ in 0 ..< 10 {
1261 | 			c_maybe, _ := xitdb.cursor_iterator_next(&iit)
1262 | 			if c_maybe == nil do break
1263 | 		}
1264 | 	}
1265 | 	elapsed_index_seek := time.since(t7)
1266 | 
1267 | 	print_result(Bench_Result{
1268 | 		name    = "Sorted_Map (B+Tree) index-seek page(10)",
1269 | 		ops     = n,
1270 | 		elapsed = elapsed_index_seek,
1271 | 	})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L1275-L1289</code>)</strong></summary>

```zig
1275 |     // 3e. Order-Statistic B+Tree positional index seek (`sorted_map_iterator_from_index`) + 10-item page
1276 |     const t7 = std.Io.Clock.awake.now(io);
1277 |     for (0..n) |i| {
1278 |         var iit = try sm.iteratorFromIndex(@intCast(i));
1279 |         for (0..10) |_| {
1280 |             if ((try iit.next()) == null) break;
1281 |         }
1282 |     }
1283 |     const elapsed_index_seek = t7.untilNow(io, .awake).nanoseconds;
1284 | 
1285 |     try printResult(stdout, .{
1286 |         .name = "Sorted_Map (B+Tree) index-seek page(10)",
1287 |         .ops = n,
1288 |         .elapsed_ns = elapsed_index_seek,
1289 |     });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `sorted_map_iterator_from_index` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L706-L708`](../../xitdb/collections.odin#L706-L708) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_iterator_sorted_from_index` | `depth 1` (from `sorted_map_iterator_from_index`) | 59 | [`xitdb/cursor.odin#L792-L850`](../../xitdb/cursor.odin#L792-L850) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator_sorted_from_index`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/cursor.odin` | `_sorted_header` | `depth 2` (from `cursor_iterator_sorted_from_index`) | 12 | [`xitdb/cursor.odin#L779-L790`](../../xitdb/cursor.odin#L779-L790) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 2` (from `cursor_iterator_sorted_from_index`) | 11 | [`xitdb/cursor.odin#L767-L777`](../../xitdb/cursor.odin#L767-L777) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator_sorted_from_index`, `_sorted_header`, `_fill_slot_block_raw_from`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator_sorted_from_index`, `_sorted_header`, `_fill_slot_block_raw_from`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/cursor.odin` | `_fill_slot_block_raw_from` | `depth 2` (from `cursor_iterator_sorted_from_index`) | 19 | [`xitdb/cursor.odin#L670-L688`](../../xitdb/cursor.odin#L670-L688) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 3` (from `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 3` (from `_sorted_header`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `_fill_slot_block_raw_from`, `_init_btree_iter_level`, `_fill_slot_block_from`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/database.odin` | `is_root` | `depth 4` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 4` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `_fill_slot_block_from`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 5` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`Sorted_Map (B+Tree) index-seek page(10)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/collections.odin` (1 procedures · 3 lines: [`L706–L708`](../../xitdb/collections.odin#L706-L708))

#### [`sorted_map_iterator_from_index`](../../xitdb/collections.odin#L706-L708) — `ENTRY POINT` (`L706–L708`)

```odin
 706 | sorted_map_iterator_from_index :: proc(m: Read_Sorted_Map, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
 707 | 	return cursor_iterator_sorted_from_index(m.cursor, start_index)  // <== [calls cursor_iterator_sorted_from_index]
 708 | }
```

### `xitdb/core.odin` (3 procedures · 87 lines: [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359))

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

### `xitdb/cursor.odin` (11 procedures · 224 lines: [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L58–L61`](../../xitdb/cursor.odin#L58-L61), [`L648–L668`](../../xitdb/cursor.odin#L648-L668), [`L670–L688`](../../xitdb/cursor.odin#L670-L688), [`L690–L693`](../../xitdb/cursor.odin#L690-L693), [`L695–L721`](../../xitdb/cursor.odin#L695-L721), [`L767–L777`](../../xitdb/cursor.odin#L767-L777), [`L779–L790`](../../xitdb/cursor.odin#L779-L790), [`L792–L850`](../../xitdb/cursor.odin#L792-L850), [`L1050–L1083`](../../xitdb/cursor.odin#L1050-L1083), [`L1085–L1106`](../../xitdb/cursor.odin#L1085-L1106))

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

#### [`_fill_slot_block_raw_from`](../../xitdb/cursor.odin#L670-L688) — `DEPTH 2` (`L670–L688`)

```odin
 670 | @(private)
 671 | _fill_slot_block_raw_from :: proc(cursor: Read_Cursor, position: i64, start_idx: int, end_idx: int, level: ^Iter_Level) -> Error {
 672 | 	level.position = position
 673 | 	level.index = u8(start_idx)
 674 | 	level.count = u8(end_idx)
 675 | 	rem_slots := end_idx - start_idx
 676 | 	if rem_slots <= 0 {
 677 | 		return nil
 678 | 	}
 679 | 	core_seek_to(cursor.db.core, position + i64(start_idx) * SLOT_LENGTH) or_return  // <== [calls core_seek_to]
 680 | 	index_block_bytes: [INDEX_BLOCK_SIZE]u8 = ---
 681 | 	core_read_exact(cursor.db.core, index_block_bytes[:rem_slots * SLOT_LENGTH]) or_return  // <== [calls core_read_exact]
 682 | 	for j in 0 ..< rem_slots {
 683 | 		sb: [SLOT_LENGTH]u8 = ---
 684 | 		copy(sb[:], index_block_bytes[j * SLOT_LENGTH : (j + 1) * SLOT_LENGTH])
 685 | 		level.block[start_idx + j] = slot_from_bytes_raw(sb)  // <== [calls slot_from_bytes_raw]
 686 | 	}
 687 | 	return nil
 688 | }
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

#### [`_resolve_start_index`](../../xitdb/cursor.odin#L767-L777) — `DEPTH 2` (`L767–L777`)

```odin
 767 | @(private)
 768 | _resolve_start_index :: proc(index: i64, size: i64) -> (res: i64, err: bool) {
 769 | 	resolved := index
 770 | 	if index < 0 {
 771 | 		resolved = index + size
 772 | 	}
 773 | 	if resolved < 0 || resolved >= size {
 774 | 		return 0, false
 775 | 	}
 776 | 	return resolved, true
 777 | }
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

#### [`cursor_iterator_sorted_from_index`](../../xitdb/cursor.odin#L792-L850) — `DEPTH 1` (`L792–L850`)

```odin
 792 | cursor_iterator_sorted_from_index :: proc(unresolved_cursor: Read_Cursor, start_index: i64) -> (res: Cursor_Iterator, err: Error) {
 793 | 	cursor := cursor_resolved_cursor(unresolved_cursor) or_return  // <== [calls cursor_resolved_cursor]
 794 | 	res.cursor = cursor
 795 | 	#partial switch cursor.slot_ptr.slot.tag {
 796 | 	case .None:
 797 | 		return res, nil
 798 | 	case .Sorted_Map, .Sorted_Set:
 799 | 	case:
 800 | 		return {}, .Unexpected_Tag
 801 | 	}
 802 | 	header := _sorted_header(cursor) or_return  // <== [calls _sorted_header]
 803 | 	total := header.size
 804 | 	idx, ok := _resolve_start_index(start_index, total)  // <== [calls _resolve_start_index]
 805 | 	if !ok {
 806 | 		return res, nil
 807 | 	}
 808 | 	node_ptr := header.root_ptr
 809 | 	rem := idx
 810 | 	for {
 811 | 		core_seek_to(cursor.db.core, node_ptr) or_return  // <== [calls core_seek_to]
 812 | 		header_bytes: [BTREE_NODE_HEADER_SIZE]u8 = ---
 813 | 		core_read_exact(cursor.db.core, header_bytes[:]) or_return  // <== [calls core_read_exact]
 814 | 		kind_int := header_bytes[0]
 815 | 		if kind_int > u8(BTree_Node_Kind.Branch) {
 816 | 			return {}, .Invalid_BTree_Node_Kind
 817 | 		}
 818 | 		num := int(header_bytes[1])
 819 | 		if num > BTREE_SLOT_COUNT {
 820 | 			return {}, .Invalid_BTree_Node
 821 | 		}
 822 | 		position := node_ptr + BTREE_NODE_HEADER_SIZE
 823 | 		level := &res.stack[res.stack_len]
 824 | 		if BTree_Node_Kind(kind_int) == .Leaf {
 825 | 			r := int(rem)
 826 | 			_fill_slot_block_raw_from(cursor, position, r, num, level) or_return  // <== [calls _fill_slot_block_raw_from]
 827 | 			res.stack_len += 1
 828 | 			break
 829 | 		}
 830 | 		counts_pos := position + SLOT_LENGTH * 2 * BTREE_SLOT_COUNT
 831 | 		core_seek_to(cursor.db.core, counts_pos) or_return  // <== [calls core_seek_to]
 832 | 		counts_buf: [8 * BTREE_SLOT_COUNT]u8 = ---
 833 | 		core_read_exact(cursor.db.core, counts_buf[:num * 8]) or_return  // <== [calls core_read_exact]
 834 | 		i := 0
 835 | 		for i + 1 < num {
 836 | 			cnt := i64(endian.unchecked_get_u64be(counts_buf[i * 8 : i * 8 + 8]))
 837 | 			if rem < cnt {
 838 | 				break
 839 | 			}
 840 | 			rem -= cnt
 841 | 			i += 1
 842 | 		}
 843 | 		_fill_slot_block_raw_from(cursor, position, i, num, level) or_return  // <== [calls _fill_slot_block_raw_from]
 844 | 		res.stack_len += 1
 845 | 		node_ptr = level.block[i].value
 846 | 	}
 847 | 	res.size = total
 848 | 	res.index = idx
 849 | 	return res, nil
 850 | }
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

### `xitdb/types.odin` (5 procedures · 40 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107))

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

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 3` (`L880–L890`)

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

