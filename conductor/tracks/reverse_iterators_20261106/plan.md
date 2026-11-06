# Implementation Plan: `reverse_iterators_20261106`

## Phase 1: Core Reverse Cursor Iterator & Range Seek Primitives
- [x] Implement `_fill_slot_block_from`, `_fill_slot_block_rev`, `_init_iter_level_rev`, `_init_btree_iter_level`, and `_init_btree_iter_level_rev` with `core_slice_at` zero-copy fast path and combined single-read file I/O in [`xitdb/cursor.odin`](../../xitdb/cursor.odin).
- [x] Implement `cursor_iterator_reverse`, `cursor_iterator_sorted_reverse_from_index`, `cursor_iterator_sorted_reverse_from_key`, `cursor_iterator_array_list_reverse_from_index`, and `cursor_iterator_linked_array_list_reverse_from_index` in [`xitdb/cursor.odin`](../../xitdb/cursor.odin).
- [x] Implement `_iterator_prev_internal` and `cursor_iterator_prev` using unsigned `u8` wrap-around symmetry in [`xitdb/cursor.odin`](../../xitdb/cursor.odin).

## Phase 2: High-Level Collection Reverse Iterator Wrappers
- [x] Implement `array_list_iterator_reverse`, `array_list_iterator_reverse_from`, `linked_array_list_iterator_reverse`, `linked_array_list_iterator_reverse_from`, `hash_map_iterator_reverse`, and `hash_set_iterator_reverse` in [`xitdb/collections.odin`](../../xitdb/collections.odin).
- [x] Implement `sorted_map_iterator_reverse`, `sorted_map_iterator_reverse_from`, `sorted_map_iterator_reverse_from_string`, `sorted_map_iterator_reverse_from_index`, `sorted_set_iterator_reverse`, `sorted_set_iterator_reverse_from`, `sorted_set_iterator_reverse_from_string`, and `sorted_set_iterator_reverse_from_index` in [`xitdb/collections.odin`](../../xitdb/collections.odin).

## Phase 3: 3-Layer ATDD Specification & Cross-Cutting Invariants
- [x] Add `spec_reverse_iterators_across_btree_bplustree_and_radix_trie` (Scenario 37) and `spec_reverse_iterators_on_buffered_file_three_tier_trees_and_boundary_guards` (Scenario 38) in [`tests/spec_xitdb.odin`](../../tests/spec_xitdb.odin) and [`tests/dsl_xitdb.odin`](../../tests/dsl_xitdb.odin).
- [x] Add cross-cutting reverse-equality assertions, `driver_verify_reverse_iterators_and_upper_bounds`, and `driver_verify_three_tier_buffered_file_reverse_iterators_and_guards` in [`tests/driver_xitdb.odin`](../../tests/driver_xitdb.odin).
- [x] Verify all 61 ATDD specifications and unit tests pass with zero memory leaks (`odin test tests`).

## Phase 4: Performance Benchmarking vs. Forward Iterator & Rank-Stepping
- [x] Benchmark forward vs. reverse iterators and `sorted_map_get_index_kv_pair` rank-stepping across `Core_Memory` and flushed `Core_Buffered_File` (`N = 10,000`), confirming `~1.00x` parity with forward iteration (`~4.7x` faster than rank-stepping in memory and `~47x` faster on disk).
