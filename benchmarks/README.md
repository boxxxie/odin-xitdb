# xitdb Benchmarks

This directory contains performance benchmarks for `xitdb`, measuring throughput ($\text{ops/sec}$), average latency ($\text{ns/op}$), resulting database byte footprint, and memory allocations across all collection types and storage backends.

---

## Running the Benchmarks

Always compile benchmarks with `-o:speed` (and optionally `-microarch:native` to enable target-specific SIMD instructions alongside runtime x86 SHA-NI detection):

```bash
odin run benchmarks -o:speed -microarch:native
```

To disable bounds checking in hot loops for peak release numbers:

```bash
odin run benchmarks -o:speed -microarch:native -no-bounds-check
```

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig`. To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`):

```bash
zig build bench -Doptimize=ReleaseFast -Dcpu=native
```

### JSONL Results & Clean Git Diffs (`odin.jsonl` / `zig.jsonl`)

Every benchmark run automatically writes flat JSONL records (one JSON object per benchmark case) to:
- `benchmarks/odin.jsonl` (written by `bench_xitdb.odin`)
- `benchmarks/zig.jsonl` (written by `bench_xitdb.zig`)

Each line follows the schema:
```json
{"lang":"odin","name":"HAMT Hash_Map bulk put (1 tx)","ops":2000,"total_ms":0.625,"ns_per_op":312,"ops_per_sec":3200947,"bytes_used":219650}
```

`.gitattributes` configures `*.jsonl diff=jsonl`. To get human-readable `git diff` output on `.jsonl` files (instead of noisy raw JSON diffs), configure the `jsonl` textconv driver in your local Git config:

```bash
git config diff.jsonl.textconv "jq -r 'if .bytes_used > 0 then \"\(.name) | \(.ns_per_op) ns/op | \(.ops_per_sec) ops/sec | \(.bytes_used) B\" else \"\(.name) | \(.ns_per_op) ns/op | \(.ops_per_sec) ops/sec\" end'"
```

You can also compare `benchmarks/odin.jsonl` and `benchmarks/zig.jsonl` directly with `jq`:

```bash
jq -rn '[inputs] | group_by(.name)[] | "\(.[0].name): Odin=\(.[0].ns_per_op)ns vs Zig=\(.[1].ns_per_op)ns (\((.[1].ns_per_op / ([.[0].ns_per_op, 1] | max) * 100 | round) / 100)x)"' benchmarks/odin.jsonl benchmarks/zig.jsonl
```

---

## Reference Results (`-o:speed -microarch:native`, `Core_Memory`)

| Benchmark | Ops | Odin (`ns/op`) | Zig (`ns/op`) | Speedup vs. Zig | Odin (`ops/sec`) | Footprint |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `HAMT Hash_Map bulk put (1 tx)` | 2,000 | **328** | 824 | **2.51x** | 3,048,311 | 214.5 KB |
| `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | **93** | 277 | **2.98x** | 10,743,504 | — |
| `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | **56** | 187 | **3.34x** | 17,706,636 | — |
| `HAMT CoW branched moment commits` | 500 | **2,067** | 2,332 | **1.13x** | 483,892 | 457.7 KB |
| `HAMT Hash_Map remove & branch shortening` | 1,000 | **250** | 933 | **3.73x** | 4,000,816 | — |
| `HAMT Hash_Map unordered iterator scan` | 2,000 | **39** | 149 | **3.82x** | 25,921,846 | — |
| `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | **354** | 785 | **2.22x** | 2,823,666 | — |
| `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | **301** | 899 | **2.99x** | 3,318,065 | — |
| `HAMT Counted_Hash_Map remove` | 1,000 | **200** | 1,106 | **5.53x** | 4,992,611 | — |
| `HAMT deep suffix-collision put (depth 10+)` | 500 | **287** | 1,302 | **4.54x** | 3,489,232 | — |
| `HAMT deep suffix-collision branch collapse` | 500 | **219** | 2,997 | **13.68x** | 4,567,670 | — |
| `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | **303** | 561 | **1.85x** | 3,304,884 | — |
| `HAMT Counted_Hash_Set membership check` | 2,000 | **84** | 292 | **3.48x** | 11,972,965 | — |
| `Array_List (Radix Trie) append` | 2,000 | **109** | 227 | **2.08x** | 9,176,880 | 19.3 KB |
| `Array_List (Radix Trie) random get` | 2,000 | **46** | 131 | **2.85x** | 21,679,512 | — |
| `Array_List (Radix Trie) iterator scan` | 2,000 | **12** | 35 | **2.92x** | 82,935,932 | — |
| `Array_List (Radix Trie) in-place put` | 2,000 | **93** | 194 | **2.09x** | 10,763,799 | — |
| `Array_List (Radix Trie) index-seek page(10)` | 2,000 | **336** | 1,451 | **4.32x** | 2,972,594 | — |
| `Array_List (Radix Trie) depth-collapse slice` | 500 | **905** | 1,323 | **1.46x** | 1,105,024 | — |
| `Linked_Array_List (B-Tree) append` | 2,000 | **295** | 2,756 | **9.34x** | 3,385,934 | 45.3 KB |
| `Linked_Array_List (B-Tree) random get` | 2,000 | **52** | 2,104 | **40.46x** | 19,178,030 | — |
| `Linked_Array_List (B-Tree) iterator scan` | 2,000 | **13** | 65 | **5.00x** | 76,778,379 | — |
| `Linked_Array_List (B-Tree) middle insert` | 500 | **269** | 3,487 | **12.96x** | 3,722,398 | — |
| `Linked_Array_List (B-Tree) middle remove` | 500 | **357** | 3,582 | **10.03x** | 2,797,422 | — |
| `Linked_Array_List (B-Tree) concat + slice` | 400 | **999** | 33,851 | **33.88x** | 1,001,379 | — |
| `Linked_Array_List (B-Tree) in-place put` | 2,000 | **170** | 2,303 | **13.55x** | 5,871,318 | — |
| `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | **388** | 3,322 | **8.56x** | 2,574,907 | — |
| `Sorted_Map (B+Tree) out-of-order put` | 2,000 | **402** | 4,488 | **11.16x** | 2,485,275 | 115.4 KB |
| `Sorted_Map (B+Tree) key lookup` | 2,000 | **166** | 4,297 | **25.89x** | 6,024,060 | — |
| `Sorted_Map (B+Tree) rank query` | 2,000 | **132** | 4,260 | **32.27x** | 7,553,555 | — |
| `Sorted_Map (B+Tree) ordered scan` | 2,000 | **13** | 52 | **4.00x** | 76,807,865 | — |
| `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | **575** | 5,529 | **9.62x** | 1,738,361 | — |
| `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | **270** | 6,102 | **22.60x** | 3,706,216 | — |
| `Sorted_Map (B+Tree) get_index select` | 2,000 | **71** | 3,326 | **46.85x** | 14,129,682 | — |
| `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | **413** | 4,419 | **10.70x** | 2,419,108 | — |
| `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | **380** | 4,939 | **13.00x** | 2,630,485 | — |
| `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | **370** | 4,372 | **11.82x** | 2,699,893 | 80.0 KB |
| `Sorted_Set (B+Tree) contains lookup` | 2,000 | **157** | 4,099 | **26.11x** | 6,388,797 | — |
| `Replication (genesis -> 200 moments)` | 200 | **218** | 1,141 | **5.23x** | 4,582,846 | 250.9 KB |
| `Replication (incremental 1-moment delta)` | 100 | 3,202 | **1,864** | 0.58x | 312,294 | 132.7 KB |
| `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 20,328 | **9,949** | 0.49x | 49,193 | 1.2 KB |
| `Compaction (File_Offset_Map, 200 -> 1)` | 1 | **15,439** | 18,554 | **1.20x** | 64,771 | 1.2 KB |
| `Compaction (Heterogeneous DAG + dedup)` | 1 | **130,465** | 166,552 | **1.28x** | 7,665 | 23.4 KB |
| `Replication (Post-compaction resync)` | 1 | 2,295 | **1,794** | 0.78x | 435,730 | 23.4 KB |
| `Hasher: SHA-1 (20B) HAMT put` | 2,000 | **235** | 800 | **3.40x** | 4,257,031 | 224.7 KB |
| `Hasher: SHA-256 (32B) HAMT put` | 2,000 | **250** | 936 | **3.74x** | 3,992,096 | 248.7 KB |
| `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | **6** | 8 | **1.33x** | 153,914,824 | — |
| `Bytes: External Bytes read_bytes_buf` | 10,000 | **9** | 37 | **4.11x** | 107,940,072 | — |
| `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | **7** | 7 | **1.00x** | 148,508,970 | — |
| `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | **9** | 51 | **5.67x** | 110,547,320 | — |
| `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | **861** | 1,724 | **2.00x** | 1,161,825 | 1024.1 KB |
| `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | **73** | 81 | **1.11x** | 13,648,966 | — |
| `Stream: Cursor_Reader random seek + 64B read` | 2,000 | **6** | 28 | **4.67x** | 160,076,837 | — |
| `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 41 | **34** | 0.83x | 24,499,896 | — |
| `Path: 4-level nested cursor_write_path` | 500 | **251** | 1,501 | **5.98x** | 3,981,050 | — |
| `Path: 4-level nested cursor_read_path` | 500 | **156** | 1,286 | **8.24x** | 6,394,189 | — |
| `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | **90** | 254 | **2.82x** | 11,094,531 | — |
| `Backend: Core_Memory commits` | 500 | **1,287** | 2,574 | **2.00x** | 777,125 | 391.0 KB |
| `Backend: Core_Buffered_File commits` | 500 | **5,059** | 18,599 | **3.68x** | 197,681 | 391.0 KB |
| `Backend: Core_File (unbuffered) commits` | 500 | **46,858** | 47,742 | **1.02x** | 21,341 | 391.0 KB |
| `Tx: Mid-tx database_freeze + CoW clone` | 500 | **1,146** | 1,899 | **1.66x** | 872,501 | — |
| `Tx: Aborted transaction rollback truncate` | 500 | **687** | 1,942 | **2.83x** | 1,455,964 | — |
| `DB: Re-open & trailer checksum verify` | 5,000 | **63** | 240 | **3.81x** | 15,953,645 | — |

---

## Benchmark Workloads

The benchmark suite evaluates the core operational profiles of an immutable structural database:

### 1. HAMT Key-Value Throughput (`Hash_Map` & `Counted_Hash_Map`)
* **Batch Insert (Single Transaction)**: Inserts $N$ keys in a single moment, exercising the in-place HAMT node mutation fast path (`ptr >= tx_start`) and stack-allocated key digest buffers (`database_digest_string_buf`).
* **Historical Branching (Multi-Moment CoW)**: Commits $M$ sequential moments where each moment updates a subset of keys from the prior moment, measuring path-copying Copy-on-Write overhead and file growth per commit.
* **Point Lookups & Full Iteration**: Random key lookups via `hash_map_get_cursor` and full-tree traversal via the zero-allocation stack `Cursor_Iterator`.

### 2. Indexed & Positional Lists (`Array_List` vs. `Linked_Array_List`)
* **Sequential Append**: Compares 16-way Radix Trie (`Array_List`) append throughput against count-augmented B-Tree (`Linked_Array_List`) append throughput.
* **Random-Access Reads**: Measures $O(\log_{16} N)$ index lookup across multi-tier trees.
* **Mid-List Structural Edits (`Linked_Array_List`)**: Benchmarks arbitrary mid-list insertions (`linked_array_list_insert`), deletions (`linked_array_list_remove`), range slicing (`linked_array_list_slice`), and $O(\log N)$ B-Tree concatenation (`linked_array_list_concat`).

### 3. Ordered B+Tree Indexing (`Sorted_Map` & `Sorted_Set`)
* **Out-of-Order Key Insertion**: Inserts pseudo-randomly permuted keys into a `Sorted_Map`, exercising binary search, separator promotion, and B+Tree leaf/branch splitting.
* **Rank & Positional Index Queries**: Measures `sorted_map_rank` ($O(\log N)$ count of keys $< k$) and `sorted_map_get_index_kv_pair` ($O(\log N)$ lookup of the $i$-th sorted key).
* **Range & Prefix Scans**: Measures lower-bound seek + sequential leaf iteration via `sorted_map_iterator_from_string`.

### 4. Compaction & Incremental Replication
* **History Compaction**: Measures `database_compact` throughput and space reclamation when compacting a multi-moment database down to its latest moment using `Memory_Offset_Map` vs. `File_Offset_Map`.
* **Delta Replication**: Measures the time to compute `database_replication_start`, extract committed delta bytes, and apply them to a replica (`database_apply_replicated_bytes`).

### 5. Cryptographic Hashers (`SHA-1` vs. `SHA-256`)
* Compares hashing throughput on short keys ($\le 32\text{ B}$) and large blocks ($4\text{ KiB}$), verifying hardware x86 SHA-NI acceleration on `amd64` targets.

---

## Storage Backend Comparison

Benchmarks can be parameterized across the three `Core` backends to evaluate I/O trade-offs:

| Backend | Constructor | Best For |
| :--- | :--- | :--- |
| **`Core_Memory`** | `core_memory_init()` | Measuring pure data-structure CPU & memory overhead without OS syscall noise. |
| **`Core_Buffered_File`** | `core_buffered_file_open(path, 2*1024*1024, flags, fsync)` | Production file workloads—coalesces node reads/writes in a contiguous tail window before flushing on transaction sync. |
| **`Core_File`** | `core_file_open(path, flags, fsync)` | Baseline unbuffered OS file I/O comparison. |

> **Note on `fsync`:** When benchmarking raw disk throughput across thousands of tiny transactions, pass `fsync = false` to measure OS page-cache write speed, or `fsync = true` to measure hardware disk-flush latency per transaction.
