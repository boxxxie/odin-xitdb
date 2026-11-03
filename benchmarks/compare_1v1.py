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

    def add_path_part(pt: str) -> None:
        if pt in active_parts:
            return
        active_parts.add(pt)
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
                        add_path_part(sub_pt)
                    for callee in arm["callees"]:
                        if callee not in callees_to_visit:
                            callees_to_visit.append(callee)
        else:
            callees_to_visit = list(pinfo["callees"])

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
                        add_path_part(sub_pt)
                    for callee in arm["callees"]:
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


def generate_all_slices() -> None:
    """
    Generates:
      1. benchmarks/slices/<rank>_<slug>.md for every benchmark
      2. benchmarks/slices/README.md index
      3. benchmarks/slices/index.html interactive single-page codebase slice viewer
    """
    os.makedirs(SLICES_DIR, exist_ok=True)
    odin_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.odin"), "odin")
    zig_harness = scan_harness_file(os.path.join(BENCH_DIR, "bench_xitdb.zig"), "zig")
    odin_procs = parse_odin_library_procs()
    code_map = build_code_map()

    known_procs = set(odin_procs.keys())
    ident_re = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")

    sorted_items = sorted(code_map.values(), key=lambda x: x["rank"])
    index_rows: List[str] = [
        "# xitdb Per-Benchmark Code Slices & Call-Graph Projections",
        "",
        "Each slice below projects `xitdb/*.odin` down to **only the procedures and call paths touched by that benchmark**, with direct `#L<start>-L<end>` links into both the benchmark harness and the library source files.",
        "",
        "| # | Benchmark | Harness (Odin / Zig) | Touched Library Scope | Entry `xitdb` Calls |",
        "| ---: | :--- | :--- | :--- | :--- |",
    ]

    html_payload: List[Dict[str, Any]] = []

    for item in sorted_items:
        b_name = item["name"]
        rank = item["rank"]
        slug = item["slug"]
        o_info = odin_harness[b_name]
        z_info = zig_harness.get(b_name)
        slice_info = compute_benchmark_slice(o_info["direct_calls"], odin_procs)
        reached_set = set(slice_info["order"])

        odin_link_from_root = f"../{item['odin_bench_url']}"
        zig_link_from_root = f"../{item['zig_bench_url']}" if item["zig_bench_url"] else ""

        harness_links = f"[Odin (`L{item['odin_start_line']}–L{item['odin_end_line']}`)](../{item['odin_bench_url']})"
        if item["zig_bench_url"]:
            harness_links += f" · [Zig (`L{item['zig_start_line']}–L{item['zig_end_line']}`)](../{item['zig_bench_url']})"

        entry_calls_md = ", ".join(f"`{c}`" for c in item["entry_calls"])
        scope_md = f"[**{item['odin_procs_count']} procs · {item['odin_files_count']} files · {item['odin_lines_count']} LOC**]({slug}.md)"
        index_rows.append(
            f"| {rank} | [`{b_name}`]({slug}.md) | {harness_links} | {scope_md} | {entry_calls_md} |"
        )

        md: List[str] = [
            f"# #{rank}. `{b_name}` — Code Slice",
            "",
            f"[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L{item['odin_start_line']}-L{item['odin_end_line']}`)]({odin_link_from_root})"
            + (
                f" · [Zig Harness (`bench_xitdb.zig#L{item['zig_start_line']}-L{item['zig_end_line']}`)]({zig_link_from_root})"
                if zig_link_from_root
                else ""
            ),
            "",
            f"- **Touched Library Scope:** **{item['odin_procs_count']}** procedures across **{item['odin_files_count']}** `xitdb/*.odin` files (**{item['odin_lines_count']}** lines of library code)",
            f"- **Direct Benchmark Entry Points:** {entry_calls_md}",
            "",
            "---",
            "",
            "## 1. Benchmark Harness Code",
            "",
            f"### Odin (`benchmarks/{item['odin_bench_url']}`)",
            "",
            "```odin",
        ]

        for offset, raw_ln in enumerate(o_info["snippet"].splitlines()):
            ln_no = item["odin_start_line"] + offset
            md.append(f"{ln_no:4d} | {raw_ln}")
        md.append("```")

        if z_info:
            md.extend(
                [
                    "",
                    "<details>",
                    f"<summary><strong>Zig Benchmark Harness (<code>benchmarks/{item['zig_bench_url']}</code>)</strong></summary>",
                    "",
                    "```zig",
                ]
            )
            for offset, raw_ln in enumerate(z_info["snippet"].splitlines()):
                ln_no = item["zig_start_line"] + offset
                md.append(f"{ln_no:4d} | {raw_ln}")
            md.extend(["```", "</details>"])

        md.extend(
            [
                "",
                "---",
                "",
                "## 2. Reached `xitdb` Call Graph & File Coverage",
                "",
                "| File | Procedure | Role / Call Depth | Lines | Source Link |",
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

        md.extend(
            [
                "",
                "---",
                "",
                "## 3. Highlighted Library Code Slice (`xitdb/*.odin`)",
                "",
                "> Only procedures reachable when running **`"
                + b_name
                + "`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. ",
                "",
            ]
        )

        for rel_file, file_procs in slice_info["by_file"].items():
            file_loc = sum(p["line_count"] for p in file_procs)
            ranges_md = ", ".join(
                f"[`L{p['start_line']}–L{p['end_line']}`](../../{rel_file}#L{p['start_line']}-L{p['end_line']})"
                for p in file_procs
            )
            md.extend(
                [
                    f"### `{rel_file}` ({len(file_procs)} procedures · {file_loc} lines: {ranges_md})",
                    "",
                ]
            )
            for p in file_procs:
                src_url = f"../../{rel_file}#L{p['start_line']}-L{p['end_line']}"
                depth = p["depth"]
                badge = "ENTRY POINT" if depth == 0 else f"DEPTH {depth}"
                arms_note = (
                    f" — Active `Path_Part` arms: {', '.join(f'`{a}`' for a in p['active_arms'])}"
                    if p.get("active_arms")
                    else ""
                )
                md.extend(
                    [
                        f"#### [`{p['name']}`]({src_url}) — `{badge}` (`L{p['start_line']}–L{p['end_line']}`){arms_note}",
                        "",
                        "```odin",
                    ]
                )
                line_nums = p.get(
                    "line_numbers",
                    list(range(p["start_line"], p["start_line"] + len(p["raw_lines"]))),
                )
                prev_ln = None
                for idx_ln, (ln_no, raw_ln, clean_ln) in enumerate(
                    zip(line_nums, p["raw_lines"], p["clean_lines"])
                ):
                    if prev_ln is not None and ln_no > prev_ln + 1:
                        md.append(
                            f"   ... | \t// ... [lines {prev_ln + 1}–{ln_no - 1}: untouched Path_Part arms omitted] ..."
                        )
                    prev_ln = ln_no
                    called_here: List[str] = []
                    if idx_ln > 0:
                        for m_id in ident_re.finditer(clean_ln):
                            tok = m_id.group(1)
                            if (
                                tok != p["name"]
                                and tok in reached_set
                                and tok in known_procs
                                and tok not in called_here
                            ):
                                called_here.append(tok)
                    marker = (
                        f"  // <== [calls {', '.join(called_here)}]"
                        if called_here
                        else ""
                    )
                    md.append(f"{ln_no:4d} | {raw_ln}{marker}")
                md.extend(["```", ""])

        slice_path = os.path.join(SLICES_DIR, f"{slug}.md")
        with open(slice_path, "w", encoding="utf-8") as f:
            f.write("\n".join(md) + "\n")

        html_payload.append(
            {
                "rank": rank,
                "name": b_name,
                "slug": slug,
                "odin_url": f"../{item['odin_bench_url']}",
                "zig_url": f"../{item['zig_bench_url']}" if item["zig_bench_url"] else "",
                "odin_snippet": o_info["snippet"],
                "odin_start": item["odin_start_line"],
                "procs_count": item["odin_procs_count"],
                "files_count": item["odin_files_count"],
                "lines_count": item["odin_lines_count"],
                "reached_procs": slice_info["order"],
                "depths": slice_info["depths"],
            }
        )

    with open(os.path.join(SLICES_DIR, "README.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(index_rows) + "\n")

    # Generate interactive single-page viewer (benchmarks/slices/index.html)
    html_procs = {
        k: {
            "name": v["name"],
            "file": v["file"],
            "start_line": v["start_line"],
            "end_line": v["end_line"],
            "code": "\n".join(v["raw_lines"]),
            "callees": v["callees"],
        }
        for k, v in odin_procs.items()
    }
    html_doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>xitdb Benchmark Codebase Slice Explorer</title>
<style>
  body {{ margin: 0; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; background: #0d1117; color: #c9d1d9; display: flex; height: 100vh; overflow: hidden; }}
  #sidebar {{ width: 380px; border-right: 1px solid #30363d; overflow-y: auto; padding: 12px; background: #161b22; }}
  #main {{ flex: 1; overflow-y: auto; padding: 20px; }}
  .bench-item {{ padding: 8px 10px; border-radius: 6px; cursor: pointer; margin-bottom: 4px; border: 1px solid transparent; font-size: 12px; }}
  .bench-item:hover {{ background: #21262d; }}
  .bench-item.active {{ background: #1f6feb22; border-color: #58a6ff; color: #58a6ff; }}
  .badge {{ display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 11px; background: #21262d; color: #8b949e; }}
  .badge.entry {{ background: #23863644; color: #3fb950; border: 1px solid #238636; }}
  pre {{ background: #161b22; padding: 12px; border-radius: 6px; border: 1px solid #30363d; overflow-x: auto; font-size: 12px; line-height: 1.45; }}
  .proc-card {{ margin-bottom: 16px; }}
  a {{ color: #58a6ff; text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  input {{ width: 100%; box-sizing: border-box; padding: 8px; margin-bottom: 10px; background: #0d1117; border: 1px solid #30363d; color: #c9d1d9; border-radius: 6px; }}
</style>
</head>
<body>
<div id="sidebar">
  <h3 style="margin-top:0">xitdb Benchmark Slices</h3>
  <input id="search" type="text" placeholder="Filter 75 benchmarks..." oninput="renderList()">
  <div id="bench-list"></div>
</div>
<div id="main"><div id="content"></div></div>
<script>
const BENCHMARKS = {json.dumps(html_payload)};
const PROCS = {json.dumps(html_procs)};
let activeIdx = 0;

function escapeHtml(s) {{
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}}

function renderList() {{
  const q = document.getElementById("search").value.toLowerCase();
  const el = document.getElementById("bench-list");
  el.innerHTML = BENCHMARKS.map((b, i) => {{
    if (q && !b.name.toLowerCase().includes(q)) return "";
    const cls = i === activeIdx ? "bench-item active" : "bench-item";
    return `<div class="${{cls}}" onclick="selectBench(${{i}})">
      <strong>#${{b.rank}}</strong> ${{escapeHtml(b.name)}}<br>
      <span class="badge">${{b.procs_count}} procs · ${{b.files_count}} files · ${{b.lines_count}} LOC</span>
    </div>`;
  }}).join("");
}}

function selectBench(idx) {{
  activeIdx = idx;
  renderList();
  const b = BENCHMARKS[idx];
  const reached = new Set(b.reached_procs);
  const byFile = {{}};
  for (const pname of b.reached_procs) {{
    const p = PROCS[pname];
    if (!byFile[p.file]) byFile[p.file] = [];
    byFile[p.file].push(p);
  }}
  let html = `<h2>#${{b.rank}}. ${{escapeHtml(b.name)}}</h2>
    <p><a href="${{b.slug}}.md">Markdown Slice (${{b.slug}}.md)</a> ·
       <a href="${{b.odin_url}}">Odin Harness</a>
       ${{b.zig_url ? ` · <a href="${{b.zig_url}}">Zig Harness</a>` : ""}}</p>
    <h3>Benchmark Harness (bench_xitdb.odin)</h3>
    <pre>${{escapeHtml(b.odin_snippet)}}</pre>
    <h3>Touched Library Code (${{b.procs_count}} procedures across ${{b.files_count}} xitdb/*.odin files)</h3>`;
  for (const [file, procs] of Object.entries(byFile)) {{
    procs.sort((a, c) => a.start_line - c.start_line);
    html += `<h4>${{file}} (${{procs.length}} procedures)</h4>`;
    for (const p of procs) {{
      const d = b.depths[p.name];
      const badgeCls = d === 0 ? "badge entry" : "badge";
      const badgeTxt = d === 0 ? "ENTRY POINT" : `DEPTH ${{d}}`;
      html += `<div class="proc-card">
        <div><strong>${{p.name}}</strong> <span class="${{badgeCls}}">${{badgeTxt}}</span>
        <span class="badge">L${{p.start_line}}–L${{p.end_line}}</span></div>
        <pre>${{escapeHtml(p.code)}}</pre>
      </div>`;
    }}
  }}
  document.getElementById("content").innerHTML = html;
}}

renderList();
if (BENCHMARKS.length > 0) selectBench(0);
</script>
</body>
</html>
"""
    with open(os.path.join(SLICES_DIR, "index.html"), "w", encoding="utf-8") as f:
        f.write(html_doc)


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
