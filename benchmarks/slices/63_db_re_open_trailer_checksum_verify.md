# #63. `DB: Re-open & trailer checksum verify` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L2087-L2102`)](../bench_xitdb.odin#L2087-L2102) · [Zig Harness (`bench_xitdb.zig#L2265-L2279`)](../bench_xitdb.zig#L2265-L2279)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **56** | 57.0 ± 1.4 | 2.5% | 58.8 | 17,857,143 | - | **4.27x Odin** (`z = 41.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 239 | 242.6 ± 10.0 | 4.1% | 256.2 | 4,184,100 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Multi-Handle Coherent `Core_Buffered_File` (`#59` — 1.05x faster in Odin: `16.97 µs` vs `17.85 µs`):** Both Odin ([`xitdb/core.odin#L25-L33`](../../xitdb/core.odin#L25-L33), [`#L144-L152`](../../xitdb/core.odin#L144-L152)) and Zig ([`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232)) clear `memory.buf` and `file_len` in `flush()` so multiple buffered handles taking turns under an external file lock never read stale `Root_Header` or `file_len` values (`spec_buffered_file_multi_handle_alternating_commits_preserve_all_moments`). Within each transaction, Odin's direct `core_slice_at` window reads and stack-buffered node I/O avoid vtable overhead.
- **Single Trailer Validation on Open & Truncate (`#62–#63` — 2.91x–4.27x faster in Odin):** In `#63`, Zig validates the root trailer CRC-64/XZ twice back-to-back (`Database.init` line 536 `committedSize()` then `rootCursor()` line 546 `readRootSlot()`) over an unbuffered `CoreMemory.Reader`. Odin's `_database_truncate_with_header` ([`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362)) and `Core_Memory` slice reads avoid redundant header/trailer round-trips.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Keep `flush()` clearing `memory.buffer` and `file_len = null` in `CoreBufferedFile` ([`lib.zig#L5226-L5231`](../../reference/xitdb-zig/src/lib.zig#L5226-L5231)):** Essential for multi-handle coherency when processes alternate commits on the same file.
- **Reuse validated root `Slot` in `Database.init` + `rootCursor()` ([`lib.zig#L535-L548`](../../reference/xitdb-zig/src/lib.zig#L535-L548)):** Avoid computing the trailer CRC-64/XZ twice when opening an existing database.

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
| `Database.init` | 79 | Database initialization, header validation, `committedSize()`, and `rootCursor()` | [`lib.zig#L470-L548`](../../reference/xitdb-zig/src/lib.zig#L470-L548) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |
| `CoreBufferedFile` | 166 | Contiguous tail-buffered OS file backend (`flush` clears buffer on `sync`) | [`lib.zig#L5067-L5232`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232) |
| `CoreFile` | 38 | Unbuffered OS file descriptor backend | [`lib.zig#L5029-L5066`](../../reference/xitdb-zig/src/lib.zig#L5029-L5066) |
| `freeze` | 7 | Mid-transaction `freeze()` barrier for O(1) structural CoW branching | [`lib.zig#L560-L566`](../../reference/xitdb-zig/src/lib.zig#L560-L566) |
| `commitRoot` | 26 | Transaction trailer append, `core.sync()`, and `writeRootHeader` commit sequence | [`lib.zig#L776-L801`](../../reference/xitdb-zig/src/lib.zig#L776-L801) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |

### Reached Odin Procedures (`37` procedures across `3` files · `810` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_memory_resize` | `depth 2` (from `core_write_all`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 2` (from `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
