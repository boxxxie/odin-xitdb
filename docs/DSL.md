# xitdb 5-Layer DSL & Datalog Reference

The [`xitdb/dsl.odin`](../xitdb/dsl.odin) module layers a zero-dependency query, transaction, reflection, and Datalog engine on top of `xitdb`'s persistent structural trees. Every DSL operation compiles down to `read_slot_pointer` and `[]Path_Part` without altering the v1 wire format.

> For the embedded LuaJIT 2.1 bindings to this 5-layer DSL, see [`LUAJIT.md`](LUAJIT.md). For low-level storage cores, cursors, and collection APIs, see [`CORE_API.md`](CORE_API.md).

---

## Collection Sigils & Path Combinators

Every collection type in `xitdb` has a dedicated sigil used across string path selectors, transaction scripts, struct tags, and Datalog clauses.

| Sigil | Collection Type | Combinator | Backing Structure | Key / Index Type |
| :--- | :--- | :--- | :--- | :--- |
| `.key` or `["key"]` | `Hash_Map` | `hm("key")` | 16-way HAMT | `string` |
| `#key` or `#["key"]` | `Counted_Hash_Map` | `chm("key")` | 16-way HAMT + Header | `string` |
| `$key` or `$["key"]` | `Sorted_Map` | `sm("key")` | B+Tree | `string` |
| `[i]` | `Array_List` | `al(i)` | 16-way Radix Trie | `i64` |
| `[[i]]` | `Linked_Array_List` | `ll(i)` | Count-Augmented B-Tree | `i64` |
| `%member` | `Hash_Set` | `hs("member")` | 16-way HAMT | `string` |
| `#%member` | `Counted_Hash_Set` | `chs("member")` | 16-way HAMT + Header | `string` |
| `^member` | `Sorted_Set` | `ss("member")` | B+Tree | `string` |

Keys containing spaces, dots, brackets, or sigil characters must be quoted inside brackets (for example, `.users["101"]` or `$catalog["green apple"]`). Both `Array_List` (`[i]`) and `Linked_Array_List` (`[[i]]`) support negative indices such as `-1` to address elements from the tail.

---

## Layer 1: Path Selectors & Typed Getters

Path selectors address any nested slot in the database from either the root collection or a specific historical moment `@m` in a top-level `Array_List`.

* **Moment Prefix (`@m`)**: Prefixing a selector with `@0` targets Moment 0, while `@-1` targets the latest committed moment.
* **Auto-Vivification on Writes**: Passing a `[]Path_Step` slice to `put_at_steps` or `write_steps_cursor` automatically initializes missing intermediate collections along the path.

```odin
// Read scalars directly via string selectors
uname, err1 := xitdb.get_string(&db, "@-1.users[\"101\"].username")
age,   err2 := xitdb.get_uint(&db,   "@-1.users[\"101\"].age")
delta, err3 := xitdb.get_int(&db,    "@0.metrics#net_change")
score, err4 := xitdb.get_float(&db,  "@-1.$leaderboard[\"dan\"]")

// Resolve a Read_Cursor at any path
cur_maybe, err5 := xitdb.select_cursor(&db, "@-1.todos[[0]]")

// Programmatic Path_Step combinators
steps := []xitdb.Path_Step{xitdb.hm("users"), xitdb.hm("101"), xitdb.hm("age")}
path_str := xitdb.format_steps(steps) // ".users[\"101\"].age"
```

---

## Layer 2: Datomic-Style Transactions & Script DSL

The `Tx` engine wraps `array_list_append_context` to provide reified transaction metadata, automatic secondary index maintenance, mid-transaction savepoints, and zero-copy collection cloning.

### Programmatic `Tx` API

```odin
// Initialize a transaction branching from the latest moment (-1)
tx := xitdb.tx_init(&db, base_moment = -1, track_changes = true)
defer xitdb.tx_destroy(&tx)

// Attach Datomic-style transaction metadata
xitdb.tx_doc(&tx, "Onboard user 101 and index by username")
xitdb.tx_instant(&tx, 1700000000)
xitdb.tx_meta(&tx, "author", "paul")
xitdb.tx_meta(&tx, "source", "api-v1")

// Automatically maintain a Sorted_Map secondary index when .users[id].username changes
xitdb.tx_index_on(&tx, source_map_key = "users", field_key = "username", into_sorted_map = "username->id")

// Queue mutations, zero-copy forks, and savepoints
_ = xitdb.tx_put(&tx, ".users[\"101\"].username", "dan")
_ = xitdb.tx_put(&tx, ".users[\"101\"].age", u64(28))
_ = xitdb.tx_append(&tx, ".fruits", "apple")
_ = xitdb.tx_fork(&tx, ".fruits", ".fruits_backup") // isolates clone via cursor_freeze
xitdb.tx_savepoint(&tx)                             // freezes prior writes via database_freeze

report, err := xitdb.tx_commit(&tx)
```

### Reified `__tx` Metadata Schema

When `tx_doc`, `tx_instant`, `tx_meta`, or `track_changes` is used, `tx_commit` writes a `"__tx"` `Hash_Map` inside the committed moment containing:

* **`@m.__tx.doc`**: Transaction documentation string (`string`).
* **`@m.__tx.tx_instant`**: Commit timestamp (`i64`).
* **`@m.__tx.parent`**: Base moment index from which this moment branched (`i64`).
* **`@m.__tx.<custom_key>`**: Any custom key-value pair added via `tx_meta`.
* **`@m.__tx.changes[i]`**: `Array_List` of `Hash_Map` entries with `"op"`, `"path"`, `"old_tag"`, and `"new_tag"`.

### Declarative Transaction Script (`transact_script`)

`transact_script` parses multi-line transaction blocks into a `Tx` and commits them atomically:

```odin
report, err := xitdb.transact_script(&db, `
	branch @-1 {
		doc "Update inventory and add markdown report"
		instant 1700000500
		meta "ticket" = "XIT-42"

		fork .fruits -> .backup_fruits
		savepoint

		put .users["101"].age = 29u
		put .balance_delta    = -50i
		put .ratio            = 3.14159
		put .report           = "# Q4 Summary"^^md
		append .fruits        = "pear"
		slice .fruits 2
		rm .deprecated_key
	}
`)
```

| Script Literal Syntax | Stored Wire Tag | Example |
| :--- | :--- | :--- |
| `<number>u` or `<positive_int>` | `.Uint` (`u64`) | `29u`, `100` |
| `<number>i` or `-<number>` | `.Int` (`i64`) | `-42`, `10i` |
| `<number>.<number>` | `.Float` (`f64`) | `3.14159` |
| `"text"` | `.Short_Bytes` ($\le 8\text{ B}$) or `.Bytes` | `"hello"` |
| `"text"^^<2-char-tag>` | `.Short_Bytes` ($\le 6\text{ B}$, `full=true`) or `.Bytes` | `"# Hi"^^md` |

Strings without null bytes up to 8 bytes (or up to 6 bytes when paired with a 2-byte format tag) are stored inline inside the 9-byte `Slot` as `.Short_Bytes` with zero disk indirection.

---

## Layer 3: Struct Reflection (`marshal` / `unmarshal`) & Datomic `pull`

### Odin Struct Tag Mapping

`marshal` and `unmarshal` use `core:reflect` to map native Odin structs to `xitdb` collections. Customize field names, collection types, and 2-byte format tags with the `xitdb` struct tag:

| Struct Tag | Target Collection / Encoding | Supported Odin Field Types |
| :--- | :--- | :--- |
| `xitdb:"field_name"` | Default (`Hash_Map`, `Array_List`, or scalar) | `string`, integers, floats, `bool`, `[]T`, `struct` |
| `xitdb:"-"` | Skipped during `marshal` and `unmarshal` | Any |
| `xitdb:"bio,tag=md"` | `Bytes` / `Short_Bytes` with 2-byte `format_tag` | `string` |
| `xitdb:"[[todos]]"` or `xitdb:"todos,linked_list"` | `Linked_Array_List` | `[]T` |
| `xitdb:"%roles"` or `xitdb:"roles,hash_set"` | `Hash_Set` | `[]string` |
| `xitdb:"^tags"` or `xitdb:"tags,sorted_set"` | `Sorted_Set` (unmarshals in ascending order) | `[]string` |
| `xitdb:"$catalog"` or `xitdb:"catalog,sorted_map"` | `Sorted_Map` | `map[string]V` |
| `xitdb:"#metrics"` or `xitdb:"metrics,counted_map"` | `Counted_Hash_Map` | `map[string]V` |

```odin
User_Profile :: struct {
	username: string   `xitdb:"username"`,
	age:      u64      `xitdb:"age"`,
	bio:      string   `xitdb:"bio,tag=md"`,
	todos:    []string `xitdb:"[[todos]]"`,
	tags:     []string `xitdb:"^tags"`,
	internal: int      `xitdb:"-"`,
}

// Marshal into any Write_Cursor
xitdb.marshal(&cursor, profile)

// Unmarshal from any Read_Cursor
decoded, err := xitdb.unmarshal(User_Profile, cursor.read_cursor, context.temp_allocator)
```

### Datomic-Style `pull` Projections

`pull` extracts a shaped subset of a moment or collection cursor into a `Pull_Value` union (`u64`, `i64`, `f64`, `string`, `Bytes`, `Pull_List`, `Pull_Map`):

* **Wildcard (`"*"`)**: Recursively reads the entire subtree (automatically omitting `"__tx"` at the root of a moment).
* **Field Selection (`"{username, age}"`)**: Reads only the requested keys from a map.
* **Range Slicing (`"todos[0..3]"`)**: Uses `array_list_iterator_from` or `linked_array_list_iterator_from` to seek directly to index `0` in $O(\log_{16} N)$ time and read `3` elements.
* **Nested Sub-Selection (`"{.profile{username, todos[0..2]}}"`)**: Walks nested path steps and projects child patterns.

```odin
pulled, err := xitdb.pull(moment.cursor, "{.profile{username, age, todos[0..2]}}")
if prof, ok := xitdb.pull_get(pulled, "profile"); ok {
	uname, _ := xitdb.pull_get(prof, "username")
}
```

---

## Layer 4: Structural Diffs, Temporal Lineage & B+Tree Queries

Because `xitdb` shares unchanged subtrees across transactions using 9-byte `Slot` pointers, historical comparisons never scan unmodified data:

* **`diff_moments(&db, moment_a, moment_b)`**: Compares two moments and skips any branch where `slot_a == slot_b` in $O(1)$ time, returning a `[]Tx_Change` slice of leaf mutations.
* **`history_of(&db, ".users[\"101\"].age")`**: Walks moments `0 ..< N` and returns a `[]History_Entry` slice for every moment where the target path's `Slot` changed, alongside its `__tx.doc` and `__tx.tx_instant`.
* **`query_prefix(moment, "username->id", "da")`**: Seeks to `"da"` in $O(\log_{16} N)$ time via `sorted_map_iterator_from_string` and returns all matching `Index_Hit` entries.
* **`query_count_range(moment, "username->id", "da", "dz")`**: Computes the exact number of keys in `["da", "dz")` in $O(\log_{16} N)$ time via `sorted_map_rank("dz") - sorted_map_rank("da")` without scanning leaf nodes.

---

## Layer 5: Structural & Temporal Datalog (`query_datalog`)

`query_datalog` evaluates declarative `find ... where ...` queries across all `xitdb` collections and historical moments.

### Query Grammar

```text
Query      := "find" FindItem ("," FindItem)* "where" Clause+
FindItem   := Var | ("count" | "sum" | "min" | "max") "(" Var ")"
Clause     := Pattern | "not" Pattern | Predicate | Reach
Pattern    := ("@" (Int | Var))? Step+ ("=" (Var | Literal))?
Predicate  := Var ("==" | "!=" | "<" | "<=" | ">" | ">=") (Var | Literal)
            | ("starts_with" | "contains") "(" Var "," StringLiteral ")"
Reach      := "reach(" Var "," Var ("," Var)? "," Pattern ")"
Var        := "?" Ident
```

### Unification, Index Pushdown, Aggregations & `reach`

* **Automatic B+Tree Pushdown**: When a clause binds a variable on a `Sorted_Map` (`$idx[?k] = ?v`) or `Sorted_Set` (`^set^?k`) and the query includes `starts_with(?k, "prefix")` or `?k >= "bound"`, the engine automatically seeks to the lower bound via `cursor_iterator_sorted_from_key` and stops as soon as keys exceed the prefix.
* **$O(\log_{16} N)$ Point Lookups on Bound Variables**: Once a variable `?id` is bound, subsequent steps like `.users[?id].age = ?age` or `not .users[?id].roles%"suspended"` execute direct hash/tree lookups rather than full scans.
* **Grouped & Global Aggregations**: Non-aggregate variables in `find` act as grouping keys; if all items in `find` are aggregates (`count`, `sum`, `min`, `max`), a single summary row is returned.
* **Cycle-Safe Transitive Closure (`reach`)**: Runs a Breadth-First Search (BFS) with a per-seed visited set over any edge pattern, optionally binding a third variable `?hops` to the shortest-path hop count (`u64`).
* **Temporal Queries (`@?m` and `@0`)**: Prefix any clause with `@?m` to unify across all historical moments or `@0` to pin a clause to a specific moment.

```odin
res, err := xitdb.query_datalog(&db, `
	find ?dept, count(?id), min(?age), max(?age), sum(?age)
	where
		.users[?id].dept = ?dept
		.users[?id].age  = ?age
		not .users[?id].roles%"suspended"
`)

for r_idx in 0 ..< len(res.rows) {
	dept, _  := xitdb.datalog_row_get(res, r_idx, "?dept")
	count, _ := xitdb.datalog_row_get(res, r_idx, "count(?id)")
	total, _ := xitdb.datalog_row_get(res, r_idx, "sum(?age)")
}
```

---

## CLI & Interactive REPL (`cmd/xit/main.odin`)

Build the standalone `xit` CLI/REPL binary with:

```bash
odin build cmd/xit -out:xit -o:speed
```

| Command | Description |
| :--- | :--- |
| `./xit <db.xit>` | Launch the interactive REPL on a database file |
| `./xit --memory` | Launch the interactive REPL backed by `Core_Memory` |
| `./xit status <db.xit>` | Inspect header, hasher, committed size, and moment count |
| `./xit moments <db.xit>` | List all moments with their `__tx` author, timestamp, and doc |
| `./xit get <db.xit> '<selector>'` | Evaluate a Layer 1 selector (for example, `'@-1.users["101"].age'`) |
| `./xit pull <db.xit> [@m] '<pat>'` | Evaluate a Layer 3 `pull` projection (for example, `'{users}'`) |
| `./xit query <db.xit> '<datalog>'` | Execute a Layer 5 Datalog query and print an ASCII table |
| `./xit tx <db.xit> '<script\|file>'` | Commit a Layer 2 transaction script from inline text or a file |
| `./xit diff <db.xit> <m_a> <m_b>` | Print the Layer 4 structural diff between two moments |
| `./xit history <db.xit> '<path>'` | Print the Layer 4 mutation lineage of a path across history |
| `./xit compact <src.xit> <dst.xit>` | Compact `<src.xit>` into a new file `<dst.xit>` |
| `./xit lua-eval <db.xit> '<code>'` | Execute inline LuaJIT code with `db` bound to `<db.xit>` |
| `./xit lua-run <db.xit> <file.lua>` | Execute a LuaJIT script file with `db` bound to `<db.xit>` |
| `./xit lua-compile <db.xit> <file.lua> <path>` | Compile `<file.lua>` to stripped `\x1bLJ` bytecode and store at `<path>` |
