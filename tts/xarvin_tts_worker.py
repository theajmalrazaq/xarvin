#!/usr/bin/env python3
"""XARVIN streaming TTS worker.

Protocol (JSON lines over stdin/stdout):
  in : {"cmd": "speak", "text": "..."}   queue a sentence (non-blocking)
       {"cmd": "stop"}                   interrupt + flush queue
       {"cmd": "ping"}
  out: {"event": "ready", ...}
       {"event": "playing", "text": "..."}  audio for this sentence actually started
       {"event": "done", "text": "..."}     audio for this sentence fully finished
       {"event": "stopped"} / {"event": "pong"}

Each sentence is played by its own mpv process (clean, no distortion). While one
sentence plays, the next one is already being fetched, so gaps stay minimal.
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
DEEPGRAM_VOICE = CONFIG.get("DEEPGRAM_VOICE", "aura-2-draco-en")

SILENCE_MP3_PATH = SCRIPT_DIR / "silence_preroll.mp3"
SILENCE_PREROLL = SILENCE_MP3_PATH.read_bytes() if SILENCE_MP3_PATH.exists() else b""

PLAYER_CMD = ["mpv", "--no-video", "--no-terminal", "--really-quiet",
              "--audio-stream-silence=yes", "--audio-buffer=0.2", "-"]

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


def open_tts_stream(text):
    """Return an open HTTP response streaming MP3 audio from Deepgram Flux/Aura, or None."""
    if DEEPGRAM_API_KEY:
        try:
            api_ver = "v2" if DEEPGRAM_VOICE.startswith("flux") else "v1"
            req = urllib.request.Request(
                f"https://api.deepgram.com/{api_ver}/speak?model={DEEPGRAM_VOICE}",
                data=json.dumps({"text": text[:800]}).encode("utf-8"),
                headers={"Authorization": f"Token {DEEPGRAM_API_KEY}",
                         "Content-Type": "application/json"},
                method="POST")
            resp = urllib.request.urlopen(req, timeout=10)
            if resp.status == 200:
                return resp
        except Exception as e:
            sys.stderr.write(f"[TTS] Deepgram error: {e}\n")
    return None


class Job:
    """One sentence: audio chunks are fetched in the background into self.chunks."""

    def __init__(self, text, gen):
        self.text = text
        self.gen = gen
        self.chunks = queue.Queue()
        threading.Thread(target=self._fetch, daemon=True).start()

    def _fetch(self):
        resp = open_tts_stream(self.text)
        try:
            if resp is not None:
                while True:
                    if self.gen != state["gen"]:
                        break
                    c = resp.read(4096)
                    if not c:
                        break
                    self.chunks.put(c)
        except Exception as e:
            sys.stderr.write(f"[TTS] stream error: {e}\n")
        finally:
            self.chunks.put(None)  # end marker
            try:
                if resp is not None:
                    resp.close()
            except Exception:
                pass


state = {"gen": 0, "player": None}
jobs = queue.Queue()
player_lock = threading.Lock()


def player_loop():
    while True:
        job = jobs.get()
        if job.gen != state["gen"]:
            continue
        player = None
        started = False
        try:
            while True:
                c = job.chunks.get()
                if c is None or job.gen != state["gen"]:
                    break
                if player is None:
                    with player_lock:
                        if job.gen != state["gen"]:
                            break
                        player = subprocess.Popen(PLAYER_CMD, stdin=subprocess.PIPE,
                                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        state["player"] = player
                    if SILENCE_PREROLL:
                        player.stdin.write(SILENCE_PREROLL)
                    emit({"event": "playing", "text": job.text})
                    started = True
                player.stdin.write(c)
                player.stdin.flush()
            if player is not None:
                try:
                    player.stdin.close()
                except Exception:
                    pass
                if job.gen == state["gen"]:
                    player.wait(timeout=60)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            pass
        finally:
            with player_lock:
                if state["player"] is player:
                    state["player"] = None
        if job.gen == state["gen"]:
            if not started:
                sys.stderr.write(f"[TTS] no audio for: {job.text[:60]}\n")
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
    sys.stderr.write(f"[TTS] XARVIN Voice Worker Initialized (Engine: deepgram, Voice: {DEEPGRAM_VOICE})\n")
    threading.Thread(target=player_loop, daemon=True).start()
    emit({"event": "ready", "engine": "deepgram", "voice": DEEPGRAM_VOICE})

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
            jobs.put(Job(text, state["gen"]))  # fetch starts immediately (prefetch)


if __name__ == "__main__":
    main()
