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
KEYS = {"a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "e": 14, "y": 16,
        "1": 18, "2": 19, "3": 20, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "]": 30, "k": 40, "n": 45,
        "m": 46, ",": 43, "space": 49, "esc": 53, "left": 123, "right": 124, "return": 36, "delete": 51}
window = None       # x, y, width, height on screen
crashes = []
reported = set()    # crash reports already summarised
signatures = set()
STARTED = time.time()
LIMIT = 16 * 60     # seconds: stop trying after this, so the summary is always printed


class Enough(Exception):
    pass


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout.strip()


def alive():
    return sh("pgrep", "-x", "PixelDeck") != ""


def find_window():
    out = sh("swift", os.path.join(HERE, "window.swift"), sh("pgrep", "-x", "PixelDeck").split("\n")[0])
    parts = out.split()
    return [int(v) for v in parts[1:5]] if len(parts) == 5 else None


extra = []          # more arguments for the app, for the phase being run


def launch():
    global window
    subprocess.run(["pkill", "-x", "PixelDeck"], capture_output=True)
    time.sleep(1)
    subprocess.run(["open", "-n", "--stderr", ERRORS, APP, "--args"] + ARGS + extra)
    time.sleep(8)
    # The window opens in the same place every time: look for it once.
    window = window or find_window()


def to_screen(x, y):
    scale = 0.77        # the Mac shows the app's points at 77%
    return str(round(window[0] + x * scale, 1)), str(round(window[1] + y * scale, 1))


def check(what):
    time.sleep(0.25)
    if alive():
        return True
    tail = sh("tail", "-3", ERRORS)
    print(f"*** CRASH after: {what}\n    {tail}", flush=True)
    # What the system said about it (a crash report isn't written when the system stops the app).
    said = sh("log", "show", "--last", "15s", "--style", "compact", "--predicate",
              'process == "PixelDeck" AND (messageType == error OR messageType == fault)')
    for line in said.split("\n")[-14:]:
        print("    log:", line[:280], flush=True)
    crashes.append(what)
    time.sleep(5)         # the crash report is written a little later
    report()
    if len(crashes) >= int(os.environ.get("MONKEY_MAX_CRASHES", "14")) or time.time() - STARTED > LIMIT:
        raise Enough()
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


def look(what):
    """With MONKEY_LOOK set: describes the window as text (Tools/ci/describe.py), to see what is showing."""
    if not os.environ.get("MONKEY_LOOK") or not alive():
        return
    out = sh("swift", os.path.join(HERE, "window.swift"), sh("pgrep", "-x", "PixelDeck").split("\n")[0]).split()
    if len(out) != 5:
        return
    subprocess.run(["screencapture", "-x", "-o", "-l" + out[0], "look.png"])
    subprocess.run(["sips", "-s", "format", "bmp", "look.png", "--out", "look.bmp"], capture_output=True)
    print(f"--- the window {what}")
    print(sh("python3", os.path.join(HERE, "describe.py"), "look.bmp", "12"), flush=True)


ONLY = [p for p in os.environ.get("MONKEY_ONLY", "").split(",") if p]


def phase(name, *arguments):
    """Starts the app afresh for a phase (with more arguments for the app, if given)."""
    global extra
    if ONLY and not any(word in name for word in ONLY):
        return False
    extra = list(arguments)
    if time.time() - STARTED > LIMIT:
        raise Enough()
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
    try:
        trial()
    except Enough:
        print("=== stopping early: enough crashes, or out of time")
    subprocess.run(["pkill", "-x", "PixelDeck"], capture_output=True)
    print(f"=== {len(crashes)} crash(es) while trying the app")
    for what in crashes:
        print("   ", what)
    time.sleep(8)
    report()
    sys.exit(1 if crashes else 0)


def trial():

    if phase("draw with every tool"):
        stroke("pencil at launch")
        for name, y in TOOLS:
            click(290, y, f"tool rail {name}")
            stroke(f"canvas with {name}")
        key("z", "cmd", what="undo"); key("z", "cmd", what="undo"); key("z", "cmd", "shift", what="redo")
        look("after drawing with every tool")

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

    # Whole screens opened from the menu bar: click all over each one.
    for name, mods, title in [("e", ("cmd",), "export screen"), (",", ("cmd",), "settings screen"),
                              ("n", ("cmd", "opt"), "new canvas screen"), ("k", ("cmd",), "palettes screen"),
                              ("u", ("cmd", "shift"), "adjust colours screen"), ("s", ("cmd", "shift"), "stamps screen")]:
        if phase(title):
            key(name, *mods, what=f"open the {title}")
            time.sleep(1.2)
            look(f"showing the {title}")
            for y in range(120, 800, 56):
                for x in range(330, 980, 72):
                    click(x, y, title)
            escape()
            stroke(f"canvas after the {title}")

    # Whole-window screens the app opens by itself when asked to (debug builds: -monkeyOpen).
    for what in ("photo", "playground", "academy", "movies"):
        if phase(f"opened {what} screen", "-monkeyOpen", what):
            time.sleep(3)
            look(f"showing the {what} screen")
            # From the foot of the window up, so the Back and Close buttons along the top come last.
            for y in range(826, 100, -48):
                for x in range(1250, 30, -86):
                    click(x, y, f"{what} screen")
                if what == "playground":
                    for name in ("right", "right", "space", "left", "space"):
                        key(name, what="playing")
            drag(560, 380, 700, 470, f"{what} screen")
            look(f"after clicking all over the {what} screen")
            for x in range(1250, 30, -86):
                click(x, 70, f"top of the {what} screen")
            escape()

    # A whole movie made into a video by the app itself (three scenes and a sound).
    if phase("movie export", "-monkeyOpen", "movieExport"):
        said = ""
        for _ in range(30):
            time.sleep(3)
            said = sh("grep", "-h", "PD-MOVIE", ERRORS,
                      os.path.expanduser("~/Library/Containers/karthikvasudevan.pixeldeck/Data/tmp/pd-movie-test.txt"))
            if said or not alive():
                break
        print(said or "PD-MOVIE nothing reported", flush=True)
        check("making a movie into a video")

    # An assistant drawing through the bridge the app gives the Claude app (Tools/ci/mcp_bridge.sh).
    if phase("assistant", "-aiEnabled", "YES", "-aiToken", "monkeytoken0123456789", "-aiApprovedClients", "(Tester)"):
        url = "http://127.0.0.1:47860/mcp/monkeytoken0123456789"
        asks = [
            {"jsonrpc": "2.0", "id": 0, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "Tester", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "rect", "arguments": {"x1": 2, "y1": 2, "x2": 7, "y2": 6, "color": "#FF5C8A", "filled": True}}},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "read_canvas", "arguments": {}}},
        ]
        script = open(os.path.join(HERE, "mcp_bridge.sh")).read()
        out = subprocess.run(["/bin/sh", "-c", script, "pixeldeck", url], input="\n".join(json.dumps(a) for a in asks) + "\n",
                             capture_output=True, text=True, timeout=60)
        for line in out.stdout.split("\n"):
            if line.strip():
                print("    answer:", line[:700], flush=True)
        if out.stderr.strip():
            print("    bridge said:", out.stderr.strip()[:300])
        check("an assistant drawing through the bridge")

    # Photo to pixel art, step 2: are the size and colour options in view?
    if "photo options" in ONLY and phase("photo options", "-monkeyOpen", "photo"):
        time.sleep(3)
        click(640, 802, "Next")
        time.sleep(1.5)
        look("showing step 2 of Photo to pixel art")

    # Choosing a picture: does the Finder's window open, and does it close again?
    if "picture" in ONLY and phase("picture window", "-monkeyOpen", "photoEmpty"):
        global window
        for mode in ("in a normal window", "in full screen"):
            if mode == "in full screen":
                key("f", "cmd", "ctrl", what="full screen")
                time.sleep(4)
                window = find_window()
                print("window now:", window)
            # The Choose a picture button is 122 points above the foot of the window, in the middle.
            width, height = window[2] / 0.77, window[3] / 0.77
            print(f"--- {mode}: before\n" + sh("swift", os.path.join(HERE, "windows.swift")), flush=True)
            click(width / 2, height - 122, "Choose a picture")
            time.sleep(3)
            print(f"--- {mode}: after clicking Choose a picture\n" + sh("swift", os.path.join(HERE, "windows.swift")), flush=True)
            key("esc", what="escape from the picture window")
            time.sleep(2)
            print(f"--- {mode}: after Escape\n" + sh("swift", os.path.join(HERE, "windows.swift")), flush=True)
            click(width / 2, height - 60, "Next (should do nothing without a picture)")
            print("app still running:", alive(), flush=True)

    # Community needs iCloud, which the build machine's unsigned copy of the app doesn't have:
    # CloudKit stops the app there ("Significant issue"). Only tried when asked for by name.
    if "community" in ONLY and phase("community"):
        click(80, 842, "Community")
        time.sleep(3)
        check("Community, three seconds after opening")
        look("showing Community")
        for x, y in ((640, 400), (400, 300), (900, 300), (640, 700), (200, 120), (1100, 120)):
            click(x, y, "inside Community")
        escape()



def report():
    """Summarises crash reports that haven't been shown yet (each kind of crash once)."""
    seen = signatures
    paths = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/PixelDeck*.ips")))
    for path in paths:
        if path in reported:
            continue
        reported.add(path)
        try:
            text = open(path).read()
            body = json.loads(text[text.index("\n") + 1:])
        except Exception as error:
            print(f"{os.path.basename(path)}: unreadable ({error})")
            continue
        images = body.get("usedImages", [])
        thread = next((t for t in body.get("threads", []) if t.get("triggered")), None)
        # The first few frames say what went wrong; after that only the app's own frames are
        # listed, with a count of the system frames between them.
        frames, skipped = [], 0
        for n, frame in enumerate((thread or {}).get("frames", [])):
            image = images[frame.get("imageIndex", 0)].get("name", "?") if images else "?"
            if n >= 6 and not image.startswith("PixelDeck"):
                skipped += 1
                continue
            if skipped:
                frames.append(f"    ... {skipped} system frames")
                skipped = 0
            frames.append(f"{image}  {frame.get('symbol', hex(frame.get('imageOffset', 0)))} +{frame.get('symbolLocation', 0)}")
        if skipped:
            frames.append(f"    ... {skipped} system frames")
        ours = next((f for f in frames if f.startswith("PixelDeck")), frames[0] if frames else "")
        signature = (json.dumps(body.get("asi", {}))[:200], ours)
        if signature in seen:
            print(f"    (same crash as before: {ours[:110]})", flush=True)
            continue
        seen.add(signature)
        print(f"----- {os.path.basename(path)}")
        print("exception:", json.dumps(body.get("exception", {})))
        print("message:", json.dumps(body.get("asi", {}))[:900])
        demangled = subprocess.run(["xcrun", "swift-demangle", "--simplified"], input="\n".join(frames), capture_output=True, text=True).stdout
        print(demangled or "\n".join(frames), flush=True)


if __name__ == "__main__":
    main()
