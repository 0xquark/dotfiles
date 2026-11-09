"""Runs a job Joi handed off, in the background, and tells K when it's done.

Usage: joi-handoff claude|darlene "the task"

The answer goes to ~/.local/state/joi/handoffs/<time>-<who>.md. While it runs,
<time>-<who>.running holds the task, so Joi and her face can see it. When it's
done, K gets a notification, Joi's face reacts, and Joi says who's finished.
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
import uuid

WHO, TASK = sys.argv[1], sys.argv[2]
NAMES = {"claude": "Claude", "darlene": "Darlene"}
HANDOFFS = os.path.join(os.environ["JOI_STATE"], "handoffs")
RUN = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "joi")
LIMIT = 15 * 60  # seconds a job may take

# Both work in the background with nobody watching, and the task came through
# speech-to-text, so they look and report instead of changing things
BRIEF = ("Joi, K's assistant, handed you this task. K isn't watching, so investigate and "
         "report back: don't change files, settings or the system. Finish with a short "
         "answer K can read in a notification, then the details.\n\nTask: ")


def claude():
    out = subprocess.run(
        [os.environ["JOI_CLAUDE"], "-p", BRIEF + TASK, "--output-format", "text",
         # Reading, searching and the web only; anything else is refused without asking
         "--permission-mode", "default",
         "--allowedTools", "Read", "Grep", "Glob", "WebSearch", "WebFetch",
         "--disallowedTools", "Edit", "Write", "NotebookEdit", "Bash"],
        capture_output=True, text=True, timeout=LIMIT, cwd=os.path.expanduser("~"))
    return (out.stdout or out.stderr).strip()


def darlene():
    with open(os.environ["JOI_KEY_FILE"]) as f:
        key = next(l.split("=", 1)[1].strip() for l in f if l.startswith("API_SERVER_KEY="))
    req = urllib.request.Request(
        os.environ["JOI_DARLENE_URL"],
        json.dumps({"model": "darlene", "messages": [{"role": "user", "content": BRIEF + TASK}]}).encode(),
        {"Content-Type": "application/json", "Authorization": "Bearer " + key,
         "X-Hermes-Session-Id": f"handoff-{uuid.uuid4().hex[:12]}"})
    with urllib.request.urlopen(req, timeout=LIMIT) as r:
        return json.load(r)["choices"][0]["message"]["content"].strip()


def tell(name, answer, path):
    # The first paragraph, without markdown, fits a notification
    first = answer.split("\n\n", 1)[0].replace("**", "").replace("`", "").strip()
    first = first if len(first) < 280 else first[:277] + "…"
    subprocess.run(["notify-send", "--app-name=Joi", f"{name} is done", f"{first}\n\n{path}"])
    try:
        with open(os.path.join(RUN, "event"), "w") as f:
            f.write("handoff")
    except OSError:
        pass
    if not os.path.exists(os.environ["JOI_MUTED_FILE"]):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(os.path.join(RUN, "speaker.sock"))
                s.sendall(f"K, {name} is done.".encode())
        except OSError:
            pass


def main():
    os.makedirs(HANDOFFS, exist_ok=True)
    stamp = time.strftime("%Y-%m-%d-%H%M%S")
    running = os.path.join(HANDOFFS, f"{stamp}-{WHO}.running")
    result = os.path.join(HANDOFFS, f"{stamp}-{WHO}.md")
    with open(running, "w") as f:
        f.write(TASK)
    name = NAMES[WHO]
    try:
        answer = (claude if WHO == "claude" else darlene)() or "(no answer)"
    except Exception as e:
        answer = f"It didn't work: {e}"
    with open(result, "w") as f:
        f.write(f"# {name}: {TASK}\n\n{answer}\n")
    os.remove(running)
    tell(name, answer, result)


main()
