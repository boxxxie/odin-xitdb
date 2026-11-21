# #14. `Array_List (Radix Trie) append` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) · [Odin Harness (`bench_xitdb.odin#L1019-L1054`)](../bench_xitdb.odin#L1019-L1054) · [Zig Harness (`bench_xitdb.zig#L834-L863`)](../bench_xitdb.zig#L834-L863)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **165** | 167.2 ± 8.1 | 4.8% | 178.2 | 6,060,606 | 19.3 KB | **1.42x Odin** (`z = 13.0`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 235 | 240.8 ± 9.8 | 4.1% | 253.4 | 4,255,319 | 19.3 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Zero-Vtable `Core_Memory` Slice Reads ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360), [`xitdb/hamt.odin#L345-L452`](../../xitdb/hamt.odin#L345-L452)):** Odin's `read_array_list_slot` decodes 9-byte `Slot`s directly from `Core_Memory.buf`, whereas Zig's [`CoreMemory.reader()`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003) initializes `std.Io.Reader` with `.buffer = &.{}` (empty slice). Because `.buffer` is empty, every `takeInt` in `readArrayListSlot` misses `std.Io.Reader`'s inline fast path and dispatches through `vtable.readVec` → `CoreMemory.Reader.stream` → `Writer.fixed.drain` (two virtual calls per integer).
- **Stack-Allocated `Cursor_Iterator` ([`xitdb/cursor.odin#L655-L1096`](../../xitdb/cursor.odin#L655-L1096)):** On `#16 Array_List iterator scan` (**12 ns vs 33 ns**) and `#18 index-seek page(10)` (**4.45x faster in Odin**), Odin decodes each 144-byte `index_block` directly from memory without per-slot `std.Io` vtable calls.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Use `std.Io.Reader.fixed` in `CoreMemory.reader()` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Setting `self.interface = .fixed(self.parent.buffer.written())` (refreshed in `seekTo()`) lets `takeInt` and `readSliceAll` execute inline with zero vtable calls (`-12 net LOC`, removing `CoreMemory.Reader.stream`).

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1019-L1054`](../bench_xitdb.odin#L1019-L1054))

```odin
1019 | 	// 2a. Array_List (16-way Radix Trie)
1020 | 	{
1021 | 		core: xitdb.Core = xitdb.core_memory_init()
1022 | 		defer xitdb.core_destroy(&core)
1023 | 
1024 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1025 | 		rc := xitdb.database_root_cursor(&db)
1026 | 		history, _ := xitdb.write_array_list_init(rc)
1027 | 
1028 | 		List_Ctx :: struct {
1029 | 			n: int,
1030 | 		}
1031 | 		lctx := List_Ctx{n = n}
1032 | 
1033 | 		append_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1034 | 			c := (^List_Ctx)(user_data)
1035 | 			list := xitdb.write_array_list_init(cursor^) or_return
1036 | 			for i in 0 ..< c.n {
1037 | 				xitdb.array_list_append(&list, u64(i)) or_return
1038 | 			}
1039 | 			return nil
1040 | 		}
1041 | 
1042 | 		sp0 := span_begin()
1043 | 		_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, append_cb, &lctx)
1044 | 		elapsed_append, hw0, has_hw0 := span_end(sp0)
1045 | 		sz, _ := xitdb.database_committed_size(&db)
1046 | 
1047 | 		print_result(Bench_Result{
1048 | 			name         = "Array_List (Radix Trie) append",
1049 | 			ops          = n,
1050 | 			elapsed      = elapsed_append,
1051 | 			bytes_used   = sz,
1052 | 			counters     = hw0,
1053 | 			has_counters = has_hw0,
1054 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L834-L863`](../bench_xitdb.zig#L834-L863))

```zig
 834 |     // 2a. Array_List (16-way Radix Trie)
 835 |     {
 836 |         var buffer = std.Io.Writer.Allocating.init(allocator);
 837 |         defer buffer.deinit();
 838 | 
 839 |         var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
 840 |         const history = try DB.ArrayList(.read_write).init(db.rootCursor());
 841 | 
 842 |         const AppendCtx = struct {
 843 |             n: usize,
 844 | 
 845 |             pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
 846 |                 const list = try DB.ArrayList(.read_write).init(cursor.*);
 847 |                 for (0..self.n) |i| {
 848 |                     try list.append(.{ .uint = @intCast(i) });
 849 |                 }
 850 |             }
 851 |         };
 852 | 
 853 |         const t0 = std.Io.Clock.awake.now(io);
 854 |         try history.appendContext(.{ .slot = .{} }, AppendCtx{ .n = n });
 855 |         const elapsed_append = t0.untilNow(io, .awake).nanoseconds;
 856 |         const sz = try db.committedSize();
 857 | 
 858 |         try printResult(stdout, .{
 859 |             .name = "Array_List (Radix Trie) append",
 860 |             .ops = n,
 861 |             .elapsed_ns = elapsed_append,
 862 |             .bytes_used = sz,
 863 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `ArrayList` | 90 | Typed 16-way Radix Trie `ArrayList` wrapper (`append`, `getCursor`, `put`, `slice`) | [`lib.zig#L4299-L4388`](../../reference/xitdb-zig/src/lib.zig#L4299-L4388) |
| `readSlotPointer.array_list` | 122 | `PathPart` switch arms: `.array_list_init`, `.array_list_get`, `.array_list_append`, `.array_list_slice` | [`lib.zig#L927-L1048`](../../reference/xitdb-zig/src/lib.zig#L927-L1048) |
| `readArrayListSlotAppend` | 35 | 16-way Radix Trie tail append and root overflow growth | [`lib.zig#L1820-L1854`](../../reference/xitdb-zig/src/lib.zig#L1820-L1854) |
| `readArrayListSlot` | 49 | 16-way Radix Trie O(log16 N) slot descent and CoW path copy | [`lib.zig#L1856-L1904`](../../reference/xitdb-zig/src/lib.zig#L1856-L1904) |
| `readArrayListSlice` | 37 | 16-way Radix Trie truncation and root depth collapse | [`lib.zig#L1906-L1942`](../../reference/xitdb-zig/src/lib.zig#L1906-L1942) |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`91` procedures across `6` files · `1913` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Append`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 28 | [`xitdb/core.odin#L85-L112`](../../xitdb/core.odin#L85-L112) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 30 | [`xitdb/core.odin#L351-L380`](../../xitdb/core.odin#L351-L380) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/collections.odin` | `write_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `array_list_append` | **Entry Point** (`depth 0`) | 7 | [`xitdb/collections.odin#L77-L83`](../../xitdb/collections.odin#L77-L83) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L89-L96`](../../xitdb/collections.odin#L89-L96) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 1` (from `core_memory_init`, `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `_memory_destroy` | `depth 1` (from `core_destroy`, `_overlay_destroy`) | 14 | [`xitdb/core.odin#L207-L220`](../../xitdb/core.odin#L207-L220) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_overlay_destroy` | `depth 1` (from `core_destroy`) | 11 | [`xitdb/core.odin#L222-L232`](../../xitdb/core.odin#L222-L232) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_write_headers`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_read_file_size`, `database_commit_root`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
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
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_array_list_init`, `array_list_append`, `array_list_append_context`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_write_headers`, `database_commit_root`, `header_write`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 67 | [`xitdb/database.odin#L603-L669`](../../xitdb/database.odin#L603-L669) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `header_read_at`, `core_read_i64_at`, `_exec_path_part`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 3` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `compute_root_trailer_checksum`, `core_write_slot`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `core_write_i64` | `depth 3` (from `database_write_root_header`, `core_write_long`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 788 | [`xitdb/database.odin#L671-L1458`](../../xitdb/database.odin#L671-L1458) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 38 | [`xitdb/hamt.odin#L343-L380`](../../xitdb/hamt.odin#L343-L380) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1528-L1559`](../../xitdb/database.odin#L1528-L1559) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 4` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `_overlay_page` | `depth 4` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`, `core_read_slot_at`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1484-L1489`](../../xitdb/types.odin#L1484-L1489) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `read_array_list_slot_append`) | 70 | [`xitdb/hamt.odin#L382-L451`](../../xitdb/hamt.odin#L382-L451) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1561-L1609`](../../xitdb/database.odin#L1561-L1609) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1407-L1418`](../../xitdb/types.odin#L1407-L1418) |
| `xitdb/core.odin` | `core_write_long` | `depth 6` (from `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
