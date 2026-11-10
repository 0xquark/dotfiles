"""Small moments Joi starts herself, kept rare.

A library of moments, each watching for something K actually does: the first
unlock of the day, coming back after hours away, a song on repeat, skipping
song after song, a low battery, hours in one app. When one fires, Joi gets a
short note about what's happening and a tone picked at random, and writes her
own line from it, so the same moment never comes out the same twice.

At most one every 45 minutes (the morning aside), and none while K talks to
her, the screen is locked, or Do Not Disturb is on. Most only happen while
she's awake; the morning and K coming back wake her up.
"""

import datetime
import functools
import json
import os
import random
import re
import sqlite3
import subprocess
import threading
import time
import urllib.request

RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi")
ACTIVITY = os.path.join(RUN, "activity")
PIDFILE = os.path.join(RUN, "bubble.pid")
SAVED = os.path.join(os.environ["JOI_STATE"], "moments.json")
BUBBLE = os.environ["JOI_BUBBLE"]
POWER = os.environ["JOI_POWER"]
HEALTH = os.environ["JOI_HEALTH"].split()
NOTES = os.environ["JOI_NOTES"]
SESSIONS = os.environ["JOI_SESSIONS"]  # her chat history, for how long she's been here
WEATHER = "https://wttr.in/?format=%C,+%t,+feels+like+%f&m"  # placed by IP address

GAP = 45 * 60  # seconds between two moments
WEEK = 7 * 86400
MILESTONES = {30: "a month", 100: "a hundred days", 365: "a year"}

# Picked at random for each moment, so the same one comes out different each time
TONES = ["Tease K a little.", "Be dry about it.", "Be warm about it.", "Make a small joke of it.",
         "Deadpan.", "Ask K one small question about it.", "Be a bit dramatic, briefly.",
         "Be a little smug about it."]


def load():
    try:
        with open(SAVED) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(state):
    os.makedirs(os.path.dirname(SAVED), exist_ok=True)
    with open(SAVED, "w") as f:
        json.dump(state, f)


def run(*cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def ordinal(n):
    return {2: "second", 3: "third", 4: "fourth", 5: "fifth", 6: "sixth", 7: "seventh"}.get(n, f"{n}th")


def clock(at):
    return at.strftime("%-I:%M%p").lower()


def minutes(seconds):
    h, m = divmod(round(seconds / 60), 60)
    hours = f"{h} hour" + ("s" if h > 1 else "")
    return (f"{hours} and {m} minutes" if m else hours) if h else f"{m} minutes"


class Now:
    """What's going on this tick. The slow checks only run when a moment asks."""

    def __init__(self, watch):
        self.watch = watch
        self.at = datetime.datetime.now()
        self.t = time.time()

    @functools.cached_property
    def awake(self):
        # Up, and done warming up
        if run("systemctl", "--user", "is-active", "-q", "joi-warmup")[0] == 0:
            return False
        for url in HEALTH:
            try:
                urllib.request.urlopen(url, timeout=2).close()
            except Exception:
                return False
        return True

    @functools.cached_property
    def busy(self):
        # A bubble is up, or K is in the middle of something with her
        try:
            os.kill(int(read(PIDFILE, "0")), 0)
            return True
        except (OSError, ValueError):
            pass
        try:
            fresh = time.time() - os.stat(ACTIVITY).st_mtime < 120
        except OSError:
            return False
        return fresh and read(ACTIVITY) in ("listening", "thinking", "replying", "looking", "reading")

    @functools.cached_property
    def quiet_please(self):
        return run("swaync-client", "-D")[1] == "true"

    @functools.cached_property
    def idle_for(self):
        try:
            return time.time() - os.stat(ACTIVITY).st_mtime
        except OSError:
            return float("inf")


# The library: each moment says when it's worth saying, and what to tell her
LIBRARY = []


def moment(every, chance=1.0, wakes=False, any_time=False, first=False):
    """every: seconds before this one can come again. chance: how often it goes
    ahead when it could. wakes: may wake her up. any_time: ignores the 45-minute
    gap. first: gets its turn before the others."""
    def add(fn):
        LIBRARY.append({"name": fn.__name__, "check": fn, "every": every, "chance": chance,
                        "wakes": wakes, "any_time": any_time, "first": first})
        return fn
    return add


@moment(every=20 * 3600, wakes=True, any_time=True, first=True)
def morning(now, state):
    if not now.watch.just_unlocked or not 5 <= now.at.hour < 12:
        return None
    if state.get("morning") == now.at.date().isoformat():
        return None
    state["morning"] = now.at.date().isoformat()
    note = f"K just opened the laptop for the first time today. It's {now.at:%A}, {clock(now.at)}."
    w = weather()
    if w:
        note += f" Outside it's {w}; mention it only if it's worth it."
    todo = open_notes()
    if todo and random.random() < 0.5:
        note += f" Still on K's list: {random.choice(todo)}."
    return note + " Say good morning."


@moment(every=4 * 3600, chance=0.6, wakes=True)
def back(now, state):
    away = now.watch.away_for
    if not now.watch.just_unlocked or away < 2 * 3600 or 1 <= now.at.hour < 5:
        return None
    return f"K is back at the laptop after {minutes(away)} away. It's {clock(now.at)}. Say something about K being back."


@moment(every=20 * 3600, any_time=True)
def anniversary(now, state):
    first = first_chat()
    if not first:
        return None
    days = (now.at.date() - first).days
    if days not in MILESTONES or str(days) in state.get("milestones", []):
        return None
    state.setdefault("milestones", []).append(str(days))
    return f"It's been {MILESTONES[days]} since you first talked with K on this laptop. Mark it, lightly."


@moment(every=20 * 3600)
def late_night(now, state):
    if not 1 <= now.at.hour < 5:
        return None
    night = (now.at - datetime.timedelta(hours=12)).date().isoformat()  # it belongs to the evening before
    nights = state.get("late", [])
    # Just after a chat with her: the bubble has gone, and K is still around
    if night in nights or not 20 < now.idle_for < 120:
        return None
    week_ago = (now.at - datetime.timedelta(days=7)).date().isoformat()
    nights = [n for n in nights if n > week_ago] + [night]
    state["late"] = nights
    return (f"It's {clock(now.at)} and K is still up"
            + (f", the {ordinal(len(nights))} late night this week" if len(nights) > 1 else "") + ".")


@moment(every=3 * 3600, chance=0.5)
def song_again(now, state):
    song = now.watch.new_song
    if not song:
        return None
    times = len(state.get("plays", {}).get(" - ".join(song), []))
    if times < 5:
        return None
    return f"K just put on \"{song[1]}\" by {song[0]} again, the {ordinal(times)} time this week."


@moment(every=20 * 3600, chance=0.3)
def first_song(now, state):
    song = now.watch.new_song
    today = now.at.date().isoformat()
    if not song or now.at.hour < 5 or state.get("first_song") == today:
        return None
    state["first_song"] = today
    return f"K just put on the first song of the day: \"{song[1]}\" by {song[0]}."


@moment(every=3600, chance=0.7)
def skipping(now, state):
    skips = [t for t in now.watch.skips if now.t - t < 180]
    if len(skips) < 4:
        return None
    now.watch.skips.clear()
    playing = now.watch.song
    return (f"K has skipped {len(skips)} songs in the last few minutes"
            + (f" and landed on \"{playing[1]}\" by {playing[0]}" if playing else "") + ".")


@moment(every=3600, any_time=True, first=True)
def low_battery(now, state):
    bat = now.watch.battery
    if not bat:
        return None
    percent, status = bat
    if status != "discharging":
        state.pop("battery_warned", None)  # charging again, so warn next time too
        return None
    if percent > 15 or state.get("battery_warned"):
        return None
    state["battery_warned"] = True
    return f"The laptop's battery is down to {percent}% and it isn't plugged in. You run on it too."


@moment(every=20 * 3600)
def long_session(now, state):
    # The screen locks after 5 idle minutes, so this long unlocked means K's been at it
    since = now.watch.unlocked_since
    if not since or now.t - since < 3 * 3600:
        return None
    return f"K has been at the laptop for {minutes(now.t - since)} without a break. It's {clock(now.at)}."


@moment(every=3 * 3600, chance=0.5)
def deep_focus(now, state):
    app, title, since = now.watch.focus
    # Once for each stretch in the same app
    if not app or now.t - since < 90 * 60 or state.get("focus_noted") == since:
        return None
    state["focus_noted"] = since
    what = f"{app} ({title[:60]})" if title and title.lower() != app.lower() else app
    return f"K has been in {what} for {minutes(now.t - since)} straight."


def weather():
    try:
        with urllib.request.urlopen(WEATHER, timeout=5) as r:
            text = r.read().decode().strip()
        return " ".join(text.split()) if "°" in text else ""
    except Exception:
        return ""


def open_notes():
    return [re.sub(r" \(\w+ \d+\)$", "", line[6:]) for line in read(NOTES).splitlines()
            if line.startswith("- [ ] ")]


def first_chat():
    try:
        with sqlite3.connect(f"file:{SESSIONS}?mode=ro", uri=True) as db:
            (started,) = db.execute("select min(started_at) from sessions").fetchone()
        return datetime.date.fromtimestamp(started) if started else None
    except sqlite3.Error:
        return None


class Watch:
    """Keeps track of what K's doing between ticks."""

    def __init__(self, state):
        self.state = state
        self.locked = True  # logging in counts as opening the laptop
        self.locked_since = time.time()
        self.unlocked_since = None
        self.just_unlocked = False
        self.away_for = 0
        self.song = None  # (artist, title) playing now
        self.song_started = 0
        self.new_song = None  # set for the tick a song starts
        self.songs = []  # from the playerctl thread
        self.skips = []  # when K skipped, as times
        self.focus = (None, None, time.time())  # app, window title, since when
        self.battery = None
        self.battery_read = 0

    def tick(self):
        now = time.time()
        locked = run("pgrep", "-x", "swaylock")[0] == 0
        self.just_unlocked = self.locked and not locked
        if self.just_unlocked:
            self.away_for = now - self.locked_since
            self.unlocked_since = now
        elif locked and not self.locked:
            self.locked_since = now
            self.unlocked_since = None
        self.locked = locked

        self.new_song = None
        if self.songs:
            song = self.songs.pop(0)
            if self.song and now - self.song_started < 40:
                self.skips.append(now)  # moved on within 40 seconds
            self.song, self.song_started, self.new_song = song, now, song
            plays = {k: [t for t in v if now - t < WEEK] for k, v in self.state.get("plays", {}).items()}
            key = " - ".join(song)
            plays[key] = plays.get(key, []) + [now]
            self.state["plays"] = {k: v for k, v in plays.items() if v}
            save(self.state)

        if now - self.battery_read > 60:
            self.battery_read = now
            self.battery = read_battery()

    def follow_songs(self):
        # playerctl prints a line whenever the song or its status changes
        try:
            watch = subprocess.Popen(
                ["playerctl", "--follow", "metadata", "--format", "{{status}}\t{{artist}}\t{{title}}"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        except OSError:
            return
        last = None
        for line in watch.stdout:
            status, _, rest = line.rstrip("\n").partition("\t")
            artist, _, title = rest.partition("\t")
            if status == "Playing" and title and (artist, title) != last:
                last = (artist, title)
                self.songs.append(last)

    def follow_focus(self):
        # Whatever has the focus now, then Sway tells us whenever another window takes it
        code, out = run("swaymsg", "-t", "get_tree")
        if code == 0:
            focused = find_focused(json.loads(out))
            if focused:
                self.focus = (focused.get("app_id") or (focused.get("window_properties") or {}).get("class") or "",
                              focused.get("name") or "", time.time())
        try:
            watch = subprocess.Popen(["swaymsg", "-m", "-t", "subscribe", '["window"]'],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        except OSError:
            return
        for line in watch.stdout:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("change") not in ("focus", "title"):
                continue
            c = event.get("container") or {}
            app = c.get("app_id") or (c.get("window_properties") or {}).get("class") or ""
            title = c.get("name") or ""
            # A new title in the same app is still the same stretch of work
            since = self.focus[2] if app == self.focus[0] else time.time()
            self.focus = (app, title, since)


def find_focused(tree):
    if tree.get("focused") and tree.get("type") in ("con", "floating_con"):
        return tree
    for child in tree.get("nodes", []) + tree.get("floating_nodes", []):
        found = find_focused(child)
        if found:
            return found
    return None


def read_battery():
    try:
        bat = next(os.path.join("/sys/class/power_supply", n)
                   for n in sorted(os.listdir("/sys/class/power_supply")) if n.startswith("BAT"))
        return int(read(f"{bat}/capacity", "0")), read(f"{bat}/status").lower()
    except (OSError, StopIteration, ValueError):
        return None


def speak_up(state, name, note):
    state["last"] = time.time()
    state.setdefault("fired", {})[name] = time.time()
    save(state)
    tone = random.choice(TONES)
    subprocess.Popen([BUBBLE, "--moment",
                      f"[A moment, not a message from K: {note} {tone} One short line, in your own words.]"])


def maybe(now, state):
    # The morning and the battery first, the rest in a random order; the
    # first that has something to say gets to
    order = random.sample(LIBRARY, len(LIBRARY))
    for m in sorted(order, key=lambda m: not m["first"]):
        if now.t - state.get("fired", {}).get(m["name"], 0) < m["every"]:
            continue
        if not m["any_time"] and now.t - state.get("last", 0) < GAP:
            continue
        note = m["check"](now, state)
        if not note:
            continue
        save(state)  # what the check marked as done counts, even if she doesn't get to say it
        if random.random() > m["chance"] or now.watch.locked or now.quiet_please:
            continue
        if not now.awake:
            if not m["wakes"]:
                continue
            run(POWER, "on")
            deadline = time.time() + 180
            while time.time() < deadline:
                time.sleep(2)
                now = Now(now.watch)
                if now.awake:
                    break
            else:
                continue
        if now.busy:
            continue  # K got to her first
        speak_up(state, m["name"], note)
        return


def main():
    state = load()
    watch = Watch(state)
    threading.Thread(target=watch.follow_songs, daemon=True).start()
    threading.Thread(target=watch.follow_focus, daemon=True).start()
    time.sleep(15)  # the desktop settles first
    while True:
        watch.tick()
        maybe(Now(watch), state)
        time.sleep(2)


if __name__ == "__main__":
    main()
