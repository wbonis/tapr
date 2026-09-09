#!/usr/bin/env python3
"""Summarize Tapr decision logs per app launch: taps, side votes, bursts, gate trips.

Usage: scripts/analyze-log.py [events.jsonl ...]
Defaults to ~/Library/Logs/Tapr/events.previous.jsonl and events.jsonl.
"""
import collections
import json
import os
import statistics
import sys

BURST_GAP = 0.5


def load(paths):
    events = []
    for path in paths:
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return events


def sessions(events):
    grouped = collections.OrderedDict()
    for event in events:
        grouped.setdefault(event.get("pid"), []).append(event)
    return grouped.values()


def quartiles(values, points=(0.1, 0.25, 0.5, 0.75, 0.9)):
    if not values:
        return "n/a"
    ordered = sorted(values)
    return " ".join("%.2f" % ordered[min(len(ordered) - 1, int(len(ordered) * p))] for p in points)


def bursts(taps):
    groups, current = [], []
    for tap in taps:
        if current and tap["sensor_time"] - current[-1]["sensor_time"] > BURST_GAP:
            groups.append(current)
            current = []
        current.append(tap)
    if current:
        groups.append(current)
    return groups


def tap_vote(tap):
    if "vote" in tap:
        return tap["vote"]
    return tap.get("left_score", 0) - tap.get("right_score", 0)


def summarize(events):
    launch = next((e for e in events if e["event"] == "launch"), {})
    taps = [e for e in events if e["event"] == "tap"]
    gestures = [e for e in events if e["event"] == "gesture"]
    rejected = [e for e in events if e["event"] == "sequence_rejected"]
    dropped = [e for e in events if e["event"] == "tap_rejected"]
    gate = [e for e in events if e["event"] == "motion_gate" and not e.get("settled")]
    health = [e for e in events if e["event"] == "sensor_health"]
    print("== launch %s version %s threshold %.3f interval %.2f split %s calibration_ready %s" % (
        launch.get("timestamp", "?"), launch.get("version", "?"), launch.get("threshold", 0),
        launch.get("interval", 0), launch.get("split_sides"), launch.get("calibration_ready")))
    if health:
        print("   samples: %d s logged, accel_hz median %d" % (
            len(health), statistics.median(e.get("accel_hz", 0) for e in health)))
    print("   taps: %d  by reason %s" % (len(taps), dict(collections.Counter(t.get("reason") for t in taps))))
    if taps:
        print("   strength_g quartiles: %s" % quartiles([t["strength_g"] for t in taps]))
        print("   |vote| quartiles:     %s" % quartiles([abs(tap_vote(t)) for t in taps]))
    groups = bursts(taps)
    print("   bursts (gap <= %.1f s): %d  sizes %s" % (BURST_GAP, len(groups),
                                                     dict(sorted(collections.Counter(len(g) for g in groups).items()))))
    print("   gestures: %d  %s" % (len(gestures), dict(collections.Counter(
        "%s-%d" % (g.get("side"), g.get("count")) for g in gestures))))
    print("   rejected sequences: %d  %s" % (len(rejected), dict(collections.Counter(r.get("reason") for r in rejected))))
    print("   rejected impacts: %d  %s" % (len(dropped), dict(collections.Counter(d.get("reason") for d in dropped))))
    print("   gate trips: %d  %s  cancelled taps %d  cancelled impacts %d" % (
        len(gate), dict(collections.Counter(g.get("reason") for g in gate)),
        sum(g.get("cancelled_taps", 0) for g in gate), sum(1 for g in gate if g.get("cancelled_impact"))))
    if groups:
        rate = 100.0 * len(gestures) / len(groups)
        print("   recognized gestures per burst: %.0f%%" % rate)


def main(argv):
    folder = os.path.expanduser("~/Library/Logs/Tapr")
    paths = argv[1:] or [os.path.join(folder, "events.previous.jsonl"), os.path.join(folder, "events.jsonl")]
    events = load(paths)
    if not events:
        print("no events found in %s" % ", ".join(paths))
        return 1
    for session in sessions(events):
        summarize(session)
    impacts = os.path.join(folder, "impacts.jsonl")
    if os.path.exists(impacts):
        with open(impacts, encoding="utf-8") as handle:
            count = sum(1 for _ in handle)
        print("== impact windows recorded: %d (%s)" % (count, impacts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
