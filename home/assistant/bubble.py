"""A chat bubble above Joi's corner of the bar.

It shows typing dots while Joi thinks, then types her reply out with small
pauses after commas and sentences, then fades. The reply streams in, so she
starts typing and speaking with her first sentence. Click it to close it early and hush her.
Usage: joi-bubble "what you said", joi-bubble --type to type to her first, or
joi-bubble --moment "what's happening" when she speaks up by herself
"""

import json
import os
import random
import re
import signal
import socket
import sys
import threading
import time
import urllib.request
import uuid

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

URL = os.environ["JOI_URL"]
HEALTH = os.environ["JOI_HEALTH"].split()
KEY_FILE = os.environ["JOI_KEY_FILE"]
STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi")
SESSION = os.path.join(STATE, "conversation.json")
ACTIVITY = os.path.join(STATE, "activity")  # read by the face in the bar
PIDFILE = os.path.join(STATE, "bubble.pid")
SPEAKER = os.path.join(STATE, "speaker.sock")
MUTED = os.environ["JOI_MUTED_FILE"]  # she only types while this exists
MOMENT = os.path.join(STATE, "moment")  # her tools stay off while she says a moment's line
READ_NEXT = os.path.join(STATE, "read-next")  # text her read_aloud tool left to read out
FRESH = 30 * 60  # seconds a conversation stays open between questions
WIDTH = 48  # characters per line, at most
BOTTOM = 38  # clears the pill rising out of the bar
RISE = 10  # pixels the bubble slides up as it appears

SENTENCE_END = re.compile(r"(?<=[.!?])\s+|\n+")
EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️‍]")


def read_activity():
    try:
        with open(ACTIVITY) as f:
            return f.read().strip()
    except OSError:
        return ""


def set_activity(what):
    try:
        with open(ACTIVITY, "w") as f:
            f.write(what)
    except OSError:
        pass


class Voice:
    """One reply's voice: each sentence goes to joi-speaker as soon as it's ready."""

    def __init__(self):
        self.sock = None
        self.off = os.path.exists(MUTED)

    def send(self, text):
        if self.off or not text:
            return
        try:
            if not self.sock:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(SPEAKER)
            self.sock.sendall((text + " ").encode())
        except OSError:
            self.off = True  # no voice running, the bubble is enough

    def done(self):
        if self.sock:
            self.sock.close()


def hush():
    # A connection with nothing in it stops her
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(SPEAKER)
    except OSError:
        pass


def humanize(text):
    # The model slips into assistant habits now and then
    text = re.sub(r"\s*[—–]\s*", ", ", text)
    text = re.sub(r"[*_`#]+", "", text)
    text = EMOJI.sub("", text)
    return re.sub(r"\s+", " ", text).strip(" ,")


def conversation():
    # Hermes keeps the history; a fresh id after a quiet spell starts a new chat
    try:
        with open(SESSION) as f:
            saved = json.load(f)
        if time.time() - saved["at"] < FRESH:
            return saved["id"]
    except (OSError, ValueError, KeyError):
        pass
    return f"joi-{uuid.uuid4().hex[:12]}"


def touch_conversation(session_id):
    with open(SESSION, "w") as f:
        json.dump({"at": time.time(), "id": session_id}, f)


def api_key():
    with open(KEY_FILE) as f:
        for line in f:
            if line.startswith("API_SERVER_KEY="):
                return line.split("=", 1)[1].strip()
    raise RuntimeError("no API_SERVER_KEY")


def forget_moment():
    try:
        os.remove(MOMENT)
    except OSError:
        pass


def take_reading():
    # Only a fresh one: an old file is from a chat in the terminal
    try:
        fresh = time.time() - os.stat(READ_NEXT).st_mtime < 120
        with open(READ_NEXT) as f:
            text = f.read()
        os.remove(READ_NEXT)
        return text if fresh else ""
    except OSError:
        return ""


def awake():
    for url in HEALTH:
        try:
            urllib.request.urlopen(url, timeout=2).close()
        except Exception:
            return False
    return True


def ask(said, moment=False):
    """Her reply, in pieces as the model writes it."""
    # A moment goes into the same conversation, so K can answer her
    session_id = conversation()
    req = urllib.request.Request(
        URL,
        json.dumps({"model": "joi", "stream": True,
                    "messages": [{"role": "user", "content": said}]}).encode(),
        {"Content-Type": "application/json", "Authorization": "Bearer " + api_key(),
         "X-Hermes-Session-Id": session_id},
    )
    if moment:
        open(MOMENT, "w").close()
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            for line in r:
                line = line.decode("utf-8", "replace").strip()
                if not line.startswith("data: {"):
                    continue  # keepalives, the end marker
                # Tool progress events come through too; they have no choices
                for choice in json.loads(line[6:]).get("choices") or []:
                    if choice.get("finish_reason") == "error":
                        raise RuntimeError("the model failed")
                    piece = (choice.get("delta") or {}).get("content")
                    if piece:
                        yield piece
    finally:
        if moment:
            forget_moment()
    touch_conversation(session_id)


class Bubble:
    def __init__(self, said, moment=False):
        self.moment = moment
        self.win = Gtk.Window()
        self.win.set_app_paintable(True)
        self.win.set_visual(self.win.get_screen().get_rgba_visual())
        GtkLayerShell.init_for_window(self.win)
        GtkLayerShell.set_namespace(self.win, "joi")
        GtkLayerShell.set_layer(self.win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(self.win, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self.win, GtkLayerShell.Edge.RIGHT, 10)
        GtkLayerShell.set_margin(self.win, GtkLayerShell.Edge.BOTTOM, BOTTOM - RISE)

        css = Gtk.CssProvider()
        css.load_from_data(f"""
            window {{ background: transparent; }}
            .bubble {{
                background: {os.environ["JOI_BG"]};
                border: 1px solid {os.environ["JOI_BORDER"]};
                border-radius: 8px;
                padding: 7px 12px;
            }}
            .said {{ color: {os.environ["JOI_DIM"]}; font-size: 0.85em; }}
            .reply {{ color: {os.environ["JOI_FG"]}; }}
            entry {{
                background: transparent;
                border: none;
                box-shadow: none;
                padding: 0;
                min-height: 0;
                color: {os.environ["JOI_FG"]};
                caret-color: {os.environ["JOI_FG"]};
            }}
        """.encode())
        Gtk.StyleContext.add_provider_for_screen(
            self.win.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        box.get_style_context().add_class("bubble")
        self.said = self._label("said", "" if moment else said or "")
        self.reply = self._label("reply", "")
        box.pack_start(self.said, False, False, 0)
        box.pack_start(self.reply, False, False, 0)

        # Typing to her: a text box first, and the keyboard while it's open
        self.entry = None
        if said is None:
            self.entry = Gtk.Entry()
            self.entry.set_width_chars(36)
            self.entry.connect("activate", self.submit)
            self.entry.connect("key-press-event", self.on_key)
            box.pack_start(self.entry, False, False, 0)
            GtkLayerShell.set_keyboard_mode(self.win, GtkLayerShell.KeyboardMode.EXCLUSIVE)

        events = Gtk.EventBox()
        events.add(box)
        events.connect("button-press-event", self.close)
        self.win.add(events)
        self.win.set_opacity(0)
        self.win.show_all()

        self.text = None
        self.shown = 0
        self.finished = False  # the whole reply is in
        self.waiting = False  # typing caught up and waits for the next sentence
        self.dots = 0
        self.note = ""
        self.appear = 0.0
        GLib.timeout_add(16, self.slide_in)
        if self.entry:
            hint = "to Joi · Enter sends, Esc cancels"
            self.said.set_text(hint)
            self.said.set_width_chars(len(hint))
            self.reply.hide()
            self.entry.grab_focus()
            set_activity("reading")
        else:
            if moment:
                self.said.hide()  # she starts it, so there's nothing K said
            self.start(said)

    def start(self, said):
        self.started = time.monotonic()
        GLib.timeout_add(350, self.tick_dots)
        set_activity("thinking")
        threading.Thread(target=self.fetch, args=(said,), daemon=True).start()

    def submit(self, entry):
        said = entry.get_text().strip()
        if not said:
            self.close()
            return
        # The typed text becomes the dim line, like a spoken question
        entry.hide()
        GtkLayerShell.set_keyboard_mode(self.win, GtkLayerShell.KeyboardMode.NONE)
        self.said.set_text(said)
        self.said.set_width_chars(min(len(said), WIDTH))
        self.said.show()
        self.reply.show()
        self.start(said)

    def on_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def _label(self, cls, text):
        label = Gtk.Label(label=text, xalign=0)
        label.set_line_wrap(True)
        label.set_width_chars(min(len(text), WIDTH))
        label.set_max_width_chars(WIDTH)
        label.get_style_context().add_class(cls)
        return label

    def slide_in(self):
        # Fade in while sliding up out of the pill
        self.appear = min(1.0, self.appear + 0.09)
        ease = 1 - (1 - self.appear) ** 3
        self.win.set_opacity(ease)
        GtkLayerShell.set_margin(self.win, GtkLayerShell.Edge.BOTTOM, BOTTOM - RISE + round(RISE * ease))
        return self.appear < 1.0

    def fetch(self, said):
        voice = Voice()
        got = False
        try:
            if not awake():
                self.note = "waking up "
                deadline = time.monotonic() + 120
                while not awake() and time.monotonic() < deadline:
                    time.sleep(1)
                self.note = ""
            # Whole sentences go out as they finish; the last one when the reply's done
            rest = ""
            for piece in ask(said, self.moment):
                *done, rest = SENTENCE_END.split(rest + piece)
                for sentence in filter(None, map(humanize, done)):
                    got = True
                    voice.send(sentence)
                    GLib.idle_add(self.more, sentence)
            for sentence in filter(None, [humanize(rest)]):
                got = True
                voice.send(sentence)
                GLib.idle_add(self.more, sentence)
            # What she was asked to read follows her reply, in the same breath
            voice.send(take_reading())
        except Exception:
            if not got and not self.moment:
                got = True
                GLib.idle_add(self.more, "can't reach my head right now, is Joi switched on?")
        finally:
            voice.done()
        if not got:
            if self.moment:
                GLib.idle_add(Gtk.main_quit)  # a moment that comes to nothing just doesn't happen
                return
            GLib.idle_add(self.more, "...")
        GLib.idle_add(self.finish)

    def tick_dots(self):
        if self.text is not None:
            return False
        self.dots = self.dots % 3 + 1
        note = self.note or ("looking " if read_activity() == "looking" else "")
        self.reply.set_text(note + "•" * self.dots)
        return True

    def more(self, sentence):
        first = self.text is None
        self.text = sentence if first else f"{self.text} {sentence}"
        # The bubble grows a sentence at a time, so it keeps still while typing
        self.reply.set_width_chars(min(len(self.text), WIDTH))
        if first:
            set_activity("replying")
            self.reply.set_text("")
            # Typing dots for a moment at least, like someone reading first
            wait = max(0, 0.7 - (time.monotonic() - self.started))
            GLib.timeout_add(int(wait * 1000), self.type_next)
        elif self.waiting:
            self.waiting = False
            self.type_next()
        return False

    def finish(self):
        self.finished = True
        if self.waiting:
            self.waiting = False
            self.type_next()
        return False

    def close(self, *_):
        hush()
        Gtk.main_quit()

    def type_next(self):
        if self.shown >= len(self.text):
            if not self.finished:
                self.waiting = True  # more() picks it up again
                return False
            set_activity("ready")
            # Long enough to read it, then fade
            GLib.timeout_add(int(2500 + 55 * len(self.text)), self.fade)
            return False
        self.shown += 1
        self.reply.set_text(self.text[:self.shown])
        ch = self.text[self.shown - 1]
        delay = random.uniform(18, 38)
        if ch == ",":
            delay += 160
        elif ch in ".?!" and self.text[self.shown:self.shown + 1] == " ":
            delay += 380
        GLib.timeout_add(int(delay), self.type_next)
        return False

    def fade(self):
        opacity = self.win.get_opacity() - 0.1
        if opacity <= 0:
            Gtk.main_quit()
            return False
        self.win.set_opacity(opacity)
        GLib.timeout_add(30, self.fade)
        return False


def main():
    os.makedirs(STATE, exist_ok=True)
    # One bubble at a time: a new question replaces the last answer
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), signal.SIGTERM)
    except (OSError, ValueError):
        pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    signal.signal(signal.SIGTERM, lambda *_: os._exit(0))
    args = sys.argv[1:]
    if args[:1] == ["--moment"]:
        Bubble(" ".join(args[1:]), moment=True)
    else:
        forget_moment()  # K is talking now, so her tools are back
        Bubble(None if args == ["--type"] else " ".join(args))
    try:
        Gtk.main()
    finally:
        set_activity("ready")


main()
