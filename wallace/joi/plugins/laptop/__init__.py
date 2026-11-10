"""Named tools for the laptop: music, volume, links, timers, eyes on the
screen and the clipboard, reading aloud, notes, and laptop settings.

A small model calls one plainly named tool per job much more reliably than it
writes shell commands.
"""

import base64
import json
import os
import re
import shutil
import subprocess
import time
import urllib.request


def _run(*cmd):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    return p.returncode, (p.stdout or p.stderr).strip()


def _session(*cmd):
    # A transient user unit gets the desktop session's environment (Wayland,
    # D-Bus), which the gateway, started before Sway, lacks. Its PATH is the
    # session's though, so the commands go by their full path from ours.
    return _run("systemd-run", "--user", "--collect", "--quiet", *cmd)


STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi")


def _event(name):
    # Her face in the bar reacts to these
    try:
        with open(os.path.join(STATE, "event"), "w") as f:
            f.write(name)
    except OSError:
        pass


def _activity(what):
    try:
        with open(os.path.join(STATE, "activity"), "w") as f:
            f.write(what)
    except OSError:
        pass


def _ok(**fields):
    return json.dumps({"ok": True, **fields})


def _err(msg):
    _event("oops")
    return json.dumps({"ok": False, "error": msg})


def _player(cmd, done):
    def handler(args, **kwargs):
        try:
            code, out = _run("playerctl", cmd)
            return _ok(done=done) if code == 0 else _err(out or "no player is open")
        except Exception as e:
            return _err(str(e))
    return handler


def now_playing(args, **kwargs):
    try:
        code, out = _run("playerctl", "metadata", "--format", "{{artist}} - {{title}} ({{status}})")
        return _ok(now_playing=out) if code == 0 else _err("nothing is playing")
    except Exception as e:
        return _err(str(e))


def volume(args, **kwargs):
    change = str(args.get("change", "")).strip()
    sink = "@DEFAULT_AUDIO_SINK@"
    try:
        if change == "mute":
            _run("wpctl", "set-mute", sink, "toggle")
        elif change in ("up", "down"):
            _run("wpctl", "set-volume", "-l", "1.0", sink, "10%+" if change == "up" else "10%-")
        elif change.rstrip("%").isdigit():
            _run("wpctl", "set-volume", "-l", "1.0", sink, change.rstrip("%") + "%")
        elif change != "get":
            return _err(f"unknown change {change!r}")
        # "Volume: 0.45 [MUTED]" becomes "45%, muted"
        _, out = _run("wpctl", "get-volume", sink)
        parts = out.split()
        level = f"{round(float(parts[1]) * 100)}%" if len(parts) > 1 else out
        return _ok(volume=level + (", muted" if "MUTED" in out else ""))
    except Exception as e:
        return _err(str(e))


def open_link(args, **kwargs):
    url = args.get("url", "").strip()
    if not url.startswith(("http://", "https://")):
        url = "https://" + url
    try:
        code, out = _session(shutil.which("xdg-open"), url)
        return _ok(opened=url) if code == 0 else _err(out)
    except Exception as e:
        return _err(str(e))


def remind(args, **kwargs):
    text = args.get("text", "").strip() or "timer"
    try:
        minutes = float(args.get("minutes", 0))
    except (TypeError, ValueError):
        return _err("minutes must be a number")
    if minutes <= 0:
        return _err("minutes must be more than 0")
    try:
        # Named joi-timer-*, so timers() can find and cancel it. It rings even if she's asleep.
        code, out = _session(f"--on-active={round(minutes * 60)}s",
                             f"--unit=joi-timer-{int(time.time() * 1000)}", f"--description={text}",
                             _ctx.get_config("ring_command"), text)
        return _ok(timer=text, in_minutes=minutes) if code == 0 else _err(out)
    except Exception as e:
        return _err(str(e))


def _timers():
    _, out = _run("systemctl", "--user", "list-timers", "--all", "--output=json", "joi-timer-*")
    found = []
    for t in json.loads(out or "[]"):
        _, text = _run("systemctl", "--user", "show", "-P", "Description", t["unit"])
        left = max(0, t["next"] / 1e6 - time.time()) if t.get("next") else 0
        found.append({"unit": t["unit"], "text": text, "minutes_left": round(left / 60, 1)})
    return found


def timers(args, **kwargs):
    cancel = str(args.get("cancel", "")).strip().lower()
    try:
        found = _timers()
        if not cancel:
            return _ok(timers=found)
        gone = [t for t in found if cancel in ("all", "everything") or cancel in t["text"].lower()]
        if not gone and len(found) == 1:
            gone = found  # "cancel the timer" when there's only one
        if not gone:
            return _err(f"no timer matches {cancel!r}")
        for t in gone:
            _run("systemctl", "--user", "stop", t["unit"])
        return _ok(cancelled=[t["text"] for t in gone])
    except Exception as e:
        return _err(str(e))


def _sway(*cmd):
    # Run by Sway itself, so an app she opens belongs to the desktop and outlives the call
    p = subprocess.run(["swaymsg", "exec", " ".join(cmd)], env=_desktop_env(),
                       capture_output=True, text=True, timeout=10)
    return p.returncode, (p.stdout or p.stderr).strip()


def read_aloud(args, **kwargs):
    if os.path.exists(_ctx.get_config("muted_file")):
        return _err("you're muted, so you can't read it out; K can unmute you first")
    sources = {"selection": ["--primary"], "clipboard": []}
    first = str(args.get("from", "selection")).strip().lower()
    order = [first] + [s for s in sources if s != first] if first in sources else list(sources)
    env = _desktop_env()
    try:
        for source in order:
            p = subprocess.run(["wl-paste", "--no-newline", "--type", "text", *sources[source]],
                               env=env, capture_output=True, text=True, timeout=5)
            text = p.stdout.strip() if p.returncode == 0 else ""
            if text:
                break
        else:
            return _err("nothing is selected or copied")
        # The bubble reads it out after her reply
        with open(os.path.join(STATE, "read-next"), "w") as f:
            f.write(text[:5000])
        return _ok(reading=text[:80] + ("…" if len(text) > 80 else ""), source=source,
                   words=len(text.split()), cut=len(text) > 5000,
                   note="It's read out right after your reply, so reply in a few words.")
    except Exception as e:
        return _err(str(e))


def do_not_disturb(args, **kwargs):
    turn = str(args.get("turn", "on")).strip().lower()
    swaync = shutil.which("swaync-client")
    try:
        # A new request replaces any planned switch-off
        _run("systemctl", "--user", "stop", "joi-dnd-off.timer")
        if turn == "off":
            code, out = _run(swaync, "-df")
            return _ok(do_not_disturb="off") if code == 0 else _err(out)
        code, out = _run(swaync, "-dn")
        if code != 0:
            return _err(out)
        minutes = float(args.get("minutes") or 0)
        if minutes > 0:
            _session(f"--on-active={round(minutes * 60)}s", "--unit=joi-dnd-off", swaync, "-df")
            return _ok(do_not_disturb="on", for_minutes=minutes)
        return _ok(do_not_disturb="on", until="K turns it off")
    except Exception as e:
        return _err(str(e))


def _read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def _duration(hours):
    h, m = divmod(round(hours * 60), 60)
    return f"{h}h {m}m" if h else f"{m}m"


def battery(args, **kwargs):
    want = str(args.get("charge", "")).strip().lower()
    run = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    try:
        bat = next(os.path.join("/sys/class/power_supply", n)
                   for n in sorted(os.listdir("/sys/class/power_supply")) if n.startswith("BAT"))
        percent = int(_read(f"{bat}/capacity", "0"))
        status = _read(f"{bat}/status").lower()
        now, full = int(_read(f"{bat}/charge_now", "0")), int(_read(f"{bat}/charge_full", "0"))
        current = int(_read(f"{bat}/current_now", "0"))
        # The bar's LIM button keeps the last limit it set here; every boot starts at 80
        limit = int(_read(os.path.join(run, "charge-limit"), "80"))
        target = {"full": 100, "100": 100, "normal": 80, "limit": 80, "80": 80}.get(want)
        if target and target != limit:
            command = _ctx.get_config("charge_command")
            if not command:
                return _err("this laptop has no way to change the charge limit set up")
            code, out = _session(command, "toggle")
            if code != 0:
                return _err(out or "couldn't change the charge limit")
            limit = target
        info = {"percent": percent, "state": status, "charges_to": f"{limit}%"}
        if current > 0 and status == "discharging":
            info["time_left"] = _duration(now / current)
        elif current > 0 and status == "charging":
            info["time_to_limit"] = _duration(max(0, full * limit / 100 - now) / current)
        return _ok(**info)
    except Exception as e:
        return _err(str(e))


def screen_brightness(args, **kwargs):
    change = str(args.get("change", "get")).strip().lower()
    tool = [shutil.which("brightnessctl"), "--class=backlight"]
    try:
        if change in ("up", "down"):
            _run(*tool, "set", "10%+" if change == "up" else "10%-")
        elif change.rstrip("%").isdigit():
            _run(*tool, "set", str(max(1, int(change.rstrip("%")))) + "%")
        elif change != "get":
            return _err(f"unknown change {change!r}")
        # "intel_backlight,backlight,57600,30%,192000"
        _, out = _run(*tool, "-m")
        return _ok(brightness=out.split(",")[3] if out.count(",") >= 3 else out)
    except Exception as e:
        return _err(str(e))


def power_mode(args, **kwargs):
    mode = str(args.get("mode", "get")).strip().lower()
    try:
        if mode != "get":
            code, out = _run("powerprofilesctl", "set", mode)
            if code != 0:
                return _err(out or f"couldn't switch to {mode}")
        _, now = _run("powerprofilesctl", "get")
        return _ok(power_mode=now)
    except Exception as e:
        return _err(str(e))


def _notes():
    path = _ctx.get_config("notes_file")
    text = _read(path)
    return path, text.splitlines() if text else ["# Notes", ""]


def _save_notes(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def add_note(args, **kwargs):
    text = " ".join(str(args.get("text", "")).split())
    # She sometimes passes K's whole sentence: "note that I need…", "add eggs to my list"
    text = re.sub(r"^(please )?(note( down)? that|note down|note|add|put)\s+", "", text, flags=re.I)
    text = re.sub(r"\s+(to|on) (my|the) (to-?do )?(list|notes)$", "", text, flags=re.I)
    if not text:
        return _err("say what to note")
    try:
        path, lines = _notes()
        lines.append(f"- [ ] {text} ({time.strftime('%b %-d')})")
        _save_notes(path, lines)
        return _ok(noted=text)
    except Exception as e:
        return _err(str(e))


def read_notes(args, **kwargs):
    try:
        _, lines = _notes()
        notes = [l[6:] for l in lines if l.startswith("- [ ] ")]
        return _ok(notes=notes[-30:], total=len(notes))
    except Exception as e:
        return _err(str(e))


def cross_off(args, **kwargs):
    query = str(args.get("text", "")).strip().lower()
    words = set(query.split())
    try:
        path, lines = _notes()
        open_notes = [i for i, l in enumerate(lines) if l.startswith("- [ ] ")]

        # "called the landlord" crosses off "call the landlord": the note sharing most words
        def score(i):
            note = lines[i][6:].lower()
            return 2 * len(words) if query in note else len(words & set(note.split()))

        best = max(open_notes, key=score, default=None)
        if best is None or score(best) * 2 < len(words):
            return _err(f"no note matches {query!r}")
        lines[best] = "- [x] " + lines[best][6:]
        _save_notes(path, lines)
        return _ok(crossed_off=lines[best][6:])
    except Exception as e:
        return _err(str(e))


def lock_screen(args, **kwargs):
    code, out = _sway(_ctx.get_config("lock_command"))
    return _ok(locked=True) if code == 0 else _err(out or "couldn't lock")


def _apps():
    home = os.path.expanduser("~")
    folders = [f"{home}/.local/share/applications", f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share/applications",
               f"{home}/.nix-profile/share/applications", "/run/current-system/sw/share/applications",
               f"{home}/.local/share/flatpak/exports/share/applications", "/var/lib/flatpak/exports/share/applications"]
    apps = {}
    for folder in folders:
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".desktop") or name in apps:
                continue
            entry = {}
            for line in _read(os.path.join(folder, name)).splitlines():
                if line.startswith("[") and line != "[Desktop Entry]":
                    break  # only the main section, before the actions
                key, _, value = line.partition("=")
                entry.setdefault(key.strip(), value.strip())
            if entry.get("Type") == "Application" and "true" not in (entry.get("NoDisplay"), entry.get("Hidden")):
                apps[name] = entry.get("Name", name)
    return apps


def open_app(args, **kwargs):
    want = str(args.get("name", "")).strip().lower()
    if not want:
        return _err("say which app")
    try:
        apps = _apps()

        def rank(item):
            app_id, name = item[0].lower().removesuffix(".desktop"), item[1].lower()
            if want in (name, app_id):
                return 0
            if name.startswith(want):
                return 1
            return 2 if want in name or want in app_id else 3

        found = sorted(apps.items(), key=lambda item: (rank(item), len(item[1])))
        if not found or rank(found[0]) == 3:
            return _err(f"no app called {want!r}")
        app_id, name = found[0]
        code, out = _sway(shutil.which("gtk-launch"), app_id.removesuffix(".desktop"))
        return _ok(opened=name) if code == 0 else _err(out or f"couldn't open {name}")
    except Exception as e:
        return _err(str(e))


def _desktop_env():
    # Sway's session variables, which the gateway, started before Sway, lacks
    env = dict(os.environ)
    out = subprocess.run(["systemctl", "--user", "show-environment"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        key, _, value = line.partition("=")
        if key in ("WAYLAND_DISPLAY", "SWAYSOCK", "XDG_RUNTIME_DIR"):
            env[key] = value
    return env


def _see(image, mime, question):
    # Ask the same local model, with its vision part, about the picture
    body = {
        "messages": [
            {"role": "system", "content": "This is a picture from K's laptop: a window, or something "
             "K copied. Say what it shows and answer the question in two or three sentences. "
             "Quote text exactly when it matters."},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {
                    "url": f"data:{mime};base64," + base64.b64encode(image).decode()}},
                {"type": "text", "text": question or "What is this?"}]},
        ],
        "max_tokens": 200,
    }
    url = _ctx.get_config("model_url", "http://127.0.0.1:8091/v1/chat/completions")
    req = urllib.request.Request(url, json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    _activity("looking")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)["choices"][0]["message"]["content"]
    finally:
        _activity("thinking")


def _focused_window(tree):
    if tree.get("focused") and tree.get("type") == "con":
        return tree
    for child in tree.get("nodes", []) + tree.get("floating_nodes", []):
        found = _focused_window(child)
        if found:
            return found
    return None


def look_at_screen(args, **kwargs):
    question = str(args.get("question", "")).strip()
    env = _desktop_env()
    try:
        tree = json.loads(subprocess.run(["swaymsg", "-t", "get_tree"], env=env,
                                         capture_output=True, text=True).stdout)
        window = _focused_window(tree)
        # The focused window, or the whole screen when nothing is focused
        cmd = ["grim", "-t", "jpeg", "-q", "85"]
        if window:
            r = window["rect"]
            cmd += ["-g", f"{r['x']},{r['y']} {r['width']}x{r['height']}"]
        shot = subprocess.run(cmd + ["-"], env=env, capture_output=True, timeout=10)
        if shot.returncode != 0:
            return _err(shot.stderr.decode().strip() or "couldn't take a screenshot")
        return _ok(window=(window or {}).get("name") or "the screen",
                   seen=_see(shot.stdout, "image/jpeg", question))
    except Exception as e:
        return _err(str(e))


def look_at_clipboard(args, **kwargs):
    question = str(args.get("question", "")).strip()
    env = _desktop_env()
    try:
        types = subprocess.run(["wl-paste", "--list-types"], env=env,
                               capture_output=True, text=True, timeout=5).stdout.split()
        image = next((t for t in types if t in ("image/png", "image/jpeg")), None)
        if image:
            data = subprocess.run(["wl-paste", "--type", image], env=env,
                                  capture_output=True, timeout=10).stdout
            return _ok(kind="image", seen=_see(data, image, question))
        if any(t.startswith("text/") or t in ("UTF8_STRING", "STRING") for t in types):
            text = subprocess.run(["wl-paste", "--no-newline"], env=env,
                                  capture_output=True, text=True, timeout=5).stdout
            return _ok(kind="text", text=text[:6000], cut=len(text) > 6000)
        return _err("the clipboard is empty")
    except Exception as e:
        return _err(str(e))


def hand_off(args, **kwargs):
    who = str(args.get("to", "")).strip().lower()
    task = str(args.get("task", "")).strip()
    if who not in ("claude", "darlene"):
        return _err("hand off to claude or darlene")
    if not task:
        return _err("say what the task is")
    # Its own transient unit, so it runs on after this turn and survives the gateway
    code, out = _session(_ctx.get_config("handoff_command"), who, task)
    if code != 0:
        return _err(out or "couldn't start it")
    return _ok(started=f"{who.title()} is working on it in the background; K gets a "
                       "notification when it's done")


def check_handoffs(args, **kwargs):
    folder = _ctx.get_config("handoffs_folder")
    try:
        names = sorted(os.listdir(folder), reverse=True)
    except OSError:
        return _ok(running=[], finished=[])
    running, finished = [], []
    for name in names:
        path = os.path.join(folder, name)
        who = name.rsplit("-", 1)[-1].split(".")[0].title()
        with open(path) as f:
            text = f.read()
        if name.endswith(".running"):
            running.append({"who": who, "task": text})
        elif name.endswith(".md") and len(finished) < 3:
            finished.append({"who": who, "file": path, "answer": text[:1500]})
    return _ok(running=running, finished=finished)


def _myself(setting, *args):
    code, out = _session(_ctx.get_config(setting), *args)
    return _ok(done=True) if code == 0 else _err(out or "couldn't do it")


def mute_yourself(args, **kwargs):
    return _myself("mute_command", "on")


def unmute_yourself(args, **kwargs):
    return _myself("mute_command", "off")


def go_to_sleep(args, **kwargs):
    # Late enough that her goodnight still gets typed and said
    return _myself("power_command_later", "off")


def _guard(session_id="", **kwargs):
    # Warm-up chats on wake only fill the model's cache, so their tool calls never run
    if session_id.startswith("warmup-"):
        return {"action": "block", "message": "Warming up: just reply."}
    # The bubble marks a moment she starts herself; she only says her line then.
    # A fresh mark only, in case a bubble was closed mid-way.
    try:
        if time.time() - os.stat(os.path.join(STATE, "moment")).st_mtime < 120:
            return {"action": "block", "message": "This is a moment: just say your line."}
    except OSError:
        pass
    return None


_ctx = None  # set in register(), for the plugin's settings and the Spotify plugin's tools


def _spotify(tool, args):
    out = json.loads(_ctx.dispatch_tool(tool, args))
    if isinstance(out, dict) and out.get("error"):
        raise RuntimeError(out["error"])
    return out


def _pick(found, query, only):
    def items(kind):
        return [i for i in (found.get(kind + "s") or {}).get("items") or [] if i]

    if only:
        hits = items(only)
        return (only, hits[0]) if hits else None
    artists, tracks, playlists = items("artist"), items("track"), items("playlist")
    # "daft punk" is the artist, "harder better faster stronger" a song
    if artists and artists[0]["name"].lower() == query.lower():
        return "artist", artists[0]
    for kind, hits in (("track", tracks), ("playlist", playlists), ("artist", artists)):
        if hits:
            return kind, hits[0]
    return None


def play_music(args, **kwargs):
    query = str(args.get("query", "")).strip()
    kinds = {"song": "track", "track": "track", "artist": "artist",
             "album": "album", "playlist": "playlist"}
    only = kinds.get(str(args.get("kind", "")).strip().lower())
    if not query:
        return _err("say what to play")
    try:
        found = _spotify("spotify_search", {"query": query, "limit": 3,
                                            "types": [only] if only else ["artist", "track", "playlist"]})
        pick = _pick(found, query, only)
        if not pick:
            return _err(f"couldn't find {query} on Spotify")
        kind, item = pick
        play = {"action": "play"}
        if kind == "track":
            play["uris"] = [item["uri"]]
        else:
            play["context_uri"] = item["uri"]
        try:
            _spotify("spotify_playback", play)
        except RuntimeError:
            # No active player yet: start it on the laptop's Spotify
            devices = _spotify("spotify_devices", {"action": "list"}).get("devices") or []
            if not devices:
                raise
            computer = [d for d in devices if d.get("type") == "Computer"] or devices
            play["device_id"] = computer[0]["id"]
            _spotify("spotify_playback", play)
        by = ", ".join(a["name"] for a in item.get("artists", [])[:2])
        return _ok(playing=f"{item['name']} by {by}" if by else item["name"], kind=kind)
    except Exception as e:
        return _err(str(e))


def _schema(name, description, properties, required):
    return {"name": name, "description": description,
            "parameters": {"type": "object", "properties": properties, "required": required}}


def register(ctx):
    global _ctx
    _ctx = ctx

    def tool(name, description, handler, properties=None, required=()):
        ctx.register_tool(name=name, toolset="laptop", handler=handler,
                          schema=_schema(name, description, properties or {}, list(required)))

    tool("pause_music", "Pause the music.", _player("pause", "paused"))
    tool("resume_music", "Play or resume the music.", _player("play", "playing"))
    tool("next_song", "Skip to the next song.", _player("next", "skipped"))
    tool("previous_song", "Go back to the previous song.", _player("previous", "went back"))
    tool("now_playing", "Tell which song is playing right now.", now_playing)
    tool("play_music", "Play a song, artist, album or playlist on Spotify.", play_music,
         {"query": {"type": "string", "description": "what to play, like 'daft punk' or 'blinding lights'"},
          "kind": {"type": "string", "enum": ["song", "artist", "album", "playlist"],
                   "description": "optional; use playlist for a mood like 'something chill'"}},
         ["query"])
    tool("volume", "Change or read the speaker volume.", volume,
         {"change": {"type": "string",
                     "description": "'up', 'down', 'mute', 'get', or a level like '30%'"}},
         ["change"])
    tool("open_link", "Open a website in the browser.", open_link,
         {"url": {"type": "string"}}, ["url"])
    tool("remind", "Set a timer or a reminder. It rings and shows a notification when the time's up.",
         remind, {"minutes": {"type": "number"},
                  "text": {"type": "string", "description": "what it's for, like 'pasta' or 'call mum'"}},
         ["minutes", "text"])
    tool("timers", "List the timers and reminders, with the time left, or cancel one.", timers,
         {"cancel": {"type": "string", "description": "optional: which one to cancel, or 'all'"}})
    tool("read_aloud", "Read out loud the text K selected or copied, when K says 'read this' or "
         "'read it to me'.", read_aloud,
         {"from": {"type": "string", "enum": ["selection", "clipboard"]}})
    tool("do_not_disturb", "Turn Do Not Disturb on or off, so notifications stay quiet.",
         do_not_disturb, {"turn": {"type": "string", "enum": ["on", "off"]},
                          "minutes": {"type": "number", "description": "optional: switch it off after this long"}},
         ["turn"])
    tool("battery", "Tell the battery level and time left, or change how far it charges.", battery,
         {"charge": {"type": "string", "enum": ["full", "normal"],
                     "description": "optional: 'full' charges to 100%, 'normal' stops at 80%"}})
    tool("screen_brightness", "Change or read the screen brightness.", screen_brightness,
         {"change": {"type": "string", "description": "'up', 'down', 'get', or a level like '40%'"}},
         ["change"])
    tool("power_mode", "Switch or read the power mode.", power_mode,
         {"mode": {"type": "string", "enum": ["power-saver", "balanced", "performance", "get"]}},
         ["mode"])
    tool("add_note", "Write something down on K's notes and to-do list, like 'note that the "
         "plumber called' or 'add milk to my list'.", add_note,
         {"text": {"type": "string"}}, ["text"])
    tool("read_notes", "Read K's notes and to-do list.", read_notes)
    tool("cross_off", "Cross something off K's to-do list once it's done.", cross_off,
         {"text": {"type": "string", "description": "the thing that's done, in K's words"}}, ["text"])
    tool("lock_screen", "Lock the screen.", lock_screen)
    tool("open_app", "Open an app on the laptop, like Spotify or Firefox.", open_app,
         {"name": {"type": "string"}}, ["name"])
    question = {"question": {"type": "string",
                             "description": "what K wants to know, like 'what does this error mean'"}}
    tool("look_at_screen", "Look at the window K is looking at right now.",
         look_at_screen, question, ["question"])
    tool("look_at_clipboard", "Look at what K copied: text, or an image like a screenshot.",
         look_at_clipboard, question, ["question"])
    tool("hand_off", "Hand a bigger job to Claude (research, code, explaining things) or "
         "Darlene (the laptop, NixOS, the terminal). It runs in the background.", hand_off,
         {"to": {"type": "string", "enum": ["claude", "darlene"]},
          "task": {"type": "string", "description": "the whole task, in K's words, with any details"}},
         ["to", "task"])
    tool("check_handoffs", "See which handed-off jobs are still running, and what came back.",
         check_handoffs)
    tool("mute_yourself", "Stop speaking out loud; keep answering in text.", mute_yourself)
    tool("unmute_yourself", "Speak out loud again.", unmute_yourself)
    tool("go_to_sleep", "Switch yourself off for now, after saying goodnight.", go_to_sleep)
    ctx.register_hook("pre_tool_call", _guard)
