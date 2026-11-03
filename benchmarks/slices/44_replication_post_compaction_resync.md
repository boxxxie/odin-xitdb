# #44. `Replication (Post-compaction resync)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Hot-Tail Retention & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1523-L1548`)](../bench_xitdb.odin#L1523-L1548) · [Zig Harness (`bench_xitdb.zig#L1605-L1635`)](../bench_xitdb.zig#L1605-L1635)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **1,462** | 1,463.8 ± 28.7 | 2.0% | 1,505.0 | 683,995 | 23.4 KB | **1.19x Odin** (`z = 13.1`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,743 | 1,735.2 ± 41.2 | 2.4% | 1,777.8 | 573,723 | 23.4 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 06: CoreBufferedFile Hot-Tail Retention & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Direct Slice Copy in Replication ([`xitdb/compact_replicate.odin#L775-L887`](../../xitdb/compact_replicate.odin#L775-L887)):** On `#39 Replication (genesis -> 200 moments)` (**10.04x faster in Odin**) and `#40 Incremental 1-moment delta` (**2.25x faster**), Odin copies committed byte slices directly between buffers and verifies the 25-byte `Root_Trailer` CRC-64/XZ without unbuffered `std.Io` vtable streaming.
- **Batch Output Writes & `0..<num` Traversal in Compaction ([`xitdb/compact_replicate.odin#L106-L773`](../../xitdb/compact_replicate.odin#L106-L773)):** On `#41` (**2.05x faster**) and `#42` (**1.47x faster**), Odin formats compacted blocks in stack buffers and visits `0 ..< num` active B-Tree slots, whereas `Compactor` in [`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911) writes remapped slots via per-element `writeInt` calls and loops over all 16 slots.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Keep `std.AutoHashMap(u64, u64)` in `compact` ([`lib.zig#L650-L709`](../../reference/xitdb-zig/src/lib.zig#L650-L709)):** Zig's SwissTable `AutoHashMap` already gives Zig a **1.15x lead** on `#43`—keep it unchanged.
- **Use `std.Io.Reader.fixed` in `CoreMemory` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)) & batch-write remapped slots in `Compactor` ([`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911)):** Eliminates vtable overhead in `readCommitted` / `applyReplicated` (`#39–#40`) and makes `Compactor` even faster by visiting `0..header.num` and writing each compacted node in one `writeAll`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1523-L1548`](../bench_xitdb.odin#L1523-L1548))

```odin
1523 | 		// 4f. Post-compaction replica resync (`database_replication_start` divergence detection + full replacement sync)
1524 | 		resync_rep_core: xitdb.Core = xitdb.core_memory_init()
1525 | 		defer xitdb.core_destroy(&resync_rep_core)
1526 | 		resync_rep_db, _ := xitdb.database_init(&resync_rep_core, xitdb.sha1_hasher())
1527 | 
1528 | 		// First sync replica with pre-compaction DAG primary
1529 | 		orig_end, _ := xitdb.database_committed_size(&dag_db)
1530 | 		orig_bytes, _ := xitdb.database_read_committed_bytes(&dag_db, 0, orig_end, context.temp_allocator)
1531 | 		_ = xitdb.database_apply_replicated_bytes(&resync_rep_db, 0, orig_bytes)
1532 | 
1533 | 		// Now measure resync against the compacted DAG primary (`dag_comp_db`)
1534 | 		t_resync := time.now()
1535 | 		rep_state, _ := xitdb.database_replica_state(&resync_rep_db)
1536 | 		resync_start, _ := xitdb.database_replication_start(&dag_comp_db, rep_state)
1537 | 		assert(resync_start == 0)
1538 | 		comp_end, _ := xitdb.database_committed_size(&dag_comp_db)
1539 | 		comp_payload, _ := xitdb.database_read_committed_buf(&dag_comp_db, resync_start, comp_end, orig_bytes)
1540 | 		_ = xitdb.database_apply_replicated_bytes(&resync_rep_db, resync_start, comp_payload)
1541 | 		elapsed_resync := time.since(t_resync)
1542 | 
1543 | 		print_result(Bench_Result{
1544 | 			name       = "Replication (Post-compaction resync)",
1545 | 			ops        = 1,
1546 | 			elapsed    = elapsed_resync,
1547 | 			bytes_used = i64(len(comp_payload)),
1548 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1605-L1635`](../bench_xitdb.zig#L1605-L1635))

```zig
1605 |         // 4f. Post-compaction replica resync (`database_replication_start` divergence detection + full replacement sync)
1606 |         var resync_rep_buffer = std.Io.Writer.Allocating.init(allocator);
1607 |         defer resync_rep_buffer.deinit();
1608 |         var resync_rep_db = try DB.init(io, .{ .buffer = &resync_rep_buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1609 | 
1610 |         // First sync replica with pre-compaction DAG primary
1611 |         const orig_end = try dag_db.committedSize();
1612 |         payload_buf.clearRetainingCapacity();
1613 |         try dag_db.readCommitted(0, orig_end, &payload_buf.writer);
1614 |         var orig_reader = std.Io.Reader.fixed(payload_buf.written());
1615 |         try resync_rep_db.applyReplicated(0, &orig_reader, orig_end);
1616 | 
1617 |         // Now measure resync against the compacted DAG primary (`dag_comp_db`)
1618 |         const t_resync = std.Io.Clock.awake.now(io);
1619 |         const r_state = try resync_rep_db.replicaState();
1620 |         const resync_start = try dag_comp_db.replicationStart(r_state);
1621 |         std.debug.assert(resync_start == 0);
1622 |         const comp_end = try dag_comp_db.committedSize();
1623 |         payload_buf.clearRetainingCapacity();
1624 |         try dag_comp_db.readCommitted(resync_start, comp_end, &payload_buf.writer);
1625 |         const comp_payload_len = payload_buf.written().len;
1626 |         var comp_reader = std.Io.Reader.fixed(payload_buf.written());
1627 |         try resync_rep_db.applyReplicated(resync_start, &comp_reader, comp_end - resync_start);
1628 |         const elapsed_resync = t_resync.untilNow(io, .awake).nanoseconds;
1629 | 
1630 |         try printResult(stdout, .{
1631 |             .name = "Replication (Post-compaction resync)",
1632 |             .ops = 1,
1633 |             .elapsed_ns = elapsed_resync,
1634 |             .bytes_used = comp_payload_len,
1635 |         });
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

### Reached Odin Procedures (`42` procedures across `4` files · `968` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 54 | [`xitdb/database.odin#L182-L235`](../../xitdb/database.odin#L182-L235) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/compact_replicate.odin` | `database_read_committed_bytes` | **Entry Point** (`depth 0`) | 23 | [`xitdb/compact_replicate.odin#L904-L926`](../../xitdb/compact_replicate.odin#L904-L926) |
| `xitdb/compact_replicate.odin` | `database_apply_replicated_bytes` | **Entry Point** (`depth 0`) | 29 | [`xitdb/compact_replicate.odin#L980-L1008`](../../xitdb/compact_replicate.odin#L980-L1008) |
| `xitdb/compact_replicate.odin` | `database_replica_state` | **Entry Point** (`depth 0`) | 5 | [`xitdb/compact_replicate.odin#L804-L808`](../../xitdb/compact_replicate.odin#L804-L808) |
| `xitdb/compact_replicate.odin` | `database_replication_start` | **Entry Point** (`depth 0`) | 18 | [`xitdb/compact_replicate.odin#L813-L830`](../../xitdb/compact_replicate.odin#L813-L830) |
| `xitdb/compact_replicate.odin` | `database_read_committed_buf` | **Entry Point** (`depth 0`) | 24 | [`xitdb/compact_replicate.odin#L878-L901`](../../xitdb/compact_replicate.odin#L878-L901) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_apply_replicated_bytes`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `_database_committed_size_with_header`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L974-L977`](../../xitdb/types.odin#L974-L977) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_read_committed_buf`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `header_write`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`, `database_apply_replicated_bytes`) | 9 | [`xitdb/database.odin#L272-L280`](../../xitdb/database.odin#L272-L280) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`, `database_read_committed_bytes`, `database_apply_replicated_bytes`) | 5 | [`xitdb/database.odin#L337-L341`](../../xitdb/database.odin#L337-L341) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 1` (from `database_read_committed_bytes`, `database_apply_replicated_bytes`, `database_replica_state`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `database_read_committed_bytes`, `database_read_committed_buf`, `database_read_root_trailer`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
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
