# #63. `DB: Re-open & trailer checksum verify` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L2087-L2102`)](../bench_xitdb.odin#L2087-L2102) · [Zig Harness (`bench_xitdb.zig#L2265-L2279`)](../bench_xitdb.zig#L2265-L2279)

- **Touched Library Scope:** **36** procedures across **3** `xitdb/*.odin` files (**812** lines of library code)
- **Direct Benchmark Entry Points:** `database_init`, `sha1_hasher`, `database_root_cursor`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L2087-L2102`)

```odin
2087 | 		// 5e. Database re-open & header/root-trailer checksum validation (`database_init` on populated `Core_Memory`)
2088 | 		reopen_ops := commits * 10
2089 | 		t_reopen := time.now()
2090 | 		for _ in 0 ..< reopen_ops {
2091 | 			reopened_db, r_err := xitdb.database_init(&core, xitdb.sha1_hasher())
2092 | 			assert(r_err == nil)
2093 | 			rc := xitdb.database_root_cursor(&reopened_db)
2094 | 			assert(rc.slot_ptr.slot.tag == .Hash_Map)
2095 | 		}
2096 | 		elapsed_reopen := time.since(t_reopen)
2097 | 
2098 | 		print_result(Bench_Result{
2099 | 			name    = "DB: Re-open & trailer checksum verify",
2100 | 			ops     = reopen_ops,
2101 | 			elapsed = elapsed_reopen,
2102 | 		})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L2265-L2279</code>)</strong></summary>

```zig
2265 |         // 6e. Database re-open & header/root-trailer checksum validation (`database_init` on populated `Core_Memory`)
2266 |         const reopen_ops = commits * 10;
2267 |         const t_reopen = std.Io.Clock.awake.now(io);
2268 |         for (0..reopen_ops) |_| {
2269 |             var reopened_db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
2270 |             const rc = reopened_db.rootCursor();
2271 |             std.debug.assert(rc.slot_ptr.slot.tag == .hash_map);
2272 |         }
2273 |         const elapsed_reopen = t_reopen.untilNow(io, .awake).nanoseconds;
2274 | 
2275 |         try printResult(stdout, .{
2276 |             .name = "DB: Re-open & trailer checksum verify",
2277 |             .ops = reopen_ops,
2278 |             .elapsed_ns = elapsed_reopen,
2279 |         });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 2` (from `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`DB: Re-open & trailer checksum verify`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/core.odin` (8 procedures · 229 lines: [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437))

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 2` (`L125–L142`)

```odin
 125 | @(private)
 126 | _buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
 127 | 	cached_len := bf.file_len
 128 | 	bf.file_len = nil
 129 | 	os.seek(bf.file.file, pos, .Start) or_return
 130 | 	written := 0
 131 | 	for written < len(data) {
 132 | 		n := os.write(bf.file.file, data[written:]) or_return
 133 | 		if n == 0 {
 134 | 			return io.Error.Short_Write
 135 | 		}
 136 | 		written += n
 137 | 	}
 138 | 	if cl, ok := cached_len.?; ok {
 139 | 		bf.file_len = max(cl, pos + i64(len(data)))
 140 | 	}
 141 | 	return nil
 142 | }
```

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 2` (`L144–L151`)

```odin
 144 | @(private)
 145 | _buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
 146 | 	if len(bf.memory.buf) > bf.flushed_len {
 147 | 		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return  // <== [calls _buffered_write_to_file]
 148 | 		bf.flushed_len = len(bf.memory.buf)
 149 | 	}
 150 | 	return nil
 151 | }
```

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 1` (`L153–L174`)

```odin
 153 | core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
 154 | 	switch &v in c {
 155 | 	case Core_Memory:
 156 | 		return i64(len(v.buf)), nil
 157 | 	case Core_File:
 158 | 		return os.file_size(v.file)
 159 | 	case Core_Buffered_File:
 160 | 		flen: i64
 161 | 		if fl, ok := v.file_len.?; ok {
 162 | 			flen = fl
 163 | 		} else {
 164 | 			flen = os.file_size(v.file.file) or_return
 165 | 			v.file_len = flen
 166 | 		}
 167 | 		buf_size := i64(len(v.memory.buf))
 168 | 		if buf_size == 0 {
 169 | 			return flen, nil
 170 | 		}
 171 | 		return max(v.memory_pos + buf_size, flen), nil
 172 | 	}
 173 | 	return 0, .Invalid_Database
 174 | }
```

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

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 1` (`L219–L236`)

```odin
 219 | core_sync :: proc(c: ^Core) -> Error {
 220 | 	switch &v in c {
 221 | 	case Core_Memory:
 222 | 		return nil
 223 | 	case Core_File:
 224 | 		if !v.fsync {
 225 | 			return nil
 226 | 		}
 227 | 		return os.sync(v.file)
 228 | 	case Core_Buffered_File:
 229 | 		_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 230 | 		if !v.file.fsync {
 231 | 			return nil
 232 | 		}
 233 | 		return os.sync(v.file.file)
 234 | 	}
 235 | 	return .Invalid_Database
 236 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 4` (`L288–L323`)

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

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 3` (`L326–L359`)

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

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 1` (`L362–L437`)

```odin
 362 | core_write_all :: proc(c: ^Core, p: []u8) -> Error {
 363 | 	if len(p) == 0 {
 364 | 		return nil
 365 | 	}
 366 | 	switch &v in c {
 367 | 	case Core_Memory:
 368 | 		old_size := int(len(v.buf))
 369 | 		end_pos := int(v.pos) + len(p)
 370 | 		if end_pos > old_size {
 371 | 			resize(&v.buf, end_pos)
 372 | 		}
 373 | 		copy(v.buf[int(v.pos):end_pos], p)
 374 | 		v.pos = i64(end_pos)
 375 | 		return nil
 376 | 	case Core_File:
 377 | 		written := 0
 378 | 		for written < len(p) {
 379 | 			n := os.write(v.file, p[written:]) or_return
 380 | 			if n == 0 {
 381 | 				return io.Error.Short_Write
 382 | 			}
 383 | 			written += n
 384 | 		}
 385 | 		return nil
 386 | 	case Core_Buffered_File:
 387 | 		n := i64(len(p))
 388 | 		if v.file_len == nil {
 389 | 			fl := os.file_size(v.file.file) or_return
 390 | 			v.file_len = fl
 391 | 		}
 392 | 		buf_size := i64(len(v.memory.buf))
 393 | 		if buf_size > 0 && v.pos + n <= v.memory_pos {
 394 | 			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
 395 | 			// write directly to the file without evicting the hot tail buffer.
 396 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 397 | 			v.pos += n
 398 | 			return nil
 399 | 		}
 400 | 		if buf_size == 0 {
 401 | 			v.memory_pos = v.pos
 402 | 			v.flushed_len = 0
 403 | 		} else if v.pos > v.memory_pos + buf_size ||
 404 | 		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
 405 | 			_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 406 | 			clear(&v.memory.buf)
 407 | 			v.flushed_len = 0
 408 | 			v.memory_pos = v.pos
 409 | 		}
 410 | 		buf_size = i64(len(v.memory.buf))
 411 | 		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
 412 | 			rel_off := int(v.pos - v.memory_pos)
 413 | 			end_off := rel_off + len(p)
 414 | 			if end_off > len(v.memory.buf) {
 415 | 				resize(&v.memory.buf, end_off)
 416 | 			}
 417 | 			copy(v.memory.buf[rel_off:end_off], p)
 418 | 			if rel_off < v.flushed_len {
 419 | 				if end_off <= v.flushed_len {
 420 | 					_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 421 | 				} else {
 422 | 					v.flushed_len = rel_off
 423 | 				}
 424 | 			}
 425 | 		} else {
 426 | 			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
 427 | 				_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 428 | 				clear(&v.memory.buf)
 429 | 				v.flushed_len = 0
 430 | 			}
 431 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 432 | 		}
 433 | 		v.pos += n
 434 | 		return nil
 435 | 	}
 436 | 	return .Invalid_Database
 437 | }
```

### `xitdb/database.odin` (11 procedures · 149 lines: [`L182–L235`](../../xitdb/database.odin#L182-L235), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L272–L280`](../../xitdb/database.odin#L272-L280), [`L283–L298`](../../xitdb/database.odin#L283-L298), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L337–L341`](../../xitdb/database.odin#L337-L341), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L379–L382`](../../xitdb/database.odin#L379-L382), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414))

#### [`database_init`](../../xitdb/database.odin#L182-L235) — `ENTRY POINT` (`L182–L235`)

```odin
 182 | database_init :: proc(core: ^Core, hasher := Hasher{}) -> (db: Database, err: Error) {
 183 | 	h := hasher
 184 | 	if h.hash_proc == nil && h.hash_size == 0 {
 185 | 		h = sha1_hasher()  // <== [calls sha1_hasher]
 186 | 	}
 187 | 
 188 | 	// If buffered file, clear any stale buffer bytes before opening.
 189 | 	#partial switch &bf in core {
 190 | 	case Core_Buffered_File:
 191 | 		clear(&bf.memory.buf)
 192 | 		bf.flushed_len = 0
 193 | 		bf.memory_pos = 0
 194 | 		bf.pos = 0
 195 | 		bf.file_len = nil
 196 | 	}
 197 | 
 198 | 	db.core = core
 199 | 	db.hasher = h
 200 | 	db.tx_start = nil
 201 | 	db.transaction = nil
 202 | 
 203 | 	core_seek_to(core, 0) or_return  // <== [calls core_seek_to]
 204 | 	length := core_length(core) or_return  // <== [calls core_length]
 205 | 
 206 | 	if length == 0 {
 207 | 		file_id := h.file_id
 208 | 		if file_id == 0 {
 209 | 			file_id = _random_u64()  // <== [calls _random_u64]
 210 | 		}
 211 | 		digest_len := h.hash_size
 212 | 		if digest_len == 0 {
 213 | 			digest_len = 20
 214 | 		}
 215 | 		db.header = Header{
 216 | 			file_id      = file_id,
 217 | 			hash_id      = h.id,
 218 | 			hash_size    = digest_len,
 219 | 			version      = VERSION,
 220 | 			padding      = 0,
 221 | 			magic_number = MAGIC_NUMBER,
 222 | 		}
 223 | 		header_write(db.header, core) or_return  // <== [calls header_write]
 224 | 		rh_bytes := root_header_to_bytes(Root_Header{file_size = 0, root = Slot{}})  // <== [calls root_header_to_bytes]
 225 | 		core_write_all(core, rh_bytes[:]) or_return  // <== [calls core_write_all]
 226 | 		database_commit_root(&db, Slot{}, 0) or_return  // <== [calls database_commit_root]
 227 | 		core_sync(core) or_return  // <== [calls core_sync]
 228 | 	} else {
 229 | 		db.header = database_read_and_validate_header(&db) or_return  // <== [calls database_read_and_validate_header]
 230 | 		_ = database_committed_size(&db) or_return  // <== [calls database_committed_size]
 231 | 	}
 232 | 
 233 | 	db.tx_start = nil
 234 | 	return db, nil
 235 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 1` (`L237–L244`)

```odin
 237 | @(private)
 238 | _random_u64 :: proc() -> u64 {
 239 | 	v := rand.uint64()
 240 | 	if v == 0 {
 241 | 		v = 1
 242 | 	}
 243 | 	return v
 244 | }
```

#### [`database_read_and_validate_header`](../../xitdb/database.odin#L272-L280) — `DEPTH 1` (`L272–L280`)

```odin
 272 | database_read_and_validate_header :: proc(db: ^Database) -> (res: Header, err: Error) {
 273 | 	core_seek_to(db.core, 0) or_return  // <== [calls core_seek_to]
 274 | 	header := header_read(db.core) or_return  // <== [calls header_read]
 275 | 	header_validate(header) or_return  // <== [calls header_validate]
 276 | 	if db.hasher.hash_size != 0 && header.hash_size != db.hasher.hash_size {
 277 | 		return {}, .Invalid_Hash_Size
 278 | 	}
 279 | 	return header, nil
 280 | }
```

#### [`database_root_cursor`](../../xitdb/database.odin#L283-L298) — `ENTRY POINT` (`L283–L298`)

```odin
 283 | database_root_cursor :: proc(db: ^Database) -> Write_Cursor {
 284 | 	root, err := database_read_root_slot(db)  // <== [calls database_read_root_slot]
 285 | 	if err != nil {
 286 | 		root = Slot{}
 287 | 	}
 288 | 	return Write_Cursor{
 289 | 		read_cursor = Read_Cursor{
 290 | 			slot_ptr = Slot_Pointer{
 291 | 				position = i64(ROOT_HEADER_START),
 292 | 				slot     = root,
 293 | 			},
 294 | 			db        = db,
 295 | 			frozen_at = 0,
 296 | 		},
 297 | 	}
 298 | }
```

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 2` (`L319–L334`)

```odin
 319 | @(private)
 320 | _database_committed_size_with_header :: proc(db: ^Database, header: Root_Header) -> (committed_size: i64, file_size: i64, err: Error) {
 321 | 	minimum_size := i64(ROOT_HEADER_END + ROOT_TRAILER_LENGTH)
 322 | 	if header.file_size < minimum_size {
 323 | 		return 0, 0, .Invalid_Database
 324 | 	}
 325 | 	file_size = core_length(db.core) or_return  // <== [calls core_length]
 326 | 	if file_size < header.file_size {
 327 | 		return 0, 0, .Truncated_Database
 328 | 	}
 329 | 	trailer := database_read_root_trailer(db, header.file_size) or_return  // <== [calls database_read_root_trailer]
 330 | 	if trailer.root != header.root {
 331 | 		return 0, 0, .Invalid_Database
 332 | 	}
 333 | 	return header.file_size, file_size, nil
 334 | }
```

#### [`database_committed_size`](../../xitdb/database.odin#L337-L341) — `DEPTH 1` (`L337–L341`)

```odin
 337 | database_committed_size :: proc(db: ^Database) -> (res: i64, err: Error) {
 338 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 339 | 	committed_size, _ := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 340 | 	return committed_size, nil
 341 | }
```

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

#### [`database_read_root_slot`](../../xitdb/database.odin#L379-L382) — `DEPTH 1` (`L379–L382`)

```odin
 379 | database_read_root_slot :: proc(db: ^Database) -> (res: Slot, err: Error) {
 380 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 381 | 	return header.root, nil
 382 | }
```

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 3` (`L384–L398`)

```odin
 384 | database_read_root_trailer :: proc(db: ^Database, end: i64) -> (res: Root_Trailer, err: Error) {
 385 | 	if end < ROOT_TRAILER_LENGTH {
 386 | 		return {}, .Invalid_Database
 387 | 	}
 388 | 	trailer_pos := end - ROOT_TRAILER_LENGTH
 389 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 390 | 	b: [ROOT_TRAILER_LENGTH]u8
 391 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 392 | 	trailer := root_trailer_from_bytes(b)  // <== [calls root_trailer_from_bytes]
 393 | 	if trailer.checksum != compute_root_trailer_checksum(db.header.file_id, trailer_pos, trailer.root, trailer.commit_id) {  // <== [calls compute_root_trailer_checksum]
 394 | 		return {}, .Invalid_Database
 395 | 	}
 396 | 	tag_validate(trailer.root.tag) or_return  // <== [calls tag_validate]
 397 | 	return trailer, nil
 398 | }
```

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 1` (`L400–L407`)

```odin
 400 | database_commit_root :: proc(db: ^Database, root: Slot, commit_id: u64) -> Error {
 401 | 	trailer_pos := core_length(db.core) or_return  // <== [calls core_length]
 402 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 403 | 	trailer := root_trailer_to_bytes(new_root_trailer(db.header.file_id, trailer_pos, root, commit_id))  // <== [calls root_trailer_to_bytes, new_root_trailer]
 404 | 	core_write_all(db.core, trailer[:]) or_return  // <== [calls core_write_all]
 405 | 	core_sync(db.core) or_return  // <== [calls core_sync]
 406 | 	return database_write_root_header(db, root)  // <== [calls database_write_root_header]
 407 | }
```

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 2` (`L409–L414`)

```odin
 409 | database_write_root_header :: proc(db: ^Database, root: Slot) -> Error {
 410 | 	file_size := core_length(db.core) or_return  // <== [calls core_length]
 411 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 412 | 	header := root_header_to_bytes(Root_Header{file_size = file_size, root = root})  // <== [calls root_header_to_bytes]
 413 | 	return core_write_all(db.core, header[:])  // <== [calls core_write_all]
 414 | }
```

### `xitdb/types.odin` (17 procedures · 434 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L175–L353`](../../xitdb/types.odin#L175-L353), [`L571–L691`](../../xitdb/types.odin#L571-L691), [`L825–L834`](../../xitdb/types.odin#L825-L834), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L929–L937`](../../xitdb/types.odin#L929-L937), [`L939–L950`](../../xitdb/types.odin#L939-L950), [`L952–L966`](../../xitdb/types.odin#L952-L966), [`L968–L972`](../../xitdb/types.odin#L968-L972), [`L974–L977`](../../xitdb/types.odin#L974-L977), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`sha1_transf_hw`](../../xitdb/types.odin#L175-L353) — `DEPTH 2` (`L175–L353`)

```odin
 175 | 	@(private = "file", enable_target_feature = "sse2,ssse3,sse4.1,sha")
 176 | 	sha1_transf_hw :: proc "contextless" (state: ^[5]u32, data: []u8) #no_bounds_check {
 177 | 		// Load initial state: state[0..3] = A, B, C, D; state[4] = E
 178 | 		abcd := intrinsics.unaligned_load((^x86.__m128i)(&state[0]))
 179 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B) // lane 3..0 = A, B, C, D
 180 | 		e0 := x86._mm_set_epi32(i32(state[4]), 0, 0, 0)
 181 | 
 182 | 		data := data
 183 | 		for len(data) >= 64 {
 184 | 			abcd_save := abcd
 185 | 			e0_save := e0
 186 | 
 187 | 			// Rounds 0..3
 188 | 			msg0 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[0:])))
 189 | 			msg0 = x86._mm_shuffle_epi8(msg0, SHA1_SHUF_MASK)
 190 | 			e0 = x86._mm_add_epi32(e0, msg0)
 191 | 			e1 := abcd
 192 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 193 | 
 194 | 			// Rounds 4..7
 195 | 			msg1 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[16:])))
 196 | 			msg1 = x86._mm_shuffle_epi8(msg1, SHA1_SHUF_MASK)
 197 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 198 | 			e0 = abcd
 199 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 200 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 201 | 
 202 | 			// Rounds 8..11
 203 | 			msg2 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[32:])))
 204 | 			msg2 = x86._mm_shuffle_epi8(msg2, SHA1_SHUF_MASK)
 205 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 206 | 			e1 = abcd
 207 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 208 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 209 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 210 | 
 211 | 			// Rounds 12..15
 212 | 			msg3 := intrinsics.unaligned_load((^x86.__m128i)(raw_data(data[48:])))
 213 | 			msg3 = x86._mm_shuffle_epi8(msg3, SHA1_SHUF_MASK)
 214 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 215 | 			e0 = abcd
 216 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 217 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 0)
 218 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 219 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 220 | 
 221 | 			// Rounds 16..19
 222 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 223 | 			e1 = abcd
 224 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 225 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 0)
 226 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 227 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 228 | 
 229 | 			// Rounds 20..23
 230 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 231 | 			e0 = abcd
 232 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 233 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 234 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 235 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 236 | 
 237 | 			// Rounds 24..27
 238 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 239 | 			e1 = abcd
 240 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 241 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 242 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 243 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 244 | 
 245 | 			// Rounds 28..31
 246 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 247 | 			e0 = abcd
 248 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 249 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 250 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 251 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 252 | 
 253 | 			// Rounds 32..35
 254 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 255 | 			e1 = abcd
 256 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 257 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 1)
 258 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 259 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 260 | 
 261 | 			// Rounds 36..39
 262 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 263 | 			e0 = abcd
 264 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 265 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 1)
 266 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 267 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 268 | 
 269 | 			// Rounds 40..43
 270 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 271 | 			e1 = abcd
 272 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 273 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 274 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 275 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 276 | 
 277 | 			// Rounds 44..47
 278 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 279 | 			e0 = abcd
 280 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 281 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 282 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 283 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 284 | 
 285 | 			// Rounds 48..51
 286 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 287 | 			e1 = abcd
 288 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 289 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 290 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 291 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 292 | 
 293 | 			// Rounds 52..55
 294 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 295 | 			e0 = abcd
 296 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 297 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 2)
 298 | 			msg0 = x86._mm_sha1msg1_epu32(msg0, msg1)
 299 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 300 | 
 301 | 			// Rounds 56..59
 302 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 303 | 			e1 = abcd
 304 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 305 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 2)
 306 | 			msg1 = x86._mm_sha1msg1_epu32(msg1, msg2)
 307 | 			msg0 = x86._mm_xor_si128(msg0, msg2)
 308 | 
 309 | 			// Rounds 60..63
 310 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 311 | 			e0 = abcd
 312 | 			msg0 = x86._mm_sha1msg2_epu32(msg0, msg3)
 313 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 314 | 			msg2 = x86._mm_sha1msg1_epu32(msg2, msg3)
 315 | 			msg1 = x86._mm_xor_si128(msg1, msg3)
 316 | 
 317 | 			// Rounds 64..67
 318 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg0)
 319 | 			e1 = abcd
 320 | 			msg1 = x86._mm_sha1msg2_epu32(msg1, msg0)
 321 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 322 | 			msg3 = x86._mm_sha1msg1_epu32(msg3, msg0)
 323 | 			msg2 = x86._mm_xor_si128(msg2, msg0)
 324 | 
 325 | 			// Rounds 68..71
 326 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg1)
 327 | 			e0 = abcd
 328 | 			msg2 = x86._mm_sha1msg2_epu32(msg2, msg1)
 329 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 330 | 			msg3 = x86._mm_xor_si128(msg3, msg1)
 331 | 
 332 | 			// Rounds 72..75
 333 | 			e0 = x86._mm_sha1nexte_epu32(e0, msg2)
 334 | 			e1 = abcd
 335 | 			msg3 = x86._mm_sha1msg2_epu32(msg3, msg2)
 336 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e0, 3)
 337 | 
 338 | 			// Rounds 76..79
 339 | 			e1 = x86._mm_sha1nexte_epu32(e1, msg3)
 340 | 			e0 = abcd
 341 | 			abcd = x86._mm_sha1rnds4_epu32(abcd, e1, 3)
 342 | 
 343 | 			// Combine state
 344 | 			e0 = x86._mm_sha1nexte_epu32(e0, e0_save)
 345 | 			abcd = x86._mm_add_epi32(abcd, abcd_save)
 346 | 
 347 | 			data = data[64:]
 348 | 		}
 349 | 
 350 | 		abcd = x86._mm_shuffle_epi32(abcd, 0x1B)
 351 | 		intrinsics.unaligned_store((^x86.__m128i)(&state[0]), abcd)
 352 | 		state[4] = u32(x86._mm_extract_epi32(e0, 3))
 353 | 	}
```

#### [`sha1_sum_into`](../../xitdb/types.odin#L571-L691) — `DEPTH 1` (`L571–L691`)

```odin
 571 | sha1_sum_into :: proc(data: []u8, out: []u8) #no_bounds_check {
 572 | 	state := [5]u32{
 573 | 		0x67452301,
 574 | 		0xEFCDAB89,
 575 | 		0x98BADCFE,
 576 | 		0x10325476,
 577 | 		0xC3D2E1F0,
 578 | 	}
 579 | 
 580 | 	when ODIN_ARCH == .amd64 {
 581 | 		if _has_sha_ni {
 582 | 			full_len := len(data) & ~int(63)
 583 | 			if full_len > 0 {
 584 | 				sha1_transf_hw(&state, data[:full_len])  // <== [calls sha1_transf_hw]
 585 | 			}
 586 | 			rem := len(data) - full_len
 587 | 			bit_len := u64(len(data)) * 8
 588 | 			if rem < 56 {
 589 | 				tail: [64]u8
 590 | 				copy(tail[:rem], data[full_len:])
 591 | 				tail[rem] = 0x80
 592 | 				endian.unchecked_put_u64be(tail[56:64], bit_len)
 593 | 				sha1_transf_hw(&state, tail[0:64])  // <== [calls sha1_transf_hw]
 594 | 			} else {
 595 | 				tail: [128]u8
 596 | 				copy(tail[:rem], data[full_len:])
 597 | 				tail[rem] = 0x80
 598 | 				endian.unchecked_put_u64be(tail[120:128], bit_len)
 599 | 				sha1_transf_hw(&state, tail[0:128])  // <== [calls sha1_transf_hw]
 600 | 			}
 601 | 			endian.unchecked_put_u32be(out[0:4], state[0])
 602 | 			endian.unchecked_put_u32be(out[4:8], state[1])
 603 | 			endian.unchecked_put_u32be(out[8:12], state[2])
 604 | 			endian.unchecked_put_u32be(out[12:16], state[3])
 605 | 			endian.unchecked_put_u32be(out[16:20], state[4])
 606 | 			return
 607 | 		}
 608 | 	}
 609 | 
 610 | 	h0, h1, h2, h3, h4 := state[0], state[1], state[2], state[3], state[4]
 611 | 
 612 | 	rol32 :: #force_inline proc(x: u32, n: uint) -> u32 {
 613 | 		return (x << n) | (x >> (32 - n))
 614 | 	}
 615 | 
 616 | 	process_block :: proc(block: []u8, h0, h1, h2, h3, h4: ^u32) {
 617 | 		w: [80]u32
 618 | 		for i in 0 ..< 16 {
 619 | 			v, _ := endian.get_u32(block[i * 4:i * 4 + 4], .Big)
 620 | 			w[i] = v
 621 | 		}
 622 | 		for i in 16 ..< 80 {
 623 | 			x := w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16]
 624 | 			w[i] = (x << 1) | (x >> 31)
 625 | 		}
 626 | 
 627 | 		a := h0^
 628 | 		b := h1^
 629 | 		c := h2^
 630 | 		d := h3^
 631 | 		e := h4^
 632 | 
 633 | 		for i in 0 ..< 80 {
 634 | 			f, k: u32
 635 | 			if i < 20 {
 636 | 				f = (b & c) | ((~b) & d)
 637 | 				k = 0x5A827999
 638 | 			} else if i < 40 {
 639 | 				f = b ~ c ~ d
 640 | 				k = 0x6ED9EBA1
 641 | 			} else if i < 60 {
 642 | 				f = (b & c) | (b & d) | (c & d)
 643 | 				k = 0x8F1BBCDC
 644 | 			} else {
 645 | 				f = b ~ c ~ d
 646 | 				k = 0xCA62C1D6
 647 | 			}
 648 | 			temp := ((a << 5) | (a >> 27)) + f + e + k + w[i]
 649 | 			e = d
 650 | 			d = c
 651 | 			c = (b << 30) | (b >> 2)
 652 | 			b = a
 653 | 			a = temp
 654 | 		}
 655 | 
 656 | 		h0^ += a
 657 | 		h1^ += b
 658 | 		h2^ += c
 659 | 		h3^ += d
 660 | 		h4^ += e
 661 | 	}
 662 | 
 663 | 	i := 0
 664 | 	for i + 64 <= len(data) {
 665 | 		process_block(data[i:i + 64], &h0, &h1, &h2, &h3, &h4)
 666 | 		i += 64
 667 | 	}
 668 | 
 669 | 	rem := len(data) - i
 670 | 	bit_len := u64(len(data)) * 8
 671 | 	if rem < 56 {
 672 | 		tail: [64]u8
 673 | 		copy(tail[:rem], data[i:])
 674 | 		tail[rem] = 0x80
 675 | 		endian.put_u64(tail[56:64], .Big, bit_len)
 676 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 677 | 	} else {
 678 | 		tail: [128]u8
 679 | 		copy(tail[:rem], data[i:])
 680 | 		tail[rem] = 0x80
 681 | 		endian.put_u64(tail[120:128], .Big, bit_len)
 682 | 		process_block(tail[0:64], &h0, &h1, &h2, &h3, &h4)
 683 | 		process_block(tail[64:128], &h0, &h1, &h2, &h3, &h4)
 684 | 	}
 685 | 
 686 | 	endian.put_u32(out[0:4], .Big, h0)
 687 | 	endian.put_u32(out[4:8], .Big, h1)
 688 | 	endian.put_u32(out[8:12], .Big, h2)
 689 | 	endian.put_u32(out[12:16], .Big, h3)
 690 | 	endian.put_u32(out[16:20], .Big, h4)
 691 | }
```

#### [`sha1_hasher`](../../xitdb/types.odin#L825-L834) — `ENTRY POINT` (`L825–L834`)

```odin
 825 | sha1_hasher :: proc(id: u32 = 0, file_id: u64 = 0) -> Hasher {
 826 | 	return Hasher{
 827 | 		hash_proc = proc(data: []u8, out_hash: []u8, _: rawptr) {
 828 | 			sha1_sum_into(data, out_hash)  // <== [calls sha1_sum_into]
 829 | 		},
 830 | 		hash_size = 20,
 831 | 		id        = id,
 832 | 		file_id   = file_id,
 833 | 	}
 834 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 2` (`L871–L877`)

```odin
 871 | slot_to_bytes :: #force_inline proc(s: Slot) -> [SLOT_LENGTH]u8 {
 872 | 	buf: [SLOT_LENGTH]u8 = ---
 873 | 	full_bit := u8(0x80) if s.full else u8(0)
 874 | 	buf[0] = full_bit | (u8(s.tag) & 0x7f)
 875 | 	endian.unchecked_put_u64be(buf[1:9], u64(s.value))
 876 | 	return buf
 877 | }
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

#### [`header_validate`](../../xitdb/types.odin#L929-L937) — `DEPTH 2` (`L929–L937`)

```odin
 929 | header_validate :: proc(h: Header) -> Error {
 930 | 	if h.magic_number != MAGIC_NUMBER {
 931 | 		return .Invalid_Database
 932 | 	}
 933 | 	if h.version != VERSION {
 934 | 		return .Invalid_Version
 935 | 	}
 936 | 	return nil
 937 | }
```

#### [`header_to_bytes`](../../xitdb/types.odin#L939-L950) — `DEPTH 2` (`L939–L950`)

```odin
 939 | header_to_bytes :: proc(h: Header) -> [HEADER_LENGTH]u8 {
 940 | 	buf: [HEADER_LENGTH]u8
 941 | 	buf[0] = h.magic_number[0]
 942 | 	buf[1] = h.magic_number[1]
 943 | 	buf[2] = h.magic_number[2]
 944 | 	buf[3] = h.padding
 945 | 	endian.put_u16(buf[4:6], .Big, h.version)
 946 | 	endian.put_u16(buf[6:8], .Big, h.hash_size)
 947 | 	endian.put_u32(buf[8:12], .Big, h.hash_id)
 948 | 	endian.put_u64(buf[12:20], .Big, h.file_id)
 949 | 	return buf
 950 | }
```

#### [`header_from_bytes`](../../xitdb/types.odin#L952-L966) — `DEPTH 3` (`L952–L966`)

```odin
 952 | header_from_bytes :: proc(buf: [HEADER_LENGTH]u8) -> Header {
 953 | 	b := buf
 954 | 	version, _ := endian.get_u16(b[4:6], .Big)
 955 | 	hash_size, _ := endian.get_u16(b[6:8], .Big)
 956 | 	hash_id, _ := endian.get_u32(b[8:12], .Big)
 957 | 	file_id, _ := endian.get_u64(b[12:20], .Big)
 958 | 	return Header{
 959 | 		magic_number = {b[0], b[1], b[2]},
 960 | 		padding      = b[3],
 961 | 		version      = version,
 962 | 		hash_size    = hash_size,
 963 | 		hash_id      = hash_id,
 964 | 		file_id      = file_id,
 965 | 	}
 966 | }
```

#### [`header_read`](../../xitdb/types.odin#L968-L972) — `DEPTH 2` (`L968–L972`)

```odin
 968 | header_read :: proc(r: ^Core) -> (h: Header, err: Error) {
 969 | 	buf: [HEADER_LENGTH]u8
 970 | 	core_read_exact(r, buf[:]) or_return  // <== [calls core_read_exact]
 971 | 	return header_from_bytes(buf), nil  // <== [calls header_from_bytes]
 972 | }
```

#### [`header_write`](../../xitdb/types.odin#L974-L977) — `DEPTH 1` (`L974–L977`)

```odin
 974 | header_write :: proc(h: Header, w: ^Core) -> Error {
 975 | 	buf := header_to_bytes(h)  // <== [calls header_to_bytes]
 976 | 	return core_write_all(w, buf[:])  // <== [calls core_write_all]
 977 | }
```

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 1` (`L985–L991`)

```odin
 985 | root_header_to_bytes :: proc(rh: Root_Header) -> [ROOT_HEADER_LENGTH]u8 {
 986 | 	buf: [ROOT_HEADER_LENGTH]u8
 987 | 	slot_bytes := slot_to_bytes(rh.root)  // <== [calls slot_to_bytes]
 988 | 	copy(buf[0:9], slot_bytes[:])
 989 | 	endian.put_u64(buf[9:17], .Big, u64(rh.file_size))
 990 | 	return buf
 991 | }
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

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 3` (`L1012–L1020`)

```odin
1012 | compute_root_trailer_checksum :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> u64 {
1013 | 	data: [33]u8
1014 | 	endian.put_u64(data[0:8], .Big, file_id)
1015 | 	endian.put_u64(data[8:16], .Big, u64(position))
1016 | 	slot_bytes := slot_to_bytes(root)  // <== [calls slot_to_bytes]
1017 | 	copy(data[16:25], slot_bytes[:])
1018 | 	endian.put_u64(data[25:33], .Big, commit_id)
1019 | 	return hash.crc64_xz(data[:])
1020 | }
```

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 2` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 2` (`L1030–L1037`)

```odin
1030 | root_trailer_to_bytes :: proc(rt: Root_Trailer) -> [ROOT_TRAILER_LENGTH]u8 {
1031 | 	buf: [ROOT_TRAILER_LENGTH]u8
1032 | 	slot_bytes := slot_to_bytes(rt.root)  // <== [calls slot_to_bytes]
1033 | 	copy(buf[0:9], slot_bytes[:])
1034 | 	endian.put_u64(buf[9:17], .Big, rt.commit_id)
1035 | 	endian.put_u64(buf[17:25], .Big, rt.checksum)
1036 | 	return buf
1037 | }
```

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 4` (`L1039–L1051`)

```odin
1039 | root_trailer_from_bytes :: proc(buf: [ROOT_TRAILER_LENGTH]u8) -> Root_Trailer {
1040 | 	b := buf
1041 | 	slot_buf: [SLOT_LENGTH]u8
1042 | 	copy(slot_buf[:], b[0:9])
1043 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
1044 | 	commit_id, _ := endian.get_u64(b[9:17], .Big)
1045 | 	checksum, _ := endian.get_u64(b[17:25], .Big)
1046 | 	return Root_Trailer{
1047 | 		checksum  = checksum,
1048 | 		commit_id = commit_id,
1049 | 		root      = root,
1050 | 	}
1051 | }
```

