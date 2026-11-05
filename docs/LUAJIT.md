# xitdb Embedded LuaJIT 2.1 Guide & API Reference

`xitdb` ships with a first-class **LuaJIT 2.1** (`system:luajit-5.1`) userdata client (`xitdb/lua.odin`) and foreign binding package (`xitdb/luajit/luajit.odin`). Any Odin application can expose `xitdb` databases, cursors, collections, transactions, Datalog queries, and compiled `\x1bLJ` bytecode directly to LuaJIT scripts.

---

## 1. System Requirements & Linking

`xitdb/luajit` links against LuaJIT 2.1 (`Lua 5.1` C ABI + `luaJIT_setmode`):

* **Linux**: `libluajit-5.1-dev` (`sudo apt-get install libluajit-5.1-dev` or `pacman -S luajit`)
* **macOS**: `luajit` (`brew install luajit`, with `LIBRARY_PATH="$(brew --prefix luajit)/lib"`)
* **Windows**: `lua51.lib` and `lua51.dll` built via LuaJIT's `msvcbuild.bat`

---

## 2. Host Integration in Odin (`xitdb` + `xitdb/luajit`)

### Creating a LuaJIT State & Binding a Database

```odin
package main

import "core:fmt"
import "xitdb"
import lua "xitdb/luajit"

main :: proc() {
	core := xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())

	// 1. Create a LuaJIT 2.1 VM with standard libs (`jit`, `bit`, `ffi`, etc.)
	//    and the `xitdb` module preloaded (and optionally bind `db` as global `db`):
	L := xitdb.lua_new_state(&db, context.allocator)
	defer lua.close(L)

	// 2. Execute a LuaJIT chunk:
	ok, err_msg := xitdb.lua_exec_string(L, `
		local tx = db:tx_init(nil, true)
		tx:doc("Seed from LuaJIT")
		tx:put('.users["u1"].username', "alice")
		tx:put('.users["u1"].age', 31)
		tx:commit()
	`, "init_chunk")
	assert(ok, err_msg)

	age, _ := xitdb.get_uint(&db, `@0.users["u1"].age`)
	fmt.println("age =", age) // 31
}
```

### Odin Host Procedures (`xitdb/lua.odin`)

| Odin Procedure | Description |
| :--- | :--- |
| `lua_new_state(db: ^Database = nil, allocator := context.allocator) -> ^lua.State` | Creates a new LuaJIT 2.1 VM, opens standard libraries (`jit`, `bit`, `ffi`), registers all `xitdb` metatables and the `xitdb` global/require module, and binds `db` as global `db` if non-nil. |
| `lua_open_xitdb(L: ^lua.State, allocator := context.allocator)` | Registers the `xitdb` module and metatables on an existing `^lua.State`. |
| `lua_set_allocator(L: ^lua.State, allocator: mem.Allocator)` | Associates an Odin allocator with `L` for all `xitdb` C callbacks. |
| `lua_push_database(L: ^lua.State, db: ^Database)` | Pushes a borrowed `xitdb.Database` userdata wrapping an Odin `^Database` (`owns_core = false`). |
| `lua_push_read_cursor(L: ^lua.State, rc: Read_Cursor)` | Pushes a read-only `xitdb.Cursor` userdata onto the Lua stack. |
| `lua_push_write_cursor(L: ^lua.State, wc: Write_Cursor)` | Pushes a read-write `xitdb.Cursor` userdata onto the Lua stack. |
| `lua_push_slot(L: ^lua.State, slot: Slot)` | Pushes a 9-byte `xitdb.Slot` userdata onto the Lua stack. |
| `lua_exec_string(L: ^lua.State, code: string, chunk_name := "=(xitdb.lua)") -> (bool, string)` | Compiles and executes a Lua source string with stack traceback on error. |
| `lua_exec_file(L: ^lua.State, path: string) -> (bool, string)` | Compiles and executes a `.lua` file from disk. |
| `lua_compile_bytecode(L: ^lua.State, src: string, chunk_name := "chunk", strip := true, allocator := context.temp_allocator) -> ([]u8, bool, string)` | Compiles Lua source to LuaJIT `\x1bLJ` bytecode (`string.dump(fn, strip)`). |
| `lua_load_bytecode(L: ^lua.State, bytecode: []u8, chunk_name := "bytecode") -> (bool, string)` | Loads compiled `\x1bLJ` bytecode onto the top of the Lua stack as a callable function. |
| `lua_marshal_table(L: ^lua.State, idx: c.int, cursor: ^Write_Cursor) -> Error` | Marshals the Lua table at stack index `idx` into `cursor` (supporting sigil keys like `["[[todos]]"]`, `["^tags"]`, `["$catalog"]`, `["#metrics"]`, and `["bio,tag=md"]`). |
| `lua_unmarshal_to_table(L: ^lua.State, cursor: Read_Cursor) -> Error` | Recursively decodes `cursor` directly into a Lua table/value on top of the stack. |
| `lua_push_pull_value(L: ^lua.State, pv: Pull_Value)` | Pushes a `Pull_Value` tree onto the Lua stack as native Lua tables and scalars. |

---

## 3. Lua Module Reference (`xitdb.*`)

### Opening Databases from Lua

* **`xitdb.open_memory([hasher]) -> Database`**
  Opens an in-memory database (`Core_Memory`). `hasher` can be `"sha1"` (default), `"sha256"`, or `{hash = "sha256", id = "sha2"}`.
* **`xitdb.open_file(path[, opts]) -> Database`**
  Opens an unbuffered file database (`Core_File`). `opts` is an optional table `{hash = "sha1"|"sha256", truncate = false, fsync = false}`.
* **`xitdb.open_buffered_file(path[, buf_size[, opts]]) -> Database`**
  Opens a buffered file database (`Core_Buffered_File`, default `buf_size = 65536`).
* **`xitdb.open(path[, opts]) -> Database`**
  Alias for `open_buffered_file` (or `open_memory` when `path == ":memory:"`).

### Typed Scalars & Tagged Bytes

By default, plain Lua non-negative integers write as `.Uint`, negative integers as `.Int`, non-integral numbers as `.Float`, booleans as `.Uint` (`1`/`0`), and strings as `.Short_Bytes` ($\le 8\text{ B}$) or `.Bytes`. Use explicit constructors when you need exact wire tags:

* **`xitdb.uint(n)`** $\rightarrow$ forces `.Uint` (`u64`)
* **`xitdb.int(n)`** $\rightarrow$ forces `.Int` (`i64`)
* **`xitdb.float(n)`** $\rightarrow$ forces `.Float` (`f64`)
* **`xitdb.bytes(str[, format_tag])`** $\rightarrow$ writes `.Short_Bytes` or `.Bytes` with an optional 2-byte `format_tag` (e.g. `xitdb.bytes("# Doc", "md")`)
* **`xitdb.slot(tag_name_or_int, value[, full])`** $\rightarrow$ constructs a raw 9-byte `Slot` userdata

### Collection Constructors

Pass any `Cursor` (or `Collection`) to open a typed collection handle:

| Read Constructor | Write Constructor | Backing Structure |
| :--- | :--- | :--- |
| `xitdb.read_array_list(cur)` | `xitdb.write_array_list(wcur)` | 16-way Radix Trie (`Array_List`) |
| `xitdb.read_linked_array_list(cur)` | `xitdb.write_linked_array_list(wcur)` | Count-Augmented B-Tree (`Linked_Array_List`) |
| `xitdb.read_hash_map(cur)` | `xitdb.write_hash_map(wcur)` | 16-way HAMT (`Hash_Map`) |
| `xitdb.read_counted_hash_map(cur)` | `xitdb.write_counted_hash_map(wcur)` | 16-way HAMT + Count (`Counted_Hash_Map`) |
| `xitdb.read_hash_set(cur)` | `xitdb.write_hash_set(wcur)` | 16-way HAMT (`Hash_Set`) |
| `xitdb.read_counted_hash_set(cur)` | `xitdb.write_counted_hash_set(wcur)` | 16-way HAMT + Count (`Counted_Hash_Set`) |
| `xitdb.read_sorted_map(cur)` | `xitdb.write_sorted_map(wcur)` | Count-Augmented B+Tree (`Sorted_Map`) |
| `xitdb.read_sorted_set(cur)` | `xitdb.write_sorted_set(wcur)` | Count-Augmented B+Tree (`Sorted_Set`) |

### Bytecode, Offset Maps & Timing Utilities

* **`xitdb.compile_bytecode(fn_or_source[, strip_debug]) -> string`**
  Compiles a Lua function or source string into LuaJIT `\x1bLJ` bytecode (`strip_debug` defaults to `false`).
* **`xitdb.load_bytecode(bytecode_str[, chunk_name]) -> function`**
  Loads LuaJIT `\x1bLJ` bytecode into a callable Lua function.
* **`xitdb.memory_offset_map() -> Offset_Map`** / **`xitdb.file_offset_map(backing_db) -> Offset_Map`**
  Creates an offset map for `db:compact(target_db, offset_map)`.
* **`xitdb.now_ns() -> number`**
  Returns monotonic elapsed nanoseconds since process startup (fitting within IEEE-754 `double`'s 53-bit exact integer precision).

---

## 4. Userdata Methods Reference

### `Database` Methods (`db:*`)

* **Lifecycle & Core**:
  * `db:close()`, `db:reopen()`, `db:flush()`
  * `db:root_cursor() -> Cursor` (write cursor)
  * `db:committed_size() -> number`
  * `db:header_info() -> {magic, version, hash_size, hash_id, root_header_offset, tag}`
  * `db:digest(str) -> string` (raw 20B SHA-1 or 32B SHA-256 bytes)
  * `db:freeze()` (mid-transaction `database_freeze`)
  * `db:run_context(function(root_cursor) ... end)` (commits on return; aborts and truncates if callback raises an error or returns `false`)
* **Replication & Compaction**:
  * `db:replica_state() -> {committed_size, checksum, checksum_lo, checksum_hi}`
  * `db:replication_start(replica_state_or_db) -> start_offset`
  * `db:read_committed_bytes(start_offset, end_offset) -> string`
  * `db:apply_replicated_bytes(start_offset, payload_bytes)`
  * `db:compact(target_db_or_path[, offset_map]) -> Database`
* **5-Layer DSL Methods**:
  * **Layer 1**: `db:moment_count()`, `db:moment_cursor(idx)`, `db:select_cursor(selector)`, `db:get_string(sel)`, `db:get_bytes(sel)`, `db:get_uint(sel)`, `db:get_int(sel)`, `db:get_float(sel)`, `db:exists(sel)`, `db:count_at(sel)`
  * **Layer 2**: `db:tx_init([base_moment[, track_changes]]) -> Tx`, `db:transact_script(script[, track_changes]) -> report_table`
  * **Layer 3**: `db:marshal(selector, table)`, `db:unmarshal(selector) -> table`, `db:pull(selector_or_moment, pattern) -> table`
  * **Layer 4**: `db:diff_moments(m_a, m_b[, include_tx_meta]) -> changes_list`, `db:history_of(path) -> history_list`, `db:query_prefix(moment, index_name, prefix) -> hits`, `db:query_page(moment, index_name, offset, limit) -> hits`, `db:query_count_range(moment, index_name, low, high) -> count`
  * **Layer 5**: `db:query_datalog(query_str[, default_moment]) -> {columns = {...}, rows = {...}}`

### `Tx` Methods (`tx:*`)

```lua
local tx = db:tx_init(-1, true)
tx:doc("Update user and index")
  :instant(1700000000)
  :meta("author", "alice")
  :index_on("users", "username", "username->id")
  :put('.users["u1"].username', "alice")
  :put('.users["u1"].age', 32)
  :append(".audit_log", "updated u1")
  :insert(".todos", 0, "urgent")
  :slice(".audit_log", 10)
  :fork(".users", ".users_snapshot")
  :savepoint()
  :remove('.users["u1"].temp_flag')

local report = tx:commit() -- or tx:abort()
```

### `Cursor` Methods (`cur:*`)

* **Metadata & Conversion**: `cur:tag() -> string`, `cur:slot() -> Slot`, `cur:offset() -> number`, `cur:is_writable() -> bool`, `cur:read_only() -> Cursor`, `cur:freeze()`
* **Scalar & Byte I/O**: `cur:count()`, `cur:read_uint()`, `cur:read_int()`, `cur:read_float()`, `cur:read_string()`, `cur:read_bytes() -> payload, format_tag`, `cur:read_value()`, `cur:read_kv_pair() -> key_cur, val_cur`
* **Writes**: `cur:write(val)`, `cur:write_if_empty(val)`, `cur:marshal(table)`, `cur:unmarshal() -> table`, `cur:pull(pattern) -> value`
* **Streams & Paths**: `cur:reader() -> Cursor_Reader`, `cur:writer([format_tag]) -> Cursor_Writer`, `cur:read_path(parts) -> Cursor`, `cur:write_path(parts) -> Cursor`, `cur:iterator() -> Iterator`

### `Collection` Methods (`col:*`)

* **Common**: `col:kind() -> string`, `col:count() -> number`, `col:slot() -> Slot`, `col:cursor() -> Cursor`, `col:iterator() -> Iterator`
* **Lists (`Array_List`, `Linked_Array_List`)**:
  * `col:get_cursor(idx)`, `col:get_slot(idx)`, `col:get_uint(idx)`, `col:get_int(idx)`, `col:get_float(idx)`, `col:get_string(idx)`
  * `col:append(val)`, `col:append_cursor()`, `col:append_context([base_slot,] function(cursor) ... end)`
  * `col:put(idx, val)`, `col:put_cursor(idx)`, `col:slice([offset,] size)`
  * `col:insert(idx, val)`, `col:insert_cursor(idx)`, `col:remove(idx)`, `col:concat(other_slot)` *(Linked_Array_List)*
  * `col:iterator_from(start_idx)`
* **Maps & Sets (`Hash_Map`, `Counted_Hash_Map`, `Sorted_Map`, `Hash_Set`, `Counted_Hash_Set`, `Sorted_Set`)**:
  * `col:get_cursor(key)`, `col:get_slot(key)`, `col:get_key_cursor(key)`, `col:get_kv_pair(key) -> key_cur, val_cur`, `col:contains(key) -> bool`
  * `col:get_cursor_by_hash(digest)`, `col:get_slot_by_hash(digest)` *(HAMT maps/sets)*
  * `col:put(key[, val])`, `col:put_cursor(key)`, `col:put_key(key)`, `col:put_by_hash(digest, val)`, `col:put_key_and_value(digest, key, val)`
  * `col:remove(key) -> bool`, `col:remove_by_hash(digest) -> bool`
  * `col:rank(key) -> number`, `col:get_index(idx) -> Cursor`, `col:get_index_kv_pair(idx) -> key_cur, val_cur`, `col:iterator_from(lower_bound_key)`, `col:iterator_from_index(start_idx)` *(Sorted_Map / Sorted_Set)*

---

## 5. Performance Notes for Hot Loops

To eliminate Lua GC pressure in tight loops, `xitdb` reuses registry-anchored child userdata on each parent `Collection`, `Iterator`, and `Cursor`:

* Calling `it:next()` updates and returns the iterator's cached `Cursor` userdata in place.
* Calling `col:get_cursor(k)` or `cur:read_kv_pair()` updates and returns the parent's cached child `Cursor` userdata in place.
* **Important**: If you need to hold onto a cursor returned by `it:next()` or `col:get_cursor()` across subsequent iterations of the same loop, clone it into a standalone userdata with `local saved = cur:read_only()` (or save its slot via `local s = col:get_slot(k)`).
