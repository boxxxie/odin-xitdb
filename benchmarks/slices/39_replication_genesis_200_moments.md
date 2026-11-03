# #39. `Replication (genesis -> 200 moments)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L1372-L1390`)](../bench_xitdb.odin#L1372-L1390) · [Zig Harness (`bench_xitdb.zig#L1388-L1411`)](../bench_xitdb.zig#L1388-L1411)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **104** | 107.2 ± 11.2 | 10.5% | 122.39999999999999 | 9,615,385 | 250.9 KB | **10.04x Odin** (`z = 9.1`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,044 | 1,148.6 ± 255.7 | 22.3% | 1,477.6 | 957,854 | 250.9 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Direct Slice Streaming in Replication ([`xitdb/compact_replicate.odin#L15-L148`](../../xitdb/compact_replicate.odin#L15-L148)):** On `#39 Replication (genesis -> 200 moments)` (**10.04x faster in Odin**) and `#40 Incremental 1-moment delta` (**2.25x faster**), Odin's `database_read_committed_bytes` and `database_apply_replicated_bytes` copy committed byte ranges directly between buffers and verify the 25-byte `Root_Trailer` CRC-64/XZ in place, avoiding `std.Io.Reader.stream` / `std.Io.Writer.drain` 256-byte chunking.
- **Flat Open-Addressed `Memory_Offset_Map` & Buffered `File_Offset_Map` ([`xitdb/compact_replicate.odin#L150-L260`](../../xitdb/compact_replicate.odin#L150-L260)):** On `#41` (**2.05x faster**) and `#42` (**1.47x faster**), Odin pre-sizes the offset map and copies index blocks in single `core_read_exact` / `core_write_all` transfers.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Increase stream buffer size or slice directly in `readCommitted` / `applyReplicated` ([`lib.zig#L592-L637`](../../reference/xitdb-zig/src/lib.zig#L592-L637)):** Streaming via `CoreMemory`'s 256-byte `std.Io` buffer breaks a 250 KB replication delta into ~1,000 virtual `stream`/`drain` calls; exposing a direct slice fast path (or a 64 KB buffer) removes that overhead.
- **Apply the B-Tree / Sorted-Node batch read optimization in `Compactor` ([`lib.zig#L4620-L4760`](../../reference/xitdb-zig/src/lib.zig#L4620-L4760)):** `Compactor.compactBTreeNode` and `compactSortedNode` call `readBTreeNode`/`readSortedNode` and `writeBTreeNodeAt`/`writeSortedNodeAt`, so batch-reading nodes speeds up compaction as well.

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
| `Compactor` | 406 | Reachability-based garbage-collecting compactor (`MemoryOffsetMap` / `FileOffsetMap`) | [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) |
| `readCommitted` | 16 | Committed byte-range streaming for incremental replication | [`lib.zig#L592-L607`](../../reference/xitdb-zig/src/lib.zig#L592-L607) |
| `applyReplicated` | 25 | Replica byte-stream application and root trailer verification | [`lib.zig#L613-L637`](../../reference/xitdb-zig/src/lib.zig#L613-L637) |
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |
| `CoreBufferedFile` | 153 | Write-buffered OS file backend | [`lib.zig#L5068-L5220`](../../reference/xitdb-zig/src/lib.zig#L5068-L5220) |

### Reached Odin Procedures (`41` procedures across `4` files · `944` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/compact_replicate.odin` | `database_replica_state` | **Entry Point** (`depth 0`) | 5 | [`xitdb/compact_replicate.odin#L683-L687`](../../xitdb/compact_replicate.odin#L683-L687) |
| `xitdb/compact_replicate.odin` | `database_replication_start` | **Entry Point** (`depth 0`) | 18 | [`xitdb/compact_replicate.odin#L692-L709`](../../xitdb/compact_replicate.odin#L692-L709) |
| `xitdb/compact_replicate.odin` | `database_read_committed_bytes` | **Entry Point** (`depth 0`) | 23 | [`xitdb/compact_replicate.odin#L783-L805`](../../xitdb/compact_replicate.odin#L783-L805) |
| `xitdb/compact_replicate.odin` | `database_apply_replicated_bytes` | **Entry Point** (`depth 0`) | 29 | [`xitdb/compact_replicate.odin#L859-L887`](../../xitdb/compact_replicate.odin#L859-L887) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_apply_replicated_bytes`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `_database_committed_size_with_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `header_write`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`, `database_replica_state`, `database_replication_start`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 1` (from `database_replica_state`, `database_replication_start`, `database_read_committed_bytes`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `database_read_committed_bytes`, `database_read_root_trailer`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_apply_replicated_bytes`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_committed_size`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_committed_size`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 1` (from `database_apply_replicated_bytes`, `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L939-L950`](../../xitdb/types.odin#L939-L950) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L968-L972`](../../xitdb/types.odin#L968-L972) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L929-L937`](../../xitdb/types.odin#L929-L937) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 2` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 2` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `tag_validate` | `depth 2` (from `database_read_root_trailer`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 2` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L952-L966`](../../xitdb/types.odin#L952-L966) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `root_trailer_from_bytes`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
