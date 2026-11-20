"""DeckLink agent for Windows. Builds one deck per open window and streams them to the phone."""
import asyncio, ctypes, datetime, json, os, secrets, shutil, socket, subprocess, sys, time
from ctypes import wintypes
from pathlib import Path
from aiohttp import web, WSMsgType
import pyautogui, pyperclip, psutil, qrcode
import win32gui, win32process, win32con

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

RES = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
HOME = Path.home() / "DeckLink"
IN_DIR, OUT_DIR = HOME / "incoming", HOME / "outgoing"
for d in (IN_DIR, OUT_DIR):
    d.mkdir(parents=True, exist_ok=True)
LAYOUTS = HOME / "layouts.json"  # your editable copy
if not LAYOUTS.exists():
    shutil.copy(RES / "layouts.json", LAYOUTS)
TOKEN_FILE = HOME / "token.txt"
TOKEN = TOKEN_FILE.read_text().strip() if TOKEN_FILE.exists() else secrets.token_urlsafe(8)
TOKEN_FILE.write_text(TOKEN)
PORT = 8765
MAX_DECKS = 12
pyautogui.PAUSE = 0.02
pyautogui.FAILSAFE = False

clients = set()
S = {"clip": "", "layouts": {"contexts": [], "generic": []}, "mtime": 0, "order": [],
     "decks": [], "active": 0, "force": True}
SKIP_EXE = {"textinputhost.exe", "searchhost.exe", "startmenuexperiencehost.exe", "shellexperiencehost.exe"}
OWN_EXE = Path(sys.executable).name.lower()


def load_layouts():
    m = LAYOUTS.stat().st_mtime
    if m != S["mtime"]:
        try:
            S["layouts"] = json.loads(LAYOUTS.read_text(encoding="utf-8"))
            S["mtime"], S["force"] = m, True
        except Exception as e:
            print("layouts.json error:", e)


def cloaked(h):
    v = ctypes.c_int(0)
    try:
        ctypes.windll.dwmapi.DwmGetWindowAttribute(wintypes.HWND(h), 14, ctypes.byref(v), ctypes.sizeof(v))
    except Exception:
        pass
    return v.value != 0


def exe_of(h):
    try:
        return psutil.Process(win32process.GetWindowThreadProcessId(h)[1]).name().lower()
    except Exception:
        return ""


def list_windows():
    out = []

    def cb(h, _):
        if not win32gui.IsWindowVisible(h) or win32gui.GetWindow(h, win32con.GW_OWNER):
            return
        title = win32gui.GetWindowText(h)
        if not title or title == "Program Manager":
            return
        if win32gui.GetWindowLong(h, win32con.GWL_EXSTYLE) & win32con.WS_EX_TOOLWINDOW or cloaked(h):
            return
        exe = exe_of(h)
        if exe in SKIP_EXE or exe == OWN_EXE:
            return
        out.append({"id": h, "exe": exe, "title": title})

    win32gui.EnumWindows(cb, None)
    return out


def resolve(exe, title):
    for c in S["layouts"]["contexts"]:
        if c["id"] == "default":
            continue
        m = c.get("match", {})
        if m.get("exe") and exe not in m["exe"]:
            continue
        if m.get("title") and not any(t.lower() in title.lower() for t in m["title"]):
            continue
        return c
    return None


def friendly(exe, title):
    return title[:24] if exe == "applicationframehost.exe" or not exe else exe[:-4].title()


def build_decks():
    wins = list_windows()
    live = {w["id"]: w for w in wins}
    S["order"] = [h for h in S["order"] if h in live] + [w["id"] for w in wins if w["id"] not in S["order"]]
    S["order"] = S["order"][:MAX_DECKS]
    desk = next((c for c in S["layouts"]["contexts"] if c["id"] == "default"), None)
    decks = []
    if desk:
        decks.append({"id": 0, "name": desk["name"], "icon": desk.get("icon", "🖥️"), "title": "Media, volume and system", "buttons": desk["buttons"]})
    for h in S["order"]:
        w = live[h]
        c = resolve(w["exe"], w["title"])
        if c:
            name, icon, btns = c["name"], c.get("icon", "🪟"), c["buttons"]
        else:
            name, icon, btns = friendly(w["exe"], w["title"]), "🪟", S["layouts"].get("generic", [])
        decks.append({"id": h, "name": name, "icon": icon, "title": w["title"][:60], "buttons": btns})
    return decks


def decks_msg():
    return {"t": "decks", "active": S["active"], "decks": [
        {"id": d["id"], "name": d["name"], "icon": d["icon"], "title": d["title"],
         "buttons": [{"label": b["label"], "icon": b.get("icon", "")} for b in d["buttons"]]} for d in S["decks"]]}


def focus(h):
    try:
        if win32gui.IsIconic(h):
            win32gui.ShowWindow(h, win32con.SW_RESTORE)
        pyautogui.press("alt")  # lets SetForegroundWindow succeed
        win32gui.SetForegroundWindow(h)
    except Exception:
        pass


def do_action(a, hwnd):
    t = a.get("type")
    if t == "hotkey":
        pyautogui.hotkey(*a["keys"])
    elif t == "key":
        pyautogui.press(a["key"])
    elif t == "text":
        pyautogui.write(a["text"], interval=0.01)
    elif t == "url":
        os.startfile(a["url"])
    elif t == "run":
        subprocess.Popen(a["cmd"], shell=True)
    elif t == "win" and hwnd:
        ops = {"min": win32con.SW_MINIMIZE, "max": win32con.SW_MAXIMIZE, "restore": win32con.SW_RESTORE}
        if a["op"] in ops:
            win32gui.ShowWindow(hwnd, ops[a["op"]])
        elif a["op"] == "close":
            win32gui.PostMessage(hwnd, win32con.WM_CLOSE, 0, 0)


def run_press(hwnd, action):
    if hwnd and win32gui.GetForegroundWindow() != hwnd:
        focus(hwnd)
        time.sleep(0.2)
    do_action(action, hwnd)


async def broadcast(msg):
    for w in list(clients):
        try:
            await w.send_json(msg)
        except Exception:
            clients.discard(w)


async def watch():
    last = None
    while True:
        load_layouts()
        S["decks"] = build_decks()
        ids = {d["id"] for d in S["decks"]}
        fg = win32gui.GetForegroundWindow()
        if fg in ids:
            S["active"] = fg
        elif S["active"] not in ids:
            S["active"] = 0
        sig = (tuple((d["id"], d["name"]) for d in S["decks"]), S["active"])
        if sig != last or S["force"]:
            last, S["force"] = sig, False
            await broadcast(decks_msg())
        try:
            clip = pyperclip.paste()
        except Exception:
            clip = S["clip"]
        if clip != S["clip"]:
            S["clip"] = clip
            await broadcast({"t": "clip", "text": clip})
        await asyncio.sleep(0.4)


async def ws_handler(request):
    if request.query.get("k") != TOKEN:
        return web.Response(status=401)
    w = web.WebSocketResponse(heartbeat=20)
    await w.prepare(request)
    clients.add(w)
    await w.send_json(decks_msg())
    await w.send_json({"t": "clip", "text": S["clip"]})
    loop = asyncio.get_running_loop()
    async for m in w:
        if m.type != WSMsgType.TEXT:
            continue
        d = json.loads(m.data)
        if d.get("t") == "press":
            deck = next((x for x in S["decks"] if x["id"] == d.get("deck")), None)
            i = d.get("i", -1)
            if deck and 0 <= i < len(deck["buttons"]):
                await loop.run_in_executor(None, run_press, deck["id"], deck["buttons"][i]["action"])
        elif d.get("t") == "clip":
            S["clip"] = d["text"]
            pyperclip.copy(d["text"])
    clients.discard(w)
    return w


def authed(request):
    if request.query.get("k") != TOKEN:
        raise web.HTTPUnauthorized()


async def upload(request):
    authed(request)
    reader = await request.multipart()
    n = 0
    async for part in reader:
        if part.filename:
            name = f"{datetime.datetime.now():%Y%m%d-%H%M%S}-{Path(part.filename).name}"
            with open(IN_DIR / name, "wb") as f:
                while chunk := await part.read_chunk():
                    f.write(chunk)
            n += 1
    return web.json_response({"saved": n})


async def files(request):
    authed(request)
    return web.json_response(sorted((p.name for p in OUT_DIR.iterdir() if p.is_file()), reverse=True))


async def download(request):
    authed(request)
    p = (OUT_DIR / request.match_info["name"]).resolve()
    if p.parent != OUT_DIR.resolve() or not p.is_file():
        raise web.HTTPNotFound()
    return web.FileResponse(p)


async def index(request):
    return web.FileResponse(RES / "static" / "index.html")


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("8.8.8.8", 80))
    ip = s.getsockname()[0]
    s.close()
    return ip


def show_qr(label, data):
    print(label)
    q = qrcode.QRCode(border=1)
    q.add_data(data)
    q.print_ascii(invert=True)
    print(data + "\n")


async def on_start(app):
    app["watch"] = asyncio.create_task(watch())


if __name__ == "__main__":
    host = f"{lan_ip()}:{PORT}"
    print("\nDeckLink is running. Keep this window open. Phone and PC must be on the same Wi-Fi.\n")
    show_qr("1) iPhone app: scan with the Camera app", f"decklink://pair?host={host}&token={TOKEN}")
    show_qr("2) No app? Open in Safari and Add to Home Screen", f"http://{host}/?k={TOKEN}")
    print(f"Phone photos arrive in: {IN_DIR}\nFiles for the phone go in: {OUT_DIR}\nEdit decks in: {LAYOUTS}\n")
    app = web.Application(client_max_size=2 ** 33)
    app.add_routes([web.get("/", index), web.get("/ws", ws_handler), web.post("/upload", upload),
                    web.get("/files", files), web.get("/dl/{name}", download)])
    app.on_startup.append(on_start)
    web.run_app(app, host="0.0.0.0", port=PORT, print=None)
