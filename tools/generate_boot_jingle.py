#!/usr/bin/env python3
"""Generate the original PegineLab ~7 s 8-bit-style boot jingle.

No third-party packages are required. Output is mono 8-bit PCM WAV at 11025 Hz.
The melody is original and intentionally does not reproduce a known game tune.
"""
import math
import random
import wave
from pathlib import Path

SR = 11025
DURATION = 7.0
OUT = Path(__file__).resolve().parents[1] / "web" / "assets" / "boot-jingle.wav"

NOTES = {
    "C5": 523.25, "D5": 587.33, "E5": 659.25, "G5": 783.99,
    "A5": 880.00, "C6": 1046.50, "D6": 1174.66, "E6": 1318.51,
    "G6": 1567.98,
}

EVENTS = [
    (0.00,.14,"C5",.42),(0.16,.14,"E5",.42),(0.32,.14,"G5",.42),(0.48,.22,"C6",.48),
    (0.88,.14,"D5",.40),(1.04,.14,"G5",.40),(1.20,.14,"A5",.40),(1.36,.24,"D6",.48),
    (1.72,.10,"E5",.34),(1.84,.10,"G5",.34),(1.96,.10,"C6",.34),(2.08,.28,"E6",.50),
    (2.48,.12,"C6",.36),(2.62,.12,"A5",.36),(2.76,.12,"G5",.36),(2.90,.30,"C6",.48),
    (3.36,.10,"C5",.34),(3.48,.10,"D5",.34),(3.60,.10,"E5",.34),(3.72,.10,"G5",.36),
    (3.84,.10,"A5",.36),(3.96,.22,"C6",.48),(4.32,.11,"E6",.38),(4.45,.11,"D6",.38),
    (4.58,.11,"C6",.38),(4.71,.28,"G5",.46),(5.12,.10,"G5",.33),(5.24,.10,"A5",.33),
    (5.36,.10,"C6",.35),(5.48,.10,"D6",.35),(5.60,.10,"E6",.38),(5.72,.34,"G6",.50),
    (6.12,.12,"E6",.34),(6.26,.12,"C6",.34),(6.40,.42,"C6",.48),
]

def main():
    n = int(SR * DURATION)
    s = [0.0] * n
    for start, dur, note, amp in EVENTS:
        freq = NOTES[note]
        i0, i1 = int(start * SR), min(n, int((start + dur) * SR))
        for i in range(i0, i1):
            t = (i - i0) / SR
            rel = (i - i0) / max(1, i1 - i0)
            env = min(1.0, t / .008) * min(1.0, (1 - rel) / .12)
            sq = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
            sq2 = 1.0 if math.sin(4 * math.pi * freq * t) >= 0 else -1.0
            s[i] += amp * env * (.82 * sq + .18 * sq2)

    random.seed(23)
    for start, dur, amp in [(0.0,.045,.12),(6.86,.05,.08)]:
        for i in range(int(start*SR), min(n, int((start+dur)*SR))):
            s[i] += amp * (1 if random.random() > .5 else -1)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1); w.setsampwidth(1); w.setframerate(SR)
        w.writeframes(bytes(int(128 + max(-.95, min(.95, x))*120) & 0xff for x in s))
    print(OUT)

if __name__ == "__main__":
    main()
