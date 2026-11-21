# Implementation Plan: `odin_latest_vet_compat_20261121`

## Phase 1: Isolate `amd64` SHA-NI Imports for ARM64 `-vet` Cleanliness
- [x] Split `amd64`-only `core:simd` and `core:simd/x86` SHA-NI implementation (`_has_sha_ni`, `_init_sha_ni`, `sha1_transf_hw`, `sha256_transf_hw`, and hardware fast-path helpers) out of [`xitdb/types.odin`](../../../xitdb/types.odin) into a `#+build amd64` file (`xitdb/sha_ni_amd64.odin`) with non-`amd64` stubs in `xitdb/sha_ni_other.odin` (`#+build !amd64`).
- [x] Verify SHA-NI detection, SHA-1/SHA-256 test vectors, and `-target:darwin_arm64 -vet -warnings-as-errors` / `-target:linux_arm64 -vet -warnings-as-errors` pass with zero unused-import warnings.

## Phase 2: Resolve Odin `dev-2026-11a+` Stack-Escape Warnings Zero-Allocation
- [x] Install/test against Odin `dev-2026-11a` (or current `latest`) locally to reproduce all 33 stack-escape warnings.
- [x] Resolve [`xitdb/cursor.odin`](../../../xitdb/cursor.odin) (`cursor_write_path` `tx_stack` assignment/clear) cleanly without heap allocation or breaking nested write guards.
- [x] Resolve [`xitdb/dsl.odin`](../../../xitdb/dsl.odin) (`tx_commit` returning `Tx_Report.changes` from heap-backed `ectx.recorded`) so the slice isn't syntactically tied to local `ectx`.
- [x] Resolve [`xitdb/compact_replicate.odin`](../../../xitdb/compact_replicate.odin) (`File_Offset_Map`) and [`xitdb/collections.odin`](../../../xitdb/collections.odin) (`hash_map_*` / `hash_set_*` 64-byte stack digest buffers) using an idiomatic, leak-free, zero-allocation pattern accepted by Odin `dev-2026-11a+`.
- [x] Run ATDD suite (`odin test tests -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`), ASan fuzz simulation (`-sanitize:address`), `fuzz/` checks, and `hugi run benchmarks --test` to confirm zero regressions and zero leaks.

## Phase 3: Restore Strict Cross-OS Checks & Unpin Odin in CI/Release
- [x] Update `.github/workflows/ci.yml` to remove the `release: dev-2026-10` pin and restore `-vet -warnings-as-errors` on `Check benchmark suite syntax & types` across all matrix OSes (`ubuntu-latest`, `macos-latest`, `windows-latest`).
- [x] Update `.github/workflows/release.yml` to remove the `release: dev-2026-10` pin so release verification uses Odin `latest` consistently.
- [x] Verify all CI checks pass across Linux, macOS (ARM64), and Windows on a feature-branch PR.
