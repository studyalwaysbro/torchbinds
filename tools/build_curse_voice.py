#!/usr/bin/env python3
"""Record the curse caller's lines: python3 tools/build_curse_voice.py

Borrows the take, check and treatment code from the Godslayer voice builder, with its Frostbite
voice. Each line is tried until the service's own transcription matches the words, then written
to Sounds/curse/<clip>.ogg. Needs ELEVENLABS_API_KEY, ffmpeg and ffprobe.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.expanduser("~/projects/godslayer/tools"))
import build_voice as bv  # noqa: E402

OUT = os.path.join(HERE, "..", "Sounds", "curse")
PACK = {"id": "torchcurse", "voice": "cgSgspJ2msm6clMCkdW9", "pitch": 1.03, "speed": 1.07, "hall": "tight", "bass": 2,
        "delivery": {"points": {"tag": "[urgent, sharp] ", "stability": 0.5}, "aside": {"tag": "[playful, pleased] ", "stability": 0.5}}}
LINES = {
    "self1": ("points", "Curse on you!"),
    "self2": ("points", "You're cursed! Get it off!"),
    "self3": ("points", "That curse is yours!"),
    "one1": ("points", "Curse in the party!"),
    "one2": ("points", "Someone's cursed. Decurse!"),
    "one3": ("points", "Curse! Clean it up!"),
    "many1": ("points", "Curses everywhere! Start scrubbing!"),
    "many2": ("points", "So many curses! Go, go, go!"),
    "still1": ("aside", "Still cursed."),
    "still2": ("aside", "That curse is still there."),
    "still3": ("aside", "Curse is still up."),
    "clean1": ("aside", "All clean."),
    "clean2": ("aside", "Spotless. Lovely."),
    "clean3": ("aside", "Curses gone. Good."),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for clip, (kind, text) in LINES.items():
        best = None
        for attempt in range(bv.ATTEMPTS):
            info = bv.take(PACK, clip, kind, text, attempt)
            if best is None or info["score"] > best["score"]:
                best = info
            if info["good"]:
                best = info
                break
        seconds = bv.treat(best["path"], os.path.join(OUT, clip + ".ogg"), kind, PACK)
        bad += 0 if best["good"] else 1
        print("%-7s %s %.1fs  heard: %s" % (clip, "ok  " if best["good"] else "WEAK", seconds, best["heard"]))
    print("%d clips, %d weak" % (len(LINES), bad))


if __name__ == "__main__":
    main()
