# xitdb Benchmarks

This directory contains the statistical performance benchmark suite for `xitdb`, measuring throughput ($\text{ops/sec}$), median/mean latency ($\text{ns/op}$), variance ($\pm\sigma$, $\text{CV}\%$, $\text{IQR}$, $\text{p95}$, $\text{p99}$, $\text{min..max}$), and resulting database byte footprint across all collection types, storage backends, and the 5-layer DSL/Datalog engine.

---

## Running the Benchmarks

Always compile benchmarks with `-o:speed` (and `-microarch:native` to enable target-specific SIMD instructions alongside runtime x86 SHA-NI detection). By default, each benchmark group executes **1 warmup pass** followed by **5 measured trials** (`--runs 5 --warmup 1`) and automatically tags results with the current Git commit SHA:

```bash
odin run benchmarks -o:speed -microarch:native
```

You can customize the number of measured trials, warmup passes, commit SHA, run ID, or append multiple runs for the same commit:

```bash
# Run 10 measured trials after 2 warmup passes
odin run benchmarks -o:speed -microarch:native -- --runs 10 --warmup 2

# Append an additional run session to odin.jsonl & history.jsonl for the current commit
odin run benchmarks -o:speed -microarch:native -- --runs 5 --append

# Disable bounds checking in hot loops for peak release numbers
odin run benchmarks -o:speed -microarch:native -no-bounds-check -- --runs 5
```

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig`. To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`):

```bash
zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 5 --warmup 1
```

Or run both suites back-to-back with unified commit/run tagging and statistical significance reporting (Welch's $z$-test):

```bash
./benchmarks/compare_1v1.py --runs 5 --warmup 1
```

### Multi-Run Pooling, Commit History & Regression Analysis (`history.jsonl`)

Every benchmark run writes enriched JSONL records to:
- `benchmarks/odin.jsonl` (latest Odin snapshot, or accumulated runs with `--append`)
- `benchmarks/zig.jsonl` (latest Zig snapshot, or accumulated runs with `--append`)
- `benchmarks/history.jsonl` (append-only multi-commit, multi-run history log)

Each JSONL line captures the Git commit SHA, run session ID, summary statistics, quantiles, and the raw `samples_ns` array:
```json
{"rank":1,"lang":"odin","commit":"cadcc64f08ac","run_id":"run-1793600514","name":"HAMT Hash_Map bulk put (1 tx)","ops":2000,"runs":5,"warmup":1,"total_ms":0.404,"ns_per_op":202,"mean_ns":205.20,"median_ns":202.00,"stddev_ns":8.41,"variance_ns2":70.70,"cv_pct":4.10,"min_ns":198,"max_ns":219,"iqr_ns":7.00,"p95_ns":217,"p99_ns":219,"ops_per_sec":4950495,"bytes_used":219650,"samples_ns":[219,205,202,200,198]}
```

 When multiple runs are recorded for the same `(commit, lang, name)`, `compare_1v1.py` and `update_readme.sh` automatically **pool all `samples_ns` arrays** across those runs and recompute unified variance metrics:

```bash
# List all commits, run sessions, and pooled sample counts in history.jsonl
./benchmarks/compare_1v1.py --list-commits

# Inspect individual runs, quantiles (IQR, p95, p99), and raw sample arrays for matching tests
./benchmarks/compare_1v1.py --inspect "HAMT Hash_Map"

# Compare two Git commits for statistically significant speedups or regressions (Welch's t/z test)
./benchmarks/compare_1v1.py --compare-commits <baseline_sha> <candidate_sha> --lang odin
```

`.gitattributes` configures `*.jsonl diff=jsonl`. To get human-readable `git diff` output on `.jsonl` files, configure the `jsonl` textconv driver in your local Git config:

```bash
git config diff.jsonl.textconv "jq -r '\"#\\(.rank) [\\(.commit // \"?\")] \\(.name) | \\(.ns_per_op) ± \\(.stddev_ns // 0) ns/op (CV \\(.cv_pct // 0)%, n=\\(.runs // 1)) | \\(.ops_per_sec) ops/sec\"'"
```

To regenerate the reference tables below from `benchmarks/odin.jsonl` and `benchmarks/zig.jsonl` (optionally filtering by commit prefix):

```bash
./benchmarks/update_readme.sh [commit_sha]
```

---

## Reference Results (`-o:speed -microarch:native`, `Core_Memory`)

<!-- BEGIN_BENCHMARK_TABLE -->
### 1. Odin Results (`-o:speed -microarch:native`, Commit `2d6f9a7120f3`)

| # | Benchmark | Ops | Runs | Median (`ns/op`) | Mean ± σ (`ns`) | CV | Min..Max (`ns`) | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 5 | **202** | 241 ± 86.3 | 35.9% | 201..395 | 4,950,495 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 5 | **95** | 109 ± 31.4 | 28.8% | 93..165 | 10,526,316 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 5 | **60** | 77 ± 27.4 | 35.4% | 56..116 | 16,666,667 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 5 | **923** | 1,138 ± 307.2 | 27.0% | 902..1,483 | 1,083,424 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 5 | **167** | 173 ± 16.6 | 9.6% | 161..201 | 5,988,024 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 5 | **37** | 37 ± 0.8 | 2.3% | 36..38 | 27,027,027 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 5 | **192** | 201 ± 16.6 | 8.3% | 191..230 | 5,208,333 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 5 | **210** | 218 ± 22.8 | 10.4% | 205..259 | 4,761,905 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 5 | **165** | 172 ± 11.7 | 6.8% | 162..188 | 6,060,606 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 5 | **193** | 202 ± 24.8 | 12.3% | 187..246 | 5,181,347 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 5 | **211** | 212 ± 3.8 | 1.8% | 208..218 | 4,739,336 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 5 | **222** | 236 ± 32.9 | 13.9% | 220..295 | 4,504,505 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 5 | **91** | 91 ± 1.5 | 1.7% | 90..94 | 10,989,011 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 5 | **108** | 109 ± 0.9 | 0.8% | 108..110 | 9,259,259 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 5 | **46** | 46 ± 0.5 | 1.2% | 46..47 | 21,739,130 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 5 | **13** | 13 ± 0.5 | 4.3% | 12..13 | 76,923,077 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 5 | **89** | 89 ± 1.1 | 1.3% | 88..91 | 11,235,955 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 5 | **347** | 349 ± 6.3 | 1.8% | 343..358 | 2,881,844 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 5 | **701** | 699 ± 8.6 | 1.2% | 688..711 | 1,426,534 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 5 | **231** | 231 ± 4.5 | 1.9% | 226..237 | 4,329,004 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 5 | **53** | 54 ± 0.9 | 1.7% | 53..55 | 18,867,925 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 5 | **13** | 13 ± 0.5 | 4.1% | 13..14 | 76,923,077 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 5 | **258** | 258 ± 2.9 | 1.1% | 256..263 | 3,875,969 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 5 | **349** | 350 ± 6.4 | 1.8% | 344..360 | 2,865,330 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 5 | **807** | 812 ± 13.1 | 1.6% | 797..827 | 1,239,157 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 5 | **161** | 162 ± 1.9 | 1.2% | 160..164 | 6,211,180 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 5 | **394** | 395 ± 2.3 | 0.6% | 393..398 | 2,538,071 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 5 | **388** | 387 ± 1.7 | 0.4% | 384..388 | 2,577,320 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 5 | **163** | 163 ± 1.0 | 0.6% | 162..164 | 6,134,969 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 5 | **131** | 131 ± 0.7 | 0.5% | 130..132 | 7,633,588 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 5 | **13** | 13 ± 0.0 | 0.0% | 13..13 | 76,923,077 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 5 | **466** | 465 ± 1.5 | 0.3% | 463..467 | 2,145,923 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 5 | **230** | 231 ± 2.6 | 1.1% | 228..234 | 4,347,826 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 5 | **64** | 65 ± 1.3 | 2.0% | 64..67 | 15,625,000 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 5 | **401** | 401 ± 1.5 | 0.4% | 399..403 | 2,493,766 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 5 | **362** | 362 ± 1.3 | 0.4% | 360..363 | 2,762,431 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 5 | **343** | 343 ± 2.0 | 0.6% | 341..345 | 2,915,452 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 5 | **144** | 145 ± 0.9 | 0.6% | 144..146 | 6,944,444 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 5 | **104** | 107 ± 11.2 | 10.5% | 100..127 | 9,615,385 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 5 | **743** | 752 ± 17.9 | 2.4% | 737..781 | 1,345,895 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 5 | **3,707** | 3,891 ± 324.4 | 8.3% | 3,587..4,358 | 269,760 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 5 | **9,347** | 9,491 ± 481.3 | 5.1% | 8,976..10,229 | 106,986 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 5 | **126,618** | 126,387 ± 4396.2 | 3.5% | 121,297..133,060 | 7,898 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 5 | **1,462** | 1,463 ± 36.7 | 2.5% | 1,423..1,513 | 683,995 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 5 | **223** | 223 ± 2.9 | 1.3% | 218..225 | 4,484,305 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 5 | **233** | 233 ± 2.5 | 1.1% | 231..236 | 4,291,845 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 5 | **6** | 6 ± 0.0 | 0.0% | 6..6 | 166,666,667 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 5 | **9** | 9 ± 0.0 | 0.0% | 9..9 | 111,111,111 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 5 | **6** | 6 ± 0.0 | 0.0% | 6..6 | 166,666,667 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 5 | **9** | 9 ± 0.4 | 4.9% | 9..10 | 111,111,111 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 5 | **288** | 291 ± 9.9 | 3.4% | 285..309 | 3,472,222 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 5 | **52** | 53 ± 0.9 | 1.7% | 52..54 | 19,230,769 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 5 | **6** | 6 ± 0.9 | 14.0% | 6..8 | 166,666,667 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 5 | **13** | 13 ± 0.4 | 3.4% | 13..14 | 76,923,077 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 5 | **230** | 231 ± 1.9 | 0.8% | 229..234 | 4,347,826 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 5 | **148** | 148 ± 4.2 | 2.8% | 141..152 | 6,756,757 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 5 | **97** | 97 ± 2.1 | 2.1% | 95..100 | 10,309,278 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 5 | **1,216** | 1,218 ± 10.7 | 0.9% | 1,206..1,235 | 822,368 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 5 | **4,579** | 4,578 ± 15.1 | 0.3% | 4,554..4,593 | 218,388 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 5 | **44,053** | 44,127 ± 193.3 | 0.4% | 43,895..44,387 | 22,700 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 5 | **1,118** | 1,114 ± 9.4 | 0.8% | 1,100..1,122 | 894,454 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 5 | **693** | 693 ± 3.5 | 0.5% | 687..696 | 1,443,001 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 5 | **56** | 56 ± 0.5 | 1.0% | 56..57 | 17,857,143 | — |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | 500 | 5 | **4,562** | 4,709 ± 386.4 | 8.2% | 4,505..5,398 | 219,202 | 232.5 KB |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | 500 | 5 | **540** | 540 ± 10.9 | 2.0% | 530..557 | 1,851,852 | — |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | 200 | 5 | **4,233** | 4,408 ± 282.4 | 6.4% | 4,161..4,735 | 236,239 | — |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | 200 | 5 | **1,977** | 1,972 ± 25.7 | 1.3% | 1,940..2,000 | 505,817 | — |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | 200 | 5 | **1,534** | 1,536 ± 31.0 | 2.0% | 1,491..1,566 | 651,890 | — |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | 200 | 5 | **261,697** | 263,402 ± 4235.1 | 1.6% | 259,365..269,351 | 3,821 | — |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | 200 | 5 | **1,880** | 1,834 ± 87.8 | 4.8% | 1,722..1,909 | 531,915 | — |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | 100 | 5 | **15,366** | 15,610 ± 676.6 | 4.3% | 15,102..16,800 | 65,079 | — |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | 25 | 5 | **855,426** | 842,899 ± 25041.1 | 3.0% | 809,808..868,800 | 1,169 | — |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | 100 | 5 | **27,103** | 27,651 ± 1173.0 | 4.2% | 26,620..29,021 | 36,896 | — |

### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `2d6f9a7120f3`)

| # | Benchmark | Ops | Runs | Median (`ns/op`) | Mean ± σ (`ns`) | CV | Min..Max (`ns`) | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 5 | **756** | 755 ± 8.3 | 1.1% | 744..765 | 1,322,751 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 5 | **257** | 256 ± 3.1 | 1.2% | 251..259 | 3,891,051 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 5 | **175** | 177 ± 4.5 | 2.6% | 174..185 | 5,714,286 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 5 | **2,206** | 2,204 ± 31.5 | 1.4% | 2,160..2,248 | 453,309 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 5 | **896** | 898 ± 5.4 | 0.6% | 893..905 | 1,116,071 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 5 | **135** | 135 ± 1.7 | 1.2% | 134..138 | 7,407,407 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 5 | **693** | 692 ± 3.6 | 0.5% | 687..697 | 1,443,001 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 5 | **758** | 761 ± 7.1 | 0.9% | 758..774 | 1,319,261 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 5 | **927** | 928 ± 5.3 | 0.6% | 922..934 | 1,078,749 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 5 | **1,201** | 1,205 ± 10.8 | 0.9% | 1,198..1,224 | 832,639 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 5 | **2,643** | 2,639 ± 23.1 | 0.9% | 2,610..2,667 | 378,358 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 5 | **516** | 514 ± 6.7 | 1.3% | 507..522 | 1,937,984 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 5 | **255** | 254 ± 2.3 | 0.9% | 250..256 | 3,921,569 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 5 | **200** | 202 ± 5.9 | 2.9% | 196..209 | 5,000,000 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 5 | **120** | 120 ± 1.8 | 1.5% | 118..122 | 8,333,333 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 5 | **29** | 30 ± 1.4 | 4.7% | 29..32 | 34,482,759 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 5 | **192** | 196 ± 6.7 | 3.4% | 191..206 | 5,208,333 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 5 | **1,428** | 1,501 ± 113.5 | 7.6% | 1,421..1,680 | 700,280 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 5 | **1,321** | 1,468 ± 266.7 | 18.2% | 1,299..1,921 | 757,002 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 5 | **2,705** | 2,686 ± 44.9 | 1.7% | 2,627..2,729 | 369,686 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 5 | **2,041** | 2,011 ± 47.7 | 2.4% | 1,951..2,050 | 489,956 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 5 | **54** | 54 ± 1.9 | 3.5% | 52..57 | 18,518,519 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 5 | **3,315** | 3,314 ± 35.0 | 1.1% | 3,277..3,356 | 301,659 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 5 | **3,380** | 3,377 ± 27.6 | 0.8% | 3,338..3,415 | 295,858 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 5 | **31,901** | 32,567 ± 1648.8 | 5.1% | 31,643..35,510 | 31,347 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 5 | **2,197** | 2,231 ± 90.6 | 4.1% | 2,177..2,392 | 455,166 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 5 | **3,141** | 3,148 ± 59.8 | 1.9% | 3,067..3,233 | 318,370 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 5 | **4,192** | 4,204 ± 23.0 | 0.5% | 4,181..4,235 | 238,550 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 5 | **3,999** | 4,203 ± 469.4 | 11.2% | 3,968..5,042 | 250,063 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 5 | **3,928** | 3,941 ± 37.4 | 0.9% | 3,910..4,004 | 254,582 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 5 | **49** | 49 ± 1.1 | 2.2% | 48..51 | 20,408,163 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 5 | **5,080** | 5,162 ± 147.8 | 2.9% | 5,075..5,418 | 196,850 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 5 | **5,692** | 5,728 ± 149.5 | 2.6% | 5,586..5,983 | 175,685 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 5 | **3,038** | 3,129 ± 157.9 | 5.0% | 3,032..3,399 | 329,164 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 5 | **4,094** | 4,124 ± 181.7 | 4.4% | 3,918..4,418 | 244,260 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 5 | **4,566** | 4,552 ± 52.3 | 1.1% | 4,483..4,613 | 219,010 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 5 | **4,031** | 4,044 ± 56.9 | 1.4% | 3,991..4,140 | 248,077 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 5 | **3,780** | 3,759 ± 84.6 | 2.3% | 3,615..3,824 | 264,550 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 5 | **864** | 878 ± 49.4 | 5.6% | 830..960 | 1,157,407 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 5 | **1,641** | 1,640 ± 40.1 | 2.4% | 1,579..1,691 | 609,385 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 5 | **6,552** | 7,664 ± 2939.1 | 38.4% | 5,570..12,854 | 152,625 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 5 | **11,702** | 12,391 ± 2055.9 | 16.6% | 10,820..15,859 | 85,455 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 5 | **106,439** | 108,583 ± 6364.1 | 5.9% | 103,965..119,554 | 9,395 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 5 | **1,613** | 1,613 ± 18.7 | 1.2% | 1,593..1,643 | 619,963 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 5 | **756** | 756 ± 3.6 | 0.5% | 753..761 | 1,322,751 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 5 | **854** | 858 ± 8.1 | 0.9% | 853..872 | 1,170,960 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 5 | **8** | 8 ± 1.3 | 15.9% | 7..10 | 125,000,000 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 5 | **37** | 37 ± 1.7 | 4.6% | 35..39 | 27,027,027 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 5 | **7** | 7 ± 0.0 | 0.0% | 7..7 | 142,857,143 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 5 | **48** | 48 ± 0.7 | 1.5% | 47..49 | 20,833,333 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 5 | **1,614** | 1,621 ± 36.4 | 2.2% | 1,593..1,684 | 619,579 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 5 | **73** | 78 ± 12.7 | 16.1% | 72..101 | 13,698,630 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 5 | **27** | 27 ± 1.1 | 4.0% | 26..29 | 37,037,037 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 5 | **29** | 29 ± 1.0 | 3.4% | 28..30 | 34,482,759 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 5 | **1,438** | 1,435 ± 9.6 | 0.7% | 1,420..1,446 | 695,410 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 5 | **1,233** | 1,228 ± 10.1 | 0.8% | 1,214..1,238 | 811,030 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 5 | **246** | 246 ± 1.2 | 0.5% | 245..248 | 4,065,041 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 5 | **2,473** | 2,480 ± 22.9 | 0.9% | 2,455..2,513 | 404,367 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 5 | **17,854** | 17,842 ± 79.1 | 0.4% | 17,746..17,957 | 56,010 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 5 | **46,795** | 46,869 ± 352.1 | 0.8% | 46,407..47,254 | 21,370 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 5 | **1,869** | 1,872 ± 42.7 | 2.3% | 1,824..1,925 | 535,045 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 5 | **1,949** | 1,943 ± 22.2 | 1.1% | 1,904..1,961 | 513,084 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 5 | **236** | 237 ± 3.1 | 1.3% | 234..242 | 4,237,288 | — |

### 3. 1v1 Comparison (Odin vs. Zig, Commit `2d6f9a7120f3`)

| # | Benchmark | Odin (`ns/op` ± σ) | Zig (`ns/op` ± σ) | Speedup vs. Zig | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **202** ± 86.3 | 756 ± 8.3 | **3.74x** | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **95** ± 31.4 | 257 ± 3.1 | **2.71x** | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **60** ± 27.4 | 175 ± 4.5 | **2.92x** | — |
| 4 | `HAMT CoW branched moment commits` | **923** ± 307.2 | 2,206 ± 31.5 | **2.39x** | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | **167** ± 16.6 | 896 ± 5.4 | **5.37x** | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | **37** ± 0.8 | 135 ± 1.7 | **3.65x** | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **192** ± 16.6 | 693 ± 3.6 | **3.61x** | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **210** ± 22.8 | 758 ± 7.1 | **3.61x** | — |
| 9 | `HAMT Counted_Hash_Map remove` | **165** ± 11.7 | 927 ± 5.3 | **5.62x** | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **193** ± 24.8 | 1,201 ± 10.8 | **6.22x** | — |
| 11 | `HAMT deep suffix-collision branch collapse` | **211** ± 3.8 | 2,643 ± 23.1 | **12.53x** | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **222** ± 32.9 | 516 ± 6.7 | **2.32x** | — |
| 13 | `HAMT Counted_Hash_Set membership check` | **91** ± 1.5 | 255 ± 2.3 | **2.80x** | — |
| 14 | `Array_List (Radix Trie) append` | **108** ± 0.9 | 200 ± 5.9 | **1.85x** | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | **46** ± 0.5 | 120 ± 1.8 | **2.61x** | — |
| 16 | `Array_List (Radix Trie) iterator scan` | **13** ± 0.5 | 29 ± 1.4 | **2.23x** | — |
| 17 | `Array_List (Radix Trie) in-place put` | **89** ± 1.1 | 192 ± 6.7 | **2.16x** | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **347** ± 6.3 | 1,428 ± 113.5 | **4.12x** | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **701** ± 8.6 | 1,321 ± 266.7 | **1.88x** | — |
| 20 | `Linked_Array_List (B-Tree) append` | **231** ± 4.5 | 2,705 ± 44.9 | **11.71x** | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | **53** ± 0.9 | 2,041 ± 47.7 | **38.51x** | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **13** ± 0.5 | 54 ± 1.9 | **4.15x** | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **258** ± 2.9 | 3,315 ± 35.0 | **12.85x** | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **349** ± 6.4 | 3,380 ± 27.6 | **9.68x** | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **807** ± 13.1 | 31,901 ± 1648.8 | **39.53x** | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **161** ± 1.9 | 2,197 ± 90.6 | **13.65x** | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **394** ± 2.3 | 3,141 ± 59.8 | **7.97x** | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **388** ± 1.7 | 4,192 ± 23.0 | **10.80x** | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | **163** ± 1.0 | 3,999 ± 469.4 | **24.53x** | — |
| 30 | `Sorted_Map (B+Tree) rank query` | **131** ± 0.7 | 3,928 ± 37.4 | **29.98x** | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **13** ± 0.0 | 49 ± 1.1 | **3.77x** | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **466** ± 1.5 | 5,080 ± 147.8 | **10.90x** | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **230** ± 2.6 | 5,692 ± 149.5 | **24.75x** | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | **64** ± 1.3 | 3,038 ± 157.9 | **47.47x** | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **401** ± 1.5 | 4,094 ± 181.7 | **10.21x** | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **362** ± 1.3 | 4,566 ± 52.3 | **12.61x** | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **343** ± 2.0 | 4,031 ± 56.9 | **11.75x** | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **144** ± 0.9 | 3,780 ± 84.6 | **26.25x** | — |
| 39 | `Replication (genesis -> 200 moments)` | **104** ± 11.2 | 864 ± 49.4 | **8.31x** | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | **743** ± 17.9 | 1,641 ± 40.1 | **2.21x** | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **3,707** ± 324.4 | 6,552 ± 2939.1 | **1.77x** | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **9,347** ± 481.3 | 11,702 ± 2055.9 | **1.25x** | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 126,618 ± 4396.2 | **106,439** ± 6364.1 | 0.84x | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | **1,462** ± 36.7 | 1,613 ± 18.7 | **1.10x** | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **223** ± 2.9 | 756 ± 3.6 | **3.39x** | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **233** ± 2.5 | 854 ± 8.1 | **3.67x** | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **6** ± 0.0 | 8 ± 1.3 | **1.33x** | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | **9** ± 0.0 | 37 ± 1.7 | **4.11x** | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **6** ± 0.0 | 7 ± 0.0 | **1.17x** | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **9** ± 0.4 | 48 ± 0.7 | **5.33x** | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **288** ± 9.9 | 1,614 ± 36.4 | **5.60x** | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **52** ± 0.9 | 73 ± 12.7 | **1.40x** | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **6** ± 0.9 | 27 ± 1.1 | **4.50x** | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **13** ± 0.4 | 29 ± 1.0 | **2.23x** | — |
| 55 | `Path: 4-level nested cursor_write_path` | **230** ± 1.9 | 1,438 ± 9.6 | **6.25x** | — |
| 56 | `Path: 4-level nested cursor_read_path` | **148** ± 4.2 | 1,233 ± 10.1 | **8.33x** | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **97** ± 2.1 | 246 ± 1.2 | **2.54x** | — |
| 58 | `Backend: Core_Memory commits` | **1,216** ± 10.7 | 2,473 ± 22.9 | **2.03x** | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | **4,579** ± 15.1 | 17,854 ± 79.1 | **3.90x** | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | **44,053** ± 193.3 | 46,795 ± 352.1 | **1.06x** | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1,118** ± 9.4 | 1,869 ± 42.7 | **1.67x** | — |
| 62 | `Tx: Aborted transaction rollback truncate` | **693** ± 3.5 | 1,949 ± 22.2 | **2.81x** | — |
| 63 | `DB: Re-open & trailer checksum verify` | **56** ± 0.5 | 236 ± 3.1 | **4.21x** | — |
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
