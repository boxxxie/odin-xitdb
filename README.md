# xitdb for Odin

[![CI](https://github.com/boxxxie/odin-xitdb/actions/workflows/ci.yml/badge.svg)](https://github.com/boxxxie/odin-xitdb/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-v0.1.0-blue.svg)](README.md)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09%2B-3882D2.svg)](https://odin-lang.org)
[![Format](https://img.shields.io/badge/xitdb-v1%20wire%20format-5C6BC0.svg)](https://github.com/radarroark/xitdb)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

An immutable, persistent, single-file structural database written in pure Odin. Wire-compatible with [xitdb](https://github.com/radarroark/xitdb) v1 (Zig, Go, Java, Clojure) with zero external dependencies.

Unlike flat key-value stores that force you to serialize objects into opaque blobs, **xitdb** lets you nest maps, sorted B+Trees, radix tries, sets, scalars, and streaming byte arrays directly on disk. Every transaction appends a new root snapshot ("moment") using structural sharing, giving you instant time-travel queries, zero-copy collection cloning, and lock-free reads of historical state.

---

## Why xitdb?

* **Built-In 5-Layer DSL & Datalog Engine**: Query and mutate nested collections using string path selectors (`@-1.users["101"].age`), Datomic-style transactions with reified `__tx` metadata and change tracking, native Odin struct `marshal`/`unmarshal` tags, Datomic `pull` projections, $O(1)$ structural diffs (`diff_moments`, `history_of`), and a Datalog engine with automatic B+Tree prefix pushdown, grouped aggregations (`count`, `sum`, `min`, `max`), and cycle-safe transitive `reach`.
* **True Time-Travel & Branching History**: Database state is modeled as an append-only list of immutable moments. Mutating a collection in a new transaction shares unchanged subtrees with prior moments and only writes modified paths.
* **Fast Intra-Transaction In-Place Writes**: While historical moments are strictly immutable, nodes allocated *within* the active transaction are mutated in place until the transaction commits or is explicitly frozen.
* **Rich Composable Collections**: Nest `Hash_Map`, `Counted_Hash_Map`, `Sorted_Map`, `Array_List`, `Linked_Array_List`, `Hash_Set`, `Counted_Hash_Set`, and `Sorted_Set` to arbitrary depth without manual serialization.
* **Crash-Safe Without a WAL**: Transactions commit by writing a `Root_Trailer` (verified by a `CRC-64/XZ` checksum over the file ID, offset, root slot, and commit ID) followed by updating the `Root_Header`. Unfinished writes from a power loss or crash are ignored on open and automatically truncated on the next write.
* **Incremental Log Replication**: Sync a primary database to replicas by streaming only the committed byte range since the replica's last verified trailer checksum.
* **Garbage-Collecting Compaction**: Prune old moments and compact the database into a fresh file or memory buffer using an in-memory or disk-backed offset map. Shared subtrees (DAGs) and even cyclic references are preserved.
* **Performance-Tuned Odin Implementation**:
  * Automatic x86 SHA-NI hardware acceleration for SHA-1 and SHA-256 (with runtime CPUID detection and pure-Odin fallback).
  * Zero-allocation tree traversal via stack-allocated `Cursor_Iterator` and caller-supplied buffer reads (`cursor_read_bytes_buf`).
  * Inline `Short_Bytes` slot encoding—strings and byte slices $\le 8$ bytes (or $\le 6$ bytes with a 2-byte format tag) are stored directly inside the 9-byte `Slot` with zero heap/disk indirection.

---

## Installation

Copy the `xitdb` directory into your Odin project and import it:

```odin
import "xitdb"
```

Requires the Odin compiler (`core:*` and `base:*` libraries only; no C dependencies).

---

## Quick Start

In `xitdb`, the idiomatic pattern is to use a top-level `Array_List` at the database root, where each element is a `Hash_Map` representing a point-in-time snapshot ("moment") of your database.

```odin
package main

import "core:fmt"
import "xitdb"

main :: proc() {
	// 1. Open a buffered file database (or use xitdb.core_memory_init() for in-memory)
	core, open_err := xitdb.core_buffered_file_open("app.xit", 2 * 1024 * 1024)
	assert(open_err == nil)
	defer xitdb.core_destroy(&core, close_file = true)

	db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
	assert(init_err == nil)

	// 2. Commit Moment 0 (genesis transaction)
	rc := xitdb.database_root_cursor(&db)
	history, _ := xitdb.write_array_list_init(rc)

	tx0_err := xitdb.array_list_append_context(&history, xitdb.Slot{}, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&moment, "version", u64(1)) or_return

		fruits_cur := xitdb.hash_map_put_cursor(&moment, "fruits") or_return
		fruits := xitdb.write_array_list_init(fruits_cur) or_return
		xitdb.array_list_append(&fruits, "apple") or_return
		xitdb.array_list_append(&fruits, "pear") or_return
		xitdb.array_list_append(&fruits, "grape") or_return
		return nil
	})
	assert(tx0_err == nil)

	// 3. Branch Moment 1 from Moment 0 (-1 = latest moment) and mutate
	latest_slot, _ := xitdb.array_list_get_slot(history, -1)
	tx1_err := xitdb.array_list_append_context(&history, latest_slot.?, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
		moment := xitdb.write_hash_map_init(cursor^) or_return
		xitdb.hash_map_put(&moment, "version", u64(2)) or_return

		fruits_cur := xitdb.hash_map_put_cursor(&moment, "fruits") or_return
		fruits := xitdb.write_array_list_init(fruits_cur) or_return
		xitdb.array_list_put(&fruits, 0, "lemon") or_return // replace "apple" -> "lemon"
		xitdb.array_list_slice(&fruits, 2) or_return        // truncate to ["lemon", "pear"]
		return nil
	})
	assert(tx1_err == nil)

	// 4. Time-travel read: inspect Moment 0 and Moment 1 side-by-side
	m0_cur, _ := xitdb.array_list_get_cursor(history, 0)
	m0, _ := xitdb.read_hash_map_init(m0_cur.?)
	m0_fruits_cur, _ := xitdb.hash_map_get_cursor(m0, "fruits")
	m0_fruits, _ := xitdb.read_array_list_init(m0_fruits_cur.?)
	m0_first, _ := xitdb.array_list_get_cursor(m0_fruits, 0)
	str0, _ := xitdb.cursor_read_string(m0_first.?, 64, context.temp_allocator)

	m1_cur, _ := xitdb.array_list_get_cursor(history, 1)
	m1, _ := xitdb.read_hash_map_init(m1_cur.?)
	m1_fruits_cur, _ := xitdb.hash_map_get_cursor(m1, "fruits")
	m1_fruits, _ := xitdb.read_array_list_init(m1_fruits_cur.?)
	m1_first, _ := xitdb.array_list_get_cursor(m1_fruits, 0)
	str1, _ := xitdb.cursor_read_string(m1_first.?, 64, context.temp_allocator)

	fmt.printf("Moment 0 fruits[0] = %q\n", str0) // "apple"
	fmt.printf("Moment 1 fruits[0] = %q\n", str1) // "lemon"
}
```

---

## Data Structures & Complexity

All collections are persistent, structural-sharing trees built from 9-byte `Slot` pointers.

| Collection | Backing Structure | Lookup | Insert / Update | Remove | Count | Key Highlights |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`Array_List`** | 16-way Radix Trie | $O(\log_{16} N)$ | $O(\log_{16} N)$ | Slice tail: $O(\log_{16} N)$ | $O(1)$ | Fast indexed array, append, tail-slice, and negative indexing (`-1`). |
| **`Linked_Array_List`** | Count-Augmented B-Tree | $O(\log_{16} N)$ | $O(\log_{16} N)$ anywhere | $O(\log_{16} N)$ anywhere | $O(1)$ | Supports mid-list `insert`, `remove`, arbitrary `(offset, size)` slicing, and $O(\log N)$ `concat`. |
| **`Hash_Map`** | 16-way HAMT | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(\log_{16} N)$ | — | Keyed by `string`, `[]u8`, or raw digest. Automatically collapses branches on removal. |
| **`Counted_Hash_Map`** | 16-way HAMT + Header | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(1)$ | Same as `Hash_Map` while maintaining an exact $O(1)$ entry count. |
| **`Hash_Set`** / **`Counted_Hash_Set`** | 16-way HAMT | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(\log_{16} N)$ | — / $O(1)$ | Set membership over strings, byte slices, or precomputed hashes. |
| **`Sorted_Map`** | Count-Augmented B+Tree | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(1)$ | Lexicographical key order, $O(\log N)$ `rank`, $O(\log N)$ lookup by positional index, and range iterators. |
| **`Sorted_Set`** | Count-Augmented B+Tree | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(\log_{16} N)$ | $O(1)$ | Ordered unique keys with `rank`, positional index access, and lower-bound iteration. |

### Scalar & Byte Types

Any collection slot can store:
* **`u64` / `xitdb.Uint`**: Unsigned 64-bit integer (stored inline in the 9-byte slot).
* **`i64` / `xitdb.Int`**: Signed 64-bit integer (stored inline).
* **`f64` / `xitdb.Float`**: IEEE-754 64-bit float (stored inline).
* **`string` / `[]u8` / `xitdb.Bytes`**:
  * Payloads without null bytes up to 8 bytes (or up to 6 bytes with a 2-byte `format_tag`) are stored inline as `.Short_Bytes`.
  * Larger payloads or payloads containing `0x00` are stored as `.Bytes` on the heap log and support streaming reads/writes.
* **`xitdb.Slot`**: Any collection or value slot can be written into another slot to clone or link subtrees in $O(1)$ time.

---

## Core Patterns & Recipes

### 1. Secondary Indexing, Pagination & Prefix Autocomplete (`Sorted_Map`)

Because `Sorted_Map` is backed by a count-augmented B+Tree, it supports both **lexicographical lower-bound iteration** (`sorted_map_iterator_from_string`) and **$O(\log N)$ positional offset iteration** (`sorted_map_iterator_from_index`):

```odin
// Paginate 20 users starting at page 3 (offset 60) in O(log N) time:
it, _ := xitdb.sorted_map_iterator_from_index(username_idx, 20 * 3)
for i := 0; i < 20; i += 1 {
	cur_maybe, _ := xitdb.cursor_iterator_next(&it)
	cur, ok := cur_maybe.?
	if !ok do break

	kv, _ := xitdb.cursor_read_kv_pair(cur, context.temp_allocator)
	username, _ := xitdb.cursor_read_string(kv.key_cursor, 128, context.temp_allocator)
	user_id, _  := xitdb.cursor_read_string(kv.value_cursor, 64, context.temp_allocator)
}

// Prefix autocomplete for usernames starting with "da":
prefix_it, _ := xitdb.sorted_map_iterator_from_string(username_idx, "da")
for {
	cur_maybe, _ := xitdb.cursor_iterator_next(&prefix_it)
	cur, ok := cur_maybe.?
	if !ok do break

	kv, _ := xitdb.cursor_read_kv_pair(cur, context.temp_allocator)
	username, _ := xitdb.cursor_read_string(kv.key_cursor, 128, context.temp_allocator)
	if !strings.has_prefix(username, "da") do break
	// match!
}
```

### 2. Zero-Copy Collection Cloning & `cursor_freeze`

To clone any collection across transactions, simply read its `Slot` and write it under a new key. If you clone a collection *within the same transaction* and want subsequent mutations on the clone to leave the original untouched, call `xitdb.cursor_freeze(&clone_cursor)` before mutating:

```odin
orig_slot, _ := xitdb.array_list_slot(cities_list.read_array_list)
xitdb.hash_map_put(&moment, "More-Cities", orig_slot) or_return

clone_cur := xitdb.hash_map_put_cursor(&moment, "More-Cities") or_return
xitdb.cursor_freeze(&clone_cur) or_return // isolate clone from in-place edits

more_cities := xitdb.write_array_list_init(clone_cur) or_return
xitdb.array_list_append(&more_cities, "Tokyo") or_return
```

You can also call `xitdb.database_freeze(cursor.db)` mid-transaction to freeze *everything* written so far in the transaction. Frozen data even survives if a later step in the transaction aborts.

### 3. Streaming Large Blobs & Random-Access Seek

Avoid buffering large payloads in memory by streaming directly to and from the database with `Cursor_Writer` and `Cursor_Reader`:

```odin
// Streaming write (with optional 2-byte format tag)
blob_cur := xitdb.hash_map_put_cursor(&moment, "report") or_return
writer := xitdb.cursor_writer(&blob_cur) or_return
writer.format_tag = transmute([]u8)string("md")
_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("# Title\n"))
_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("Body paragraph..."))
xitdb.cursor_writer_finish(&writer) or_return

// Streaming read with random-access seek
reader, _ := xitdb.cursor_reader(blob_cur.read_cursor)
xitdb.cursor_reader_seek_to(&reader, 8)
buf: [64]u8
n, _ := xitdb.cursor_reader_read(&reader, buf[:])
```

### 4. Incremental Log Replication

Replicating from a primary `Database` to a secondary replica requires no special server process—just ship the byte slice returned by `database_read_committed_bytes`:

```odin
// 1. Replica reports its current committed size + trailer CRC64
rep_state, _ := xitdb.database_replica_state(&replica_db)

// 2. Primary determines start offset (returns rep_state.committed_size for delta sync,
//    or 0 if the replica diverged or the primary was compacted)
start_offset, _ := xitdb.database_replication_start(&primary_db, rep_state)
end_offset, _   := xitdb.database_committed_size(&primary_db)

// 3. Read committed delta bytes from primary and apply to replica
delta, _ := xitdb.database_read_committed_bytes(&primary_db, start_offset, end_offset, context.temp_allocator)
xitdb.database_apply_replicated_bytes(&replica_db, start_offset, delta)
```

### 5. History Pruning & Compaction

To reclaim disk space from old historical moments, slice your history list to retain the latest $K$ moments and compact into a new `Core`:

```odin
// Retain only the latest moment
rc := xitdb.database_root_cursor(&db)
history, _ := xitdb.write_array_list_init(rc)
xitdb.array_list_slice(&history, 1)

// Compact into a new target Core (uses Memory_Offset_Map by default,
// or pass a File_Offset_Map to bound RAM usage on multi-GB databases)
compacted_core, _ := xitdb.core_file_open("app.compact.xit", {.Read, .Write, .Create, .Trunc})
compacted_db, _   := xitdb.database_compact(&db, &compacted_core)
```

---

## 5-Layer DSL & Datalog Engine (`xitdb/dsl.odin`)

On top of the low-level cursor API, `xitdb` includes a zero-dependency 5-layer DSL that compiles down to `read_slot_pointer` and `[]Path_Part`. See [`DSL.md`](DSL.md) for the complete reference guide.

### Layer 1: String Path Selectors & Combinators (`select_cursor`, `get_uint`, `read_steps_cursor`)

Sigils select the exact collection type at each hop, prefixed by an optional `@moment` (`@-1` for latest, `@0` for genesis, etc.):

| Sigil | Collection Type | Example Path |
| :--- | :--- | :--- |
| `.key` or `["key"]` | `Hash_Map` (HAMT) | `@-1.users["101"].age` |
| `#key` or `#["key"]` | `Counted_Hash_Map` | `@-1.#metrics.views` |
| `$key` or `$["key"]` | `Sorted_Map` (B+Tree) | `@-1.$catalog["apple"]` |
| `[0]` / `[-1]` | `Array_List` (Radix Trie) | `@-1.fruits[-1]` |
| `[[0]]` | `Linked_Array_List` (Counted B-Tree) | `@-1.todos[[0]]` |
| `%m` / `#%m` / `^m` | `Hash_Set` / `Counted_Hash_Set` / `Sorted_Set` | `@-1.users["101"].roles%"admin"` |

```odin
// Direct typed reads from any moment using string selectors:
age, _     := xitdb.get_uint(&db, `@-1.users["101"].age`)       // -> 26
old_age, _ := xitdb.get_uint(&db, `@0.users["101"].age`)        // -> 25 (historical read!)
price, _   := xitdb.get_float(&db, `@-1.$catalog["apple"]`)     // -> 1.25 (B+Tree Sorted_Map)
views, _   := xitdb.get_uint(&db, `@-1.#metrics.views`)         // -> 999  (Counted_Hash_Map)
todo, _    := xitdb.get_string(&db, `@-1.todos[[1]]`)           // -> "ship v1" (Linked_Array_List)

// Or compile-time zero-parse combinators:
cur, _ := xitdb.read_steps_cursor(
	xitdb.moment_cursor(&db, -1),
	[]xitdb.Path_Step{xitdb.hm("users"), xitdb.hm("101"), xitdb.hm("age")},
)
```

### Layer 2: Datomic-Style Transactions (`Tx`) & Declarative Script DSL (`transact_script`)

You can use either the programmatic `Tx` builder (with automatic B+Tree secondary index maintenance via `tx_index_on`) or run a declarative multi-line transaction script via `transact_script`:

```odin
// 1. Declarative Transaction Script (with doc, metadata, zero-copy fork, savepoint, and Linked_Array_List splice):
rep, _ := xitdb.transact_script(&db, `
	branch @-1 {
		doc "Promote dan, snapshot fruits, and insert middle todo"
		instant 1700000500
		meta "author" = "paul"
		meta "ticket" = 42u

		fork .fruits -> .backup_fruits
		savepoint

		put .users["101"].age = 26u
		put .fruits[0] = "lemon"
		append .fruits = "grape"
		insert .todos[[1]] = "write docs"
	}
`)
defer xitdb.tx_report_destroy(&rep)

// Every commit automatically reifies `__tx` metadata inside the moment itself:
author, _ := xitdb.get_string(&db, "@-1.__tx.author") // -> "paul"
doc, _    := xitdb.get_string(&db, "@-1.__tx.doc")    // -> "Promote dan, snapshot fruits..."

// 2. Programmatic Tx with Automatic B+Tree Secondary Index Maintenance:
tx, _ := xitdb.tx_begin(&db, -1, record_tx_meta = true, compute_diff = true)
xitdb.tx_index_on(&tx, "users", "username", "username->id") // keeps Sorted_Map "$username->id" synced!
xitdb.tx_put(&tx, `.users["101"].username`, "dan")
xitdb.tx_put(&tx, `.users["101"].age`, u64(25))
rep2, _ := xitdb.tx_commit(&tx)
```

### Layer 3: Odin Struct Tag Reflection (`marshal`, `unmarshal`) & Datomic `pull`

Map native Odin structs directly to heterogeneous `xitdb` collections using struct tags, or project arbitrary subtrees with `pull`:

```odin
Workspace_State :: struct {
	project: string             `xitdb:"project"`,
	version: u64                `xitdb:"version"`,
	bio:     string             `xitdb:"bio,tag=md"`, // Stored with 2-byte format_tag "md"
	todos:   []string           `xitdb:"[[todos]]"`,  // Stored as Linked_Array_List!
	tags:    []string           `xitdb:"^tags"`,      // Stored as B+Tree Sorted_Set!
	catalog: map[string]f64     `xitdb:"$catalog"`,   // Stored as B+Tree Sorted_Map!
	metrics: map[string]u64     `xitdb:"#metrics"`,   // Stored as Counted_Hash_Map!
	secret:  string             `xitdb:"-"`,          // Ignored
}

// Marshal / Unmarshal at any cursor:
xitdb.marshal(&workspace_cursor, state)
restored, _ := xitdb.unmarshal(Workspace_State, workspace_cursor.read_cursor, context.temp_allocator)

// Or run a Datomic-style `pull` projection with slice bounds:
proj, _ := xitdb.pull(rep.after.cursor, "{.workspace{project, version, todos[0..2], ^tags}}")
defer xitdb.pull_destroy(&proj)

ws_view    := xitdb.pull_get(proj, "workspace")
proj_name  := xitdb.pull_get(ws_view, "project").str         // -> "xitdb-dsl"
first_todo := xitdb.pull_get(ws_view, "todos").items[0].str  // -> "design"
```

### Layer 4: $O(1)$ Structural Diffs (`diff_moments`), Lineage (`history_of`) & B+Tree Range Queries

Because `xitdb` is copy-on-write, unchanged subtrees share identical 9-byte `Slot` values (`tag + offset`) and are skipped in $O(1)$ time during diffs:

```odin
// 1. Structural diff between genesis (@0) and latest (@-1):
diffs, _ := xitdb.diff_moments(&db, moment_a = 0, moment_b = -1)
for d in diffs {
	// e.g. path=".users[\"101\"].age", op=.Put, old_val=25, new_val=26
}

// 2. Full audit lineage of a single path across all moments:
hist, _ := xitdb.history_of(&db, `.users["101"].age`)
for entry in hist {
	// entry.moment_idx, entry.tx_instant, entry.tx_doc, entry.val (25 -> 26 -> 27)
}

// 3. Secondary index B+Tree prefix scan & O(log N) rank count:
da_users, _ := xitdb.query_prefix(rep.after, "username->id", "da")            // -> [("dan", "101"), ("dave", "102")]
count, _    := xitdb.query_count_range(rep.after, "username->id", "da", "dz") // O(log N) via sorted_map_rank!
```

### Layer 5: Structural & Temporal Datalog Engine (`query_datalog`)

Unify logic variables (`?var`) across maps, B+Trees, lists, sets, and historical moments (`@0`, `@?m`), with automatic B+Tree prefix pushdown, grouped aggregations, and cycle-safe graph traversal (`reach`):

#### A. B+Tree Prefix Pushdown, Set Negation (`not`) & Temporal Joins (`@0`)
```odin
res, _ := xitdb.query_datalog(&db, `
	find ?name, ?id, ?old_age, ?new_age
	where
		$username->id[?name] = ?id
		starts_with(?name, "da")
		.users[?id].age = ?new_age
		@0.users[?id].age = ?old_age
		?new_age > ?old_age
		.users[?id].roles%"admin"
		not .users[?id].roles%"suspended"
`)
defer xitdb.datalog_result_destroy(&res)
// B+Tree seeks directly to "da" via sorted_map_iterator_from_string,
// then performs point lookups on .users[?id] and @0.users[?id]!
```

#### B. Grouped & Global Aggregations (`count`, `sum`, `min`, `max`)
```odin
// Non-aggregate variables (?dept) automatically form the GROUP BY key:
aggs, _ := xitdb.query_datalog(&db, `
	find ?dept, count(?id), min(?age), max(?age), sum(?age)
	where
		.users[?id].dept = ?dept
		.users[?id].age = ?age
		not .users[?id].roles%"suspended"
`)
defer xitdb.datalog_result_destroy(&aggs)

for i in 0 ..< len(aggs.rows) {
	dept, _  := xitdb.datalog_row_get(aggs, i, "?dept")
	cnt, _   := xitdb.datalog_row_get(aggs, i, "count(?id)")
	total, _ := xitdb.datalog_row_get(aggs, i, "sum(?age)")
}
```

#### C. Cycle-Safe Transitive Graph Traversal (`reach` with Shortest-Path Hop Depth)
```odin
// Traverses `.follows[?u]%?v` (or any Map/Set/List edge) via BFS with cycle detection,
// binding `?hops` to the shortest-path hop distance (1, 2, 3, ...):
reach_res, _ := xitdb.query_datalog(&db, `
	find ?peer, ?hops
	where
		?start == "alice"
		reach(?start, ?peer, ?hops, .follows[?u]%?v)
		.users[?peer].active = true
`)
defer xitdb.datalog_result_destroy(&reach_res)
```

---

## CLI & Interactive REPL (`cmd/xit/main.odin`)

`xitdb` ships with a standalone CLI and interactive REPL (`cmd/xit`) that exposes all 5 layers of the DSL plus database inspection and compaction:

```bash
# Build the standalone binary
odin build cmd/xit -out:xit -o:speed

# 1. Commit a declarative transaction block from the CLI
./xit tx app.xit '
branch none {
    doc "Initial user directory"
    meta "author" = "paul"
    put .users["101"].username = "dan"
    put .users["101"].dept = "eng"
    put .users["101"].age = 28u
    put .users["102"].username = "alice"
    put .users["102"].dept = "eng"
    put .users["102"].age = 40u
}
'

# 2. Run a Datalog aggregation query from the CLI
./xit query app.xit 'find ?dept, count(?id), sum(?age) where .users[?id].dept = ?dept .users[?id].age = ?age'

# 3. Inspect moments, path selectors, pull projections, diffs, or launch the REPL
./xit moments app.xit
./xit get     app.xit '@-1.users["101"].age'
./xit pull    app.xit '{users}'
./xit app.xit          # or `./xit --memory` for an in-memory REPL
```

---

## Storage Backends & Hashers

### Storage Cores (`xitdb/core.odin`)

* **`Core_Memory`**: Dynamic in-memory byte buffer (`core_memory_init`, `core_memory_from_bytes`). Ideal for tests, caches, or embedded snapshots.
* **`Core_Buffered_File`**: OS file handle paired with a contiguous in-memory tail write buffer (`core_buffered_file_open`, default $2\text{ MiB}$). Minimizes syscalls during deep tree updates while writing header commits directly.
* **`Core_File`**: Direct unbuffered OS file I/O (`core_file_open`). Multiple independent read-only handles can safely read from the same file concurrently.

### Hashers (`xitdb/types.odin`)

* **`xitdb.sha1_hasher(id, file_id)`**: 20-byte SHA-1 digest (default; hardware-accelerated via x86 SHA-NI when available).
* **`xitdb.sha256_hasher(id, file_id)`**: 32-byte SHA-256 digest (hardware-accelerated via x86 SHA-NI when available).
* **Custom `xitdb.Hasher`**: Supply any `hash_proc :: proc(data: []u8, out_hash: []u8, user_data: rawptr)` and `hash_size` (e.g., BLAKE3, xxHash64, SipHash).

---

## Repository Layout

```text
.
├── xitdb/
│   ├── types.odin              # Wire format constants, Slot, Header, Trailer, SHA-1/SHA-256
│   ├── core.odin               # Core_Memory, Core_File, Core_Buffered_File storage backends
│   ├── database.odin           # Database init, transactions, freeze, path traversal engine
│   ├── cursor.odin             # Read/Write cursors, zero-alloc stack iterators, stream I/O
│   ├── collections.odin        # Typed APIs for ArrayList, LinkedArrayList, HashMap, SortedMap, Sets
│   ├── hamt.odin               # 16-way HAMT & Radix Trie implementation
│   ├── btree.odin              # Count-augmented B-Tree & B+Tree implementation
│   ├── compact_replicate.odin  # Garbage-collecting compactor & incremental log replication
│   └── dsl.odin                # 5-layer DSL: Path selectors, Datomic Tx, marshal/pull, diff & Datalog
├── cmd/xit/
│   └── main.odin               # Standalone CLI & interactive REPL for xitdb
├── DSL.md                      # 5-Layer DSL, Datalog & CLI/REPL reference guide
├── tests/                      # 3-layer ATDD executable specification & unit test suite
└── benchmarks/                 # Throughput, latency & memory allocation benchmark suite
```

## Running Tests

```bash
odin test tests
```

See [`DSL.md`](DSL.md), [`tests/README.md`](tests/README.md), and [`benchmarks/README.md`](benchmarks/README.md) for details on the DSL/Datalog reference, test architecture, and benchmark suite.
