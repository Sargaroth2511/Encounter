#!/usr/bin/env python3
"""Mirror calibration — measures the empirical combat worth of each stat increment.

Creates mirror fights (two identical combatants) and bumps one stat at a time
on the foe side, measuring the resulting advantage in fictive-HP delta and
win-rate shift.

Fictive HP includes overkill as negative HP, giving a richer signal than plain
HP remaining: a side that barely died shows 0%, one that was obliterated shows
a large negative value. This helps distinguish close losses from landslides.

This is an *exploratory* tool, separate from calibrate_weights.py. It does not
modify score_weights.json — it just reports "how much combat advantage does
+1 of each stat actually buy?" as a starting point for manual weight design.

Usage:
    python tools/mirror_calibrate.py
    python tools/mirror_calibrate.py --hero aria --runs 500
    python tools/mirror_calibrate.py --hero aria --runs 300 --weapon club
    python tools/mirror_calibrate.py --hero aria --runs 300 --output assets/data/balance/mirror_results.json
    python tools/mirror_calibrate.py --verbose
"""

import argparse
import json
import os
import subprocess
import sys

GODOT_PATH_DEFAULT = "godot"
TEMP_SCENARIO_ID   = "_mirror_temp"
TEMP_SCENARIO_PATH = os.path.join("assets", "data", "scenarios", "_mirror_temp.json")

# Per-stat bump sizes: chosen to be meaningful but not extreme.
STAT_DELTAS: dict[str, int] = {
    "max_hp":            5,
    "max_action_points": 1,
    "hit_chance":        5,
    "dodge":             5,
    "parry":             5,
    "armor":             5,
}


# ---------------------------------------------------------------------------
# Scenario building
# ---------------------------------------------------------------------------

def load_hero(hero_id: str) -> dict:
    path = os.path.join("assets", "data", "heroes", f"{hero_id}.json")
    if not os.path.exists(path):
        print(f"ERROR: hero file not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path) as f:
        return json.load(f)


def _inline_combatant(cid: str, name: str, side: str, stats: dict, profiles: list) -> dict:
    return {
        "id": cid,
        "display_name": name,
        "side": side,
        "stats": stats,
        "attack_profiles": profiles,
    }


def build_mirror_scenario(party_stats: dict, foe_stats: dict, profiles: list) -> dict:
    """Inline mirror scenario — both combatants use the same weapon profiles."""
    return {
        "id": TEMP_SCENARIO_ID,
        "display_name": "Mirror calibration (temp — do not commit)",
        "combatants": [
            _inline_combatant("mirror_party", "Mirror A", "PARTY", party_stats, profiles),
            _inline_combatant("mirror_foe",   "Mirror B", "FOES",  foe_stats,   profiles),
        ],
    }

# ---------------------------------------------------------------------------
# Godot runner
# ---------------------------------------------------------------------------

def run_scenario(scenario: dict, runs: int, godot_path: str, verbose: bool = False) -> dict:
    """Write temp scenario, invoke Godot batch runner, return parsed summary."""
    with open(TEMP_SCENARIO_PATH, "w") as f:
        json.dump(scenario, f, indent=2)

    cmd = [
        godot_path, "--headless",
        "--script", "src/tools/combat_batch.gd", "--",
        "--scenario", TEMP_SCENARIO_ID,
        "--runs", str(runs),
        "--format", "jsonl",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print("ERROR: godot subprocess timed out", file=sys.stderr)
        return {}
    except FileNotFoundError:
        print(f"ERROR: godot not found at '{godot_path}'. Pass --godot-path.", file=sys.stderr)
        sys.exit(1)

    # Last non-empty line that looks like JSON
    lines = [l.strip() for l in result.stdout.splitlines() if l.strip()]
    for line in reversed(lines):
        try:
            data = json.loads(line)
            if "results" in data:
                return data
        except json.JSONDecodeError:
            continue

    if verbose:
        print(f"  stdout: {result.stdout[:600]}")
        print(f"  stderr: {result.stderr[:600]}")
    return {}


# ---------------------------------------------------------------------------
# Measurement logic
# ---------------------------------------------------------------------------

def measure(hero_data: dict, runs: int, godot_path: str, verbose: bool,
            weapon_override: str | None = None) -> list[dict]:
    base_stats = hero_data["stats"].copy()
    profiles   = hero_data.get("attack_profiles", [])
    if weapon_override:
        profiles = [{"id": "main_hand", "weapon": weapon_override}]

    # ---- baseline: identical mirror ----
    print(f"Running baseline ({runs} runs, mirror fight)...", flush=True)
    baseline = run_scenario(
        build_mirror_scenario(base_stats.copy(), base_stats.copy(), profiles),
        runs, godot_path, verbose,
    )
    if not baseline:
        print("ERROR: baseline run returned no data.")
        return []

    b = baseline["results"]
    b_party_fictive = b.get("avg_party_fictive_hp_remaining", 0.0)
    b_foes_fictive  = b.get("avg_foes_fictive_hp_remaining",  0.0)
    b_win_rate      = b.get("party_win_rate", 0.0)
    b_delta         = b_foes_fictive - b_party_fictive  # ~0 for a fair mirror

    print(f"  Baseline win-rate: {b_win_rate*100:.1f}%  "
          f"fictive delta (foe−party): {b_delta*100:+.1f}%")
    print(f"  party fictive={b_party_fictive*100:.1f}%  "
          f"foes fictive={b_foes_fictive*100:.1f}%")
    print()

    # ---- per-stat bumps ----
    results = []
    for stat, delta in STAT_DELTAS.items():
        if stat not in base_stats:
            continue

        bumped = base_stats.copy()
        bumped[stat] = base_stats[stat] + delta

        print(f"  {stat} +{delta}  ({base_stats[stat]} → {bumped[stat]}) ...", end=" ", flush=True)
        run = run_scenario(
            build_mirror_scenario(base_stats.copy(), bumped, profiles),
            runs, godot_path, verbose,
        )
        if not run:
            print("FAILED")
            continue

        r = run["results"]
        r_party_fictive = r.get("avg_party_fictive_hp_remaining", 0.0)
        r_foes_fictive  = r.get("avg_foes_fictive_hp_remaining",  0.0)
        r_win_rate      = r.get("party_win_rate", 0.0)
        r_delta         = r_foes_fictive - r_party_fictive

        # How much did the foe's advantage shift relative to baseline?
        adv_shift   = r_delta - b_delta       # positive = foe gained advantage
        per_unit    = adv_shift / delta        # per stat point
        win_shift   = b_win_rate - r_win_rate  # how much party win-rate dropped

        print(f"win={r_win_rate*100:.1f}%  Δwin={win_shift*100:+.1f}%  "
              f"fictive_adv_shift={adv_shift*100:+.1f}%  per_unit={per_unit*100:+.3f}%")

        results.append({
            "stat":                   stat,
            "delta":                  delta,
            "base_value":             base_stats[stat],
            "bumped_value":           bumped[stat],
            "party_win_rate":         r_win_rate,
            "win_rate_shift":         win_shift,
            "fictive_adv_shift_pct":  adv_shift,
            "fictive_adv_per_unit":   per_unit,
        })

    return results


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Mirror calibration — measures stat worth empirically via mirror fights."
    )
    ap.add_argument("--hero",       default="aria",        help="Hero id (default: aria)")
    ap.add_argument("--weapon",     default="",            help="Override weapon id for both mirror combatants")
    ap.add_argument("--runs",       type=int, default=300, help="Runs per scenario (default: 300)")
    ap.add_argument("--godot-path", default=GODOT_PATH_DEFAULT, dest="godot_path",
                    help="Godot executable path")
    ap.add_argument("--output",     default="",            help="Save results JSON to this path")
    ap.add_argument("--verbose",    action="store_true",   help="Show raw Godot output on errors")
    args = ap.parse_args()

    hero_data = load_hero(args.hero)
    weapon_label = f" (weapon override: {args.weapon})" if args.weapon else ""
    print("=" * 60)
    print(f"Hero:   {hero_data.get('display_name', args.hero)}{weapon_label}")
    print(f"Stats:  {hero_data['stats']}")
    print(f"Runs per scenario: {args.runs}")
    print("=" * 60)
    print()

    results = measure(hero_data, args.runs, args.godot_path, args.verbose,
                      weapon_override=args.weapon if args.weapon else None)

    # Clean up temp scenario
    if os.path.exists(TEMP_SCENARIO_PATH):
        os.remove(TEMP_SCENARIO_PATH)

    if not results:
        print("No results — check errors above.")
        sys.exit(1)

    # Summary table sorted by per-unit advantage (most impactful stat first)
    print()
    print("=" * 60)
    print("STAT WORTH — fictive HP advantage per stat unit (foe bumped)")
    print(f"  {'stat':<24} {'base':>5} {'Δ':>4}  {'per_unit':>10}  {'Δwin_rate':>10}")
    print("  " + "-" * 58)
    for r in sorted(results, key=lambda x: x["fictive_adv_per_unit"], reverse=True):
        print(f"  {r['stat']:<24} {r['base_value']:>5} {'+'+str(r['delta']):>4}  "
              f"{r['fictive_adv_per_unit']*100:>+9.3f}%  "
              f"{r['win_rate_shift']*100:>+9.1f}%")

    if args.output:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults saved to {args.output}")


if __name__ == "__main__":
    main()
