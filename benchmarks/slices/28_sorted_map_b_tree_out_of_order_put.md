# #28. `Sorted_Map (B+Tree) out-of-order put` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) · [Odin Harness (`bench_xitdb.odin#L1110-L1148`)](../bench_xitdb.odin#L1110-L1148) · [Zig Harness (`bench_xitdb.zig#L1136-L1174`)](../bench_xitdb.zig#L1136-L1174)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **377** | 376.4 ± 1.9 | 0.5% | 378.6 | 2,652,520 | 115.4 KB | **7.62x Odin** (`z = 214.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 2,872 | 2,869.8 ± 25.9 | 0.9% | 2,896.2 | 348,189 | 115.4 KB | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 03: SortedMap & SortedSet Binary Search & Index Select**](../zig-guide/03_sorted_bptree_binary_search.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Binary Search ($O(\log_2 16)$) vs. Linear Scan ($O(16)$) in Nodes ([`xitdb/btree.odin#L1213-L1245`](../../xitdb/btree.odin#L1213-L1245) vs. [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Zig's `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey` scan `0..node.num` linearly (up to 16 `sortedEntryKeySlot` + `compareKey` seeks per node), and [`compareKey`](../../reference/xitdb-zig/src/lib.zig#L2612) zero-fills `var key_buf: [256]u8 = @splat(0)` on every external key check. Odin uses **binary search** (`<= 4` comparisons per node) and an uninitialized `stack_buf: [256]u8 = ---` (**11.6x–32.1x faster**).
- **Single-Read `Sorted_Node` Decoding Only Up to `node.num` ([`xitdb/btree.odin#L1028-L1105`](../../xitdb/btree.odin#L1028-L1105)):** Zig's [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) and [`writeSortedNodeAt`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) execute **18 `takeInt`/`writeInt` calls** for a `146B` leaf and **50 calls** for a `418B` branch (reading all 16 children, 16 separators, and 16 counts even when `node.num == 2`). Odin reads the block in one `core_read_exact` call and decodes `0 ..< node.num`.
- **O(1) Direct Leaf Slot Seek in `sorted_get_by_index` ([`xitdb/btree.odin#L1361-L1439`](../../xitdb/btree.odin#L1361-L1439)):** On `#34 Sorted_Map get_index select` (**51.25x faster in Odin: 64 ns vs 3,280 ns**), Odin reads the 2-byte leaf header and seeks straight to `node_ptr + 2 + rem * 9` to read 1 `Slot`, whereas Zig's [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) decodes all 16 leaf slots via `readSortedNode`.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Extract `sortedBranchSearch` and `sortedLeafSearch` binary search helpers (`~24 lines` replacing 4 linear loops in [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Cuts key comparisons and `SortedKeyValuePair` seeks from up to 16 down to at most 4 per level while *reducing* code duplication across `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey`.
- **Drop `@splat(0)` in `compareKey` ([`lib.zig#L2612`](../../reference/xitdb-zig/src/lib.zig#L2612)) and batch-decode `SortedNode` ([`lib.zig#L2481-L2528`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528)):** Change `var key_buf: [256]u8 = @splat(0)` to `undefined`, and read/write `SortedNode` via one stack `[146]u8` / `[418]u8` buffer.
- **Direct leaf slot read in `sortedGetByIndex` ([`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680)):** When `hdr[0] == .leaf`, seek to `node_ptr + 2 + rem * 9` and read 1 `Slot` instead of calling `readSortedNode`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1110-L1148`](../bench_xitdb.odin#L1110-L1148))

```odin
1110 | 	core: xitdb.Core = xitdb.core_memory_init()
1111 | 	defer xitdb.core_destroy(&core)
1112 | 
1113 | 	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
1114 | 	rc := xitdb.database_root_cursor(&db)
1115 | 	history, _ := xitdb.write_array_list_init(rc)
1116 | 
1117 | 	keys := make([]string, n, context.temp_allocator)
1118 | 	for i in 0 ..< n {
1119 | 		// Deterministic coprime permutation so insertions hit B+Tree leaves out of order
1120 | 		perm := (i * 1999 + 73) % n
1121 | 		keys[i] = fmt.tprintf("skey-%06d", perm)
1122 | 	}
1123 | 
1124 | 	Sorted_Ctx :: struct {
1125 | 		keys: []string,
1126 | 	}
1127 | 	sctx := Sorted_Ctx{keys = keys}
1128 | 
1129 | 	put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1130 | 		c := (^Sorted_Ctx)(user_data)
1131 | 		sm := xitdb.write_sorted_map_init(cursor^) or_return
1132 | 		for k, idx in c.keys {
1133 | 			xitdb.sorted_map_put(&sm, k, u64(idx)) or_return
1134 | 		}
1135 | 		return nil
1136 | 	}
1137 | 
1138 | 	t0 := time.now()
1139 | 	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, put_cb, &sctx)
1140 | 	elapsed_put := time.since(t0)
1141 | 	sz, _ := xitdb.database_committed_size(&db)
1142 | 
1143 | 	print_result(Bench_Result{
1144 | 		name       = "Sorted_Map (B+Tree) out-of-order put",
1145 | 		ops        = n,
1146 | 		elapsed    = elapsed_put,
1147 | 		bytes_used = sz,
1148 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1136-L1174`](../bench_xitdb.zig#L1136-L1174))

```zig
1136 |     var arena = std.heap.ArenaAllocator.init(allocator);
1137 |     defer arena.deinit();
1138 |     const temp = arena.allocator();
1139 | 
1140 |     var buffer = std.Io.Writer.Allocating.init(allocator);
1141 |     defer buffer.deinit();
1142 | 
1143 |     const DB = xitdb.Database(.memory, HashInt);
1144 |     var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
1145 |     const history = try DB.ArrayList(.read_write).init(db.rootCursor());
1146 | 
1147 |     const keys = try temp.alloc([]const u8, n);
1148 |     for (0..n) |i| {
1149 |         const perm = (i * 1999 + 73) % n;
1150 |         keys[i] = try std.fmt.allocPrint(temp, "skey-{d:0>6}", .{perm});
1151 |     }
1152 | 
1153 |     const PutCtx = struct {
1154 |         keys: []const []const u8,
1155 | 
1156 |         pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
1157 |             const sm = try DB.SortedMap(.read_write).init(cursor.*);
1158 |             for (self.keys, 0..) |k, idx| {
1159 |                 try sm.put(k, .{ .uint = @intCast(idx) });
1160 |             }
1161 |         }
1162 |     };
1163 | 
1164 |     const t0 = std.Io.Clock.awake.now(io);
1165 |     try history.appendContext(.{ .slot = .{} }, PutCtx{ .keys = keys });
1166 |     const elapsed_put = t0.untilNow(io, .awake).nanoseconds;
1167 |     const sz = try db.committedSize();
1168 | 
1169 |     try printResult(stdout, .{
1170 |         .name = "Sorted_Map (B+Tree) out-of-order put",
1171 |         .ops = n,
1172 |         .elapsed_ns = elapsed_put,
1173 |         .bytes_used = sz,
1174 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `SortedMap` | 101 | Typed counted B+Tree `SortedMap` wrapper (`put`, `getCursor`, `getIndex`, `rank`, `remove`) | [`lib.zig#L4128-L4228`](../../reference/xitdb-zig/src/lib.zig#L4128-L4228) |
| `SortedSet` | 66 | Typed counted B+Tree `SortedSet` wrapper | [`lib.zig#L4232-L4297`](../../reference/xitdb-zig/src/lib.zig#L4232-L4297) |
| `readSlotPointer.sorted_map` | 126 | `PathPart` switch arms: `.sorted_map_init`, `.sorted_map_get`, `.sorted_map_get_index`, `.sorted_map_remove` | [`lib.zig#L1399-L1524`](../../reference/xitdb-zig/src/lib.zig#L1399-L1524) |
| `readSortedNode` | 31 | Counted B+Tree 16-slot node deserializer (18–50 `takeInt` calls) | [`lib.zig#L2481-L2511`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) |
| `writeSortedNodeAt` | 16 | Counted B+Tree 16-slot node serializer (18–50 `writeInt` calls) | [`lib.zig#L2513-L2528`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) |
| `compareKey` | 31 | Lexicographic key comparison against `.short_bytes` / `.bytes` slot | [`lib.zig#L2599-L2629`](../../reference/xitdb-zig/src/lib.zig#L2599-L2629) |
| `sortedGet` | 25 | Counted B+Tree key lookup descent (linear separator/leaf scan) | [`lib.zig#L2634-L2658`](../../reference/xitdb-zig/src/lib.zig#L2634-L2658) |
| `sortedGetByIndex` | 20 | Counted B+Tree O(log N) rank selection by subtree counts | [`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) |
| `sortedRank` | 25 | Counted B+Tree O(log N) order-statistic rank query | [`lib.zig#L2683-L2707`](../../reference/xitdb-zig/src/lib.zig#L2683-L2707) |
| `sortedPut` | 140 | Counted B+Tree key insertion, leaf/branch split, and separator propagation | [`lib.zig#L2736-L2875`](../../reference/xitdb-zig/src/lib.zig#L2736-L2875) |
| `sortedRemove` | 40 | Counted B+Tree key deletion and sibling merge/rebalance | [`lib.zig#L2879-L2918`](../../reference/xitdb-zig/src/lib.zig#L2879-L2918) |

### Reached Odin Procedures (`112` procedures across `7` files · `2709` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Append`, `Sorted_Map_Init`, `Sorted_Map_Get`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 7 | [`xitdb/core.odin#L42-L48`](../../xitdb/core.odin#L42-L48) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 22 | [`xitdb/core.odin#L102-L123`](../../xitdb/core.odin#L102-L123) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 53 | [`xitdb/database.odin#L182-L234`](../../xitdb/database.odin#L182-L234) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L825-L834`](../../xitdb/types.odin#L825-L834) |
| `xitdb/database.odin` | `database_root_cursor` | **Entry Point** (`depth 0`) | 16 | [`xitdb/database.odin#L282-L297`](../../xitdb/database.odin#L282-L297) |
| `xitdb/collections.odin` | `write_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L26-L31`](../../xitdb/collections.odin#L26-L31) |
| `xitdb/collections.odin` | `write_sorted_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L679-L684`](../../xitdb/collections.odin#L679-L684) |
| `xitdb/collections.odin` | `sorted_map_put` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L789-L791`](../../xitdb/collections.odin#L789-L791) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_write_all`, `core_sync`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_commit_root`, `database_read_and_validate_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_commit_root`, `database_write_root_header`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/types.odin` | `header_write` | `depth 1` (from `database_init`) | 4 | [`xitdb/types.odin#L980-L983`](../../xitdb/types.odin#L980-L983) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 1` (from `database_init`, `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/core.odin` | `core_write_all` | `depth 1` (from `database_init`, `header_write`, `database_commit_root`) | 52 | [`xitdb/core.odin#L376-L427`](../../xitdb/core.odin#L376-L427) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 9 | [`xitdb/database.odin#L271-L279`](../../xitdb/database.odin#L271-L279) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 5 | [`xitdb/database.odin#L336-L340`](../../xitdb/database.odin#L336-L340) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L571-L691`](../../xitdb/types.odin#L571-L691) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 1` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L378-L381`](../../xitdb/database.odin#L378-L381) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_array_list_init`, `write_sorted_map_init`, `array_list_append_context`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_array_list_init` | `depth 1` (from `write_array_list_init`) | 9 | [`xitdb/collections.odin#L16-L24`](../../xitdb/collections.odin#L16-L24) |
| `xitdb/collections.odin` | `read_sorted_map_init` | `depth 1` (from `write_sorted_map_init`) | 9 | [`xitdb/collections.odin#L669-L677`](../../xitdb/collections.odin#L669-L677) |
| `xitdb/collections.odin` | `sorted_map_put_by_bytes` | `depth 1` (from `sorted_map_put`) | 7 | [`xitdb/collections.odin#L766-L772`](../../xitdb/collections.odin#L766-L772) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 2` (from `header_write`) | 12 | [`xitdb/types.odin#L945-L956`](../../xitdb/types.odin#L945-L956) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 2` (from `root_header_to_bytes`, `root_trailer_to_bytes`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `_memory_resize` | `depth 2` (from `core_write_all`, `core_write_slot`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/types.odin` | `header_read` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L974-L978`](../../xitdb/types.odin#L974-L978) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L935-L943`](../../xitdb/types.odin#L935-L943) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `database_read_root_slot`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 2` (from `database_committed_size`, `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L175-L353`](../../xitdb/types.odin#L175-L353) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_array_list_init`, `read_sorted_map_init`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `header_read`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read`) | 15 | [`xitdb/types.odin#L958-L972`](../../xitdb/types.odin#L958-L972) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `database_read_root_trailer`, `core_read_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `sorted_target_slot`, `sorted_entry_key_slot`) | 5 | [`xitdb/core.odin#L564-L568`](../../xitdb/core.odin#L564-L568) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `sorted_put`) | 15 | [`xitdb/core.odin#L570-L584`](../../xitdb/core.odin#L570-L584) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L539-L562`](../../xitdb/core.odin#L539-L562) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/btree.odin` | `write_sorted_node` | `depth 4` (from `_exec_path_part`, `sorted_put`, `sorted_grow_root`) | 5 | [`xitdb/btree.odin#L1114-L1118`](../../xitdb/btree.odin#L1114-L1118) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `btree_reusable`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/btree.odin` | `sorted_get` | `depth 4` (from `_exec_path_part`) | 115 | [`xitdb/btree.odin#L1254-L1368`](../../xitdb/btree.odin#L1254-L1368) |
| `xitdb/btree.odin` | `sorted_target_slot` | `depth 4` (from `_exec_path_part`) | 18 | [`xitdb/btree.odin#L2205-L2222`](../../xitdb/btree.odin#L2205-L2222) |
| `xitdb/btree.odin` | `sorted_put` | `depth 4` (from `_exec_path_part`) | 374 | [`xitdb/btree.odin#L1673-L2046`](../../xitdb/btree.odin#L1673-L2046) |
| `xitdb/btree.odin` | `sorted_grow_root` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/btree.odin#L2192-L2203`](../../xitdb/btree.odin#L2192-L2203) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `slot_from_slice`, `kv_pair_from_bytes`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/btree.odin` | `write_sorted_node_at` | `depth 5` (from `write_sorted_node`, `sorted_write_node`) | 39 | [`xitdb/btree.odin#L1074-L1112`](../../xitdb/btree.odin#L1074-L1112) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `sorted_get`, `sorted_entry_key_slot`) | 17 | [`xitdb/core.odin#L431-L447`](../../xitdb/core.odin#L431-L447) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_entry_key_slot`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/btree.odin` | `sorted_entry_key_slot` | `depth 5` (from `sorted_get`, `sorted_target_slot`, `sorted_put`) | 13 | [`xitdb/btree.odin#L1136-L1148`](../../xitdb/btree.odin#L1136-L1148) |
| `xitdb/btree.odin` | `compare_key` | `depth 5` (from `sorted_get`, `sorted_put`, `sorted_leaf_search`) | 60 | [`xitdb/btree.odin#L1157-L1216`](../../xitdb/btree.odin#L1157-L1216) |
| `xitdb/types.odin` | `is_key_only_entry` | `depth 5` (from `sorted_target_slot`, `sorted_put`, `sorted_entry_key_slot`) | 3 | [`xitdb/types.odin#L1335-L1337`](../../xitdb/types.odin#L1335-L1337) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 5` (from `sorted_target_slot`) | 6 | [`xitdb/database.odin#L529-L534`](../../xitdb/database.odin#L529-L534) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `sorted_put`, `sorted_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/btree.odin` | `write_sorted_pair` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`) | 7 | [`xitdb/btree.odin#L1610-L1616`](../../xitdb/btree.odin#L1610-L1616) |
| `xitdb/btree.odin` | `read_kv_pair` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1128-L1134`](../../xitdb/btree.odin#L1128-L1134) |
| `xitdb/btree.odin` | `write_kv_pair` | `depth 5` (from `sorted_put`, `write_sorted_pair`) | 6 | [`xitdb/btree.odin#L1150-L1155`](../../xitdb/btree.odin#L1150-L1155) |
| `xitdb/btree.odin` | `write_sorted_key_and_entry` | `depth 5` (from `sorted_put`) | 54 | [`xitdb/btree.odin#L1618-L1671`](../../xitdb/btree.odin#L1618-L1671) |
| `xitdb/btree.odin` | `sorted_write_node` | `depth 5` (from `sorted_put`) | 7 | [`xitdb/btree.odin#L1120-L1126`](../../xitdb/btree.odin#L1120-L1126) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `sorted_put`, `write_sorted_key_and_entry`, `core_write_long`) | 14 | [`xitdb/core.odin#L524-L537`](../../xitdb/core.odin#L524-L537) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 5` (from `sorted_put`) | 10 | [`xitdb/types.odin#L1299-L1308`](../../xitdb/types.odin#L1299-L1308) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 5` (from `sorted_put`) | 38 | [`xitdb/btree.odin#L1035-L1072`](../../xitdb/btree.odin#L1035-L1072) |
| `xitdb/btree.odin` | `sorted_leaf_search` | `depth 5` (from `sorted_put`) | 17 | [`xitdb/btree.odin#L1220-L1236`](../../xitdb/btree.odin#L1220-L1236) |
| `xitdb/btree.odin` | `sorted_branch_search` | `depth 5` (from `sorted_put`) | 14 | [`xitdb/btree.odin#L1239-L1252`](../../xitdb/btree.odin#L1239-L1252) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/core.odin` | `core_read_i64` | `depth 6` (from `compare_key`) | 24 | [`xitdb/core.odin#L499-L522`](../../xitdb/core.odin#L499-L522) |
| `xitdb/types.odin` | `decode_kv_pair` | `depth 6` (from `read_kv_pair`) | 35 | [`xitdb/types.odin#L1155-L1189`](../../xitdb/types.odin#L1155-L1189) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `write_kv_pair`) | 27 | [`xitdb/types.odin#L1206-L1232`](../../xitdb/types.odin#L1206-L1232) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/core.odin` | `core_write_long` | `depth 6` (from `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L492-L497`](../../xitdb/core.odin#L492-L497) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 7` (from `decode_kv_pair`) | 3 | [`xitdb/types.odin#L1122-L1124`](../../xitdb/types.odin#L1122-L1124) |
| `xitdb/types.odin` | `kv_pair_from_bytes` | `depth 7` (from `decode_kv_pair`) | 10 | [`xitdb/types.odin#L1136-L1145`](../../xitdb/types.odin#L1136-L1145) |
