#!/usr/bin/env python3
"""XARVIN streaming TTS worker (Deepgram Aura 2).

Protocol (JSON lines over stdin/stdout):
  in : {"cmd": "speak", "text": "..."}   queue a sentence (non-blocking)
       {"cmd": "stop"}                   interrupt + flush queue
       {"cmd": "ping"}
  out: {"event": "ready", ...}
       {"event": "playing", "text": "...", "duration_ms": 2450}
       {"event": "done", "text": "..."}
       {"event": "stopped"} / {"event": "pong"}

Each sentence is prefetched in the background while the previous sentence plays,
and reports its exact audio duration in milliseconds (from 48kbps CBR MP3 size
adjusted by SPEECH_SPEED) so the UI word-by-word highlight stays 100% synced.
"""
import os
import sys
import re
import json
import queue
import threading
import subprocess
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
ENV_FILE = Path(os.environ.get("XARVIN_ENV", PROJECT_DIR / "config" / "xarvin.env"))

CONFIG = {}
if ENV_FILE.exists():
    with open(ENV_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                CONFIG[k.strip()] = v.strip().strip("'\"")

DEEPGRAM_API_KEY = CONFIG.get("DEEPGRAM_API_KEY", "")
DEEPGRAM_VOICE = CONFIG.get("DEEPGRAM_VOICE", "aura-2-orion-en")
try:
    SPEECH_SPEED = float(CONFIG.get("SPEECH_SPEED", "1.15"))
except ValueError:
    SPEECH_SPEED = 1.15

PLAYER_CMD = [
    "mpv",
    "--no-video",
    "--no-terminal",
    "--really-quiet",
    "--audio-stream-silence=yes",
    "--audio-buffer=0.1",
    f"--speed={SPEECH_SPEED}",
    "-",
]

out_lock = threading.Lock()


def emit(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def clean_for_speech(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"```[\s\S]*?```", " ", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[#*_~`>]", " ", text)
    text = re.sub(r"^\s*[-+*]\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"^\s*\d+\.\s+", "", text, flags=re.MULTILINE)
    return re.sub(r"\s+", " ", text).strip()


def fetch_tts_audio(text: str) -> bytes:
    """Fetch MP3 audio bytes from Deepgram Aura 2."""
    if not DEEPGRAM_API_KEY:
        return b""
    try:
        api_ver = "v2" if DEEPGRAM_VOICE.startswith("flux") else "v1"
        req = urllib.request.Request(
            f"https://api.deepgram.com/{api_ver}/speak?model={DEEPGRAM_VOICE}",
            data=json.dumps({"text": text[:800]}).encode("utf-8"),
            headers={
                "Authorization": f"Token {DEEPGRAM_API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                return resp.read()
    except Exception as e:
        sys.stderr.write(f"[TTS] Deepgram error: {e}\n")
    return b""


class Job:
    """One sentence prefetched in a background thread."""

    def __init__(self, text: str, gen: int):
        self.text = text
        self.gen = gen
        self.ready = threading.Event()
        self.audio = b""
        threading.Thread(target=self._fetch, daemon=True).start()

    def _fetch(self):
        try:
            if self.gen == state["gen"]:
                self.audio = fetch_tts_audio(self.text)
        finally:
            self.ready.set()


state = {"gen": 0, "player": None}
jobs = queue.Queue()
player_lock = threading.Lock()


def player_loop():
    while True:
        job = jobs.get()
        if job.gen != state["gen"]:
            continue
        job.ready.wait(timeout=12)
        if job.gen != state["gen"] or not job.audio:
            if job.gen == state["gen"]:
                emit({"event": "done", "text": job.text})
            continue

        # Deepgram Aura 2 MP3 is 48 kbps CBR (6000 bytes/sec)
        raw_seconds = len(job.audio) / 6000.0
        duration_ms = max(300, int((raw_seconds / max(0.5, SPEECH_SPEED)) * 1000))

        player = None
        try:
            with player_lock:
                if job.gen != state["gen"]:
                    continue
                player = subprocess.Popen(
                    PLAYER_CMD,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                state["player"] = player

            emit({"event": "playing", "text": job.text, "duration_ms": duration_ms})
            player.stdin.write(job.audio)
            player.stdin.close()
            if job.gen == state["gen"]:
                player.wait(timeout=60)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            pass
        finally:
            with player_lock:
                if state["player"] is player:
                    state["player"] = None

        if job.gen == state["gen"]:
            emit({"event": "done", "text": job.text})


def stop_all():
    state["gen"] += 1
    while True:
        try:
            jobs.get_nowait()
        except queue.Empty:
            break
    with player_lock:
        p = state["player"]
        state["player"] = None
    if p and p.poll() is None:
        try:
            p.terminate()
            p.wait(timeout=0.3)
        except Exception:
            pass


def main():
    sys.stderr.write(
        f"[TTS] XARVIN Voice Worker Initialized (Engine: deepgram, Voice: {DEEPGRAM_VOICE}, Speed: {SPEECH_SPEED}x)\n"
    )
    threading.Thread(target=player_loop, daemon=True).start()
    emit({"event": "ready", "engine": "deepgram", "voice": DEEPGRAM_VOICE, "speed": SPEECH_SPEED})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        cmd = req.get("cmd")
        if cmd == "ping":
            emit({"event": "pong"})
        elif cmd == "stop":
            stop_all()
            emit({"event": "stopped"})
        elif cmd == "speak":
            text = clean_for_speech(req.get("text", ""))
            if not text:
                emit({"event": "done", "text": ""})
                continue
            jobs.put(Job(text, state["gen"]))


if __name__ == "__main__":
    main()
