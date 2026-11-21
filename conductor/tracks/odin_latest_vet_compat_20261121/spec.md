# Specification: Odin `dev-2026-11a+` Stack-Escape & ARM64 `-vet` Compatibility (`odin_latest_vet_compat_20261121`)

## Overview
Update [`xitdb/`](../../../xitdb/) so the full repository, benchmark suite, and fuzz harnesses pass `odin check ... -vet -warnings-as-errors` cleanly on Odin `dev-2026-11a+` across Linux (`amd64`), macOS (`darwin_arm64`), and Windows (`amd64`), allowing CI and release workflows to unpin `release: dev-2026-10`.

While preparing `v2.1.0` (PR #4), CI on `laytan/setup-odin@v2` (`latest` = `dev-2026-11a`) surfaced 33 conservative stack-escape analyzer warnings promoted to errors by `-warnings-as-errors`, plus 2 ARM64-only `-vet` unused-import errors on `macos-latest` (verified locally with `-target:darwin_arm64 -vet -warnings-as-errors`). As an interim unblock, CI and release workflows pinned `release: dev-2026-10` and moved `-vet -warnings-as-errors` for `benchmarks` into `Strict static checks (Linux)`.

## Diagnostic Scope

### 1. ARM64 Unused Imports in `xitdb/types.odin` (2 `-vet` errors on `darwin_arm64`)
* `xitdb/types.odin` imports `"core:simd"` (line 8) and `"core:simd/x86"` (line 9) unconditionally at top level, while all uses (`_has_sha_ni`, `_init_sha_ni`, `sha1_transf_hw`, `sha256_transf_hw`, and `when ODIN_ARCH == .amd64` fast paths in `sha1_sum_into` / `sha256_sum_into`) are compiled only when `ODIN_ARCH == .amd64`.
* On non-`amd64` targets (`macos-latest` ARM64), `-vet` (`-vet-unused-imports`) rejects both imports as unused.

### 2. Stack-Escape Analyzer Warnings under Odin `dev-2026-11a+` (33 warnings)
All 33 warnings represent valid, non-escaping runtime lifetimes flagged conservatively by `dev-2026-11a`'s local stack-lifetime pass:
1. **`xitdb/cursor.odin` (`cursor_write_path`, line 125 — 1 warning):**
   - `c.db.transaction = &tx_stack` with conditional `defer if starts_transaction { c.db.transaction = nil }`.
   - Must keep stack-allocated `tx_stack` (zero heap allocation on unbatched top-level writes) and preserve nested-transaction semantics.
2. **`xitdb/compact_replicate.odin` (`offset_map_put`, line 167 — 1 warning):**
   - `File_Offset_Map` passes local stack scratch `key_buf[:]` into `hash_map_put_by_hash`.
3. **`xitdb/collections.odin` (`hash_map_*` / `hash_set_*`, lines 333–668 — 30 warnings):**
   - Wrapper procedures digest keys into local stack scratch `buf: [64]u8 = ---` and pass `buf[:]` (via `hash`) to `*_by_hash`.
   - Must retain zero heap/temp-allocator overhead for hot-path hash digests.
4. **`xitdb/dsl.odin` (`tx_commit`, line 1388 — 1 warning):**
   - Returns `Tx_Report{ ..., changes = ectx.recorded[:] }` where `ectx` is a local struct on the stack wrapping a heap-allocated `[dynamic]Tx_Change` slice.

## Functional & Non-Functional Requirements
* **Zero Runtime Overhead / Allocation Regression:** Keep `tx_stack`, 64-byte stack digest scratch buffers, and `Tx_Report.changes` heap allocation behavior zero-overhead (no new heap allocations in hot paths).
* **Cross-Architecture Cleanliness:** `odin check xitdb -no-entry-point -vet -warnings-as-errors` and `odin check benchmarks ... -vet -warnings-as-errors` must pass for both `amd64` and `-target:darwin_arm64` (and `-target:linux_arm64`).
* **Zero Leaks & Wire Compatibility:** Preserve v1/v2 binary wire format, `SLOT_LENGTH`, CRC/SHA checksums, and SHA-NI acceleration on `amd64`; pass `odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` and `sanitize:address` checks.
* **CI Unpinning:** Restore `-vet -warnings-as-errors` for `benchmarks` across all CI OSes and remove the temporary `release: dev-2026-10` pin (or track `latest`) in `.github/workflows/ci.yml` and `.github/workflows/release.yml`.

## Acceptance Criteria
1. Isolating `amd64` SHA-NI code passes `odin check xitdb -no-entry-point -vet -warnings-as-errors` on both host `amd64` and `-target:darwin_arm64`.
2. Installing/running Odin `dev-2026-11a+` produces zero `Warning:` or `Error:` diagnostics across `xitdb`, `cmd/xit`, `tests`, `benchmarks`, and `fuzz/{dsl,wire,lua}` with `-vet -warnings-as-errors`.
3. `odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` and `odin test tests -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true` pass 100%, with no benchmark regression in `hugi`.
4. `.github/workflows/ci.yml` (`ubuntu-latest`, `macos-latest`, `windows-latest`) and `.github/workflows/release.yml` pass against Odin `latest` with `-vet -warnings-as-errors` active on every OS.

## Out of Scope
* Changing wire protocol constants, slot layouts, or collection semantics.
* Adding heap allocations to `cursor_write_path`, `hash_map_*`, `hash_set_*`, or `File_Offset_Map`.
