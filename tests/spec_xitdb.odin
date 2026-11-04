package xitdb_tests

import "core:fmt"
import "core:math/rand"
import "core:slice"
import "core:testing"
import xitdb "../xitdb"

// ============================================================================
// Layer 1: Executable Specifications (`spec_xitdb.odin`)
// ============================================================================
// Written in the language of the problem domain (historical moments, persistent
// structural sharing, lexicographical indexing, incremental log replication,
// compaction, and atomic transaction rollback).
//
// Zero raw byte offsets, slot pointers, cursor mechanics, or I/O handles appear
// in Layer 1 scenario specs; all technical mechanics live in Layer 3 (`driver_xitdb.odin`).

// ----------------------------------------------------------------------------
// Scenario 1: Wire Compatibility with Upstream Reference `test.db` Fixture
// ----------------------------------------------------------------------------

@(test)
spec_reference_database_wire_compatibility :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN the upstream v1 reference database fixture `test.db`
	given_reference_database_fixture(&ctx, "tests/testdata/test.db")

	// THEN the database history contains 2 immutable moments
	then_history_has_moments(&ctx, 2)

	// AND Moment 0 preserves all initial scalars, lists, linked lists, maps, and sets
	then_moment_has_string(&ctx, 0, "foo", "foo")
	then_moment_stores_inline_short_bytes(&ctx, 0, "foo")
	then_moment_has_array_list(&ctx, 0, "fruits", []string{"apple", "pear", "grape"})
	then_moment_has_nested_record_uint(&ctx, 0, "people", 0, "age", 25)
	then_moment_has_nested_record_uint(&ctx, 0, "people", 1, "age", 42)
	then_moment_has_linked_list(&ctx, 0, "todos", []string{"Pay the bills", "Wash the car", "Get an oil change"})
	then_moment_has_counted_map_size(&ctx, 0, "letters-counted-map", 2)
	then_moment_has_set_members(&ctx, 0, "letters-set", []string{"a", "c"})
	then_moment_has_counted_set(&ctx, 0, "letters-counted-set", 2, []string{"a", "c"})

	// AND Moment 1 reflects structural mutations while leaving Moment 0 intact
	then_moment_lacks_key(&ctx, 1, "bar")
	then_moment_has_array_list(&ctx, 1, "fruits", []string{"lemon", "pear"})
	then_moment_has_linked_list(&ctx, 1, "todos", []string{"Wash the car"})
}

// ----------------------------------------------------------------------------
// Scenario 2: Branching Moments, Persistent Structural Sharing & Rich Types
// ----------------------------------------------------------------------------

@(test)
spec_branching_moments_preserve_historical_immutability :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a SHA-256 database with an initial Moment 0 containing scalars, tagged documents, and collections
	given_in_memory_database(&ctx, hash_algo = "sha2")
	given_committed_moment(
		&ctx,
		Op_Put_String{key = "foo", val = "foo"},
		Op_Put_String{key = "bar", val = "bar"},
		Op_Put_Int{key = "int_val", val = -42},
		Op_Put_Uint{key = "uint_val", val = 999},
		Op_Put_Float{key = "float_val", val = 3.14159},
		Op_Put_Tagged{key = "tagged_short", val = "hello", format_tag = "js"},
		Op_Put_Tagged{key = "tagged_long", val = "hello world long string > 8 bytes", format_tag = "te"},
		Op_Stream_Tagged{key = "streamed", chunks = []string{"chunk1-", "chunk2"}, format_tag = "md"},
		Op_Put_Array_List{key = "fruits", items = []string{"apple", "pear", "grape"}},
		Op_Put_Linked_List{key = "todos", items = []string{"Pay the bills", "Buy milk"}},
		Op_Insert_Linked_List{key = "todos", index = 1, val = "Wash the car"},
		Op_Put_Counted_Map{key = "counted_map", entries = []Key_Uint{{"a", 1}, {"b", 2}}},
		Op_Put_Counted_Set{key = "counted_set", members = []string{"x", "y"}},
	)

	// UPON branching Moment 1 from Moment 0 and mutating keys, lists, and linked lists
	upon_branching_moment(
		&ctx,
		from_moment = 0,
		ops = {
			Op_Remove_Key{key = "bar"},
			Op_Update_Array_List_Item{key = "fruits", index = 0, val = "lemon"},
			Op_Slice_Array_List{key = "fruits", size = 2},
			Op_Remove_Linked_List{key = "todos", index = 0},
			Op_Slice_Linked_List{key = "todos", offset = 0, size = 1},
		},
	)

	// THEN Moment 0 remains completely untouched (immutable historical snapshot)
	then_moment_has_string(&ctx, 0, "bar", "bar")
	then_moment_has_scalars(
		&ctx,
		0,
		Key_Int{"int_val", -42},
		Key_Uint{"uint_val", 999},
		Key_Float{"float_val", 3.14159},
	)
	then_moment_has_tagged_document(&ctx, 0, "tagged_short", "hello", "js")
	then_moment_has_tagged_document(&ctx, 0, "tagged_long", "hello world long string > 8 bytes", "te")
	then_moment_has_tagged_document(&ctx, 0, "streamed", "chunk1-chunk2", "md")
	then_moment_has_array_list(&ctx, 0, "fruits", []string{"apple", "pear", "grape"})
	then_moment_has_linked_list(&ctx, 0, "todos", []string{"Pay the bills", "Wash the car", "Buy milk"})
	then_moment_has_counted_map_size(&ctx, 0, "counted_map", 2)
	then_moment_has_counted_set(&ctx, 0, "counted_set", 2, []string{"x", "y"})

	// AND Moment 1 reflects all branched updates
	then_moment_lacks_key(&ctx, 1, "bar")
	then_moment_has_array_list(&ctx, 1, "fruits", []string{"lemon", "pear"})
	then_moment_has_linked_list(&ctx, 1, "todos", []string{"Wash the car"})
}

// ----------------------------------------------------------------------------
// Scenario 3: SortedMap & SortedSet B+Tree Splitting, Ranking & Rebalancing
// ----------------------------------------------------------------------------

@(test)
spec_sorted_catalog_maintains_lexicographical_ranks_across_splits_and_merges :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	catalog_entries := [?]Key_Uint{
		{"mango", 100}, {"apple", 101}, {"zebra", 102}, {"banana", 103},
		{"cherry", 104}, {"date", 105}, {"elderberry", 106}, {"fig", 107},
		{"grape", 108}, {"honeydew", 109}, {"kiwi", 110}, {"lemon", 111},
		{"nectarine", 112}, {"orange", 113}, {"papaya", 114}, {"quince", 115},
		{"raspberry", 116}, {"strawberry", 117}, {"tangerine", 118}, {"ugli", 119},
		{"vanilla", 120}, {"watermelon", 121}, {"xigua", 122}, {"yam", 123},
		{"apricot", 124}, {"blackberry", 125}, {"blueberry", 126}, {"cantaloupe", 127},
		{"clementine", 128}, {"coconut", 129}, {"cranberry", 130}, {"currant", 131},
		{"dragonfruit", 132}, {"guava", 133}, {"jackfruit", 134}, {"kumquat", 135},
		{"lime", 136}, {"lychee", 137}, {"mulberry", 138}, {"olive", 139},
	}

	// GIVEN a database with 40 out-of-order fruit keys in a SortedMap
	given_in_memory_database(&ctx, hash_algo = "sha1")
	given_committed_moment(&ctx, Op_Put_Sorted_Map{key = "catalog", entries = catalog_entries[:]})

	// THEN Moment 0 indexes all 40 entries in strict lexicographical order with accurate ranks
	then_moment_has_sorted_map_in_order(
		&ctx,
		0,
		"catalog",
		expected_count = 40,
		sample_ranks = []Key_Int{{"apple", 0}, {"apricot", 1}, {"banana", 2}, {"zebra", 39}},
	)

	// UPON branching Moment 1 and removing 20 keys to trigger B+Tree node rebalancing & merges
	keys_to_remove := [?]string{
		"mango", "apple", "zebra", "banana", "cherry", "date", "elderberry", "fig",
		"grape", "honeydew", "kiwi", "lemon", "nectarine", "orange", "papaya", "quince",
		"raspberry", "strawberry", "tangerine", "ugli",
	}
	upon_branching_moment(&ctx, 0, Op_Remove_Sorted_Map{key = "catalog", keys_to_drop = keys_to_remove[:]})

	// THEN Moment 1 retains the 20 remaining entries in strict ascending order with updated ranks
	then_moment_has_sorted_map_in_order(
		&ctx,
		1,
		"catalog",
		expected_count = 20,
		sample_ranks = []Key_Int{{"apricot", 0}, {"blackberry", 1}, {"yam", 19}},
	)
}

// ----------------------------------------------------------------------------
// Scenario 4: Incremental Log Replication & History Compaction
// ----------------------------------------------------------------------------

@(test)
spec_incremental_replication_and_garbage_collecting_compaction :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a primary database with 5 committed moments
	given_in_memory_database(&ctx, hash_algo = "sha1")
	given_committed_moments_count(
		&ctx,
		5,
		Op_Put_String{key = "foo", val = "foo"},
		Op_Put_Array_List{key = "fruits", items = []string{"apple", "pear", "grape"}},
	)

	// UPON replicating the primary database to a fresh secondary replica
	upon_replicating_to_secondary(&ctx)

	// THEN the initial sync streams from genesis (offset 0) and replicates all 5 moments
	then_last_sync_started_at_genesis(&ctx)
	then_history_has_moments(&ctx, 5, on = .Replica)

	// UPON committing a 6th moment on the primary and syncing again
	given_committed_moment(&ctx, Op_Put_String{key = "foo", val = "updated-in-m6"})
	upon_replicating_to_secondary(&ctx)

	// THEN only the delta commit bytes are shipped (start_offset > 0) and the replica has 6 moments
	then_last_sync_was_incremental(&ctx)
	then_history_has_moments(&ctx, 6, on = .Replica)
	then_moment_has_string(&ctx, 5, "foo", "updated-in-m6", on = .Replica)

	// UPON pruning history to 1 moment and compacting the database
	upon_retaining_latest_moments(&ctx, 1)
	upon_compacting_database(&ctx)

	// THEN the compacted database has a smaller byte footprint while preserving the retained moment
	then_compacted_footprint_is_smaller(&ctx)
	then_history_has_moments(&ctx, 1, on = .Compacted)
	then_moment_has_string(&ctx, 0, "foo", "foo", on = .Compacted)
	then_moment_has_array_list(&ctx, 0, "fruits", []string{"apple", "pear", "grape"}, on = .Compacted)
}

// ----------------------------------------------------------------------------
// Scenario 5: Buffered File Backend, Atomic Rollback & Disk-Backed Compaction
// ----------------------------------------------------------------------------

@(test)
spec_buffered_file_atomic_rollback_and_file_offset_map_compaction :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a buffered-file database (512-byte buffer) with 1 committed moment
	given_buffered_file_database(&ctx, hash_algo = "sha1", buffer_bytes = 512)
	given_committed_moment(&ctx, Op_Put_String{key = "k1", val = "v1"})
	committed_size_after_m0 := driver_committed_size(&ctx)

	// UPON attempting a second moment transaction that aborts mid-flight with Write_Failed
	upon_attempting_moment_that_aborts(
		&ctx,
		Op_Put_String{key = "k2", val = "uncommitted-dirty-data"},
		Op_Fail_With{err = .Write_Failed},
	)

	// THEN the database truncates uncommitted bytes back to the prior committed watermark
	then_aborted_transaction_leaves_committed_size_unchanged(&ctx, .Write_Failed, committed_size_after_m0)
	then_history_has_moments(&ctx, 1)
	then_moment_has_string(&ctx, 0, "k1", "v1")
	then_moment_lacks_key(&ctx, 0, "k2")

	// UPON compacting the buffered-file database using a disk-backed File_Offset_Map
	upon_compacting_database(&ctx, use_file_offset_map = true)

	// THEN the compacted file database preserves the committed moment intact
	then_history_has_moments(&ctx, 1, on = .Compacted)
	then_moment_has_string(&ctx, 0, "k1", "v1", on = .Compacted)
}

// ============================================================================
// Pattern D & E: Property-Based Invariants & Cryptographic Primitives
// ============================================================================

@(test)
spec_property_sorted_map_and_linked_list_invariants :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// Property: For any pseudo-random permutation of 64 keys inserted into Sorted_Map
	// and Linked_Array_List, `sorted_map_rank(k)` == index in sorted order, and
	// `Linked_Array_List` preserves exact insertion order.
	entries: [64]Key_Uint
	items: [64]string
	expected_sorted: [64]string

	for i in 0 ..< 64 {
		perm := (i * 37 + 13) % 64
		k := fmt.tprintf("key-%03d", perm)
		entries[i] = Key_Uint{key = k, val = u64(perm)}
		items[i] = k
		expected_sorted[i] = k
	}

	given_committed_moment(
		&ctx,
		Op_Put_Sorted_Map{key = "sorted", entries = entries[:]},
		Op_Put_Linked_List{key = "linked", items = items[:]},
		Op_Put_Linked_List{key = "extra_linked", items = []string{"tail-0", "tail-1"}},
		Op_Concat_Linked_List{target_key = "linked", source_key = "extra_linked"},
		Op_Put_Sorted_Set{key = "tags", members = []string{"zig", "odin", "go", "clojure"}},
	)

	slice.sort(expected_sorted[:])
	sample_ranks: [64]Key_Int
	for k, rank in expected_sorted {
		sample_ranks[rank] = Key_Int{key = k, val = i64(rank)}
	}

	expected_concat: [66]string
	copy(expected_concat[:64], items[:])
	expected_concat[64] = "tail-0"
	expected_concat[65] = "tail-1"

	then_moment_has_sorted_map_in_order(&ctx, 0, "sorted", 64, sample_ranks[:])
	then_moment_has_linked_list(&ctx, 0, "linked", expected_concat[:])
	then_moment_has_sorted_set_in_order(&ctx, 0, "tags", []string{"clojure", "go", "odin", "zig"})
}

@(test)
unit_cryptographic_hash_vectors_and_trailer_crc64 :: proc(t: ^testing.T) {
	// RFC 3174 / FIPS 180-4 test vectors for "abc"
	abc := transmute([]u8)string("abc")

	sha1_digest := xitdb.sha1_sum(abc)
	expected_sha1 := [20]u8{
		0xa9, 0x99, 0x3e, 0x36, 0x47, 0x06, 0x81, 0x6a, 0xba, 0x3e,
		0x25, 0x71, 0x78, 0x50, 0xc2, 0x6c, 0x9c, 0xd0, 0xd8, 0x9d,
	}
	testing.expect(t, sha1_digest == expected_sha1, "SHA-1('abc') mismatch")

	sha256_digest := xitdb.sha256_sum(abc)
	expected_sha256 := [32]u8{
		0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
		0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
		0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
		0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
	}
	testing.expect(t, sha256_digest == expected_sha256, "SHA-256('abc') mismatch")

	// Empty string vector
	empty_sha1 := xitdb.sha1_sum(nil)
	expected_empty_sha1 := [20]u8{
		0xda, 0x39, 0xa3, 0xee, 0x5e, 0x6b, 0x4b, 0x0d, 0x32, 0x55,
		0xbf, 0xef, 0x95, 0x60, 0x18, 0x90, 0xaf, 0xd8, 0x07, 0x09,
	}
	testing.expect(t, empty_sha1 == expected_empty_sha1, "SHA-1('') mismatch")

	// Root trailer checksum (CRC-64/XZ) deterministic check
	trailer := xitdb.new_root_trailer(0, 37, xitdb.Slot{value = 100, tag = .Array_List}, 1)
	testing.expect(t, trailer.checksum != 0, "Expected non-zero root trailer checksum")
}

// ----------------------------------------------------------------------------
// Scenario 6: Frozen Cursors, Frozen Streams & Survival Across Rollback
// ----------------------------------------------------------------------------

@(test)
spec_frozen_writers_reject_in_place_mutation_and_survive_transaction_rollback :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN an in-memory database
	given_in_memory_database(&ctx)

	// THEN freezing mid-transaction protects pre-freeze slots (.Frozen_Slot) and
	// streaming bytes (.Frozen_Bytes) while preserving frozen data even when the
	// subsequent transaction step aborts
	then_frozen_cursors_and_streams_reject_writes_and_survive_rollback(
		&ctx,
		initial_val = 10,
		post_freeze_val = 30,
		stream_len = 16,
	)
}

// ----------------------------------------------------------------------------
// Scenario 7: Expired Transaction & Nested Top-Level Write Guards
// ----------------------------------------------------------------------------

@(test)
spec_expired_cursors_and_nested_root_transactions_are_rejected :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN an in-memory database
	given_in_memory_database(&ctx)

	// THEN top-level writes inside an active root transaction return .Nested_Top_Level_Write
	// and write cursors/writers used after transaction completion return .Expired_Transaction
	then_nested_and_expired_transactions_are_rejected(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 8: Deep Multi-Tier Range Iteration (`iterator_from`)
// ----------------------------------------------------------------------------

@(test)
spec_deep_radix_trie_and_btree_range_iterators :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN 200 items in both an Array_List (multi-tier 16-way radix trie) and a Linked_Array_List (multi-tier B-Tree)
	items: [200]string
	for i in 0 ..< 200 {
		items[i] = fmt.tprintf("item-%03d", i)
	}
	given_committed_moment(
		&ctx,
		Op_Put_Array_List{key = "array", items = items[:]},
		Op_Put_Linked_List{key = "linked", items = items[:]},
	)

	// THEN `iterator_from` yields exact suffixes for positive and negative start indices,
	// and yields empty iterators for out-of-bounds indices
	valid_starts := [?]i64{0, 1, 15, 16, 17, 100, 198, 199, -1, -2, -16, -100, -200}
	oob_starts := [?]i64{200, 201, 1000, -201, -1000}
	then_indexed_range_iterators_match_expected_slices(
		&ctx,
		0,
		"array",
		"linked",
		200,
		valid_starts[:],
		oob_starts[:],
	)
}

// ----------------------------------------------------------------------------
// Scenario 9: Sorted_Map Lower-Bound Key & Negative Index Range Iteration
// ----------------------------------------------------------------------------

@(test)
spec_sorted_map_lower_bound_and_negative_index_iterators :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN 60 keys "k0000".."k0059" inserted in reverse order
	entries: [60]Key_Uint
	for i in 0 ..< 60 {
		rev := 59 - i
		entries[i] = Key_Uint{
			key = fmt.tprintf("k%04d", rev),
			val = u64(rev),
		}
	}
	given_committed_moment(&ctx, Op_Put_Sorted_Map{key = "sorted", entries = entries[:]})

	// THEN lower-bound iteration on present key "k0030" starts at "k0030",
	// and negative index -1 starts at "k0059"
	then_sorted_map_range_iterators_start_at(&ctx, 0, "sorted", "k0030", "k0030", -1, "k0059")

	// AND lower-bound iteration on absent key "k00095" (between k0009 and k0010) starts at "k0010",
	// and negative index -60 starts at "k0000"
	then_sorted_map_range_iterators_start_at(&ctx, 0, "sorted", "k00095", "k0010", -60, "k0000")
}

// ----------------------------------------------------------------------------
// Scenario 10: Replication Divergence Detection & Full Re-Sync
// ----------------------------------------------------------------------------

@(test)
spec_replication_detects_diverged_file_id_and_commit_history :: proc(t: ^testing.T) {
	primary_a := driver_init_ctx(t)
	defer driver_destroy_ctx(&primary_a)

	primary_b := driver_init_ctx(t)
	defer driver_destroy_ctx(&primary_b)

	// GIVEN Primary A (file_id = 1) replicated to Secondary, and an unrelated Primary B (file_id = 2)
	given_in_memory_database_with_file_id(&primary_a, file_id = 1)
	upon_writing_root_uint(&primary_a, 1)
	upon_replicating_to_secondary(&primary_a)
	then_root_has_uint(&primary_a, 1, on = .Replica)

	given_in_memory_database_with_file_id(&primary_b, file_id = 2)
	upon_writing_root_uint(&primary_b, 1)
	upon_writing_root_uint(&primary_b, 2)

	// THEN Primary B requires full replacement from offset 0 (file_id differs)
	// AND attempting to force-append Primary B's delta onto Primary A's replica is rejected with .Invalid_Database
	then_replication_from_diverged_primary_requires_full_resync(&primary_b, &primary_a, expect_delta_rejection = true)

	// AND two databases with the same file_id (3) and identical byte lengths but divergent commits
	// also trigger a full replacement from offset 0
	fork_1 := driver_init_ctx(t)
	defer driver_destroy_ctx(&fork_1)
	fork_2 := driver_init_ctx(t)
	defer driver_destroy_ctx(&fork_2)

	given_in_memory_database_with_file_id(&fork_1, file_id = 3)
	given_in_memory_database_with_file_id(&fork_2, file_id = 3)
	upon_writing_root_string(&fork_1, "aaaaaaaaaaaa")
	upon_writing_root_string(&fork_2, "bbbbbbbbbbbb")

	upon_replicating_to_secondary(&fork_1)
	then_replication_from_diverged_primary_requires_full_resync(&fork_2, &fork_1, expect_delta_rejection = false)
}

// ----------------------------------------------------------------------------
// Scenario 11: Compaction of Cyclic Structures, Empty DBs & Post-Compaction Writes
// ----------------------------------------------------------------------------

@(test)
spec_compaction_preserves_cyclic_graphs_and_supports_continued_writes :: proc(t: ^testing.T) {
	// 1. Empty database compaction produces an empty database
	{
		empty_ctx := driver_init_ctx(t)
		defer driver_destroy_ctx(&empty_ctx)

		given_in_memory_database(&empty_ctx)
		upon_compacting_database(&empty_ctx)
		then_root_is_empty(&empty_ctx, on = .Compacted)
	}

	// 2. Cyclic self-references and mutual map references survive compaction without infinite recursion
	{
		ctx := driver_init_ctx(t)
		defer driver_destroy_ctx(&ctx)

		given_in_memory_database(&ctx)
		given_committed_moment(&ctx, Op_Put_String{key = "greeting", val = "initial"})
		upon_committing_cyclic_moment(&ctx, base_moment = 0)
		upon_compacting_database(&ctx)

		then_history_has_moments(&ctx, 1, on = .Compacted)
		then_moment_has_string(&ctx, 0, "greeting", "initial", on = .Compacted)
		then_compacted_cycles_preserve_slot_identity(&ctx, 0)

		// 3. Continuing to write new moments onto the compacted database preserves history
		upon_branching_compacted_moment(&ctx, 0, Op_Put_String{key = "post_compact", val = "added-after-compact"})

		then_history_has_moments(&ctx, 2, on = .Compacted)
		then_moment_has_string(&ctx, 1, "greeting", "initial", on = .Compacted)
		then_moment_has_string(&ctx, 1, "post_compact", "added-after-compact", on = .Compacted)
	}
}

// ----------------------------------------------------------------------------
// Scenario 12: Non-ArrayList Top-Level Roots (HashMap, LinkedArrayList, Scalars)
// ----------------------------------------------------------------------------

@(test)
spec_non_array_list_top_level_roots_and_compaction :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// THEN top-level Hash_Map and Linked_Array_List roots support direct transactions,
	// expire nested cursors after top-level writes, and compact cleanly
	then_top_level_hash_map_and_linked_list_roots_succeed(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 13: Custom Hasher (64-bit / 8-byte Hash Collisions at Maximum Depth)
// ----------------------------------------------------------------------------

@(test)
spec_custom_64bit_hasher_handles_deep_nibble_prefix_collisions :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN two 8-byte hashes sharing 15 of 16 nibbles (differing only in the final nibble)
	h1 := [8]u8{0, 0, 0, 0, 0, 0, 0, 0x00}
	h2 := [8]u8{0, 0, 0, 0, 0, 0, 0, 0x10}
	h3 := [8]u8{0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff}

	// THEN the 16-way HAMT resolves all 16 levels of depth, stores all 3 keys, and removes h1 cleanly
	then_custom_64bit_hasher_resolves_deep_collisions(&ctx, h1, h2, h3, 100, 200, 300)
}

// ----------------------------------------------------------------------------
// Scenario 14: Wire Format Validation & Corrupt Header/Tag/Stream Guards
// ----------------------------------------------------------------------------

@(test)
unit_wire_format_validation_and_error_guards :: proc(t: ^testing.T) {
	// 1. Invalid magic number -> .Invalid_Database
	{
		bad_magic := xitdb.Header{
			magic_number = {'b', 'a', 'd'},
			version      = xitdb.VERSION,
			hash_size    = 20,
		}
		testing.expect_value(t, xitdb.header_validate(bad_magic), xitdb.Xitdb_Error.Invalid_Database)
	}

	// 2. Unsupported version -> .Invalid_Version
	{
		bad_ver := xitdb.Header{
			magic_number = xitdb.MAGIC_NUMBER,
			version      = 99,
			hash_size    = 20,
		}
		testing.expect_value(t, xitdb.header_validate(bad_ver), xitdb.Xitdb_Error.Invalid_Version)
	}

	// 3. Invalid slot tag byte -> .Unexpected_Tag
	{
		raw_slot := [xitdb.SLOT_LENGTH]u8{99, 0, 0, 0, 0, 0, 0, 0, 0}
		_, tag_err := xitdb.slot_from_bytes(raw_slot)
		testing.expect_value(t, tag_err, xitdb.Xitdb_Error.Unexpected_Tag)
	}

	// 4. Opening database with mismatched hasher size -> .Invalid_Hash_Size
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		_, err1 := xitdb.database_init(&core, xitdb.sha1_hasher())
		testing.expect_value(t, err1, nil)

		_, err2 := xitdb.database_init(&core, xitdb.sha256_hasher())
		testing.expect_value(t, err2, xitdb.Xitdb_Error.Invalid_Hash_Size)
	}

	// 5. Truncated database file -> .Truncated_Database
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		_ = xitdb.cursor_write(&rc, "some payload longer than 8 bytes")

		// Chop 5 bytes off the end of the underlying buffer
		cur_len, _ := xitdb.core_length(&core)
		_ = xitdb.core_set_length(&core, cur_len - 5)

		_, trunc_err := xitdb.database_committed_size(&db)
		testing.expect_value(t, trunc_err, xitdb.Xitdb_Error.Truncated_Database)
	}

	// 6. Reading bytes exceeding `max_size` -> .Stream_Too_Long
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		_ = xitdb.cursor_write(&rc, "a string that is 27 bytes!!")

		_, max_err := xitdb.cursor_read_bytes(rc.read_cursor, max_size = 5, allocator = context.temp_allocator)
		testing.expect_value(t, max_err, xitdb.Xitdb_Error.Stream_Too_Long)
		free_all(context.temp_allocator)
	}

	// 7. Compacting into a non-empty target database -> .Target_Not_Empty
	{
		src_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&src_core)
		src_db, _ := xitdb.database_init(&src_core, xitdb.sha1_hasher())
		src_rc := xitdb.database_root_cursor(&src_db)
		_ = xitdb.cursor_write(&src_rc, u64(1))

		dst_core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&dst_core)
		dst_db, _ := xitdb.database_init(&dst_core, xitdb.sha1_hasher())
		dst_rc := xitdb.database_root_cursor(&dst_db)
		_ = xitdb.cursor_write(&dst_rc, u64(2))

		_, comp_err := xitdb.database_compact(&src_db, &dst_core)
		testing.expect_value(t, comp_err, xitdb.Xitdb_Error.Target_Not_Empty)
	}
}

// ----------------------------------------------------------------------------
// Scenario 15: Streaming Writer Random-Access Seek Overwrite & Core_Memory Clamping
// ----------------------------------------------------------------------------

@(test)
unit_streaming_writer_seek_overwrite_and_memory_truncation_clamping :: proc(t: ^testing.T) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// 1. Streaming writer seek + overwrite inside a transaction ("goodbye, world!" -> "goodbye, cruel world!")
	Writer_Seek_Ctx :: struct {
		db:          ^xitdb.Database,
		text_cursor: xitdb.Write_Cursor,
	}
	wctx := Writer_Seek_Ctx{db = &db}

	seek_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^Writer_Seek_Ctx)(user_data)
		hash := xitdb.database_digest_string(c.db, "text", context.temp_allocator)
		tc := xitdb.cursor_write_path(cursor, []xitdb.Path_Part{
			xitdb.Hash_Map_Init{counted = false, set = false},
			xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_Value{hash = hash}},
		}) or_return
		c.text_cursor = tc

		writer := xitdb.cursor_writer(&c.text_cursor) or_return
		_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("goodbye, world!"))
		xitdb.cursor_writer_seek_to(&writer, 9) or_return
		_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("cruel world!"))
		return xitdb.cursor_writer_finish(&writer)
	}

	tx_err := xitdb.database_run_context(&db, seek_cb, &wctx)
	testing.expect_value(t, tx_err, nil)

	reader, r_err := xitdb.cursor_reader(wctx.text_cursor.read_cursor)
	testing.expect_value(t, r_err, nil)
	all_bytes, ra_err := xitdb.cursor_reader_read_all(&reader, context.temp_allocator)
	testing.expect_value(t, ra_err, nil)
	testing.expect_value(t, string(all_bytes), "goodbye, cruel world!")

	// 2. Core_Memory set_length bounds checking and position clamping
	testing.expect_value(t, xitdb.core_set_length(&core, 0), nil)
	testing.expect_value(t, xitdb.core_write_all(&core, []u8{1, 2, 3, 4}), nil)
	testing.expect_value(t, xitdb.core_seek_to(&core, 1), nil)

	// Invalid lengths (> current length or negative) fail without disturbing position or buffer
	for invalid_len in ([]i64{5, -1, min(i64)}) {
		err := xitdb.core_set_length(&core, invalid_len)
		testing.expect(t, err != nil, "Expected invalid length to return an error")
		pos, _ := xitdb.core_position(&core)
		testing.expect_value(t, pos, i64(1))
	}

	// Truncating to 3 preserves position 1; seeking to 3 and truncating to 2 clamps position to 2
	testing.expect_value(t, xitdb.core_set_length(&core, 3), nil)
	pos1, _ := xitdb.core_position(&core)
	testing.expect_value(t, pos1, i64(1))

	testing.expect_value(t, xitdb.core_seek_to(&core, 3), nil)
	testing.expect_value(t, xitdb.core_set_length(&core, 2), nil)
	pos2, _ := xitdb.core_position(&core)
	testing.expect_value(t, pos2, i64(2))

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// Scenario 16: Sorted_Map Low-Level Write Guards & Key-Deduplication Invariants
// ----------------------------------------------------------------------------

@(test)
spec_sorted_map_immutability_guards_and_key_deduplication :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN an in-memory database
	given_in_memory_database(&ctx)

	// THEN Sorted_Map deduplicates re-inserted keys without incrementing count,
	// rejects positional writes (.Write_Not_Allowed), rejects direct key-slot
	// overwrites (.Cursor_Not_Writeable), and tags entries with .Sorted_KV_Pair
	then_sorted_map_enforces_dedup_and_write_guards(&ctx, "k0001", "k0002", 1, 999, 2)
}

// ----------------------------------------------------------------------------
// Scenario 17: Uncommitted Trailing Bytes (Simulated Crash) & Read-Only Open
// ----------------------------------------------------------------------------

@(test)
spec_unfinished_transaction_trailing_bytes_are_truncated_on_next_write :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a file-backed database with 1 committed moment
	given_file_database(&ctx, hash_algo = "sha1")
	given_committed_moment(&ctx, Op_Put_String{key = "foo", val = "bar"})
	committed_before := driver_committed_size(&ctx)

	// UPON appending 9 bytes of uncommitted trailing garbage (simulating an interrupted transaction)
	upon_appending_uncommitted_trailing_garbage(&ctx, transmute([]u8)string("extrajunk"))

	// THEN re-opening the database (including read-only handles) succeeds without error,
	// and the very next write transaction automatically truncates the trailing garbage first
	then_reopening_ignores_trailing_garbage_and_next_write_truncates_it(&ctx, committed_before, 9, "next_k", "next_v")
	then_history_has_moments(&ctx, 2)
	then_moment_has_string(&ctx, 0, "foo", "bar")
	then_moment_has_string(&ctx, 1, "foo", "bar")
	then_moment_has_string(&ctx, 1, "next_k", "next_v")
}

// ----------------------------------------------------------------------------
// Scenario 18: Collection Cloning & `cursor_freeze` Copy-on-Write Isolation
// ----------------------------------------------------------------------------

@(test)
spec_cloning_collections_and_cursor_freeze_copy_on_write_isolation :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN initial `fruits` in Moment 0 and intra-transaction cloned lists in Moment 1
	then_cloning_collections_isolates_with_cursor_freeze(
		&ctx,
		initial_fruits = []string{"apple", "pear", "grape"},
		initial_cities = []string{"NYC", "LA"},
		extra_unfrozen_city = "Chicago",
		extra_frozen_cities = []string{"Charleston", "Louisville"},
	)

	// THEN cross-moment clone `food` grew to 5 items while `fruits` remained 3 items
	then_moment_has_array_list(&ctx, 1, "fruits", []string{"apple", "pear", "grape"})
	then_moment_has_array_list(&ctx, 1, "food", []string{"apple", "pear", "grape", "eggs", "rice"})

	// AND intra-transaction clone WITHOUT `cursor_freeze` mutated both `shared_orig` and `shared_clone`
	then_moment_has_array_list(&ctx, 1, "shared_orig", []string{"NYC", "LA", "Chicago"})
	then_moment_has_array_list(&ctx, 1, "shared_clone", []string{"NYC", "LA", "Chicago"})

	// AND intra-transaction clone WITH `cursor_freeze` isolated `big-cities` (2 items) from `cities` (4 items)
	then_moment_has_array_list(&ctx, 1, "big-cities", []string{"NYC", "LA"})
	then_moment_has_array_list(&ctx, 1, "cities", []string{"NYC", "LA", "Charleston", "Louisville"})
}

// ----------------------------------------------------------------------------
// Scenario 19: Secondary Index Pagination & Prefix Autocomplete
// ----------------------------------------------------------------------------

@(test)
spec_secondary_index_pagination_and_prefix_autocomplete :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN 5 user records indexed in both a primary `users` Hash_Map (id -> user)
	// and a secondary `username->id` Sorted_Map (username -> id)
	given_users_with_secondary_username_index(
		&ctx,
		[]User_Seed{
			{id = "101", username = "dan"},
			{id = "102", username = "sarah"},
			{id = "103", username = "bob"},
			{id = "104", username = "dave"},
			{id = "105", username = "alice"},
		},
	)

	// THEN paginating 2 users per page via the secondary index yields alphabetical pages
	then_paginated_username_page_equals(&ctx, 0, page_size = 2, page_index = 0, expected_usernames = []string{"alice", "bob"})
	then_paginated_username_page_equals(&ctx, 0, page_size = 2, page_index = 1, expected_usernames = []string{"dan", "dave"})
	then_paginated_username_page_equals(&ctx, 0, page_size = 2, page_index = 2, expected_usernames = []string{"sarah"})
	then_paginated_username_page_equals(&ctx, 0, page_size = 2, page_index = 3, expected_usernames = []string{})

	// AND lower-bound prefix autocomplete on "da" yields ["dan", "dave"] and stops before "sarah"
	then_username_prefix_autocomplete_equals(&ctx, 0, prefix = "da", expected_usernames = []string{"dan", "dave"})
	then_username_prefix_autocomplete_equals(&ctx, 0, prefix = "sa", expected_usernames = []string{"sarah"})
	then_username_prefix_autocomplete_equals(&ctx, 0, prefix = "z", expected_usernames = []string{})
}

// ----------------------------------------------------------------------------
// Scenario 20: HAMT Multi-Byte Hash Prefix Collisions & Branch Shortening
// ----------------------------------------------------------------------------

@(test)
spec_hamt_hash_prefix_conflict_branching_and_branch_shortening :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// GIVEN keys whose SHA-1 digests collide with "foo" in the first 2 bytes ("58555")
	// and first 4 bytes ("11602875152")
	// THEN the HAMT root slot splits from .KV_Pair -> .Index on insertion, stays .Index
	// when the 2-byte collision is removed, shortens back to .KV_Pair when the 4-byte
	// collision is removed, and preserves the existing .KV_Pair if a nested collision split
	// fails midway (e.g. .Out_Of_Memory) and is caught inside a transaction
	then_hamt_splits_on_prefix_conflicts_and_shortens_on_removal(
		&ctx,
		base_key = "foo",
		conflict_2byte_key = "58555",
		conflict_4byte_key = "11602875152",
	)
}

// ----------------------------------------------------------------------------
// Scenario 21: Inline `Short_Bytes` vs Heap `Bytes` Thresholds & `write_if_empty`
// ----------------------------------------------------------------------------

@(test)
spec_inline_short_bytes_vs_external_bytes_and_tagged_thresholds :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// THEN untagged strings <= 8 bytes fit inline as .Short_Bytes (full = false),
	// untagged strings > 8 bytes spill to .Bytes (full = false),
	// 2-byte tagged strings <= 6 bytes fit inline as .Short_Bytes (full = true),
	// and 2-byte tagged strings > 6 bytes spill to .Bytes (full = true)
	then_inline_and_external_byte_slots_match_thresholds(
		&ctx,
		[]Inline_Bytes_Check{
			{key = "untagged_8", val = "shortstr", format_tag = "", expected_tag = .Short_Bytes, expected_full = false, expected_size = 8},
			{key = "untagged_10", val = "longstring", format_tag = "", expected_tag = .Bytes, expected_full = false, expected_size = 10},
			{key = "tagged_5", val = "short", format_tag = "st", expected_tag = .Short_Bytes, expected_full = true, expected_size = 5},
			{key = "tagged_6", val = "shorts", format_tag = "st", expected_tag = .Short_Bytes, expected_full = true, expected_size = 6},
			{key = "tagged_8_spills", val = "shortstr", format_tag = "st", expected_tag = .Bytes, expected_full = true, expected_size = 8},
		},
	)
}

// ----------------------------------------------------------------------------
// Scenario 22: Radix-Trie (`Array_List`) Root Overflow, Slicing & Sparse `.None` Slots
// ----------------------------------------------------------------------------

@(test)
spec_radix_trie_root_overflow_slicing_and_sparse_none_slots :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN 33 items (SLOT_COUNT * 2 + 1) appended to an Array_List (forcing radix-trie root overflow),
	// THEN slicing down to 16 items (SLOT_COUNT) collapses the root and setting index 3 to `nil` (.None)
	// preserves list count and iterates all 16 positions cleanly
	then_radix_trie_handles_root_overflow_slice_and_sparse_none_slots(
		&ctx,
		total_items = xitdb.SLOT_COUNT * 2 + 1,
		slice_down_to = i64(xitdb.SLOT_COUNT),
		sparse_nil_index = 3,
	)
}

// ----------------------------------------------------------------------------
// Scenario 23: B-Tree (`Linked_Array_List`) Multi-Leaf Self-Concat, Slice, Insert & Remove
// ----------------------------------------------------------------------------

@(test)
spec_btree_linked_list_slice_concat_insert_remove_across_leaf_and_branch_tiers :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN a 30-element Linked_Array_List (spanning multiple B-Tree leaves)
	// UPON self-concatenating to 60 elements, slicing 35 elements from offset 7,
	// inserting at index 18, and removing index 4
	// THEN index lookups, out-of-bounds checks, and B-Tree leaf iterators match the expected sequence
	then_btree_linked_list_preserves_order_across_concat_slice_insert_remove(
		&ctx,
		item_count = 30,
		slice_offset = 7,
		slice_size = 35,
		insert_idx = 18,
		inserted_val = "inserted-middle",
		remove_idx = 4,
	)
}

// ----------------------------------------------------------------------------
// Scenario 24: `Bytes`-Keyed Maps/Sets, KV-Pair Digest Inspection & Duplicate Updates
// ----------------------------------------------------------------------------

@(test)
spec_bytes_keyed_collections_and_kv_pair_inspection :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN binary byte keys (including non-ASCII bytes) stored in Counted_Hash_Map and Counted_Hash_Set
	// THEN key cursors, KV-pair hashes, duplicate-key updates, and removals maintain exact counts
	then_bytes_keyed_collections_preserve_keys_hashes_and_counts(
		&ctx,
		raw_key_a = []u8{0x01, 0x02, 0xfe, 0xff},
		raw_key_b = []u8{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x11, 0x22, 0x33, 0x44},
		val_a = "binary_val_a",
		val_b = "binary_val_b",
	)
}

// ----------------------------------------------------------------------------
// Scenario 25: Re-Opening Compacted File Database & Independent Multi-Handle Reads
// ----------------------------------------------------------------------------

@(test)
spec_reopening_compacted_file_database_and_independent_file_handles :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a file-backed database with 2 moments that is pruned to 1 moment and compacted to disk
	given_file_database(&ctx, hash_algo = "sha1")
	given_committed_moment(
		&ctx,
		Op_Put_String{key = "alpha", val = "alpha-long-payload-string"},
		Op_Put_String{key = "beta", val = "beta-long-payload-string"},
	)
	given_committed_moment(&ctx, Op_Put_String{key = "ephemeral", val = "dropped"})
	upon_retaining_latest_moments(&ctx, 1)
	upon_compacting_database(&ctx)

	// THEN closing the compacted file and re-opening two separate OS file descriptors on it
	// allows interleaved streaming reads without seek-offset interference
	then_reopened_compacted_file_supports_interleaved_multi_handle_reads(
		&ctx,
		moment_idx = 0,
		key1 = "alpha",
		expected1 = "alpha-long-payload-string",
		key2 = "beta",
		expected2 = "beta-long-payload-string",
	)
}

// ----------------------------------------------------------------------------
// Scenario 26: `Cursor_Reader` Byte-by-Byte `read_fully`, Partial `read` & Random Seek
// ----------------------------------------------------------------------------

@(test)
unit_cursor_reader_byte_by_byte_seek_and_eof_boundaries :: proc(t: ^testing.T) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	m, _ := xitdb.write_hash_map_init(xitdb.database_root_cursor(&db))

	// Test both an inline `.Short_Bytes` value ("hello", 5 bytes) and an external `.Bytes` value ("hello, world!", 13 bytes)
	_ = xitdb.hash_map_put(&m, "short", "hello")
	_ = xitdb.hash_map_put(&m, "long", "hello, world!")

	for key in ([]string{"short", "long"}) {
		expected := "hello" if key == "short" else "hello, world!"
		cur_maybe, _ := xitdb.hash_map_get_cursor(m.read_hash_map, key)
		reader, r_err := xitdb.cursor_reader(cur_maybe.?)
		testing.expect_value(t, r_err, nil)
		testing.expect_value(t, reader.size, i64(len(expected)))

		// 1. Read 1 byte at a time via `cursor_reader_read_fully` up to exact length
		one_byte: [1]u8
		for i in 0 ..< len(expected) {
			testing.expect_value(t, xitdb.cursor_reader_read_fully(&reader, one_byte[:]), nil)
			testing.expect_value(t, one_byte[0], expected[i])
		}

		// 2. Reading past the end with `read_fully` returns `.End_Of_Stream`, while `read` returns `0, nil`
		testing.expect_value(t, xitdb.cursor_reader_read_fully(&reader, one_byte[:]), xitdb.Xitdb_Error.End_Of_Stream)
		n_eof, r_eof_err := xitdb.cursor_reader_read(&reader, one_byte[:])
		testing.expect_value(t, r_eof_err, nil)
		testing.expect_value(t, n_eof, 0)

		// 3. Seeking out of bounds (< 0 or > size) returns `.Invalid_Offset`
		testing.expect_value(t, xitdb.cursor_reader_seek_to(&reader, -1), xitdb.Xitdb_Error.Invalid_Offset)
		testing.expect_value(t, xitdb.cursor_reader_seek_to(&reader, reader.size + 1), xitdb.Xitdb_Error.Invalid_Offset)

		// 4. Seeking back to offset 2 reads the suffix `expected[2:]`
		testing.expect_value(t, xitdb.cursor_reader_seek_to(&reader, 2), nil)
		suffix, s_err := xitdb.cursor_reader_read_all(&reader, context.temp_allocator)
		testing.expect_value(t, s_err, nil)
		testing.expect_value(t, string(suffix), expected[2:])
	}

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// Scenario 27: Post-Compaction Replica Resync & Resumed Incremental Replication
// ----------------------------------------------------------------------------

@(test)
spec_post_compaction_replica_resync_converges_cleanly :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx, hash_algo = "sha1")

	// THEN compacting an already-replicated primary triggers a full-replacement resync (start_offset == 0)
	// on the replica and cleanly resumes incremental delta replication on subsequent commits
	then_post_compaction_replica_resync_converges_and_resumes_delta_sync(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 28: Multi-Tier In-Place Mutation vs `cursor_freeze` B-Tree/B+Tree Isolation
// ----------------------------------------------------------------------------

@(test)
spec_multi_tier_btree_in_place_updates_and_cursor_freeze_isolation :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// THEN multi-tier Sorted_Map and Linked_Array_List support fast in-place updates (including new-minimum
	// branch separator updates) before freeze, and isolate frozen snapshots via Copy-on-Write after `cursor_freeze`
	then_multi_tier_btrees_support_in_place_updates_and_cursor_freeze_isolation(&ctx, item_count = 40)
}

// ----------------------------------------------------------------------------
// Scenario 29: `Sorted_Set` Multi-Tier Splits, Rebalancing & Range Iterators
// ----------------------------------------------------------------------------

@(test)
spec_sorted_set_multi_tier_splits_rebalancing_and_range_iterators :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// THEN a 40-member Sorted_Set splits across multiple leaves, ignores duplicate insertions,
	// supports lower-bound key and negative-index iterators, and rebalances cleanly when 25 members are removed
	then_sorted_set_maintains_order_across_multi_tier_splits_merges_and_range_iterators(
		&ctx,
		total_members = 40,
		remove_count = 25,
	)
}

// ----------------------------------------------------------------------------
// Scenario 30: `Linked_Array_List` Empty Slice Collapse & Out-of-Bounds Error Guards
// ----------------------------------------------------------------------------

@(test)
spec_linked_array_list_slice_to_empty_and_range_error_guards :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// THEN full-range slice is a no-op, out-of-bounds slice/insert/remove/put return expected errors,
	// and slicing to 0 elements collapses the B-Tree root cleanly so subsequent appends rebuild from empty
	then_linked_array_list_handles_empty_slice_and_range_error_guards(&ctx, initial_count = 25)
}

// ----------------------------------------------------------------------------
// Scenario 31: `cursor_write_kv_pair` Direct Slot Mutation & `cursor_read_bytes_buf` Edge Guards
// ----------------------------------------------------------------------------

@(test)
unit_write_kv_pair_cursors_and_read_bytes_buf_edge_cases :: proc(t: ^testing.T) {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
	rc := xitdb.database_root_cursor(&db)

	// 1. `cursor_read_bytes_buf` on an empty `.None` root cursor succeeds with a 0-length buffer
	// and returns `.End_Of_Stream` with a non-empty buffer
	empty_buf: [0]u8
	empty_obj, e_err := xitdb.cursor_read_bytes_buf(rc.read_cursor, empty_buf[:])
	testing.expect_value(t, e_err, nil)
	testing.expect_value(t, len(empty_obj.value), 0)

	non_empty_buf: [8]u8
	_, ne_err := xitdb.cursor_read_bytes_buf(rc.read_cursor, non_empty_buf[:])
	testing.expect_value(t, ne_err, xitdb.Xitdb_Error.End_Of_Stream)

	// 2. `cursor_write_kv_pair` allows direct structured writes to `key_cursor` and `value_cursor` inside a transaction
	KV_Write_Ctx :: struct {
		db: ^xitdb.Database,
	}
	kv_ctx := KV_Write_Ctx{db = &db}

	kv_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		c := (^KV_Write_Ctx)(user_data)
		m := xitdb.write_hash_map_init(cursor^) or_return
		custom_hash := xitdb.database_digest_string(c.db, "composite_key", context.temp_allocator)
		kv_cur := xitdb.cursor_write_path(&m.write_cursor, []xitdb.Path_Part{
			xitdb.Hash_Map_Get{target = xitdb.Hash_Map_Get_KV_Pair{hash = custom_hash}},
		}) or_return
		wkv := xitdb.cursor_write_kv_pair(kv_cur, context.temp_allocator) or_return
		xitdb.cursor_write(&wkv.key_cursor, "composite_key") or_return
		xitdb.cursor_write(&wkv.value_cursor, u64(777)) or_return

		// Also verify `hash_map_put_key` idempotency (`if_empty = true`)
		xitdb.hash_map_put_key(&m, "composite_key", "ignored_key_overwrite") or_return
		return nil
	}
	testing.expect_value(t, xitdb.database_run_context(&db, kv_cb, &kv_ctx), nil)

	// Read back via `hash_map_get_kv_pair` and verify both key and value cursors
	rm, _ := xitdb.read_hash_map_init(xitdb.database_root_cursor(&db).read_cursor)
	rkv_maybe, rkv_err := xitdb.hash_map_get_kv_pair(rm, "composite_key", context.temp_allocator)
	testing.expect_value(t, rkv_err, nil)
	rkv := rkv_maybe.?
	k_str, _ := xitdb.cursor_read_string(rkv.key_cursor, 64, context.temp_allocator)
	v_uint, _ := xitdb.cursor_read_uint(rkv.value_cursor)
	testing.expect_value(t, k_str, "composite_key")
	testing.expect_value(t, v_uint, u64(777))

	// Calling `cursor_read_bytes_buf` on a `.Uint` slot returns `.Unexpected_Tag`
	_, tag_err := xitdb.cursor_read_bytes_buf(rkv.value_cursor, non_empty_buf[:])
	testing.expect_value(t, tag_err, xitdb.Xitdb_Error.Unexpected_Tag)

	free_all(context.temp_allocator)
}

// ----------------------------------------------------------------------------
// Scenario 32: `Sorted_Set` Key-Only Leaf Entries, Map Reinterpretation & `linked_array_list_append_context`
// ----------------------------------------------------------------------------

@(test)
spec_sorted_set_key_only_leaf_entries_map_reinterpretation_and_linked_list_append_context :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// THEN Sorted_Set stores keys directly in leaf nodes (.Bytes / .Short_Bytes without .Sorted_KV_Pair indirection),
	// supports reinterpretation as Sorted_Map (promoting key-only entries when values are written),
	// and Linked_Array_List supports `linked_array_list_append_context`
	then_sorted_set_stores_key_only_leaf_entries_and_reinterprets_with_sorted_map(&ctx)
	then_linked_array_list_append_context_nests_collections(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 33: `Cursor_Reader` Lifetime Across Buffer Reallocation, Window Shifts & Truncation
// ----------------------------------------------------------------------------

@(test)
spec_cursor_reader_survives_buffer_reallocation_window_flushes_and_truncation :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// THEN holding an open Cursor_Reader across writes that reallocate Core_Memory.buf or shift Core_Buffered_File's
	// tail window preserves exact streaming reads without dangling slices, and detects post-open truncation
	then_cursor_reader_survives_buffer_reallocation_window_shift_and_truncation(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 34: `Core_Buffered_File` Multi-Handle Alternating Commits Preserve All Moments
// ----------------------------------------------------------------------------

@(test)
spec_buffered_file_multi_handle_alternating_commits_preserve_all_moments :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// THEN two independent Core_Buffered_File handles taking turns committing moments ("1", "2", "3", "4")
	// to the same file never overwrite or lose commits due to stale tail-cache state
	then_buffered_file_multi_handle_alternating_commits_preserve_all_moments(
		&ctx,
		[]string{"1", "2", "3", "4"},
	)
}

// ----------------------------------------------------------------------------
// Scenario 35: Fast-Path Corruption & Truncation Guards on B-Tree, B+Tree, and HAMT
// ----------------------------------------------------------------------------

@(test)
spec_corrupt_slot_tags_inflated_branch_counts_and_truncated_btree_nodes_are_rejected :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// THEN corrupt slot tags, inflated branch subtree counts (rem >= num at leaf), and mid-node truncations
	// return deterministic errors across both Core_Memory fast paths and Core_File seek+read paths
	then_corrupt_slot_tags_inflated_branch_counts_and_truncated_btree_nodes_are_rejected(&ctx)
}





