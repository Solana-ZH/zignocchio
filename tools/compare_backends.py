#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

EXAMPLES = [
    "hello",
    "counter",
    "transfer-sol",
    "pda-storage",
    "vault",
    "token-vault",
    "escrow",
    "noop",
    "logonly",
]

RUNTIME_CU_SUPPORTED = {
    "hello",
    "counter",
    "transfer-sol",
    "pda-storage",
    "vault",
    "escrow",
}


def run_timed(cmd: list[str], cwd: Path) -> float:
    start = time.perf_counter()
    subprocess.run(cmd, cwd=cwd, check=True)
    return time.perf_counter() - start


def run_capture(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)


def fmt_bytes(value: int) -> str:
    return f"{value:,}"


def fmt_seconds(value: float) -> str:
    return f"{value:.2f}s"


def fmt_signed_int(value: int) -> str:
    return f"{value:+,}"


def winner_for_smaller(sbpf_value: int, fork_value: int) -> str:
    if sbpf_value < fork_value:
        return "sbpf-linker"
    if fork_value < sbpf_value:
        return "fork-sbf"
    return "tie"


def winner_for_faster(sbpf_value: float, fork_value: float) -> str:
    if sbpf_value < fork_value:
        return "sbpf-linker"
    if fork_value < sbpf_value:
        return "fork-sbf"
    return "tie"


def detect_runtime_probe(root: Path) -> list[str]:
    return [
        "cargo",
        "run",
        "--quiet",
        "--manifest-path",
        str(root / "tests_rust" / "Cargo.toml"),
        "--bin",
        "cu_probe",
        "--",
    ]


def probe_runtime_cu(root: Path, example: str, artifact: Path) -> dict[str, Any]:
    if example not in RUNTIME_CU_SUPPORTED:
        return {"supported": False, "results": {}, "error": "no runtime CU harness"}

    cmd = detect_runtime_probe(root) + ["--example", example, "--artifact", str(artifact)]
    proc = run_capture(cmd, root)
    if proc.returncode != 0:
        message = (proc.stderr or proc.stdout).strip() or f"cu probe failed with exit code {proc.returncode}"
        return {"supported": True, "results": {}, "error": message}

    results: dict[str, int] = {}
    for line in proc.stdout.splitlines():
        if not line.startswith("CU\t"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        _prefix, scenario, cu_text = parts
        results[scenario] = int(cu_text)

    if not results:
        return {"supported": True, "results": {}, "error": "cu probe produced no scenario output"}

    return {"supported": True, "results": results, "error": ""}


def render_runtime_table(rows: list[dict[str, Any]]) -> list[str]:
    lines = [
        "## Runtime CU Comparison",
        "",
        "Measured with `mollusk-svm`'s `compute_units_consumed` on representative happy-path scenarios.",
        "These numbers are useful as a backend-to-backend proxy, but they are not a promise about every validator/runtime version.",
        "",
        "| example | scenario | sbpf-linker CU | fork-sbf CU | Δ CU (fork - sbpf) | lower CU |",
        "|---|---|---:|---:|---:|---|",
    ]

    any_rows = False
    for row in rows:
        sbpf_runtime = row["sbpf_runtime"]
        fork_runtime = row["fork_runtime"]

        scenario_names = sorted(
            set(sbpf_runtime.get("results", {}).keys())
            | set(fork_runtime.get("results", {}).keys())
        )

        if scenario_names:
            any_rows = True
            for scenario in scenario_names:
                sbpf_cu = sbpf_runtime.get("results", {}).get(scenario)
                fork_cu = fork_runtime.get("results", {}).get(scenario)
                if sbpf_cu is not None and fork_cu is not None:
                    delta = fork_cu - sbpf_cu
                    winner = winner_for_smaller(sbpf_cu, fork_cu)
                    delta_text = fmt_signed_int(delta)
                    sbpf_text = fmt_bytes(sbpf_cu)
                    fork_text = fmt_bytes(fork_cu)
                else:
                    delta_text = "n/a"
                    winner = "n/a"
                    sbpf_text = fmt_bytes(sbpf_cu) if sbpf_cu is not None else "n/a"
                    fork_text = fmt_bytes(fork_cu) if fork_cu is not None else "n/a"

                lines.append(
                    f"| {row['example']} | {scenario} | {sbpf_text} | {fork_text} | {delta_text} | {winner} |"
                )
        else:
            note = sbpf_runtime.get("error") or fork_runtime.get("error") or "n/a"
            lines.append(f"| {row['example']} | _none_ | n/a | n/a | n/a | {note} |")

    if not any_rows:
        lines.append("| _none_ | _none_ | n/a | n/a | n/a | no runtime data |")

    lines += [
        "",
        "### Runtime notes",
        "",
    ]

    for row in rows:
        sbpf_runtime = row["sbpf_runtime"]
        fork_runtime = row["fork_runtime"]
        messages: list[str] = []
        if sbpf_runtime.get("error"):
            messages.append(f"sbpf-linker: {sbpf_runtime['error']}")
        if fork_runtime.get("error"):
            messages.append(f"fork-sbf: {fork_runtime['error']}")
        if messages:
            lines.append(f"- `{row['example']}` — " + " | ".join(messages))

    if lines[-1] == "":
        lines.pop()

    return lines


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare sbpf-linker and fork-sbf build outputs."
    )
    parser.add_argument(
        "--fork-zig",
        default=os.environ.get("SOLANA_ZIG", ""),
        help="Path to the solana-zig fork binary. Defaults to $SOLANA_ZIG.",
    )
    parser.add_argument(
        "--examples",
        nargs="*",
        default=EXAMPLES,
        help="Example names to compare.",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Optional output Markdown file path.",
    )
    parser.add_argument(
        "--skip-runtime-cu",
        action="store_true",
        help="Skip runtime compute-unit probing.",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    fork_zig = args.fork_zig.strip()
    if not fork_zig:
        print("error: missing fork Zig binary. Pass --fork-zig or set SOLANA_ZIG.", file=sys.stderr)
        return 2

    fork_zig_path = Path(fork_zig)
    if not fork_zig_path.exists():
        print(f"error: fork Zig not found: {fork_zig}", file=sys.stderr)
        return 2

    out_dir = root / ".backend-compare"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    (out_dir / "sbpf-linker").mkdir(parents=True)
    (out_dir / "fork-sbf").mkdir(parents=True)

    rows: list[dict[str, Any]] = []

    for example in args.examples:
        print(f"==> sbpf-linker: {example}")
        sbpf_time = run_timed(["zig", "build", f"-Dexample={example}"], root)
        sbpf_so = root / "zig-out" / "lib" / f"{example}.so"
        if not sbpf_so.exists():
            raise FileNotFoundError(f"missing sbpf-linker artifact: {sbpf_so}")
        sbpf_copy = out_dir / "sbpf-linker" / f"{example}.so"
        shutil.copy2(sbpf_so, sbpf_copy)
        sbpf_size = sbpf_copy.stat().st_size
        sbpf_runtime = (
            {"supported": False, "results": {}, "error": "runtime CU probing skipped"}
            if args.skip_runtime_cu
            else probe_runtime_cu(root, example, sbpf_copy)
        )

        print(f"==> fork-sbf: {example}")
        fork_time = run_timed([str(fork_zig_path), "build", f"-Dexample={example}", "-Dbackend=fork-sbf"], root)
        fork_so = root / "zig-out" / "lib" / f"{example}.so"
        if not fork_so.exists():
            raise FileNotFoundError(f"missing fork-sbf artifact: {fork_so}")
        fork_copy = out_dir / "fork-sbf" / f"{example}.so"
        shutil.copy2(fork_so, fork_copy)
        fork_size = fork_copy.stat().st_size
        fork_runtime = (
            {"supported": False, "results": {}, "error": "runtime CU probing skipped"}
            if args.skip_runtime_cu
            else probe_runtime_cu(root, example, fork_copy)
        )

        size_delta = fork_size - sbpf_size
        time_delta = fork_time - sbpf_time
        rows.append(
            {
                "example": example,
                "sbpf_size": sbpf_size,
                "fork_size": fork_size,
                "size_delta": size_delta,
                "sbpf_time": sbpf_time,
                "fork_time": fork_time,
                "time_delta": time_delta,
                "sbpf_runtime": sbpf_runtime,
                "fork_runtime": fork_runtime,
            }
        )

    lines = [
        "# Backend Comparison Report",
        "",
        f"- stock Zig backend: `sbpf-linker`",
        f"- fork Zig binary: `{fork_zig_path}`",
        "- compared metrics: `.so` size, wall-clock build time, representative runtime CU",
        "",
        "## Build Output Comparison",
        "",
        "| example | sbpf-linker size | fork-sbf size | Δ size (fork - sbpf) | smaller artifact | sbpf-linker build | fork-sbf build | Δ time | faster build |",
        "|---|---:|---:|---:|---|---:|---:|---:|---|",
    ]

    for row in rows:
        lines.append(
            "| {example} | {sbpf_size} | {fork_size} | {size_delta} | {size_winner} | {sbpf_time} | {fork_time} | {time_delta:+.2f}s | {time_winner} |".format(
                example=row["example"],
                sbpf_size=fmt_bytes(int(row["sbpf_size"])),
                fork_size=fmt_bytes(int(row["fork_size"])),
                size_delta=fmt_signed_int(int(row["size_delta"])),
                size_winner=winner_for_smaller(int(row["sbpf_size"]), int(row["fork_size"])),
                sbpf_time=fmt_seconds(float(row["sbpf_time"])),
                fork_time=fmt_seconds(float(row["fork_time"])),
                time_delta=float(row["time_delta"]),
                time_winner=winner_for_faster(float(row["sbpf_time"]), float(row["fork_time"])),
            )
        )

    if args.skip_runtime_cu:
        lines += [
            "",
            "## Runtime CU Comparison",
            "",
            "Skipped by `--skip-runtime-cu`.",
        ]
    else:
        lines += [""] + render_runtime_table(rows)

    total_sbpf = sum(int(r["sbpf_size"]) for r in rows)
    total_fork = sum(int(r["fork_size"]) for r in rows)
    avg_sbpf_time = sum(float(r["sbpf_time"]) for r in rows) / max(len(rows), 1)
    avg_fork_time = sum(float(r["fork_time"]) for r in rows) / max(len(rows), 1)
    sbpf_smaller_count = sum(1 for r in rows if int(r["sbpf_size"]) < int(r["fork_size"]))
    fork_smaller_count = sum(1 for r in rows if int(r["fork_size"]) < int(r["sbpf_size"]))
    tie_size_count = len(rows) - sbpf_smaller_count - fork_smaller_count
    sbpf_faster_count = sum(1 for r in rows if float(r["sbpf_time"]) < float(r["fork_time"]))
    fork_faster_count = sum(1 for r in rows if float(r["fork_time"]) < float(r["sbpf_time"]))
    tie_time_count = len(rows) - sbpf_faster_count - fork_faster_count

    runtime_pairs: list[tuple[str, int, int]] = []
    for row in rows:
        sbpf_results = row["sbpf_runtime"].get("results", {})
        fork_results = row["fork_runtime"].get("results", {})
        for scenario in sorted(set(sbpf_results.keys()) & set(fork_results.keys())):
            runtime_pairs.append((scenario, int(sbpf_results[scenario]), int(fork_results[scenario])))

    sbpf_lower_cu_count = sum(1 for _scenario, sbpf_cu, fork_cu in runtime_pairs if sbpf_cu < fork_cu)
    fork_lower_cu_count = sum(1 for _scenario, sbpf_cu, fork_cu in runtime_pairs if fork_cu < sbpf_cu)
    tie_cu_count = len(runtime_pairs) - sbpf_lower_cu_count - fork_lower_cu_count

    lines += [
        "",
        "## Summary",
        "",
        f"- total `.so` size (`sbpf-linker`): {fmt_bytes(total_sbpf)} bytes",
        f"- total `.so` size (`fork-sbf`): {fmt_bytes(total_fork)} bytes",
        f"- smaller artifact wins: `sbpf-linker` {sbpf_smaller_count}, `fork-sbf` {fork_smaller_count}, ties {tie_size_count}",
        f"- average build time (`sbpf-linker`): {fmt_seconds(avg_sbpf_time)}",
        f"- average build time (`fork-sbf`): {fmt_seconds(avg_fork_time)}",
        f"- faster build wins: `sbpf-linker` {sbpf_faster_count}, `fork-sbf` {fork_faster_count}, ties {tie_time_count}",
    ]

    if args.skip_runtime_cu:
        lines.append("- runtime CU comparison: skipped")
    else:
        lines.append(
            f"- lower runtime CU wins (scenario rows with data): `sbpf-linker` {sbpf_lower_cu_count}, `fork-sbf` {fork_lower_cu_count}, ties {tie_cu_count}"
        )

    lines += [
        "",
        "Artifacts copied to:",
        f"- `{out_dir / 'sbpf-linker'}`",
        f"- `{out_dir / 'fork-sbf'}`",
    ]

    report = "\n".join(lines) + "\n"
    if args.output:
        output_path = (root / args.output).resolve() if not Path(args.output).is_absolute() else Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(report)
        print(f"wrote report to {output_path}")
    else:
        print()
        print(report)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
