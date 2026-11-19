# #25. `Linked_Array_List (B-Tree) concat + slice` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) · [Odin Harness (`bench_xitdb.odin#L1087-L1112`)](../bench_xitdb.odin#L1087-L1112) · [Zig Harness (`bench_xitdb.zig#L1068-L1091`)](../bench_xitdb.zig#L1068-L1091)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **1,831** | 1,830.8 ± 30.4 | 1.7% | 1,870.0 | 546,150 | - | **12.46x Odin** (`z = 53.3`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 22,814 | 22,871.0 ± 882.4 | 3.9% | 23,795.6 | 43,833 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Read Block Serialization vs. 18–34 Per-Field `std.Io` Calls ([`xitdb/btree.odin#L8-L75`](../../xitdb/btree.odin#L8-L75) vs. [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** This is the primary driver of Odin's **4.6x–43.2x speedup** on `Linked_Array_List` (`BTREE_SLOT_COUNT = 16`: `146B` leaf, `274B` branch). Zig's `readBTreeNode` and `writeBTreeNodeAt` loop over all 16 slots (and 16 counts on branches) unconditionally, issuing **18 to 34 individual unbuffered `takeInt`/`writeInt` calls** per node even when `node.num == 2`. Odin reads the node in **one `core_read_exact` call** into a stack buffer and decodes only `0 ..< node.num` active entries.
- **O(1) Direct Leaf Slot Seek in `read_btree_slot` ([`xitdb/btree.odin#L103-L189`](../../xitdb/btree.odin#L103-L189)):** On `#21 Linked_Array_List random get` (**43.24x faster in Odin: 54 ns vs 2,335 ns**), when `read_btree_slot` reaches a `.Leaf`, Odin peeks the 2-byte header, validates `rem < leaf_num`, and reads **only the single 9-byte `Slot`** at `node_ptr + 2 + rem * 9`. Zig's [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) calls `readBTreeNode` at the leaf, executing 18 `takeInt` calls and 16 tag checks to decode all 16 slots just to return `node.values[rem]`.
- **Targeted In-Place Branch Count Patching ([`xitdb/btree.odin#L232-L268`](../../xitdb/btree.odin#L232-L268)):** When inserting into a branch node already owned by the current transaction (`btree_reusable` is true and no child split occurred), Odin patches only the 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) instead of rewriting all 274 bytes.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Read/Write `BTreeNode` via a stack `[146]u8` / `[274]u8` buffer (`~25 lines` in [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** Read the node in one `reader.interface.readSliceAll` (and write in one `writer.interface.writeAll(&buf)`), decoding `0..node.num` in memory with `std.mem.readInt`. This keeps the `BTreeNode` struct and all split/join/rebalance logic 100% unchanged while eliminating 18–34 vtable/syscall dispatches per node.
- **Short-circuit `.leaf` in `readBTreeSlot` (`~8 lines` in [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042)):** Read the 2-byte `(kind, num)` header first; when `kind == .leaf`, verify `rem < num` and seek directly to `node_ptr + 2 + rem * 9` to read 1 `Slot`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1087-L1112`](../bench_xitdb.odin#L1087-L1112))

```odin
1087 | 		Rope_Ctx :: struct {
1088 | 			base_slot: xitdb.Slot,
1089 | 			iters:     int,
1090 | 		}
1091 | 		rctx := Rope_Ctx{base_slot = m0_slot.?, iters = 200}
1092 | 
1093 | 		rope_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1094 | 			c := (^Rope_Ctx)(user_data)
1095 | 			list := xitdb.write_linked_array_list_init(cursor^) or_return
1096 | 			for _ in 0 ..< c.iters {
1097 | 				xitdb.linked_array_list_concat(&list, c.base_slot) or_return
1098 | 				cnt, _ := xitdb.linked_array_list_count(list)
1099 | 				xitdb.linked_array_list_slice(&list, cnt / 4, cnt / 2) or_return
1100 | 			}
1101 | 			return nil
1102 | 		}
1103 | 
1104 | 		t5 := time.now()
1105 | 		_ = xitdb.array_list_append_context(&history, m0_slot.?, rope_cb, &rctx)
1106 | 		elapsed_rope := time.since(t5)
1107 | 
1108 | 		print_result(Bench_Result{
1109 | 			name    = "Linked_Array_List (B-Tree) concat + slice",
1110 | 			ops     = rctx.iters * 2,
1111 | 			elapsed = elapsed_rope,
1112 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1068-L1091`](../bench_xitdb.zig#L1068-L1091))

```zig
1068 |         const RopeCtx = struct {
1069 |             base_slot: xitdb.Slot,
1070 |             iters: usize,
1071 | 
1072 |             pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
1073 |                 const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
1074 |                 for (0..self.iters) |_| {
1075 |                     try list.concat(self.base_slot);
1076 |                     const c = try list.count();
1077 |                     try list.slice(c / 4, c / 2);
1078 |                 }
1079 |             }
1080 |         };
1081 | 
1082 |         const rctx = RopeCtx{ .base_slot = m0_slot, .iters = 200 };
1083 |         const t5 = std.Io.Clock.awake.now(io);
1084 |         try history.appendContext(.{ .slot = m0_slot }, rctx);
1085 |         const elapsed_rope = t5.untilNow(io, .awake).nanoseconds;
1086 | 
1087 |         try printResult(stdout, .{
1088 |             .name = "Linked_Array_List (B-Tree) concat + slice",
1089 |             .ops = rctx.iters * 2,
1090 |             .elapsed_ns = elapsed_rope,
1091 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `LinkedArrayList` | 115 | Typed count-augmented B-Tree `LinkedArrayList` wrapper (`append`, `insert`, `remove`, `concat`, `slice`) | [`lib.zig#L4390-L4504`](../../reference/xitdb-zig/src/lib.zig#L4390-L4504) |
| `readSlotPointer.linked_array_list` | 222 | `PathPart` switch arms: `.linked_array_list_init`, `.linked_array_list_get`, `.linked_array_list_append`, `.linked_array_list_slice`, `.linked_array_list_concat`, `.linked_array_list_insert`, `.linked_array_list_remove` | [`lib.zig#L1049-L1270`](../../reference/xitdb-zig/src/lib.zig#L1049-L1270) |
| `readBTreeNode` | 27 | Count-augmented B-Tree 16-slot node deserializer (18–34 `takeInt` calls) | [`lib.zig#L1946-L1972`](../../reference/xitdb-zig/src/lib.zig#L1946-L1972) |
| `writeBTreeNodeAt` | 15 | Count-augmented B-Tree 16-slot node serializer (18–34 `writeInt` calls) | [`lib.zig#L1977-L1991`](../../reference/xitdb-zig/src/lib.zig#L1977-L1991) |
| `btreeWriteNode` | 7 | In-place transaction reuse check (`btreeReusable`) vs append copy | [`lib.zig#L2013-L2019`](../../reference/xitdb-zig/src/lib.zig#L2013-L2019) |
| `readBTreeSlot` | 20 | Count-augmented B-Tree rank lookup descent | [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) |
| `btreeInsert` | 108 | Count-augmented B-Tree recursive rank insertion and node split | [`lib.zig#L2047-L2154`](../../reference/xitdb-zig/src/lib.zig#L2047-L2154) |
| `btreeGetForWrite` | 29 | Count-augmented B-Tree CoW in-place slot update | [`lib.zig#L2181-L2209`](../../reference/xitdb-zig/src/lib.zig#L2181-L2209) |
| `btreeRemove` | 37 | Count-augmented B-Tree recursive rank deletion and sibling rebalance | [`lib.zig#L2215-L2251`](../../reference/xitdb-zig/src/lib.zig#L2215-L2251) |
| `btreeJoin` | 11 | Count-augmented B-Tree height-aware O(log N) tree concatenation | [`lib.zig#L2423-L2433`](../../reference/xitdb-zig/src/lib.zig#L2423-L2433) |
| `btreeSplit` | 27 | Count-augmented B-Tree O(log N) rank split for `slice` | [`lib.zig#L2451-L2477`](../../reference/xitdb-zig/src/lib.zig#L2451-L2477) |

### Reached Odin Procedures (`98` procedures across `7` files · `1965` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Slice`, `Linked_Array_List_Concat`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `write_linked_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L126-L131`](../../xitdb/collections.odin#L126-L131) |
| `xitdb/collections.odin` | `linked_array_list_concat` | **Entry Point** (`depth 0`) | 4 | [`xitdb/collections.odin#L203-L206`](../../xitdb/collections.odin#L203-L206) |
| `xitdb/collections.odin` | `linked_array_list_count` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L137-L139`](../../xitdb/collections.odin#L137-L139) |
| `xitdb/collections.odin` | `linked_array_list_slice` | **Entry Point** (`depth 0`) | 4 | [`xitdb/collections.odin#L198-L201`](../../xitdb/collections.odin#L198-L201) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L89-L96`](../../xitdb/collections.odin#L89-L96) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_linked_array_list_init`, `linked_array_list_concat`, `linked_array_list_slice`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 1` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L116-L124`](../../xitdb/collections.odin#L116-L124) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 1` (from `linked_array_list_count`) | 37 | [`xitdb/cursor.odin#L436-L472`](../../xitdb/cursor.odin#L436-L472) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_linked_array_list_init`, `cursor_count`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 2` (from `cursor_count`, `_exec_path_part`, `core_read_slot_raw_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1114-L1122`](../../xitdb/types.odin#L1114-L1122) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 2` (from `cursor_count`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/types.odin` | `check_long` | `depth 2` (from `cursor_count`) | 6 | [`xitdb/types.odin#L1482-L1487`](../../xitdb/types.odin#L1482-L1487) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`, `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot_append`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/btree.odin` | `btree_new_root` | `depth 4` (from `_exec_path_part`, `btree_split_left`, `btree_subtree`) | 3 | [`xitdb/btree.odin#L101-L103`](../../xitdb/btree.odin#L101-L103) |
| `xitdb/btree.odin` | `btree_split_right` | `depth 4` (from `_exec_path_part`) | 37 | [`xitdb/btree.odin#L953-L989`](../../xitdb/btree.odin#L953-L989) |
| `xitdb/btree.odin` | `btree_split_left` | `depth 4` (from `_exec_path_part`) | 43 | [`xitdb/btree.odin#L991-L1033`](../../xitdb/btree.odin#L991-L1033) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1107-L1112`](../../xitdb/types.odin#L1107-L1112) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_new_root`, `btree_split_right`) | 5 | [`xitdb/btree.odin#L79-L83`](../../xitdb/btree.odin#L79-L83) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `_database_truncate_with_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 38 | [`xitdb/hamt.odin#L343-L380`](../../xitdb/hamt.odin#L343-L380) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1084-L1089`](../../xitdb/types.odin#L1084-L1089) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/btree.odin` | `btree_join` | `depth 4` (from `_exec_path_part`, `btree_split_right`, `btree_split_left`) | 15 | [`xitdb/btree.odin#L922-L936`](../../xitdb/btree.odin#L922-L936) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1080-L1082`](../../xitdb/types.odin#L1080-L1082) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`, `core_flush`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `core_read_at` | `depth 3` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 3` (from `core_read_long_at`, `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `core_read_slot_at`, `database_read_root_trailer`, `slot_from_slice`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 4` (from `database_read_root_header`, `database_write_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 4` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/core.odin` | `_memory_resize` | `depth 4` (from `core_write_slot`, `core_write_all`, `_overlay_write_at`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `read_array_list_slot_append`, `root_trailer_to_bytes`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `slot_from_slice`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 5` (from `btree_split_right`, `btree_split_left`, `btree_join`) | 36 | [`xitdb/btree.odin#L8-L43`](../../xitdb/btree.odin#L8-L43) |
| `xitdb/btree.odin` | `btree_subtree` | `depth 5` (from `btree_split_right`, `btree_split_left`) | 14 | [`xitdb/btree.odin#L938-L951`](../../xitdb/btree.odin#L938-L951) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 5` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `write_btree_node`) | 33 | [`xitdb/btree.odin#L45-L77`](../../xitdb/btree.odin#L45-L77) |
| `xitdb/core.odin` | `_overlay_length` | `depth 5` (from `core_length`, `_overlay_read_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/types.odin` | `radix_shift` | `depth 5` (from `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 5` (from `read_array_list_slot_append`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/btree.odin` | `btree_height` | `depth 5` (from `btree_join`) | 24 | [`xitdb/btree.odin#L748-L771`](../../xitdb/btree.odin#L748-L771) |
| `xitdb/btree.odin` | `btree_merge_nodes` | `depth 5` (from `btree_join`, `btree_join_right`, `btree_join_left`) | 16 | [`xitdb/btree.odin#L830-L845`](../../xitdb/btree.odin#L830-L845) |
| `xitdb/btree.odin` | `btree_join_right` | `depth 5` (from `btree_join`) | 35 | [`xitdb/btree.odin#L847-L881`](../../xitdb/btree.odin#L847-L881) |
| `xitdb/btree.odin` | `btree_join_left` | `depth 5` (from `btree_join`) | 38 | [`xitdb/btree.odin#L883-L920`](../../xitdb/btree.odin#L883-L920) |
| `xitdb/btree.odin` | `btree_make_root` | `depth 5` (from `btree_join`) | 11 | [`xitdb/btree.odin#L773-L783`](../../xitdb/btree.odin#L773-L783) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 4` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 5` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `database_read_root_trailer`, `new_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 5` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `database_write_root_header`, `core_write_long`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 5` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 6` (from `read_btree_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 6` (from `read_btree_node`, `btree_height`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/btree.odin` | `btree_assemble_branch` | `depth 6` (from `btree_subtree`, `btree_merge_nodes`, `btree_join_right`) | 23 | [`xitdb/btree.odin#L806-L828`](../../xitdb/btree.odin#L806-L828) |
| `xitdb/core.odin` | `_overlay_page` | `depth 6` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/core.odin` | `core_write_long` | `depth 6` (from `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 6` (from `read_array_list_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/btree.odin` | `btree_assemble_leaf` | `depth 6` (from `btree_merge_nodes`) | 20 | [`xitdb/btree.odin#L785-L804`](../../xitdb/btree.odin#L785-L804) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 6` (from `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 7` (from `core_read_block_at`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 7` (from `btree_assemble_branch`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
