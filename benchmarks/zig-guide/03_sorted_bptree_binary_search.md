# 03. `SortedMap` & `SortedSet` (Counted B+Tree): Binary Search, Batch Node I/O & Index Select

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

Across all 11 `SortedMap` and `SortedSet` benchmarks (`#28–#38`), Odin is **4.1x to 51.3x faster** while producing byte-identical `115.4 KB` (`SortedMap`) and `80.0 KB` (`SortedSet`) B+Trees:

| # | Benchmark | Odin (`-o:speed`) | Zig (`ReleaseFast`) | Speedup | Slice |
| ---: | :--- | ---: | ---: | :--- | :--- |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **388 ns** | 4,511 ns | **11.63x Odin** | [Slice #28](../slices/28_sorted_map_b_tree_out_of_order_put.md) |
| 29 | `Sorted_Map (B+Tree) key lookup` | **163 ns** | 4,242 ns | **26.02x Odin** | [Slice #29](../slices/29_sorted_map_b_tree_key_lookup.md) |
| 30 | `Sorted_Map (B+Tree) rank query` | **131 ns** | 4,205 ns | **32.10x Odin** | [Slice #30](../slices/30_sorted_map_b_tree_rank_query.md) |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **230 ns** | 5,966 ns | **25.94x Odin** | [Slice #33](../slices/33_sorted_map_b_tree_remove_rebalance.md) |
| 34 | `Sorted_Map (B+Tree) get_index select` | **64 ns** | 3,280 ns | **51.25x Odin** | [Slice #34](../slices/34_sorted_map_b_tree_get_index_select.md) |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **144 ns** | 3,953 ns | **27.45x Odin** | [Slice #38](../slices/38_sorted_set_b_tree_contains_lookup.md) |

---

## 2. What Happens Today in `lib.zig`

Four compounding factors explain the `11x–51x` gap:

1. **Linear Scans Instead of Binary Search in 4 Places:** [`sortedGet`](../../reference/xitdb-zig/src/lib.zig#L2640-L2654), [`sortedRank`](../../reference/xitdb-zig/src/lib.zig#L2690-L2702), [`sortedPut`](../../reference/xitdb-zig/src/lib.zig#L2743-L2757), and [`sortedStackFromKey`](../../reference/xitdb-zig/src/lib.zig#L3657-L3672) all scan `0..node.num` linearly:
   ```zig
   // reference/xitdb-zig/src/lib.zig#L2640-L2653
   .leaf => {
       for (0..node.num) |i| {
           const entry = node.entries[i];
           const key_slot = try self.sortedEntryKeySlot(entry);
           switch (try self.compareKey(key_slot, key)) {
               .eq => return .{ .slot = entry, .key_slot = key_slot, .position = ... },
               .gt => return null,
               .lt => {},
           }
       }
       return null;
   },
   ```
   Because each leaf comparison in `SortedMap` seeks to a `SortedKeyValuePair` (`sortedEntryKeySlot`) and then seeks to the `.bytes` key (`compareKey`), scanning up to 16 entries linearly performs up to **32 seeks per node** instead of at most **$\lceil \log_2 16 \rceil = 4$ comparisons** with binary search.

2. **`@splat(0)` Zeroing 256 Bytes on Every External Key Comparison:** In [`compareKey`](../../reference/xitdb-zig/src/lib.zig#L2612), `var key_buf: [256]u8 = @splat(0);` zero-fills 256 stack bytes before immediately overwriting `key_buf[0..read_len]` via `readSliceAll`.

3. **50 Virtual `takeInt` / `writeInt` Calls per Branch Node:** [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) and [`writeSortedNodeAt`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) issue `2 + 16 = 18` `takeInt`/`writeInt` calls for a 146-byte leaf and `2 + 16 + 16 + 16 = 50` calls for a 418-byte branch (`SORTED_BRANCH_BLOCK_SIZE`).

4. **Full Leaf Decode on `sortedGetByIndex` (`51.25x` gap on `#34`):** [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) calls `readSortedNode` on `.leaf` (18 `takeInt` calls) instead of seeking directly to `node_ptr + 2 + rem * 9`.

---

## 3. What Odin Does (`xitdb/btree.odin`)

- **Shared Binary Search Helpers ([`xitdb/btree.odin#L1213-L1245`](../../xitdb/btree.odin#L1213-L1245)):** `sorted_leaf_search` and `sorted_branch_search` perform $O(\log_2 B)$ binary search ($\le 4$ comparisons per level).
- **Uninitialized Stack Buffer in `compare_key` ([`xitdb/btree.odin#L1189-L1195`](../../xitdb/btree.odin#L1189-L1195)):** Uses `stack_buf: [256]u8 = ---` (`undefined` in Zig) and slices in-memory `Core_Memory` / `Core_Buffered_File` key bytes directly without copying.
- **Stack-Buffered `Sorted_Node` Read/Write & Direct Leaf Slot Seek ([`xitdb/btree.odin#L1028-L1105`](../../xitdb/btree.odin#L1028-L1105), [`xitdb/btree.odin#L1361-L1439`](../../xitdb/btree.odin#L1361-L1439)).**

---

## 4. Idiomatic Zig Update (Cleaner & Shorter Than 4 Linear Loops)

### Step 1: Two Reusable Binary Search Helpers (`~24 lines`)

Extracting `sortedBranchSearch` and `sortedLeafSearch` *reduces* duplication across `sortedGet`, `sortedRank`, `sortedPut`, `sortedRemove`, and `sortedStackFromKey`:

```zig
const LeafSearchResult = struct {
    index: usize,
    found: bool,
    key_slot: Slot = .{},
};

// Returns the child index `0 .. node.num - 1` whose key range contains `key`.
fn sortedBranchSearch(self: *Database(db_kind, HashInt), node: *const SortedNode, key: []const u8) !usize {
    var lo: usize = 1;
    var hi: usize = node.num;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (try self.compareKey(node.separators[mid], key)) {
            .lt, .eq => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return lo - 1;
}

// Returns `{ .index = match_idx, .found = true, .key_slot = ks }` on exact match,
// or `{ .index = lower_bound_idx, .found = false }` when absent.
fn sortedLeafSearch(self: *Database(db_kind, HashInt), node: *const SortedNode, key: []const u8) !LeafSearchResult {
    var lo: usize = 0;
    var hi: usize = node.num;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const ks = try self.sortedEntryKeySlot(node.entries[mid]);
        switch (try self.compareKey(ks, key)) {
            .eq => return .{ .index = mid, .found = true, .key_slot = ks },
            .lt => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return .{ .index = lo, .found = false };
}
```

Now `sortedGet`, `sortedRank`, and `sortedPut` become **shorter and easier to read** than before:

```zig
fn sortedGet(self: *Database(db_kind, HashInt), root_ptr: u64, key: []const u8) !?SortedSlot {
    var node_ptr = root_ptr;
    while (true) {
        const node = try self.readSortedNode(node_ptr);
        switch (node.kind) {
            .leaf => {
                const res = try self.sortedLeafSearch(&node, key);
                if (!res.found) return null;
                return .{
                    .slot = node.entries[res.index],
                    .key_slot = res.key_slot,
                    .position = node_ptr + BTREE_NODE_HEADER_SIZE + res.index * byteSizeOf(Slot),
                };
            },
            .branch => {
                const i = try self.sortedBranchSearch(&node, key);
                node_ptr = node.children[i].value;
            },
        }
    }
}
```

### Step 2: Drop `@splat(0)` in `compareKey` (`1-line change`)

In [`lib.zig#L2612`](../../reference/xitdb-zig/src/lib.zig#L2612):

```zig
// Before:
var key_buf: [256]u8 = @splat(0);
// After (`readSliceAll` fills `key_buf[0..read_len]` completely before it is read):
var key_buf: [256]u8 = undefined;
```

### Step 3: Batch `readSortedNode` / `writeSortedNodeAt` + Direct Leaf Seek in `sortedGetByIndex`

Apply the exact same stack-buffer pattern from [Guide 02](02_btree_node_batch_io_and_leaf_seek.md) (`[SORTED_LEAF_BLOCK_SIZE]u8` = 146B and `[SORTED_BRANCH_BLOCK_SIZE]u8` = 418B, decoding `0..num` in `readSortedNode`), and short-circuit `.leaf` in `sortedGetByIndex`:

```zig
// Inside sortedGetByIndex when hdr[0] == .leaf:
const pos = node_ptr + BTREE_NODE_HEADER_SIZE + rem * byteSizeOf(Slot);
try reader.seekTo(pos);
const s: Slot = @bitCast(try takeInt(&reader.interface, SlotInt, .big));
try s.tag.validate();
return .{ .slot = s, .key_slot = .{}, .position = pos };
```
