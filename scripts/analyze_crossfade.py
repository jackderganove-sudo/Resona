#!/usr/bin/env python3
"""Evaluates the crossfade measurements of the simulator run.

Input per case (from the app's Documents, see CrossfadeTestHarness.swift):
  crossfade-<case>.csv     every 10 ms, for BOTH mpv instances:
                           t, slot, active, file, pos, volume, paused, idle
  crossfade-<case>.events  case/fade/start/length + skip/pause/resume times

The simulator plays with ao=null, so there is no audio device to record.
What is measured is the REAL state of both mpv instances (position and
volume, set by the real CrossfadeEngine). The audible mix is reconstructed
from it: the test files are known sine tones (xf-a 440 Hz, xf-b 660 Hz,
xf-c 880 Hz, amplitude 0.5), so every instance contributes
    0.5 * (volume / 100) ** 3 * sin(2 pi f pos(t))
(mpv applies its software volume cubically). Positions and volumes are
interpolated linearly between the 10 ms samples. The mix is written as a
WAV, then evaluated in 50 ms windows: RMS, Goertzel magnitude per tone,
silence/gaps, jumps, and the power sum during the fade (equal power).

Output: <out>/crossfade-<case>.png, crossfade-<case>-mix.wav and
crossfade-results.json (+ markdown summary on stdout).
"""

import csv
import json
import math
import struct
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 8000
WINDOW = 0.05
FREQ = {"xf-a.wav": 440.0, "xf-b.wav": 660.0, "xf-c.wav": 880.0}
AMP = 0.5
SILENCE_DB = -40.0


def load(case_dir: Path, case: str):
    rows = list(csv.DictReader(open(case_dir / f"crossfade-{case}.csv")))
    meta, events = {}, []
    events_file = case_dir / f"crossfade-{case}.events"
    if events_file.exists():
        for line in events_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                meta[k] = v
            elif "," in line:
                t, name = line.split(",", 1)
                events.append((float(t), name))
    samples = {}
    for r in rows:
        t = float(r["t"])
        samples.setdefault(t, {})[r["slot"]] = {
            "active": r["active"] == "1",
            "file": r["file"],
            "pos": float(r["pos"]),
            "vol": float(r["volume"]),
            "paused": r["paused"] == "1",
            "idle": r["idle"] == "1",
        }
    times = sorted(samples)
    return times, samples, meta, events


def gain(vol):
    return AMP * max(0.0, vol / 100.0) ** 3


def reconstruct(times, samples):
    """Mix + per-tone amplitude envelopes at RATE."""
    duration = times[-1]
    n = int(duration * RATE)
    tau = np.arange(n) / RATE
    mix = np.zeros(n)
    envelopes = {f: np.zeros(n) for f in FREQ}
    slots = sorted({s for t in times for s in samples[t]})
    for slot in slots:
        for a, b in zip(times, times[1:]):
            sa, sb = samples[a].get(slot), samples[b].get(slot)
            if not sa or sa["file"] not in FREQ or sa["idle"] or sa["paused"]:
                continue
            i0, i1 = int(a * RATE), min(n, int(b * RATE))
            if i1 <= i0:
                continue
            frac = (tau[i0:i1] - a) / max(1e-6, b - a)
            same = sb and sb["file"] == sa["file"] and not sb["idle"] and 0 <= sb["pos"] - sa["pos"] < 0.2 + (b - a)
            if same:
                pos = sa["pos"] + (sb["pos"] - sa["pos"]) * frac
                vol = sa["vol"] + (sb["vol"] - sa["vol"]) * frac
            else:
                pos = sa["pos"] + (tau[i0:i1] - a)
                vol = np.full(i1 - i0, sa["vol"])
            amp = AMP * np.clip(vol / 100.0, 0, None) ** 3
            mix[i0:i1] += amp * np.sin(2 * math.pi * FREQ[sa["file"]] * pos)
            envelopes[sa["file"]][i0:i1] += amp
    return tau, mix, envelopes


def goertzel(block, freq):
    k = 2 * math.cos(2 * math.pi * freq / RATE)
    s1 = s2 = 0.0
    for x in block:
        s0 = x + k * s1 - s2
        s2, s1 = s1, s0
    power = s1 * s1 + s2 * s2 - k * s1 * s2
    return 2 * math.sqrt(max(power, 0)) / len(block)   # ≈ sine amplitude


def write_wav(path, mix):
    peak = max(1e-9, float(np.max(np.abs(mix))))
    data = np.clip(mix / max(1.0, peak), -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in data))


def analyze(case_dir: Path, out: Path, case: str):
    times, samples, meta, events = load(case_dir, case)
    fade = float(meta.get("fade", 0))
    tau, mix, env = reconstruct(times, samples)
    write_wav(out / f"crossfade-{case}-mix.wav", mix)

    win = int(WINDOW * RATE)
    centers, rms_db, tones = [], [], {f: [] for f in FREQ}
    for i in range(0, len(mix) - win, win):
        block = mix[i:i + win]
        centers.append((i + win / 2) / RATE)
        rms = math.sqrt(float(np.mean(block ** 2)))
        rms_db.append(20 * math.log10(max(rms, 1e-9)))
        for f, hz in FREQ.items():
            tones[f].append(goertzel(block, hz))
    centers = np.array(centers)
    rms_db = np.array(rms_db)

    pause_ranges = []
    pause_start = None
    for t, name in events:
        if name == "pause":
            pause_start = t
        elif name == "resume" and pause_start is not None:
            pause_ranges.append((pause_start, t))
            pause_start = None

    def excused(t, margin=0.35):
        if any(a - margin <= t <= b + margin for a, b in pause_ranges):
            return True
        return any(abs(t - e) <= margin for e, n in events if n == "skip")

    # Silence (gaps) after the first audio, excluding pauses.
    audible = rms_db > SILENCE_DB
    first = int(np.argmax(audible)) if audible.any() else len(audible)
    gaps, current = [], None
    for i in range(first, len(audible)):
        if not audible[i] and not excused(centers[i], 0):
            current = current or [centers[i], centers[i]]
            current[1] = centers[i]
        elif current:
            gaps.append(current)
            current = None
    if current:
        gaps.append(current)
    gaps = [(a, b + WINDOW) for a, b in gaps]

    # Jumps: loudness step > 6 dB between neighbouring windows (fades are
    # smooth: 3 s ≈ 60 windows), skip/pause/resume excused.
    jumps = [float(centers[i]) for i in range(first + 1, len(rms_db))
             if abs(rms_db[i] - rms_db[i - 1]) > 6 and not excused(centers[i])
             and rms_db[i] > SILENCE_DB and rms_db[i - 1] > SILENCE_DB]

    # Position jumps of each instance while playing the same file.
    pos_jumps = []
    for a, b in zip(times, times[1:]):
        for slot, sa in samples[a].items():
            sb = samples[b].get(slot)
            if not sb or sa["file"] != sb["file"] or sa["file"] not in FREQ:
                continue
            if sa["paused"] or sb["paused"] or sa["idle"] or sb["idle"]:
                continue
            delta = sb["pos"] - sa["pos"]
            if abs(delta - (b - a)) > 0.25 and not excused(b):
                pos_jumps.append({"t": round(b, 3), "slot": slot, "file": sa["file"], "delta": round(delta, 3)})

    # Overlap = both tones present; power sum relative to steady state.
    a_env, b_env = env["xf-a.wav"], env["xf-b.wav"]
    overlap = (a_env > 0.005) & (b_env > 0.005)
    result = {"case": case, "fade": fade, "events": events, "gaps": [[round(a, 3), round(b, 3)] for a, b in gaps],
              "loudness_jumps": jumps, "position_jumps": pos_jumps[:20]}
    steady = AMP ** 2
    if overlap.any():
        idx = np.where(overlap)[0]
        start, end = tau[idx[0]], tau[idx[-1]]
        power = (a_env[idx] ** 2 + b_env[idx] ** 2) / steady
        power_db = 10 * np.log10(np.maximum(power, 1e-9))
        mid = idx[len(idx) // 2]
        mid_window = int(tau[mid] / WINDOW)
        result.update({
            "overlap_start": round(float(start), 3),
            "overlap_seconds": round(float(end - start), 3),
            "power_min_db": round(float(power_db.min()), 2),
            "power_max_db": round(float(power_db.max()), 2),
            "mid_tone_a": round(float(tones["xf-a.wav"][min(mid_window, len(centers) - 1)]), 4),
            "mid_tone_b": round(float(tones["xf-b.wav"][min(mid_window, len(centers) - 1)]), 4),
        })
    else:
        result.update({"overlap_seconds": 0})

    # Verdict per case.
    checks = {}
    real_gaps = [g for g in gaps if g[1] - g[0] > 0.06]
    if case in ("fade3", "fade10"):
        checks["no_gap"] = not real_gaps
        checks["no_jump"] = not jumps and not pos_jumps
        checks["overlap_length_ok"] = abs(result.get("overlap_seconds", 0) - fade) < 0.6
        checks["both_tones_audible_mid_fade"] = result.get("mid_tone_a", 0) > 0.05 and result.get("mid_tone_b", 0) > 0.05
        checks["equal_power_within_1_5_db"] = result.get("power_min_db", -99) > -1.5 and result.get("power_max_db", 99) < 1.5
    elif case == "skip":
        after = [g for g in real_gaps if g[0] > next((t for t, n in events if n == "skip"), 0)]
        checks["skip_happened"] = any(n == "skip" for _, n in events)
        checks["no_long_silence_after_skip"] = all(b - a < 1.0 for a, b in after)
        checks["no_unexpected_jump"] = not jumps
        checks["old_and_faded_song_gone_after_skip"] = bool(
            np.all(env["xf-a.wav"][int((next((t for t, n in events if n == "skip"), 0) + 0.5) * RATE):] < 0.005))
    elif case == "pause":
        checks["pause_happened"] = any(n == "pause" for _, n in events)
        resume = next((t for t, n in events if n == "resume"), None)
        if resume is not None:
            k = int((resume + 1.0) / WINDOW)
            checks["audio_after_resume"] = bool(k < len(rms_db) and rms_db[k] > SILENCE_DB)
        checks["no_gap_outside_pause"] = not real_gaps
        checks["no_unexpected_jump"] = not jumps
    elif case == "off":
        checks["no_overlap"] = result.get("overlap_seconds", 0) == 0
        checks["song_change_gap_below_1s"] = all(b - a < 1.0 for a, b in real_gaps)
        result["song_change_gap"] = round(max((b - a for a, b in real_gaps), default=0), 3)
    result["checks"] = checks
    result["passed"] = all(checks.values())

    plot(out / f"crossfade-{case}.png", case, fade, tau, env, centers, rms_db, tones, times, samples, events, result)
    return result


def plot(path, case, fade, tau, env, centers, rms_db, tones, times, samples, events, result):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(4, 1, figsize=(12, 11), sharex=True)
    colors = {"xf-a.wav": "#d0605e", "xf-b.wav": "#4c8bd6", "xf-c.wav": "#58a55c"}
    names = {"xf-a.wav": "Song A 440 Hz", "xf-b.wav": "Song B 660 Hz", "xf-c.wav": "Song C 880 Hz"}

    ax = axes[0]
    step = max(1, len(tau) // 4000)
    for f in FREQ:
        if env[f].any():
            ax.plot(tau[::step], env[f][::step], color=colors[f], label=names[f])
    total = np.sqrt(sum(e ** 2 for e in env.values()))
    ax.plot(tau[::step], total[::step], color="black", linestyle="--", linewidth=1, label="Leistungssumme (√Σa²)")
    ax.set_ylabel("Amplitude")
    ax.set_title(f"Crossfade-Messung „{case}“ (Fade {fade:g} s) — {'BESTANDEN' if result['passed'] else 'NICHT BESTANDEN'}")
    ax.legend(loc="upper right", fontsize=8)

    ax = axes[1]
    for f in FREQ:
        if any(tones[f]):
            ax.plot(centers, tones[f], color=colors[f], label=f"Goertzel {names[f]}")
    ax.set_ylabel("Ton-Amplitude")
    ax.legend(loc="upper right", fontsize=8)

    ax = axes[2]
    ax.plot(centers, rms_db, color="#444")
    ax.axhline(SILENCE_DB, color="#999", linestyle=":", label="Stille-Schwelle")
    ax.set_ylabel("RMS (dBFS)")
    ax.set_ylim(-60, 0)
    for a, b in result["gaps"]:
        ax.axvspan(a, b, color="red", alpha=0.25)
    ax.legend(loc="lower right", fontsize=8)

    ax = axes[3]
    for slot in ("A", "B"):
        xs, ys = [], []
        for t in times:
            s = samples[t].get(slot)
            if s and s["file"] in FREQ and not s["idle"]:
                xs.append(t)
                ys.append(s["pos"])
            else:
                xs.append(t)
                ys.append(float("nan"))
        ax.plot(xs, ys, label=f"mpv {slot} Position", linewidth=1.2)
    ax.set_ylabel("Position (s)")
    ax.set_xlabel("Messzeit (s)")
    ax.legend(loc="upper left", fontsize=8)

    for t, name in events:
        for a in axes:
            a.axvline(t, color="purple", linestyle="--", linewidth=0.8)
        axes[0].text(t, axes[0].get_ylim()[1] * 0.95, name, color="purple", fontsize=8)
    checks = "\n".join(f"{'✓' if ok else '✗'} {k}" for k, ok in result["checks"].items())
    axes[2].text(0.01, 0.05, checks, transform=axes[2].transAxes, fontsize=8, va="bottom",
                 bbox=dict(facecolor="white", alpha=0.8, edgecolor="#ccc"))
    fig.tight_layout()
    fig.savefig(path, dpi=110)
    plt.close(fig)


def main():
    case_dir, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for case in ("fade3", "fade10", "skip", "pause", "off"):
        if not (case_dir / f"crossfade-{case}.csv").exists():
            results.append({"case": case, "passed": False, "error": "no measurement (app did not finish)"})
            continue
        try:
            results.append(analyze(case_dir, out, case))
        except Exception as error:  # keep the other cases
            results.append({"case": case, "passed": False, "error": repr(error)})
    (out / "crossfade-results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False))
    print("| Fall | Ergebnis | Überlappung | Leistung min/max | Lücken | Details |")
    print("|---|---|---|---|---|---|")
    for r in results:
        detail = r.get("error") or ", ".join(k for k, ok in r.get("checks", {}).items() if not ok) or "–"
        power = f"{r['power_min_db']} / {r['power_max_db']} dB" if "power_min_db" in r else "–"
        print(f"| {r['case']} | {'✅' if r['passed'] else '❌'} | {r.get('overlap_seconds', '–')} s | {power} | "
              f"{len(r.get('gaps', []))} | {detail} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
