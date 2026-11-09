"""Joi's voice: keeps Kokoro's Heart voice loaded and speaks what it's sent.

It listens on $XDG_RUNTIME_DIR/joi/speaker.sock. A client sends text and
closes its side. Playback starts with the first sentence while the rest is
still being made. A new message cuts the current one off, and an empty one
just hushes her.
Usage: joi-speaker CONFIG MODEL VOICE
"""

import os
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


def speak(text, mine):
    global player
    with lock:
        if mine != turn:
            return
        player = subprocess.Popen(
            ["pw-play", "--raw", "--rate", str(RATE), "--channels", "1",
             "--format", "s16", "--media-role", "Communication", "-"],
            stdin=subprocess.PIPE,
        )
        mine_player = player
    try:
        for _, _, audio in pipeline(text, voice=VOICE, split_pattern=SENTENCES):
            if mine != turn:
                break
            if audio is None:
                continue
            pcm = (np.clip(audio.numpy(), -1, 1) * 32767).astype(np.int16)
            mine_player.stdin.write(pcm.tobytes())
            mine_player.stdin.flush()
        mine_player.stdin.close()
        mine_player.wait()
    except (BrokenPipeError, ValueError):
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
        with conn:
            data = b""
            while chunk := conn.recv(4096):
                data += chunk
        text = data.decode("utf-8", "replace").strip()
        with lock:
            turn += 1
            hush()
        if text:
            threading.Thread(target=speak, args=(text, turn), daemon=True).start()


serve()
