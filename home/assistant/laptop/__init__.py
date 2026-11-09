"""Named tools for the laptop: music, volume, links, reminders, and eyes on
the screen and the clipboard.

A small model calls one plainly named tool per job much more reliably than it
writes shell commands.
"""

import base64
import json
import os
import shlex
import shutil
import subprocess
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
    text = args.get("text", "").strip() or "reminder"
    try:
        minutes = float(args.get("minutes", 0))
    except (TypeError, ValueError):
        return _err("minutes must be a number")
    if minutes <= 0:
        return _err("minutes must be more than 0")
    try:
        # Show it, and make her face ring the alarm
        ring = (f"{shutil.which('notify-send')} --app-name=Joi Joi {shlex.quote(text)}; "
                f"echo alarm > {shlex.quote(os.path.join(STATE, 'event'))}")
        code, out = _session(f"--on-active={round(minutes * 60)}s", shutil.which("sh"), "-c", ring)
        return _ok(reminder=text, in_minutes=minutes) if code == 0 else _err(out)
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
    tool("remind", "Show a reminder notification after some minutes.", remind,
         {"minutes": {"type": "number"}, "text": {"type": "string"}}, ["minutes", "text"])
    question = {"question": {"type": "string",
                             "description": "what K wants to know, like 'what does this error mean'"}}
    tool("look_at_screen", "Look at the window K is looking at right now.",
         look_at_screen, question, ["question"])
    tool("look_at_clipboard", "Look at what K copied: text, or an image like a screenshot.",
         look_at_clipboard, question, ["question"])
