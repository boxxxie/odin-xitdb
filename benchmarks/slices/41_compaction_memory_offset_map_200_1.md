# #41. `Compaction (Memory_Offset_Map, 200 -> 1)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L1419-L1437`)](../bench_xitdb.odin#L1419-L1437) · [Zig Harness (`bench_xitdb.zig#L1440-L1458`)](../bench_xitdb.zig#L1440-L1458)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **2,304** | 2,358.4 ± 193.1 | 8.2% | 2,621.0 | 434,028 | 1.2 KB | **2.97x Odin** (`z = 4.7`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 6,833 | 7,247.6 ± 2,332.7 | 32.2% | 10,383.599999999999 | 146,349 | 1.2 KB | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L1419-L1437`](../bench_xitdb.odin#L1419-L1437))

```odin
1419 | 	// 4b. Prune to latest 1 moment & compact database
1420 | 	_ = xitdb.array_list_slice(&history, 1)
1421 | 
1422 | 	comp_core: xitdb.Core = xitdb.core_memory_init()
1423 | 	defer xitdb.core_destroy(&comp_core)
1424 | 
1425 | 	t1 := time.now()
1426 | 	offset_map: xitdb.Offset_Map = xitdb.memory_offset_map_init()
1427 | 	defer xitdb.offset_map_destroy(&offset_map)
1428 | 	comp_db, _ := xitdb.database_compact(&db, &comp_core, &offset_map)
1429 | 	elapsed_compact := time.since(t1)
1430 | 	comp_size, _ := xitdb.database_committed_size(&comp_db)
1431 | 
1432 | 	print_result(Bench_Result{
1433 | 		name       = "Compaction (Memory_Offset_Map, 200 -> 1)",
1434 | 		ops        = 1,
1435 | 		elapsed    = elapsed_compact,
1436 | 		bytes_used = comp_size,
1437 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1440-L1458`](../bench_xitdb.zig#L1440-L1458))

```zig
1440 |     // 4b. Prune to latest 1 moment & compact database
1441 |     try history.slice(1);
1442 | 
1443 |     var comp_buffer = std.Io.Writer.Allocating.init(allocator);
1444 |     defer comp_buffer.deinit();
1445 | 
1446 |     const t1 = std.Io.Clock.awake.now(io);
1447 |     var offset_map = std.AutoHashMap(u64, u64).init(allocator);
1448 |     defer offset_map.deinit();
1449 |     var comp_db = try db.compact(.memory, .{ .buffer = &comp_buffer }, &offset_map);
1450 |     const elapsed_compact = t1.untilNow(io, .awake).nanoseconds;
1451 |     const comp_size = try comp_db.committedSize();
1452 | 
1453 |     try printResult(stdout, .{
1454 |         .name = "Compaction (Memory_Offset_Map, 200 -> 1)",
1455 |         .ops = 1,
1456 |         .elapsed_ns = elapsed_compact,
1457 |         .bytes_used = comp_size,
1458 |     });
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

### Reached Odin Procedures (`90` procedures across `7` files · `1941` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Array_List_Slice`, `Hash_Map_Init`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_slice` | **Entry Point** (`depth 0`) | 4 | [`xitdb/collections.odin#L90-L93`](../../xitdb/collections.odin#L90-L93) |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_init` | **Entry Point** (`depth 0`) | 3 | [`xitdb/compact_replicate.odin#L31-L33`](../../xitdb/compact_replicate.odin#L31-L33) |
| `xitdb/compact_replicate.odin` | `offset_map_destroy` | **Entry Point** (`depth 0`) | 6 | [`xitdb/compact_replicate.odin#L172-L177`](../../xitdb/compact_replicate.odin#L172-L177) |
| `xitdb/compact_replicate.odin` | `database_compact` | **Entry Point** (`depth 0`) | 78 | [`xitdb/compact_replicate.odin#L734-L811`](../../xitdb/compact_replicate.odin#L734-L811) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `array_list_slice`, `database_compact`, `database_run_context`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/compact_replicate.odin` | `memory_offset_map_destroy` | `depth 1` (from `offset_map_destroy`) | 7 | [`xitdb/compact_replicate.odin#L35-L41`](../../xitdb/compact_replicate.odin#L35-L41) |
| `xitdb/compact_replicate.odin` | `offset_map_reset` | `depth 1` (from `database_compact`) | 16 | [`xitdb/compact_replicate.odin#L89-L104`](../../xitdb/compact_replicate.odin#L89-L104) |
| `xitdb/database.odin` | `database_init` | `depth 1` (from `database_compact`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_compact`, `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/types.odin` | `slot_empty` | `depth 1` (from `database_compact`, `cursor_read_path_slot`, `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_compact`, `database_init`, `_exec_path_part`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_compact`, `database_run_context`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `database_compact`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/database.odin` | `database_run_context` | `depth 1` (from `database_compact`) | 5 | [`xitdb/database.odin#L301-L305`](../../xitdb/database.odin#L301-L305) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `database_init`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/cursor.odin` | `cursor_write` | `depth 2` (from `offset_map_reset`) | 5 | [`xitdb/cursor.odin#L186-L190`](../../xitdb/cursor.odin#L186-L190) |
| `xitdb/collections.odin` | `write_hash_map_init` | `depth 2` (from `offset_map_reset`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/types.odin` | `sha1_hasher` | `depth 2` (from `database_init`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `database_init`, `cursor_reload_slot`, `read_slot_pointer`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/database.odin` | `_random_u64` | `depth 2` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 2` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_init`, `_exec_path_part`, `header_write`) | 56 | [`xitdb/core.odin#L376-L431`](../../xitdb/core.odin#L376-L431) |
| `xitdb/database.odin` | `database_commit_root` | `depth 2` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 2` (from `database_init`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 2` (from `database_init`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_read_root_slot`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `cursor_read_path_slot`, `read_hash_map_init`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slice`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L568-L572`](../../xitdb/core.odin#L568-L572) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 15 | [`xitdb/core.odin#L574-L588`](../../xitdb/core.odin#L574-L588) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L543-L566`](../../xitdb/core.odin#L543-L566) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/hamt.odin` | `read_array_list_slice` | `depth 4` (from `_exec_path_part`) | 28 | [`xitdb/hamt.odin#L457-L484`](../../xitdb/hamt.odin#L457-L484) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`, `read_array_list_slice`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 3` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L496-L501`](../../xitdb/core.odin#L496-L501) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L488-L494`](../../xitdb/core.odin#L488-L494) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 3` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_header_to_bytes`, `core_write_slot`, `read_array_list_slot_append`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `core_write_slot`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 3` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 3` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 3` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/types.odin` | `header_read` | `depth 3` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 3` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 3` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slice`, `read_array_list_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 14 | [`xitdb/core.odin#L528-L541`](../../xitdb/core.odin#L528-L541) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L503-L526`](../../xitdb/core.odin#L503-L526) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 4` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 4` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
