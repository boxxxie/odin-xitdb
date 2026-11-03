# #21. `Linked_Array_List (B-Tree) random get` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) · [Odin Harness (`bench_xitdb.odin#L956-L971`)](../bench_xitdb.odin#L956-L971) · [Zig Harness (`bench_xitdb.zig#L987-L1002`)](../bench_xitdb.zig#L987-L1002)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **53** | 53.6 ± 0.9 | 1.7% | 54.8 | 18,867,925 | - | **44.06x Odin** (`z = 43.9`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 2,335 | 2,292.2 ± 113.9 | 5.0% | 2,414.0 | 428,266 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Read Block Serialization vs. 18–34 Per-Field `std.Io` Calls ([`xitdb/btree.odin#L8-L75`](../../xitdb/btree.odin#L8-L75) vs. [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** This is the primary driver of Odin's **4.6x–44.9x speedup** on `Linked_Array_List` (`BTREE_SLOT_COUNT = 16`: `146B` leaf, `274B` branch). Zig's `readBTreeNode` and `writeBTreeNodeAt` loop over all 16 slots (and 16 counts on branches) unconditionally, issuing **18 to 34 individual unbuffered `takeInt`/`writeInt` calls** per node even when `node.num == 2`. Odin reads the node in **one `core_read_exact` call** into a stack buffer and decodes only `0 ..< node.num` active entries.
- **O(1) Direct Leaf Slot Seek in `read_btree_slot` ([`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181)):** On `#21 Linked_Array_List random get` (**44.06x faster in Odin: 53 ns vs 2,335 ns**), when `read_btree_slot` reaches a `.Leaf`, Odin peeks the 2-byte header and reads **only the single 9-byte `Slot`** at `node_ptr + 2 + rem * 9`. Zig's [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) calls `readBTreeNode` at the leaf, executing 18 `takeInt` calls and 16 tag checks to decode all 16 slots just to return `node.values[rem]`.
- **Targeted In-Place Branch Count Patching ([`xitdb/btree.odin#L224-L260`](../../xitdb/btree.odin#L224-L260)):** When inserting into a branch node already owned by the current transaction (`btree_reusable` is true and no child split occurred), Odin patches only the 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) instead of rewriting all 274 bytes.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Read/Write `BTreeNode` via a stack `[146]u8` / `[274]u8` buffer (`~25 lines` in [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** Read the node in one `reader.interface.readSliceAll` (and write in one `writer.interface.writeAll(&buf)`), decoding `0..node.num` in memory with `std.mem.readInt`. This keeps the `BTreeNode` struct and all split/join/rebalance logic 100% unchanged while eliminating 18–34 vtable/syscall dispatches per node.
- **Short-circuit `.leaf` in `readBTreeSlot` (`~8 lines` in [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042)):** Read the 2-byte `(kind, num)` header first; when `kind == .leaf`, seek directly to `node_ptr + 2 + rem * 9` and read 1 `Slot`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L956-L971`](../bench_xitdb.odin#L956-L971))

```odin
 956 | 		l_cur, _ := xitdb.array_list_get_cursor(history, 0)
 957 | 		rlist, _ := xitdb.read_linked_array_list_init(l_cur.?)
 958 | 
 959 | 		t1 := time.now()
 960 | 		for i in 0 ..< n {
 961 | 			ic, _ := xitdb.linked_array_list_get_cursor(rlist, i64(i))
 962 | 			v, _ := xitdb.cursor_read_uint(ic.?)
 963 | 			assert(v == u64(i))
 964 | 		}
 965 | 		elapsed_get := time.since(t1)
 966 | 
 967 | 		print_result(Bench_Result{
 968 | 			name    = "Linked_Array_List (B-Tree) random get",
 969 | 			ops     = n,
 970 | 			elapsed = elapsed_get,
 971 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L987-L1002`](../bench_xitdb.zig#L987-L1002))

```zig
 987 |         const l_cur = (try history.getCursor(0)).?;
 988 |         const rlist = try DB.LinkedArrayList(.read_only).init(l_cur);
 989 | 
 990 |         const t1 = std.Io.Clock.awake.now(io);
 991 |         for (0..n) |i| {
 992 |             const ic = (try rlist.getCursor(@intCast(i))).?;
 993 |             const v = try ic.readUint();
 994 |             std.debug.assert(v == @as(u64, @intCast(i)));
 995 |         }
 996 |         const elapsed_get = t1.untilNow(io, .awake).nanoseconds;
 997 | 
 998 |         try printResult(stdout, .{
 999 |             .name = "Linked_Array_List (B-Tree) random get",
1000 |             .ops = n,
1001 |             .elapsed_ns = elapsed_get,
1002 |         });
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

### Reached Odin Procedures (`28` procedures across `7` files · `577` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Linked_Array_List_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/collections.odin` | `linked_array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L133-L135`](../../xitdb/collections.odin#L133-L135) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L201-L210`](../../xitdb/cursor.odin#L201-L210) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`, `linked_array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L69-L80`](../../xitdb/cursor.odin#L69-L80) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `read_linked_array_list_init`, `cursor_read_uint`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `read_array_list_slot`, `read_btree_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/btree.odin` | `read_btree_slot` | `depth 4` (from `_exec_path_part`) | 79 | [`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1092-L1097`](../../xitdb/types.odin#L1092-L1097) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_btree_slot`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_length` | `depth 5` (from `read_array_list_slot`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `read_array_list_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_btree_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
