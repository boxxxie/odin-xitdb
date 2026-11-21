# xitdb Test Suite

This directory contains the test suite for `xitdb`. It combines **Acceptance Test-Driven Development (ATDD)** executable specifications, property-based invariant checks, and low-level wire-format unit tests.

---

## Quick Start

Run the entire test suite from the repository root (enforcing zero leaks / bad frees):

```bash
odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
```

Run a single specification or unit test by name:

```bash
odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_NAMES=xitdb_tests.spec_reference_database_wire_compatibility
```

Run with thread count and verbose output:

```bash
odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -terse
```

---

## 3-Layer Architecture

Following Dave Farley's Acceptance Testing architecture, the test suite is strictly separated into three layers so that behavioral specifications remain readable and decoupled from low-level cursor mechanics:

```text
tests/
├── spec_xitdb.odin             # Layer 1: Core Executable Specifications (What the system does)
├── spec_dsl_xitdb.odin         # Layer 1: 5-Layer DSL & Datalog Executable Specifications
├── unit_user_dsl.odin          # Direct Unit & Integration Tests for the User DSL (`xitdb/dsl.odin`)
├── unit_lua.odin               # Unit Tests for the LuaJIT bridge (`xitdb/lua.odin`)
├── unit_fuzz_regressions.odin  # Deterministic regressions promoted from libFuzzer & simulation runs
├── fuzz_sim_xitdb.odin         # Seeded PRNG differential simulation against pure-Odin models
├── dsl_xitdb.odin              # Layer 2: Domain-Specific Language (Given / Upon / Then steps)
├── driver_xitdb.odin           # Layer 3: Protocol Drivers (How xitdb APIs & cursors are invoked)
└── testdata/
    └── test.db                 # Upstream v1 reference database fixture for cross-language parity
```

### Layer 1: Executable Specifications (`spec_xitdb.odin`)
* Expresses database guarantees in the domain language of **historical moments**, **branching snapshots**, **lexicographical ranks**, **incremental delta replication**, **compaction**, and **atomic rollback**.
* Contains **zero** raw byte offsets, slot bitmasks, or cursor plumbing.

### Layer 2: Domain-Specific Language (`dsl_xitdb.odin`)
* Provides reusable, composable steps prefixed by role:
  * `given_*` — Establishes preconditions and seeds moments (e.g., `given_buffered_file_database`, `given_committed_moment`, `given_users_with_secondary_username_index`).
  * `upon_*` — Triggers domain transitions (e.g., `upon_branching_moment`, `upon_replicating_to_secondary`, `upon_compacting_database`).
  * `then_*` — Asserts postconditions and cross-cutting invariants (e.g., `then_moment_has_sorted_map_in_order`, `then_last_sync_was_incremental`).

### Layer 3: Protocol Drivers (`driver_xitdb.odin`)
* The **only** layer that directly touches `xitdb.Database`, `xitdb.Core`, `xitdb.Write_Cursor`, `xitdb.Slot`, and wire-format primitives.
* Automatically enforces cross-cutting invariants on every collection assertion:
  * Asserting a `Linked_Array_List` verifies both $O(\log N)$ positional index lookup (`linked_array_list_get_cursor`) and sequential B-Tree leaf iteration (`linked_array_list_iterator`).
  * Asserting a `Sorted_Map` verifies strict ascending lexicographical order across the iterator, `sorted_map_rank(k) == i`, and `sorted_map_get_index_kv_pair(i) == k` for every element.
  * Asserting a tagged document verifies both `cursor_read_bytes_object` and streaming `Cursor_Reader` output.

---

## What Is Covered

| Category | Scenarios in `spec_xitdb.odin` |
| :--- | :--- |
| **Upstream Wire Compatibility** | `spec_reference_database_wire_compatibility` validates byte-for-byte compatibility against the upstream `test.db` v1 fixture. |
| **Historical Immutability & Rich Types** | `spec_branching_moments_preserve_historical_immutability`, `spec_inline_short_bytes_vs_external_bytes_and_tagged_thresholds`, `spec_bytes_keyed_collections_and_kv_pair_inspection`. |
| **HAMT & Radix Trie Edge Cases** | `spec_hamt_hash_prefix_conflict_branching_and_branch_shortening`, `spec_custom_64bit_hasher_handles_deep_nibble_prefix_collisions`, `spec_radix_trie_root_overflow_slicing_and_sparse_none_slots`. |
| **B-Tree & B+Tree Operations** | `spec_sorted_catalog_maintains_lexicographical_ranks_across_splits_and_merges`, `spec_btree_linked_list_slice_concat_insert_remove_across_leaf_and_branch_tiers`, `spec_sorted_set_multi_tier_splits_rebalancing_and_range_iterators`, `spec_linked_array_list_slice_to_empty_and_range_error_guards`, `spec_property_sorted_map_and_linked_list_invariants`. |
| **Range Iterators & Indexing** | `spec_deep_radix_trie_and_btree_range_iterators`, `spec_sorted_map_lower_bound_and_negative_index_iterators`, `spec_secondary_index_pagination_and_prefix_autocomplete`, `unit_cursor_iterator_in_place_init_and_reuse_invariants`. |
| **Freeze & Copy-on-Write Isolation** | `spec_frozen_writers_reject_in_place_mutation_and_survive_transaction_rollback`, `spec_cloning_collections_and_cursor_freeze_copy_on_write_isolation`, `spec_multi_tier_btree_in_place_updates_and_cursor_freeze_isolation`. |
| **Crash Recovery & Transaction Guards** | `spec_buffered_file_atomic_rollback_and_file_offset_map_compaction`, `spec_unfinished_transaction_trailing_bytes_are_truncated_on_next_write`, `spec_expired_cursors_and_nested_root_transactions_are_rejected`. |
| **Replication & Compaction** | `spec_incremental_replication_and_garbage_collecting_compaction`, `spec_replication_detects_diverged_file_id_and_commit_history`, `spec_compaction_preserves_cyclic_graphs_and_supports_continued_writes`, `spec_post_compaction_replica_resync_converges_cleanly`, `spec_reopening_compacted_file_database_and_independent_file_handles`. |
| **Crypto & Wire Guards** | `unit_cryptographic_hash_vectors_and_trailer_crc64`, `unit_wire_format_validation_and_error_guards`, `unit_streaming_writer_seek_overwrite_and_memory_truncation_clamping`, `unit_cursor_reader_byte_by_byte_seek_and_eof_boundaries`, `spec_corrupt_slot_tags_inflated_branch_counts_and_truncated_btree_nodes_are_rejected`, `spec_compactor_and_buffered_file_enforce_max_size_and_allocation_failure_guards`. |
| **Lock-Free Concurrency & Virtual Memory (`core_read_at` & `vmem.reserve`)** | `spec_lock_free_concurrent_cursors_and_resumable_iterators`, `spec_virtual_memory_base_pointer_stability_under_concurrent_appends`, `spec_concurrent_compaction_and_replication_with_parallel_readers`, `spec_concurrent_dsl_selectors_pull_diff_and_datalog_queries`, `spec_virtual_memory_reservation_cap_shrink_regrow_and_init_from_bytes`. |
| **5-Layer DSL & Datalog Engine** | `spec_datomic_tx_metadata_path_selectors_and_temporal_history`, `spec_struct_marshal_unmarshal_and_datomic_pull_projection`, `spec_datalog_unification_across_btree_indexes_hash_maps_and_negated_sets`, `spec_temporal_datalog_unification_across_moments_and_tx_metadata`, `spec_datalog_grouped_and_global_aggregations`, `spec_datalog_transitive_reach_and_cycle_safe_graph_traversal`, `spec_dsl_error_guards_savepoint_survival_and_counted_collections`. |
| **User DSL Direct Unit Tests (`unit_user_dsl.odin`)** | `unit_user_dsl_selector_sigils_combinators_and_nested_resolution`, `unit_user_dsl_tx_wants_tx_meta_gating_fork_and_savepoint`, `unit_user_dsl_transact_script_literals_and_ops`, `unit_user_dsl_marshal_unmarshal_types_and_pull_ranges`, `unit_user_dsl_diff_moments_history_of_and_btree_queries`, `unit_user_dsl_datalog_predicates_pushdown_aggregations_and_reach`, `unit_user_dsl_secondary_index_stale_key_eviction_and_heap_allocator_cleanup`, `unit_user_dsl_cyclic_graph_pull_and_diff_safety`, `unit_user_dsl_deep_recursive_pull_and_diff_small_stack_safety`, `unit_user_dsl_iterator_pool_oom_and_range_edge_guards`, `unit_user_dsl_arena_context_allocator_bounds_iterator_growth`. |
| **Fuzzing & Differential Simulation (`fuzz_sim_xitdb.odin`, `unit_fuzz_regressions.odin`)** | `fuzz_sim_differential_collections_iterators_overlay_and_compaction`, `fuzz_sim_multi_seed_sha256_and_branching_histories`, `unit_fuzz_regression_dsl_selector_roundtrip_escaping`, `unit_fuzz_regression_datalog_leading_where_and_deep_reach_no_panic`, `unit_fuzz_regression_dsl_pull_huge_range_no_oom`, `unit_fuzz_regression_tx_invalid_selector_and_escaped_keys_zero_leaks`, `unit_fuzz_regression_wire_corrupt_bytes_length_and_cyclic_nodes_no_oom`, `unit_fuzz_regression_negative_slot_values_and_core_bounds`, `unit_fuzz_regression_lua_commit_error_uaf_and_reuse_guards`, `unit_fuzz_regression_diff_corrupt_array_count_and_btree_write_guards`, `unit_fuzz_regression_deep_hamt_diff_over_32_nibbles`, `unit_fuzz_regression_dsl_persistent_allocator_and_where_boundaries`, `unit_fuzz_regression_btree_sibling_cycles_concat_max_size_and_shrink`, `unit_fuzz_regression_array_list_counted_map_and_sorted_empty_fast_paths`. |

---

## Fuzzing & Differential Simulation

Two complementary fuzzing layers cover `xitdb`:

1. **Deterministic Differential Simulation (`tests/fuzz_sim_xitdb.odin`):**
   * Runs fast smoke seeds inside default `odin test tests`.
   * Scale up operation counts or pin a specific seed under AddressSanitizer:
     ```bash
     odin test tests -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_FUZZ_OPS=2000
     odin test tests -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_FUZZ_SEED=42 -define:ODIN_FUZZ_OPS=2000
     ```

2. **Coverage-Guided `libFuzzer` + ASan / LSan Harnesses (`fuzz/`):**
   * Builds Odin targets via `-build-mode:llvm-ir -sanitize:address` and links with `clang -fsanitize=fuzzer,address` (writing binaries, corpora, and crash artifacts under git-ignored `.tmp/fuzz/`; run from the repository root):
     ```bash
     ./fuzz/run.sh all -runs=2000          # smoke check all targets
     ./fuzz/run.sh dsl -max_total_time=30   # fuzz selectors, Datalog, Pull, and transact_script
     ./fuzz/run.sh wire -max_total_time=30  # fuzz corrupted .xit wire blobs & compaction
     ./fuzz/run.sh lua -max_total_time=30   # fuzz sandboxed LuaJIT bridge + leak detection
     ```

---

## Adding a New Test

1. **Write the specification first** in `spec_xitdb.odin` using `given_*`, `upon_*`, and `then_*` calls that describe the intended behavior.
2. **Add or reuse DSL steps** in `dsl_xitdb.odin` to bridge domain parameters to the driver.
3. **Implement the driver mechanics** in `driver_xitdb.odin` and ensure all temporary files and allocators are cleaned up in `driver_destroy_ctx`.
