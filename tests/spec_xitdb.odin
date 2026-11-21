package xitdb_tests

import "core:encoding/endian"
import "core:fmt"
import "core:math/rand"
import "core:mem"
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

	// Genesis v2 database layout (57 bytes: 20B Header + 4B padding + 8B file_size + 25B Root_Trailer at offset 32)
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&core)
		h := xitdb.sha1_hasher(file_id = 0x0102030405060708)
		db, db_err := xitdb.database_init(&core, h)
		testing.expect_value(t, db_err, nil)

		committed_sz, sz_err := xitdb.database_committed_size(&db)
		testing.expect_value(t, sz_err, nil)
		testing.expect_value(t, committed_sz, i64(57))

		bytes, rd_err := xitdb.database_read_committed_bytes(&db, 0, committed_sz, context.temp_allocator)
		defer free_all(context.temp_allocator)
		testing.expect_value(t, rd_err, nil)
		testing.expect_value(t, len(bytes), 57)

		expected_file_id := [8]u8{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}
		testing.expect(t, slice.equal(bytes[12:20], expected_file_id[:]), "Expected big-endian file_id at bytes[12..20]")

		expected_trailer := [25]u8{
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x95, 0xd4, 0x94, 0xc3, 0x4d, 0xf8, 0x07,
			0xe5,
		}
		testing.expect(t, slice.equal(bytes[32:57], expected_trailer[:]), "Expected v2 genesis trailer at bytes[32..57]")
	}
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

	// 8. Root_Header padding bytes (20..24 in v2) are ignored because only `file_size` at
	//    `FILE_SIZE_START` (24..32) is read and the root slot is resolved from the CRC-verified
	//    Root_Trailer at `file_size`, while a corrupted trailer fails.
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer xitdb.core_destroy(&core)
		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
		rc := xitdb.database_root_cursor(&db)
		_ = xitdb.cursor_write(&rc, i64(42))

		// Corrupt the 4 padding bytes before FILE_SIZE_START (bytes 20..24)
		_ = xitdb.core_seek_to(&core, xitdb.ROOT_HEADER_START)
		_ = xitdb.core_write_all(&core, []u8{99, 0xff, 0xff, 0xff})

		// Reading root header and root cursor still succeeds via the verified Root_Trailer
		fresh_rc := xitdb.database_root_cursor(&db)
		val, val_err := xitdb.cursor_read_int(fresh_rc.read_cursor)
		testing.expect_value(t, val_err, nil)
		testing.expect_value(t, val, i64(42))

		// Corrupting the Root_Trailer checksum causes database_read_root_header to fail with .Invalid_Database
		end_pos, _ := xitdb.core_length(&core)
		_ = xitdb.core_seek_to(&core, end_pos - 1)
		_ = xitdb.core_write_byte(&core, 0xaa)
		_, bad_trailer_err := xitdb.cursor_read_int(xitdb.database_root_cursor(&db).read_cursor)
		testing.expect_value(t, bad_trailer_err, xitdb.Xitdb_Error.Invalid_Database)
	}

	// 9. Multi-chunk (> 256B) .Bytes key comparison in Sorted_Map on an unbuffered file backend
	{
		ctx := driver_init_ctx(t, .File)
		defer driver_destroy_ctx(&ctx)
		driver_open_primary(&ctx)

		rc := xitdb.database_root_cursor(&ctx.primary_db)
		sm, sm_err := xitdb.write_sorted_map_init(rc)
		testing.expect_value(t, sm_err, nil)

		prefix_buf: [550]u8
		for i in 0 ..< len(prefix_buf) {
			prefix_buf[i] = u8('a' + (i % 26))
		}
		prefix := string(prefix_buf[:])
		k1 := fmt.tprintf("%s_01", prefix)
		k2 := fmt.tprintf("%s_02", prefix)
		k3 := fmt.tprintf("%s_03", prefix)

		testing.expect_value(t, xitdb.sorted_map_put(&sm, k2, i64(20)), nil)
		testing.expect_value(t, xitdb.sorted_map_put(&sm, k1, i64(10)), nil)
		testing.expect_value(t, xitdb.sorted_map_put(&sm, k3, i64(30)), nil)

		rsm := sm.read_sorted_map
		c1, err1 := xitdb.sorted_map_get_cursor(rsm, k1)
		testing.expect_value(t, err1, nil)
		v1, _ := xitdb.cursor_read_int(c1.?)
		testing.expect_value(t, v1, i64(10))

		kv1_maybe, idx_err := xitdb.sorted_map_get_index_kv_pair(rsm, 1)
		testing.expect_value(t, idx_err, nil)
		v2, _ := xitdb.cursor_read_int(kv1_maybe.?.value_cursor)
		testing.expect_value(t, v2, i64(20))

		rank2, r_err := xitdb.sorted_map_rank(rsm, k2)
		testing.expect_value(t, r_err, nil)
		testing.expect_value(t, rank2, i64(1))
	}

	// 10. Interrupted initial database creation (file_size == 0 and length <= new_size)
	//     recovers cleanly on `database_init` by re-creating the genesis commit.
	{
		core: xitdb.Core = xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&core)

		// Simulate an interrupted genesis creation: valid 20B Header + 12B zero root header + 10B partial trailer (42B <= 57B)
		hdr := xitdb.Header{
			file_id      = 0x1122334455667788,
			hash_id      = 0,
			hash_size    = 20,
			version      = xitdb.VERSION,
			padding      = 0,
			magic_number = xitdb.MAGIC_NUMBER,
		}
		testing.expect_value(t, xitdb.header_write(hdr, &core), nil)
		partial_zeros: [22]u8
		testing.expect_value(t, xitdb.core_write_all(&core, partial_zeros[:]), nil)

		recovered_db, rec_err := xitdb.database_init(&core, xitdb.sha1_hasher(file_id = 0x9988776655443322))
		testing.expect_value(t, rec_err, nil)
		rec_sz, sz_err := xitdb.database_committed_size(&recovered_db)
		testing.expect_value(t, sz_err, nil)
		testing.expect_value(t, rec_sz, i64(57))
		testing.expect_value(t, recovered_db.header.file_id, u64(0x9988776655443322))
	}

	// 11. Interrupted full replication copy (`database_apply_replicated` at `start == 0` cut off mid-stream):
	//     leaves valid header + zero `file_size` + partial body (> 57B), reopens cleanly via `database_init`,
	//     reports `Replica_State{committed_size = 0, checksum = 0}`, and succeeds on the next full sync.
	{
		src_core: xitdb.Core = xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&src_core)
		src_db, _ := xitdb.database_init(&src_core, xitdb.sha1_hasher(file_id = 777))
		src_rc := xitdb.database_root_cursor(&src_db)
		_ = xitdb.cursor_write(&src_rc, "a sufficiently long payload so total committed size exceeds 80 bytes!")
		src_end, _ := xitdb.database_committed_size(&src_db)

		full_bytes, _ := xitdb.database_read_committed_bytes(&src_db, 0, src_end, context.temp_allocator)
		defer free_all(context.temp_allocator)

		rep_core: xitdb.Core = xitdb.core_memory_init()
		defer _ = xitdb.core_destroy(&rep_core)
		rep_db, _ := xitdb.database_init(&rep_core, xitdb.sha1_hasher(file_id = 888))

		// Feed a truncated stream (missing the final 10 bytes, but claiming full `src_end` length)
		trunc_stream: xitdb.Core = xitdb.core_memory_from_bytes(full_bytes[:len(full_bytes) - 10])
		defer _ = xitdb.core_destroy(&trunc_stream)
		apply_err := xitdb.database_apply_replicated(&rep_db, 0, &trunc_stream, src_end)
		testing.expect_value(t, apply_err, xitdb.Xitdb_Error.Unexpected_EOF)

		// Simulate an interrupted copy that wrote > 57 bytes before dying (file_size in root header is still 0)
		_ = xitdb.core_seek_to(&rep_core, 32)
		_ = xitdb.core_write_all(&rep_core, full_bytes[32:len(full_bytes) - 5])

		// Re-opening the interrupted replica succeeds without overwriting the partial copy
		reopened_rep, re_err := xitdb.database_init(&rep_core, xitdb.sha1_hasher())
		testing.expect_value(t, re_err, nil)

		// replica_state reports {committed_size = 0, checksum = 0} so replication_start returns 0
		state, st_err := xitdb.database_replica_state(&reopened_rep)
		testing.expect_value(t, st_err, nil)
		testing.expect_value(t, state.committed_size, i64(0))
		testing.expect_value(t, state.checksum, u64(0))

		rep_start, rs_err := xitdb.database_replication_start(&src_db, state)
		testing.expect_value(t, rs_err, nil)
		testing.expect_value(t, rep_start, i64(0))

		// Applying the full payload now succeeds and recovers the replica
		testing.expect_value(t, xitdb.database_apply_replicated_bytes(&reopened_rep, 0, full_bytes), nil)
		verify_rc := xitdb.database_root_cursor(&reopened_rep)
		actual_str, str_err := xitdb.cursor_read_string(verify_rc.read_cursor, 4096, context.temp_allocator)
		testing.expect_value(t, str_err, nil)
		testing.expect_value(t, actual_str, "a sufficiently long payload so total committed size exceeds 80 bytes!")
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

// ----------------------------------------------------------------------------
// Scenario 36: Compactor & Buffered-File `max_size` / Out-of-Memory Allocation Guards
// ----------------------------------------------------------------------------

@(test)
spec_compactor_and_buffered_file_enforce_max_size_and_allocation_failure_guards :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// THEN database_compact into a capped Core_Memory target, offset_map_put under a failing allocator,
	// and Core_Buffered_File tail-buffer writes under max_size / allocation failure return deterministic
	// errors instead of out-of-bounds panics or silent cap violations
	then_compactor_and_buffered_file_enforce_max_size_and_allocation_failure_guards(&ctx)
}

// ----------------------------------------------------------------------------
// Scenario 37: Lock-Free Concurrent Cursors & Resumable Iterators (`core_read_at`)
// ----------------------------------------------------------------------------

@(test)
spec_lock_free_concurrent_cursors_and_resumable_iterators :: proc(t: ^testing.T) {
	for backend in Backend_Kind {
		ctx := driver_init_ctx(t)
		defer driver_destroy_ctx(&ctx)

		// GIVEN a database on Memory, File, or Buffered_File populated with 64 items across HAMT maps,
		// Radix Trie array lists, B-Tree linked lists, B+Tree sorted maps, and an 8 KiB Bytes stream
		given_database_initialized_with(&ctx, backend)
		upon_populating_concurrent_read_fixture(&ctx, item_count = 64)

		// THEN 8 worker threads can concurrently read random keys, iterate collections,
		// stream Cursor_Reader chunks, and pause/serialize {moment_slot, cursor_slot} at index 32 ("key-0032")
		// to resume the remaining 32 items on other worker threads with zero seek-offset interference
		then_concurrent_readers_and_resumable_cursors_succeed_without_interference(
			&ctx,
			worker_count             = 8,
			item_count               = 64,
			pause_at_key             = "key-0032",
			expected_remaining_keys  = 32,
			pause_at_index           = 32,
			expected_remaining_items = 32,
			sentinel_pos             = 777777,
		)
	}
}

// ----------------------------------------------------------------------------
// Scenario 38: Virtual Memory (`vmem.reserve`) Base-Pointer Stability Under Concurrent Appends
// ----------------------------------------------------------------------------

@(test)
spec_virtual_memory_base_pointer_stability_under_concurrent_appends :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a Core_Memory-backed database with an initial committed moment of 48 items
	given_database_initialized_with(&ctx, .Memory)
	upon_populating_concurrent_read_fixture(&ctx, item_count = 48)

	// THEN when a writer thread appends 40 new moments (growing the database across multiple megabytes)
	// while 6 reader threads concurrently read committed moments, the base pointer raw_data(buf)
	// never moves and all 41 moments remain intact
	then_virtual_memory_base_pointer_remains_stable_during_concurrent_writer_appends(
		&ctx,
		reader_count   = 6,
		append_moments = 40,
		item_count     = 48,
	)
}

// ----------------------------------------------------------------------------
// Scenario 39: Concurrent Compaction & Incremental Replication While Readers Query Source DB
// ----------------------------------------------------------------------------

@(test)
spec_concurrent_compaction_and_replication_with_parallel_readers :: proc(t: ^testing.T) {
	for backend in Backend_Kind {
		ctx := driver_init_ctx(t)
		defer driver_destroy_ctx(&ctx)

		// GIVEN a database on Memory, File, or Buffered_File with an initial committed moment of 48 items
		given_database_initialized_with(&ctx, backend)
		upon_populating_concurrent_read_fixture(&ctx, item_count = 48)

		// THEN while 6 parallel reader threads continuously query collections, a background compaction thread
		// and a background replication thread can concurrently read and compact/replicate the source database
		// with zero seek-offset interference or data corruption
		then_concurrent_compaction_and_replication_succeed_during_parallel_reads(
			&ctx,
			reader_count = 6,
			item_count   = 48,
			sentinel_pos = 888888,
		)
	}
}

// ----------------------------------------------------------------------------
// Scenario 40: Virtual Memory (`vmem.reserve`) Reservation Cap, `core_set_length` Shrink/Re-Grow & `init_from_bytes`
// ----------------------------------------------------------------------------

@(test)
spec_virtual_memory_reservation_cap_shrink_regrow_and_init_from_bytes :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a Core_Memory initialized with a bounded 64 KiB virtual address reservation
	given_virtual_memory_core_with_reservation(&ctx, reserve_bytes = 65536)

	// UPON writing 32 KiB, shrinking via core_set_length to 4 KiB, and re-growing by 32 KiB (total 36 KiB)
	upon_writing_shrinking_and_regrowing_virtual_memory_core(
		&ctx,
		initial_write_bytes = 32768,
		shrink_to_bytes     = 4096,
		regrow_write_bytes  = 32768,
	)

	// THEN the base pointer never moves, attempting to write beyond the 64 KiB reservation returns .Write_Failed,
	// and core_memory_init_from_bytes clones the 36 KiB buffer into a fresh vmem-backed Core_Memory
	then_virtual_memory_enforces_reservation_cap_and_clones_from_bytes(
		&ctx,
		expected_length       = 4096 + 32768,
		expected_overflow_err = .Write_Failed,
	)
}

// ----------------------------------------------------------------------------
// Scenario 41: Reverse & Upper-Bound Range Iterators Across All Collection Types
// ----------------------------------------------------------------------------

@(test)
spec_reverse_iterators_across_btree_bplustree_and_radix_trie :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN a moment containing sorted keys ["alice", "bob", "charlie", "dave", "erin"]
	// across Sorted_Map, Sorted_Set, Array_List, Linked_Array_List, Counted_Hash_Map, and Hash_Set
	users := [?]Key_Uint{
		{key = "alice",   val = 1},
		{key = "bob",     val = 2},
		{key = "charlie", val = 3},
		{key = "dave",    val = 4},
		{key = "erin",    val = 5},
	}
	names := [?]string{"alice", "bob", "charlie", "dave", "erin"}

	given_committed_moment(
		&ctx,
		Op_Put_Sorted_Map{key = "users", entries = users[:]},
		Op_Put_Sorted_Set{key = "tags", members = names[:]},
		Op_Put_Array_List{key = "array", items = names[:]},
		Op_Put_Linked_List{key = "linked", items = names[:]},
		Op_Put_Counted_Map{key = "hashmap", entries = users[:]},
		Op_Put_Hash_Set{key = "hashset", members = names[:]},
	)

	// THEN inclusive upper-bound reverse iteration (`<= "charlie"`) includes "charlie" and descends to "alice"
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "charlie", inclusive = true,  expected_keys    = []string{"charlie", "bob", "alice"})
	then_sorted_set_reverse_from_key_equals(&ctx, 0, "tags",  "charlie", inclusive = true,  expected_members = []string{"charlie", "bob", "alice"})

	// AND exclusive upper-bound reverse iteration (`< "charlie"`) strictly precedes "charlie"
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "charlie", inclusive = false, expected_keys    = []string{"bob", "alice"})
	then_sorted_set_reverse_from_key_equals(&ctx, 0, "tags",  "charlie", inclusive = false, expected_members = []string{"bob", "alice"})

	// AND an intermediate key ("carol", between "bob" and "charlie") starts at "bob" for both inclusive and exclusive bounds
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "carol", inclusive = true,  expected_keys = []string{"bob", "alice"})
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "carol", inclusive = false, expected_keys = []string{"bob", "alice"})

	// AND an upper bound above the maximum key ("zoe") yields the full descending collection
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "zoe", inclusive = true,  expected_keys = []string{"erin", "dave", "charlie", "bob", "alice"})
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "zoe", inclusive = false, expected_keys = []string{"erin", "dave", "charlie", "bob", "alice"})

	// AND boundary probes at or below the minimum key ("alice" / "aaa") include or exclude "alice" accurately
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "alice", inclusive = true,  expected_keys = []string{"alice"})
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "alice", inclusive = false, expected_keys = []string{})
	then_sorted_map_reverse_from_key_equals(&ctx, 0, "users", "aaa",   inclusive = true,  expected_keys = []string{})

	// AND reverse iteration from positive or negative index starts at that rank and walks down to index 0
	then_sorted_map_reverse_from_index_equals(&ctx, 0, "users",   2, expected_keys  = []string{"charlie", "bob", "alice"})
	then_sorted_map_reverse_from_index_equals(&ctx, 0, "users",  -2, expected_keys  = []string{"dave", "charlie", "bob", "alice"})
	then_sorted_map_reverse_from_index_equals(&ctx, 0, "users",  99, expected_keys  = []string{})
	then_array_list_reverse_from_index_equals(&ctx, 0, "array",  -2, expected_items = []string{"dave", "charlie", "bob", "alice"})
	then_linked_list_reverse_from_index_equals(&ctx, 0, "linked", 2, expected_items = []string{"charlie", "bob", "alice"})

	// AND HAMT reverse iterators (`hash_map_iterator_reverse`, `hash_set_iterator_reverse`) mirror forward HAMT order
	then_hamt_reverse_iterators_mirror_forward_order(&ctx, 0, "hashmap", "hashset", 5)
}

// ----------------------------------------------------------------------------
// Scenario 42: 3-Tier Buffered-File Reverse Iterators & Multi-Level Stale Separators
// ----------------------------------------------------------------------------

@(test)
spec_reverse_iterators_on_buffered_file_three_tier_trees_and_boundary_guards :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	// GIVEN a small-window Core_Buffered_File database (512-byte tail buffer) populated with 200 even-numbered items
	// ("k-0000", "k-0002", ..., "k-0398") spanning 3-tier B+Trees, 3-tier B-Trees, and 2-tier Radix-Tries
	given_buffered_file_database(&ctx, buffer_bytes = 512)

	N :: 200
	sm_entries := make([]Key_Uint, N, context.temp_allocator)
	ss_members := make([]string, N, context.temp_allocator)
	list_items := make([]string, N, context.temp_allocator)
	for i in 0 ..< N {
		k := fmt.tprintf("k-%04d", i * 2)
		sm_entries[i] = Key_Uint{key = k, val = u64(i)}
		ss_members[i] = k
		list_items[i] = fmt.tprintf("item-%04d", i)
	}

	given_committed_moment(
		&ctx,
		Op_Put_Sorted_Map{key = "sm", entries = sm_entries},
		Op_Put_Sorted_Set{key = "ss", members = ss_members},
		Op_Put_Array_List{key = "al", items = list_items},
		Op_Put_Linked_List{key = "ll", items = list_items},
	)

	// WHEN the buffered file is flushed so 3-tier nodes are read from the OS file descriptor
	upon_flushing_database(&ctx)

	// THEN full forward/reverse collection invariants and cross-leaf reverse slices succeed from disk
	then_moment_has_sorted_map_in_order(&ctx, 0, "sm", i64(N))
	then_moment_has_sorted_set_in_order(&ctx, 0, "ss", ss_members)
	then_moment_has_array_list(&ctx, 0, "al", list_items)
	then_moment_has_linked_list(&ctx, 0, "ll", list_items)

	then_array_list_reverse_from_index_equals(
		&ctx, 0, "al", start_idx = 17, limit = 4,
		expected_items = []string{"item-0017", "item-0016", "item-0015", "item-0014"},
	)
	then_linked_list_reverse_from_index_equals(
		&ctx, 0, "ll", start_idx = 17, limit = 4,
		expected_items = []string{"item-0017", "item-0016", "item-0015", "item-0014"},
	)

	// WHEN leaf-split boundary key "k-0016" and 2nd-tier branch-split boundary key "k-0128" are deleted in Moment 1
	// (leaving stale separator keys in parent/grandparent branches while leaf 0-th entries advance to "k-0018" and "k-0130")
	upon_branching_moment(
		&ctx,
		0,
		Op_Remove_Sorted_Map{key = "sm", keys_to_drop = []string{"k-0016", "k-0128"}},
	)
	upon_flushing_database(&ctx)

	// THEN reverse upper-bound queries at or across the deleted leaf-split boundary ("k-0016" / "k-0017" / "k-0018")
	// seamlessly pop the leaf and step into the preceding leaf ("k-0014", "k-0012", "k-0010")
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0016", inclusive = true, limit = 3,
		expected_keys = []string{"k-0014", "k-0012", "k-0010"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0017", inclusive = true, limit = 3,
		expected_keys = []string{"k-0014", "k-0012", "k-0010"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0018", inclusive = false, limit = 3,
		expected_keys = []string{"k-0014", "k-0012", "k-0010"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0018", inclusive = true, limit = 3,
		expected_keys = []string{"k-0018", "k-0014", "k-0012"},
	)

	// AND reverse upper-bound queries across the deleted 2nd-tier internal branch boundary ("k-0128" / "k-0129" / "k-0130")
	// cascade up two branch levels and descend into the preceding subtree ("k-0126", "k-0124", "k-0122")
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0128", inclusive = true, limit = 3,
		expected_keys = []string{"k-0126", "k-0124", "k-0122"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0129", inclusive = true, limit = 3,
		expected_keys = []string{"k-0126", "k-0124", "k-0122"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0130", inclusive = false, limit = 3,
		expected_keys = []string{"k-0126", "k-0124", "k-0122"},
	)
	then_sorted_map_reverse_from_key_equals(
		&ctx, 1, "sm", "k-0130", inclusive = true, limit = 3,
		expected_keys = []string{"k-0130", "k-0126", "k-0124"},
	)
}

// ----------------------------------------------------------------------------
// Pattern E (Direct SUT Unit Test): Reverse Iterator Unwritten `.None`, Sparse Slots & Tag Guards
// ----------------------------------------------------------------------------

@(test)
unit_reverse_iterator_unwritten_none_sparse_slots_and_tag_guards :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core: xitdb.Core = xitdb.core_memory_init()
	defer _ = xitdb.core_destroy(&core)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		t_ptr := (^testing.T)(user_data)
		root_map := xitdb.write_hash_map_init(cursor^) or_return

		// 1. Unwritten cursor (.None, full = false) returns an empty iterator for all 5 reverse constructors,
		// and repeated `cursor_iterator_prev` calls after exhaustion remain idempotent (`nil, nil` with `index == 0`)
		unwritten_cur := xitdb.hash_map_put_cursor(&root_map, "unwritten") or_return
		unwritten_rc := unwritten_cur.read_cursor

		for kind in 0 ..< 5 {
			it_empty: xitdb.Cursor_Iterator
			err: xitdb.Error
			switch kind {
			case 0:
				it_empty, err = xitdb.cursor_iterator_reverse(unwritten_rc)
			case 1:
				it_empty, err = xitdb.cursor_iterator_sorted_reverse_from_index(unwritten_rc, 0)
			case 2:
				it_empty, err = xitdb.cursor_iterator_sorted_reverse_from_key(unwritten_rc, []u8{'a'}, true)
			case 3:
				it_empty, err = xitdb.cursor_iterator_array_list_reverse_from_index(unwritten_rc, 0)
			case 4:
				it_empty, err = xitdb.cursor_iterator_linked_array_list_reverse_from_index(unwritten_rc, 0)
			}
			testing.expect_value(t_ptr, err, nil)
			for _ in 0 ..< 3 {
				c_empty, p_err := xitdb.cursor_iterator_prev(&it_empty)
				testing.expect_value(t_ptr, p_err, nil)
				testing.expect(t_ptr, c_empty == nil, "Expected nil on unwritten .None reverse iterator")
				testing.expect_value(t_ptr, it_empty.index, i64(0))
			}
		}

		// 2. Scalar cursor (.Uint) returns `.Unexpected_Tag` for all reverse iterator constructors and `cursor_iterator_prev`
		scalar_cur := xitdb.hash_map_put_cursor(&root_map, "scalar") or_return
		xitdb.cursor_write(&scalar_cur, u64(123)) or_return
		scalar_rc := scalar_cur.read_cursor

		_, e0 := xitdb.cursor_iterator_reverse(scalar_rc)
		testing.expect_value(t_ptr, e0, xitdb.Xitdb_Error.Unexpected_Tag)
		_, e1 := xitdb.cursor_iterator_sorted_reverse_from_index(scalar_rc, 0)
		testing.expect_value(t_ptr, e1, xitdb.Xitdb_Error.Unexpected_Tag)
		_, e2 := xitdb.cursor_iterator_sorted_reverse_from_key(scalar_rc, []u8{'a'}, true)
		testing.expect_value(t_ptr, e2, xitdb.Xitdb_Error.Unexpected_Tag)
		_, e3 := xitdb.cursor_iterator_array_list_reverse_from_index(scalar_rc, 0)
		testing.expect_value(t_ptr, e3, xitdb.Xitdb_Error.Unexpected_Tag)
		_, e4 := xitdb.cursor_iterator_linked_array_list_reverse_from_index(scalar_rc, 0)
		testing.expect_value(t_ptr, e4, xitdb.Xitdb_Error.Unexpected_Tag)

		bad_it := xitdb.Cursor_Iterator{cursor = scalar_rc}
		_, e5 := xitdb.cursor_iterator_prev(&bad_it)
		testing.expect_value(t_ptr, e5, xitdb.Xitdb_Error.Unexpected_Tag)

		// 3. Sparse Array_List containing an explicit `Slot{tag = .None, full = true}` entry yields all 3 items in reverse
		al_cur := xitdb.hash_map_put_cursor(&root_map, "sparse_al") or_return
		al := xitdb.write_array_list_init(al_cur) or_return
		xitdb.array_list_append(&al, "first") or_return
		xitdb.array_list_append(&al, xitdb.Slot{tag = .None, full = true}) or_return
		xitdb.array_list_append(&al, "third") or_return

		rev_al, ral_err := xitdb.array_list_iterator_reverse(al.read_array_list)
		testing.expect_value(t_ptr, ral_err, nil)

		c2, _ := xitdb.cursor_iterator_prev(&rev_al)
		s2, _ := xitdb.cursor_read_string(c2.?, 32, context.temp_allocator)
		testing.expect_value(t_ptr, s2, "third")

		c1, _ := xitdb.cursor_iterator_prev(&rev_al)
		sl1, _ := xitdb.cursor_slot(c1.?)
		testing.expect_value(t_ptr, sl1.tag, xitdb.Tag.None)
		testing.expect_value(t_ptr, sl1.full, true)

		c0, _ := xitdb.cursor_iterator_prev(&rev_al)
		s0, _ := xitdb.cursor_read_string(c0.?, 32, context.temp_allocator)
		testing.expect_value(t_ptr, s0, "first")

		for _ in 0 ..< 3 {
			c_done, done_err := xitdb.cursor_iterator_prev(&rev_al)
			testing.expect_value(t_ptr, done_err, nil)
			testing.expect(t_ptr, c_done == nil, "Expected nil after reverse iterator exhaustion")
		}

		return nil
	}

	testing.expect_value(t, xitdb.database_run_context(&db, cb, t), nil)
}

@(test)
unit_cursor_iterator_in_place_init_and_reuse_invariants :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)

	core: xitdb.Core = xitdb.core_memory_init()
	defer _ = xitdb.core_destroy(&core)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	testing.expect_value(t, init_err, nil)

	cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
		t_ptr := (^testing.T)(user_data)
		root_map := xitdb.write_hash_map_init(cursor^) or_return

		// Empty / special cursors
		unwritten_cur := xitdb.hash_map_put_cursor(&root_map, "unwritten") or_return
		unwritten_rc := unwritten_cur.read_cursor

		scalar_cur := xitdb.hash_map_put_cursor(&root_map, "scalar") or_return
		xitdb.cursor_write(&scalar_cur, u64(42)) or_return
		scalar_rc := scalar_cur.read_cursor

		empty_al_cur := xitdb.hash_map_put_cursor(&root_map, "empty_al") or_return
		_ = xitdb.write_array_list_init(empty_al_cur) or_return
		empty_ll_cur := xitdb.hash_map_put_cursor(&root_map, "empty_ll") or_return
		_ = xitdb.write_linked_array_list_init(empty_ll_cur) or_return
		empty_sm_cur := xitdb.hash_map_put_cursor(&root_map, "empty_sm") or_return
		_ = xitdb.write_sorted_map_init(empty_sm_cur) or_return
		empty_ss_cur := xitdb.hash_map_put_cursor(&root_map, "empty_ss") or_return
		_ = xitdb.write_sorted_set_init(empty_ss_cur) or_return
		empty_hm_cur := xitdb.hash_map_put_cursor(&root_map, "empty_hm") or_return
		_ = xitdb.write_hash_map_init(empty_hm_cur) or_return
		empty_chm_cur := xitdb.hash_map_put_cursor(&root_map, "empty_chm") or_return
		_ = xitdb.write_counted_hash_map_init(empty_chm_cur) or_return
		empty_hs_cur := xitdb.hash_map_put_cursor(&root_map, "empty_hs") or_return
		_ = xitdb.write_hash_set_init(empty_hs_cur) or_return
		empty_chs_cur := xitdb.hash_map_put_cursor(&root_map, "empty_chs") or_return
		_ = xitdb.write_counted_hash_set_init(empty_chs_cur) or_return

		// Multi-tier populated collections (N = 40 > 16 so radix tries and B-Trees have height >= 2)
		N :: 40
		al_cur := xitdb.hash_map_put_cursor(&root_map, "al") or_return
		al := xitdb.write_array_list_init(al_cur) or_return
		ll_cur := xitdb.hash_map_put_cursor(&root_map, "ll") or_return
		ll := xitdb.write_linked_array_list_init(ll_cur) or_return
		sm_cur := xitdb.hash_map_put_cursor(&root_map, "sm") or_return
		sm := xitdb.write_sorted_map_init(sm_cur) or_return
		ss_cur := xitdb.hash_map_put_cursor(&root_map, "ss") or_return
		ss := xitdb.write_sorted_set_init(ss_cur) or_return

		for i in 0 ..< N {
			xitdb.array_list_append(&al, fmt.tprintf("al-%02d", i)) or_return
			xitdb.linked_array_list_append(&ll, fmt.tprintf("ll-%02d", i)) or_return
			xitdb.sorted_map_put(&sm, fmt.tprintf("k-%02d", i), u64(i)) or_return
			xitdb.sorted_set_put(&ss, fmt.tprintf("s-%02d", i)) or_return
		}

		H :: 20
		hm_cur := xitdb.hash_map_put_cursor(&root_map, "hm") or_return
		hm := xitdb.write_hash_map_init(hm_cur) or_return
		chm_cur := xitdb.hash_map_put_cursor(&root_map, "chm") or_return
		chm := xitdb.write_counted_hash_map_init(chm_cur) or_return
		hs_cur := xitdb.hash_map_put_cursor(&root_map, "hs") or_return
		hs := xitdb.write_hash_set_init(hs_cur) or_return
		chs_cur := xitdb.hash_map_put_cursor(&root_map, "chs") or_return
		chs := xitdb.write_counted_hash_set_init(chs_cur) or_return

		for i in 0 ..< H {
			mk := fmt.tprintf("m-%02d", i)
			hk := fmt.tprintf("h-%02d", i)
			xitdb.hash_map_put(&hm, mk, u64(i)) or_return
			xitdb.hash_map_put(&chm, mk, u64(i)) or_return
			xitdb.hash_set_put(&hs, hk) or_return
			xitdb.hash_set_put(&chs, hk) or_return
		}

		al_rc  := al.read_array_list.cursor
		ll_rc  := ll.read_linked_array_list.cursor
		sm_rc  := sm.read_sorted_map.cursor
		ss_rc  := ss.read_sorted_set.cursor
		hm_rc  := hm.read_hash_map.cursor
		chm_rc := chm.read_hash_map.cursor
		hs_rc  := hs.read_hash_set.cursor
		chs_rc := chs.read_hash_set.cursor

		make_dirty :: proc(t_ptr: ^testing.T, it: ^xitdb.Cursor_Iterator, sm_rc: xitdb.Read_Cursor) {
			err := xitdb.cursor_iterator_init(it, sm_rc)
			testing.expect_value(t_ptr, err, nil)
			for _ in 0 ..< 20 {
				c, next_err := xitdb.cursor_iterator_next(it)
				testing.expect_value(t_ptr, next_err, nil)
				testing.expect(t_ptr, c != nil, "Expected non-nil element while dirtying iterator")
			}
			testing.expect(t_ptr, it.stack_len >= 2, "Expected multi-tier B+Tree stack_len >= 2")
			testing.expect_value(t_ptr, it.index, i64(20))
			testing.expect_value(t_ptr, it.size, i64(40))
		}

		collect_strings :: proc(t_ptr: ^testing.T, it: ^xitdb.Cursor_Iterator, kv_key: bool, reverse: bool = false) -> []string {
			out := make([dynamic]string, 0, 16, context.temp_allocator)
			for {
				c_maybe: Maybe(xitdb.Read_Cursor)
				next_err: xitdb.Error
				if reverse {
					c_maybe, next_err = xitdb.cursor_iterator_prev(it)
				} else {
					c_maybe, next_err = xitdb.cursor_iterator_next(it)
				}
				testing.expect_value(t_ptr, next_err, nil)
				c, ok := c_maybe.?
				if !ok {
					break
				}
				target := c
				if kv_key {
					k_cur, _, kv_err := xitdb.cursor_read_kv_pair_slots(c)
					testing.expect_value(t_ptr, kv_err, nil)
					target = k_cur
				}
				s, s_err := xitdb.cursor_read_string(target, 64, context.temp_allocator)
				testing.expect_value(t_ptr, s_err, nil)
				append(&out, s)
			}
			return out[:]
		}

		is_zeroed_iter :: proc(it: ^xitdb.Cursor_Iterator) -> bool {
			for b in mem.ptr_to_bytes(it) {
				if b != 0 {
					return false
				}
			}
			return true
		}

		expect_slice_eq :: proc(t_ptr: ^testing.T, a, b: []string, label: string) {
			testing.expect_value(t_ptr, len(a), len(b))
			n := min(len(a), len(b))
			for i in 0 ..< n {
				if a[i] != b[i] {
					testing.expectf(t_ptr, false, "%s mismatch at %d: %q vs %q", label, i, a[i], b[i])
					break
				}
			}
		}

		expect_empty_iter :: proc(t_ptr: ^testing.T, it: ^xitdb.Cursor_Iterator, label: string, reverse: bool = false) {
			c: Maybe(xitdb.Read_Cursor)
			err: xitdb.Error
			if reverse {
				c, err = xitdb.cursor_iterator_prev(it)
			} else {
				c, err = xitdb.cursor_iterator_next(it)
			}
			testing.expect_value(t_ptr, err, nil)
			testing.expectf(t_ptr, c == nil, "%s: expected nil from empty iterator", label)
		}

		// Allocate a single Cursor_Iterator and reuse it across all tests
		it := new(xitdb.Cursor_Iterator)
		defer free(it)

		// 1. cursor_iterator_init: parity across all 8 populated collection types
		all_cols := [?]struct {
			rc:     xitdb.Read_Cursor,
			kv_key: bool,
			sorted: bool,
			count:  int,
			prefix: string,
		}{
			{al_rc,  false, true,  N, "al-"},
			{ll_rc,  false, true,  N, "ll-"},
			{sm_rc,  true,  true,  N, "k-"},
			{ss_rc,  true,  true,  N, "s-"},
			{hm_rc,  true,  false, H, "m-"},
			{chm_rc, true,  false, H, "m-"},
			{hs_rc,  true,  false, H, "h-"},
			{chs_rc, true,  false, H, "h-"},
		}
		for col in all_cols {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_init(it, col.rc), nil)
			got := collect_strings(t_ptr, it, col.kv_key)

			ref_it, ref_err := xitdb.cursor_iterator(col.rc)
			testing.expect_value(t_ptr, ref_err, nil)
			ref := collect_strings(t_ptr, &ref_it, col.kv_key)

			testing.expect_value(t_ptr, len(got), col.count)
			expect_slice_eq(t_ptr, got, ref, col.prefix)
			if col.sorted {
				for i in 0 ..< len(got) {
					testing.expect_value(t_ptr, got[i], fmt.tprintf("%s%02d", col.prefix, i))
				}
			} else {
				slice.sort(got)
				for i in 0 ..< len(got) {
					testing.expect_value(t_ptr, got[i], fmt.tprintf("%s%02d", col.prefix, i))
				}
			}
		}

		// cursor_iterator_init on dirty iterator -> all 8 empty collections, .None, and .Uint error
		empty_cols := [?]xitdb.Read_Cursor{
			empty_al_cur.read_cursor,
			empty_ll_cur.read_cursor,
			empty_sm_cur.read_cursor,
			empty_ss_cur.read_cursor,
			empty_hm_cur.read_cursor,
			empty_chm_cur.read_cursor,
			empty_hs_cur.read_cursor,
			empty_chs_cur.read_cursor,
		}
		for ec in empty_cols {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_init(it, ec), nil)
			expect_empty_iter(t_ptr, it, "cursor_iterator_init empty")
		}

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_init(it, unwritten_rc), nil)
		testing.expect_value(t_ptr, it.size, i64(0))
		testing.expect_value(t_ptr, it.index, i64(0))
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "cursor_iterator_init .None")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_init(it, scalar_rc), xitdb.Xitdb_Error.Unexpected_Tag)
		testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on cursor_iterator_init error")

		// 2. cursor_iterator_sorted_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, sm_rc, 25), nil)
		testing.expect_value(t_ptr, it.size, i64(40))
		testing.expect_value(t_ptr, it.index, i64(25))
		sm_idx_got := collect_strings(t_ptr, it, true)
		sm_idx_ref_it, sm_idx_ref_err := xitdb.cursor_iterator_sorted_from_index(sm_rc, 25)
		testing.expect_value(t_ptr, sm_idx_ref_err, nil)
		expect_slice_eq(t_ptr, sm_idx_got, collect_strings(t_ptr, &sm_idx_ref_it, true), "sorted_from_index 25")
		testing.expect_value(t_ptr, len(sm_idx_got), 15)
		testing.expect_value(t_ptr, sm_idx_got[0], "k-25")
		testing.expect_value(t_ptr, sm_idx_got[14], "k-39")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, sm_rc, -5), nil)
		testing.expect_value(t_ptr, it.index, i64(35))
		sm_neg := collect_strings(t_ptr, it, true)
		testing.expect_value(t_ptr, len(sm_neg), 5)
		testing.expect_value(t_ptr, sm_neg[0], "k-35")
		testing.expect_value(t_ptr, sm_neg[4], "k-39")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, ss_rc, 30), nil)
		ss_idx := collect_strings(t_ptr, it, true)
		testing.expect_value(t_ptr, len(ss_idx), 10)
		testing.expect_value(t_ptr, ss_idx[0], "s-30")
		testing.expect_value(t_ptr, ss_idx[9], "s-39")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, sm_rc, oob), nil)
			testing.expect_value(t_ptr, it.size, i64(40))
			testing.expect_value(t_ptr, it.index, i64(40))
			testing.expect_value(t_ptr, it.stack_len, 0)
			expect_empty_iter(t_ptr, it, "sorted_from_index oob")
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, empty_sm_cur.read_cursor, 0), nil)
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "sorted_from_index empty")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "sorted_from_index .None")

		for bad in ([?]xitdb.Read_Cursor{hm_rc, al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on sorted_from_index_init error")
		}

		// 3. cursor_iterator_sorted_from_key_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, sm_rc, transmute([]u8)string("k-17")), nil)
		testing.expect_value(t_ptr, it.size, i64(40))
		testing.expect_value(t_ptr, it.index, i64(17))
		sm_key_got := collect_strings(t_ptr, it, true)
		sm_key_ref_it, sm_key_ref_err := xitdb.cursor_iterator_sorted_from_key(sm_rc, transmute([]u8)string("k-17"))
		testing.expect_value(t_ptr, sm_key_ref_err, nil)
		expect_slice_eq(t_ptr, sm_key_got, collect_strings(t_ptr, &sm_key_ref_it, true), "sorted_from_key k-17")
		testing.expect_value(t_ptr, len(sm_key_got), 23)
		testing.expect_value(t_ptr, sm_key_got[0], "k-17")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, sm_rc, transmute([]u8)string("k-17a")), nil)
		testing.expect_value(t_ptr, it.index, i64(18))
		sm_mid := collect_strings(t_ptr, it, true)
		testing.expect_value(t_ptr, len(sm_mid), 22)
		testing.expect_value(t_ptr, sm_mid[0], "k-18")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, sm_rc, transmute([]u8)string("z-99")), nil)
		testing.expect_value(t_ptr, it.index, i64(40))
		expect_empty_iter(t_ptr, it, "sorted_from_key past end")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, empty_sm_cur.read_cursor, transmute([]u8)string("a")), nil)
		expect_empty_iter(t_ptr, it, "sorted_from_key empty")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, ss_rc, transmute([]u8)string("s-35")), nil)
		ss_key := collect_strings(t_ptr, it, true)
		testing.expect_value(t_ptr, len(ss_key), 5)
		testing.expect_value(t_ptr, ss_key[0], "s-35")
		testing.expect_value(t_ptr, ss_key[4], "s-39")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, unwritten_rc, transmute([]u8)string("a")), nil)
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "sorted_from_key .None")

		for bad in ([?]xitdb.Read_Cursor{al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_from_key_init(it, bad, transmute([]u8)string("a")), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on sorted_from_key_init error")
		}

		// 4. cursor_iterator_array_list_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, al_rc, 20), nil)
		testing.expect_value(t_ptr, it.size, i64(40))
		testing.expect_value(t_ptr, it.index, i64(20))
		al_got := collect_strings(t_ptr, it, false)
		al_ref_it, al_ref_err := xitdb.cursor_iterator_array_list_from_index(al_rc, 20)
		testing.expect_value(t_ptr, al_ref_err, nil)
		expect_slice_eq(t_ptr, al_got, collect_strings(t_ptr, &al_ref_it, false), "array_list_from_index 20")
		testing.expect_value(t_ptr, len(al_got), 20)
		testing.expect_value(t_ptr, al_got[0], "al-20")
		testing.expect_value(t_ptr, al_got[19], "al-39")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, al_rc, -3), nil)
		testing.expect_value(t_ptr, it.index, i64(37))
		al_neg := collect_strings(t_ptr, it, false)
		testing.expect_value(t_ptr, len(al_neg), 3)
		testing.expect_value(t_ptr, al_neg[0], "al-37")
		testing.expect_value(t_ptr, al_neg[2], "al-39")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, al_rc, oob), nil)
			testing.expect_value(t_ptr, it.stack_len, 0)
			expect_empty_iter(t_ptr, it, "array_list_from_index oob")
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, empty_al_cur.read_cursor, 0), nil)
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "array_list_from_index empty")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "array_list_from_index .None")

		for bad in ([?]xitdb.Read_Cursor{ll_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on array_list_from_index_init error")
		}

		// 5. cursor_iterator_linked_array_list_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, ll_rc, 22), nil)
		testing.expect_value(t_ptr, it.size, i64(40))
		testing.expect_value(t_ptr, it.index, i64(22))
		ll_got := collect_strings(t_ptr, it, false)
		ll_ref_it, ll_ref_err := xitdb.cursor_iterator_linked_array_list_from_index(ll_rc, 22)
		testing.expect_value(t_ptr, ll_ref_err, nil)
		expect_slice_eq(t_ptr, ll_got, collect_strings(t_ptr, &ll_ref_it, false), "linked_array_list_from_index 22")
		testing.expect_value(t_ptr, len(ll_got), 18)
		testing.expect_value(t_ptr, ll_got[0], "ll-22")
		testing.expect_value(t_ptr, ll_got[17], "ll-39")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, ll_rc, -4), nil)
		testing.expect_value(t_ptr, it.index, i64(36))
		ll_neg := collect_strings(t_ptr, it, false)
		testing.expect_value(t_ptr, len(ll_neg), 4)
		testing.expect_value(t_ptr, ll_neg[0], "ll-36")
		testing.expect_value(t_ptr, ll_neg[3], "ll-39")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, ll_rc, oob), nil)
			testing.expect_value(t_ptr, it.stack_len, 0)
			expect_empty_iter(t_ptr, it, "linked_array_list_from_index oob")
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, empty_ll_cur.read_cursor, 0), nil)
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "linked_array_list_from_index empty")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "linked_array_list_from_index .None")

		for bad in ([?]xitdb.Read_Cursor{al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on linked_array_list_from_index_init error")
		}

		// 6. cursor_iterator_reverse_init: parity across all 8 populated collections + empty/.None/.Unexpected_Tag
		for col in all_cols {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_reverse_init(it, col.rc), nil)
			got := collect_strings(t_ptr, it, col.kv_key, reverse = true)

			ref_it, ref_err := xitdb.cursor_iterator_reverse(col.rc)
			testing.expect_value(t_ptr, ref_err, nil)
			ref := collect_strings(t_ptr, &ref_it, col.kv_key, reverse = true)

			testing.expect_value(t_ptr, len(got), col.count)
			expect_slice_eq(t_ptr, got, ref, col.prefix)
			if col.sorted {
				for i in 0 ..< len(got) {
					testing.expect_value(t_ptr, got[i], fmt.tprintf("%s%02d", col.prefix, col.count - 1 - i))
				}
			} else {
				slice.sort(got)
				for i in 0 ..< len(got) {
					testing.expect_value(t_ptr, got[i], fmt.tprintf("%s%02d", col.prefix, i))
				}
			}
		}
		for ec in empty_cols {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_reverse_init(it, ec), nil)
			expect_empty_iter(t_ptr, it, "cursor_iterator_reverse_init empty", reverse = true)
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_reverse_init(it, unwritten_rc), nil)
		expect_empty_iter(t_ptr, it, "cursor_iterator_reverse_init .None", reverse = true)

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_reverse_init(it, scalar_rc), xitdb.Xitdb_Error.Unexpected_Tag)
		testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on cursor_iterator_reverse_init error")

		// Verify forward -> reverse -> forward transitions on the exact same reused Cursor_Iterator
		testing.expect_value(t_ptr, xitdb.cursor_iterator_reverse_init(it, al_rc), nil)
		first_rev, fr_err := xitdb.cursor_iterator_prev(it)
		testing.expect_value(t_ptr, fr_err, nil)
		fr_str, _ := xitdb.cursor_read_string(first_rev.?, 64, context.temp_allocator)
		testing.expect_value(t_ptr, fr_str, "al-39")
		testing.expect_value(t_ptr, xitdb.cursor_iterator_init(it, al_rc), nil)
		first_fwd, ff_err := xitdb.cursor_iterator_next(it)
		testing.expect_value(t_ptr, ff_err, nil)
		ff_str, _ := xitdb.cursor_read_string(first_fwd.?, 64, context.temp_allocator)
		testing.expect_value(t_ptr, ff_str, "al-00")

		// 7. cursor_iterator_sorted_reverse_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, sm_rc, 15), nil)
		testing.expect_value(t_ptr, it.size, i64(40))
		testing.expect_value(t_ptr, it.index, i64(16))
		sm_ridx := collect_strings(t_ptr, it, true, reverse = true)
		sm_ridx_ref_it, sm_ridx_ref_err := xitdb.cursor_iterator_sorted_reverse_from_index(sm_rc, 15)
		testing.expect_value(t_ptr, sm_ridx_ref_err, nil)
		expect_slice_eq(t_ptr, sm_ridx, collect_strings(t_ptr, &sm_ridx_ref_it, true, reverse = true), "sorted_reverse_from_index 15")
		testing.expect_value(t_ptr, len(sm_ridx), 16)
		testing.expect_value(t_ptr, sm_ridx[0], "k-15")
		testing.expect_value(t_ptr, sm_ridx[15], "k-00")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, sm_rc, -5), nil)
		sm_rneg := collect_strings(t_ptr, it, true, reverse = true)
		testing.expect_value(t_ptr, len(sm_rneg), 36)
		testing.expect_value(t_ptr, sm_rneg[0], "k-35")
		testing.expect_value(t_ptr, sm_rneg[35], "k-00")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, ss_rc, 5), nil)
		ss_ridx := collect_strings(t_ptr, it, true, reverse = true)
		testing.expect_value(t_ptr, len(ss_ridx), 6)
		testing.expect_value(t_ptr, ss_ridx[0], "s-05")
		testing.expect_value(t_ptr, ss_ridx[5], "s-00")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, sm_rc, oob), nil)
			testing.expect_value(t_ptr, it.stack_len, 0)
			expect_empty_iter(t_ptr, it, "sorted_reverse_from_index oob", reverse = true)
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, empty_sm_cur.read_cursor, 0), nil)
		expect_empty_iter(t_ptr, it, "sorted_reverse_from_index empty", reverse = true)

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "sorted_reverse_from_index .None", reverse = true)

		for bad in ([?]xitdb.Read_Cursor{hm_rc, al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on sorted_reverse_from_index_init error")
		}

		// 8. cursor_iterator_sorted_reverse_from_key_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, sm_rc, transmute([]u8)string("k-17"), true), nil)
		sm_rkey_inc := collect_strings(t_ptr, it, true, reverse = true)
		sm_rkey_ref_it, sm_rkey_ref_err := xitdb.cursor_iterator_sorted_reverse_from_key(sm_rc, transmute([]u8)string("k-17"), true)
		testing.expect_value(t_ptr, sm_rkey_ref_err, nil)
		expect_slice_eq(t_ptr, sm_rkey_inc, collect_strings(t_ptr, &sm_rkey_ref_it, true, reverse = true), "sorted_reverse_from_key k-17")
		testing.expect_value(t_ptr, len(sm_rkey_inc), 18)
		testing.expect_value(t_ptr, sm_rkey_inc[0], "k-17")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, sm_rc, transmute([]u8)string("k-17"), false), nil)
		sm_rkey_exc := collect_strings(t_ptr, it, true, reverse = true)
		testing.expect_value(t_ptr, len(sm_rkey_exc), 17)
		testing.expect_value(t_ptr, sm_rkey_exc[0], "k-16")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, sm_rc, transmute([]u8)string("a-00"), true), nil)
		testing.expect_value(t_ptr, it.stack_len, 0)
		expect_empty_iter(t_ptr, it, "sorted_reverse_from_key before first", reverse = true)

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, empty_sm_cur.read_cursor, transmute([]u8)string("z")), nil)
		expect_empty_iter(t_ptr, it, "sorted_reverse_from_key empty", reverse = true)

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, unwritten_rc, transmute([]u8)string("z")), nil)
		expect_empty_iter(t_ptr, it, "sorted_reverse_from_key .None", reverse = true)

		for bad in ([?]xitdb.Read_Cursor{al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_sorted_reverse_from_key_init(it, bad, transmute([]u8)string("z")), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on sorted_reverse_from_key_init error")
		}

		// 9. cursor_iterator_array_list_reverse_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, al_rc, 10), nil)
		al_rev_got := collect_strings(t_ptr, it, false, reverse = true)
		al_rev_ref_it, al_rev_ref_err := xitdb.cursor_iterator_array_list_reverse_from_index(al_rc, 10)
		testing.expect_value(t_ptr, al_rev_ref_err, nil)
		expect_slice_eq(t_ptr, al_rev_got, collect_strings(t_ptr, &al_rev_ref_it, false, reverse = true), "array_list_reverse_from_index 10")
		testing.expect_value(t_ptr, len(al_rev_got), 11)
		testing.expect_value(t_ptr, al_rev_got[0], "al-10")
		testing.expect_value(t_ptr, al_rev_got[10], "al-00")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, al_rc, -1), nil)
		al_rev_all := collect_strings(t_ptr, it, false, reverse = true)
		testing.expect_value(t_ptr, len(al_rev_all), 40)
		testing.expect_value(t_ptr, al_rev_all[0], "al-39")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, al_rc, oob), nil)
			expect_empty_iter(t_ptr, it, "array_list_reverse_from_index oob", reverse = true)
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, empty_al_cur.read_cursor, 0), nil)
		expect_empty_iter(t_ptr, it, "array_list_reverse_from_index empty", reverse = true)
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "array_list_reverse_from_index .None", reverse = true)
		for bad in ([?]xitdb.Read_Cursor{ll_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_array_list_reverse_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on array_list_reverse_from_index_init error")
		}

		// 10. cursor_iterator_linked_array_list_reverse_from_index_init
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, ll_rc, 12), nil)
		ll_rev_got := collect_strings(t_ptr, it, false, reverse = true)
		ll_rev_ref_it, ll_rev_ref_err := xitdb.cursor_iterator_linked_array_list_reverse_from_index(ll_rc, 12)
		testing.expect_value(t_ptr, ll_rev_ref_err, nil)
		expect_slice_eq(t_ptr, ll_rev_got, collect_strings(t_ptr, &ll_rev_ref_it, false, reverse = true), "linked_array_list_reverse_from_index 12")
		testing.expect_value(t_ptr, len(ll_rev_got), 13)
		testing.expect_value(t_ptr, ll_rev_got[0], "ll-12")
		testing.expect_value(t_ptr, ll_rev_got[12], "ll-00")

		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, ll_rc, -38), nil)
		ll_rev_neg := collect_strings(t_ptr, it, false, reverse = true)
		testing.expect_value(t_ptr, len(ll_rev_neg), 3)
		testing.expect_value(t_ptr, ll_rev_neg[0], "ll-02")
		testing.expect_value(t_ptr, ll_rev_neg[2], "ll-00")

		for oob in ([?]i64{40, -41}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, ll_rc, oob), nil)
			expect_empty_iter(t_ptr, it, "linked_array_list_reverse_from_index oob", reverse = true)
		}
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, empty_ll_cur.read_cursor, 0), nil)
		expect_empty_iter(t_ptr, it, "linked_array_list_reverse_from_index empty", reverse = true)
		make_dirty(t_ptr, it, sm_rc)
		testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, unwritten_rc, 0), nil)
		expect_empty_iter(t_ptr, it, "linked_array_list_reverse_from_index .None", reverse = true)
		for bad in ([?]xitdb.Read_Cursor{al_rc, scalar_rc}) {
			make_dirty(t_ptr, it, sm_rc)
			testing.expect_value(t_ptr, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it, bad, 0), xitdb.Xitdb_Error.Unexpected_Tag)
			testing.expect(t_ptr, is_zeroed_iter(it), "Expected full zero reset on linked_array_list_reverse_from_index_init error")
		}

		return nil
	}

	testing.expect_value(t, xitdb.database_run_context(&db, cb, t), nil)

	// 11. Mid-walk B+Tree error rollback and sorted total == 0 fast-path (isolated DB)
	corrupt_core: xitdb.Core = xitdb.core_memory_init()
	defer _ = xitdb.core_destroy(&corrupt_core)

	corrupt_db, cdb_err := xitdb.database_init(&corrupt_core, xitdb.sha1_hasher())
	testing.expect_value(t, cdb_err, nil)

	corrupt_cb :: proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		root_map := xitdb.write_hash_map_init(cursor^) or_return
		empty_sm_cur := xitdb.hash_map_put_cursor(&root_map, "empty_sm") or_return
		_ = xitdb.write_sorted_map_init(empty_sm_cur) or_return

		sm_cur := xitdb.hash_map_put_cursor(&root_map, "sm") or_return
		sm := xitdb.write_sorted_map_init(sm_cur) or_return
		al_cur := xitdb.hash_map_put_cursor(&root_map, "al") or_return
		al := xitdb.write_array_list_init(al_cur) or_return
		ll_cur := xitdb.hash_map_put_cursor(&root_map, "ll") or_return
		ll := xitdb.write_linked_array_list_init(ll_cur) or_return
		for i in 0 ..< 40 {
			xitdb.sorted_map_put(&sm, fmt.tprintf("k-%02d", i), u64(i)) or_return
			xitdb.array_list_append(&al, fmt.tprintf("al-%02d", i)) or_return
			xitdb.linked_array_list_append(&ll, fmt.tprintf("ll-%02d", i)) or_return
		}
		return nil
	}
	testing.expect_value(t, xitdb.database_run_context(&corrupt_db, corrupt_cb, nil), nil)

	root_rc := xitdb.database_root_cursor(&corrupt_db).read_cursor
	root_hm, rhm_err := xitdb.read_hash_map_init(root_rc)
	testing.expect_value(t, rhm_err, nil)

	empty_sm_maybe, esm_err := xitdb.hash_map_get_cursor(root_hm, "empty_sm")
	testing.expect_value(t, esm_err, nil)
	empty_sm_rc := empty_sm_maybe.?
	empty_sm_slot, ess_err := xitdb.cursor_slot(empty_sm_rc)
	testing.expect_value(t, ess_err, nil)

	sm_maybe, sm_err := xitdb.hash_map_get_cursor(root_hm, "sm")
	testing.expect_value(t, sm_err, nil)
	c_sm_rc := sm_maybe.?
	c_sm_slot, css_err := xitdb.cursor_slot(c_sm_rc)
	testing.expect_value(t, css_err, nil)

	al_maybe, al_err := xitdb.hash_map_get_cursor(root_hm, "al")
	testing.expect_value(t, al_err, nil)
	c_al_rc := al_maybe.?
	c_al_slot, cas_err := xitdb.cursor_slot(c_al_rc)
	testing.expect_value(t, cas_err, nil)

	ll_maybe, ll_err := xitdb.hash_map_get_cursor(root_hm, "ll")
	testing.expect_value(t, ll_err, nil)
	c_ll_rc := ll_maybe.?
	c_ll_slot, cls_err := xitdb.cursor_slot(c_ll_rc)
	testing.expect_value(t, cls_err, nil)

	cm := &corrupt_core.(xitdb.Core_Memory)

	// Point empty_sm's root_ptr at an out-of-bounds offset: total == 0 fast-path avoids dereferencing root_ptr
	endian.put_u64(cm.buf[empty_sm_slot.value + 8 : empty_sm_slot.value + 16], .Big, 999_999)

	is_zeroed :: proc(it: ^xitdb.Cursor_Iterator) -> bool {
		for b in mem.ptr_to_bytes(it) {
			if b != 0 {
				return false
			}
		}
		return true
	}

	it_iso := new(xitdb.Cursor_Iterator)
	defer free(it_iso)

	// Dirty it_iso on c_sm_rc first, then verify empty_sm total == 0 fast-path succeeds
	testing.expect_value(t, xitdb.cursor_iterator_init(it_iso, c_sm_rc), nil)
	_, _ = xitdb.cursor_iterator_next(it_iso)

	testing.expect_value(t, xitdb.cursor_iterator_sorted_from_key_init(it_iso, empty_sm_rc, transmute([]u8)string("a")), nil)
	c_fast, cf_err := xitdb.cursor_iterator_next(it_iso)
	testing.expect_value(t, cf_err, nil)
	testing.expect(t, c_fast == nil, "Expected nil from empty Sorted_Map fast-path")

	testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_key_init(it_iso, empty_sm_rc, transmute([]u8)string("z")), nil)
	cr_fast, crf_err := xitdb.cursor_iterator_prev(it_iso)
	testing.expect_value(t, crf_err, nil)
	testing.expect(t, cr_fast == nil, "Expected nil from empty Sorted_Map reverse fast-path")

	// Corrupt all child leaf nodes under c_sm_rc's B+Tree branch root so mid-walk fails after stack_len >= 1
	root_ptr_val, _ := endian.get_u64(cm.buf[c_sm_slot.value + 8 : c_sm_slot.value + 16], .Big)
	branch_off := int(root_ptr_val)
	branch_num := int(cm.buf[branch_off + 1])
	testing.expect(t, cm.buf[branch_off] == 1 && branch_num > 0, "Expected multi-tier B+Tree branch root")
	for j in 0 ..< branch_num {
		slot_off := branch_off + xitdb.BTREE_NODE_HEADER_SIZE + j * xitdb.SLOT_LENGTH
		child_slot, cs_err := xitdb.slot_from_slice(cm.buf[slot_off : slot_off + xitdb.SLOT_LENGTH])
		testing.expect_value(t, cs_err, nil)
		cm.buf[child_slot.value] = 0xFF
	}

	// Re-dirty it_iso via an Array_List? No, c_sm_rc's branch root itself is still intact at level 0,
	// or dirty it_iso via cursor_iterator_sorted_from_index_init's outer loop itself (`stack_len` becomes 1 before leaf fail).
	// Still pre-fill it_iso with non-zero bytes to prove both pre-existing dirty bytes AND mid-walk branch stack are wiped!
	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_sorted_from_index_init(it_iso, c_sm_rc, 25), xitdb.Xitdb_Error.Invalid_BTree_Node_Kind)
	testing.expect(t, is_zeroed(it_iso), "Expected full zero rollback on mid-walk sorted_from_index_init failure")

	val_it, val_err := xitdb.cursor_iterator_sorted_from_index(c_sm_rc, 25)
	testing.expect_value(t, val_err, xitdb.Xitdb_Error.Invalid_BTree_Node_Kind)
	testing.expect(t, is_zeroed(&val_it), "Expected full zero rollback on value-returning cursor_iterator_sorted_from_index failure")

	// Corrupt interior radix slot 1 in c_al_rc (tag .None, value 0) -> must return .Unexpected_Tag without reading offset 0
	al_root_ptr_val, _ := endian.get_u64(cm.buf[c_al_slot.value + 8 : c_al_slot.value + 16], .Big)
	mem.zero(&cm.buf[int(al_root_ptr_val) + xitdb.SLOT_LENGTH], xitdb.SLOT_LENGTH)

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_array_list_from_index_init(it_iso, c_al_rc, 20), xitdb.Xitdb_Error.Unexpected_Tag)
	testing.expect(t, is_zeroed(it_iso), "Expected full zero rollback on corrupt interior Array_List slot (forward)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_array_list_reverse_from_index_init(it_iso, c_al_rc, 20), xitdb.Xitdb_Error.Unexpected_Tag)
	testing.expect(t, is_zeroed(it_iso), "Expected full zero rollback on corrupt interior Array_List slot (reverse)")

	al_val_it, al_val_err := xitdb.cursor_iterator_array_list_from_index(c_al_rc, 20)
	testing.expect_value(t, al_val_err, xitdb.Xitdb_Error.Unexpected_Tag)
	testing.expect(t, is_zeroed(&al_val_it), "Expected full zero rollback on value-returning cursor_iterator_array_list_from_index failure")

	// Zero all branch child slots in c_sm_rc and c_ll_rc -> all 6 B-Tree descending initializers must reject with .Invalid_BTree_Node
	for j in 0 ..< branch_num {
		mem.zero(&cm.buf[branch_off + xitdb.BTREE_NODE_HEADER_SIZE + j * xitdb.SLOT_LENGTH], xitdb.SLOT_LENGTH)
	}
	ll_root_ptr_val, _ := endian.get_u64(cm.buf[c_ll_slot.value + 8 : c_ll_slot.value + 16], .Big)
	ll_branch_off := int(ll_root_ptr_val)
	ll_branch_num := int(cm.buf[ll_branch_off + 1])
	testing.expect(t, cm.buf[ll_branch_off] == 1 && ll_branch_num > 0, "Expected multi-tier Linked_Array_List branch root")
	for j in 0 ..< ll_branch_num {
		mem.zero(&cm.buf[ll_branch_off + xitdb.BTREE_NODE_HEADER_SIZE + j * xitdb.SLOT_LENGTH], xitdb.SLOT_LENGTH)
	}

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_sorted_from_index_init(it_iso, c_sm_rc, 25), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Sorted_Map branch slot (from_index)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_sorted_from_key_init(it_iso, c_sm_rc, transmute([]u8)string("k-25")), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Sorted_Map branch slot (from_key)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_index_init(it_iso, c_sm_rc, 25), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Sorted_Map branch slot (reverse_from_index)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_sorted_reverse_from_key_init(it_iso, c_sm_rc, transmute([]u8)string("k-25")), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Sorted_Map branch slot (reverse_from_key)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_from_index_init(it_iso, c_ll_rc, 25), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Linked_Array_List branch slot (from_index)")

	mem.set(it_iso, 0xAA, size_of(xitdb.Cursor_Iterator))
	testing.expect_value(t, xitdb.cursor_iterator_linked_array_list_reverse_from_index_init(it_iso, c_ll_rc, 25), xitdb.Xitdb_Error.Invalid_BTree_Node)
	testing.expect(t, is_zeroed(it_iso), "Expected zero rollback on corrupt Linked_Array_List branch slot (reverse_from_index)")
}

// ----------------------------------------------------------------------------
// Scenario 43: Zero-Copy Copy-on-Write Overlay Forks (`Core_Overlay`)
// ----------------------------------------------------------------------------

@(test)
spec_copy_on_write_overlay_fork_shares_parent_bytes_and_isolates_both_sides :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN a parent with ~64 KiB of committed history (a 1,000-entry sorted map)
	N :: 1_000
	entries := make([]Key_Uint, N, context.temp_allocator)
	for i in 0 ..< N {
		entries[i] = Key_Uint{key = fmt.tprintf("user-%05d", i), val = u64(i)}
	}
	given_committed_moment(&ctx, Op_Put_Sorted_Map{key = "users", entries = entries[:]}, Op_Put_String{key = "owner", val = "parent"})

	// WHEN the parent is forked onto a copy-on-write overlay
	upon_forking_primary_onto_copy_on_write_overlay(&ctx)

	// THEN the fork sees the parent's full history without copying it
	then_history_has_moments(&ctx, 1, on = .Fork)
	then_moment_has_string(&ctx, 0, "owner", "parent", on = .Fork)
	then_moment_has_sorted_map_in_order(&ctx, 0, "users", N)

	// WHEN the parent commits first (rewriting its root header in place)
	upon_committing_moment_on(&ctx, .Primary, Op_Put_String{key = "owner", val = "parent-v2"})

	// THEN the fork still sees exactly the forked history: its header page was snapshotted at fork time
	then_history_has_moments(&ctx, 1, on = .Fork)
	then_moment_has_string(&ctx, 0, "owner", "parent", on = .Fork)

	// WHEN the fork then commits on top of its own view
	upon_committing_moment_on(&ctx, .Fork, Op_Put_String{key = "owner", val = "fork"})

	// THEN neither side sees the other's commit
	then_history_has_moments(&ctx, 2, on = .Fork)
	then_history_has_moments(&ctx, 2, on = .Primary)
	then_moment_has_string(&ctx, 1, "owner", "fork",      on = .Fork)
	then_moment_has_string(&ctx, 1, "owner", "parent-v2", on = .Primary)
	then_moment_has_string(&ctx, 0, "owner", "parent",    on = .Fork)

	// AND the fork owns only its header page plus the bytes it appended, not the parent's history
	then_fork_owns_at_most_bytes(&ctx, max_owned = 8 * 1024, primary_at_least = 32 * 1024)
}

// ----------------------------------------------------------------------------
// Scenario 44: Structural Byte-Key Collection Diff (`diff_collection`)
// ----------------------------------------------------------------------------

@(test)
spec_structural_collection_diff_reports_byte_keys_across_hamt_and_bplus_trees :: proc(t: ^testing.T) {
	ctx := driver_init_ctx(t)
	defer driver_destroy_ctx(&ctx)

	given_in_memory_database(&ctx)

	// GIVEN multi-level HAMT and B+Tree collections with 600 entries each
	N :: 600
	entries := make([]Key_Uint, N, context.temp_allocator)
	for i in 0 ..< N {
		entries[i] = Key_Uint{key = fmt.tprintf("k-%04d", i), val = u64(i)}
	}
	given_committed_moment(
		&ctx,
		Op_Put_Counted_Map{key = "hm", entries = entries[:]},
		Op_Put_Sorted_Map{key = "sm", entries = entries[:]},
	)

	// WHEN moment 1 updates 2 values, removes 2 keys, and adds 2 keys in both collections
	updates := [?]Key_Uint{
		{key = "k-0007", val = 7_000},
		{key = "k-0412", val = 412_000},
		{key = "n-0001", val = 1},
		{key = "n-0002", val = 2},
	}
	drops := [?]string{"k-0100", "k-0599"}
	upon_committing_moment_on(
		&ctx, .Primary,
		Op_Put_Counted_Map{key = "hm", entries = updates[:]},
		Op_Remove_Counted_Map{key = "hm", keys_to_drop = drops[:]},
		Op_Put_Sorted_Map{key = "sm", entries = updates[:]},
		Op_Remove_Sorted_Map{key = "sm", keys_to_drop = drops[:]},
	)

	// THEN both structures report exactly those 6 keys with their raw bytes
	expected := []string{"+n-0001", "+n-0002", "-k-0100", "-k-0599", "~k-0007", "~k-0412"}
	then_collection_diff_equals(&ctx, 0, 1, "hm", expected)
	then_collection_diff_equals(&ctx, 0, 1, "sm", expected)

	// AND agree with a full scan of both versions, in both directions
	then_collection_diff_matches_full_scan(&ctx, 0, 1, "hm", expected_count = 6)
	then_collection_diff_matches_full_scan(&ctx, 0, 1, "sm", expected_count = 6)
	then_collection_diff_matches_full_scan(&ctx, 1, 0, "sm", expected_count = 6)

	// AND identical versions produce no changes, while a missing collection reports everything as added
	then_collection_diff_equals(&ctx, 1, 1, "sm", []string{})
	then_collection_diff_matches_full_scan(&ctx, 0, 1, "absent", expected_count = 0)

	// AND diffs work across a copy-on-write fork that rewrote part of the tree
	upon_forking_primary_onto_copy_on_write_overlay(&ctx)
	more := [?]Key_Uint{{key = "k-0300", val = 300_000}}
	upon_committing_moment_on(&ctx, .Fork, Op_Put_Sorted_Map{key = "sm", entries = more[:]})
	then_collection_diff_equals(&ctx, 1, 2, "sm", []string{"~k-0300"}, on = .Fork)
}
