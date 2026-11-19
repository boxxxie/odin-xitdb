# #39. `Replication (genesis -> 200 moments)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1418-L1436`)](../bench_xitdb.odin#L1418-L1436) · [Zig Harness (`bench_xitdb.zig#L1388-L1411`)](../bench_xitdb.zig#L1388-L1411)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **775** | 782.8 ± 29.1 | 3.7% | 817.6 | 1,290,323 | 250.9 KB | **1.73x Odin** (`z = 9.1`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,338 | 1,306.6 ± 125.4 | 9.6% | 1,433.6 | 747,384 | 250.9 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Direct Slice Copy in Replication ([`xitdb/compact_replicate.odin#L816-L928`](../../xitdb/compact_replicate.odin#L816-L928)):** On `#39 Replication (genesis -> 200 moments)` (**8.18x faster in Odin**) and `#40 Incremental 1-moment delta` (**1.90x faster**), Odin copies committed byte slices directly between buffers and verifies the 25-byte `Root_Trailer` CRC-64/XZ without unbuffered `std.Io` vtable streaming.
- **Open-Addressed `Memory_Offset_Map` & Single-Pass Block Reserve ([`xitdb/compact_replicate.odin#L11-L811`](../../xitdb/compact_replicate.odin#L11-L811)):** On `#41` (**2.97x faster**), `#42` (**1.18x faster**), and `#43` (**3.22x faster**), Odin uses a flat open-addressed `Memory_Offset_Map`, reserves `Core_Memory` blocks in one `non_zero_resize`, and visits `0 ..< num` active B-Tree slots in stack buffers, whereas `Compactor` in [`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911) writes remapped slots via per-element `writeInt` calls and loops over all 16 slots.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Pre-size `CoreMemory` target buffer & batch-write remapped slots in `Compactor` ([`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911)):** Visiting `0..header.num` and writing each compacted node in one `writeAll` (after pre-reserving the target `CoreMemory` buffer instead of zero-writing twice) eliminates per-slot `writeInt` vtable dispatches.
- **Streamlined `readCommitted` / `applyReplicated` slice copies (`#39–#40`):** Copying committed byte slices directly on `CoreMemory` avoids unbuffered `std.Io` vtable overhead.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1418-L1436`](../bench_xitdb.odin#L1418-L1436))

```odin
1418 | 	// 4a. Replicate all moments to a fresh secondary replica
1419 | 	rep_core: xitdb.Core = xitdb.core_memory_init()
1420 | 	defer xitdb.core_destroy(&rep_core)
1421 | 	rep_db, _ := xitdb.database_init(&rep_core, xitdb.sha1_hasher())
1422 | 
1423 | 	t0 := time.now()
1424 | 	rep_state, _ := xitdb.database_replica_state(&rep_db)
1425 | 	start_off, _ := xitdb.database_replication_start(&db, rep_state)
1426 | 	end_off, _ := xitdb.database_committed_size(&db)
1427 | 	payload, _ := xitdb.database_read_committed_bytes(&db, start_off, end_off, context.temp_allocator)
1428 | 	_ = xitdb.database_apply_replicated_bytes(&rep_db, start_off, payload)
1429 | 	elapsed_rep := time.since(t0)
1430 | 
1431 | 	print_result(Bench_Result{
1432 | 		name       = "Replication (genesis -> 200 moments)",
1433 | 		ops        = moments_count,
1434 | 		elapsed    = elapsed_rep,
1435 | 		bytes_used = end_off,
1436 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1388-L1411`](../bench_xitdb.zig#L1388-L1411))

```zig
1388 |     // 4a. Replicate all moments to a fresh secondary replica
1389 |     var rep_buffer = std.Io.Writer.Allocating.init(allocator);
1390 |     defer rep_buffer.deinit();
1391 |     var rep_db = try DB.init(io, .{ .buffer = &rep_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1392 | 
1393 |     var payload_buf = std.Io.Writer.Allocating.init(allocator);
1394 |     defer payload_buf.deinit();
1395 | 
1396 |     const t0 = std.Io.Clock.awake.now(io);
1397 |     const rep_state = try rep_db.replicaState();
1398 |     const start_off = try db.replicationStart(rep_state);
1399 |     const end_off = try db.committedSize();
1400 |     payload_buf.clearRetainingCapacity();
1401 |     try db.readCommitted(start_off, end_off, &payload_buf.writer);
1402 |     var rep_reader = std.Io.Reader.fixed(payload_buf.written());
1403 |     try rep_db.applyReplicated(start_off, &rep_reader, end_off - start_off);
1404 |     const elapsed_rep = t0.untilNow(io, .awake).nanoseconds;
1405 | 
1406 |     try printResult(stdout, .{
1407 |         .name = "Replication (genesis -> 200 moments)",
1408 |         .ops = moments_count,
1409 |         .elapsed_ns = elapsed_rep,
1410 |         .bytes_used = end_off,
1411 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `compact` | 60 | Top-level `Database.compact` reachability-copy entry point | [`lib.zig#L650-L709`](../../reference/xitdb-zig/src/lib.zig#L650-L709) |
| `Compactor` | 406 | Reachability-based garbage-collecting compactor (`std.AutoHashMap` / custom `OffsetMap`) | [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) |
| `readCommitted` | 16 | Committed byte-range streaming for incremental replication | [`lib.zig#L592-L607`](../../reference/xitdb-zig/src/lib.zig#L592-L607) |
| `applyReplicated` | 25 | Replica byte-stream application and root trailer verification | [`lib.zig#L613-L637`](../../reference/xitdb-zig/src/lib.zig#L613-L637) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |
| `CoreBufferedFile` | 166 | Contiguous tail-buffered OS file backend (`flush` clears buffer on `sync`) | [`lib.zig#L5067-L5232`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232) |

### Reached Odin Procedures (`54` procedures across `4` files · `1250` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 28 | [`xitdb/core.odin#L85-L112`](../../xitdb/core.odin#L85-L112) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 30 | [`xitdb/core.odin#L351-L380`](../../xitdb/core.odin#L351-L380) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/compact_replicate.odin` | `database_replica_state` | **Entry Point** (`depth 0`) | 9 | [`xitdb/compact_replicate.odin#L825-L833`](../../xitdb/compact_replicate.odin#L825-L833) |
| `xitdb/compact_replicate.odin` | `database_replication_start` | **Entry Point** (`depth 0`) | 18 | [`xitdb/compact_replicate.odin#L838-L855`](../../xitdb/compact_replicate.odin#L838-L855) |
| `xitdb/compact_replicate.odin` | `database_read_committed_bytes` | **Entry Point** (`depth 0`) | 21 | [`xitdb/compact_replicate.odin#L928-L948`](../../xitdb/compact_replicate.odin#L928-L948) |
| `xitdb/compact_replicate.odin` | `database_apply_replicated_bytes` | **Entry Point** (`depth 0`) | 48 | [`xitdb/compact_replicate.odin#L1022-L1069`](../../xitdb/compact_replicate.odin#L1022-L1069) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 1` (from `core_memory_init`, `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `_memory_destroy` | `depth 1` (from `core_destroy`, `_overlay_destroy`) | 14 | [`xitdb/core.odin#L207-L220`](../../xitdb/core.odin#L207-L220) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_overlay_destroy` | `depth 1` (from `core_destroy`) | 11 | [`xitdb/core.odin#L222-L232`](../../xitdb/core.odin#L222-L232) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `database_write_headers`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_read_file_size`, `database_commit_root`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L293-L300`](../../xitdb/database.odin#L293-L300) |
| `xitdb/database.odin` | `database_read_file_size` | `depth 1` (from `database_init`, `database_replica_state`) | 7 | [`xitdb/database.odin#L315-L321`](../../xitdb/database.odin#L315-L321) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_apply_replicated_bytes`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_write_headers` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`) | 8 | [`xitdb/database.odin#L304-L311`](../../xitdb/database.odin#L304-L311) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`, `database_replica_state`, `database_replication_start`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L574-L694`](../../xitdb/types.odin#L574-L694) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 1` (from `database_replica_state`, `database_replication_start`, `database_read_committed_bytes`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 1` (from `database_read_committed_bytes`, `database_read_root_trailer`, `header_read_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 1` (from `database_apply_replicated_bytes`, `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_validate` | `depth 1` (from `database_apply_replicated_bytes`, `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_committed_size`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 1` (from `database_apply_replicated_bytes`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_apply_replicated_bytes`, `database_write_headers`, `database_commit_root`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 2` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 2` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `tag_validate` | `depth 2` (from `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/core.odin` | `core_read_at` | `depth 2` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_memory_resize` | `depth 2` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 2` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/core.odin` | `core_write_i64` | `depth 2` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 2` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 3` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 3` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `_overlay_page` | `depth 3` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
