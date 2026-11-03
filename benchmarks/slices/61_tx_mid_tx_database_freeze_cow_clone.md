# #61. `Tx: Mid-tx database_freeze + CoW clone` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L2021-L2062`)](../bench_xitdb.odin#L2021-L2062) · [Zig Harness (`bench_xitdb.zig#L2181-L2231`)](../bench_xitdb.zig#L2181-L2231)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **1,118** | 1,114.4 ± 9.4 | 0.8% | 1,122.0 | 894,454 | - | **1.75x Odin** (`z = 21.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,959 | 1,967.2 ± 86.9 | 4.4% | 2,072.2 | 510,465 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Unified Read-From-Write-Buffer in `Core_Buffered_File` (`#59` — 4.06x faster in Odin: `4.58 ms` vs `18.57 ms`):** In Zig's [`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5068-L5220), only writes are buffered (`write_buf`); **every `reader.seekTo()` flushes the entire write buffer to the OS via `pwritev` and issues a `preadv` syscall**. Because HAMT/B-Tree transactions interleave slot reads and block appends, Zig flushes the write buffer on nearly every slot read! Odin's [`Core_Buffered_File`](../../xitdb/core.odin#L219-L437) serves reads that fall inside the active write window `[buf_start, buf_start + buf_len)` **directly from memory without flushing**, and caches committed read pages below `buf_start`.
- **Cached Root Header on Truncate & Re-Open (`#61–#63` — 1.75x–4.45x faster in Odin):** Odin's `_database_truncate_with_header` ([`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362)) reuses the already-read `Root_Header` instead of re-reading `ROOT_HEADER_START` twice per transaction.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Serve in-range reads from `CoreBufferedFile.write_buf` before flushing (`~12 lines` in [`lib.zig#L5083-L5115`](../../reference/xitdb-zig/src/lib.zig#L5083-L5115)):** In `CoreBufferedFile.Reader.stream`, check if `[offset, offset + n)` lies within `[write_buf_start, write_buf_start + write_buf_len)`. If so, `@memcpy` directly from `write_buf` without calling `flush()`. This single 12-line check eliminates ~90% of `pwritev`/`preadv` syscalls during buffered file transactions.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L2021-L2062`](../bench_xitdb.odin#L2021-L2062))

```odin
2021 | 	// 5d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
2022 | 	{
2023 | 		core: xitdb.Core = xitdb.core_memory_init()
2024 | 		defer xitdb.core_destroy(&core)
2025 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
2026 | 
2027 | 		Freeze_Ctx :: struct {
2028 | 			db:    ^xitdb.Database,
2029 | 			iters: int,
2030 | 		}
2031 | 		fctx := Freeze_Ctx{db = &db, iters = commits}
2032 | 
2033 | 		freeze_cow_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
2034 | 			c := (^Freeze_Ctx)(user_data)
2035 | 			top := xitdb.write_hash_map_init(cursor^) or_return
2036 | 			base_wc := xitdb.hash_map_put_cursor(&top, "base") or_return
2037 | 			base_map := xitdb.write_hash_map_init(base_wc) or_return
2038 | 			for j in 0 ..< 16 {
2039 | 				xitdb.hash_map_put(&base_map, fmt.tprintf("k-%02d", j), u64(j)) or_return
2040 | 			}
2041 | 			base_slot := xitdb.hash_map_slot(base_map.read_hash_map) or_return
2042 | 
2043 | 			for i in 0 ..< c.iters {
2044 | 				xitdb.database_freeze(c.db) or_return
2045 | 				fork_key := fmt.tprintf("fork-%04d", i)
2046 | 				xitdb.hash_map_put(&top, fork_key, base_slot) or_return
2047 | 				fork_wc := xitdb.hash_map_put_cursor(&top, fork_key) or_return
2048 | 				fork_map := xitdb.write_hash_map_init(fork_wc) or_return
2049 | 				xitdb.hash_map_put(&fork_map, "k-00", u64(1000 + i)) or_return
2050 | 			}
2051 | 			return nil
2052 | 		}
2053 | 
2054 | 		t_fc := time.now()
2055 | 		_ = xitdb.database_run_context(&db, freeze_cow_cb, &fctx)
2056 | 		elapsed_fc := time.since(t_fc)
2057 | 
2058 | 		print_result(Bench_Result{
2059 | 			name    = "Tx: Mid-tx database_freeze + CoW clone",
2060 | 			ops     = commits,
2061 | 			elapsed = elapsed_fc,
2062 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L2181-L2231`](../bench_xitdb.zig#L2181-L2231))

```zig
2181 |     // 6d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
2182 |     {
2183 |         const DB = xitdb.Database(.memory, HashInt);
2184 |         var buffer = std.Io.Writer.Allocating.init(allocator);
2185 |         defer buffer.deinit();
2186 |         var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
2187 | 
2188 |         const FreezeCowCtx = struct {
2189 |             db: *DB,
2190 |             iters: usize,
2191 | 
2192 |             pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
2193 |                 const top = try DB.HashMap(.read_write).init(cursor.*);
2194 |                 const h_base = hashSha1("base");
2195 |                 try top.putKey(h_base, .{ .bytes = "base" });
2196 |                 const base_wc = try top.putCursor(h_base);
2197 |                 const base_map = try DB.HashMap(.read_write).init(base_wc);
2198 |                 for (0..16) |j| {
2199 |                     var kbuf: [16]u8 = undefined;
2200 |                     const k = try std.fmt.bufPrint(&kbuf, "k-{d:0>2}", .{j});
2201 |                     const hk = hashSha1(k);
2202 |                     try base_map.putKey(hk, .{ .bytes = k });
2203 |                     try base_map.put(hk, .{ .uint = @intCast(j) });
2204 |                 }
2205 |                 const base_slot = try base_map.slot();
2206 |                 const hk00 = hashSha1("k-00");
2207 | 
2208 |                 for (0..self.iters) |i| {
2209 |                     try self.db.freeze();
2210 |                     var fkbuf: [16]u8 = undefined;
2211 |                     const fork_key = try std.fmt.bufPrint(&fkbuf, "fork-{d:0>4}", .{i});
2212 |                     const h_fork = hashSha1(fork_key);
2213 |                     try top.putKey(h_fork, .{ .bytes = fork_key });
2214 |                     try top.put(h_fork, .{ .slot = base_slot });
2215 |                     const fork_wc = try top.putCursor(h_fork);
2216 |                     const fork_map = try DB.HashMap(.read_write).init(fork_wc);
2217 |                     try fork_map.putKey(hk00, .{ .bytes = "k-00" });
2218 |                     try fork_map.put(hk00, .{ .uint = @intCast(1000 + i) });
2219 |                 }
2220 |             }
2221 |         };
2222 | 
2223 |         const t_fc = std.Io.Clock.awake.now(io);
2224 |         try db.runContext(FreezeCowCtx{ .db = &db, .iters = commits });
2225 |         const elapsed_fc = t_fc.untilNow(io, .awake).nanoseconds;
2226 | 
2227 |         try printResult(stdout, .{
2228 |             .name = "Tx: Mid-tx database_freeze + CoW clone",
2229 |             .ops = commits,
2230 |             .elapsed_ns = elapsed_fc,
2231 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |
| `CoreBufferedFile` | 153 | Write-buffered OS file backend | [`lib.zig#L5068-L5220`](../../reference/xitdb-zig/src/lib.zig#L5068-L5220) |
| `CoreFile` | 38 | Unbuffered OS file descriptor backend | [`lib.zig#L5029-L5066`](../../reference/xitdb-zig/src/lib.zig#L5029-L5066) |
| `freeze` | 7 | Mid-transaction `freeze()` barrier for O(1) structural CoW branching | [`lib.zig#L560-L566`](../../reference/xitdb-zig/src/lib.zig#L560-L566) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |

### Reached Odin Procedures (`95` procedures across `6` files · `2064` LOC) (Active `_exec_path_part` arms: `Hash_Map_Init`, `Hash_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L423-L428`](../../xitdb/collections.odin#L423-L428) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/collections.odin` | `hash_map_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L272-L274`](../../xitdb/collections.odin#L272-L274) |
| `xitdb/database.odin` | `database_freeze` | **Entry Point** (`depth 0`) | 9 | [`xitdb/database.odin#L309-L317`](../../xitdb/database.odin#L309-L317) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L302-L306`](../../xitdb/database.odin#L302-L306) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_freeze`, `database_commit_root`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `database_run_context`, `hash_map_put_key_by_hash`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L384-L390`](../../xitdb/collections.odin#L384-L390) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L378-L382`](../../xitdb/collections.odin#L378-L382) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `hash_map_slot`) | 4 | [`xitdb/cursor.odin#L63-L66`](../../xitdb/cursor.odin#L63-L66) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L283-L298`](../../xitdb/database.odin#L283-L298) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `_exec_path_part`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `cursor_slot`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L379-L382`](../../xitdb/database.odin#L379-L382) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1397-L1450`](../../xitdb/database.odin#L1397-L1450) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1384-L1395`](../../xitdb/database.odin#L1384-L1395) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
