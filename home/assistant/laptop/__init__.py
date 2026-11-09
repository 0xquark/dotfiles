"""Named tools for the laptop: music, volume, links and reminders.

A small model calls one plainly named tool per job much more reliably than it
writes shell commands.
"""

import json
import subprocess


def _run(*cmd):
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    return p.returncode, (p.stdout or p.stderr).strip()


def _session(*cmd):
    # A transient user unit gets the desktop session's environment (Wayland,
    # D-Bus), which the gateway, started before Sway, lacks.
    return _run("systemd-run", "--user", "--collect", "--quiet", *cmd)


def _ok(**fields):
    return json.dumps({"ok": True, **fields})


def _err(msg):
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
        code, out = _session("xdg-open", url)
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
        code, out = _session(f"--on-active={round(minutes * 60)}s",
                             "notify-send", "--app-name=Joi", "Joi", text)
        return _ok(reminder=text, in_minutes=minutes) if code == 0 else _err(out)
    except Exception as e:
        return _err(str(e))


_ctx = None  # set in register(), for calling the Spotify plugin's tools


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
