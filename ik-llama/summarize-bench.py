#!/usr/bin/env python3
"""Summarize llama-bench CSV files produced by bench-*.sh."""

from __future__ import annotations

import csv
import glob
import os
import re
import sys
from pathlib import Path


def clean_number(value: str | None) -> float | None:
    if value is None:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", value.replace(",", ""))
    if not match:
        return None
    return float(match.group(0))


def find_value(row: dict[str, str], candidates: tuple[str, ...]) -> float | None:
    normalized = {key.strip().lower(): value for key, value in row.items()}
    for candidate in candidates:
        if candidate in normalized:
            value = clean_number(normalized[candidate])
            if value is not None:
                return value
    for key, value in normalized.items():
        if any(candidate in key for candidate in candidates):
            parsed = clean_number(value)
            if parsed is not None:
                return parsed
    return None


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def read_summary(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def result_from_summary_row(row: dict[str, str]) -> dict[str, object] | None:
    output = Path(row["output"])
    if not output.is_absolute():
        output = Path.cwd() / output

    csv_rows = read_csv_rows(output)
    if not csv_rows:
        print(f"Skipping empty/missing CSV: {output}", file=sys.stderr)
        return None

    prompt_ts = None
    gen_ts = None
    tests: list[str] = []

    for csv_row in csv_rows:
        test_name = next(
            (csv_row.get(key) for key in ("test", "type", "backend") if csv_row.get(key)),
            "",
        )
        if test_name:
            tests.append(test_name)

        row_ts = find_value(
            csv_row,
            (
                "pp t/s",
                "pp_t/s",
                "prompt t/s",
                "prompt tok/s",
                "prompt_ts",
                "avg_ts",
            ),
        )
        if row_ts is not None and (test_name.startswith("pp") or "prompt" in test_name):
            prompt_ts = row_ts
            continue

        row_ts = find_value(
            csv_row,
            (
                "tg t/s",
                "tg_t/s",
                "generation t/s",
                "gen t/s",
                "gen tok/s",
                "avg_ts",
            ),
        )
        if row_ts is not None and (test_name.startswith("tg") or "gen" in test_name):
            gen_ts = row_ts

    if prompt_ts is None and len(csv_rows) == 1:
        prompt_ts = find_value(csv_rows[0], ("pp t/s", "pp_t/s", "prompt t/s", "prompt tok/s"))
    if gen_ts is None and len(csv_rows) == 1:
        gen_ts = find_value(csv_rows[0], ("tg t/s", "tg_t/s", "generation t/s", "gen t/s", "gen tok/s"))

    return {
        "mode": row.get("mode", ""),
        "threads": row.get("threads", ""),
        "threads_batch": row.get("threads_batch", ""),
        "prompt_ts": prompt_ts,
        "gen_ts": gen_ts,
        "test": ",".join(tests),
        "output": str(output),
    }


def print_table(results: list[dict[str, object]]) -> None:
    if not results:
        print("No benchmark rows found. Are the CSV files empty or missing?")
        return

    results.sort(
        key=lambda item: (
            item["mode"],
            -(item["prompt_ts"] or 0.0),
            -(item["gen_ts"] or 0.0),
        )
    )

    print("mode\tthreads\tthreads_batch\tprompt_tok_s\tgen_tok_s\ttest\toutput")
    for item in results:
        prompt = "" if item["prompt_ts"] is None else f"{item['prompt_ts']:.2f}"
        gen = "" if item["gen_ts"] is None else f"{item['gen_ts']:.2f}"
        print(
            f"{item['mode']}\t{item['threads']}\t{item['threads_batch']}\t"
            f"{prompt}\t{gen}\t{item['test']}\t{item['output']}"
        )


def main() -> int:
    args = sys.argv[1:] or sorted(glob.glob("bench-results/*-summary.tsv"))
    if not args:
        print("Usage: ./summarize-bench.py bench-results/*-summary.tsv", file=sys.stderr)
        return 1

    results: list[dict[str, object]] = []
    for arg in args:
        path = Path(arg)
        if not path.exists():
            print(f"Summary not found: {path}", file=sys.stderr)
            continue
        results.extend(
            result
            for row in read_summary(path)
            if (result := result_from_summary_row(row)) is not None
        )

    print_table(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
