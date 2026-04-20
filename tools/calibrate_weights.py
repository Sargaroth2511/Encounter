#!/usr/bin/env python3
"""
Score-weight calibrator for Encounter.

Runs a suite of combat scenarios via Godot headless, measures how well the
score-ratio predicts the actual HP-remaining advantage, and auto-tunes the
curve parameters using gradient-free optimisation (scipy Nelder-Mead).

Usage:
    python tools/calibrate_weights.py --mode auto --iterations 50
    python tools/calibrate_weights.py --mode step --iterations 20 --runs-per-scenario 200

Prerequisites:
    pip install scipy numpy
    godot must be on PATH (or set --godot-path)
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any

import numpy as np
from scipy.optimize import minimize

# ---------------------------------------------------------------------------
# Paths (relative to project root)
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent.parent
WEIGHTS_PATH = PROJECT_ROOT / "assets" / "data" / "balance" / "score_weights.json"
SUITE_PATH = PROJECT_ROOT / "assets" / "data" / "balance" / "calibration_suite.json"
BATCH_SCRIPT = "src/tools/combat_batch.gd"

# Stat names in the order they appear in the param vector.
STAT_NAMES = [
    "max_hp",
    "max_mp",
    "max_action_points",
    "hit_chance",
    "dodge",
    "parry",
    "armor",
    "offensive_value",
]

# Each stat has 3 params: scale, midpoint, steepness
PARAMS_PER_STAT = 3


# ---------------------------------------------------------------------------
# Weight I/O
# ---------------------------------------------------------------------------

def load_weights(path: Path = WEIGHTS_PATH) -> dict[str, dict[str, float]]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_weights(weights: dict[str, dict[str, float]], path: Path = WEIGHTS_PATH) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(weights, f, indent=2)
        f.write("\n")


def weights_to_vector(weights: dict[str, dict[str, float]]) -> np.ndarray:
    """Flatten weight dict into a 1-D numpy array for the optimiser."""
    vec: list[float] = []
    for name in STAT_NAMES:
        p = weights.get(name, {"scale": 1.0, "midpoint": 1.0, "steepness": 1.0})
        vec.extend([p["scale"], p["midpoint"], p["steepness"]])
    return np.array(vec, dtype=np.float64)


def vector_to_weights(vec: np.ndarray) -> dict[str, dict[str, float]]:
    """Rebuild weight dict from a flat vector."""
    weights: dict[str, dict[str, float]] = {}
    for i, name in enumerate(STAT_NAMES):
        offset = i * PARAMS_PER_STAT
        weights[name] = {
            "scale": float(max(0.01, vec[offset])),
            "midpoint": float(max(0.01, vec[offset + 1])),
            "steepness": float(max(0.01, vec[offset + 2])),
        }
    return weights


# ---------------------------------------------------------------------------
# Suite / scenario helpers
# ---------------------------------------------------------------------------

def load_suite(path: Path = SUITE_PATH) -> list[str]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["scenarios"]


def run_batch(
    scenario_id: str,
    runs: int,
    godot_path: str,
    seed_start: int = 1,
    max_rounds: int = 100,
) -> dict[str, Any]:
    """Run combat_batch.gd for one scenario and return the parsed JSON summary."""
    cmd = [
        godot_path,
        "--headless",
        "--script", BATCH_SCRIPT,
        "--",
        "--scenario", scenario_id,
        "--runs", str(runs),
        "--seed-start", str(seed_start),
        "--max-rounds", str(max_rounds),
        "--format", "jsonl",
    ]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(PROJECT_ROOT),
        timeout=300,
    )
    if result.returncode != 0:
        print(f"  [ERROR] godot exited {result.returncode} for {scenario_id}",
              file=sys.stderr)
        if result.stderr:
            # Filter out Godot noise, show only real errors
            for line in result.stderr.splitlines():
                if "ERROR" in line or "error" in line.lower():
                    print(f"    {line}", file=sys.stderr)
        return {}

    # combat_batch prints one JSON line to stdout
    stdout = result.stdout.strip()
    if not stdout:
        print(f"  [ERROR] no output from batch run for {scenario_id}", file=sys.stderr)
        return {}

    try:
        return json.loads(stdout)
    except json.JSONDecodeError as e:
        # Godot may print warnings before the JSON line; take the last line
        lines = stdout.splitlines()
        for line in reversed(lines):
            line = line.strip()
            if line.startswith("{"):
                try:
                    return json.loads(line)
                except json.JSONDecodeError:
                    continue
        print(f"  [ERROR] could not parse JSON for {scenario_id}: {e}",
              file=sys.stderr)
        return {}


# ---------------------------------------------------------------------------
# Loss computation
# ---------------------------------------------------------------------------

def compute_scenario_error(summary: dict[str, Any]) -> tuple[float, dict[str, float]]:
    """
    Returns (squared_error, details_dict) for one scenario.

    predicted_advantage = score_ratio - 1.0
    actual_advantage    = avg_party_hp_remaining - avg_foes_hp_remaining
    error               = (predicted - actual)^2
    """
    totals = summary.get("totals", {})
    results = summary.get("results", {})

    score_ratio = float(totals.get("score_ratio", 1.0))
    party_hp = float(results.get("avg_party_hp_remaining", 0.0))
    foes_hp = float(results.get("avg_foes_hp_remaining", 0.0))

    predicted = score_ratio - 1.0
    actual = party_hp - foes_hp
    error = (predicted - actual) ** 2

    return error, {
        "score_ratio": score_ratio,
        "party_hp_pct": party_hp,
        "foes_hp_pct": foes_hp,
        "predicted": predicted,
        "actual": actual,
        "error": error,
    }


# ---------------------------------------------------------------------------
# Objective function
# ---------------------------------------------------------------------------

class Objective:
    """Callable that the optimiser minimises."""

    def __init__(
        self,
        scenarios: list[str],
        runs_per_scenario: int,
        godot_path: str,
        verbose: bool = False,
    ) -> None:
        self.scenarios = scenarios
        self.runs = runs_per_scenario
        self.godot = godot_path
        self.verbose = verbose
        self.eval_count = 0
        self.last_details: dict[str, dict[str, float]] = {}

    def __call__(self, vec: np.ndarray) -> float:
        self.eval_count += 1
        weights = vector_to_weights(vec)
        save_weights(weights)

        total_loss = 0.0
        details: dict[str, dict[str, float]] = {}

        for sid in self.scenarios:
            summary = run_batch(sid, self.runs, self.godot)
            if not summary:
                # Penalise failed runs so the optimiser avoids bad regions
                total_loss += 10.0
                details[sid] = {"error": 10.0, "note": "batch_failed"}
                continue
            err, info = compute_scenario_error(summary)
            total_loss += err
            details[sid] = info

        self.last_details = details

        if self.verbose:
            print(f"  eval #{self.eval_count}  loss={total_loss:.6f}")

        return total_loss


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

def print_iteration_report(
    iteration: int,
    weights: dict[str, dict[str, float]],
    details: dict[str, dict[str, float]],
    total_loss: float,
) -> None:
    print(f"\n{'='*60}")
    print(f"Iteration {iteration}   total_loss = {total_loss:.6f}")
    print(f"{'='*60}")
    print("\n-- Curve parameters --")
    for name in STAT_NAMES:
        p = weights.get(name, {})
        print(f"  {name:20s}  scale={p.get('scale', 0):7.2f}  "
              f"midpoint={p.get('midpoint', 0):7.2f}  "
              f"steepness={p.get('steepness', 0):5.2f}")
    print("\n-- Per-scenario results --")
    print(f"  {'scenario':20s} {'score_ratio':>12s} {'predicted':>10s} "
          f"{'actual':>10s} {'error':>10s} {'party_hp%':>10s} {'foes_hp%':>10s}")
    for sid, info in details.items():
        if "note" in info:
            print(f"  {sid:20s}  ** {info['note']} **")
            continue
        print(f"  {sid:20s} {info['score_ratio']:12.4f} {info['predicted']:10.4f} "
              f"{info['actual']:10.4f} {info['error']:10.6f} "
              f"{info['party_hp_pct']*100:9.1f}% {info['foes_hp_pct']*100:9.1f}%")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Calibrate score weights against combat simulations")
    parser.add_argument("--mode", choices=["auto", "step"], default="auto",
                        help="auto = run to convergence; step = approve each iteration")
    parser.add_argument("--iterations", type=int, default=50,
                        help="Maximum optimiser iterations (default 50)")
    parser.add_argument("--runs-per-scenario", type=int, default=200,
                        help="Fights per scenario per evaluation (default 200)")
    parser.add_argument("--suite", type=str, default=str(SUITE_PATH),
                        help="Path to calibration suite JSON")
    parser.add_argument("--godot-path", type=str, default="godot",
                        help="Path to Godot executable (default: godot)")
    parser.add_argument("--verbose", action="store_true",
                        help="Print every objective evaluation")
    args = parser.parse_args()

    suite_path = Path(args.suite)
    scenarios = load_suite(suite_path)
    print(f"Calibration suite: {scenarios}")
    print(f"Runs per scenario: {args.runs_per_scenario}")
    print(f"Max iterations: {args.iterations}")
    print(f"Mode: {args.mode}")

    # Load initial weights
    weights = load_weights()
    x0 = weights_to_vector(weights)

    objective = Objective(
        scenarios=scenarios,
        runs_per_scenario=args.runs_per_scenario,
        godot_path=args.godot_path,
        verbose=args.verbose,
    )

    if args.mode == "auto":
        _run_auto(objective, x0, args.iterations)
    else:
        _run_step(objective, x0, args.iterations)


def _run_auto(objective: Objective, x0: np.ndarray, max_iter: int) -> None:
    print("\nStarting automatic calibration...\n")

    # Evaluate initial loss
    initial_loss = objective(x0)
    print_iteration_report(0, vector_to_weights(x0), objective.last_details, initial_loss)

    result = minimize(
        objective,
        x0,
        method="Nelder-Mead",
        options={
            "maxiter": max_iter,
            "xatol": 0.01,
            "fatol": 0.0001,
            "adaptive": True,
            "disp": True,
        },
    )

    final_weights = vector_to_weights(result.x)
    save_weights(final_weights)

    # Final evaluation for clean report
    final_loss = objective(result.x)
    print_iteration_report(result.nit, final_weights, objective.last_details, final_loss)
    print(f"\nOptimiser converged: {result.success}")
    print(f"Message: {result.message}")
    print(f"Total evaluations: {objective.eval_count}")
    print(f"Final loss: {final_loss:.6f}")
    print(f"Weights saved to: {WEIGHTS_PATH}")


def _run_step(objective: Objective, x0: np.ndarray, max_iter: int) -> None:
    print("\nStarting step-by-step calibration...\n")

    current = x0.copy()
    best_loss = float("inf")
    best_vec = current.copy()

    for iteration in range(1, max_iter + 1):
        loss = objective(current)
        weights = vector_to_weights(current)
        print_iteration_report(iteration, weights, objective.last_details, loss)

        if loss < best_loss:
            best_loss = loss
            best_vec = current.copy()
            save_weights(weights)
            print(f"\n  ** New best loss: {best_loss:.6f} — weights saved **")

        # One Nelder-Mead step: run a short optimisation from current position
        try:
            answer = input("\nContinue? [y]es / [n]o / [r]eset to best: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nAborted.")
            break

        if answer in ("n", "no"):
            break
        if answer in ("r", "reset"):
            current = best_vec.copy()
            print("  Reset to best known weights.")
            continue

        # Run a short optimisation pass (5 iterations) from current
        result = minimize(
            objective,
            current,
            method="Nelder-Mead",
            options={
                "maxiter": 5,
                "adaptive": True,
                "disp": False,
            },
        )
        current = result.x

    final_weights = vector_to_weights(best_vec)
    save_weights(final_weights)
    print(f"\nCalibration complete. Best loss: {best_loss:.6f}")
    print(f"Weights saved to: {WEIGHTS_PATH}")


if __name__ == "__main__":
    main()
