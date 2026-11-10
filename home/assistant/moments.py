"""Small moments Joi starts herself, kept rare.

morning     the first unlock of the day after 5am: good morning, maybe the
            weather. Wakes her up if she's asleep.
late night  K still up between 1 and 5am, just after a chat with her, once a night
songs       a song K played five times this week comes on again, sometimes

Each one is a line from her in the bubble, from a short note about what's
happening. At most one every 45 minutes, besides the morning, and none while
K talks to her, the screen is locked, or Do Not Disturb is on.
"""

import datetime
import json
import os
import random
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
WEATHER = "https://wttr.in/?format=%C,+%t,+feels+like+%f&m"  # placed by IP address

GAP = 45 * 60  # seconds between two moments
SONG_GAP = 3 * 3600  # between two about songs
WEEK = 7 * 86400
SONG_PLAYS = 5  # plays in a week before a song counts as played a lot


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


def awake():
    # Up, and done warming up
    if run("systemctl", "--user", "is-active", "-q", "joi-warmup")[0] == 0:
        return False
    for url in HEALTH:
        try:
            urllib.request.urlopen(url, timeout=2).close()
        except Exception:
            return False
    return True


def locked():
    return run("pgrep", "-x", "swaylock")[0] == 0


def quiet_please():
    return run("swaync-client", "-D")[1] == "true"


def busy():
    # A bubble is up, or K is in the middle of something with her
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), 0)
        return True
    except (OSError, ValueError):
        pass
    try:
        with open(ACTIVITY) as f:
            what = f.read().strip()
        fresh = time.time() - os.stat(ACTIVITY).st_mtime < 120
        return fresh and what in ("listening", "thinking", "replying", "looking", "reading")
    except OSError:
        return False


def idle_for():
    try:
        return time.time() - os.stat(ACTIVITY).st_mtime
    except OSError:
        return float("inf")


def weather():
    try:
        with urllib.request.urlopen(WEATHER, timeout=5) as r:
            text = r.read().decode().strip()
        return " ".join(text.split()) if "°" in text else ""
    except Exception:
        return ""


def speak_up(state, note):
    state["last"] = time.time()
    save(state)
    subprocess.Popen([BUBBLE, "--moment", f"[A moment, not a message from K: {note}]"])


def clock():
    return datetime.datetime.now().strftime("%-I:%M%p").lower()


def morning(state):
    now = datetime.datetime.now()
    today = now.date().isoformat()
    if state.get("morning") == today or not 5 <= now.hour < 12:
        return
    state["morning"] = today  # once a day, even if it doesn't work out
    save(state)
    if quiet_please():
        return
    if not awake():
        run(POWER, "on")
        deadline = time.time() + 180
        while not awake() and time.time() < deadline:
            time.sleep(2)
    if busy() or locked() or not awake():
        return  # K got to her first, or went away again
    w = weather()
    speak_up(state, f"K just opened the laptop for the first time today. It's {now:%A}, {clock()}."
                    + (f" Outside it's {w}." if w else "")
                    + " Say good morning to K in one short line, in your own words."
                    + (" Mention the weather only if it's worth mentioning." if w else ""))


def late_night(state):
    now = datetime.datetime.now()
    if not 1 <= now.hour < 5:
        return
    night = (now - datetime.timedelta(hours=12)).date().isoformat()  # it belongs to the evening before
    nights = state.get("late", [])
    if night in nights or time.time() - state.get("last", 0) < GAP:
        return
    # Just after a chat with her: the bubble has gone, and K is still around
    if not 20 < idle_for() < 120 or busy() or locked() or not awake() or quiet_please():
        return
    week_ago = (now - datetime.timedelta(days=7)).date().isoformat()
    nights = [n for n in nights if n > week_ago] + [night]
    state["late"] = nights
    count = len(nights)
    speak_up(state, f"it's {clock()} and K is still up"
                    + (f", the {ordinal(count)} late night this week" if count > 1 else "")
                    + ". Say one short line about it, in your own words.")


def ordinal(n):
    return {2: "second", 3: "third", 4: "fourth", 5: "fifth", 6: "sixth", 7: "seventh"}.get(n, f"{n}th")


def follow_songs(found):
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
            found.append(last)


def playing_now():
    return run("playerctl", "metadata", "--format", "{{status}}\t{{artist}}\t{{title}}")[1]


def count_play(state, song):
    now = time.time()
    plays = {k: [t for t in v if now - t < WEEK] for k, v in state.get("plays", {}).items()}
    key = " - ".join(song)
    plays[key] = plays.get(key, []) + [now]
    state["plays"] = {k: v for k, v in plays.items() if v}
    save(state)
    return len(plays[key])


def song_moment(state, song, times):
    now = time.time()
    if now - state.get("last", 0) < GAP or now - state.get("song", 0) < SONG_GAP:
        return
    if random.random() < 0.5 or busy() or locked() or not awake() or quiet_please():
        return
    # Still on after a few seconds, so K didn't skip it
    time.sleep(8)
    if playing_now() != "Playing\t" + "\t".join(song):
        return
    state["song"] = now
    artist, title = song
    speak_up(state, f"K just put on \"{title}\"" + (f" by {artist}" if artist else "")
                    + f" again, the {ordinal(times)} time this week."
                    + " React in one short line, in your own words.")


def main():
    state = load()
    songs = []
    threading.Thread(target=follow_songs, args=(songs,), daemon=True).start()
    # Logging in counts as opening the laptop, once the desktop is up
    time.sleep(15)
    was_locked = True
    while True:
        is_locked = locked()
        if was_locked and not is_locked:
            morning(state)
        was_locked = is_locked
        late_night(state)
        while songs:
            song = songs.pop(0)
            times = count_play(state, song)
            if times >= SONG_PLAYS:
                song_moment(state, song, times)
        time.sleep(2)


main()
