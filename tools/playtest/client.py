"""Local playtest client. Standard-library Python only; no mouse automation."""

import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import godot

ROOT = godot.ROOT


class Client:
    def __init__(self, port=18765):
        self.port = port

    def send(self, op, **args):
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.settimeout(40)
            sock.sendall((json.dumps({"op": op, **args}) + "\n").encode())
            with sock.makefile("r", encoding="utf-8") as stream:
                line = stream.readline()
        if not line:
            raise RuntimeError("Game disconnected before replying; inspect godot.log")
        result = json.loads(line)
        if not result["ok"]:
            raise RuntimeError(result.get("error", str(result)))
        return result

    def state(self):
        return self.send("state")["state"]

    def until(self, predicate, description, timeout=45):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            state = self.state()
            if predicate(state):
                return state
            time.sleep(0.15)
        raise TimeoutError(f"Timed out: {description}; task={state['task']}, goal={state['goal']}")


def launch(args):
    try:
        with socket.create_connection(("127.0.0.1", args.port), timeout=0.3):
            pass
    except OSError:
        pass
    else:
        raise RuntimeError(f"Port {args.port} already has a session; quit it or choose another --port")
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy() if args.headless else godot.xr_env()
    command = [str(args.godot or godot.executable()), "--path", str(ROOT)]
    command += ["--headless", "--xr-mode", "off"] if args.headless else ["--xr-mode", "on"]
    command += ["--log-file", str(out / "godot.log"), "res://tools/playtest/session.tscn", "--",
                f"--profile={args.profile}", f"--port={args.port}", f"--out={out.as_posix()}"]
    with (out / "console.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=log,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    try:
        end = time.monotonic() + 30
        while time.monotonic() < end:
            if process.poll() is not None:
                raise RuntimeError((out / "console.log").read_text(encoding="utf-8"))
            try:
                state = Client(args.port).state()
                if state["pid"] != process.pid:
                    raise RuntimeError("Port answered from a different process")
                print(json.dumps({"pid": process.pid, "port": args.port, "output": str(out),
                                  "task": state["task"], "profile": state["profile"]}, ensure_ascii=False))
                return
            except (OSError, RuntimeError):
                time.sleep(0.2)
        raise TimeoutError("Playtest did not become ready; inspect " + str(out / "godot.log"))
    except Exception:
        process.terminate()
        raise


def vector(text):
    values = [float(part) for part in text.split(",")]
    if len(values) != 3:
        raise argparse.ArgumentTypeError("Expected x,y,z in metres (rotation is degrees)")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--full", action="store_true", help="Include full observations in action replies")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["launch", "demo"]:
        start = sub.add_parser(name)
        start.add_argument("--godot")
        start.add_argument("--headless", action="store_true")
        start.add_argument("--out", default=str(ROOT / "build/playtest"))
        start.add_argument("--profile", default="playtest")
    sub.add_parser("state")
    where = sub.add_parser("where", help="Only object positions and offsets from each hand")
    where.add_argument("target", nargs="?", default="")
    raw = sub.add_parser("send")
    raw.add_argument("json")
    move = sub.add_parser("move")
    move.add_argument("hand", choices=["left", "right"])
    target = move.add_mutually_exclusive_group(required=True)
    target.add_argument("--to")
    target.add_argument("--position", type=vector)
    move.add_argument("--offset", type=vector, default=[0, 0, 0])
    move.add_argument("--rotation", type=vector)
    move.add_argument("--seconds", type=float, default=0.6)
    for action in ("poke", "aim", "click"):
        command = sub.add_parser(action)
        command.add_argument("to")
        command.add_argument("--hand", choices=["left", "right"], default="right")
    grip = sub.add_parser("grip")
    grip.add_argument("hand", choices=["left", "right"])
    grip.add_argument("state", choices=["on", "off"])
    teleport = sub.add_parser("teleport")
    teleport.add_argument("to")
    capture = sub.add_parser("capture")
    capture.add_argument("name")
    sub.add_parser("quit")
    args = parser.parse_args()
    if args.command in ["launch", "demo"]:
        launch(args)
        if args.command == "demo":
            command = [sys.executable, str(Path(__file__).with_name("playthrough.py")),
                       "--port", str(args.port), "--out", args.out]
            if args.headless:
                command.append("--no-images")
            sys.exit(subprocess.call(command, cwd=ROOT))
        return
    client = Client(args.port)
    if args.command == "where":
        state = client.state()
        objects = state["objects"] + state["buttons"]
        if args.target == "target":
            objects = [trial["target"] for trial in state["trials"] if trial.get("target")]
        else:
            objects = [obj for obj in objects if obj["visible"] and
                       (not args.target or args.target in obj["id"] or args.target == obj["path"])]
        result = []
        for obj in objects:
            entry = {"id": obj["id"], "position": obj["position"]}
            for side in ["left", "right"]:
                entry[side + "_offset"] = [round(a - b, 4) for a, b in
                                           zip(obj["position"], state["hands"][side]["position"])]
            result.append(entry)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return
    values = vars(args).copy()
    op = values.pop("command")
    values.pop("port")
    values.pop("full")
    if op == "send":
        values = json.loads(args.json)
        op = values.pop("op")
    elif op == "grip":
        op = "button"
        values = {"hand": args.hand, "action": "grip_click", "pressed": args.state == "on"}
    values = {key: value for key, value in values.items() if value is not None}
    result = client.send(op, **values)
    if op == "quit":
        for _ in range(50):
            time.sleep(0.1)
            try:
                with socket.create_connection(("127.0.0.1", args.port), timeout=0.2):
                    pass
            except OSError:
                break
    if op != "state" and not args.full and "state" in result:
        state = result.pop("state")
        result.update(task=state["task"], goal=state["goal"], menu_open=state["menu_open"],
                      inventory=state["inventory"], hands=state["hands"])
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, TimeoutError) as error:
        sys.exit(str(error))
