# xitdb Test Suite

This directory contains the test suite for `xitdb`. It combines **Acceptance Test-Driven Development (ATDD)** executable specifications, property-based invariant checks, and low-level wire-format unit tests.

---

## Quick Start

Run the entire test suite from the repository root:

```bash
odin test tests
```

Run a single specification or unit test by name:

```bash
odin test tests -define:ODIN_TEST_NAMES=xitdb_tests.spec_reference_database_wire_compatibility
```

Run with thread count and verbose output:

```bash
odin test tests -terse
```

---

## 3-Layer Architecture

Following Dave Farley's Acceptance Testing architecture, the test suite is strictly separated into three layers so that behavioral specifications remain readable and decoupled from low-level cursor mechanics:

```text
tests/
├── spec_xitdb.odin          # Layer 1: Core Executable Specifications (What the system does)
├── spec_dsl_xitdb.odin      # Layer 1: 5-Layer DSL & Datalog Executable Specifications
├── unit_user_dsl.odin       # Direct Unit & Integration Tests for the User DSL (`xitdb/dsl.odin`)
├── dsl_xitdb.odin           # Layer 2: Domain-Specific Language (Given / Upon / Then steps)
├── driver_xitdb.odin        # Layer 3: Protocol Drivers (How xitdb APIs & cursors are invoked)
└── testdata/
    └── test.db              # Upstream v1 reference database fixture for cross-language parity
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
| **Range Iterators & Indexing** | `spec_deep_radix_trie_and_btree_range_iterators`, `spec_sorted_map_lower_bound_and_negative_index_iterators`, `spec_secondary_index_pagination_and_prefix_autocomplete`. |
| **Freeze & Copy-on-Write Isolation** | `spec_frozen_writers_reject_in_place_mutation_and_survive_transaction_rollback`, `spec_cloning_collections_and_cursor_freeze_copy_on_write_isolation`, `spec_multi_tier_btree_in_place_updates_and_cursor_freeze_isolation`. |
| **Crash Recovery & Transaction Guards** | `spec_buffered_file_atomic_rollback_and_file_offset_map_compaction`, `spec_unfinished_transaction_trailing_bytes_are_truncated_on_next_write`, `spec_expired_cursors_and_nested_root_transactions_are_rejected`. |
| **Replication & Compaction** | `spec_incremental_replication_and_garbage_collecting_compaction`, `spec_replication_detects_diverged_file_id_and_commit_history`, `spec_compaction_preserves_cyclic_graphs_and_supports_continued_writes`, `spec_post_compaction_replica_resync_converges_cleanly`, `spec_reopening_compacted_file_database_and_independent_file_handles`. |
| **Crypto & Wire Guards** | `unit_cryptographic_hash_vectors_and_trailer_crc64`, `unit_wire_format_validation_and_error_guards`, `unit_streaming_writer_seek_overwrite_and_memory_truncation_clamping`, `unit_cursor_reader_byte_by_byte_seek_and_eof_boundaries`. |
| **5-Layer DSL & Datalog Engine** | `spec_datomic_tx_metadata_path_selectors_and_temporal_history`, `spec_struct_marshal_unmarshal_and_datomic_pull_projection`, `spec_datalog_unification_across_btree_indexes_hash_maps_and_negated_sets`, `spec_temporal_datalog_unification_across_moments_and_tx_metadata`, `spec_datalog_grouped_and_global_aggregations`, `spec_datalog_transitive_reach_and_cycle_safe_graph_traversal`, `spec_dsl_error_guards_savepoint_survival_and_counted_collections`. |
| **User DSL Direct Unit Tests (`unit_user_dsl.odin`)** | `unit_user_dsl_selector_sigils_combinators_and_nested_resolution`, `unit_user_dsl_tx_wants_tx_meta_gating_fork_and_savepoint`, `unit_user_dsl_transact_script_literals_and_ops`, `unit_user_dsl_marshal_unmarshal_types_and_pull_ranges`, `unit_user_dsl_diff_moments_history_of_and_btree_queries`, `unit_user_dsl_datalog_predicates_pushdown_aggregations_and_reach`. |

---

## Adding a New Test

1. **Write the specification first** in `spec_xitdb.odin` using `given_*`, `upon_*`, and `then_*` calls that describe the intended behavior.
2. **Add or reuse DSL steps** in `dsl_xitdb.odin` to bridge domain parameters to the driver.
3. **Implement the driver mechanics** in `driver_xitdb.odin` and ensure all temporary files and allocators are cleaned up in `driver_destroy_ctx`.
