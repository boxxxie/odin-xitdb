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
{"rank":1,"lang":"odin","name":"HAMT Hash_Map bulk put (1 tx)","ops":2000,"total_ms":0.625,"ns_per_op":312,"ops_per_sec":3200947,"bytes_used":219650}
```

`.gitattributes` configures `*.jsonl diff=jsonl`. To get human-readable `git diff` output on `.jsonl` files (instead of noisy raw JSON diffs), configure the `jsonl` textconv driver in your local Git config:

```bash
git config diff.jsonl.textconv "jq -r 'if .bytes_used > 0 then \"#\(.rank) \(.name) | \(.ns_per_op) ns/op | \(.ops_per_sec) ops/sec | \(.bytes_used) B\" else \"#\(.rank) \(.name) | \(.ns_per_op) ns/op | \(.ops_per_sec) ops/sec\" end'"
```

You can also compare `benchmarks/odin.jsonl` and `benchmarks/zig.jsonl` directly with `jq`, or regenerate the reference table below automatically using `./benchmarks/update_readme.sh`:

```bash
./benchmarks/update_readme.sh
```

---

## Reference Results (`-o:speed -microarch:native`, `Core_Memory`)

<!-- BEGIN_BENCHMARK_TABLE -->
### 1. Odin Results (`-o:speed -microarch:native`)

| # | Benchmark | Ops | Total (`ms`) | `ns/op` | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 0.92 | **459** | 2,177,179 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 0.19 | **94** | 10,647,870 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 0.12 | **59** | 17,063,390 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 0.94 | **1,876** | 532,931 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 0.21 | **211** | 4,733,145 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 0.08 | **38** | 26,043,701 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 0.59 | **295** | 3,391,877 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 0.64 | **322** | 3,105,272 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 0.25 | **254** | 3,929,335 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 0.22 | **439** | 2,277,790 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 0.12 | **233** | 4,298,967 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 0.89 | **446** | 2,239,837 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 0.18 | **89** | 11,270,653 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 0.21 | **103** | 9,665,198 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 0.10 | **48** | 20,942,628 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 0.03 | **12** | 80,687,457 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 0.18 | **91** | 10,992,575 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 0.70 | **348** | 2,874,133 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 0.44 | **889** | 1,125,107 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 0.50 | **248** | 4,025,927 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 0.11 | **53** | 18,923,624 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 0.03 | **14** | 70,914,442 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 0.14 | **279** | 3,581,354 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 0.18 | **367** | 2,726,817 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 0.43 | **1,080** | 925,778 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 0.36 | **178** | 5,624,851 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 0.79 | **397** | 2,521,416 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 1.16 | **581** | 1,720,051 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 0.36 | **177** | 5,640,094 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 0.26 | **128** | 7,841,661 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 0.03 | **13** | 78,715,365 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 1.08 | **539** | 1,854,068 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 0.25 | **245** | 4,085,151 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 0.13 | **67** | 14,983,518 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 0.82 | **412** | 2,426,322 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 0.75 | **375** | 2,664,162 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 0.70 | **351** | 2,849,393 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 0.28 | **141** | 7,109,948 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 0.09 | **429** | 2,330,731 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 0.26 | **2,585** | 386,798 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 0.01 | **7,574** | 132,031 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 0.01 | **13,456** | 74,316 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 0.11 | **112,280** | 8,906 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 0.00 | **1,603** | 623,830 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 0.48 | **240** | 4,163,891 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 0.48 | **239** | 4,189,675 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 0.06 | **6** | 161,903,991 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 0.08 | **8** | 119,350,257 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 0.06 | **6** | 161,877,782 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 0.10 | **10** | 98,873,827 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 0.21 | **832** | 1,201,946 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 0.02 | **66** | 15,237,188 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 0.01 | **6** | 175,886,026 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 0.07 | **36** | 28,045,377 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 0.11 | **229** | 4,370,859 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 0.07 | **147** | 6,821,562 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 0.17 | **86** | 11,614,874 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 0.62 | **1,230** | 812,966 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 2.41 | **4,813** | 207,752 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 23.13 | **46,253** | 21,620 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 0.60 | **1,191** | 839,412 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 0.37 | **729** | 1,370,979 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 0.30 | **59** | 16,922,020 | — |

### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`)

| # | Benchmark | Ops | Total (`ms`) | `ns/op` | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 2.14 | **1,071** | 933,738 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 0.53 | **267** | 3,746,097 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 0.37 | **187** | 5,352,030 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 1.14 | **2,280** | 438,545 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 1.05 | **1,049** | 953,022 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 0.51 | **256** | 3,904,199 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 1.69 | **847** | 1,180,992 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 2.00 | **1,000** | 999,542 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 0.98 | **982** | 1,018,550 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 0.62 | **1,236** | 809,170 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 1.35 | **2,700** | 370,374 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 1.04 | **521** | 1,920,621 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 0.52 | **260** | 3,849,759 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 0.44 | **220** | 4,544,174 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 0.26 | **129** | 7,778,439 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 0.08 | **39** | 25,602,949 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 0.39 | **194** | 5,164,689 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 2.91 | **1,454** | 687,778 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 0.66 | **1,310** | 763,257 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 5.51 | **2,753** | 363,305 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 4.29 | **2,142** | 466,759 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 0.13 | **67** | 14,888,596 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 1.76 | **3,517** | 284,299 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 1.79 | **3,570** | 280,118 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 13.72 | **34,298** | 29,157 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 4.80 | **2,398** | 417,040 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 7.01 | **3,505** | 285,338 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 10.07 | **5,037** | 198,518 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 9.08 | **4,538** | 220,354 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 8.44 | **4,220** | 236,990 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 0.10 | **51** | 19,735,544 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 10.86 | **5,431** | 184,135 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 5.92 | **5,923** | 168,837 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 6.40 | **3,199** | 312,602 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 8.53 | **4,265** | 234,452 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 9.60 | **4,800** | 208,340 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 8.48 | **4,242** | 235,746 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 8.18 | **4,092** | 244,392 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 0.23 | **1,131** | 884,392 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 0.18 | **1,791** | 558,397 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 0.01 | **11,752** | 85,092 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 0.02 | **18,665** | 53,576 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 0.18 | **181,550** | 5,508 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 0.00 | **1,764** | 566,893 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 1.62 | **807** | 1,238,518 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 1.78 | **890** | 1,123,265 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 0.07 | **7** | 140,502,719 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 0.36 | **36** | 27,683,500 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 0.07 | **7** | 142,793,906 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 0.49 | **49** | 20,276,038 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 0.61 | **2,366** | 422,593 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 0.05 | **174** | 5,748,417 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 0.06 | **28** | 35,395,098 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 0.06 | **30** | 32,849,353 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 0.79 | **1,571** | 636,440 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 0.64 | **1,283** | 779,665 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 0.50 | **248** | 4,026,413 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 1.28 | **2,555** | 391,337 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 10.59 | **21,171** | 47,235 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 29.12 | **58,248** | 17,168 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 0.92 | **1,838** | 544,158 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 0.97 | **1,948** | 513,456 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 1.19 | **237** | 4,217,349 | — |

### 3. 1v1 Comparison (Odin vs. Zig)

| # | Benchmark | Odin (`ns/op`) | Zig (`ns/op`) | Speedup vs. Zig | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **459** | 1,071 | **2.33x** | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **94** | 267 | **2.84x** | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **59** | 187 | **3.17x** | — |
| 4 | `HAMT CoW branched moment commits` | **1,876** | 2,280 | **1.22x** | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | **211** | 1,049 | **4.97x** | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | **38** | 256 | **6.74x** | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **295** | 847 | **2.87x** | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **322** | 1,000 | **3.11x** | — |
| 9 | `HAMT Counted_Hash_Map remove` | **254** | 982 | **3.87x** | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **439** | 1,236 | **2.82x** | — |
| 11 | `HAMT deep suffix-collision branch collapse` | **233** | 2,700 | **11.59x** | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **446** | 521 | **1.17x** | — |
| 13 | `HAMT Counted_Hash_Set membership check` | **89** | 260 | **2.92x** | — |
| 14 | `Array_List (Radix Trie) append` | **103** | 220 | **2.14x** | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | **48** | 129 | **2.69x** | — |
| 16 | `Array_List (Radix Trie) iterator scan` | **12** | 39 | **3.25x** | — |
| 17 | `Array_List (Radix Trie) in-place put` | **91** | 194 | **2.13x** | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **348** | 1,454 | **4.18x** | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **889** | 1,310 | **1.47x** | — |
| 20 | `Linked_Array_List (B-Tree) append` | **248** | 2,753 | **11.10x** | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | **53** | 2,142 | **40.42x** | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **14** | 67 | **4.79x** | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **279** | 3,517 | **12.61x** | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **367** | 3,570 | **9.73x** | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **1,080** | 34,298 | **31.76x** | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **178** | 2,398 | **13.47x** | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **397** | 3,505 | **8.83x** | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **581** | 5,037 | **8.67x** | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | **177** | 4,538 | **25.64x** | — |
| 30 | `Sorted_Map (B+Tree) rank query` | **128** | 4,220 | **32.97x** | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **13** | 51 | **3.92x** | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **539** | 5,431 | **10.08x** | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **245** | 5,923 | **24.18x** | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | **67** | 3,199 | **47.75x** | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **412** | 4,265 | **10.35x** | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **375** | 4,800 | **12.80x** | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **351** | 4,242 | **12.09x** | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **141** | 4,092 | **29.02x** | — |
| 39 | `Replication (genesis -> 200 moments)` | **429** | 1,131 | **2.64x** | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 2,585 | **1,791** | 0.69x | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **7,574** | 11,752 | **1.55x** | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **13,456** | 18,665 | **1.39x** | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | **112,280** | 181,550 | **1.62x** | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | **1,603** | 1,764 | **1.10x** | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **240** | 807 | **3.36x** | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **239** | 890 | **3.72x** | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **6** | 7 | **1.17x** | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | **8** | 36 | **4.50x** | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **6** | 7 | **1.17x** | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **10** | 49 | **4.90x** | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **832** | 2,366 | **2.84x** | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **66** | 174 | **2.64x** | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **6** | 28 | **4.67x** | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 36 | **30** | 0.83x | — |
| 55 | `Path: 4-level nested cursor_write_path` | **229** | 1,571 | **6.86x** | — |
| 56 | `Path: 4-level nested cursor_read_path` | **147** | 1,283 | **8.73x** | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **86** | 248 | **2.88x** | — |
| 58 | `Backend: Core_Memory commits` | **1,230** | 2,555 | **2.08x** | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | **4,813** | 21,171 | **4.40x** | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | **46,253** | 58,248 | **1.26x** | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1,191** | 1,838 | **1.54x** | — |
| 62 | `Tx: Aborted transaction rollback truncate` | **729** | 1,948 | **2.67x** | — |
| 63 | `DB: Re-open & trailer checksum verify` | **59** | 237 | **4.02x** | — |
<!-- END_BENCHMARK_TABLE -->

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

### 6. 5-Layer DSL & Datalog Engine (`run_dsl_benchmarks`)
* **Layer 1 & 2 (`parse_selector`, `get_uint`, `Tx` + Secondary Index)**: Measures string selector path resolution (`@-1.users["..."].age`) and Datomic-style `Tx` commits with automatic `Sorted_Map` secondary index maintenance (`tx_index_on`).
* **Layer 3 (`marshal`, `unmarshal`, `pull`)**: Measures native Odin struct tag reflection (`xitdb:"..."`) and Datomic-style `pull` subtree projections with range slicing.
* **Layer 4 (`diff_moments`, `history_of`)**: Measures $O(1)$ `Slot`-pointer subtree skipping when diffing moments where only 1 of 700 entities changed, plus temporal path lineage across moments.
* **Layer 5 (`query_datalog`)**: Measures B+Tree prefix pushdown (`starts_with`) with index nested-loop joins, grouped aggregations (`count`, `sum`, `min`, `max`), and cycle-safe BFS transitive closure (`reach` over a 32-node directed ring).

---

## Storage Backend Comparison

Benchmarks can be parameterized across the three `Core` backends to evaluate I/O trade-offs:

| Backend | Constructor | Best For |
| :--- | :--- | :--- |
| **`Core_Memory`** | `core_memory_init()` | Measuring pure data-structure CPU & memory overhead without OS syscall noise. |
| **`Core_Buffered_File`** | `core_buffered_file_open(path, 2*1024*1024, flags, fsync)` | Production file workloads—coalesces node reads/writes in a contiguous tail window before flushing on transaction sync. |
| **`Core_File`** | `core_file_open(path, flags, fsync)` | Baseline unbuffered OS file I/O comparison. |

> **Note on `fsync`:** When benchmarking raw disk throughput across thousands of tiny transactions, pass `fsync = false` to measure OS page-cache write speed, or `fsync = true` to measure hardware disk-flush latency per transaction.
