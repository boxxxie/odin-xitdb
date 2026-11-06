# Specification: Native Reverse & Upper-Bound Range Iterators

## Overview
Add zero-allocation, wire-compatible reverse iterators (`cursor_iterator_reverse`, `cursor_iterator_prev`, and upper-bound range initializers) across all `xitdb` persistent collections (`Sorted_Map`, `Sorted_Set`, `Linked_Array_List`, `Array_List`, `Hash_Map`, and `Hash_Set`).

Previously, descending range queries (`order_desc = true`) on a count-augmented B+Tree (`Sorted_Map` / `Sorted_Set`) required finding a starting rank via `sorted_map_rank_by_bytes` and stepping downward (`rank - 1, rank - 2, ...`) with `sorted_map_get_index_kv_pair`, incurring $O(K \log_{16} N)$ tree walks per page instead of $O(\log_{16} N + K / 16)$ sequential leaf block traversal.

## Architecture & Scope

1. **Zero-Allocation Reverse Stack Traversal (`xitdb/cursor.odin`):**
   - Preserve `Iter_Level` layout (`position: i64`, `index: u8`, `count: u8`, `block: [16]Slot`) and 100% binary wire compatibility.
   - Exploit unsigned `u8` wrap-around symmetry: initialize reverse frames with `level.index = u8(count - 1)` and `level.count = u8(count)`. Stepping backward with `level.index -= 1` wraps `0 - 1` to `255 >= level.count`, matching the exact single-branch bounds check (`if level.index >= level.count`) used by `_iterator_next_internal`.
   - Combine the 2-byte `BTree_Node_Header` and leaf slot block read into a single `core_read` call in `_init_btree_iter_level` and `_init_btree_iter_level_rev` on file-backed cores (`Core_File`, `Core_Buffered_File`), while using `core_slice_at` zero-copy decoding on `Core_Memory`.

2. **Upper-Bound Range Initializers (`xitdb/cursor.odin`):**
   - `cursor_iterator_reverse`: Full reverse traversal for `Array_List`, `Linked_Array_List`, `Hash_Map`, `Hash_Set`, `Counted_Hash_Map`, `Counted_Hash_Set`, `Sorted_Map`, and `Sorted_Set`.
   - `cursor_iterator_sorted_reverse_from_key(unresolved_cursor, upper_key, inclusive := true)`: $O(\log_{16} N)$ upper-bound positioning for `Sorted_Map` and `Sorted_Set`, including stale separator key handling after boundary deletions (`leaf_count == 0` when `before > 0` seamlessly steps to the preceding branch child).
   - `cursor_iterator_sorted_reverse_from_index(unresolved_cursor, start_index)`: $O(\log_{16} N)$ rank-indexed reverse positioning for `Sorted_Map` and `Sorted_Set`.
   - `cursor_iterator_array_list_reverse_from_index(unresolved_cursor, start_index)`: $O(\log_{16} N)$ radix-trie reverse positioning for `Array_List`.
   - `cursor_iterator_linked_array_list_reverse_from_index(unresolved_cursor, start_index)`: $O(\log_{16} N)$ count-augmented B-Tree reverse positioning for `Linked_Array_List`.

3. **Typed Collection Wrappers (`xitdb/collections.odin`):**
   - `array_list_iterator_reverse`, `array_list_iterator_reverse_from`
   - `linked_array_list_iterator_reverse`, `linked_array_list_iterator_reverse_from`
   - `hash_map_iterator_reverse`, `hash_set_iterator_reverse`
   - `sorted_map_iterator_reverse`, `sorted_map_iterator_reverse_from`, `sorted_map_iterator_reverse_from_string`, `sorted_map_iterator_reverse_from_index`
   - `sorted_set_iterator_reverse`, `sorted_set_iterator_reverse_from`, `sorted_set_iterator_reverse_from_string`, `sorted_set_iterator_reverse_from_index`

4. **3-Layer ATDD Executable Specifications (`tests/`):**
   - Cross-cutting reverse-iteration invariants in `driver_assert_moment_array_list`, `driver_assert_moment_linked_list`, `driver_assert_moment_sorted_set`, `driver_assert_moment_sorted_map`, and `driver_verify_indexed_range_iterators`.
   - Scenario 37 (`spec_reverse_iterators_across_btree_bplustree_and_radix_trie`): Tests inclusive/exclusive key upper bounds, out-of-bounds clamping, empty iterators, HAMT reverse sequence equality, and stale B+Tree separator boundaries on `Core_Memory`.
   - Scenario 38 (`spec_reverse_iterators_on_buffered_file_three_tier_trees_and_boundary_guards`): Tests 3-tier B+Trees (`N = 200`) over flushed `Core_Buffered_File`, multi-level stale branch separator cascades across internal branch boundaries, `.None` (`full=true` vs `full=false`) sparse `Array_List` slots, `.Unexpected_Tag` guards, and post-exhaustion idempotence.
