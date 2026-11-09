r"""Joi's face in the bar, printed as waybar JSON whenever it changes.

Every frame is 7 characters wide, a slot on each side of the face, so the face
keeps still while z's, notes and sparkles come and go around it.

asleep      (-‿-)z, breathing out z's
waking      (-_-) (˘_˘) (◔_◔) (◕_◕), then a stretch \(◕‿◕)/
awake       (◕‿◕), blinking, with a wink, a glance or a smile now and then
music       bobbing side to side with a note while something plays
listening   (◕o◕) (◕O◕)
thinking    (◔_◔)…
replying    talking, then a happy ⋆(^‿^)⋆ when she's done
switched off: a yawn, then asleep
"""

import json
import os
import random
import subprocess
import sys
import time
import urllib.request

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi")
ACTIVITY = os.path.join(STATE, "activity")
HEALTH = os.environ["JOI_HEALTH"].split()
STALE = 120  # seconds before an unfinished listening or thinking counts as over
NOTE = "\U000f075a"  # a music note from the Nerd Font, one character wide

# Looping animations: frames and how long each one shows, in seconds
LOOPS = {
    "asleep": ([" (-‿-) ", " (-‿-)z", " (-‿-)Z"], [1.4, 0.7, 0.7]),
    "waking": ([" (-_-) ", " (˘_˘) ", " (◔_◔) ", " (◕_◕) "], [0.35] * 4),
    "music": ([NOTE + "(◕‿◕) ", " (◕‿◕)" + NOTE], [0.5, 0.5]),
    "listening": ([" (◕o◕) ", " (◕O◕) "], [0.3, 0.3]),
    "thinking": ([" (◔_◔) ", " (◔_◔)·", " (◔_◔)…"], [0.35] * 3),
}
TALK = [" (◕▿◕) ", " (◕‿◕) ", " (◕o◕) "]

# One-off moments: (frame, seconds) steps, and the class they show with
STRETCH = ([("\\(◕‿◕)/", 1.4)], "happy")
HAPPY = ([("⋆(^‿^)⋆", 1.6)], "happy")
YAWN = ([(" (◕o◕) ", 0.4), (" (-o-) ", 0.8)], "asleep")
BLINK = ([(" (-‿-) ", 0.14)], "awake")
QUIRKS = [
    ([(" (◕‿-) ", 0.6)], "awake"),  # wink
    ([(" (◔‿◔) ", 0.9), (" (◕‿◕) ", 0.2), (" (◔‿◔) ", 0.6)], "awake"),  # glance up
    ([(" (◕ω◕) ", 1.2)], "awake"),  # cute
    ([(" (˘‿˘) ", 1.5)], "awake"),  # content
]

TIPS = {
    "asleep": "Joi is asleep. Click to wake her.",
    "waking": "Joi is waking up…",
    "awake": "Joi is here. Hold Hyper+Space to talk. Click to put her to sleep.",
    "music": "Joi is listening to your music. Hold Hyper+Space to talk.",
    "listening": "Joi is listening",
    "thinking": "Joi is thinking",
    "replying": "Joi is replying",
    "happy": "Joi is here. Hold Hyper+Space to talk.",
}


def running():
    out = subprocess.run(["systemctl", "--user", "is-active", "hermes-agent", "llama-server"],
                         capture_output=True, text=True).stdout.split()
    return out == ["active", "active"]


def healthy():
    for url in HEALTH:
        try:
            urllib.request.urlopen(url, timeout=1).close()
        except Exception:
            return False
    return True


def music_playing():
    out = subprocess.run(["playerctl", "--all-players", "status"],
                         capture_output=True, text=True).stdout.split()
    return "Playing" in out


def activity():
    try:
        st = os.stat(ACTIVITY)
        with open(ACTIVITY) as f:
            what = f.read().strip()
    except OSError:
        return None
    if what in ("listening", "thinking", "replying") and time.time() - st.st_mtime < STALE:
        return what
    return None


def loop_frame(name, t):
    frames, times = LOOPS[name]
    t %= sum(times)
    for frame, length in zip(frames, times):
        if t < length:
            return frame
        t -= length
    return frames[-1]


class Face:
    def __init__(self):
        self.power = "asleep"  # asleep, waking or awake, from the services
        self.music = False
        self.shown = None  # the state shown last tick, to spot transitions
        self.moment = None  # (steps, class, started)
        now = time.monotonic()
        self.next_blink = now + 3
        self.next_quirk = now + random.uniform(20, 40)

    def play(self, moment, now):
        self.moment = (moment[0], moment[1], now)

    def check_services(self):
        if not running():
            self.power = "asleep"
        elif self.power != "awake":
            self.power = "awake" if healthy() else "waking"
        self.music = self.power == "awake" and music_playing()

    def frame(self, now):
        state = self.power
        if state == "awake":
            state = activity() or ("music" if self.music else "awake")

        # Transitions get their own little moment
        before, self.shown = self.shown, state
        if before is not None and before != state:
            if state == "asleep" and before not in ("asleep", "waking"):
                self.play(YAWN, now)
            elif before in ("asleep", "waking") and state in ("awake", "music"):
                self.play(STRETCH, now)
            elif before == "replying" and state in ("awake", "music"):
                self.play(HAPPY, now)
            elif self.moment and self.moment[1] != "asleep":
                self.moment = None  # new activity cuts a quirk short

        if self.moment:
            steps, cls, started = self.moment
            t = now - started
            for frame, length in steps:
                if t < length:
                    return frame, cls
                t -= length
            self.moment = None

        if state == "awake":
            if now > self.next_quirk:
                self.next_quirk = now + random.uniform(25, 60)
                self.play(random.choice(QUIRKS), now)
                return self.frame(now)
            if now > self.next_blink:
                self.next_blink = now + random.uniform(3, 7)
                self.play(BLINK, now)
                return self.frame(now)
            return " (◕‿◕) ", "awake"
        if state == "replying":
            # A new mouth shape every 120ms, picked at random so it looks like talking
            return random.Random(int(now / 0.12)).choice(TALK), "replying"
        return loop_frame(state, now), state


def main():
    face = Face()
    last = None
    checked = 0.0
    while True:
        now = time.monotonic()
        if now - checked > 1:
            checked = now
            face.check_services()
        text, cls = face.frame(now)
        out = json.dumps({"text": text, "tooltip": TIPS[cls], "class": cls})
        if out != last:
            print(out, flush=True)
            last = out
        time.sleep(0.05)


try:
    main()
except (BrokenPipeError, KeyboardInterrupt):
    sys.exit(0)
