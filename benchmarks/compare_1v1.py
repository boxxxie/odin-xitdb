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
        records = load_jsonl_file(ODIN_JSONL) + load_jsonl_file(ZIG_JSONL)
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
    current_file: Optional[str] = None

    odin_proc_re = re.compile(r"^[+-]\s*([A-Za-z0-9_]+)\s*::\s*proc\b")
    zig_fn_re = re.compile(r"^[+-]\s*(?:pub\s+)?fn\s+([A-Za-z0-9_]+)\b")
    hunk_re = re.compile(r"^@@\s+[^@]+@@\s*(.*)$")

    for line in raw_diff.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:].strip()
            changed_files.add(current_file)
        elif current_file and line.startswith("@@"):
            m = hunk_re.match(line)
            if m and m.group(1):
                ctx = m.group(1).strip()
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

    odin_groups_set: Set[str] = set()
    zig_groups_set: Set[str] = set()
    filter_patterns: List[str] = []
    can_narrow_filter = True
    reasons: List[str] = []

    odin_files = sorted(f for f in changed_files if f.startswith("xitdb/") or f == "benchmarks/bench_xitdb.odin")
    zig_files = sorted(f for f in changed_files if f.startswith("reference/xitdb-zig/") or f == "benchmarks/bench_xitdb.zig")

    for f in odin_files:
        f_procs = procs_by_file.get(f, set())
        if f in ("xitdb/core.odin", "xitdb/cursor.odin", "xitdb/database.odin", "xitdb/types.odin"):
            odin_groups_set.update(ALL_ODIN_GROUPS)
            can_narrow_filter = False
            reasons.append(f"{f} (core/storage/cursor primitive -> all 7 Odin groups)")
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
            odin_groups_set.update(["sorted_map", "compaction", "dsl"])
            can_narrow_filter = False
            reasons.append(f"{f} (B+Tree implementation -> sorted_map, compaction, dsl)")
        elif f == "xitdb/compact_replicate.odin":
            odin_groups_set.add("compaction")
            if f_procs and all("replicate" in p for p in f_procs):
                filter_patterns.append("Replication")
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] -> group=compaction, filter=Replication")
            elif f_procs and all("compact" in p for p in f_procs):
                filter_patterns.append("Compaction")
                reasons.append(f"{f} [{', '.join(sorted(f_procs))}] -> group=compaction, filter=Compaction")
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
    parser.add_argument("--lang", choices=["odin", "zig", "both"], default="odin", help="Language for --compare-commits")
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

    args = parser.parse_args()

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
        langs = ["odin", "zig"] if args.lang == "both" else [args.lang]
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
                    zig_flags = list(common_flags) + ["--groups", ",".join(zig_groups)]
                    if bench_filter:
                        zig_flags += ["--filter", bench_filter]
                    run_cmd(
                        [zig_bin, "build", "bench", "-Doptimize=ReleaseFast", "-Dcpu=native", "--"] + zig_flags,
                        f"xitdb-zig (selective: groups={','.join(zig_groups)}"
                        + (f", filter={bench_filter})" if bench_filter else ")"),
                    )
        else:
            extra_flags: List[str] = []
            if args.groups:
                extra_flags += ["--groups", args.groups]
            if args.filter:
                extra_flags += ["--filter", args.filter]

            run_odin = args.lang in ("odin", "both") or args.groups is None
            run_zig = (args.lang in ("zig", "both") or args.groups is None) and (args.groups != "dsl")

            if run_odin:
                run_cmd(
                    ["odin", "run", "benchmarks", "-o:speed", "-microarch:native", "--"] + common_flags + extra_flags,
                    "xitdb-odin (-o:speed -microarch:native)",
                )
            if run_zig:
                zig_bin = find_zig()
                run_cmd(
                    [zig_bin, "build", "bench", "-Doptimize=ReleaseFast", "-Dcpu=native", "--"] + common_flags + extra_flags,
                    "xitdb-zig (-Doptimize=ReleaseFast -Dcpu=native)",
                )

    odin_raw = load_jsonl_file(ODIN_JSONL)
    zig_raw = load_jsonl_file(ZIG_JSONL)

    snapshot_commit = args.commit if (args.from_jsonl and not args.affected and not args.groups and not args.filter) else None
    odin_rows = pool_by_lang_and_test(odin_raw, "odin", snapshot_commit)
    zig_rows = pool_by_lang_and_test(zig_raw, "zig", snapshot_commit)

    print_1v1_comparison(odin_rows, zig_rows)


if __name__ == "__main__":
    main()
