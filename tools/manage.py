#!/usr/bin/env python3
"""Start/stop only this checkout's managed server and Godot client."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / "build" / "run"


def identity(pid):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "lstart="],
        capture_output=True,
        text=True,
    )
    if result.stderr.strip():
        raise RuntimeError(
            "Cannot inspect process identity; refusing to change process records"
        )
    return result.stdout.strip() if result.returncode == 0 else ""


def tracked(name):
    path = STATE / f"{name}.json"
    if not path.exists():
        return None
    record = json.loads(path.read_text())
    if identity(record["pid"]) != record["identity"]:
        path.unlink()
        return None
    return record


def stop(name):
    record = tracked(name)
    if not record:
        print(f"{name}: already stopped")
        return
    os.kill(record["pid"], signal.SIGTERM)
    for _ in range(100):
        if identity(record["pid"]) != record["identity"]:
            break
        time.sleep(0.05)
    else:
        raise RuntimeError(f"{name} did not stop; see build/run/{name}.log")
    (STATE / f"{name}.json").unlink(missing_ok=True)
    print(f"{name}: stopped")


def launch(name, command, env, port):
    with (STATE / f"{name}.log").open("ab") as log:
        child = subprocess.Popen(
            command,
            cwd=ROOT,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    time.sleep(0.2)
    if child.poll() is not None:
        raise RuntimeError(f"{name} exited; see build/run/{name}.log")
    (STATE / f"{name}.json").write_text(
        json.dumps(
            {
                "pid": child.pid,
                "identity": identity(child.pid),
                "port": port,
            }
        )
    )
    return child


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["start", "stop"])
    parser.add_argument(
        "--godot", default="/Applications/Godot.app/Contents/MacOS/Godot"
    )
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--data", default=str(Path.home() / ".causewaybaycoast/server"))
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / "lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == "stop":
            errors = []
            for name in ["client", "server"]:
                try:
                    stop(name)
                except (OSError, RuntimeError) as exc:
                    errors.append(str(exc))
            if errors:
                raise RuntimeError("; ".join(errors))
            return
        env = dict(
            os.environ,
            COAST_PORT=str(args.port),
            COAST_DIR=str(Path(args.data).expanduser().resolve()),
            COAST_SERVER_URL=f"ws://127.0.0.1:{args.port}/ws",
        )
        server = tracked("server")
        client = tracked("client")
        for record in [server, client]:
            if record and record["port"] != args.port:
                raise RuntimeError(
                    "Managed processes use another port. Run make stop before changing PORT."
                )
        created = []
        try:
            if not server:
                with socket.socket() as probe:
                    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                    probe.bind(("127.0.0.1", args.port))
                child = launch(
                    "server",
                    [str(ROOT / "backend/target/debug/server")],
                    env,
                    args.port,
                )
                created.append("server")
                for _ in range(100):
                    if child.poll() is not None:
                        raise RuntimeError("Server exited; see build/run/server.log")
                    try:
                        with socket.create_connection(
                            ("127.0.0.1", args.port), timeout=0.1
                        ):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    raise RuntimeError("Server readiness timed out")
            if not client:
                launch(
                    "client",
                    [args.godot, "--path", str(ROOT / "godot")],
                    env,
                    args.port,
                )
                created.append("client")
            print(
                f"Server and Godot running at ws://127.0.0.1:{args.port}/ws; logs: build/run/"
            )
        except Exception:
            for name in reversed(created):
                stop(name)
            raise


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as exc:
        sys.exit(str(exc))
