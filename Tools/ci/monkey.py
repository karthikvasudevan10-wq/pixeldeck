#!/usr/bin/env python3
"""Tries the Mac app by itself: clicks tools, draws, opens panels and menus, and says what crashed.

usage: monkey.py /path/to/PixelDeck.app /path/to/pdinput

Run by the build check when a commit message says [monkey]. Positions are in the app's own points
(a 1281 x 862 window, as the Studio lays itself out), converted to the screen from the window found.
Each phase starts the app afresh. After every action the app is checked; if it has gone, the action
is reported and the app is started again. Crash reports are summarised at the end.
"""
import glob
import json
import os
import subprocess
import sys
import time

APP, INPUT = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
ERRORS = os.path.abspath("monkey-stderr.txt")
ARGS = ["-hasSeenOnboarding", "YES", "-tourOffered", "YES", "-tourCompleted", "YES"]
KEYS = {"a": 0, "s": 1, "d": 2, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "e": 14, "y": 16,
        "1": 18, "2": 19, "3": 20, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "]": 30, "k": 40, "n": 45,
        "m": 46, ",": 43, "space": 49, "esc": 53, "left": 123, "right": 124, "return": 36, "delete": 51}
window = None       # x, y, width, height on screen
crashes = []


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def alive():
    return sh("pgrep", "-x", "PixelDeck") != ""


def find_window():
    out = sh("swift", os.path.join(HERE, "window.swift"), sh("pgrep", "-x", "PixelDeck").split("\n")[0])
    parts = out.split()
    return [int(v) for v in parts[1:5]] if len(parts) == 5 else None


def launch():
    global window
    subprocess.run(["pkill", "-x", "PixelDeck"], capture_output=True)
    time.sleep(1)
    subprocess.run(["open", "-n", "--stderr", ERRORS, APP, "--args"] + ARGS)
    time.sleep(9)
    window = find_window()


def to_screen(x, y):
    scale = window[2] / 1281.0
    return str(round(window[0] + x * scale, 1)), str(round(window[1] + y * scale, 1))


def check(what):
    time.sleep(0.25)
    if alive():
        return True
    tail = sh("tail", "-4", ERRORS)
    print(f"*** CRASH after: {what}\n    {tail}", flush=True)
    crashes.append(what)
    launch()
    return False


def click(x, y, what):
    subprocess.run([INPUT, "click", *to_screen(x, y)])
    return check(f"{what}: click {x},{y}")


def drag(x1, y1, x2, y2, what):
    subprocess.run([INPUT, "drag", *to_screen(x1, y1), *to_screen(x2, y2)])
    return check(f"{what}: drag {x1},{y1} to {x2},{y2}")


def key(name, *mods, what="key"):
    subprocess.run([INPUT, "key", str(KEYS[name]), *mods])
    return check(f"{what}: {'+'.join(mods + (name,))}")


def escape():
    key("esc", what="escape")
    key("esc", what="escape")


def phase(name):
    print(f"--- {name}", flush=True)
    launch()
    if window is None:
        print("    no window found")
        return False
    return True


# Where things are, in the app's points (see EditorView+Desk.swift).
CANVAS = (620, 420)
TOOLS = [("pencil", 152), ("eraser", 194), ("fill", 236), ("shape", 278), ("picker", 320), ("mirror", 362), ("select", 404)]


def stroke(what):
    cx, cy = CANVAS
    drag(cx - 60, cy - 40, cx + 50, cy + 30, what)
    drag(cx + 40, cy - 50, cx - 30, cy + 60, what)
    click(cx + 5, cy + 5, what)


def main():
    print(sh(INPUT, "access"))

    if phase("draw with every tool"):
        stroke("pencil at launch")
        for name, y in TOOLS:
            click(290, y, f"tool rail {name}")
            stroke(f"canvas with {name}")
        key("z", "cmd", what="undo"); key("z", "cmd", what="undo"); key("z", "cmd", "shift", what="redo")

    if phase("keys"):
        for name in ["b", "e", "x", "g", "i", "u", "m", "y", "[", "]", "p", "h", "1", "2", "3"]:
            key(name, what="tool key")
            stroke(f"canvas after key {name}")
        for name in ["n", "n", "left", "right", "space", "space"]:
            key(name, what="frame key")
        key("d", "cmd", what="duplicate frame"); key("c", "cmd", "shift", what="copy frame")
        key("v", "cmd", "shift", what="paste over"); key("v", "cmd", "opt", what="paste as new")
        key("]", "cmd", what="hold longer"); key("[", "cmd", what="hold shorter")
        key("a", "cmd", what="select all"); key("delete", what="delete")
        stroke("canvas after frames")

    if phase("tool options bar"):
        for name, y in [("pencil", 152), ("shape", 278), ("select", 404)]:
            click(290, y, f"tool rail {name}")
            if name == "select":
                drag(560, 380, 680, 460, "make a selection")
            for x in range(300, 960, 26):
                click(x, 83, f"options bar ({name})")
                stroke(f"canvas after options bar ({name}) x={x}")
            escape()

    if phase("inspector"):
        for tab in (1046, 1135, 1224):
            click(tab, 90, "inspector tab")
        for y in range(130, 850, 26):
            for x in (1020, 1075, 1130, 1185, 1245):
                click(x, y, "inspector")
                escape()
        stroke("canvas after inspector")

    if phase("timeline"):
        for x in (800, 880, 950):
            click(x, 756, "timeline chip")
            click(640, 430, "inside the sheet")
            escape()
        for x in (360, 425, 490, 295, 360):
            click(x, 818, "timeline frame")
        stroke("canvas after timeline")
        key("space", what="play"); time.sleep(1.5); key("space", what="pause")

    if phase("toolbar"):
        for x in (112, 200, 923, 967, 1011, 1055, 1105, 1155, 1201, 1247, 1247, 112):
            click(x, 26, "toolbar")
            click(x, 70, "under the toolbar (menu item)")
            escape()
        stroke("canvas after toolbar")

    if phase("menu commands"):
        for name, mods in [("e", ("cmd",)), ("k", ("cmd",)), ("u", ("cmd", "shift")), ("s", ("cmd", "shift")),
                           ("a", ("cmd", "opt")), ("o", ("opt",)), (",", ("cmd",)), ("n", ("cmd", "opt")), ("n", ("cmd",))]:
            key(name, *mods, what="menu shortcut")
            time.sleep(0.8)
            for x, y in ((640, 300), (640, 430), (500, 520), (780, 520), (640, 640)):
                click(x, y, f"inside what {'+'.join(mods + (name,))} opened")
            escape()
        stroke("canvas after menus")

    if phase("sprite list"):
        for y in range(130, 800, 34):
            click(120, y, "sidebar row")
            time.sleep(0.6)
            stroke("canvas after sidebar row")
            escape()
        click(80, 842, "Community")
        time.sleep(2)
        click(640, 400, "inside Community")
        escape()

    subprocess.run(["pkill", "-x", "PixelDeck"], capture_output=True)
    print(f"=== {len(crashes)} crash(es) while trying the app")
    time.sleep(12)        # crash reports are written a little later
    report()
    sys.exit(1 if crashes else 0)


def report():
    seen = set()
    paths = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/PixelDeck*.ips")))
    print(f"=== {len(paths)} crash report(s)")
    for path in paths:
        try:
            text = open(path).read()
            body = json.loads(text[text.index("\n") + 1:])
        except Exception as error:
            print(f"{os.path.basename(path)}: unreadable ({error})")
            continue
        images = body.get("usedImages", [])
        thread = next((t for t in body.get("threads", []) if t.get("triggered")), None)
        frames = []
        for frame in (thread or {}).get("frames", [])[:28]:
            image = images[frame.get("imageIndex", 0)].get("name", "?") if images else "?"
            frames.append(f"{image}  {frame.get('symbol', hex(frame.get('imageOffset', 0)))} +{frame.get('symbolLocation', 0)}")
        ours = next((f for f in frames if f.startswith("PixelDeck")), frames[0] if frames else "")
        signature = (json.dumps(body.get("asi", {}))[:200], ours)
        if signature in seen:
            continue
        seen.add(signature)
        print(f"----- {os.path.basename(path)}")
        print("exception:", json.dumps(body.get("exception", {})))
        print("message:", json.dumps(body.get("asi", {}))[:900])
        demangled = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(frames), capture_output=True, text=True).stdout
        print(demangled or "\n".join(frames))


if __name__ == "__main__":
    main()
