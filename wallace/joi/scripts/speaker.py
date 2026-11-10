"""Joi's voice: keeps Kokoro's Heart voice loaded and speaks what it's sent.

It listens on $XDG_RUNTIME_DIR/joi/speaker.sock. A client sends text and
closes its side, all at once or a bit at a time while a reply is still being
written. Each sentence is spoken as soon as it's complete. A new connection
cuts the current one off, and an empty one just hushes her.
Usage: joi-speaker CONFIG MODEL VOICE
"""

import codecs
import os
import re
import socket
import subprocess
import sys
import threading

import numpy as np
from kokoro import KModel, KPipeline

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi", "speaker.sock")
REPO = "hexgrad/Kokoro-82M"
RATE = 24000
SENTENCES = r"(?<=[.!?])\s+"  # one sentence at a time, so she starts sooner

config, weights, VOICE = sys.argv[1:4]
pipeline = KPipeline(lang_code="a", repo_id=REPO,
                     model=KModel(repo_id=REPO, config=config, model=weights).eval())
# The first run is slow, so get it out of the way before anyone's listening
for _ in pipeline("Hi.", voice=VOICE):
    pass

lock = threading.Lock()
turn = 0  # bumped by every message, so an older one stops speaking
player = None


def hush():
    if player and player.poll() is None:
        player.kill()


def start_player(mine):
    global player
    with lock:
        if mine != turn:
            return None
        player = subprocess.Popen(
            ["pw-play", "--raw", "--rate", str(RATE), "--channels", "1",
             "--format", "s16", "--media-role", "Communication", "-"],
            stdin=subprocess.PIPE,
        )
        return player


def speak(sentence, mine, out):
    # Returns False once a newer message has taken over
    for _, _, audio in pipeline(sentence, voice=VOICE, split_pattern=None):
        if mine != turn:
            return False
        if audio is None:
            continue
        pcm = (np.clip(audio.numpy(), -1, 1) * 32767).astype(np.int16)
        out.stdin.write(pcm.tobytes())
        out.stdin.flush()
    return mine == turn


def listen(conn, mine):
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    text = ""
    out = None
    try:
        with conn:
            while True:
                chunk = conn.recv(4096)
                text += decoder.decode(chunk, final=not chunk)
                parts = re.split(SENTENCES, text)
                # The last part may still be growing, until the client is done
                ready, text = (parts, "") if not chunk else (parts[:-1], parts[-1])
                for sentence in filter(str.strip, ready):
                    out = out or start_player(mine)
                    if not out or not speak(sentence.strip(), mine, out):
                        return
                if not chunk:
                    break
        if out:
            out.stdin.close()
            out.wait()
    except (BrokenPipeError, ValueError, OSError):
        pass


def serve():
    global turn
    os.makedirs(os.path.dirname(SOCK), exist_ok=True)
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK)
    os.chmod(SOCK, 0o600)
    server.listen()
    while True:
        conn, _ = server.accept()
        # Whoever connects now has the floor
        with lock:
            turn += 1
            hush()
            mine = turn
        threading.Thread(target=listen, args=(conn, mine), daemon=True).start()


serve()
