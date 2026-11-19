# #47. `Bytes: Inline Short_Bytes read_bytes_buf` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) · [Odin Harness (`bench_xitdb.odin#L1648-L1673`)](../bench_xitdb.odin#L1648-L1673) · [Zig Harness (`bench_xitdb.zig#L1721-L1752`)](../bench_xitdb.zig#L1721-L1752)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **12** | 12.6 ± 1.3 | 10.6% | 14.399999999999999 | 83,333,333 | - | **1.50x Zig** (`z = 7.7`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 8 | 7.6 ± 0.5 | 7.2% | 8.0 | 125,000,000 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 05: Cursor Bytes, Stream Vtables & Nested Paths**](../zig-guide/05_cursor_bytes_streams_and_paths.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L298-L364`](../../xitdb/cursor.odin#L298-L364)):** On `#48` & `#50` (**4.00x–5.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs separate unbuffered reads (`value_size`, `value`, and `format_tag`).
- **Reallocation-Safe Dynamic `core_slice_at` in `Cursor_Reader` & Pre-Sized Writes (`#51–#53` — 1.51x–8.67x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L549-L651) and [`Cursor_Reader`](../../xitdb/cursor.odin#L437-L545) resolve `core_slice_at` dynamically at each read call (remaining 100% safe across mid-stream buffer reallocations or window shifts) and copy slices directly without vtable chains, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches.
- **Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 4.69x–4.91x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Odin's single-pass `Write_KV_Data` and direct slice reads compound across all 4 levels.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).
- **Resolve `self.parent.db.core.buffer.written()` dynamically inside `Cursor.Reader.stream` (`#52–#53`):** Never cache a slice into `CoreMemory.buffer` when opening `Cursor.Reader` (which dangles if a subsequent write reallocates `CoreMemory.buffer`); instead, slice `written()` dynamically inside `stream`.
- **Apply Guides 01–04:** Batch node I/O, binary search, and single-pass KV writes automatically accelerate `#55–#56` without changing `readSlotPointer`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1648-L1673`](../bench_xitdb.odin#L1648-L1673))

```odin
1648 | 	// 5b. Inline `Short_Bytes` (<= 8B) vs External `Bytes` (> 8B) zero-alloc stack reads
1649 | 	{
1650 | 		core: xitdb.Core = xitdb.core_memory_init()
1651 | 		defer xitdb.core_destroy(&core)
1652 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1653 | 		m, _ := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))
1654 | 
1655 | 		_ = xitdb.hash_map_put(&m, "inline", "8bytes!!")
1656 | 		_ = xitdb.hash_map_put(&m, "heap", "heap-allocated-32-byte-string!!!")
1657 | 
1658 | 		inline_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "inline")
1659 | 		heap_cur, _ := xitdb.hash_map_get_cursor(m.read_hash_map, "heap")
1660 | 
1661 | 		reads := n * 5
1662 | 		stack_buf: [64]u8
1663 | 
1664 | 		t_in := time.now()
1665 | 		for _ in 0 ..< reads {
1666 | 			obj, _ := xitdb.cursor_read_bytes_buf(inline_cur.?, stack_buf[:])
1667 | 			assert(len(obj.value) == 8)
1668 | 		}
1669 | 		print_result(Bench_Result{
1670 | 			name    = "Bytes: Inline Short_Bytes read_bytes_buf",
1671 | 			ops     = reads,
1672 | 			elapsed = time.since(t_in),
1673 | 		})
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

### Reached Odin Procedures (`104` procedures across `6` files · `2372` LOC) (Active `_exec_path_part` arms: `Hash_Map_Init`, `Hash_Map_Get`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 28 | [`xitdb/core.odin#L85-L112`](../../xitdb/core.odin#L85-L112) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 30 | [`xitdb/core.odin#L351-L380`](../../xitdb/core.odin#L351-L380) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L256-L261`](../../xitdb/collections.odin#L256-L261) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L437-L441`](../../xitdb/collections.odin#L437-L441) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/cursor.odin` | `cursor_read_bytes_buf` | **Entry Point** (`depth 0`) | 77 | [`xitdb/cursor.odin#L305-L381`](../../xitdb/cursor.odin#L305-L381) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 1` (from `core_memory_init`, `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `_memory_destroy` | `depth 1` (from `core_destroy`, `_overlay_destroy`) | 14 | [`xitdb/core.odin#L207-L220`](../../xitdb/core.odin#L207-L220) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_overlay_destroy` | `depth 1` (from `core_destroy`) | 11 | [`xitdb/core.odin#L222-L232`](../../xitdb/core.odin#L222-L232) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_write_headers`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `cursor_read_bytes_buf`, `database_read_file_size`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L293-L300`](../../xitdb/database.odin#L293-L300) |
| `xitdb/database.odin` | `database_read_file_size` | `depth 1` (from `database_init`) | 7 | [`xitdb/database.odin#L315-L321`](../../xitdb/database.odin#L315-L321) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 1` (from `database_init`, `database_read_file_size`, `database_write_headers`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_init`, `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_write_headers` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L304-L311`](../../xitdb/database.odin#L304-L311) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L574-L694`](../../xitdb/types.odin#L574-L694) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `hash_map_put_key_and_value`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put`, `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L429-L435`](../../xitdb/collections.odin#L429-L435) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_bytes_buf`, `read_hash_map_init`, `cursor_read_path`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 1` (from `cursor_read_bytes_buf`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 1` (from `cursor_read_bytes_buf`, `header_read_at`, `core_read_i64_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `core_read_long_at`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_write_headers`, `database_commit_root`, `header_write`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_resolved`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `cursor_read_path`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 2` (from `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/core.odin` | `core_read_at` | `depth 2` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 3` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `_exec_path_part`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `core_write_i64` | `depth 3` (from `database_write_root_header`, `core_write_long`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`, `read_map_slot`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1420-L1473`](../../xitdb/database.odin#L1420-L1473) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1407-L1418`](../../xitdb/database.odin#L1407-L1418) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 3` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 4` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `_overlay_page` | `depth 4` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`, `core_read_slot_at`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `read_map_slot`, `kv_pair_read_buf_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 6` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
