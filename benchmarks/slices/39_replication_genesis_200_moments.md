# #39. `Replication (genesis -> 200 moments)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1372-L1390`)](../bench_xitdb.odin#L1372-L1390) · [Zig Harness (`bench_xitdb.zig#L1388-L1411`)](../bench_xitdb.zig#L1388-L1411)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **104** | 102.8 ± 1.6 | 1.6% | 104.0 | 9,615,385 | 250.9 KB | **8.18x Odin** (`z = 45.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 851 | 871.6 ± 37.5 | 4.3% | 921.2 | 1,175,088 | 250.9 KB | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1372-L1390`](../bench_xitdb.odin#L1372-L1390))

```odin
1372 | 	// 4a. Replicate all moments to a fresh secondary replica
1373 | 	rep_core: xitdb.Core = xitdb.core_memory_init()
1374 | 	defer xitdb.core_destroy(&rep_core)
1375 | 	rep_db, _ := xitdb.database_init(&rep_core, xitdb.sha1_hasher())
1376 | 
1377 | 	t0 := time.now()
1378 | 	rep_state, _ := xitdb.database_replica_state(&rep_db)
1379 | 	start_off, _ := xitdb.database_replication_start(&db, rep_state)
1380 | 	end_off, _ := xitdb.database_committed_size(&db)
1381 | 	payload, _ := xitdb.database_read_committed_bytes(&db, start_off, end_off, context.temp_allocator)
1382 | 	_ = xitdb.database_apply_replicated_bytes(&rep_db, start_off, payload)
1383 | 	elapsed_rep := time.since(t0)
1384 | 
1385 | 	print_result(Bench_Result{
1386 | 		name       = "Replication (genesis -> 200 moments)",
1387 | 		ops        = moments_count,
1388 | 		elapsed    = elapsed_rep,
1389 | 		bytes_used = end_off,
1390 | 	})
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

### Reached Odin Procedures (`42` procedures across `4` files · `936` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/compact_replicate.odin` | `database_replica_state` | **Entry Point** (`depth 0`) | 5 | [`xitdb/compact_replicate.odin#L818-L822`](../../xitdb/compact_replicate.odin#L818-L822) |
| `xitdb/compact_replicate.odin` | `database_replication_start` | **Entry Point** (`depth 0`) | 18 | [`xitdb/compact_replicate.odin#L827-L844`](../../xitdb/compact_replicate.odin#L827-L844) |
| `xitdb/compact_replicate.odin` | `database_read_committed_bytes` | **Entry Point** (`depth 0`) | 23 | [`xitdb/compact_replicate.odin#L918-L940`](../../xitdb/compact_replicate.odin#L918-L940) |
| `xitdb/compact_replicate.odin` | `database_apply_replicated_bytes` | **Entry Point** (`depth 0`) | 29 | [`xitdb/compact_replicate.odin#L994-L1022`](../../xitdb/compact_replicate.odin#L994-L1022) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_apply_replicated_bytes`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `_database_committed_size_with_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `header_write`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`, `database_replica_state`, `database_replication_start`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 1` (from `database_replica_state`, `database_replication_start`, `database_read_committed_bytes`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `database_read_committed_bytes`, `database_read_root_trailer`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_apply_replicated_bytes`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_committed_size`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_committed_size`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_memory_resize` | `depth 2` (from `core_write_all`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 2` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 2` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `tag_validate` | `depth 2` (from `database_read_root_trailer`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 2` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `root_trailer_from_bytes`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
