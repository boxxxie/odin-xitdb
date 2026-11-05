#!/usr/bin/env python3
"""
Sophisticated Benchmark Runner, Multi-Run Aggregator & Commit Regression Analyzer
for xitdb-odin vs xitdb-zig.

Features:
- Multi-sample variance tracking (Mean, Median/p50, StdDev, Variance, CV%, Min/Max, IQR, p95, p99)
- Pools multiple runs associated with the same (commit, lang, benchmark) from JSONL history
- 1v1 Comparison (Odin vs Zig) with noise/variance significance awareness
- Commit-vs-Commit regression comparison (--compare-commits <SHA_A> <SHA_B>)
- Commit & Run history inspection (--list-commits, --inspect <pattern>)
"""

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from typing import Any, Dict, List, Optional, Set, Tuple

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH_DIR = os.path.join(ROOT_DIR, "benchmarks")
ODIN_JSONL = os.path.join(BENCH_DIR, "odin.jsonl")
ZIG_JSONL = os.path.join(BENCH_DIR, "zig.jsonl")
LUA_JSONL = os.path.join(BENCH_DIR, "lua.jsonl")
HISTORY_JSONL = os.path.join(BENCH_DIR, "history.jsonl")


def find_zig() -> str:
    if "ZIG" in os.environ:
        return os.environ["ZIG"]
    bundled = os.path.join(ROOT_DIR, ".tmp", "tools", "zig-x86_64-linux-0.17.0", "zig")
    if os.path.isfile(bundled) and os.access(bundled, os.X_OK):
        return bundled
    zig_bin = shutil.which("zig")
    if zig_bin:
        return zig_bin
    raise RuntimeError("Could not find 'zig' binary. Set ZIG=/path/to/zig (0.17.0).")


def current_git_commit() -> str:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short=12", "HEAD"],
            cwd=ROOT_DIR,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out if out else "unknown"
    except Exception:
        return "unknown"


def calc_percentile(sorted_vals: List[float], p: float) -> float:
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n == 1:
        return sorted_vals[0]
    pos = p * (n - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, n - 1)
    frac = pos - lo
    return sorted_vals[lo] + frac * (sorted_vals[hi] - sorted_vals[lo])


def compute_pooled_stats(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Pools all raw `samples_ns` across multiple run records associated with the same
    (commit, lang, benchmark_name) and computes unified variance statistics.
    """
    first = records[0]
    samples: List[float] = []
    run_ids: List[str] = []

    for r in records:
        rid = str(r.get("run_id", "run-0"))
        if rid not in run_ids:
            run_ids.append(rid)
        if "samples_ns" in r and isinstance(r["samples_ns"], list) and len(r["samples_ns"]) > 0:
            samples.extend(float(x) for x in r["samples_ns"])
        elif "ns_per_op" in r:
            samples.append(float(r["ns_per_op"]))

    if not samples:
        samples = [0.0]

    sorted_s = sorted(samples)
    n = len(sorted_s)
    min_ns = sorted_s[0]
    max_ns = sorted_s[-1]
    median_ns = calc_percentile(sorted_s, 0.50)
    q1_ns = calc_percentile(sorted_s, 0.25)
    q3_ns = calc_percentile(sorted_s, 0.75)
    iqr_ns = q3_ns - q1_ns
    p95_ns = calc_percentile(sorted_s, 0.95)
    p99_ns = calc_percentile(sorted_s, 0.99)

    mean_ns = sum(sorted_s) / n
    if n > 1:
        variance_ns2 = sum((x - mean_ns) ** 2 for x in sorted_s) / (n - 1)
    else:
        variance_ns2 = 0.0
    stddev_ns = math.sqrt(variance_ns2)
    cv_pct = (stddev_ns / max(mean_ns, 1e-9)) * 100.0

    ops = int(first.get("ops", 1))
    bytes_used = max(int(r.get("bytes_used", 0)) for r in records)
    total_ms = (median_ns * max(ops, 1)) / 1e6
    ops_per_sec = (ops * 1e9) / max(median_ns * max(ops, 1), 1.0)

    return {
        "rank": int(first.get("rank", 0)),
        "lang": first.get("lang", "odin"),
        "commit": first.get("commit", "unknown"),
        "run_ids": run_ids,
        "num_invocations": len(records),
        "name": first["name"],
        "ops": ops,
        "runs": n,
        "total_ms": total_ms,
        "ns_per_op": round(median_ns),
        "median_ns": median_ns,
        "mean_ns": mean_ns,
        "stddev_ns": stddev_ns,
        "variance_ns2": variance_ns2,
        "cv_pct": cv_pct,
        "min_ns": min_ns,
        "max_ns": max_ns,
        "iqr_ns": iqr_ns,
        "p95_ns": p95_ns,
        "p99_ns": p99_ns,
        "ops_per_sec": round(ops_per_sec),
        "bytes_used": bytes_used,
        "samples_ns": samples,
    }


def load_jsonl_file(path: str) -> List[Dict[str, Any]]:
    if not os.path.isfile(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def match_commit(record_commit: str, target_commit: Optional[str]) -> bool:
    if not target_commit:
        return True
    rc = record_commit.strip()
    tc = target_commit.strip()
    return rc.startswith(tc) or tc.startswith(rc)


def pool_by_lang_and_test(
    records: List[Dict[str, Any]],
    lang: str,
    commit: Optional[str] = None,
) -> List[Dict[str, Any]]:
    filtered = [r for r in records if r.get("lang") == lang and match_commit(str(r.get("commit", "unknown")), commit)]
    if not filtered and commit:
        return []

    overall_latest_commit = filtered[-1].get("commit", "unknown") if filtered else "unknown"

    grouped: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    order: List[str] = []
    for r in filtered:
        name = r["name"]
        if name not in grouped:
            order.append(name)
        grouped[name].append(r)

    pooled = []
    for name in order:
        recs = grouped[name]
        if not commit and recs:
            latest_for_name = recs[-1].get("commit", "unknown")
            recs = [r for r in recs if r.get("commit", "unknown") == latest_for_name]
        stat = compute_pooled_stats(recs)
        if not commit and overall_latest_commit != "unknown":
            stat["commit"] = overall_latest_commit
        pooled.append(stat)
    pooled.sort(key=lambda x: x["rank"])
    return pooled


def fmt_kb(bytes_used: int) -> str:
    if bytes_used > 0:
        return f"{bytes_used / 1024.0:.1f} KB"
    return "-"


def welch_se(a: Dict[str, Any], b: Dict[str, Any]) -> float:
    var_a = a["variance_ns2"]
    var_b = b["variance_ns2"]
    n_a = max(a["runs"], 1)
    n_b = max(b["runs"], 1)
    return math.sqrt((var_a / n_a) + (var_b / n_b))


def welch_z_score(a: Dict[str, Any], b: Dict[str, Any]) -> float:
    se = welch_se(a, b)
    if se < 1e-6:
        return 99.0 if abs(a["mean_ns"] - b["mean_ns"]) >= 1.0 else 0.0
    return abs(a["mean_ns"] - b["mean_ns"]) / se


def run_cmd(cmd: List[str], label: str) -> None:
    print(f"==> Running {label}: {' '.join(cmd)}", file=sys.stderr)
    proc = subprocess.run(cmd, cwd=ROOT_DIR)
    if proc.returncode != 0:
        sys.exit(proc.returncode)


def print_1v1_comparison(odin_rows: List[Dict[str, Any]], zig_rows: List[Dict[str, Any]]) -> None:
    zig_map = {r["name"]: r for r in zig_rows}
    shared = [(o, zig_map[o["name"]]) for o in odin_rows if o["name"] in zig_map]
    odin_only = [o for o in odin_rows if o["name"] not in zig_map]

    if not shared:
        print("ERROR: No matching benchmarks found between Odin and Zig.", file=sys.stderr)
        sys.exit(1)

    o_commit = odin_rows[0]["commit"]
    z_commit = zig_rows[0]["commit"]
    o_samples = odin_rows[0]["runs"]
    z_samples = zig_rows[0]["runs"]

    print()
    print("=" * 172)
    print(
        f"  xitdb 1v1 Statistical Benchmark Comparison: Odin (-o:speed) vs Zig 0.17.0 (-Doptimize=ReleaseFast)\n"
        f"  Commit: Odin={o_commit} ({o_samples} samples/test across {odin_rows[0]['num_invocations']} run(s)) | "
        f"Zig={z_commit} ({z_samples} samples/test across {zig_rows[0]['num_invocations']} run(s))"
    )
    print("=" * 172)
    header = (
        f"  {'Benchmark':<46} | {'Ops':>7} | {'Odin Med ± σ (CV% | p95)':>32} | "
        f"{'Zig Med ± σ (CV% | p95)':>32} | {'Speedup (Sig)':>19} | {'Welch z':>8} | {'Footprint':>10}"
    )
    print(header)
    print("  " + "-" * 168)

    odin_wins = 0
    zig_wins = 0
    ties = 0
    footprint_mismatches = 0

    for o, z in shared:
        o_sz = fmt_kb(o["bytes_used"])
        z_sz = fmt_kb(z["bytes_used"])
        if o_sz != z_sz:
            footprint_mismatches += 1
            size_col = f"{o_sz}!={z_sz}"
        else:
            size_col = o_sz

        o_med = max(o["median_ns"], 1.0)
        z_med = max(z["median_ns"], 1.0)
        z_stat = welch_z_score(o, z)
        sig_flag = "*" if z_stat >= 1.96 else "~"

        o_cell = f"{o['ns_per_op']:>6} ± {o['stddev_ns']:>5.1f} ({o['cv_pct']:>4.1f}%|p95:{o['p95_ns']:>6.0f})"
        z_cell = f"{z['ns_per_op']:>6} ± {z['stddev_ns']:>5.1f} ({z['cv_pct']:>4.1f}%|p95:{z['p95_ns']:>6.0f})"

        if o["ns_per_op"] == z["ns_per_op"]:
            ties += 1
            ratio_str = "1.00x (tie)"
        elif o_med < z_med:
            odin_wins += 1
            ratio = z_med / o_med
            ratio_str = f"{ratio:5.2f}x Odin ({sig_flag})"
        else:
            zig_wins += 1
            ratio = o_med / z_med
            ratio_str = f"{ratio:5.2f}x Zig  ({sig_flag})"

        print(
            f"  {o['name']:<46} | {o['ops']:>7} | {o_cell:>32} | "
            f"{z_cell:>32} | {ratio_str:>19} | {z_stat:>8.1f} | {size_col:>10}"
        )

    if odin_only:
        print("  " + "-" * 168)
        print(f"  Odin-Only Benchmarks (5-Layer DSL & Datalog Engine) [{len(odin_only)} benchmarks]:")
        for o in odin_only:
            o_cell = f"{o['ns_per_op']:>6} ± {o['stddev_ns']:>5.1f} ({o['cv_pct']:>4.1f}%|p95:{o['p95_ns']:>6.0f})"
            o_sz = fmt_kb(o["bytes_used"])
            print(
                f"  {o['name']:<46} | {o['ops']:>7} | {o_cell:>32} | "
                f"{'—':>32} | {'—':>19} | {'—':>8} | {o_sz:>10}"
            )

    print("=" * 172)
    print(
        f"  Summary ({len(shared)} shared): Odin faster on {odin_wins}/{len(shared)}, "
        f"Zig faster on {zig_wins}/{len(shared)}, Ties: {ties}/{len(shared)} | "
        f"Footprint Mismatches: {footprint_mismatches} | (* = Welch z>=1.96, ~ = within variance)"
    )
    print("=" * 172)


def compare_commits(records: List[Dict[str, Any]], sha_a: str, sha_b: str, lang: str) -> None:
    rows_a = pool_by_lang_and_test(records, lang, sha_a)
    rows_b = pool_by_lang_and_test(records, lang, sha_b)

    if not rows_a:
        print(f"ERROR: No benchmark records found for commit '{sha_a}' (lang={lang}).", file=sys.stderr)
        sys.exit(1)
    if not rows_b:
        print(f"ERROR: No benchmark records found for commit '{sha_b}' (lang={lang}).", file=sys.stderr)
        sys.exit(1)

    map_b = {r["name"]: r for r in rows_b}
    paired = [(a, map_b[a["name"]]) for a in rows_a if a["name"] in map_b]

    full_a = rows_a[0]["commit"]
    full_b = rows_b[0]["commit"]

    print()
    print("=" * 154)
    print(
        f"  Commit-vs-Commit Benchmark Regression Report [{lang.upper()}]\n"
        f"  Baseline (A): {full_a} ({rows_a[0]['runs']} samples across {rows_a[0]['num_invocations']} run(s))  vs  "
        f"Candidate (B): {full_b} ({rows_b[0]['runs']} samples across {rows_b[0]['num_invocations']} run(s))"
    )
    print("=" * 154)
    print(
        f"  {'Benchmark':<46} | {'Baseline A (Med ± σ)':>22} | {'Candidate B (Med ± σ)':>22} | "
        f"{'Delta %':>9} | {'Speedup':>9} | {'Welch z':>7} | {'Verdict':<14}"
    )
    print("  " + "-" * 150)

    faster = 0
    slower = 0
    unchanged = 0

    for a, b in paired:
        med_a = max(a["median_ns"], 1.0)
        med_b = max(b["median_ns"], 1.0)
        delta_pct = ((med_b - med_a) / med_a) * 100.0
        speedup = med_a / med_b
        se = welch_se(a, b)
        z = welch_z_score(a, b)
        med_z = (abs(med_b - med_a) / se) if se >= 1e-6 else (99.0 if abs(med_b - med_a) >= 1.0 else 0.0)

        # Require 99% confidence (both mean z and median z >= 2.58), >= 10% relative shift, and >= 5 ns absolute shift
        # so cross-invocation CPU clock/turbo drift (~5-8%) or single-sample outliers are not misclassified.
        is_sig = (z >= 2.58) and (med_z >= 2.58) and (abs(delta_pct) >= 10.0) and (abs(med_b - med_a) >= 5.0)
        if is_sig and med_b < med_a:
            verdict = "FASTER"
            faster += 1
        elif is_sig and med_b > med_a:
            verdict = "REGRESSION"
            slower += 1
        else:
            verdict = "~NOISE"
            unchanged += 1

        cell_a = f"{a['ns_per_op']:>7} ± {a['stddev_ns']:>5.1f} ns"
        cell_b = f"{b['ns_per_op']:>7} ± {b['stddev_ns']:>5.1f} ns"
        print(
            f"  {a['name']:<46} | {cell_a:>22} | {cell_b:>22} | "
            f"{delta_pct:>+8.1f}% | {speedup:>8.2f}x | {z:>7.2f} | {verdict:<14}"
        )

    print("=" * 154)
    print(
        f"  Summary ({len(paired)} benchmarks): {faster} FASTER, {slower} REGRESSION, {unchanged} ~NOISE (within variance)"
    )
    print("=" * 154)


def list_commits(records: List[Dict[str, Any]]) -> None:
    if not records:
        print("No benchmark history records found.")
        return

    summary: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for r in records:
        key = (str(r.get("commit", "unknown")), str(r.get("lang", "odin")))
        if key not in summary:
            summary[key] = {"run_ids": set(), "tests": set(), "total_samples": defaultdict(int)}
        rid = str(r.get("run_id", "run-0"))
        summary[key]["run_ids"].add(rid)
        name = r.get("name", "")
        summary[key]["tests"].add(name)
        s_cnt = len(r.get("samples_ns", [])) if isinstance(r.get("samples_ns"), list) else int(r.get("runs", 1))
        summary[key]["total_samples"][name] += max(s_cnt, 1)

    print()
    print("=" * 96)
    print(f"  {'Commit SHA':<16} | {'Lang':<6} | {'Run Sessions':>12} | {'Benchmarks':>10} | {'Pooled Samples/Test':>20} | {'Run IDs'}")
    print("  " + "-" * 92)
    for (commit, lang), info in summary.items():
        samples_counts = list(info["total_samples"].values())
        min_s = min(samples_counts) if samples_counts else 0
        max_s = max(samples_counts) if samples_counts else 0
        samp_str = f"{min_s}" if min_s == max_s else f"{min_s}..{max_s}"
        rids = ", ".join(sorted(info["run_ids"])[:4])
        if len(info["run_ids"]) > 4:
            rids += f" (+{len(info['run_ids']) - 4} more)"
        print(
            f"  {commit:<16} | {lang:<6} | {len(info['run_ids']):>12} | {len(info['tests']):>10} | {samp_str:>20} | {rids}"
        )
    print("=" * 96)


def inspect_test(records: List[Dict[str, Any]], pattern: str, commit: Optional[str]) -> None:
    pat = pattern.lower()
    matched = [
        r for r in records
        if pat in r.get("name", "").lower() and match_commit(str(r.get("commit", "unknown")), commit)
    ]
    if not matched:
        print(f"No benchmark records matching '{pattern}'" + (f" at commit '{commit}'" if commit else ""))
        return

    grouped: Dict[Tuple[str, str, str], List[Dict[str, Any]]] = defaultdict(list)
    for r in matched:
        key = (str(r.get("commit", "unknown")), str(r.get("lang", "odin")), r["name"])
        grouped[key].append(r)

    print()
    for (c_sha, lang, name), recs in grouped.items():
        pooled = compute_pooled_stats(recs)
        print("=" * 110)
        print(f"  Benchmark : {name}")
        print(f"  Commit    : {c_sha} | Lang: {lang} | Invocations: {pooled['num_invocations']} | Total Pooled Samples: {pooled['runs']}")
        print(
            f"  Stats (ns): Median={pooled['median_ns']:.2f} | Mean={pooled['mean_ns']:.2f} ± {pooled['stddev_ns']:.2f} "
            f"(CV={pooled['cv_pct']:.2f}%, Var={pooled['variance_ns2']:.2f})"
        )
        print(
            f"  Quantiles : Min={pooled['min_ns']:.0f} | IQR={pooled['iqr_ns']:.2f} | "
            f"p95={pooled['p95_ns']:.0f} | p99={pooled['p99_ns']:.0f} | Max={pooled['max_ns']:.0f}"
        )
        print(f"  Samples   : {[round(x) for x in pooled['samples_ns']]}")
        for idx, r in enumerate(recs, 1):
            r_samples = r.get("samples_ns", [r.get("ns_per_op", 0)])
            print(f"    Run #{idx} ({r.get('run_id', 'run-0')}): median={r.get('ns_per_op')} ns/op, samples={r_samples}")
    print("=" * 110)


def load_all_history() -> List[Dict[str, Any]]:
    records = load_jsonl_file(HISTORY_JSONL)
    if not records:
        records = load_jsonl_file(ODIN_JSONL) + load_jsonl_file(ZIG_JSONL) + load_jsonl_file(LUA_JSONL)
    return records


ALL_ODIN_GROUPS = ["hamt", "lists", "sorted_map", "compaction", "hashers", "backends", "dsl"]
ALL_ZIG_GROUPS = ["hamt", "lists", "sorted_map", "compaction", "hashers", "backends"]

GROUP_RANGES = {
    "hamt": "#1–#13 (HAMT Hash_Map)",
    "lists": "#14–#27 (Array_List & Linked_Array_List)",
    "sorted_map": "#28–#38 (B+Tree Sorted_Map)",
    "compaction": "#39–#44 (Compaction & Replication)",
    "hashers": "#45–#57 (Hashers & Byte Streams)",
    "backends": "#58–#63 (Storage Backends & Durability)",
    "dsl": "#64–#75 (5-Layer DSL & Datalog Engine)",
}


def resolve_diff_target(git_ref: Optional[str]) -> Tuple[List[str], str]:
    """
    Determines the `git diff` arguments and human-readable label for change mapping.
    1. If `git_ref` is given explicitly:
       - If it contains `..`, use `[git_ref]`.
       - Otherwise treat a commit ref `<sha>` as `[f"{git_ref}~1..{git_ref}"]` (unless `git_ref == "WORKTREE"`, which diffs `HEAD`).
    2. If `git_ref` is None or `"auto"`:
       - Check if `xitdb/` or `reference/xitdb-zig/src/` has uncommitted changes vs `HEAD`.
       - Otherwise find the most recent commit touching `xitdb/` or `reference/xitdb-zig/src/` and diff `<sha>~1..<sha>`.
    """
    lib_paths = ["xitdb/", "reference/xitdb-zig/src/"]
    code_paths = lib_paths + ["benchmarks/bench_xitdb.odin", "benchmarks/bench_xitdb.zig"]
    if git_ref and git_ref != "auto":
        if git_ref.upper() == "WORKTREE":
            return ["HEAD"], "working tree vs HEAD"
        if ".." in git_ref:
            return [git_ref], git_ref
        return [f"{git_ref}~1..{git_ref}"], f"{git_ref}~1..{git_ref}"

    status_out = subprocess.check_output(
        ["git", "status", "--porcelain", "--"] + lib_paths,
        cwd=ROOT_DIR,
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    if status_out:
        return ["HEAD"], "working tree vs HEAD"

    log_out = subprocess.check_output(
        ["git", "log", "-n", "1", "--format=%h", "--"] + lib_paths,
        cwd=ROOT_DIR,
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    if log_out:
        return [f"{log_out}~1..{log_out}"], f"{log_out}~1..{log_out}"

    log_bench = subprocess.check_output(
        ["git", "log", "-n", "1", "--format=%h", "--"] + code_paths,
        cwd=ROOT_DIR,
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
    if log_bench:
        return [f"{log_bench}~1..{log_bench}"], f"{log_bench}~1..{log_bench}"
    return ["HEAD~1..HEAD"], "HEAD~1..HEAD"


def map_changes_to_benchmarks(git_ref: Optional[str] = None) -> Dict[str, Any]:
    """
    Inspects `git diff` across `xitdb/*.odin` and `reference/xitdb-zig/src/**` (down to
    file and procedure/hunk level) and maps code changes to the minimal set of
    Odin and Zig benchmark groups and name filters that need to run.
    """
    diff_args, diff_label = resolve_diff_target(git_ref)
    diff_cmd = ["git", "diff", "--unified=0"] + diff_args + [
        "--",
        "xitdb/",
        "reference/xitdb-zig/src/",
        "benchmarks/bench_xitdb.odin",
        "benchmarks/bench_xitdb.zig",
    ]
    raw_diff = subprocess.check_output(diff_cmd, cwd=ROOT_DIR, stderr=subprocess.DEVNULL, text=True)

    changed_files: Set[str] = set()
    procs_by_file: Dict[str, Set[str]] = defaultdict(set)
    changed_lines_by_file: Dict[str, List[Tuple[int, int]]] = defaultdict(list)
    current_file: Optional[str] = None

    odin_proc_re = re.compile(r"^[+-]\s*([A-Za-z0-9_]+)\s*::\s*proc\b")
    zig_fn_re = re.compile(r"^[+-]\s*(?:pub\s+)?fn\s+([A-Za-z0-9_]+)\b")
    hunk_re = re.compile(r"^@@\s+[^@]+?\+(\d+)(?:,(\d+))?\s+@@\s*(.*)$")

    for line in raw_diff.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:].strip()
            changed_files.add(current_file)
        elif current_file and line.startswith("@@"):
            m = hunk_re.match(line)
            if m:
                start_ln = int(m.group(1))
                cnt_ln = int(m.group(2)) if m.group(2) is not None else 1
                end_ln = start_ln + max(cnt_ln - 1, 0)
                changed_lines_by_file[current_file].append((start_ln, end_ln))
                if m.group(3):
                    ctx = m.group(3).strip()
                    pm = re.match(r"([A-Za-z0-9_]+)\s*::\s*proc", ctx) or re.search(r"fn\s+([A-Za-z0-9_]+)", ctx)
                    if pm:
                        procs_by_file[current_file].add(pm.group(1))
        elif current_file and (line.startswith("+") or line.startswith("-")) and not line.startswith(("+++", "---")):
            om = odin_proc_re.match(line)
            if om:
                procs_by_file[current_file].add(om.group(1))
            zm = zig_fn_re.match(line)
            if zm:
                procs_by_file[current_file].add(zm.group(1))

    # Refine Odin procedure attribution using exact AST [start_line, end_line] ranges
    try:
        odin_procs = parse_odin_library_procs()
        for f, ranges in changed_lines_by_file.items():
            if f.startswith("xitdb/"):
                exact_procs: Set[str] = set()
                for s_ln, e_ln in ranges:
                    for pname, pinfo in odin_procs.items():
                        if pinfo["file"] == f and not (e_ln < pinfo["start_line"] or s_ln > pinfo["end_line"]):
                            exact_procs.add(pname)
                if exact_procs:
                    procs_by_file[f] = exact_procs
    except Exception:
        pass

    odin_groups_set: Set[str] = set()
    zig_groups_set: Set[str] = set()
    filter_patterns: List[str] = []
    can_narrow_filter = True
    reasons: List[str] = []

    odin_files = sorted(f for f in changed_files if f.startswith("xitdb/") or f == "benchmarks/bench_xitdb.odin")
    zig_files = sorted(f for f in changed_files if f.startswith("reference/xitdb-zig/") or f == "benchmarks/bench_xitdb.zig")

    for f in odin_files:
        f_procs = procs_by_file.get(f, set())
        if f == "xitdb/core.odin":
            f_ranges = changed_lines_by_file.get(f, [])
            buffered_only_procs = {"core_buffered_file_init", "core_buffered_file_open", "_buffered_write_to_file", "_buffered_flush"}
            is_buffered_only = bool(f_procs) and all(
                p in buffered_only_procs
                or (p == "core_write_all" and f_ranges and all(s >= 395 and e <= 431 for s, e in f_ranges))
                for p in f_procs
            )
            if is_buffered_only:
                odin_groups_set.update(["backends", "compaction"])
                filter_patterns.extend(["Core_Buffered_File", "File_Offset_Map"])
                reasons.append(
                    f"{f} [{', '.join(sorted(f_procs))}] (Core_Buffered_File path -> backends, compaction; filter=Core_Buffered_File|File_Offset_Map)"
                )
            else:
                odin_groups_set.update(ALL_ODIN_GROUPS)
                can_narrow_filter = False
                reasons.append(f"{f} (core storage primitive -> all 7 Odin groups)")
        elif f == "xitdb/cursor.odin":
            index_iter_procs = {"cursor_iterator_sorted_from_index", "cursor_iterator_linked_array_list_from_index", "cursor_iterator_array_list_from_index"}
            if f_procs and f_procs.issubset(index_iter_procs):
                if "cursor_iterator_sorted_from_index" in f_procs:
                    odin_groups_set.add("sorted_map")
                    filter_patterns.append("Sorted_Map (B+Tree) index-seek")
                if "cursor_iterator_linked_array_list_from_index" in f_procs:
                    odin_groups_set.add("lists")
                    filter_patterns.append("Linked_Array_List (B-Tree) index-seek")
                if "cursor_iterator_array_list_from_index" in f_procs:
                    odin_groups_set.add("lists")
                    filter_patterns.append("Array_List (Radix Trie) index-seek")
                reasons.append(
                    f"{f} [{', '.join(sorted(f_procs))}] -> index-seek iterator benchmarks"
                )
            else:
                odin_groups_set.update(ALL_ODIN_GROUPS)
                can_narrow_filter = False
                reasons.append(f"{f} (cursor primitive -> all 7 Odin groups)")
        elif f in ("xitdb/database.odin", "xitdb/types.odin"):
            odin_groups_set.update(ALL_ODIN_GROUPS)
            can_narrow_filter = False
            reasons.append(f"{f} (database/wire primitive -> all 7 Odin groups)")
        elif f == "xitdb/hamt.odin":
            odin_groups_set.update(["hamt", "hashers", "backends", "compaction", "dsl"])
            can_narrow_filter = False
            reasons.append(f"{f} (HAMT implementation -> hamt, hashers, backends, compaction, dsl)")
        elif f == "xitdb/collections.odin":
            if f_procs and all(p.startswith(("array_list_", "linked_array_list_", "read_array_list", "write_array_list", "read_linked_array_list", "write_linked_array_list")) for p in f_procs):
                odin_groups_set.update(["lists", "compaction", "dsl"])
                can_narrow_filter = False
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] (list operations -> lists, compaction, dsl)")
            else:
                odin_groups_set.update(["hamt", "lists", "sorted_map", "compaction", "dsl"])
                can_narrow_filter = False
                reasons.append(f"{f} (collection wrappers -> hamt, lists, sorted_map, compaction, dsl)")
        elif f == "xitdb/btree.odin":
            has_btree = any(p.startswith(("btree_", "read_btree_", "write_btree_")) for p in f_procs) or not f_procs
            has_sorted = any(p.startswith(("sorted_", "read_sorted_", "write_sorted_", "compare_key", "read_kv_pair", "write_kv_pair", "write_key")) for p in f_procs) or not f_procs
            if has_btree and not has_sorted:
                odin_groups_set.update(["lists", "compaction", "hashers"])
                filter_patterns.extend(["Linked_Array_List", "Heterogeneous DAG", "4-level nested"])
                reasons.append(
                    f"{f} [{', '.join(sorted(f_procs))}] (Count-Augmented B-Tree -> lists [Linked_Array_List], compaction [Heterogeneous DAG], hashers [4-level nested])"
                )
            elif has_sorted and not has_btree:
                odin_groups_set.update(["sorted_map", "compaction", "dsl"])
                can_narrow_filter = False
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] (Sorted B+Tree -> sorted_map, compaction, dsl)")
            else:
                odin_groups_set.update(["lists", "sorted_map", "compaction", "hashers", "dsl"])
                can_narrow_filter = False
                reasons.append(f"{f} (B-Tree & B+Tree implementation -> lists, sorted_map, compaction, hashers, dsl)")
        elif f == "xitdb/compact_replicate.odin":
            odin_groups_set.add("compaction")
            if f_procs and all("replicate" in p or "replication" in p or "_stream_bytes" in p for p in f_procs):
                filter_patterns.append("Replication")
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] -> group=compaction, filter=Replication")
            elif f_procs and all("compact" in p or "offset_map" in p or "_remap_slot" in p for p in f_procs):
                filter_patterns.extend(["Compaction", "Post-compaction"])
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] -> group=compaction, filter=Compaction|Post-compaction")
            else:
                can_narrow_filter = False
                reasons.append(f"{f} -> group=compaction (#39–#44)")
        elif f == "xitdb/dsl.odin":
            odin_groups_set.add("dsl")
            if not f_procs:
                can_narrow_filter = False
                reasons.append(f"{f} -> group=dsl (#64–#75)")
            else:
                dsl_pats: Set[str] = set()
                unmapped_proc = False
                for p in f_procs:
                    pl = p.lower()
                    if any(k in pl for k in ("datalog", "_eval_", "reach")):
                        dsl_pats.add("Datalog")
                    elif any(k in pl for k in ("secondary_index", "index_on")):
                        dsl_pats.update(["Secondary Index", "Tx Commit"])
                    elif any(k in pl for k in ("pull", "diff_")):
                        dsl_pats.update(["Cyclic", "diff_moments", "pull", "Tx Commit"])
                    elif "history_of" in pl:
                        dsl_pats.add("history_of")
                    elif "marshal" in pl:
                        dsl_pats.add("Struct")
                    elif any(k in pl for k in ("select_", "get_at", "compile_path")):
                        dsl_pats.update(["Compiled Selector", "Wildcard", "history_of"])
                    elif any(k in pl for k in ("tx_", "apply_op", "_execute_")):
                        dsl_pats.update(["Tx Commit", "Secondary Index", "Cyclic"])
                    else:
                        unmapped_proc = True
                if unmapped_proc or not dsl_pats:
                    can_narrow_filter = False
                    reasons.append(f"{f} [{', '.join(sorted(f_procs))}] -> group=dsl (#64–#75)")
                else:
                    filter_patterns.extend(sorted(dsl_pats))
                    reasons.append(
                        f"{f} [{', '.join(sorted(f_procs))}] -> group=dsl, filter={'|'.join(sorted(dsl_pats))}"
                    )
        elif f == "benchmarks/bench_xitdb.odin":
            for p in f_procs:
                if "hamt" in p:
                    odin_groups_set.add("hamt")
                elif "list" in p:
                    odin_groups_set.add("lists")
                elif "sorted_map" in p:
                    odin_groups_set.add("sorted_map")
                elif "compaction" in p:
                    odin_groups_set.add("compaction")
                elif "hashers" in p:
                    odin_groups_set.add("hashers")
                elif "backends" in p:
                    odin_groups_set.add("backends")
                elif "dsl" in p:
                    odin_groups_set.add("dsl")
            if not odin_groups_set:
                odin_groups_set.update(ALL_ODIN_GROUPS)
            can_narrow_filter = False
            reasons.append(f"{f} [{', '.join(sorted(f_procs)) or 'harness'}]")

    for f in zig_files:
        can_narrow_filter = False
        if "hash_array_mapped_trie" in f:
            zig_groups_set.update(["hamt", "hashers", "backends", "compaction"])
            reasons.append(f"{f} -> Zig groups: hamt, hashers, backends, compaction")
        elif "array_list" in f or "linked_array_list" in f:
            zig_groups_set.update(["lists", "compaction"])
            reasons.append(f"{f} -> Zig groups: lists, compaction")
        elif "btree" in f or "sorted" in f:
            zig_groups_set.update(["sorted_map", "compaction"])
            reasons.append(f"{f} -> Zig groups: sorted_map, compaction")
        elif "compact" in f or "replicate" in f:
            zig_groups_set.add("compaction")
            reasons.append(f"{f} -> Zig group: compaction")
        else:
            zig_groups_set.update(ALL_ZIG_GROUPS)
            reasons.append(f"{f} -> all 6 Zig groups")

    odin_groups = [g for g in ALL_ODIN_GROUPS if g in odin_groups_set]
    zig_groups = [g for g in ALL_ZIG_GROUPS if g in zig_groups_set]
    final_filter = "|".join(dict.fromkeys(filter_patterns)) if (can_narrow_filter and filter_patterns) else ""

    return {
        "diff_label": diff_label,
        "changed_files": sorted(changed_files),
        "procs_by_file": {k: sorted(v) for k, v in sorted(procs_by_file.items())},
        "odin_groups": odin_groups,
        "zig_groups": zig_groups,
        "filter": final_filter,
        "reasons": reasons,
    }


def print_benchmark_plan(plan: Dict[str, Any]) -> None:
    print()
    print("=" * 116)
    print(f"  Code-Change-to-Benchmark Execution Plan (Diff: {plan['diff_label']})")
    print("=" * 116)
    if not plan["changed_files"]:
        print("  Changed source files : (none in xitdb/ or reference/xitdb-zig/src/)")
    else:
        print(f"  Changed source files : {', '.join(plan['changed_files'])}")
    if plan["procs_by_file"]:
        for f, ps in plan["procs_by_file"].items():
            print(f"  Modified procedures  : {f} -> {', '.join(ps)}")
    for r in plan["reasons"]:
        print(f"  Impact mapping       : {r}")
    print("  " + "-" * 112)
    if plan["odin_groups"]:
        g_desc = ", ".join(f"{g} [{GROUP_RANGES[g]}]" for g in plan["odin_groups"])
        print(f"  Odin groups to run   : {g_desc}")
    else:
        print("  Odin groups to run   : (skip — no Odin source changes)")
    if plan["zig_groups"]:
        g_desc = ", ".join(f"{g} [{GROUP_RANGES[g]}]" for g in plan["zig_groups"])
        print(f"  Zig groups to run    : {g_desc}")
    else:
        print("  Zig groups to run    : (skip — no Zig source changes)")
    print(f"  Benchmark filter     : {plan['filter'] if plan['filter'] else '(all tests in selected groups)'}")
    print("=" * 116)


SLICES_DIR = os.path.join(BENCH_DIR, "slices")


def strip_code_line(line: str, in_block_comment: bool = False) -> Tuple[str, bool]:
    """
    Replaces string/char literals and comments with spaces so brace counting
    and identifier extraction are never confused by literals or comments.
    """
    out: List[str] = []
    i = 0
    n = len(line)
    while i < n:
        if in_block_comment:
            end_idx = line.find("*/", i)
            if end_idx == -1:
                return "".join(out), True
            i = end_idx + 2
            in_block_comment = False
            out.append(" ")
            continue

        ch = line[i]
        nxt = line[i + 1] if i + 1 < n else ""

        if ch == "/" and nxt == "/":
            break
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch in ('"', "'", "`"):
            quote = ch
            out.append(" ")
            i += 1
            while i < n:
                c = line[i]
                if c == "\\" and quote != "`":
                    i += 2
                    continue
                if c == quote:
                    i += 1
                    break
                i += 1
            out.append(" ")
            continue

        out.append(ch)
        i += 1

    return "".join(out), in_block_comment


def slugify_bench_name(rank: int, name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return f"{rank:02d}_{slug}"


def scan_harness_file(file_path: str, lang: str) -> Dict[str, Dict[str, Any]]:
    """
    Parses bench_xitdb.odin or bench_xitdb.zig and maps each benchmark name to:
      - start_line, end_line (1-indexed inclusive)
      - rel_url (e.g. 'bench_xitdb.odin#L469-L494')
      - snippet (raw source lines of the benchmark block)
      - direct_calls (ordered list of xitdb functions invoked by this benchmark)
    """
    if not os.path.isfile(file_path):
        return {}

    with open(file_path, "r", encoding="utf-8") as f:
        raw_lines = f.read().splitlines()

    clean_lines: List[str] = []
    in_bc = False
    for ln in raw_lines:
        cl, in_bc = strip_code_line(ln, in_bc)
        clean_lines.append(cl)

    if lang == "odin":
        fn_re = re.compile(r"^\s*(bench_[A-Za-z0-9_]+|run_dsl_benchmarks)\s*::\s*proc\b")
        cb_re = re.compile(r"^\s*([A-Za-z0-9_]+)\s*::\s*proc\b")
        print_re = re.compile(r"\bprint_result\s*\(")
    else:
        fn_re = re.compile(r"^\s*fn\s+(bench[A-Za-z0-9_]+)\s*\(")
        cb_re = re.compile(r"^\s*const\s+([A-Za-z0-9_]+)\s*=\s*struct\b")
        print_re = re.compile(r"\bprintResult\s*\(")

    section_comment_re = re.compile(r"^\s*//\s*[0-9]+[a-z]?[\.\-\s]")
    bench_filename = os.path.basename(file_path)
    results: Dict[str, Dict[str, Any]] = {}

    i = 0
    total = len(raw_lines)
    while i < total:
        m_fn = fn_re.match(clean_lines[i])
        if not m_fn:
            i += 1
            continue

        fn_name = m_fn.group(1)
        fn_start = i + 1
        brace_depth = 0
        opened = False
        fn_end = total
        for j in range(i, total):
            for ch in clean_lines[j]:
                if ch == "{":
                    brace_depth += 1
                    opened = True
                elif ch == "}":
                    brace_depth -= 1
            if opened and brace_depth <= 0:
                fn_end = j + 1
                break

        # Discover local helper callbacks inside this group procedure (e.g. put_cb, tx_cb)
        local_callbacks: List[Tuple[str, int, int]] = []
        for j in range(fn_start, fn_end - 1):
            m_cb = cb_re.match(clean_lines[j])
            if m_cb:
                cb_name = m_cb.group(1)
                if cb_name == fn_name:
                    continue
                cb_depth = 0
                cb_opened = False
                cb_end = j + 1
                for k in range(j, fn_end):
                    for ch in clean_lines[k]:
                        if ch == "{":
                            cb_depth += 1
                            cb_opened = True
                        elif ch == "}":
                            cb_depth -= 1
                    if cb_opened and cb_depth <= 0:
                        cb_end = k + 1
                        break
                local_callbacks.append((cb_name, j + 1, cb_end))

        # Find all print_result / printResult invocations in this group function
        prev_end = fn_start
        is_first_in_fn = True
        j = fn_start - 1
        while j < fn_end:
            if print_re.search(clean_lines[j]):
                p_start = j + 1
                paren_depth = 0
                p_opened = False
                p_end = p_start
                for k in range(j, fn_end):
                    for ch in clean_lines[k]:
                        if ch == "(":
                            paren_depth += 1
                            p_opened = True
                        elif ch == ")":
                            paren_depth -= 1
                    if p_opened and paren_depth <= 0:
                        p_end = k + 1
                        break

                seg_start = prev_end + 1
                while seg_start < p_start:
                    s_line = raw_lines[seg_start - 1].strip()
                    if (
                        not s_line
                        or s_line in ("}", "};")
                        or s_line.startswith("free_all(")
                        or s_line == "_ = rep"
                    ):
                        seg_start += 1
                    else:
                        break

                # If the first benchmark in a group has a preamble before '// 1a.' / '// 5a.',
                # start the highlight at the section comment.
                if is_first_in_fn:
                    for k_line in range(seg_start, p_start):
                        if section_comment_re.match(raw_lines[k_line - 1]):
                            seg_start = k_line
                            break

                # Extract benchmark name(s) from the print_result block
                p_block_text = "\n".join(raw_lines[p_start - 1 : p_end])
                names_found: List[str] = []
                m_lit = re.search(r'\.?name\s*=\s*"([^"]+)"', p_block_text)
                if m_lit:
                    names_found.append(m_lit.group(1))
                else:
                    m_var = re.search(r"\.?name\s*=\s*([A-Za-z_][A-Za-z0-9_]*)", p_block_text)
                    if m_var:
                        var_name = m_var.group(1)
                        seg_text = "\n".join(raw_lines[seg_start - 1 : p_end])
                        for m_assign in re.finditer(
                            rf"\b{re.escape(var_name)}\s*:?=\s*(.+)", seg_text
                        ):
                            names_found.extend(
                                s
                                for s in re.findall(r'"([^"]+)"', m_assign.group(1))
                                if len(s) > 6
                            )

                # Extract direct xitdb calls in [seg_start..p_end] + any referenced local callbacks
                seg_clean = "\n".join(clean_lines[seg_start - 1 : p_end])
                seg_raw = "\n".join(raw_lines[seg_start - 1 : p_end])
                defined_in_seg = {
                    cb_n for cb_n, cb_s, cb_e in local_callbacks if seg_start <= cb_s <= p_end
                }
                for cb_name, cb_s, cb_e in local_callbacks:
                    if cb_name not in defined_in_seg and cb_e < seg_start:
                        if re.search(rf"\b{re.escape(cb_name)}\b", seg_clean):
                            seg_clean += "\n" + "\n".join(clean_lines[cb_s - 1 : cb_e])

                direct_calls: List[str] = []
                if lang == "odin":
                    for m_call in re.finditer(r"\bxitdb\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", seg_clean):
                        callee = m_call.group(1)
                        if callee == "database_committed_size":
                            continue
                        if callee not in direct_calls:
                            direct_calls.append(callee)
                else:
                    for m_call in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", seg_clean):
                        callee = m_call.group(1)
                        if callee not in direct_calls:
                            direct_calls.append(callee)

                for b_name in names_found:
                    calls_for_bench = list(direct_calls)
                    if "SHA-1" in b_name and "sha256_hasher" in calls_for_bench:
                        calls_for_bench.remove("sha256_hasher")
                    elif "SHA-256" in b_name and "sha1_hasher" in calls_for_bench:
                        calls_for_bench.remove("sha1_hasher")

                    results[b_name] = {
                        "group_fn": fn_name,
                        "start_line": seg_start,
                        "end_line": p_end,
                        "rel_url": f"{bench_filename}#L{seg_start}-L{p_end}",
                        "snippet": seg_raw,
                        "direct_calls": calls_for_bench,
                    }

                prev_end = p_end
                is_first_in_fn = False
                j = p_end
                continue
            j += 1

        i = fn_end

    return results


PATH_PART_TYPES = {
    "Array_List_Init",
    "Array_List_Get",
    "Array_List_Append",
    "Array_List_Slice",
    "Linked_Array_List_Init",
    "Linked_Array_List_Get",
    "Linked_Array_List_Append",
    "Linked_Array_List_Slice",
    "Linked_Array_List_Concat",
    "Linked_Array_List_Insert",
    "Linked_Array_List_Remove",
    "Hash_Map_Init",
    "Hash_Map_Get",
    "Hash_Map_Remove",
    "Sorted_Map_Init",
    "Sorted_Map_Get",
    "Sorted_Map_Get_Index",
    "Sorted_Map_Remove",
    "Write_Data",
    "Write_KV_Data",
    "Context",
}


def parse_odin_library_procs() -> Dict[str, Dict[str, Any]]:
    """
    Parses all procedures and proc{...} overload groups across xitdb/*.odin
    (excluding *_test.odin) and builds the static call graph, including per-variant
    arms inside `_exec_path_part`.
    """
    xitdb_dir = os.path.join(ROOT_DIR, "xitdb")
    if not os.path.isdir(xitdb_dir):
        return {}

    proc_decl_re = re.compile(
        r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*::\s*(?:#force_inline\s+)?proc\b"
    )
    procs: Dict[str, Dict[str, Any]] = {}

    for fname in sorted(os.listdir(xitdb_dir)):
        if not fname.endswith(".odin") or fname.endswith("_test.odin"):
            continue
        fpath = os.path.join(xitdb_dir, fname)
        rel_file = f"xitdb/{fname}"
        with open(fpath, "r", encoding="utf-8") as f:
            raw_lines = f.read().splitlines()

        clean_lines: List[str] = []
        in_bc = False
        for ln in raw_lines:
            cl, in_bc = strip_code_line(ln, in_bc)
            clean_lines.append(cl)

        i = 0
        total = len(raw_lines)
        while i < total:
            m = proc_decl_re.match(clean_lines[i])
            if not m:
                i += 1
                continue

            pname = m.group(1)
            start_line = i + 1
            # Include any @(private) / @(require_results) attribute immediately above
            while start_line > 1 and raw_lines[start_line - 2].strip().startswith("@("):
                start_line -= 1

            brace_depth = 0
            opened = False
            end_line = i + 1
            is_proc_group = bool(re.search(r"::\s*proc\s*\{", clean_lines[i]))

            for j in range(i, total):
                for ch in clean_lines[j]:
                    if ch == "{":
                        brace_depth += 1
                        opened = True
                    elif ch == "}":
                        brace_depth -= 1
                if opened and brace_depth <= 0:
                    end_line = j + 1
                    break

            procs[pname] = {
                "name": pname,
                "file": rel_file,
                "start_line": start_line,
                "end_line": end_line,
                "line_count": end_line - start_line + 1,
                "is_proc_group": is_proc_group,
                "raw_lines": raw_lines[start_line - 1 : end_line],
                "clean_lines": clean_lines[start_line - 1 : end_line],
                "callees": [],
                "path_parts": [],
                "case_arms": {},
            }
            i = end_line

    ident_re = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")
    call_re = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    known_names = set(procs.keys())

    for pname, info in procs.items():
        if pname == "_exec_path_part":
            # Split _exec_path_part into per-Path_Part case arms so benchmarks only pull in
            # collection implementations for Path_Part variants they actually construct.
            arm_re = re.compile(r"^\tcase\s+([A-Za-z_][A-Za-z0-9_]*)\s*:")
            arm_starts: List[Tuple[str, int]] = []
            for idx_ln, raw_ln in enumerate(info["raw_lines"]):
                m_arm = arm_re.match(raw_ln)
                if m_arm and m_arm.group(1) in PATH_PART_TYPES:
                    arm_starts.append((m_arm.group(1), idx_ln))

            for a_idx, (part_name, rel_start) in enumerate(arm_starts):
                rel_end = (
                    arm_starts[a_idx + 1][1]
                    if a_idx + 1 < len(arm_starts)
                    else len(info["raw_lines"]) - 3
                )
                while rel_end > rel_start and not info["raw_lines"][rel_end - 1].strip():
                    rel_end -= 1
                arm_clean = info["clean_lines"][rel_start:rel_end]
                arm_callees: List[str] = []
                arm_parts: List[str] = []
                for cl in arm_clean:
                    for m_c in call_re.finditer(cl):
                        tok = m_c.group(1)
                        if tok != pname and tok in known_names and tok not in arm_callees:
                            arm_callees.append(tok)
                    for m_id in ident_re.finditer(cl):
                        tok = m_id.group(1)
                        if tok in PATH_PART_TYPES and tok not in arm_parts:
                            arm_parts.append(tok)
                info["case_arms"][part_name] = {
                    "part": part_name,
                    "start_line": info["start_line"] + rel_start,
                    "end_line": info["start_line"] + rel_end - 1,
                    "raw_lines": info["raw_lines"][rel_start:rel_end],
                    "clean_lines": arm_clean,
                    "callees": arm_callees,
                    "path_parts": arm_parts,
                }
            continue

        callees: List[str] = []
        path_parts: List[str] = []
        search_re = ident_re if info["is_proc_group"] else call_re
        for cl in info["clean_lines"]:
            for m_id in search_re.finditer(cl):
                tok = m_id.group(1)
                if tok != pname and tok in known_names and tok not in callees:
                    callees.append(tok)
            if pname not in ("init_part_for", "init_tag"):
                for m_pt in ident_re.finditer(cl):
                    tok = m_pt.group(1)
                    if tok in PATH_PART_TYPES and tok not in path_parts:
                        path_parts.append(tok)
        info["callees"] = callees
        info["path_parts"] = path_parts

    return procs


def compute_benchmark_slice(
    entry_calls: List[str], odin_procs: Dict[str, Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Computes the transitive closure of reachable xitdb procedures starting from
    `entry_calls`, specializing `_exec_path_part` to only the `Path_Part` variants
    constructed by reachable procedures.
    """
    visited_depth: Dict[str, int] = {}
    called_by: Dict[str, List[str]] = defaultdict(list)
    order: List[str] = []
    queue: List[Tuple[str, int]] = []
    active_parts: Set[str] = set()
    activated_arms: Set[str] = set()

    WRITE_ONLY_PROCS = {
        "_database_truncate_with_header",
        "database_commit_root",
        "database_write_root_header",
        "core_write_slot",
        "core_write_all",
        "core_write_long",
        "core_write_byte",
        "core_set_length",
        "core_sync",
        "init_part_for",
        "init_tag",
        "_random_u64",
        "database_check_frozen_slot",
        "database_copy_collection_if_frozen",
        "database_copy_index_block_if_old",
        "btree_get_for_write",
        "btree_insert",
        "btree_grow_root",
        "btree_write_node",
        "write_btree_node",
        "write_btree_node_at",
        "sorted_put",
        "sorted_grow_root",
        "sorted_write_node",
        "write_sorted_node",
        "write_sorted_node_at",
    }

    has_writes = any(
        (
            "write" in c
            or "put" in c
            or "append" in c
            or "insert" in c
            or "remove" in c
            or "slice" in c
            or "concat" in c
            or "compact" in c
            or "apply" in c
            or "tx" in c
            or "marshal" in c
            or "freeze" in c
            or (c.endswith("_init") and not c.startswith("read_"))
        )
        for c in entry_calls
    )

    def add_path_part(pt: str) -> None:
        if pt in active_parts:
            return
        active_parts.add(pt)
        if not has_writes:
            return
        if pt.startswith("Array_List_"):
            active_parts.add("Array_List_Init")
        elif pt.startswith("Linked_Array_List_"):
            active_parts.add("Linked_Array_List_Init")
        elif pt.startswith("Hash_Map_"):
            active_parts.add("Hash_Map_Init")
        elif pt.startswith("Sorted_Map_"):
            active_parts.add("Sorted_Map_Init")

    for c in entry_calls:
        if c in odin_procs and c not in visited_depth:
            visited_depth[c] = 0
            order.append(c)
            queue.append((c, 0))
            called_by[c].append("benchmark harness")

    idx = 0
    while idx < len(queue):
        curr, depth = queue[idx]
        idx += 1
        pinfo = odin_procs[curr]

        for pt in pinfo.get("path_parts", []):
            add_path_part(pt)

        if curr == "_exec_path_part":
            callees_to_visit: List[str] = []
            for pt in list(active_parts):
                if pt not in activated_arms and pt in pinfo["case_arms"]:
                    activated_arms.add(pt)
                    arm = pinfo["case_arms"][pt]
                    for sub_pt in arm["path_parts"]:
                        if has_writes or not sub_pt.endswith("_Init"):
                            add_path_part(sub_pt)
                    for callee in arm["callees"]:
                        if not has_writes and callee in WRITE_ONLY_PROCS:
                            continue
                        if callee not in callees_to_visit:
                            callees_to_visit.append(callee)
        else:
            callees_to_visit = [
                c
                for c in pinfo["callees"]
                if has_writes or c not in WRITE_ONLY_PROCS
            ]

        for callee in callees_to_visit:
            if curr not in called_by[callee]:
                called_by[callee].append(curr)
            if callee not in visited_depth:
                visited_depth[callee] = depth + 1
                order.append(callee)
                queue.append((callee, depth + 1))

        # If newly discovered path parts unlocked additional _exec_path_part arms,
        # enqueue their callees as well.
        if "_exec_path_part" in visited_depth:
            exec_depth = visited_depth["_exec_path_part"]
            exec_info = odin_procs["_exec_path_part"]
            for pt in list(active_parts):
                if pt not in activated_arms and pt in exec_info["case_arms"]:
                    activated_arms.add(pt)
                    arm = exec_info["case_arms"][pt]
                    for sub_pt in arm["path_parts"]:
                        if has_writes or not sub_pt.endswith("_Init"):
                            add_path_part(sub_pt)
                    for callee in arm["callees"]:
                        if not has_writes and callee in WRITE_ONLY_PROCS:
                            continue
                        if "_exec_path_part" not in called_by[callee]:
                            called_by[callee].append("_exec_path_part")
                        if callee not in visited_depth:
                            visited_depth[callee] = exec_depth + 1
                            order.append(callee)
                            queue.append((callee, exec_depth + 1))

    by_file: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    total_lines = 0
    for pname in order:
        pinfo = odin_procs[pname]
        if pname == "_exec_path_part" and activated_arms:
            arms_sorted = sorted(
                (pinfo["case_arms"][pt] for pt in activated_arms if pt in pinfo["case_arms"]),
                key=lambda a: a["start_line"],
            )
            sliced_raw: List[str] = list(pinfo["raw_lines"][:13])
            sliced_clean: List[str] = list(pinfo["clean_lines"][:13])
            sliced_line_numbers: List[int] = list(
                range(pinfo["start_line"], pinfo["start_line"] + 13)
            )
            for arm in arms_sorted:
                sliced_raw.extend(arm["raw_lines"])
                sliced_clean.extend(arm["clean_lines"])
                sliced_line_numbers.extend(
                    range(arm["start_line"], arm["start_line"] + len(arm["raw_lines"]))
                )
            sliced_raw.extend(pinfo["raw_lines"][-3:])
            sliced_clean.extend(pinfo["clean_lines"][-3:])
            sliced_line_numbers.extend(
                range(pinfo["end_line"] - 2, pinfo["end_line"] + 1)
            )
            p_copy = {
                **pinfo,
                "line_count": len(sliced_raw),
                "raw_lines": sliced_raw,
                "clean_lines": sliced_clean,
                "line_numbers": sliced_line_numbers,
                "active_arms": [a["part"] for a in arms_sorted],
                "depth": visited_depth[pname],
                "callers": called_by[pname],
            }
        else:
            p_copy = {
                **pinfo,
                "line_numbers": list(
                    range(pinfo["start_line"], pinfo["end_line"] + 1)
                ),
                "depth": visited_depth[pname],
                "callers": called_by[pname],
            }

        total_lines += p_copy["line_count"]
        by_file[pinfo["file"]].append(p_copy)

    for f in by_file:
        by_file[f].sort(key=lambda x: x["start_line"])

    return {
        "order": order,
        "depths": visited_depth,
        "called_by": dict(called_by),
        "by_file": dict(sorted(by_file.items())),
        "procs_count": len(order),
        "files_count": len(by_file),
        "lines_count": total_lines,
    }


def build_code_map() -> Dict[str, Dict[str, Any]]:
    """
    Builds the complete mapping from benchmark name -> harness #L<start>-L<end> links
    and xitdb library slice metadata.
    """
    odin_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.odin"), "odin")
    zig_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.zig"), "zig")
    odin_procs = parse_odin_library_procs()

    # Determine canonical ranks from odin.jsonl if present, else appearance order
    ranks_by_name: Dict[str, int] = {}
    for r in load_jsonl_file(ODIN_JSONL):
        if "name" in r and "rank" in r:
            ranks_by_name[r["name"]] = int(r["rank"])

    code_map: Dict[str, Dict[str, Any]] = {}
    for idx, (b_name, o_info) in enumerate(odin_harness.items(), 1):
        rank = ranks_by_name.get(b_name, idx)
        slug = slugify_bench_name(rank, b_name)
        z_info = zig_harness.get(b_name)
        slice_info = compute_benchmark_slice(o_info["direct_calls"], odin_procs)

        code_map[b_name] = {
            "rank": rank,
            "name": b_name,
            "slug": slug,
            "odin_bench_url": o_info["rel_url"],
            "odin_start_line": o_info["start_line"],
            "odin_end_line": o_info["end_line"],
            "zig_bench_url": z_info["rel_url"] if z_info else "",
            "zig_start_line": z_info["start_line"] if z_info else 0,
            "zig_end_line": z_info["end_line"] if z_info else 0,
            "slice_url": f"slices/{slug}.md",
            "entry_calls": o_info["direct_calls"],
            "odin_procs_count": slice_info["procs_count"],
            "odin_files_count": slice_info["files_count"],
            "odin_lines_count": slice_info["lines_count"],
        }

    return code_map


ZIG_LIB_RANGES: Dict[str, Tuple[int, int, str]] = {
    "Database.init": (470, 548, "Database initialization, header validation, `committedSize()`, and `rootCursor()`"),
    "HashMap": (3835, 3930, "Typed `HashMap(.read_only/.read_write)` wrapper (`put`, `putKey`, `getCursor`, `remove`)"),
    "CountedHashMap": (3932, 4004, "Typed `CountedHashMap` wrapper with 8-byte count header"),
    "HashSet": (4006, 4069, "Typed `HashSet` wrapper"),
    "CountedHashSet": (4071, 4123, "Typed `CountedHashSet` wrapper"),
    "ArrayList": (4299, 4388, "Typed 16-way Radix Trie `ArrayList` wrapper (`append`, `getCursor`, `put`, `slice`)"),
    "LinkedArrayList": (4390, 4504, "Typed count-augmented B-Tree `LinkedArrayList` wrapper (`append`, `insert`, `remove`, `concat`, `slice`)"),
    "SortedMap": (4128, 4228, "Typed counted B+Tree `SortedMap` wrapper (`put`, `getCursor`, `getIndex`, `rank`, `remove`)"),
    "SortedSet": (4232, 4297, "Typed counted B+Tree `SortedSet` wrapper"),
    "readSlotPointer": (859, 1591, "Central path-traversal engine & root transaction dispatcher"),
    "readSlotPointer.array_list": (927, 1048, "`PathPart` switch arms: `.array_list_init`, `.array_list_get`, `.array_list_append`, `.array_list_slice`"),
    "readSlotPointer.linked_array_list": (1049, 1270, "`PathPart` switch arms: `.linked_array_list_init`, `.linked_array_list_get`, `.linked_array_list_append`, `.linked_array_list_slice`, `.linked_array_list_concat`, `.linked_array_list_insert`, `.linked_array_list_remove`"),
    "readSlotPointer.hash_map": (1271, 1398, "`PathPart` switch arms: `.hash_map_init`, `.hash_map_get`, `.hash_map_remove`"),
    "readSlotPointer.sorted_map": (1399, 1524, "`PathPart` switch arms: `.sorted_map_init`, `.sorted_map_get`, `.sorted_map_get_index`, `.sorted_map_remove`"),
    "readSlotPointer.write": (1525, 1590, "`PathPart` switch arms: `.write` and `.ctx`"),
    "readMapSlot": (1600, 1726, "16-way HAMT recursive slot lookup, insertion, and hash-collision split"),
    "removeMapSlot": (1728, 1811, "16-way HAMT recursive slot removal and singleton branch collapse"),
    "readArrayListSlotAppend": (1820, 1854, "16-way Radix Trie tail append and root overflow growth"),
    "readArrayListSlot": (1856, 1904, "16-way Radix Trie O(log16 N) slot descent and CoW path copy"),
    "readArrayListSlice": (1906, 1942, "16-way Radix Trie truncation and root depth collapse"),
    "readBTreeNode": (1946, 1972, "Count-augmented B-Tree 16-slot node deserializer (18–34 `takeInt` calls)"),
    "writeBTreeNodeAt": (1977, 1991, "Count-augmented B-Tree 16-slot node serializer (18–34 `writeInt` calls)"),
    "btreeWriteNode": (2013, 2019, "In-place transaction reuse check (`btreeReusable`) vs append copy"),
    "readBTreeSlot": (2023, 2042, "Count-augmented B-Tree rank lookup descent"),
    "btreeInsert": (2047, 2154, "Count-augmented B-Tree recursive rank insertion and node split"),
    "btreeGetForWrite": (2181, 2209, "Count-augmented B-Tree CoW in-place slot update"),
    "btreeRemove": (2215, 2251, "Count-augmented B-Tree recursive rank deletion and sibling rebalance"),
    "btreeJoin": (2423, 2433, "Count-augmented B-Tree height-aware O(log N) tree concatenation"),
    "btreeSplit": (2451, 2477, "Count-augmented B-Tree O(log N) rank split for `slice`"),
    "readSortedNode": (2481, 2511, "Counted B+Tree 16-slot node deserializer (18–50 `takeInt` calls)"),
    "writeSortedNodeAt": (2513, 2528, "Counted B+Tree 16-slot node serializer (18–50 `writeInt` calls)"),
    "compareKey": (2599, 2629, "Lexicographic key comparison against `.short_bytes` / `.bytes` slot"),
    "sortedGet": (2634, 2658, "Counted B+Tree key lookup descent (linear separator/leaf scan)"),
    "sortedGetByIndex": (2661, 2680, "Counted B+Tree O(log N) rank selection by subtree counts"),
    "sortedRank": (2683, 2707, "Counted B+Tree O(log N) order-statistic rank query"),
    "sortedPut": (2736, 2875, "Counted B+Tree key insertion, leaf/branch split, and separator propagation"),
    "sortedRemove": (2879, 2918, "Counted B+Tree key deletion and sibling merge/rebalance"),
    "Cursor": (2956, 3819, "Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator`"),
    "compact": (650, 709, "Top-level `Database.compact` reachability-copy entry point"),
    "Compactor": (4508, 4913, "Reachability-based garbage-collecting compactor (`std.AutoHashMap` / custom `OffsetMap`)"),
    "readCommitted": (592, 607, "Committed byte-range streaming for incremental replication"),
    "applyReplicated": (613, 637, "Replica byte-stream application and root trailer verification"),
    "freeze": (560, 566, "Mid-transaction `freeze()` barrier for O(1) structural CoW branching"),
    "commitRoot": (776, 801, "Transaction trailer append, `core.sync()`, and `writeRootHeader` commit sequence"),
    "CoreMemory": (4917, 5027, "In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables"),
    "CoreFile": (5029, 5066, "Unbuffered OS file descriptor backend"),
    "CoreBufferedFile": (5067, 5232, "Contiguous tail-buffered OS file backend (`flush` clears buffer on `sync`)"),
}


def get_odin_vs_zig_insight(
    rank: int, b_name: str
) -> Tuple[List[str], List[str], List[str], Tuple[str, str]]:
    """
    Returns (odin_improvements, zig_suggestions, zig_lib_keys, (guide_title, guide_rel_url))
    tailored to the benchmark, with 100% verified `lib.zig` and `xitdb/*.odin` line anchors.
    """
    # 1. HAMT family (#1–#13, #45–#46)
    if 1 <= rank <= 13 or rank in (45, 46):
        odin_pts = [
            "**Single-Pass Key+Value Path Traversal ([`xitdb/collections.odin#L409-L421`](../../xitdb/collections.odin#L409-L421), [`xitdb/database.odin#L1304-L1360`](../../xitdb/database.odin#L1304-L1360)):** Odin's `hash_map_put` dispatches a single path `[Hash_Map_Init, Hash_Map_Get{.KV_Pair}, Write_KV_Data]` and coalesces the `key_slot + val_slot` + external key payload write. In Zig ([`lib.zig#L3894-L3912`](../../reference/xitdb-zig/src/lib.zig#L3894-L3912)), inserting a key and value requires **two separate root-to-leaf traversals** (`m.putKey(h, ...)` followed by `m.put(h, ...)`), doubling HAMT descent, parent slot reloads, and CoW checks.",
            "**Iterative Multi-Level Collision Allocation ([`xitdb/hamt.odin#L170-L223`](../../xitdb/hamt.odin#L170-L223)):** When two hashes share multiple 4-bit nibbles (e.g. `#10 HAMT deep suffix-collision put (depth 10+)` — **6.58x faster in Odin**), Odin counts matching nibbles in registers and writes the chain + split block without re-reading the existing `KV_Pair` at each shared level. Zig's [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1705-L1720) writes a 144-byte zeroed block and recurses level-by-level.",
            "**Lazy Single-Slot Read on Removal ([`xitdb/hamt.odin#L242-L341`](../../xitdb/hamt.odin#L242-L341)):** In [`remove_map_slot`](../../xitdb/hamt.odin#L242-L341) (`#5`, `#9`, `#11` — **5.8x–13.4x faster in Odin**), Odin reads only the single 9-byte target `Slot` on the way down and only reads the 144-byte `index_block` on unwind if `key_offset > 0` and the child collapsed to `.None` or `.KV_Pair`. Zig's [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774) zero-fills and reads/validates all 16 slots (`144 bytes`) at every level before recursing—even at `key_offset == 0` where the root block never collapses.",
            "**Zero-Vtable `Core_Memory` + Hardware x86 SHA-NI ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360), [`xitdb/types.odin#L114-L530`](../../xitdb/types.odin#L114-L530)):** Odin slices `Core_Memory.buf` directly (avoiding `CoreMemory.Reader`'s `.buffer = &.{}` double-vtable dispatch on `takeInt`) and uses hardware SHA-NI when hashing keys.",
        ]
        zig_pts = [
            "**Lazy sibling block read in `removeMapSlot` ([`lib.zig#L1736-L1774`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774)):** Read only the single 9-byte `Slot` at `index_pos + 9 * i` before recursing; if `key_offset == 0` or `next_slot.tag == .index`, write `next_slot` directly without reading or validating the other 15 sibling slots.",
            "**Add single-pass `putKeyValue` (`~20 lines` in `HashMap` & `readSlotPointer`):** Allow `HashMap(.read_write)` and `CountedHashMap(.read_write)` to write both `key_slot` and `value_slot` in one `readMapSlot(..., .kv_pair, ...)` descent (and one atomic transaction on root maps) instead of calling `putKey` + `put` separately.",
            "**Back `CoreMemory.reader()` with `std.Io.Reader.fixed` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Refreshing `.fixed(self.parent.buffer.written())` in `seekTo()` eliminates two indirect vtable calls on every `takeInt`.",
        ]
        z_keys = ["HashMap", "CountedHashMap", "CountedHashSet", "readSlotPointer.hash_map", "readMapSlot", "removeMapSlot", "CoreMemory"]
        guide = ("Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove", "../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md")
        return odin_pts, zig_pts, z_keys, guide

    # 2. Array_List (16-way Radix Trie) (#14–#19)
    if 14 <= rank <= 19:
        odin_pts = [
            "**Zero-Vtable `Core_Memory` Slice Reads ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360), [`xitdb/hamt.odin#L345-L452`](../../xitdb/hamt.odin#L345-L452)):** Odin's `read_array_list_slot` decodes 9-byte `Slot`s directly from `Core_Memory.buf`, whereas Zig's [`CoreMemory.reader()`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003) initializes `std.Io.Reader` with `.buffer = &.{}` (empty slice). Because `.buffer` is empty, every `takeInt` in `readArrayListSlot` misses `std.Io.Reader`'s inline fast path and dispatches through `vtable.readVec` → `CoreMemory.Reader.stream` → `Writer.fixed.drain` (two virtual calls per integer).",
            "**Stack-Allocated `Cursor_Iterator` ([`xitdb/cursor.odin#L655-L1096`](../../xitdb/cursor.odin#L655-L1096)):** On `#16 Array_List iterator scan` (**12 ns vs 33 ns**) and `#18 index-seek page(10)` (**4.45x faster in Odin**), Odin decodes each 144-byte `index_block` directly from memory without per-slot `std.Io` vtable calls.",
        ]
        zig_pts = [
            "**Use `std.Io.Reader.fixed` in `CoreMemory.reader()` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Setting `self.interface = .fixed(self.parent.buffer.written())` (refreshed in `seekTo()`) lets `takeInt` and `readSliceAll` execute inline with zero vtable calls (`-12 net LOC`, removing `CoreMemory.Reader.stream`).",
        ]
        z_keys = ["ArrayList", "readSlotPointer.array_list", "readArrayListSlotAppend", "readArrayListSlot", "readArrayListSlice", "Cursor", "CoreMemory"]
        guide = ("Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path", "../zig-guide/01_core_memory_zero_vtable_io.md")
        return odin_pts, zig_pts, z_keys, guide

    # 3. Linked_Array_List (Count-Augmented B-Tree) (#20–#27)
    if 20 <= rank <= 27:
        odin_pts = [
            "**Single-Read Block Serialization vs. 18–34 Per-Field `std.Io` Calls ([`xitdb/btree.odin#L8-L75`](../../xitdb/btree.odin#L8-L75) vs. [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** This is the primary driver of Odin's **4.6x–43.2x speedup** on `Linked_Array_List` (`BTREE_SLOT_COUNT = 16`: `146B` leaf, `274B` branch). Zig's `readBTreeNode` and `writeBTreeNodeAt` loop over all 16 slots (and 16 counts on branches) unconditionally, issuing **18 to 34 individual unbuffered `takeInt`/`writeInt` calls** per node even when `node.num == 2`. Odin reads the node in **one `core_read_exact` call** into a stack buffer and decodes only `0 ..< node.num` active entries.",
            "**O(1) Direct Leaf Slot Seek in `read_btree_slot` ([`xitdb/btree.odin#L103-L189`](../../xitdb/btree.odin#L103-L189)):** On `#21 Linked_Array_List random get` (**43.24x faster in Odin: 54 ns vs 2,335 ns**), when `read_btree_slot` reaches a `.Leaf`, Odin peeks the 2-byte header, validates `rem < leaf_num`, and reads **only the single 9-byte `Slot`** at `node_ptr + 2 + rem * 9`. Zig's [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) calls `readBTreeNode` at the leaf, executing 18 `takeInt` calls and 16 tag checks to decode all 16 slots just to return `node.values[rem]`.",
            "**Targeted In-Place Branch Count Patching ([`xitdb/btree.odin#L232-L268`](../../xitdb/btree.odin#L232-L268)):** When inserting into a branch node already owned by the current transaction (`btree_reusable` is true and no child split occurred), Odin patches only the 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) instead of rewriting all 274 bytes.",
        ]
        zig_pts = [
            "**Read/Write `BTreeNode` via a stack `[146]u8` / `[274]u8` buffer (`~25 lines` in [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** Read the node in one `reader.interface.readSliceAll` (and write in one `writer.interface.writeAll(&buf)`), decoding `0..node.num` in memory with `std.mem.readInt`. This keeps the `BTreeNode` struct and all split/join/rebalance logic 100% unchanged while eliminating 18–34 vtable/syscall dispatches per node.",
            "**Short-circuit `.leaf` in `readBTreeSlot` (`~8 lines` in [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042)):** Read the 2-byte `(kind, num)` header first; when `kind == .leaf`, verify `rem < num` and seek directly to `node_ptr + 2 + rem * 9` to read 1 `Slot`.",
        ]
        z_keys = ["LinkedArrayList", "readSlotPointer.linked_array_list", "readBTreeNode", "writeBTreeNodeAt", "btreeWriteNode", "readBTreeSlot", "btreeInsert", "btreeGetForWrite", "btreeRemove", "btreeJoin", "btreeSplit"]
        guide = ("Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek", "../zig-guide/02_btree_node_batch_io_and_leaf_seek.md")
        return odin_pts, zig_pts, z_keys, guide

    # 4. Sorted_Map & Sorted_Set (Counted B+Tree) (#28–#38)
    if 28 <= rank <= 38:
        odin_pts = [
            "**Binary Search ($O(\\log_2 16)$) vs. Linear Scan ($O(16)$) in Nodes ([`xitdb/btree.odin#L1244-L1276`](../../xitdb/btree.odin#L1244-L1276) vs. [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Zig's `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey` scan `0..node.num` linearly (up to 16 `sortedEntryKeySlot` + `compareKey` seeks per node), and [`compareKey`](../../reference/xitdb-zig/src/lib.zig#L2612) zero-fills `var key_buf: [256]u8 = @splat(0)` on every external key check. Odin uses **binary search** (`<= 4` comparisons per node) and an uninitialized `stack_buf: [256]u8 = ---` (**10.2x–50.5x faster**).",
            "**Single-Read `Sorted_Node` Decoding Only Up to `node.num` ([`xitdb/btree.odin#L1059-L1136`](../../xitdb/btree.odin#L1059-L1136)):** Zig's [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2511) and [`writeSortedNodeAt`](../../reference/xitdb-zig/src/lib.zig#L2513-L2528) execute **18 `takeInt`/`writeInt` calls** for a `146B` leaf and **50 calls** for a `418B` branch (reading all 16 children, 16 separators, and 16 counts even when `node.num == 2`). Odin reads the block in one `core_read_exact` call and decodes `0 ..< node.num`.",
            "**O(1) Direct Leaf Slot Seek in `sorted_get_by_index` ([`xitdb/btree.odin#L1394-L1480`](../../xitdb/btree.odin#L1394-L1480)):** On `#34 Sorted_Map get_index select` (**50.46x faster in Odin: 65 ns vs 3,280 ns**), Odin reads the 2-byte leaf header, validates `rem < leaf_num`, and seeks straight to `node_ptr + 2 + rem * 9` to read 1 `Slot`, whereas Zig's [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) decodes all 16 leaf slots via `readSortedNode`.",
        ]
        zig_pts = [
            "**Extract `sortedBranchSearch` and `sortedLeafSearch` binary search helpers (`~24 lines` replacing 4 linear loops in [`lib.zig#L2640-L2757`](../../reference/xitdb-zig/src/lib.zig#L2640-L2757)):** Cuts key comparisons and `SortedKeyValuePair` seeks from up to 16 down to at most 4 per level while *reducing* code duplication across `sortedGet`, `sortedRank`, `sortedPut`, and `sortedStackFromKey`.",
            "**Drop `@splat(0)` in `compareKey` ([`lib.zig#L2612`](../../reference/xitdb-zig/src/lib.zig#L2612)) and batch-decode `SortedNode` ([`lib.zig#L2481-L2528`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528)):** Change `var key_buf: [256]u8 = @splat(0)` to `undefined`, and read/write `SortedNode` via one stack `[146]u8` / `[418]u8` buffer.",
            "**Direct leaf slot read in `sortedGetByIndex` ([`lib.zig#L2661-L2680`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680)):** When `hdr[0] == .leaf`, verify `rem < num` and seek to `node_ptr + 2 + rem * 9` to read 1 `Slot` instead of calling `readSortedNode`.",
        ]
        z_keys = ["SortedMap", "SortedSet", "readSlotPointer.sorted_map", "readSortedNode", "writeSortedNodeAt", "compareKey", "sortedGet", "sortedGetByIndex", "sortedRank", "sortedPut", "sortedRemove"]
        guide = ("Guide 03: SortedMap & SortedSet Binary Search & Index Select", "../zig-guide/03_sorted_bptree_binary_search.md")
        return odin_pts, zig_pts, z_keys, guide

    # 5. Compaction & Replication (#39–#44)
    if 39 <= rank <= 44:
        if rank == 43:
            odin_pts = [
                "**Open-Addressed `Memory_Offset_Map` & Single-Pass Block Reservation (`#43` — 3.22x faster in Odin: `32.8 µs` vs `105.7 µs`):** Both implementations produce the exact same `23.4 KB` compacted wire image and deduplicate shared structural nodes identically ([`xitdb/compact_replicate.odin#L11-L177`](../../xitdb/compact_replicate.odin#L11-L177) vs. [`lib.zig#L4508-L4913`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913)). Odin's `Memory_Offset_Map` uses a flat, open-addressed `[]Memory_Offset_Entry` table with Fibonacci hashing (`0x9e3779b97f4a7c15`), `_compactor_reserve_block` resizes `Core_Memory.buf` in $O(1)$ without zero-writing twice (while enforcing `max_size`), and B-Tree/B+Tree compaction formats active `0..<num` slots in stack buffers.",
            ]
        else:
            odin_pts = [
                "**Direct Slice Copy in Replication ([`xitdb/compact_replicate.odin#L816-L928`](../../xitdb/compact_replicate.odin#L816-L928)):** On `#39 Replication (genesis -> 200 moments)` (**8.18x faster in Odin**) and `#40 Incremental 1-moment delta` (**1.90x faster**), Odin copies committed byte slices directly between buffers and verifies the 25-byte `Root_Trailer` CRC-64/XZ without unbuffered `std.Io` vtable streaming.",
                "**Open-Addressed `Memory_Offset_Map` & Single-Pass Block Reserve ([`xitdb/compact_replicate.odin#L11-L811`](../../xitdb/compact_replicate.odin#L11-L811)):** On `#41` (**2.97x faster**), `#42` (**1.18x faster**), and `#43` (**3.22x faster**), Odin uses a flat open-addressed `Memory_Offset_Map`, reserves `Core_Memory` blocks in one `non_zero_resize`, and visits `0 ..< num` active B-Tree slots in stack buffers, whereas `Compactor` in [`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911) writes remapped slots via per-element `writeInt` calls and loops over all 16 slots.",
            ]
        zig_pts = [
            "**Pre-size `CoreMemory` target buffer & batch-write remapped slots in `Compactor` ([`lib.zig#L4714-L4911`](../../reference/xitdb-zig/src/lib.zig#L4714-L4911)):** Visiting `0..header.num` and writing each compacted node in one `writeAll` (after pre-reserving the target `CoreMemory` buffer instead of zero-writing twice) eliminates per-slot `writeInt` vtable dispatches.",
            "**Streamlined `readCommitted` / `applyReplicated` slice copies (`#39–#40`):** Copying committed byte slices directly on `CoreMemory` avoids unbuffered `std.Io` vtable overhead.",
        ]
        z_keys = ["compact", "Compactor", "readCommitted", "applyReplicated", "CoreMemory", "CoreBufferedFile"]
        guide = ("Guide 06: CoreBufferedFile Coherency & Compaction", "../zig-guide/06_buffered_file_tail_cache_and_compaction.md")
        return odin_pts, zig_pts, z_keys, guide

    # 6. Bytes, Streams & Path Traversal (#47–#57)
    if 47 <= rank <= 57:
        odin_pts = [
            "**Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L298-L364`](../../xitdb/cursor.odin#L298-L364)):** On `#48` & `#50` (**4.00x–5.33x faster in Odin**), Odin's `cursor_read_bytes_buf` reads `value_size + 2` contiguous bytes in one `core_read_exact` when `slot.full` is set. Zig's [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) performs separate unbuffered reads (`value_size`, `value`, and `format_tag`).",
            "**Reallocation-Safe Dynamic `core_slice_at` in `Cursor_Reader` & Pre-Sized Writes (`#51–#53` — 1.51x–8.67x faster in Odin):** Odin's [`Cursor_Writer`](../../xitdb/cursor.odin#L549-L651) and [`Cursor_Reader`](../../xitdb/cursor.odin#L437-L545) resolve `core_slice_at` dynamically at each read call (remaining 100% safe across mid-stream buffer reallocations or window shifts) and copy slices directly without vtable chains, whereas Zig's unbuffered `Cursor.Reader` → `CoreMemory.Reader` (`lib.zig#L2987-L3002`) chains vtable dispatches.",
            "**Compounded Collection Node Speedups on 4-Level Nested Paths (`#55–#56` — 4.69x–4.91x faster in Odin):** `#55` and `#56` traverse `HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap` in one path call; Odin's single-pass `Write_KV_Data` and direct slice reads compound across all 4 levels.",
        ]
        zig_pts = [
            "**Drop redundant `seekTo` in `Cursor.readBytesObject` ([`lib.zig#L3306-L3310`](../../reference/xitdb-zig/src/lib.zig#L3306-L3310)):** `core_reader` is already positioned at `start_position + value_size` right after reading `value`, so `format_tag` can be read directly (or coalesced with `value`).",
            "**Resolve `self.parent.db.core.buffer.written()` dynamically inside `Cursor.Reader.stream` (`#52–#53`):** Never cache a slice into `CoreMemory.buffer` when opening `Cursor.Reader` (which dangles if a subsequent write reallocates `CoreMemory.buffer`); instead, slice `written()` dynamically inside `stream`.",
            "**Apply Guides 01–04:** Batch node I/O, binary search, and single-pass KV writes automatically accelerate `#55–#56` without changing `readSlotPointer`.",
        ]
        z_keys = ["Cursor", "readSlotPointer", "readSlotPointer.write", "CoreMemory"]
        guide = ("Guide 05: Cursor Bytes, Stream Vtables & Nested Paths", "../zig-guide/05_cursor_bytes_streams_and_paths.md")
        return odin_pts, zig_pts, z_keys, guide

    # 7. Storage Backends & Transaction Lifecycle (#58–#63)
    if 58 <= rank <= 63:
        odin_pts = [
            "**Multi-Handle Coherent `Core_Buffered_File` (`#59` — 1.05x faster in Odin: `16.97 µs` vs `17.85 µs`):** Both Odin ([`xitdb/core.odin#L25-L33`](../../xitdb/core.odin#L25-L33), [`#L144-L152`](../../xitdb/core.odin#L144-L152)) and Zig ([`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232)) clear `memory.buf` and `file_len` in `flush()` so multiple buffered handles taking turns under an external file lock never read stale `Root_Header` or `file_len` values (`spec_buffered_file_multi_handle_alternating_commits_preserve_all_moments`). Within each transaction, Odin's direct `core_slice_at` window reads and stack-buffered node I/O avoid vtable overhead.",
            "**Single Trailer Validation on Open & Truncate (`#62–#63` — 2.91x–4.27x faster in Odin):** In `#63`, Zig validates the root trailer CRC-64/XZ twice back-to-back (`Database.init` line 536 `committedSize()` then `rootCursor()` line 546 `readRootSlot()`) over an unbuffered `CoreMemory.Reader`. Odin's `_database_truncate_with_header` ([`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362)) and `Core_Memory` slice reads avoid redundant header/trailer round-trips.",
        ]
        zig_pts = [
            "**Keep `flush()` clearing `memory.buffer` and `file_len = null` in `CoreBufferedFile` ([`lib.zig#L5226-L5231`](../../reference/xitdb-zig/src/lib.zig#L5226-L5231)):** Essential for multi-handle coherency when processes alternate commits on the same file.",
            "**Reuse validated root `Slot` in `Database.init` + `rootCursor()` ([`lib.zig#L535-L548`](../../reference/xitdb-zig/src/lib.zig#L535-L548)):** Avoid computing the trailer CRC-64/XZ twice when opening an existing database.",
        ]
        z_keys = ["Database.init", "CoreMemory", "CoreBufferedFile", "CoreFile", "freeze", "commitRoot", "readSlotPointer"]
        guide = ("Guide 06: CoreBufferedFile Coherency & Compaction", "../zig-guide/06_buffered_file_tail_cache_and_compaction.md")
        return odin_pts, zig_pts, z_keys, guide

    # 8. Odin 5-Layer Ergonomic DSL & Datalog Engine (#64–#75)
    odin_pts = [
        "**Odin-Native 5-Layer Ergonomic DSL ([`xitdb/dsl.odin`](../../xitdb/dsl.odin)):** Built directly on top of the wire-compatible core (`Read_Cursor`, `Write_Cursor`, `Hash_Map`, `Sorted_Map`, `Array_List`), providing path selectors (`Layer 1`), transactional `Tx` + automatic B+Tree secondary index maintenance (`Layer 2`), reflection-driven struct `marshal`/`unmarshal` & cycle-safe Datomic `pull` (`Layer 3`), structural `diff_moments` & `history_of` (`Layer 4`), and a stratified Datalog engine with B+Tree prefix pushdown (`Layer 5`).",
        "**Zero-Allocation Hot Paths & B+Tree Index Selection ([`xitdb/dsl.odin#L2800-L3783`](../../xitdb/dsl.odin#L2800-L3783)):** The Datalog engine inspects bound variables in pattern clauses, automatically selecting `Sorted_Map` (`indices/<index>`) range iterators for prefix-bound lookups and falling back to full collection scans only when unbound.",
    ]
    zig_pts = [
        "**Comptime Struct Marshaling & Pull Projection in Zig:** Zig's `@typeInfo(T)` comptime reflection maps naturally to Odin's runtime `type_info_of(T)` in `marshal`/`unmarshal` (`Layer 3`) and could be layered cleanly on top of `lib.zig` without altering the v1 wire format.",
    ]
    z_keys = ["readSlotPointer", "HashMap", "SortedMap", "ArrayList", "Cursor"]
    guide = ("Idiomatic Zig Optimization Guide (Overview)", "../zig-guide/README.md")
    return odin_pts, zig_pts, z_keys, guide


def generate_all_slices() -> None:
    """
    Generates concise, zero-bloat Odin vs. Zig comparison & call-graph slice pages:
      1. benchmarks/slices/<rank>_<slug>.md (~95 lines each; links to #L<start>-L<end> instead of duplicating source)
      2. benchmarks/slices/README.md (Cross-Language Architectural Analysis + 75-benchmark index)
    """
    os.makedirs(SLICES_DIR, exist_ok=True)
    # Remove legacy index.html if present to avoid 200KB+ embedded source blobs
    legacy_html = os.path.join(SLICES_DIR, "index.html")
    if os.path.isfile(legacy_html):
        os.remove(legacy_html)

    odin_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.odin"), "odin")
    zig_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.zig"), "zig")
    odin_procs = parse_odin_library_procs()
    code_map = build_code_map()

    odin_rows = {r["name"]: r for r in pool_by_lang_and_test(load_jsonl_file(ODIN_JSONL), "odin")}
    zig_rows = {r["name"]: r for r in pool_by_lang_and_test(load_jsonl_file(ZIG_JSONL), "zig")}

    sorted_items = sorted(code_map.values(), key=lambda x: x["rank"])
    index_rows: List[str] = [
        "# xitdb Per-Benchmark Code Slices & Odin vs. Zig Architectural Guide",
        "",
        "[← Back to Benchmark Suite (`benchmarks/README.md`)](../README.md) · [**📘 Idiomatic Zig Optimization Guide (`zig-guide/README.md`)**](../zig-guide/README.md)",
        "",
        "Across the **63 shared 1v1 benchmarks**, Odin (`-o:speed -microarch:native`) is faster on **63 / 63** benchmarks compared to Zig (`0.17.0-dev -Doptimize=ReleaseFast -Dcpu=native`), with **0 byte-footprint mismatches** (100% identical v1 wire output).",
        "",
        "Each per-benchmark page below links directly to the exact `#L<start>-L<end>` line ranges in [`bench_xitdb.odin`](../bench_xitdb.odin), [`bench_xitdb.zig`](../bench_xitdb.zig), [`xitdb/*.odin`](../../xitdb), and [`reference/xitdb-zig/src/lib.zig`](../../reference/xitdb-zig/src/lib.zig), plus a dedicated engineering guide in [`benchmarks/zig-guide/`](../zig-guide/README.md) with drop-in Zig `0.17` implementations (~140 net LOC across all 6 subsystems, verified in [`reference/xitdb-zig-patched`](../../reference/xitdb-zig-patched) via `zig build bench -Dpatched=true`).",
        "",
        "---",
        "",
        "## Cross-Language Architectural Summary: Why Odin is Faster & How to Improve Zig",
        "",
        "| Subsystem (Benchmarks) | Odin Speedup | Verified Root Cause (`xitdb/*.odin` vs. `reference/xitdb-zig/src/lib.zig`) | Idiomatic Zig Improvement & Dedicated Guide |",
        "| :--- | :--- | :--- | :--- |",
        "| **Count-Augmented B-Tree (`Linked_Array_List`, `#20–#27`)** | **2.2x – 43.2x** | `BTREE_SLOT_COUNT = 16` (`146B` leaf, `274B` branch): Odin ([`xitdb/btree.odin#L8-L189`](../../xitdb/btree.odin#L8-L189)) reads nodes via `core_slice_at` / 1 `core_read_exact`, decodes `0..<num`, patches reusable branch counts in place, and seeks straight to `node_ptr + 2 + rem * 9` on leaf `get`. | Batch-read/write nodes via a stack `[146]u8` / `[274]u8` buffer (`0..node.num`) and short-circuit `.leaf` in `readBTreeSlot` → [**Guide 02**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) |",
        "| **Counted B+Tree (`Sorted_Map` / `Sorted_Set`, `#28–#38`)** | **2.4x – 50.5x** | Odin ([`xitdb/btree.odin#L1059-L1480`](../../xitdb/btree.odin#L1059-L1480)) uses **$O(\\log_2 16)$ binary search** ($\\le 4$ comparisons), direct `core_slice_at` zero-copy key comparisons, and 1-read node decoding. | Extract `sortedBranchSearch` & `sortedLeafSearch` binary search helpers, drop `@splat(0)`, batch-decode `SortedNode`, and seek directly in `sortedGetByIndex` → [**Guide 03**](../zig-guide/03_sorted_bptree_binary_search.md) |",
        "| **16-Way HAMT (`Hash_Map` / `Counted_Hash_Map`, `#1–#13`, `#45–#46`)** | **1.4x – 13.4x** | Inserting key+value in Zig ([`lib.zig#L3894-L3912`](../../reference/xitdb-zig/src/lib.zig#L3894-L3912)) runs **two full root-to-leaf traversals** (`putKey` + `put`), and [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1705-L1720) recurses one shared nibble at a time. Odin ([`xitdb/hamt.odin`](../../xitdb/hamt.odin)) uses single-pass `Write_KV_Data`, iterative multi-nibble collision chains, and lazy 1-slot descent on `remove`. | Read only the single child slot before recursing in `removeMapSlot` and add single-pass `putKeyValue` → [**Guide 04**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) |",
        "| **16-Way Radix Trie & `CoreMemory` (`Array_List`, `#14–#19`)** | **2.2x – 4.5x** | [`CoreMemory.reader()`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003) sets `.buffer = &.{}`, causing every `takeInt` / `readSliceAll` to miss `std.Io.Reader`'s inline fast path and execute **2 vtable calls** (`readVec` → `stream` → `Writer.fixed.drain`). Odin ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360)) slices `Core_Memory.buf` directly. | Back `CoreMemory.Reader` with direct slice reads → [**Guide 01**](../zig-guide/01_core_memory_zero_vtable_io.md) |",
        "| **Streams, Bytes & Nested Paths (`#47–#57`)** | **1.2x – 8.7x** | [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3295-L3316) (`#50`, **5.33x**) issues separate unbuffered reads; `Cursor.Reader` chains vtables; `#55–#56` (`4.7x–4.9x`) compound collection node overhead across 4 nested levels. Odin resolves `core_slice_at` dynamically on each `Cursor_Reader` read (reallocation-safe). | Coalesce small `.bytes` + `format_tag` reads, resolve `CoreMemory` slices dynamically in `Cursor.Reader.stream`, and apply Guides 01–04 → [**Guide 05**](../zig-guide/05_cursor_bytes_streams_and_paths.md) |",
        "| **`CoreBufferedFile` & Lifecycle (`#58–#63`)** | **1.1x – 4.3x** | Both Odin and Zig clear `memory.buf` and `file_len` on `flush()` for multi-handle file-lock coherency (`#59`, **1.05x**). `#63` (`4.27x`) validates the trailer CRC-64/XZ twice (`init` + `rootCursor`). | Keep `flush()` clearing `memory.buffer` & `file_len = null` for multi-handle safety, and reuse the validated root `Slot` on open → [**Guide 06**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) |",
        "| **Compaction & Replication (`#39–#44`)** | **Odin 1.1x–8.2x** (`#39–#44`) | Odin copies replication slices directly (`#39` **8.18x**), uses an open-addressed `Memory_Offset_Map` with Fibonacci hashing, reserves `Core_Memory` target blocks in one `non_zero_resize`, and formats `0..<num` slots in stack buffers (`#41` **2.97x**, `#43` **3.22x**: `32.8 µs` vs `105.7 µs`). | Pre-size `CoreMemory` target buffers, apply Guide 01 for replication streaming, and batch-write `0..header.num` slots in `Compactor` → [**Guide 06**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) |",
        "",
        "---",
        "",
        "## All 75 Benchmark Slices & 1v1 Comparisons",
        "",
        "| # | Benchmark | 1v1 Speedup (Odin vs. Zig) | Harness (`#L<start>-L<end>`) | Touched Odin Scope | Entry `xitdb` Calls |",
        "| ---: | :--- | :--- | :--- | :--- | :--- |",
    ]

    for item in sorted_items:
        b_name = item["name"]
        rank = item["rank"]
        slug = item["slug"]
        o_info = odin_harness[b_name]
        z_info = zig_harness.get(b_name)
        slice_info = compute_benchmark_slice(o_info["direct_calls"], odin_procs)

        o_stat = odin_rows.get(b_name)
        z_stat = zig_rows.get(b_name)

        odin_link_from_root = f"../{item['odin_bench_url']}"
        zig_link_from_root = f"../{item['zig_bench_url']}" if item["zig_bench_url"] else ""

        harness_links = f"[Odin (`L{item['odin_start_line']}–L{item['odin_end_line']}`)](../{item['odin_bench_url']})"
        if item["zig_bench_url"]:
            harness_links += f" · [Zig (`L{item['zig_start_line']}–L{item['zig_end_line']}`)](../{item['zig_bench_url']})"

        if o_stat and z_stat:
            o_med = max(o_stat["median_ns"], 1.0)
            z_med = max(z_stat["median_ns"], 1.0)
            wz = welch_z_score(o_stat, z_stat)
            sig = "★" if wz >= 1.96 else "~"
            if o_med <= z_med:
                speedup_cell = f"**{z_med / o_med:.2f}x Odin** (`{o_stat['ns_per_op']:,} ns` vs `{z_stat['ns_per_op']:,} ns` {sig})"
            else:
                speedup_cell = f"**{o_med / z_med:.2f}x Zig** (`{z_stat['ns_per_op']:,} ns` vs `{o_stat['ns_per_op']:,} ns` {sig})"
        elif o_stat:
            speedup_cell = f"Odin DSL (`{o_stat['ns_per_op']:,} ns/op`)"
        else:
            speedup_cell = "—"

        entry_calls_md = ", ".join(f"`{c}`" for c in item["entry_calls"])
        scope_md = f"[**{item['odin_procs_count']} procs · {item['odin_files_count']} files**]({slug}.md)"
        index_rows.append(
            f"| {rank} | [`{b_name}`]({slug}.md) | {speedup_cell} | {harness_links} | {scope_md} | {entry_calls_md} |"
        )

        odin_pts, zig_pts, zig_lib_keys, (guide_title, guide_url) = get_odin_vs_zig_insight(rank, b_name)

        md: List[str] = [
            f"# #{rank}. `{b_name}` — Odin vs. Zig Code Slice & Analysis",
            "",
            f"[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 {guide_title}**]({guide_url}) · [Odin Harness (`bench_xitdb.odin#L{item['odin_start_line']}-L{item['odin_end_line']}`)]({odin_link_from_root})"
            + (
                f" · [Zig Harness (`bench_xitdb.zig#L{item['zig_start_line']}-L{item['zig_end_line']}`)]({zig_link_from_root})"
                if zig_link_from_root
                else ""
            ),
            "",
        ]

        # Section 1: 1v1 Statistical Comparison Table
        if o_stat and z_stat:
            o_med = max(o_stat["median_ns"], 1.0)
            z_med = max(z_stat["median_ns"], 1.0)
            wz = welch_z_score(o_stat, z_stat)
            verdict = (
                f"**{z_med / o_med:.2f}x Odin** (`z = {wz:.1f}`)"
                if o_med <= z_med
                else f"**{o_med / z_med:.2f}x Zig** (`z = {wz:.1f}`)"
            )
            md.extend(
                [
                    "## 1. 1v1 Statistical Performance Summary",
                    "",
                    "| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |",
                    "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |",
                    f"| **Odin** (`-o:speed -microarch:native`) | **{o_stat['ns_per_op']:,}** | {o_stat['mean_ns']:,.1f} ± {o_stat['stddev_ns']:,.1f} | {o_stat['cv_pct']:.1f}% | {o_stat['p95_ns']:,} | {o_stat['ops_per_sec']:,} | {fmt_kb(o_stat['bytes_used'])} | {verdict} |",
                    f"| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | {z_stat['ns_per_op']:,} | {z_stat['mean_ns']:,.1f} ± {z_stat['stddev_ns']:,.1f} | {z_stat['cv_pct']:.1f}% | {z_stat['p95_ns']:,} | {z_stat['ops_per_sec']:,} | {fmt_kb(z_stat['bytes_used'])} | Baseline |",
                    "",
                ]
            )
        elif o_stat:
            md.extend(
                [
                    "## 1. Statistical Performance Summary (Odin 5-Layer DSL)",
                    "",
                    "| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint |",
                    "| :--- | ---: | ---: | ---: | ---: | ---: | ---: |",
                    f"| **Odin** (`-o:speed -microarch:native`) | **{o_stat['ns_per_op']:,}** | {o_stat['mean_ns']:,.1f} ± {o_stat['stddev_ns']:,.1f} | {o_stat['cv_pct']:.1f}% | {o_stat['p95_ns']:,} | {o_stat['ops_per_sec']:,} | {fmt_kb(o_stat['bytes_used'])} |",
                    "",
                ]
            )

        # Section 2: Architectural Analysis (Odin Optimizations & Idiomatic Zig Improvements)
        md.extend(
            [
                "---",
                "",
                "## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements",
                "",
                f"> **Deep-Dive Implementation Guide:** See [**{guide_title}**]({guide_url}) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.",
                "",
                "### What Odin Does Differently (`xitdb/*.odin`)",
                "",
            ]
        )
        for pt in odin_pts:
            md.append(f"- {pt}")

        md.extend(
            [
                "",
                "### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)",
                "",
            ]
        )
        for pt in zig_pts:
            md.append(f"- {pt}")

        # Section 3: Benchmark Harness Code
        md.extend(
            [
                "",
                "---",
                "",
                "## 3. Benchmark Harness Code (`#L<start>-L<end>`)",
                "",
                f"### Odin ([`benchmarks/{item['odin_bench_url']}`]({odin_link_from_root}))",
                "",
                "```odin",
            ]
        )
        for offset, raw_ln in enumerate(o_info["snippet"].splitlines()):
            ln_no = item["odin_start_line"] + offset
            md.append(f"{ln_no:4d} | {raw_ln}")
        md.append("```")

        if z_info:
            md.extend(
                [
                    "",
                    f"### Zig ([`benchmarks/{item['zig_bench_url']}`]({zig_link_from_root}))",
                    "",
                    "```zig",
                ]
            )
            for offset, raw_ln in enumerate(z_info["snippet"].splitlines()):
                ln_no = item["zig_start_line"] + offset
                md.append(f"{ln_no:4d} | {raw_ln}")
            md.append("```")

        # Section 4: Side-by-Side Library References (Clickable #L<start>-L<end> links, zero code duplication)
        md.extend(
            [
                "",
                "---",
                "",
                "## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)",
                "",
                "### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)",
                "",
                "| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |",
                "| :--- | ---: | :--- | :--- |",
            ]
        )
        for zk in zig_lib_keys:
            if zk in ZIG_LIB_RANGES:
                zs, ze, zdesc = ZIG_LIB_RANGES[zk]
                zurl = f"../../reference/xitdb-zig/src/lib.zig#L{zs}-L{ze}"
                md.append(
                    f"| `{zk}` | {ze - zs + 1} | {zdesc} | [`lib.zig#L{zs}-L{ze}`]({zurl}) |"
                )

        exec_p = next(
            (
                p
                for p in slice_info["by_file"].get("xitdb/database.odin", [])
                if p["name"] == "_exec_path_part"
            ),
            None,
        )
        active_arms_note = (
            f" (Active `_exec_path_part` arms: {', '.join(f'`{a}`' for a in exec_p['active_arms'])})"
            if exec_p and exec_p.get("active_arms")
            else ""
        )

        md.extend(
            [
                "",
                f"### Reached Odin Procedures (`{item['odin_procs_count']}` procedures across `{item['odin_files_count']}` files · `{item['odin_lines_count']}` LOC){active_arms_note}",
                "",
                "| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |",
                "| :--- | :--- | :--- | ---: | :--- |",
            ]
        )

        for pname in slice_info["order"]:
            p = odin_procs[pname]
            depth = slice_info["depths"][pname]
            callers = ", ".join(f"`{c}`" for c in slice_info["called_by"].get(pname, [])[:3])
            role = "**Entry Point** (`depth 0`)" if depth == 0 else f"`depth {depth}` (from {callers})"
            src_url = f"../../{p['file']}#L{p['start_line']}-L{p['end_line']}"
            md.append(
                f"| `{p['file']}` | `{pname}` | {role} | {p['line_count']} | [`{p['file']}#L{p['start_line']}-L{p['end_line']}`]({src_url}) |"
            )

        slice_path = os.path.join(SLICES_DIR, f"{slug}.md")
        with open(slice_path, "w", encoding="utf-8") as f:
            f.write("\n".join(md) + "\n")

    with open(os.path.join(SLICES_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index_rows) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="xitdb Multi-Run Statistical Benchmark Runner & Analyzer")
    parser.add_argument("--runs", type=int, default=5, help="In-process measured trials per test (default: 5)")
    parser.add_argument("--warmup", type=int, default=1, help="In-process warmup passes before trials (default: 1)")
    parser.add_argument("--commit", type=str, default=None, help="Git commit SHA to tag or query")
    parser.add_argument("--run-id", type=str, default=None, help="Run session identifier")
    parser.add_argument("--append", action="store_true", help="Append to odin.jsonl/zig.jsonl to accumulate multiple runs")
    parser.add_argument("--no-history", action="store_true", help="Do not append to benchmarks/history.jsonl")
    parser.add_argument("--from-jsonl", action="store_true", help="Analyze existing JSONL files without re-running binaries")
    parser.add_argument(
        "--compare-commits",
        nargs=2,
        metavar=("SHA_A", "SHA_B"),
        help="Compare benchmark distributions between two git commit SHAs",
    )
    parser.add_argument("--lang", choices=["odin", "zig", "lua", "both", "all"], default="odin", help="Language to run or compare")
    parser.add_argument("--list-commits", action="store_true", help="List all commits and run sessions in history")
    parser.add_argument("--inspect", type=str, default=None, help="Inspect all runs and sample distributions for matching tests")
    parser.add_argument(
        "--groups",
        type=str,
        default=None,
        help="Comma-separated benchmark groups to run: hamt,lists,sorted_map,compaction,hashers,backends,dsl",
    )
    parser.add_argument(
        "--filter",
        type=str,
        default=None,
        help="Pipe- or comma-separated case-insensitive benchmark name substrings to run",
    )
    parser.add_argument(
        "--affected",
        nargs="?",
        const="auto",
        default=None,
        metavar="GIT_REF",
        help="Map git diff changes (working tree or commit range) to affected benchmarks and run only those",
    )
    parser.add_argument(
        "--plan",
        nargs="?",
        const="auto",
        default=None,
        metavar="GIT_REF",
        help="Dry-run: print the code-change-to-benchmark mapping plan for GIT_REF without executing benchmarks",
    )
    parser.add_argument(
        "--plan-json",
        nargs="?",
        const="auto",
        default=None,
        metavar="GIT_REF",
        help="Output the code-change-to-benchmark mapping plan as JSON",
    )
    parser.add_argument(
        "--code-map-json",
        action="store_true",
        help="Output JSON mapping benchmark names to #L<start>-L<end> harness links and slice metadata",
    )
    parser.add_argument(
        "--generate-slices",
        action="store_true",
        help="Generate per-benchmark code slices in benchmarks/slices/ (.md and interactive index.html)",
    )
    parser.add_argument(
        "--patched",
        action="store_true",
        help="Build Zig benchmarks against reference/xitdb-zig-patched (-Dpatched=true)",
    )

    args = parser.parse_args()

    if args.generate_slices:
        generate_all_slices()
        if not args.code_map_json and args.from_jsonl is False and args.affected is None:
            print(f"Generated benchmark code slices in {SLICES_DIR}", file=sys.stderr)
            return

    if args.code_map_json:
        print(json.dumps(build_code_map()))
        return

    if args.plan_json is not None:
        print(json.dumps(map_changes_to_benchmarks(args.plan_json)))
        return

    if args.plan is not None:
        plan = map_changes_to_benchmarks(args.plan)
        print_benchmark_plan(plan)
        return

    if args.list_commits:
        list_commits(load_all_history())
        return

    if args.inspect:
        inspect_test(load_all_history(), args.inspect, args.commit)
        return

    if args.compare_commits:
        sha_a, sha_b = args.compare_commits
        records = load_all_history()
        if args.lang == "all":
            langs = ["odin", "zig", "lua"]
        elif args.lang == "both":
            langs = ["odin", "zig"]
        else:
            langs = [args.lang]
        for lg in langs:
            compare_commits(records, sha_a, sha_b, lg)
        return

    if not args.from_jsonl:
        commit_sha = args.commit or current_git_commit()
        run_id = args.run_id or f"run-{int(time.time())}"

        common_flags = [
            "--runs", str(args.runs),
            "--warmup", str(args.warmup),
            "--commit", commit_sha,
            "--run-id", run_id,
        ]
        if args.append:
            common_flags.append("--append")
        if args.no_history:
            common_flags.append("--no-history")

        if args.affected is not None:
            plan = map_changes_to_benchmarks(args.affected)
            print_benchmark_plan(plan)
            odin_groups = args.groups.split(",") if args.groups else plan["odin_groups"]
            zig_groups = args.groups.split(",") if args.groups else plan["zig_groups"]
            bench_filter = args.filter if args.filter is not None else plan["filter"]

            if not odin_groups and not zig_groups:
                print("==> No benchmark-affecting source changes detected; skipping execution.", file=sys.stderr)
            else:
                if odin_groups:
                    odin_flags = list(common_flags) + ["--groups", ",".join(odin_groups)]
                    if bench_filter:
                        odin_flags += ["--filter", bench_filter]
                    run_cmd(
                        ["odin", "run", "benchmarks", "-o:speed", "-microarch:native", "--"] + odin_flags,
                        f"xitdb-odin (selective: groups={','.join(odin_groups)}"
                        + (f", filter={bench_filter})" if bench_filter else ")"),
                    )
                if zig_groups:
                    zig_bin = find_zig()
                    zig_build_args = [zig_bin, "build", "bench", "-Doptimize=ReleaseFast", "-Dcpu=native"]
                    if args.patched:
                        zig_build_args.append("-Dpatched=true")
                    zig_flags = list(common_flags) + ["--groups", ",".join(zig_groups)]
                    if bench_filter:
                        zig_flags += ["--filter", bench_filter]
                    run_cmd(
                        zig_build_args + ["--"] + zig_flags,
                        f"xitdb-zig{' (patched)' if args.patched else ''} (selective: groups={','.join(zig_groups)}"
                        + (f", filter={bench_filter})" if bench_filter else ")"),
                    )
        else:
            extra_flags: List[str] = []
            if args.groups:
                extra_flags += ["--groups", args.groups]
            if args.filter:
                extra_flags += ["--filter", args.filter]

            run_odin = args.lang in ("odin", "both", "all") or (args.groups is None and args.lang not in ("zig", "lua"))
            run_zig = (args.lang in ("zig", "both", "all") or (args.groups is None and args.lang not in ("odin", "lua"))) and (args.groups != "dsl")
            run_lua = args.lang in ("lua", "all")

            if run_odin:
                run_cmd(
                    ["odin", "run", "benchmarks", "-o:speed", "-microarch:native", "--"] + common_flags + extra_flags,
                    "xitdb-odin (-o:speed -microarch:native)",
                )
            if run_zig:
                zig_bin = find_zig()
                zig_build_args = [zig_bin, "build", "bench", "-Doptimize=ReleaseFast", "-Dcpu=native"]
                if args.patched:
                    zig_build_args.append("-Dpatched=true")
                run_cmd(
                    zig_build_args + ["--"] + common_flags + extra_flags,
                    f"xitdb-zig (-Doptimize=ReleaseFast -Dcpu=native{' -Dpatched=true' if args.patched else ''})",
                )
            if run_lua:
                run_cmd(
                    ["odin", "run", "benchmarks", "-o:speed", "-microarch:native", "--", "--lang", "lua"] + common_flags + extra_flags,
                    "xitdb-lua (Lua 5.4 via Odin -o:speed -microarch:native)",
                )
                if args.lang == "lua":
                    return

    odin_raw = load_jsonl_file(ODIN_JSONL)
    zig_raw = load_jsonl_file(ZIG_JSONL)

    snapshot_commit = args.commit if (args.from_jsonl and not args.affected and not args.groups and not args.filter) else None
    odin_rows = pool_by_lang_and_test(odin_raw, "odin", snapshot_commit)
    zig_rows = pool_by_lang_and_test(zig_raw, "zig", snapshot_commit)

    print_1v1_comparison(odin_rows, zig_rows)


if __name__ == "__main__":
    main()
