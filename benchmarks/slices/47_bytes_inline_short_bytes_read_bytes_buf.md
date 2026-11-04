# #47. `Bytes: Inline Short_Bytes read_bytes_buf` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1602-L1627`)](../bench_xitdb.odin#L1602-L1627) · [Zig Harness (`bench_xitdb.zig#L1721-L1752`)](../bench_xitdb.zig#L1721-L1752)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **6** | 6.0 ± 0.0 | 0.0% | 6.0 | 166,666,667 | - | **1.17x Odin** (`z = 99.0`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 7 | 7.0 ± 0.0 | 0.0% | 7.0 | 142,857,143 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L285-L340`](../../xitdb/cursor.odin#L285-L340)):** On `#48` & `#50` (**4.33x–6.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs 3 separate unbuffered reads (`value_size`, `value`, and a redundant `seekTo` + `readSliceAll` for the 2-byte `format_tag` that already immediately follows `value`).
- **Zero-Vtable Stream Reads & Pre-Sized Writes (`#51–#53` — 3.5x–5.8x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L527-L629) and [`Cursor_Reader`](../../xitdb/cursor.odin#L430-L523) read/append slices directly against `Core_Memory.buf`, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches and grows `Writer.Allocating` geometrically from 0 to 1 MB.
- **Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 6.73x–8.74x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Zig's time here is dominated by `readBTreeNode` (18 `takeInt`s at level 3) and `readSortedNode` + linear scan (at level 4).

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).
- **Return `.fixed(slice)` in `Cursor.reader()` when `comptime db_kind == .memory` ([`lib.zig#L3370-L3385`](../../reference/xitdb-zig/src/lib.zig#L3370-L3385)):** Setting `interface = .fixed(slice)` and `pos = size` makes `Cursor.Reader.seekTo` (`lib.zig#L2971-L2981`) and `readSliceAll` pure pointer arithmetic with zero vtable calls!
- **Apply Guides 01–03:** Fixing `CoreMemory.Reader`, `BTreeNode` batch I/O, and `SortedMap` binary search automatically resolves the `6.7x–8.7x` gap on `#55–#56` without changing `readSlotPointer`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1602-L1627`](../bench_xitdb.odin#L1602-L1627))

```odin
1602 | 	// 5b. Inline `Short_Bytes` (<= 8B) vs External `Bytes` (> 8B) zero-alloc stack reads
1603 | 	{
1604 | 		core: xitdb.Core = xitdb.core_memory_init()
1605 | 		defer xitdb.core_destroy(&core)
1606 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1607 | 		m, _ := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))
1608 | 
1609 | 		_ = xitdb.hash_map_put(&m, "inline", "8bytes!!")
1610 | 		_ = xitdb.hash_map_put(&m, "heap", "heap-allocated-32-byte-string!!!")
1611 | 
1612 | 		inline_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "inline")
1613 | 		heap_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "heap")
1614 | 
1615 | 		reads := n * 5
1616 | 		stack_buf: [64]u8
1617 | 
1618 | 		t_in := time.now()
1619 | 		for _ in 0 ..< reads {
1620 | 			obj, _ := xitdb.cursor_read_bytes_buf(inline_cur.?, stack_buf[:])
1621 | 			assert(len(obj.value) == 8)
1622 | 		}
1623 | 		print_result(Bench_Result{
1624 | 			name    = "Bytes: Inline Short_Bytes read_bytes_buf",
1625 | 			ops     = reads,
1626 | 			elapsed = time.since(t_in),
1627 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1721-L1752`](../bench_xitdb.zig#L1721-L1752))

```zig
1721 |     // 5b. Inline `Short_Bytes` (<= 8B) vs External `Bytes` (> 8B) zero-alloc stack reads
1722 |     {
1723 |         var buffer = std.Io.Writer.Allocating.init(allocator);
1724 |         defer buffer.deinit();
1725 |         var db = try DBSha1.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1726 |         const m = try DBSha1.HashMap(.read_write).init(db.rootCursor());
1727 | 
1728 |         const h_inline = hashSha1("inline");
1729 |         try m.putKey(h_inline, .{ .bytes = "inline" });
1730 |         try m.put(h_inline, .{ .bytes = "8bytes!!" });
1731 | 
1732 |         const h_heap = hashSha1("heap");
1733 |         try m.putKey(h_heap, .{ .bytes = "heap" });
1734 |         try m.put(h_heap, .{ .bytes = "heap-allocated-32-byte-string!!!" });
1735 | 
1736 |         const rm = m.readOnly();
1737 |         const inline_cur = (try rm.getCursor(h_inline)).?;
1738 |         const heap_cur = (try rm.getCursor(h_heap)).?;
1739 | 
1740 |         const reads = n * 5;
1741 |         var stack_buf: [64]u8 = undefined;
1742 | 
1743 |         const t_in = std.Io.Clock.awake.now(io);
1744 |         for (0..reads) |_| {
1745 |             const obj = try inline_cur.readBytesObject(&stack_buf);
1746 |             std.debug.assert(obj.value.len == 8);
1747 |         }
1748 |         try printResult(stdout, .{
1749 |             .name = "Bytes: Inline Short_Bytes read_bytes_buf",
1750 |             .ops = reads,
1751 |             .elapsed_ns = t_in.untilNow(io, .awake).nanoseconds,
1752 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |
| `readSlotPointer.write` | 66 | `PathPart` switch arms: `.write` and `.ctx` | [`lib.zig#L1525-L1590`](../../reference/xitdb-zig/src/lib.zig#L1525-L1590) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`92` procedures across `6` files · `2073` LOC) (Active `_exec_path_part` arms: `Hash_Map_Init`, `Hash_Map_Get`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L41-L47`](../../xitdb/core.odin#L41-L47) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L101-L122`](../../xitdb/core.odin#L101-L122) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/cursor.odin` | `cursor_read_bytes_buf` | **Entry Point** (`depth 0`) | 67 | [`xitdb/cursor.odin#L298-L364`](../../xitdb/cursor.odin#L298-L364) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L143-L151`](../../xitdb/core.odin#L143-L151) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `cursor_read_bytes_buf`, `database_commit_root`) | 17 | [`xitdb/core.odin#L175-L191`](../../xitdb/core.odin#L175-L191) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 21 | [`xitdb/core.odin#L153-L173`](../../xitdb/core.odin#L153-L173) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 55 | [`xitdb/core.odin#L362-L416`](../../xitdb/core.odin#L362-L416) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 18 | [`xitdb/core.odin#L218-L235`](../../xitdb/core.odin#L218-L235) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_and_value`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put`, `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L267-L269`](../../xitdb/database.odin#L267-L269) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_bytes_buf`, `read_hash_map_init`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/core.odin` | `core_read_long` | `depth 1` (from `cursor_read_bytes_buf`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L473-L479`](../../xitdb/core.odin#L473-L479) |
| `xitdb/core.odin` | `core_read_exact` | `depth 1` (from `cursor_read_bytes_buf`, `header_read`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L124-L141`](../../xitdb/core.odin#L124-L141) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `_exec_path_part`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_resolved`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L258-L265`](../../xitdb/database.odin#L258-L265) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/core.odin` | `core_read_i64` | `depth 2` (from `core_read_long`) | 24 | [`xitdb/core.odin#L488-L511`](../../xitdb/core.odin#L488-L511) |
| `xitdb/core.odin` | `core_read` | `depth 2` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L281-L323`](../../xitdb/core.odin#L281-L323) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L556-L560`](../../xitdb/core.odin#L556-L560) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 18 | [`xitdb/core.odin#L562-L579`](../../xitdb/core.odin#L562-L579) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L531-L554`](../../xitdb/core.odin#L531-L554) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1396-L1449`](../../xitdb/database.odin#L1396-L1449) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1383-L1394`](../../xitdb/database.odin#L1383-L1394) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L481-L486`](../../xitdb/core.odin#L481-L486) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L490-L500`](../../xitdb/database.odin#L490-L500) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L237-L278`](../../xitdb/core.odin#L237-L278) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 17 | [`xitdb/core.odin#L513-L529`](../../xitdb/core.odin#L513-L529) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L483-L488`](../../xitdb/database.odin#L483-L488) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1414-L1419`](../../xitdb/types.odin#L1414-L1419) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1147-L1149`](../../xitdb/types.odin#L1147-L1149) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L420-L436`](../../xitdb/core.odin#L420-L436) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1192-L1204`](../../xitdb/types.odin#L1192-L1204) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
