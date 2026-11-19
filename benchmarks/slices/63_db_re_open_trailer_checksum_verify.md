# #63. `DB: Re-open & trailer checksum verify` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L2133-L2148`)](../bench_xitdb.odin#L2133-L2148) · [Zig Harness (`bench_xitdb.zig#L2265-L2279`)](../bench_xitdb.zig#L2265-L2279)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **103** | 103.6 ± 1.5 | 1.5% | 105.6 | 9,708,738 | - | **2.65x Odin** (`z = 26.6`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 273 | 267.6 ± 13.7 | 5.1% | 281.0 | 3,663,004 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L2133-L2148`](../bench_xitdb.odin#L2133-L2148))

```odin
2133 | 		// 5e. Database re-open & header/root-trailer checksum validation (`database_init` on populated `Core_Memory`)
2134 | 		reopen_ops := commits * 10
2135 | 		t_reopen := time.now()
2136 | 		for _ in 0 ..< reopen_ops {
2137 | 			reopened_db, r_err := xitdb.database_init(&core, xitdb.sha1_hasher())
2138 | 			assert(r_err == nil)
2139 | 			rc := xitdb.database_root_cursor(&reopened_db)
2140 | 			assert(rc.slot_ptr.slot.tag == .Hash_Map)
2141 | 		}
2142 | 		elapsed_reopen := time.since(t_reopen)
2143 | 
2144 | 		print_result(Bench_Result{
2145 | 			name    = "DB: Re-open & trailer checksum verify",
2146 | 			ops     = reopen_ops,
2147 | 			elapsed = elapsed_reopen,
2148 | 		})
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

### Reached Odin Procedures (`47` procedures across `3` files · `1083` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_write_headers`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_read_file_size`, `database_commit_root`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L293-L300`](../../xitdb/database.odin#L293-L300) |
| `xitdb/database.odin` | `database_read_file_size` | `depth 1` (from `database_init`) | 7 | [`xitdb/database.odin#L315-L321`](../../xitdb/database.odin#L315-L321) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 1` (from `database_init`, `database_read_file_size`, `database_write_headers`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_init`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_write_headers` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L304-L311`](../../xitdb/database.odin#L304-L311) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L574-L694`](../../xitdb/types.odin#L574-L694) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_write_headers`, `database_commit_root`, `header_write`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 2` (from `core_sync`, `core_write_all`, `core_flush`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `header_read_at`, `core_read_i64_at`, `database_read_root_trailer`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 3` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 3` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `core_write_i64` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 4` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `_overlay_page` | `depth 4` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 5` (from `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 5` (from `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
