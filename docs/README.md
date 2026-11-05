# xitdb Documentation

Welcome to the `xitdb` documentation for Odin and LuaJIT 2.1.

`xitdb` is an immutable, persistent, single-file structural database written in pure Odin and wire-compatible with [xitdb v1](https://github.com/radarroark/xitdb). It provides copy-on-write persistent collections (`Hash_Map`, `Counted_Hash_Map`, `Sorted_Map`, `Array_List`, `Linked_Array_List`, `Hash_Set`, `Counted_Hash_Set`, `Sorted_Set`), a 5-layer query/transaction/Datalog DSL, and an embedded LuaJIT 2.1 userdata client and bytecode engine.

---

## Documentation Guides

| Guide | Audience | Summary |
| :--- | :--- | :--- |
| **[`CORE_API.md`](CORE_API.md)** | Odin Library Users | Storage cores (`Core_Memory`, `Core_Buffered_File`, `Core_File`), `Database` transactions, `Read_Cursor`/`Write_Cursor`, all 8 persistent collections, zero-allocation stack iterators, streaming `Cursor_Reader`/`Cursor_Writer`, compaction, and incremental replication. |
| **[`DSL.md`](DSL.md)** | Odin & CLI Users | The 5-layer DSL: String path selectors (`@-1.users["101"].age`), Datomic-style `Tx` & `transact_script`, Odin struct `marshal`/`unmarshal` reflection (`xitdb:"..."`), Datomic `pull` projections, $O(1)$ structural diffs (`diff_moments`, `history_of`), and the Datalog engine (`query_datalog`). |
| **[`LUAJIT.md`](LUAJIT.md)** | Odin Integrators & LuaJIT Authors | Embedding LuaJIT 2.1 (`xitdb/luajit` + `xitdb/lua.odin`), full Lua userdata API reference (`Database`, `Cursor`, `Collection`, `Iterator`, `Tx`, `Cursor_Reader`/`Writer`), Lua table `marshal`/`unmarshal`, and storing/executing stripped `\x1bLJ` bytecode inside `xitdb`. |
| **[`../usage-rules.md`](../usage-rules.md)** | Developers & Coding Agents | Prescriptive rules, API layer decision tree, collection sigil invariants, `cursor_freeze` rules, allocator lifetimes, and common anti-patterns. |
| **[`../tests/README.md`](../tests/README.md)** | Contributors | 3-layer Acceptance Test-Driven Development (ATDD) executable specification architecture (`spec_*`, `dsl_*`, `driver_*`) and unit test suites. |
| **[`../benchmarks/README.md`](../benchmarks/README.md)** | Performance Engineers | 75-benchmark cross-language suite comparing Odin, Zig, and LuaJIT 2.1 across HAMT, Radix Trie, B-Tree, B+Tree, Compaction, Replication, Streams, and the 5-Layer DSL. |

---

## Choosing Your API Surface

```text
                       ┌──────────────────────────────────────────────┐
                       │           Embedded LuaJIT 2.1 VM             │
                       │  xitdb.open_* / db:tx_init / db:query_datalog│
                       │  xitdb.compile_bytecode / xitdb.load_bytecode│
                       └──────────────────────┬───────────────────────┘
                                              │ (xitdb/lua.odin)
┌─────────────────────────────────────────────▼─────────────────────────────────────────────┐
│                               5-Layer DSL (xitdb/dsl.odin)                                │
│  Layer 5: Structural & Temporal Datalog (query_datalog, B+Tree pushdown, aggs, reach)     │
│  Layer 4: O(1) Subtree Diffs, Path Lineage & B+Tree Range Queries (diff_moments, etc.)    │
│  Layer 3: Odin Struct Tag Reflection & Datomic Pull (marshal, unmarshal, pull)            │
│  Layer 2: Datomic-Style Transactions & Script DSL (Tx, tx_index_on, transact_script)      │
│  Layer 1: Path Selectors & Combinators (select_cursor, get_uint, hm/chm/sm/al/ll/hs/ss)   │
└─────────────────────────────────────────────┬─────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼─────────────────────────────────────────────┐
│                    Core & Collections Engine (xitdb/*.odin)                               │
│  Collections: Array_List, Linked_Array_List, Hash_Map, Counted_Hash_Map, Sorted_Map, Sets │
│  Cursors:     Read_Cursor, Write_Cursor, Cursor_Iterator, Cursor_Reader, Cursor_Writer    │
│  Maintenance: database_compact (Memory/File_Offset_Map), database_apply_replicated_bytes  │
│  Storage:     Core_Memory, Core_Buffered_File, Core_File + SHA-NI SHA-1 / SHA-256         │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

* **Start with [`DSL.md`](DSL.md)** if you are building an application in Odin and want concise path queries, automatic secondary indexes, struct marshaling, diffs, or Datalog.
* **Start with [`CORE_API.md`](CORE_API.md)** if you need zero-allocation cursor loops, custom hashers, streaming multi-megabyte blobs, or direct control over `Slot` pointers and compaction.
* **Start with [`LUAJIT.md`](LUAJIT.md)** if you are embedding LuaJIT scripts or stored bytecode workflows that read and mutate `xitdb` databases directly.
