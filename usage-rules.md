# xitdb Usage Rules & Agent Guide

This guide provides prescriptive rules, API selection criteria, canonical recipes, and anti-patterns for using `xitdb` in Odin projects.

---

## Core Mental Model & Invariants

* **Root History Model**: The idiomatic database root is an `Array_List` of historical moments (`Tag.Array_List`), where each element is a `Hash_Map` (`Tag.Hash_Map`) representing an immutable point-in-time snapshot.
* **Intra-Transaction Mutability**: Committed moments are immutable, but nodes allocated after `db.tx_start` within an active transaction are mutated in place until committed or frozen.
* **Zero-Copy Cloning Requires Freezing**: Copying a `Slot` to another key inside the same transaction shares the mutable root node. Always call `cursor_freeze(&clone_cursor)` or `tx_fork(&tx, from, to)` before mutating the clone.
* **Inline Short Bytes**: Payloads without null bytes up to 8 bytes (or up to 6 bytes with a 2-byte `format_tag`) are stored inline inside the 9-byte `Slot` as `Tag.Short_Bytes` with zero heap indirection.
* **Crash-Safe Commits**: Every root transaction appends a 25-byte `Root_Trailer` verified by a CRC-64/XZ checksum before updating and flushing the 17-byte `Root_Header`. Unfinished trailing bytes are truncated on the next write.
* **Lock-Free Concurrent Reads (`core_read_at` & `vmem.reserve`)**: All read and traversal paths use stateless positional `core_read_*_at` (`os.read_at` / `pread` on `Core_File` and direct offset slicing on `Core_Memory` / `Core_Buffered_File`) without mutating `core.pos`. In addition, `core_memory_init` reserves a contiguous virtual address space (`DEFAULT_VMEM_RESERVE_SIZE`, 1 GiB on 64-bit) via `vmem.reserve` and commits physical pages on demand so `raw_data(m.buf)` never moves across appends. Multiple reader threads/actors can concurrently read any committed `Moment` or resume serialized `{moment_slot, cursor_slot}` / B+Tree keys on a shared `^Database` while a single writer appends new moments at the tail.

---

## Decision Tree: API Layer Selection

* **Layer 1 (`select_cursor`, `get_string`, `get_uint`, `get_int`, `get_float`, `read_steps_cursor`)**: Use for single-path point reads or resolving a `Read_Cursor` at a known historical moment such as `@-1` or `@0`.
* **Layer 2 (`Tx` / `tx_init` / `transact_script`)**: Use for standard moment transactions needing path auto-vivification, reified `__tx` commit metadata, automatic `Sorted_Map` secondary indexing (`tx_index_on`), or mid-tx `tx_fork`.
* **Layer 3 (`marshal` / `unmarshal` / `pull`)**: Use `marshal` and `unmarshal` to map Odin structs via `xitdb:"..."` tags, and `pull` to extract nested subtrees or list slices (`todos[0..3]`) into a `Pull_Value` union.
* **Layer 4 (`diff_moments`, `history_of`, `query_prefix`, `query_page`, `query_count_range`)**: Use for $O(1)$ unchanged-subtree structural diffs, path audit lineage, and $O(\log N)$ B+Tree prefix/rank queries.
* **Layer 5 (`query_datalog` / `parse_datalog`)**: Use for multi-collection joins, cross-moment temporal queries (`@?m`), negated set checks (`not`), grouped aggregations (`count`, `sum`, `min`, `max`), and BFS graph closure (`reach`).
* **Low-Level Cursors (`array_list_append_context`, `Write_Cursor`, `Cursor_Writer`, `Cursor_Iterator`)**: Use for zero-allocation hot loops, streaming large blobs, custom hashers, or non-`Array_List` database roots.
* **Embedded LuaJIT 2.1 (`lua_new_state`, `lua_push_database`, `lua_exec_string`, `lua_compile_bytecode`)**: Use when exposing `xitdb` databases, cursors, collections, transactions, Datalog, or stored `\x1bLJ` bytecode workflows to LuaJIT 2.1 scripts.

---

## Collection Sigils, Wire Tags & Combinators

| Sigil | Collection Type | Combinator | Backing Structure | Key Type |
| :--- | :--- | :--- | :--- | :--- |
| `.key` | `Hash_Map` | `hm("key")` | 16-way HAMT | `string` |
| `#key` | `Counted_Hash_Map` | `chm("key")` | HAMT + Header | `string` |
| `$key` | `Sorted_Map` | `sm("key")` | B+Tree | `string` |
| `[i]` | `Array_List` | `al(i)` | Radix Trie | `i64` |
| `[[i]]` | `Linked_Array_List` | `ll(i)` | Counted B-Tree | `i64` |
| `%m` | `Hash_Set` | `hs("m")` | 16-way HAMT | `string` |
| `#%m` | `Counted_Hash_Set` | `chs("m")` | HAMT + Header | `string` |
| `^m` | `Sorted_Set` | `ss("m")` | B+Tree | `string` |

Every collection stores its specific `Tag` in the 9-byte `Slot` on disk. Once a slot is initialized as a specific collection (for example, `$users` for `Sorted_Map`), accessing it with a mismatched family sigil (such as `.users` for `Hash_Map` or `#users` for `Counted_Hash_Map`) returns `Xitdb_Error.Unexpected_Tag`. Keys containing spaces, dots, brackets, or sigil characters must be quoted inside brackets, such as `.users["user.101"]` or `$catalog["green apple"]`. Both `Array_List` (`[i]`) and `Linked_Array_List` (`[[i]]`) accept negative indices like `-1` to address elements from the end.

---

## Canonical Recipes

### 1. Opening and Closing a Database

Use `core_memory_init` for tests or ephemeral state, and `core_buffered_file_open` for disk-backed databases.

```odin
core, open_err := xitdb.core_buffered_file_open("app.xit", 2 * 1024 * 1024)
assert(open_err == nil)
defer xitdb.core_destroy(&core, close_file = true)

db, init_err := xitdb.database_init(&core, xitdb.sha1_hasher())
assert(init_err == nil)
```

### 2. Transacting with Programmatic `Tx` vs. `transact_script`

`tx_init` defaults to `context.temp_allocator`; if you pass a persistent allocator like `context.allocator`, always pair it with `defer xitdb.tx_destroy(&tx)` and `defer xitdb.tx_report_destroy(&rep, context.allocator)`. Note that `__tx` metadata is only written to the moment if `tx_doc`, `tx_instant`, `tx_meta`, or `track_changes = true` is used.

```odin
tx := xitdb.tx_init(&db, base_moment = -1, track_changes = true, allocator = context.allocator)
defer xitdb.tx_destroy(&tx)

xitdb.tx_doc(&tx, "Onboard dan and maintain secondary index")
xitdb.tx_instant(&tx, 1700000000)
xitdb.tx_meta(&tx, "author", "paul")
xitdb.tx_index_on(&tx, "users", "username", "username->id")

_ = xitdb.tx_put(&tx, `.users["101"].username`, "dan")
_ = xitdb.tx_put(&tx, `.users["101"].age`, u64(28))
_ = xitdb.tx_append(&tx, ".fruits", "apple")
_ = xitdb.tx_fork(&tx, ".fruits", ".fruits_backup")
xitdb.tx_savepoint(&tx)

rep, err := xitdb.tx_commit(&tx)
assert(err == nil)
defer xitdb.tx_report_destroy(&rep, context.allocator)
```

For declarative batches, use `transact_script` (use `branch none` or `branch genesis` for Moment 0, and `branch @-1` to branch from the latest moment):

```odin
rep, err := xitdb.transact_script(&db, `
	branch @-1 {
		doc "Update inventory"
		meta "ticket" = "XIT-42"
		fork .fruits -> .backup_fruits
		savepoint
		put .users["101"].age = 29u
		put .delta            = -10i
		put .ratio            = 3.14
		put .notes            = "# Summary"^^md
		append .fruits        = "pear"
		insert .todos 0       = "ship release"
		slice .fruits 2
		rm .deprecated_key
	}
`)
```

### 3. Low-Level Cursor Transactions (`array_list_append_context`)

When mutating via low-level cursors, always branch from the latest moment slot (`array_list_get_slot(history.read_array_list, -1)`) after Moment 0:

```odin
rc := xitdb.database_root_cursor(&db)
history, _ := xitdb.write_array_list_init(rc)

// Moment 0 (genesis): pass empty Slot{}
_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
	moment := xitdb.write_hash_map_init(cursor^) or_return
	xitdb.hash_map_put(&moment, "version", u64(1)) or_return
	return nil
})

// Moment 1+: pass latest_slot.? so history branches from the prior moment
latest_slot, _ := xitdb.array_list_get_slot(history.read_array_list, -1)
_ = xitdb.array_list_append_context(&history, latest_slot.?, proc(cursor: ^xitdb.Write_Cursor, _: rawptr) -> xitdb.Error {
	moment := xitdb.write_hash_map_init(cursor^) or_return
	xitdb.hash_map_put(&moment, "version", u64(2)) or_return
	return nil
})
```

### 4. Struct Reflection (`xitdb:"..."`) and `pull` Projections

The struct tag key is `xitdb` (never `xit`). Use `tag=xx` (exact 2-byte format tag) for strings, `[[name]]` or `,linked_list` for `Linked_Array_List`, `%name` or `,hash_set` for `Hash_Set`, `^name` or `,sorted_set` for `Sorted_Set`, `$name` or `,sorted_map` for `Sorted_Map`, `#name` or `,counted_map` for `Counted_Hash_Map`, and `xitdb:"-"` to skip a field.

```odin
User_Profile :: struct {
	username: string            `xitdb:"username"`,
	age:      u64               `xitdb:"age"`,
	bio:      string            `xitdb:"bio,tag=md"`,
	todos:    []string          `xitdb:"[[todos]]"`,
	roles:    []string          `xitdb:"%roles"`,
	tags:     []string          `xitdb:"^tags"`,
	catalog:  map[string]f64    `xitdb:"$catalog"`,
	metrics:  map[string]u64    `xitdb:"#metrics"`,
	secret:   string            `xitdb:"-"`,
}

// Marshal into a Write_Cursor inside an active transaction:
xitdb.marshal(&profile_write_cursor, profile)

// Unmarshal from a Read_Cursor:
decoded, u_err := xitdb.unmarshal(User_Profile, profile_read_cursor, context.temp_allocator)

// Pull a subset with O(log N) range slicing:
pv, p_err := xitdb.pull(moment_cursor, "{.profile{username, todos[0..2], ^tags}}", context.temp_allocator)
if prof, ok := xitdb.pull_get(pv, "profile"); ok {
	uname, _ := xitdb.pull_get(prof, "username")
}
```

### 5. Datalog Queries, B+Tree Pushdown, Aggregations & `reach`

When querying a `Sorted_Map` (`$idx[?k] = ?v`) or `Sorted_Set` (`^set^?k`), adding `starts_with(?k, "prefix")` or `?k >= "bound"` automatically pushes the lower bound down into `cursor_iterator_sorted_from_key`.

```odin
res, err := xitdb.query_datalog(&db, `
	find ?dept, count(?id), min(?age), max(?age), sum(?age)
	where
		$username->id[?name] = ?id
		starts_with(?name, "da")
		.users[?id].dept = ?dept
		.users[?id].age  = ?age
		not .users[?id].roles%"suspended"
`, default_moment = -1, allocator = context.temp_allocator)

for r in 0 ..< len(res.rows) {
	dept, _  := xitdb.datalog_row_get(res, r, "?dept")
	count, _ := xitdb.datalog_row_get(res, r, "count(?id)")
}
```

### 6. Streaming Blobs, Zero-Alloc Reads, Compaction & Replication

```odin
// Zero-allocation read into a stack buffer (returns .Stream_Too_Long if buffer is too small):
stack_buf: [128]u8
bytes_obj, b_err := xitdb.cursor_read_bytes_buf(read_cur, stack_buf[:])

// Streaming write with 2-byte format tag (must run inside an active transaction):
writer, w_err := xitdb.cursor_writer(&blob_write_cur)
writer.format_tag = transmute([]u8)string("md")
_, _ = xitdb.cursor_writer_write(&writer, transmute([]u8)string("# Header\n"))
_ = xitdb.cursor_writer_finish(&writer)

// Incremental replication from primary_db to replica_db:
rep_state, _    := xitdb.database_replica_state(&replica_db)
start_offset, _ := xitdb.database_replication_start(&primary_db, rep_state)
end_offset, _   := xitdb.database_committed_size(&primary_db)
delta, _        := xitdb.database_read_committed_bytes(&primary_db, start_offset, end_offset, context.temp_allocator)
_                = xitdb.database_apply_replicated_bytes(&replica_db, start_offset, delta)

// Compaction into an empty target Core:
comp_core, _ := xitdb.core_file_open("app.compact.xit", {.Read, .Write, .Create, .Trunc})
comp_db, _   := xitdb.database_compact(&primary_db, &comp_core)
```

---

## Anti-Patterns (DO vs. DO NOT)

* **DO NOT** pass `xitdb.Slot{}` to `array_list_append_context` after Moment 0 unless you intentionally want an empty genesis snapshot. **DO** read `latest_slot, _ := xitdb.array_list_get_slot(history.read_array_list, -1)` and pass `latest_slot.?`.
* **DO NOT** copy a `Slot` within the same transaction and mutate the new cursor directly; intra-transaction nodes mutate in place and will corrupt the source collection. **DO** call `xitdb.cursor_freeze(&clone_cursor)` or `xitdb.tx_fork(&tx, src, dst)` first.
* **DO NOT** use `xit:"..."` or format tags longer than 2 bytes (`tag=markdown` returns `.Invalid_Format_Tag_Size`). **DO** use `xitdb:"field,tag=md"` with an exact 2-byte format tag.
* **DO NOT** call top-level writes on `history` inside an active `array_list_append_context` or `database_run_context` callback (returns `.Nested_Top_Level_Write`), and never reuse a `Write_Cursor` after its transaction finishes (returns `.Expired_Transaction`).
* **DO NOT** call `cursor_read_string`, `cursor_read_bytes`, `cursor_read_bytes_object`, or `database_read_committed_bytes` in a loop with the default `context.allocator` without freeing. **DO** pass `context.temp_allocator`, call `delete`, or use `cursor_read_bytes_buf`.
* **DO NOT** compact into a non-empty database file (`database_compact` returns `.Target_Not_Empty`). **DO** open a fresh or truncated `Core` (`{.Read, .Write, .Create, .Trunc}`) as the compaction target.
