"""Read-only analysis of ai_match_review + tactical_flow_review evidence.

Usage: python tools/analyze_tactical_flow.py ../verification/before.json --json
The JSON is printed to stdout; a short human summary goes to stderr. No files
are written. Thresholds identify review candidates, not a gameplay acceptance.
"""
from __future__ import annotations

import argparse
import bisect
import collections
import json
import math
import re
import statistics
import sys
from pathlib import Path

CONTROL = {"RECEIVE", "STOP", "SETTLE", "PULL", "CONTROL", "CLOSE", "TURN", "SHIELD", "CARRY", "TACKLE"}
KICKS = {"PASS", "CROSS", "CUTBACK", "SHOT"}
PASSES = KICKS - {"SHOT"}
TRANSITIONS = {"SELECT", "KICK", "CONTROL", "COMPLETE"}


def vector(value):
    if isinstance(value, str):
        value = [float(n) for n in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", value)]
    return tuple(value or (0, 0, 0))


def flat_distance(a, b):
    return math.hypot(a[0] - b[0], a[2] - b[2])


def speed(player):
    v = player["velocity"]
    return math.hypot(v[0], v[2])


def median(values):
    return round(statistics.median(values), 3) if values else None


def rounded(value):
    if isinstance(value, float):
        return round(value, 4) if math.isfinite(value) else None
    if isinstance(value, dict):
        return {str(k): rounded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [rounded(v) for v in value]
    return value


class Evidence:
    def __init__(self, path, bridge):
        self.path = path
        self.base = json.loads(path.read_text(encoding="utf-8-sig"))
        self.flow = json.loads(Path(str(path) + ".flow.json").read_text(encoding="utf-8-sig"))
        self.rows = self.flow["rows"]
        self.contacts = sorted(self.flow["contacts"], key=lambda c: c["t"])
        self.ctimes = [c["t"] for c in self.contacts]
        self.times = [r["t"] for r in self.rows]
        self.team = {}
        for row in self.rows:
            row["ball"] = vector(row["ball"])
            row["ball_velocity"] = vector(row["ball_velocity"])
            row["by_id"] = {int(p["id"]): p for p in row["players"]}
            for p in row["players"]:
                self.team[int(p["id"])] = int(p["team"])
                for k in ("position", "velocity", "facing", "target"):
                    p[k] = vector(p.get(k))
        self.stops = [e for e in self.base["incidents"] if e.get("type") == "rule_state" and e.get("state") in {"STOPPAGE", "GOAL_CELEBRATION", "HALF_TIME", "FULL_TIME"}]
        self.halves = [e["t"] for e in self.base["incidents"] if e.get("state") == "HALF_TIME"]
        self.labels = [r["owner"] if r["live"] else -1 for r in self.rows]
        self.bridged = [False] * len(self.rows)
        self.bridge = bridge
        self._bridge_possession()

    def near(self, t):
        i = bisect.bisect_left(self.times, t)
        return min((j for j in (i - 1, i) if 0 <= j < len(self.rows)), key=lambda j: abs(self.times[j] - t))

    def between(self, start, end):
        return self.contacts[bisect.bisect_right(self.ctimes, start + 1e-6):bisect.bisect_right(self.ctimes, end)]

    def stopped(self, start, end):
        return any(start < e["t"] <= end for e in self.stops)

    def _bridge_possession(self):
        # Only join two observations of the SAME owner. Never carry a last-owner
        # assumption through a pass, an opponent touch, a bounce or a stoppage.
        i = 0
        while i < len(self.rows):
            if self.labels[i] >= 0:
                i += 1
                continue
            start = i
            while i < len(self.rows) and self.labels[i] < 0:
                i += 1
            if start == 0 or i == len(self.rows):
                continue
            actor = self.labels[start - 1]
            if actor < 0 or self.labels[i] != actor or self.times[i] - self.times[start - 1] > self.bridge:
                continue
            touches = self.between(self.times[start - 1], self.times[i])
            if any(c["actor"] != actor or c["action"] in KICKS for c in touches):
                continue
            valid = True
            for j in range(start, i):
                row = self.rows[j]
                p = row["by_id"].get(actor)
                if not row["live"] or not p or row["ball"][1] > 1.0 or flat_distance(row["ball"], p["position"]) > 2.2 or row.get("last_touch", actor) != actor:
                    valid = False
                    break
            if valid:
                for j in range(start, i):
                    self.labels[j], self.bridged[j] = actor, True

    def followup(self, control, horizon=1.5):
        actor, start = control["owner"], control["t"]
        limit = min(start + horizon, self.times[-1])
        later = self.between(start, limit)
        adverse = next((c for c in later if c.get("owner", -1) >= 0 and self.team.get(c["owner"]) != self.team.get(actor)), None)
        other_contact = next((c for c in later if c["actor"] != actor), None)
        next_action = next((c for c in later if c["actor"] == actor and c["action"] in KICKS | {"CLOSE", "TURN", "PULL", "SHIELD", "CARRY"}), None)
        valid_action = next_action is not None and (other_contact is None or next_action["t"] < other_contact["t"]) and not self.stopped(start, next_action["t"])
        end_i = self.near(limit)
        kept = limit >= start + horizon - .05 and not other_contact and not self.stopped(start, limit) and self.labels[end_i] == actor
        # Exclude a subsequent kick from the rebound height measurement.
        next_kick = next((c for c in later if c["action"] in KICKS), None)
        height_end = min(start + 1, next_kick["t"] if next_kick else math.inf)
        heights = [r["ball"][1] for r in self.rows[bisect.bisect_left(self.times, start):bisect.bisect_right(self.times, height_end)]]
        return {"next_effective_action": next_action["action"] if valid_action else None,
                "next_action_delay": next_action["t"] - start if valid_action else None,
                "same_actor_control_at_1_5s": bool(kept), "secure_followup_candidate": bool(valid_action or kept),
                "opponent_control_within_1_5s": adverse is not None, "stoppage_within_1_5s": self.stopped(start, limit),
                "intervening_other_contact_within_1_5s": other_contact is not None,
                "post_control_ball_height_max_before_next_kick": max(heights) if heights else None,
                "window_complete": self.times[-1] >= start + horizon}


def actual_passes(ev):
    result = []
    base_ct = {(round(c["t"], 5), c["actor"], c["action"]): c for c in ev.base["contacts"]}
    for c in ev.contacts:
        if c["action"] not in PASSES:
            continue
        stop_t = min([e["t"] for e in ev.stops if e["t"] > c["t"]] or [math.inf])
        limit = min(c["t"] + 6, stop_t)
        control = next((n for n in ev.between(c["t"], limit)
                        if n.get("owner", -1) >= 0 and n.get("actor") == n["owner"] and n["action"] in CONTROL
                        and not (n["owner"] == c["actor"] and n["t"] - c["t"] < .12)), None)
        base_c = base_ct.get((round(c["t"], 5), c["actor"], c["action"]), {})
        v = vector(base_c.get("velocity"))
        entry = {"t": c["t"], "team": ev.team.get(c["actor"]), "actor": c["actor"], "receiver": c.get("receiver", -1),
                 "style": "loft" if v[1] > 2 else "ground", "mode_at_contact": c.get("mode", ""),
                 "first_control_actor": control["owner"] if control else None,
                 "intended_control": bool(control and c.get("receiver", -1) >= 0 and control["owner"] == c["receiver"]),
                 "flight_to_first_control": control["t"] - c["t"] if control else None,
                 "control_time": control["t"] if control else None, "window_complete": ev.times[-1] >= limit}
        if entry["intended_control"]:
            entry.update(ev.followup(control))
        result.append(entry)
    by_team = {}
    for team in sorted(set(ev.team.values())):
        passes = [p for p in result if p["team"] == team]
        good = [p for p in passes if p["intended_control"]]
        by_team[team] = {"passes": len(passes), "intended_first_controls": len(good),
                         "completion_percent": 100 * len(good) / len(passes) if passes else None,
                         "secure_followup_candidates": sum(p["secure_followup_candidate"] for p in good),
                         "first_control_to_action_median": median([p["next_action_delay"] for p in good if p["next_action_delay"] is not None]),
                         "first_control_rebounds_over_1m": sum((p["post_control_ball_height_max_before_next_kick"] or 0) > 1 for p in good)}
    return {"teams": by_team, "details": result}


def return_combinations(ev, passes):
    """Recognize observed A -> B -> A, independently of tactical labels.

    B's actual first-time return kick is valid receiving evidence even when no
    separate RECEIVE event exists. A must really run forward and receive again.
    Keep unsuccessful adjacent returns so the metric cannot hide failed legs.
    """
    details = []
    records = passes["details"]
    contacts_by_key = {(round(c["t"], 5), c["actor"]): c for c in ev.contacts if c["action"] in PASSES}
    live_starts = [e for e in ev.base["incidents"] if e.get("type") == "rule_state" and e.get("state") == "LIVE"]
    for first, second in zip(records, records[1:]):
        a, b = first["actor"], second["actor"]
        if a == b or ev.team.get(a) != ev.team.get(b) or first["receiver"] != b or second["receiver"] != a:
            continue
        if second["t"] - first["t"] > 8:
            continue
        first_contact = contacts_by_key[(round(first["t"], 5), a)]
        between_kicks = ev.between(first["t"], second["t"])
        b_control = next((c for c in between_kicks if c["actor"] == b and c.get("owner") == b and c["action"] in CONTROL), None)
        b_first_time = b_control is None and not any(c["t"] < second["t"] - 1e-6 for c in between_kicks)
        b_control_time = b_control["t"] if b_control else second["t"] if b_first_time else None
        first_leg_interference = any(c["actor"] != b for c in between_kicks)
        intervening_kick = any(c["action"] in KICKS and c["t"] < second["t"] - 1e-6 for c in between_kicks)
        final_time = second["control_time"]
        final_control = second["intended_control"]
        next_stop = min((e["t"] for e in ev.stops if e["t"] > second["t"]), default=math.inf)
        final_limit = final_time if final_time is not None else min(second["t"] + 6, next_stop, ev.times[-1])
        return_interference = any(c["actor"] != a for c in ev.between(second["t"], final_limit))
        p0 = ev.rows[ev.near(first["t"])]["by_id"][a]
        p1 = ev.rows[max(0, bisect.bisect_right(ev.times, second["t"]) - 1)]["by_id"][a]
        p2 = ev.rows[ev.near(final_limit)]["by_id"][a]
        sign = (-1 if ev.team[a] == 0 else 1) * (-1 if bisect.bisect_right(ev.halves, first["t"]) % 2 else 1)
        before_return = sign * (p1["position"][2] - p0["position"][2])
        final_progress = sign * (p2["position"][2] - p0["position"][2])
        latest_live = max((e for e in live_starts if e["t"] <= first["t"] + .25), key=lambda e: e["t"], default=None)
        context = "open_play"
        restart_age, restart_kind = None, None
        if latest_live:
            restart_age = max(0, first["t"] - latest_live["t"])
            restart_kind = latest_live.get("restart", {}).get("kind")
            # Count the opening three passes within eight seconds separately.
            # Never let a stale kickoff field label the rest of the half.
            prior_kicks = [p for p in records if latest_live["t"] - .25 <= p["t"] < first["t"]]
            opponent_touch = any(ev.team.get(c["actor"]) != ev.team[a] for c in ev.between(latest_live["t"] - .25, first["t"]))
            if restart_kind and restart_age <= 8 and len(prior_kicks) < 3 and not opponent_touch:
                context = "kickoff_sequence" if restart_kind == "kickoff" else "other_restart_sequence"
        elif "restart" in first_contact.get("reason", ""):
            context = "restart_unspecified"
        failures = []
        if b_control_time is None or first_leg_interference:
            failures.append("first_leg_not_cleanly_received_by_B")
        if intervening_kick:
            failures.append("intervening_shot_or_extra_kick")
        if b_control_time is not None and second["t"] - b_control_time > 3:
            failures.append("B_return_delay_over_3s")
        if not final_control:
            failures.append("return_not_first_controlled_by_A")
        if return_interference:
            failures.append("other_actor_touched_return_before_A_control")
        if ev.stopped(first["t"], final_limit):
            failures.append("stoppage_during_combination")
        if final_limit - first["t"] > 8:
            failures.append("whole_combination_over_8s")
        if before_return < .6:
            failures.append("A_forward_run_before_return_under_0_6m")
        if final_progress < 1:
            failures.append("A_final_forward_progress_under_1m")
        details.append({"actor_A": a, "actor_B": b, "team": ev.team[a], "context": context,
                        "restart_kind": restart_kind, "seconds_since_restart": restart_age,
                        "first_pass_time": first["t"], "B_control_time": b_control_time,
                        "B_first_time_return": b_first_time, "return_pass_time": second["t"],
                        "A_control_time": final_time if final_control else None,
                        "return_first_controller": second["first_control_actor"],
                        "A_forward_before_return": before_return, "A_forward_at_end": final_progress,
                        "A_start_position": p0["position"], "A_return_pass_position": p1["position"],
                        "A_end_position": p2["position"], "actual_return_completed": bool(final_control and not first_leg_interference and not intervening_kick and not return_interference and b_control_time is not None and not ev.stopped(first["t"], final_limit)),
                        "forward_return_candidate": not failures, "rejection_reasons": failures,
                        "window_complete": final_time is not None or ev.stopped(second["t"], final_limit) or ev.times[-1] >= second["t"] + 6,
                        "window": {"start": first["t"], "end": final_limit}})
    contexts = {}
    for context in sorted({"open_play", "kickoff_sequence", "other_restart_sequence"} | {d["context"] for d in details}):
        group = [d for d in details if d["context"] == context]
        contexts[context] = {"adjacent_return_attempts": len(group),
                             "actual_returns_completed": sum(d["actual_return_completed"] for d in group),
                             "forward_return_candidates": sum(d["forward_return_candidate"] for d in group)}
    return {"adjacent_return_attempts": len(details), "actual_returns_completed": sum(d["actual_return_completed"] for d in details),
            "forward_return_candidates": sum(d["forward_return_candidate"] for d in details),
            "contexts": contexts, "details": details,
            "criteria": "Consecutive real pass contacts A->B and B->A, same team; B actually controls or returns first-time, no other actor interferes; B returns within 3s of control, A first controls return, no stoppage, total <=8s. A advances >=0.6m before return kick and >=1m before final control along attack direction. Does not require ONE_TWO labels or prove an intentional wall pass. Kickoff/other restart opening three passes within 8s are separately classified; nearby sampled positions have ~0.2s resolution."}


def plan_chains(ev):
    # match_time is monotonic observation time, unlike the tactical clock.
    # Legacy recorder re-emitted its event ring on an epoch change. Exact event
    # fingerprints remove that replay; explicit epochs, when present, win.
    seen, plans, duplicates = set(), {}, 0
    for original in ev.flow.get("events", []):
        e = dict(original)
        fingerprint = json.dumps({k: v for k, v in e.items() if k not in {"match_time", "epoch"}}, sort_keys=True)
        if fingerprint in seen:
            duplicates += 1
            continue
        seen.add(fingerprint)
        t = e.get("match_time", e.get("time", 0))
        epoch = e.get("epoch", bisect.bisect_right(ev.halves, t))
        key = (epoch, e["id"])
        e["observed_at"] = t
        plans.setdefault(key, []).append(e)
    details, mode_counts = [], collections.defaultdict(collections.Counter)
    for (epoch, plan_id), events in plans.items():
        mode = events[0].get("mode", "")
        kicks, controls = [], []
        used_contacts = set()
        for e in events:
            if e["event"] not in {"KICK", "CONTROL"}:
                continue
            kind = e["event"]
            actor = e.get("owner") if kind == "KICK" else e.get("receiver")
            candidates = [(abs(c["t"] - e["observed_at"]), i, c) for i, c in enumerate(ev.contacts)
                          if i not in used_contacts and abs(c["t"] - e["observed_at"]) <= .25
                          and c["actor"] == actor and ((kind == "KICK" and c["action"] in PASSES and c.get("receiver") == e.get("receiver"))
                          or (kind == "CONTROL" and c["action"] in CONTROL and c.get("owner") == actor))]
            match = min(candidates, default=None, key=lambda x: x[0])
            item = {"event_time": e["observed_at"], "stage": e.get("stage"), "actor": actor, "receiver": e.get("receiver"), "actual_contact_verified": bool(match)}
            if match:
                _, ix, c = match
                used_contacts.add(ix)
                item.update({"contact_time": c["t"], "action": c["action"]})
                if kind == "CONTROL":
                    item.update(ev.followup(c))
            (kicks if kind == "KICK" else controls).append(item)
        verified_kicks = [k for k in kicks if k["actual_contact_verified"]]
        verified_controls = [c for c in controls if c["actual_contact_verified"]]
        paired = []
        for k in verified_kicks:
            control = next((c for c in verified_controls if c["actor"] == k["receiver"] and 0 <= c["contact_time"] - k["contact_time"] <= 6), None)
            if control:
                paired.append({"kick_time": k["contact_time"], "control_time": control["contact_time"], "receiver": k["receiver"],
                               "next_action": control.get("next_effective_action"), "next_action_delay": control.get("next_action_delay"),
                               "secure_followup_candidate": control.get("secure_followup_candidate", False)})
        full_two_leg = mode in {"ONE_TWO", "SWITCH_RELAY"} and len(paired) >= 2 and any(k.get("stage") == "RETURN_FLIGHT" for k in verified_kicks)
        item = {"epoch": epoch, "plan_id": plan_id, "mode": mode, "from": events[0]["observed_at"], "to": events[-1]["observed_at"],
                "events": [e["event"] for e in events], "kicks": kicks, "controls": controls, "paired_actual_legs": paired,
                "two_leg_completion_candidate": full_two_leg,
                "cancellation_reasons": [e["event"] for e in events if e["event"] not in TRANSITIONS]}
        details.append(item)
        counts = mode_counts[mode]
        counts["plan_lifetimes_seen"] += 1
        counts["selected"] += any(e["event"] == "SELECT" for e in events)
        counts["actual_kick_legs"] += len(verified_kicks)
        counts["actual_kick_control_legs"] += len(paired)
        counts["legs_with_continuation_candidate"] += sum(p["secure_followup_candidate"] for p in paired)
        counts["two_leg_completion_candidates"] += full_two_leg
    return {"modes": dict(mode_counts), "duplicate_ring_events_removed": duplicates,
            "epoch_source": "explicit where present, otherwise half-time inferred; monotonic match_time used for contact matching",
            "details": details}


def possession(ev):
    segments, low_segments = [], []
    current, slow = None, None
    per_team = collections.defaultdict(lambda: collections.Counter())
    for i, row in enumerate(ev.rows):
        dt = min(.3, (ev.times[i + 1] - row["t"]) if i + 1 < len(ev.rows) else 0)
        actor = ev.labels[i]
        p = row["by_id"].get(actor)
        if p:
            team = ev.team[actor]
            per_team[team]["stitched_owned_seconds"] += dt
            per_team[team]["raw_owned_seconds"] += dt if row["owner"] == actor else 0
            per_team[team]["bridged_seconds"] += dt if ev.bridged[i] else 0
            per_team[team]["speed_below_1_seconds"] += dt if speed(p) < 1 else 0
        if current and (actor != current["actor"] or not p):
            segments.append(current)
            current = None
        if p:
            if current is None:
                current = {"actor": actor, "team": ev.team[actor], "start": row["t"], "end": row["t"], "duration": 0, "distance": 0, "bridged_seconds": 0}
            current["end"] = row["t"] + dt
            current["duration"] += dt
            current["bridged_seconds"] += dt if ev.bridged[i] else 0
            current["distance"] += speed(p) * dt
        slow_now = p is not None and speed(p) < 1
        if slow and (not slow_now or slow["actor"] != actor):
            if slow["duration"] >= .6:
                low_segments.append(slow)
            slow = None
        if slow_now:
            if slow is None:
                slow = {"actor": actor, "start": row["t"], "end": row["t"], "duration": 0, "reasons": set(), "feet": set()}
            slow["end"] = row["t"] + dt
            slow["duration"] += dt
            slow["reasons"].add(p.get("reason", ""))
            slow["feet"].add(p.get("foot", ""))
    if current:
        segments.append(current)
    if slow and slow["duration"] >= .6:
        low_segments.append(slow)
    for s in low_segments:
        s["reasons"], s["feet"] = sorted(s["reasons"]), sorted(s["feet"])
    return {"bridge_max_seconds": ev.bridge, "teams": dict(per_team), "segment_count": len(segments),
            "segment_duration_median": median([s["duration"] for s in segments]),
            "segments_over_3s": sum(s["duration"] >= 3 for s in segments),
            "low_speed_runs_over_0_6s": sorted(low_segments, key=lambda x: -x["duration"]),
            "longest_possessions": sorted(segments, key=lambda x: -x["duration"])[:12]}


def dribbles(ev):
    details = []
    for c in ev.contacts:
        if c["action"] not in {"TURN", "PULL"}:
            continue
        i = ev.near(c["t"])
        start = ev.rows[i]
        actor = c["actor"]
        p = start["by_id"].get(actor)
        if not p:
            continue
        team = ev.team[actor]
        opponents = [q for q in start["players"] if q["team"] != team and flat_distance(q["position"], p["position"]) <= 3.2]
        tagged = any(r["by_id"].get(actor, {}).get("cut", False) for r in ev.rows[max(0, i - 2):min(len(ev.rows), i + 3)])
        end_i = ev.near(c["t"] + 1.5)
        end = ev.rows[end_i]
        ep = end["by_id"].get(actor)
        complete = ev.times[-1] >= c["t"] + 1.5 and end["t"] - start["t"] >= 1.3
        sign = (-1 if team == 0 else 1) * (-1 if bisect.bisect_right(ev.halves, c["t"]) % 2 else 1)
        progress = sign * (ep["position"][2] - p["position"][2]) if ep else 0
        indices = range(i, end_i + 1)
        controlled = sum(ev.labels[j] == actor for j in indices) / max(1, end_i - i + 1)
        other_touch = any(x["actor"] != actor for x in ev.between(c["t"], end["t"]))
        kept = complete and ev.labels[end_i] == actor and controlled >= .8 and not other_touch and not ev.stopped(c["t"], end["t"]) and ep is not None and flat_distance(end["ball"], ep["position"]) <= 1.6
        beaten = []
        chase_exits = []
        for q in opponents:
            eq = end["by_id"].get(q["id"])
            if kept and eq and progress >= 1 and sign * (q["position"][2] - p["position"][2]) > .2 and sign * (eq["position"][2] - ep["position"][2]) < -.25:
                beaten.append(q["id"])
            gap = flat_distance(q["position"], p["position"])
            approach_speed = ((p["position"][0] - q["position"][0]) * q["velocity"][0] + (p["position"][2] - q["position"][2]) * q["velocity"][2]) / max(.001, gap)
            end_gap = flat_distance(eq["position"], ep["position"]) if eq and ep else 0
            if kept and eq and progress >= 2 and sign * (q["position"][2] - p["position"][2]) < -.2 and approach_speed >= 1 and end_gap >= 2.5 and end_gap - gap >= 1.2:
                chase_exits.append({"opponent": q["id"], "start_gap": gap, "end_gap": end_gap, "opponent_speed_toward_carrier_at_start": approach_speed})
        pass_exit = cut_then_completed_pass(ev, c, i, opponents, sign) if tagged else None
        details.append({"t": c["t"], "actor": actor, "action": c["action"], "tagged_cut_near_contact": tagged,
                        "nearby_opponents": [q["id"] for q in opponents], "window_complete": complete,
                        "forward_progress_1_5s": progress, "stitched_control_fraction": controlled,
                        "retained_for_1_5s_candidate": kept, "opponents_crossed_front_to_back": beaten,
                        "beat_candidate": bool(beaten), "chase_escape_candidates": chase_exits,
                        "cut_then_completed_pass": pass_exit,
                        "window": {"start": c["t"], "end": end["t"]}, "reason": c.get("reason", "")})
    episodes = []
    for d in details:
        prior = episodes[-1] if episodes else None
        join = prior is not None and d["actor"] == prior["actor"] and d["t"] - prior["start"] <= 1.5 and not ev.stopped(prior["last_contact"], d["t"]) and not any(c["actor"] != d["actor"] or c["action"] in KICKS for c in ev.between(prior["last_contact"], d["t"]))
        if not join:
            prior = {"actor": d["actor"], "start": d["t"], "last_contact": d["t"], "review_end": d["window"]["end"],
                     "contact_times": [], "successful_contact_times": [], "opponents_crossed": set(),
                     "under_pressure": False, "all_windows_complete": True}
            episodes.append(prior)
        prior["last_contact"] = d["t"]
        prior["review_end"] = max(prior["review_end"], d["window"]["end"])
        prior["contact_times"].append(d["t"])
        prior["under_pressure"] = prior["under_pressure"] or bool(d["nearby_opponents"])
        prior["all_windows_complete"] = prior["all_windows_complete"] and d["window_complete"]
        if d["beat_candidate"]:
            prior["successful_contact_times"].append(d["t"])
            prior["opponents_crossed"].update(d["opponents_crossed_front_to_back"])
    for episode in episodes:
        episode["opponents_crossed"] = sorted(episode["opponents_crossed"])
        episode["beat_episode_candidate"] = bool(episode["successful_contact_times"])
    return {"actual_turn_pull_contacts": len(details), "tagged_cut_contacts": sum(d["tagged_cut_near_contact"] for d in details),
            "under_pressure_contacts": sum(bool(d["nearby_opponents"]) for d in details),
            "retained_under_pressure_candidates": sum(d["retained_for_1_5s_candidate"] and bool(d["nearby_opponents"]) for d in details),
            "beat_candidates": sum(d["beat_candidate"] for d in details),
            "beat_episode_candidates": sum(e["beat_episode_candidate"] for e in episodes),
            "turn_pull_episode_count": len(episodes), "episodes": episodes,
            "episode_merge_criteria": "Same actor actual TURN/PULL contacts within a fixed 1.5s from first contact, without intervening other-player touch, pass/shot or stoppage. Preserve raw contacts and failed/incomplete episodes; strict beat criteria unchanged. One episode may cross multiple opponents but counts once.",
            "chase_escape_candidates": sum(bool(d["chase_escape_candidates"]) for d in details),
            "cut_escape_completed_pass_candidates": sum(bool(d["cut_then_completed_pass"] and d["cut_then_completed_pass"]["escape_then_completed_pass_candidate"]) for d in details),
            "details": details,
            "chase_escape_criteria": "Actual TURN/PULL, opponent within 3.2m and behind by >0.2m, moving toward carrier at >=1m/s; player advances >=2m and retains the same strict 1.5s control; gap increases >=1.2m to >=2.5m. Candidate for review; not a head-on beat.",
            "cut_escape_pass_criteria": "Tagged actual TURN/PULL, PASS to teammate within 2s with no intervening other touch/stoppage; before pass, advance >=0.6m and cross same opponent from ahead to behind, OR move >=1m and increase opponent gap >=0.6m to >=1.7m. Intended teammate must be the first actual controller within 6s. No 1.5s carry requirement. One completed pass may appear under multiple preceding cut touches; use unique_pass_candidates below.",
            "unique_cut_escape_completed_pass_candidates": len({(d["actor"], d["cut_then_completed_pass"]["pass_time"]) for d in details if d["cut_then_completed_pass"] and d["cut_then_completed_pass"]["escape_then_completed_pass_candidate"]}),
            "criteria": "Actual TURN/PULL; opponent within 3.2m; player progresses >=1m along attack; same opponent moves from >0.2m ahead to >0.25m behind; >=80% stitched own control for 1.5s, same owner at end, ball gap<=1.6m, no other touch/stoppage. Conservative review candidate, not proven intentional dribble."}


def cut_then_completed_pass(ev, cut, start_i, opponents, sign):
    actor = cut["actor"]
    following = ev.between(cut["t"], cut["t"] + 2)
    kick = next((c for c in following if c["actor"] == actor and c["action"] in PASSES), None)
    if not kick:
        return None
    receiver = kick.get("receiver", -1)
    p = ev.rows[start_i]["by_id"][actor]
    pass_i = max(start_i, bisect.bisect_right(ev.times, kick["t"]) - 1)
    end = ev.rows[pass_i]
    ep = end["by_id"][actor]
    progress = sign * (ep["position"][2] - p["position"][2])
    displacement = flat_distance(ep["position"], p["position"])
    escapes = []
    for q in opponents:
        eq = end["by_id"].get(q["id"])
        if not eq:
            continue
        before_gap = flat_distance(q["position"], p["position"])
        after_gap = flat_distance(eq["position"], ep["position"])
        before_forward = sign * (q["position"][2] - p["position"][2])
        after_forward = sign * (eq["position"][2] - ep["position"][2])
        crossed = progress >= .6 and before_forward > .2 and after_forward < -.25
        separated = displacement >= 1 and after_gap - before_gap >= .6 and after_gap >= 1.7
        if crossed or separated:
            escapes.append({"opponent": q["id"], "crossed_front_to_back": crossed, "increased_separation": separated,
                            "start_gap": before_gap, "gap_at_pass": after_gap, "forward_gap_start": before_forward, "forward_gap_at_pass": after_forward})
    interference = any(c["actor"] != actor for c in following if c["t"] < kick["t"])
    stop_t = min([e["t"] for e in ev.stops if e["t"] > kick["t"]] or [math.inf])
    control = next((c for c in ev.between(kick["t"], min(stop_t, kick["t"] + 6)) if c["action"] in CONTROL and c.get("owner", -1) >= 0 and c["actor"] == c["owner"]), None)
    completed = bool(control and receiver >= 0 and receiver != actor and ev.team.get(receiver) == ev.team.get(actor) and control["owner"] == receiver)
    candidate = bool(escapes and completed and not interference and not ev.stopped(cut["t"], kick["t"]))
    return {"cut_time": cut["t"], "pass_time": kick["t"], "receiver": receiver,
            "forward_progress_before_pass": progress, "movement_before_pass": displacement,
            "escape_evidence": escapes, "other_actor_touch_before_pass": interference,
            "first_controller": control["owner"] if control else None, "control_time": control["t"] if control else None,
            "intended_real_control": completed, "escape_then_completed_pass_candidate": candidate,
            "receive_window_complete": control is not None or stop_t <= ev.times[-1] or ev.times[-1] >= kick["t"] + 6,
            "window": {"start": cut["t"], "end": control["t"] if control else max(kick["t"], min(stop_t, kick["t"] + 6, ev.times[-1]))}}


def chase_pressure_windows(ev):
    """Find actual run-away-from-a-chaser evidence, including plain CLOSE carries.

    This is independent of TURN/PULL so clean forward acceleration is visible.
    Overlapping successful windows for the same actor/defender are deduplicated.
    """
    found, until = [], {}
    for i, row in enumerate(ev.rows):
        actor = ev.labels[i]
        p = row["by_id"].get(actor)
        if not p or not row["live"] or ev.times[-1] < row["t"] + 1.5:
            continue
        team = ev.team[actor]
        sign = (-1 if team == 0 else 1) * (-1 if bisect.bisect_right(ev.halves, row["t"]) % 2 else 1)
        end_i = ev.near(row["t"] + 1.5)
        end = ev.rows[end_i]
        ep = end["by_id"][actor]
        progress = sign * (ep["position"][2] - p["position"][2])
        if progress < 2 or ev.labels[end_i] != actor or flat_distance(end["ball"], ep["position"]) > 1.6 or ev.stopped(row["t"], end["t"]):
            continue
        controlled = sum(ev.labels[j] == actor for j in range(i, end_i + 1)) / max(1, end_i - i + 1)
        if controlled < .8 or any(c["actor"] != actor or c["action"] in KICKS for c in ev.between(row["t"], end["t"])):
            continue
        for q in row["players"]:
            if q["team"] == team or row["t"] < until.get((actor, q["id"]), -1):
                continue
            gap = flat_distance(q["position"], p["position"])
            if gap > 3.2 or sign * (q["position"][2] - p["position"][2]) >= -.2:
                continue
            approach = ((p["position"][0] - q["position"][0]) * q["velocity"][0] + (p["position"][2] - q["position"][2]) * q["velocity"][2]) / max(.001, gap)
            eq = end["by_id"][q["id"]]
            end_gap = flat_distance(eq["position"], ep["position"])
            if approach >= 1 and end_gap >= 2.5 and end_gap - gap >= 1.2:
                found.append({"start": row["t"], "end": end["t"], "actor": actor, "opponent": q["id"],
                              "start_gap": gap, "end_gap": end_gap, "forward_progress": progress,
                              "start_player_speed": speed(p), "end_player_speed": speed(ep),
                              "opponent_speed_toward_carrier": approach, "stitched_control_fraction": controlled,
                              "start_reason": p.get("reason"), "end_reason": ep.get("reason")})
                until[(actor, q["id"])] = end["t"] + .5
    return {"candidate_count": len(found), "windows": found,
            "criteria": "Actual sampled carry, not restricted to a named cut: same strict 1.5s control, >=2m forward, chaser initially <=3.2m and >0.2m behind, moving toward carrier >=1m/s; separation grows >=1.2m to >=2.5m. No intervening other touch or pass/shot. Overlapping actor/opponent windows deduplicated. Review candidates only."}


def out_attribution(ev):
    outs = []
    for e in ev.stops:
        kind = e.get("restart", {}).get("kind", "")
        if e.get("state") != "STOPPAGE" or kind not in {"throw_in", "goal_kick", "corner"}:
            continue
        i = bisect.bisect_right(ev.ctimes, e["t"])
        c = ev.contacts[i - 1] if i else None
        row = ev.rows[ev.near(e["t"])]
        p = row["by_id"].get(c["actor"]) if c else None
        outs.append({"t": e["t"], "kind": kind, "last_successful_touch_action": c["action"] if c else None,
                     "last_touch_actor": c["actor"] if c else None, "touch_to_out_seconds": e["t"] - c["t"] if c else None,
                     "touch_reason": c.get("reason") if c else None, "last_actor_reason_at_out": p.get("reason") if p else None,
                     "last_actor_ball_gap_at_out": flat_distance(p["position"], row["ball"]) if p else None})
    return {"total": len(outs), "last_action_counts": dict(collections.Counter(o["last_successful_touch_action"] for o in outs)),
            "details": outs, "meaning": "Last recorded successful actor touch, not definitive fault attribution; unreported body/post deflections may intervene."}


def analyze(path, bridge=.8):
    ev = Evidence(path, bridge)
    passes = actual_passes(ev)
    return rounded({"schema": "football_tactical_flow_analysis_v1", "source": str(path.resolve()), "seed": ev.base.get("seed"),
                    "simulation_seconds": ev.base.get("duration_sim_seconds"), "live_seconds": ev.base.get("live_seconds"),
                    "full_time": ev.base.get("full_time", False), "stats": ev.base.get("stats"),
                    "passes": passes, "observed_return_combinations": return_combinations(ev, passes),
                    "plans": plan_chains(ev), "possession": possession(ev), "dribbles": dribbles(ev),
                    "chase_pressure_escape": chase_pressure_windows(ev),
                    "outs": out_attribution(ev),
                    "limitations": ["Natural sampled evidence, not visual/player acceptance or FPS evidence.",
                                    "Transient owner gaps are joined only when both ends have the same actor, <=0.8s (unless overridden), no intervening kick/other touch, ball <=1m high and <=2.2m away.",
                                    "First control does not mean a secure reception. Followup candidates may include a deliberate release; they do not prove sustained control.",
                                    "Plans require actual matching contacts. SELECT/COMPLETE strings alone do not count. Missing terminal records remain unverified.",
                                    "Cut classification is conservative; ordinary turns and involuntary PULL contacts may enter candidate review. No claim of learned intent.",
                                    "A match-time epoch is explicit when recorded; older logs infer halftime epochs. Exact duplicate ring contents are removed even when replayed with a new epoch. Arbitrary unlogged resets or identical reused event IDs cannot be reconstructed perfectly.",
                                    "Attack direction assumes blue starts toward -Z and reverses at halftime, as in these scenes."]})


def concise(report):
    lines = [f"{Path(report['source']).name}: sim={report['simulation_seconds']:.1f}s live={report['live_seconds']:.1f}s seed={report['seed']}"]
    for team, p in report["passes"]["teams"].items():
        lines.append(f"  team {team}: passes={p['passes']} intended first controls={p['intended_first_controls']} secure followup candidates={p['secure_followup_candidates']} receive->action median={p['first_control_to_action_median']}")
    for mode, m in report["plans"]["modes"].items():
        lines.append(f"  {mode}: SELECT={m['selected']} actual KICK={m['actual_kick_legs']} KICK->CONTROL={m['actual_kick_control_legs']} continued={m['legs_with_continuation_candidate']} two legs={m['two_leg_completion_candidates']}")
    d = report["dribbles"]
    for context, c in report["observed_return_combinations"]["contexts"].items():
        lines.append(f"  observed A->B->A {context}: attempts={c['adjacent_return_attempts']} completed={c['actual_returns_completed']} forward-run candidates={c['forward_return_candidates']}")
    lines.append(f"  TURN/PULL={d['actual_turn_pull_contacts']} pressure={d['under_pressure_contacts']} retained1.5s={d['retained_under_pressure_candidates']} beat contacts={d['beat_candidates']} independent beat episodes={d['beat_episode_candidates']} (all turn/pull episodes={d['turn_pull_episode_count']})")
    lines.append(f"  chase escape windows={report['chase_pressure_escape']['candidate_count']} (after TURN/PULL={d['chase_escape_candidates']}) cut->escape->completed pass candidates={d['unique_cut_escape_completed_pass_candidates']}")
    for team, p in report["possession"]["teams"].items():
        lines.append(f"  team {team}: stitched control={p['stitched_owned_seconds']:.2f}s bridged={p['bridged_seconds']:.2f}s speed<1={p['speed_below_1_seconds']:.2f}s")
    lines.append(f"  outs={report['outs']['total']} last touches={report['outs']['last_action_counts']}")
    lines.append("  Counts are review candidates; no subjective or performance acceptance claimed.")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, default=[Path(__file__).resolve().parents[2] / "verification" / "before.json"])
    parser.add_argument("--json", action="store_true", help="Print full JSON to stdout, concise summary to stderr")
    parser.add_argument("--bridge", type=float, default=.8, help="Maximum sampled owner gap span, in seconds")
    args = parser.parse_args()
    reports = [analyze(p, args.bridge) for p in args.paths]
    for report in reports:
        print(concise(report), file=sys.stderr if args.json else sys.stdout)
    if args.json:
        print(json.dumps(reports[0] if len(reports) == 1 else reports, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
