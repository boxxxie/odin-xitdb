package xitdb_tests

import "core:testing"
import xitdb "../xitdb"

// ============================================================================
// Layer 2: Domain-Specific Language (`dsl_xitdb.odin`)
// ============================================================================
// Translates domain concepts (moments, history, snapshots, replication,
// compaction, rollbacks) into parameterized calls on Layer 3 (`driver_xitdb.odin`).
// Every step takes `^Suite_Ctx` + explicit domain parameters so Layer 1
// executable specifications remain 100% self-contained and free of technical
// plumbing.

// ----------------------------------------------------------------------------
// `@given` Steps — Domain Preconditions & Seed State
// ----------------------------------------------------------------------------

given_reference_database_fixture :: proc(ctx: ^Suite_Ctx, fixture_path: string) {
	driver_open_fixture(ctx, fixture_path)
}

given_in_memory_database :: proc(ctx: ^Suite_Ctx, hash_algo: string = "sha1") {
	ctx.backend_kind = .Memory
	driver_open_primary(ctx, hash_algo)
}

given_buffered_file_database :: proc(ctx: ^Suite_Ctx, hash_algo: string = "sha1", buffer_bytes: i64 = 512) {
	ctx.backend_kind = .Buffered_File
	driver_open_primary(ctx, hash_algo, buffer_bytes)
}

given_file_database :: proc(ctx: ^Suite_Ctx, hash_algo: string = "sha1") {
	ctx.backend_kind = .File
	driver_open_primary(ctx, hash_algo)
}

given_database_initialized_with :: proc(ctx: ^Suite_Ctx, backend: Backend_Kind, hash_algo: string = "sha1") {
	ctx.backend_kind = backend
	driver_open_primary(ctx, hash_algo)
}

given_committed_moment :: proc(ctx: ^Suite_Ctx, ops: ..Moment_Mutation_Op) {
	err := driver_commit_moment(ctx, nil, ops)
	testing.expect_value(ctx.t, err, nil)
}

given_committed_moments_count :: proc(ctx: ^Suite_Ctx, count: int, ops: ..Moment_Mutation_Op) {
	for _ in 0 ..< count {
		err := driver_commit_moment(ctx, nil, ops)
		testing.expect_value(ctx.t, err, nil)
	}
}

// ----------------------------------------------------------------------------
// `@upon` Steps — Domain Actions & Transitions
// ----------------------------------------------------------------------------

upon_branching_moment :: proc(ctx: ^Suite_Ctx, from_moment: i64, ops: ..Moment_Mutation_Op) {
	err := driver_commit_moment(ctx, from_moment, ops)
	testing.expect_value(ctx.t, err, nil)
}

upon_branching_compacted_moment :: proc(ctx: ^Suite_Ctx, from_moment: i64, ops: ..Moment_Mutation_Op) {
	err := driver_commit_moment(ctx, from_moment, ops, .Compacted)
	testing.expect_value(ctx.t, err, nil)
}

upon_attempting_moment_that_aborts :: proc(ctx: ^Suite_Ctx, ops: ..Moment_Mutation_Op) {
	_ = driver_commit_moment(ctx, nil, ops)
}

upon_replicating_to_secondary :: proc(ctx: ^Suite_Ctx) {
	driver_sync_to_replica(ctx)
}

upon_retaining_latest_moments :: proc(ctx: ^Suite_Ctx, count: i64) {
	driver_slice_history(ctx, count)
}

upon_compacting_database :: proc(ctx: ^Suite_Ctx, use_file_offset_map: bool = false) {
	driver_compact_primary(ctx, use_file_offset_map)
}

upon_flushing_database :: proc(ctx: ^Suite_Ctx) {
	driver_flush_primary(ctx)
}

// ----------------------------------------------------------------------------
// `@then` Steps — Domain Outcome Assertions
// ----------------------------------------------------------------------------

then_history_has_moments :: proc(ctx: ^Suite_Ctx, expected_count: i64, on: Db_Target = .Primary) {
	actual := driver_history_count(ctx, on)
	testing.expect_value(ctx.t, actual, expected_count)
}

then_moment_has_string :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected: string, on: Db_Target = .Primary) {
	driver_assert_moment_string(ctx, moment_idx, key, expected, on)
}

then_moment_stores_inline_short_bytes :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, on: Db_Target = .Primary) {
	driver_assert_moment_slot_tag(ctx, moment_idx, key, .Short_Bytes, on)
}

then_moment_lacks_key :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, on: Db_Target = .Primary) {
	driver_assert_moment_key_absent(ctx, moment_idx, key, on)
}

then_moment_has_scalars :: proc(ctx: ^Suite_Ctx, moment_idx: i64, expected_int: Key_Int, expected_uint: Key_Uint, expected_float: Key_Float) {
	driver_assert_moment_int(ctx, moment_idx, expected_int.key, expected_int.val)
	driver_assert_moment_uint(ctx, moment_idx, expected_uint.key, expected_uint.val)
	driver_assert_moment_float(ctx, moment_idx, expected_float.key, expected_float.val)
}

then_moment_has_tagged_document :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_text: string, expected_tag: string) {
	driver_assert_moment_tagged_text(ctx, moment_idx, key, expected_text, expected_tag)
}

then_moment_has_array_list :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_items: []string, on: Db_Target = .Primary) {
	driver_assert_moment_array_list(ctx, moment_idx, key, expected_items, on)
}

then_moment_has_nested_record_uint :: proc(ctx: ^Suite_Ctx, moment_idx: i64, list_key: string, record_index: i64, field: string, expected: u64) {
	driver_assert_moment_nested_map_uint(ctx, moment_idx, list_key, record_index, field, expected)
}

then_moment_has_linked_list :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_items: []string, on: Db_Target = .Primary) {
	driver_assert_moment_linked_list(ctx, moment_idx, key, expected_items, on)
}

then_moment_has_counted_map_size :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64) {
	driver_assert_moment_counted_map_count(ctx, moment_idx, key, expected_count)
}

then_moment_has_set_members :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_members: []string) {
	driver_assert_moment_hash_set_contains(ctx, moment_idx, key, expected_members)
}

then_moment_has_counted_set :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64, expected_members: []string) {
	driver_assert_moment_counted_set(ctx, moment_idx, key, expected_count, expected_members)
}

then_moment_has_sorted_set_in_order :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_sorted_members: []string) {
	driver_assert_moment_sorted_set(ctx, moment_idx, key, expected_sorted_members)
}

then_moment_has_sorted_map_in_order :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key: string, expected_count: i64, sample_ranks: []Key_Int = nil) {
	sm := driver_assert_moment_sorted_map(ctx, moment_idx, key, expected_count)
	for sr in sample_ranks {
		actual_rank, err := xitdb.sorted_map_rank(sm, sr.key)
		testing.expect_value(ctx.t, err, nil)
		testing.expect_value(ctx.t, actual_rank, sr.val)
	}
}

then_last_sync_started_at_genesis :: proc(ctx: ^Suite_Ctx) {
	testing.expect_value(ctx.t, ctx.last_sync_start, i64(0))
}

then_last_sync_was_incremental :: proc(ctx: ^Suite_Ctx) {
	testing.expect(ctx.t, ctx.last_sync_start > 0, "Expected incremental replication start offset > 0")
}

then_compacted_footprint_is_smaller :: proc(ctx: ^Suite_Ctx) {
	orig_size, err1 := xitdb.database_committed_size(&ctx.primary_db)
	comp_size, err2 := xitdb.database_committed_size(&ctx.compacted_db)
	testing.expect_value(ctx.t, err1, nil)
	testing.expect_value(ctx.t, err2, nil)
	testing.expectf(ctx.t, comp_size < orig_size, "Expected compacted size (%d) < uncompacted size (%d)", comp_size, orig_size)
}

then_aborted_transaction_leaves_committed_size_unchanged :: proc(ctx: ^Suite_Ctx, expected_err: xitdb.Xitdb_Error, expected_size: i64) {
	testing.expect_value(ctx.t, ctx.last_err, expected_err)
	actual_size := driver_committed_size(ctx)
	testing.expect_value(ctx.t, actual_size, expected_size)
}

// ----------------------------------------------------------------------------
// Extended DSL Steps
// ----------------------------------------------------------------------------

given_in_memory_database_with_file_id :: proc(ctx: ^Suite_Ctx, file_id: u64, hash_algo: string = "sha1") {
	driver_open_primary_with_file_id(ctx, file_id, hash_algo)
}

upon_writing_root_uint :: proc(ctx: ^Suite_Ctx, val: u64) {
	driver_write_root_uint(ctx, val)
}

upon_writing_root_string :: proc(ctx: ^Suite_Ctx, val: string) {
	driver_write_root_string(ctx, val)
}

upon_committing_cyclic_moment :: proc(ctx: ^Suite_Ctx, base_moment: i64) {
	driver_commit_cyclic_moment(ctx, base_moment)
}

then_root_has_uint :: proc(ctx: ^Suite_Ctx, expected: u64, on: Db_Target = .Primary) {
	driver_assert_root_uint(ctx, expected, on)
}

then_root_has_string :: proc(ctx: ^Suite_Ctx, expected: string, on: Db_Target = .Primary) {
	driver_assert_root_string(ctx, expected, on)
}

then_root_is_empty :: proc(ctx: ^Suite_Ctx, on: Db_Target = .Primary) {
	driver_assert_root_empty(ctx, on)
}

then_frozen_cursors_and_streams_reject_writes_and_survive_rollback :: proc(ctx: ^Suite_Ctx, initial_val: i64, post_freeze_val: i64, stream_len: int) {
	driver_verify_freeze_protection_and_survival(ctx, initial_val, post_freeze_val, stream_len)
}

then_nested_and_expired_transactions_are_rejected :: proc(ctx: ^Suite_Ctx) {
	driver_verify_expired_and_nested_transaction_guards(ctx)
}

then_indexed_range_iterators_match_expected_slices :: proc(ctx: ^Suite_Ctx, moment_idx: i64, array_key: string, linked_key: string, total_count: i64, start_indices: []i64, out_of_bounds_indices: []i64) {
	driver_verify_indexed_range_iterators(ctx, moment_idx, array_key, linked_key, total_count, start_indices, out_of_bounds_indices)
}

then_sorted_map_range_iterators_start_at :: proc(ctx: ^Suite_Ctx, moment_idx: i64, map_key: string, lower_bound_key: string, expected_first_key: string, start_index: i64, expected_index_key: string) {
	driver_verify_sorted_map_range_iterators(ctx, moment_idx, map_key, lower_bound_key, expected_first_key, start_index, expected_index_key)
}

then_compacted_cycles_preserve_slot_identity :: proc(ctx: ^Suite_Ctx, moment_idx: i64) {
	driver_assert_compacted_cycles_preserve_identity(ctx, moment_idx)
}

then_top_level_hash_map_and_linked_list_roots_succeed :: proc(ctx: ^Suite_Ctx) {
	driver_verify_top_level_hash_map_and_linked_list(ctx)
}

then_custom_64bit_hasher_resolves_deep_collisions :: proc(ctx: ^Suite_Ctx, h1, h2, h3: [8]u8, v1, v2, v3: u64) {
	driver_verify_custom_64bit_hasher_collisions(ctx, h1, h2, h3, v1, v2, v3)
}

then_sorted_map_enforces_dedup_and_write_guards :: proc(ctx: ^Suite_Ctx, key1, key2: string, initial_v1, updated_v1, v2: u64) {
	driver_verify_sorted_map_write_guards_and_dedup(ctx, key1, key2, initial_v1, updated_v1, v2)
}

given_users_with_secondary_username_index :: proc(ctx: ^Suite_Ctx, users: []User_Seed) {
	driver_seed_users_with_secondary_index(ctx, users)
}

upon_appending_uncommitted_trailing_garbage :: proc(ctx: ^Suite_Ctx, garbage_bytes: []u8) {
	driver_append_trailing_garbage(ctx, garbage_bytes)
}

then_reopening_ignores_trailing_garbage_and_next_write_truncates_it :: proc(ctx: ^Suite_Ctx, committed_before_garbage: i64, garbage_len: i64, next_key: string, next_val: string) {
	driver_verify_reopen_with_trailing_garbage_and_truncate_on_write(ctx, committed_before_garbage, garbage_len, next_key, next_val)
}

then_cloning_collections_isolates_with_cursor_freeze :: proc(ctx: ^Suite_Ctx, initial_fruits: []string, initial_cities: []string, extra_unfrozen_city: string, extra_frozen_cities: []string) {
	driver_verify_collection_cloning_and_cursor_freeze(ctx, initial_fruits, initial_cities, extra_unfrozen_city, extra_frozen_cities)
}

then_paginated_username_page_equals :: proc(ctx: ^Suite_Ctx, moment_idx: i64, page_size: i64, page_index: i64, expected_usernames: []string) {
	actual := driver_query_paginated_usernames(ctx, moment_idx, page_size, page_index)
	driver_assert_string_slice(ctx.t, actual, expected_usernames)
}

then_username_prefix_autocomplete_equals :: proc(ctx: ^Suite_Ctx, moment_idx: i64, prefix: string, expected_usernames: []string) {
	actual := driver_query_prefix_usernames(ctx, moment_idx, prefix)
	driver_assert_string_slice(ctx.t, actual, expected_usernames)
}

then_replication_from_diverged_primary_requires_full_resync :: proc(primary: ^Suite_Ctx, replica_holder: ^Suite_Ctx, expect_delta_rejection: bool = false) {
	driver_verify_replication_divergence(primary, replica_holder, expect_delta_rejection)
}

then_hamt_splits_on_prefix_conflicts_and_shortens_on_removal :: proc(ctx: ^Suite_Ctx, base_key: string, conflict_2byte_key: string, conflict_4byte_key: string) {
	driver_verify_hamt_branch_splitting_and_shortening(ctx, base_key, conflict_2byte_key, conflict_4byte_key)
}

then_inline_and_external_byte_slots_match_thresholds :: proc(ctx: ^Suite_Ctx, checks: []Inline_Bytes_Check) {
	driver_verify_inline_short_bytes_and_tagged_thresholds(ctx, checks)
}

then_radix_trie_handles_root_overflow_slice_and_sparse_none_slots :: proc(ctx: ^Suite_Ctx, total_items: int, slice_down_to: i64, sparse_nil_index: i64) {
	driver_verify_radix_trie_root_overflow_and_sparse_none_slots(ctx, total_items, slice_down_to, sparse_nil_index)
}

then_btree_linked_list_preserves_order_across_concat_slice_insert_remove :: proc(ctx: ^Suite_Ctx, item_count: int, slice_offset: i64, slice_size: i64, insert_idx: i64, inserted_val: string, remove_idx: i64) {
	driver_verify_btree_linked_list_structural_operations(ctx, item_count, slice_offset, slice_size, insert_idx, inserted_val, remove_idx)
}

then_bytes_keyed_collections_preserve_keys_hashes_and_counts :: proc(ctx: ^Suite_Ctx, raw_key_a: []u8, raw_key_b: []u8, val_a: string, val_b: string) {
	driver_verify_bytes_keyed_collections_and_kv_inspection(ctx, raw_key_a, raw_key_b, val_a, val_b)
}

then_reopened_compacted_file_supports_interleaved_multi_handle_reads :: proc(ctx: ^Suite_Ctx, moment_idx: i64, key1: string, expected1: string, key2: string, expected2: string) {
	driver_verify_reopen_compacted_file_and_interleaved_readers(ctx, moment_idx, key1, expected1, key2, expected2)
}

then_post_compaction_replica_resync_converges_and_resumes_delta_sync :: proc(ctx: ^Suite_Ctx) {
	driver_verify_post_compaction_replica_resync(ctx)
}

then_multi_tier_btrees_support_in_place_updates_and_cursor_freeze_isolation :: proc(ctx: ^Suite_Ctx, item_count: int) {
	driver_verify_multi_tier_btree_in_place_and_cursor_freeze_isolation(ctx, item_count)
}

then_sorted_set_maintains_order_across_multi_tier_splits_merges_and_range_iterators :: proc(ctx: ^Suite_Ctx, total_members: int, remove_count: int) {
	driver_verify_sorted_set_multi_tier_lifecycle(ctx, total_members, remove_count)
}

then_linked_array_list_handles_empty_slice_and_range_error_guards :: proc(ctx: ^Suite_Ctx, initial_count: int) {
	driver_verify_linked_array_list_edge_boundaries(ctx, initial_count)
}

then_sorted_set_stores_key_only_leaf_entries_and_reinterprets_with_sorted_map :: proc(ctx: ^Suite_Ctx) {
	driver_verify_sorted_set_key_only_entries_and_map_reinterpretation(ctx)
}

then_linked_array_list_append_context_nests_collections :: proc(ctx: ^Suite_Ctx) {
	driver_verify_linked_array_list_append_context(ctx)
}

then_cursor_reader_survives_buffer_reallocation_window_shift_and_truncation :: proc(ctx: ^Suite_Ctx) {
	driver_verify_cursor_reader_reallocation_window_shift_and_truncation(ctx)
}

then_buffered_file_multi_handle_alternating_commits_preserve_all_moments :: proc(ctx: ^Suite_Ctx, commit_values: []string) {
	driver_verify_buffered_file_multi_handle_alternating_commits(ctx, commit_values)
}

then_corrupt_slot_tags_inflated_branch_counts_and_truncated_btree_nodes_are_rejected :: proc(ctx: ^Suite_Ctx) {
	driver_verify_fast_path_corruption_and_truncation_guards(ctx)
}

then_compactor_and_buffered_file_enforce_max_size_and_allocation_failure_guards :: proc(ctx: ^Suite_Ctx) {
	driver_verify_compactor_and_buffered_file_max_size_and_allocation_guards(ctx)
}

upon_populating_concurrent_read_fixture :: proc(ctx: ^Suite_Ctx, item_count: int) {
	driver_populate_concurrent_read_fixture(ctx, item_count)
	// Cross-cutting invariant: verify all 4 collection kinds in Moment 0 have the exact seeded count
	then_moment_has_counted_map_size(ctx, 0, "hm", i64(item_count))
	then_moment_has_sorted_map_in_order(ctx, 0, "sm", expected_count = i64(item_count))
}

then_concurrent_readers_and_resumable_cursors_succeed_without_interference :: proc(
	ctx: ^Suite_Ctx,
	worker_count: int,
	item_count: int,
	pause_at_key: string,
	expected_remaining_keys: int,
	pause_at_index: i64,
	expected_remaining_items: int,
	sentinel_pos: i64 = 777777,
) {
	// Cross-cutting invariant: set a known seek position on the underlying Core before spawning
	// concurrent reader threads, and verify that stateless `core_read_at` calls never mutate `pos`.
	driver_set_core_sentinel_pos(ctx, sentinel_pos)
	driver_verify_concurrent_readers_and_resumable_cursors(
		ctx,
		worker_count,
		item_count,
		pause_at_key,
		expected_remaining_keys,
		pause_at_index,
		expected_remaining_items,
	)
	driver_assert_core_sentinel_pos_unchanged(ctx, sentinel_pos)
}

then_virtual_memory_base_pointer_remains_stable_during_concurrent_writer_appends :: proc(
	ctx: ^Suite_Ctx,
	reader_count: int,
	append_moments: int,
	item_count: int,
) {
	driver_record_vmem_base_pointer(ctx)
	driver_verify_vmem_base_pointer_stability_under_concurrent_appends(ctx, reader_count, append_moments, item_count)
	driver_assert_vmem_base_pointer_unchanged(ctx)
	then_history_has_moments(ctx, i64(1 + append_moments))
}

then_concurrent_compaction_and_replication_succeed_during_parallel_reads :: proc(
	ctx: ^Suite_Ctx,
	reader_count: int,
	item_count: int,
	sentinel_pos: i64 = 888888,
) {
	driver_Verify_Compaction_And_Replication_With_Sentinel :: proc(ctx: ^Suite_Ctx, reader_count: int, item_count: int, sentinel_pos: i64) {
		driver_verify_concurrent_compaction_and_replication_with_readers(ctx, reader_count, item_count)
		driver_set_core_sentinel_pos(ctx, sentinel_pos)
		then_history_has_moments(ctx, 2)
		driver_assert_core_sentinel_pos_unchanged(ctx, sentinel_pos)
	}
	driver_Verify_Compaction_And_Replication_With_Sentinel(ctx, reader_count, item_count, sentinel_pos)
}

upon_transacting_dsl_script :: proc(ctx: ^Suite_Ctx, script: string) {
	driver_transact_dsl_script(ctx, script)
}

then_concurrent_dsl_workers_observe_consistent_snapshots :: proc(
	ctx: ^Suite_Ctx,
	worker_count: int,
	expect: DSL_Concurrent_Expectations,
	sentinel_pos: i64 = 999999,
) {
	driver_set_core_sentinel_pos(ctx, sentinel_pos)
	driver_verify_concurrent_dsl_queries(ctx, worker_count, expect)
	driver_assert_core_sentinel_pos_unchanged(ctx, sentinel_pos)
}

given_virtual_memory_core_with_reservation :: proc(ctx: ^Suite_Ctx, reserve_bytes: int) {
	driver_init_vmem_core_with_reservation(ctx, reserve_bytes)
}

upon_writing_shrinking_and_regrowing_virtual_memory_core :: proc(
	ctx: ^Suite_Ctx,
	initial_write_bytes: int,
	shrink_to_bytes: i64,
	regrow_write_bytes: int,
) {
	driver_write_shrink_and_regrow_vmem_core(ctx, initial_write_bytes, shrink_to_bytes, regrow_write_bytes)
}

then_virtual_memory_enforces_reservation_cap_and_clones_from_bytes :: proc(
	ctx: ^Suite_Ctx,
	expected_length: int,
	expected_overflow_err: xitdb.Xitdb_Error,
) {
	driver_assert_vmem_write_overflow_and_init_from_bytes(ctx, expected_length, expected_overflow_err)
	driver_assert_vmem_base_pointer_unchanged(ctx)
}

then_sorted_map_reverse_from_key_equals :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	map_key: string,
	upper_bound: string,
	inclusive: bool,
	expected_keys: []string,
	limit: int = 0,
) {
	actual := driver_query_sorted_map_keys_reverse_from_key(ctx, moment_idx, map_key, upper_bound, inclusive, limit)
	driver_assert_string_slice(ctx.t, actual, expected_keys)
}

then_sorted_set_reverse_from_key_equals :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	set_key: string,
	upper_bound: string,
	inclusive: bool,
	expected_members: []string,
	limit: int = 0,
) {
	actual := driver_query_sorted_set_reverse_from_key(ctx, moment_idx, set_key, upper_bound, inclusive, limit)
	driver_assert_string_slice(ctx.t, actual, expected_members)
}

then_sorted_map_reverse_from_index_equals :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	map_key: string,
	start_idx: i64,
	expected_keys: []string,
	limit: int = 0,
) {
	actual := driver_query_sorted_map_keys_reverse_from_index(ctx, moment_idx, map_key, start_idx, limit)
	driver_assert_string_slice(ctx.t, actual, expected_keys)
}

then_array_list_reverse_from_index_equals :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	list_key: string,
	start_idx: i64,
	expected_items: []string,
	limit: int = 0,
) {
	actual := driver_query_array_list_reverse_from_index(ctx, moment_idx, list_key, start_idx, limit)
	driver_assert_string_slice(ctx.t, actual, expected_items)
}

then_linked_list_reverse_from_index_equals :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	list_key: string,
	start_idx: i64,
	expected_items: []string,
	limit: int = 0,
) {
	actual := driver_query_linked_list_reverse_from_index(ctx, moment_idx, list_key, start_idx, limit)
	driver_assert_string_slice(ctx.t, actual, expected_items)
}

then_hamt_reverse_iterators_mirror_forward_order :: proc(
	ctx: ^Suite_Ctx,
	moment_idx: i64,
	map_key: string,
	set_key: string,
	expected_count: int,
) {
	driver_assert_hamt_reverse_matches_forward(ctx, moment_idx, map_key, set_key, expected_count)
}

// ----------------------------------------------------------------------------
// Lua 5.4 Domain Steps
// ----------------------------------------------------------------------------

upon_executing_lua_script :: proc(ctx: ^Suite_Ctx, script: string) {
	driver_exec_lua(ctx, script)
}

upon_compiling_and_storing_lua_bytecode :: proc(
	ctx: ^Suite_Ctx,
	base_moment: i64,
	key: string,
	lua_src: string,
	strip_debug: bool = false,
) {
	driver_compile_and_store_lua_bytecode(ctx, base_moment, key, lua_src, strip_debug)
}

upon_executing_stored_lua_bytecode :: proc(ctx: ^Suite_Ctx, selector: string) {
	driver_load_and_exec_stored_lua_bytecode(ctx, selector)
}

then_lua_assertion_passes :: proc(ctx: ^Suite_Ctx, script: string) {
	driver_exec_lua(ctx, script)
}







