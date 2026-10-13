"""Report actual contacts and sampled territory; never label these metrics AI strength."""
import json
import math
import re
import sys
from collections import Counter
from pathlib import Path


def vec(value):
    if isinstance(value, str):
        return tuple(float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", value))
    return value


def summary(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    halftime = next((e["t"] for e in data["incidents"] if e.get("state") == "HALF_TIME"), math.inf)
    teams = [{"passes": 0, "received_by_intended_player": 0, "retained_after_pass": 0,
              "shots": 0, "shots_within_20m": 0, "shot_distance_total": 0,
              "owned_seconds": 0, "owned_attacking_third_seconds": 0,
              "controlled_box_entries": 0, "stall_flag_count": 0,
              "confirmed_tackles": 0} for _ in range(2)]
    contacts = data["contacts"]
    pass_types = {"PASS", "CROSS", "CUTBACK"}
    for i, contact in enumerate(contacts):
        actor = contact["actor"]
        if actor < 0:
            continue
        team = 0 if actor < 11 else 1
        out = teams[team]
        action = contact["action"]
        if action in pass_types:
            out["passes"] += 1
            # A actual controlled touch, rather than a plan event or proximity.
            for later in contacts[i + 1:]:
                if later["t"] - contact["t"] > 6:
                    break
                if later.get("owner", -1) < 0:
                    continue
                owner = later["owner"]
                if owner == actor and later["t"] - contact["t"] < .12:
                    continue
                if owner == contact["receiver"]:
                    out["received_by_intended_player"] += 1
                if (owner < 11) == (team == 0):
                    out["retained_after_pass"] += 1
                break
        elif action == "SHOT":
            out["shots"] += 1
            attack_sign = (-1 if team == 0 else 1) * (-1 if contact["t"] > halftime else 1)
            ball = vec(contact["ball"])
            distance = math.hypot(ball[0], attack_sign * 52.5 - ball[2])
            out["shot_distance_total"] += distance
            if distance <= 20:
                out["shots_within_20m"] += 1
        elif action == "TACKLE":
            out["confirmed_tackles"] += 1
    last_t = 0
    inside = [False, False]
    reasons = Counter()
    for row in data["rows"]:
        dt = min(.25, row["t"] - last_t)
        last_t = row["t"]
        owner = row["owner"]
        if not row["live"] or owner < 0:
            continue
        team = 0 if owner < 11 else 1
        ball = vec(row["ball"])
        sign = (-1 if team == 0 else 1) * (-1 if row["t"] > halftime else 1)
        out = teams[team]
        depth = 52.5 - sign * ball[2]
        out["owned_seconds"] += dt
        if depth < 35:
            out["owned_attacking_third_seconds"] += dt
        box = depth < 16.5 and abs(ball[0]) < 20.16
        if box and not inside[team]:
            out["controlled_box_entries"] += 1
        inside[team] = box
        inside[1-team] = False
        for job in row["jobs"]:
            if job["id"] == owner:
                reasons[job["reason"]] += 1
    for event in data["incidents"]:
        if event["type"] == "carrier_stall_candidate":
            teams[0 if event["id"] < 11 else 1]["stall_flag_count"] += 1
    for out in teams:
        out["intended_pass_completion_percent"] = round(100*out["received_by_intended_player"]/max(1, out["passes"]), 1)
        out["average_shot_distance"] = round(out.pop("shot_distance_total")/max(1, out["shots"]), 2)
        for key, value in out.items():
            if isinstance(value, float):
                out[key] = round(value, 2)
    return {"file": str(path), "full_time": data.get("full_time", False),
            "sim_seconds": data["duration_sim_seconds"], "live_seconds": data["live_seconds"],
            "half_time_at": halftime if math.isfinite(halftime) else None,
            "stats": data["stats"], "teams_blue_yellow": teams,
            "carrier_reasons_sample_count": dict(reasons.most_common()),
            "limitations": "All-AI vs own-version AI; not a head-to-head strength estimate. Sampled territory/contact attribution. No FPS inference. Restart passes included; completion window 6 s. Box entries are possession excursions, not xG."}


if __name__ == "__main__":
    print(json.dumps([summary(p) for p in sys.argv[1:]], ensure_ascii=False, indent=2))
