# #63. `DB: Re-open & trailer checksum verify` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L2087-L2102`)](../bench_xitdb.odin#L2087-L2102) · [Zig Harness (`bench_xitdb.zig#L2265-L2279`)](../bench_xitdb.zig#L2265-L2279)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **56** | 56.4 ± 0.5 | 1.0% | 57.0 | 17,857,143 | - | **4.45x Odin** (`z = 109.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 249 | 249.2 ± 3.9 | 1.6% | 253.0 | 4,016,064 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Unified Read-From-Write-Buffer in `Core_Buffered_File` (`#59` — 4.06x faster in Odin: `4.58 ms` vs `18.57 ms`):** In Zig's [`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5068-L5220), only writes are buffered (`write_buf`); **every `reader.seekTo()` flushes the entire write buffer to the OS via `pwritev` and issues a `preadv` syscall**. Because HAMT/B-Tree transactions interleave slot reads and block appends, Zig flushes the write buffer on nearly every slot read! Odin's [`Core_Buffered_File`](../../xitdb/core.odin#L219-L437) serves reads that fall inside the active write window `[buf_start, buf_start + buf_len)` **directly from memory without flushing**, and caches committed read pages below `buf_start`.
- **Cached Root Header on Truncate & Re-Open (`#61–#63` — 1.75x–4.45x faster in Odin):** Odin's `_database_truncate_with_header` ([`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362)) reuses the already-read `Root_Header` instead of re-reading `ROOT_HEADER_START` twice per transaction.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Serve in-range reads from `CoreBufferedFile.write_buf` before flushing (`~12 lines` in [`lib.zig#L5083-L5115`](../../reference/xitdb-zig/src/lib.zig#L5083-L5115)):** In `CoreBufferedFile.Reader.stream`, check if `[offset, offset + n)` lies within `[write_buf_start, write_buf_start + write_buf_len)`. If so, `@memcpy` directly from `write_buf` without calling `flush()`. This single 12-line check eliminates ~90% of `pwritev`/`preadv` syscalls during buffered file transactions.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L2087-L2102`](../bench_xitdb.odin#L2087-L2102))

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

### Zig ([`benchmarks/bench_xitdb.zig#L2265-L2279`](../bench_xitdb.zig#L2265-L2279))

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

### Reached Odin Procedures (`36` procedures across `3` files · `812` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
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
