#!/usr/bin/env python3
import os
import sys
import re
import json
import subprocess
import urllib.request
from pathlib import Path

# Resolve base directories
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

TTS_ENGINE = CONFIG.get("TTS_ENGINE", "deepgram").lower()
DEEPGRAM_API_KEY = CONFIG.get("DEEPGRAM_API_KEY", "")
DEEPGRAM_VOICE = CONFIG.get("DEEPGRAM_VOICE", "aura-2-orion-en")

ELEVENLABS_API_KEY = CONFIG.get("ELEVENLABS_API_KEY", "")
ELEVENLABS_VOICE_ID = CONFIG.get("ELEVENLABS_VOICE_ID", "xcy4I5tPh94DVcviSzGr") # Naveen or configured
ELEVENLABS_MODEL = CONFIG.get("ELEVENLABS_MODEL", "eleven_turbo_v2_5")

SILENCE_MP3_PATH = SCRIPT_DIR / "silence_preroll.mp3"
SILENCE_PREROLL = SILENCE_MP3_PATH.read_bytes() if SILENCE_MP3_PATH.exists() else b""

def clean_for_speech(text: str) -> str:
    if not text:
        return ""
    # Strip markdown code blocks and inline code
    text = re.sub(r"```[\s\S]*?```", " ", text)
    text = re.sub(r"`([^`]+)`", r"\1", text)
    # Strip markdown links [label](url) -> label
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    # Strip markdown headers, bold, italics, bullets, blockquotes
    text = re.sub(r"[#*_~`>]", " ", text)
    text = re.sub(r"^\s*[-+*]\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"^\s*\d+\.\s+", "", text, flags=re.MULTILINE)
    # Normalize whitespace
    text = re.sub(r"\s+", " ", text).strip()
    return text

def main():
    active_engine = TTS_ENGINE
    if active_engine == "deepgram" and not DEEPGRAM_API_KEY:
        active_engine = "elevenlabs" if ELEVENLABS_API_KEY else "piper"

    active_voice = DEEPGRAM_VOICE if active_engine == "deepgram" else ELEVENLABS_VOICE_ID
    sys.stderr.write(f"[TTS] XARVIN Voice Worker Initialized (Engine: {active_engine}, Voice: {active_voice})\n")

    # Signal ready
    sys.stdout.write(json.dumps({
        "event": "ready",
        "engine": active_engine,
        "voice": active_voice
    }) + "\n")
    sys.stdout.flush()

    current_player = None
    interrupted = False

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
            sys.stdout.write(json.dumps({"event": "pong"}) + "\n")
            sys.stdout.flush()
        elif cmd == "stop":
            interrupted = True
            if current_player and current_player.poll() is None:
                try:
                    current_player.terminate()
                    current_player.wait(timeout=0.15)
                except Exception:
                    pass
            current_player = None
            sys.stdout.write(json.dumps({"event": "stopped"}) + "\n")
            sys.stdout.flush()
        elif cmd == "speak":
            interrupted = False
            raw_text = req.get("text", "")
            clean = clean_for_speech(raw_text)
            if not clean:
                sys.stdout.write(json.dumps({"event": "done"}) + "\n")
                sys.stdout.flush()
                continue

            success = False

            # 1. Primary: Deepgram Aura Streaming TTS
            if active_engine == "deepgram" and DEEPGRAM_API_KEY and not interrupted:
                try:
                    url = f"https://api.deepgram.com/v1/speak?model={DEEPGRAM_VOICE}"
                    headers = {
                        "Authorization": f"Token {DEEPGRAM_API_KEY}",
                        "Content-Type": "application/json"
                    }
                    payload = json.dumps({"text": clean[:800]}).encode("utf-8")
                    http_req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

                    with urllib.request.urlopen(http_req, timeout=10) as resp:
                        if resp.status == 200:
                            current_player = subprocess.Popen(
                                ["mpv", "--no-video", "--no-terminal", "--really-quiet", "--audio-stream-silence=yes", "--audio-buffer=0.1", "-"],
                                stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL
                            )

                            if SILENCE_PREROLL and current_player.stdin:
                                try:
                                    current_player.stdin.write(SILENCE_PREROLL)
                                    current_player.stdin.flush()
                                except (BrokenPipeError, OSError):
                                    pass

                            while True:
                                if interrupted:
                                    break
                                chunk = resp.read(2048)
                                if not chunk:
                                    break
                                if current_player and current_player.stdin:
                                    try:
                                        current_player.stdin.write(chunk)
                                        current_player.stdin.flush()
                                    except (BrokenPipeError, OSError):
                                        break

                            if current_player and current_player.stdin:
                                try:
                                    current_player.stdin.close()
                                except Exception:
                                    pass

                            if current_player and not interrupted:
                                current_player.wait(timeout=30)
                            success = True
                except Exception as e:
                    sys.stderr.write(f"[TTS] Deepgram speak error: {e}\n")

            # 2. Secondary: ElevenLabs Streaming TTS (if active)
            if not success and ELEVENLABS_API_KEY and not interrupted:
                try:
                    url = f"https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE_ID}/stream?optimize_streaming_latency=3"
                    headers = {
                        "xi-api-key": ELEVENLABS_API_KEY,
                        "Content-Type": "application/json",
                        "Accept": "audio/mpeg"
                    }
                    payload = json.dumps({
                        "text": clean[:800],
                        "model_id": ELEVENLABS_MODEL,
                        "voice_settings": {
                            "stability": 0.5,
                            "similarity_boost": 0.8
                        }
                    }).encode("utf-8")

                    http_req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

                    with urllib.request.urlopen(http_req, timeout=12) as resp:
                        if resp.status == 200:
                            current_player = subprocess.Popen(
                                ["mpv", "--no-video", "--no-terminal", "--really-quiet", "--audio-stream-silence=yes", "--audio-buffer=0.1", "-"],
                                stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL
                            )

                            if SILENCE_PREROLL and current_player.stdin:
                                try:
                                    current_player.stdin.write(SILENCE_PREROLL)
                                    current_player.stdin.flush()
                                except (BrokenPipeError, OSError):
                                    pass

                            while True:
                                if interrupted:
                                    break
                                chunk = resp.read(2048)
                                if not chunk:
                                    break
                                if current_player and current_player.stdin:
                                    try:
                                        current_player.stdin.write(chunk)
                                        current_player.stdin.flush()
                                    except (BrokenPipeError, OSError):
                                        break

                            if current_player and current_player.stdin:
                                try:
                                    current_player.stdin.close()
                                except Exception:
                                    pass

                            if current_player and not interrupted:
                                current_player.wait(timeout=30)
                            success = True
                except Exception as e:
                    sys.stderr.write(f"[TTS] ElevenLabs stream error: {e}\n")

            if current_player and current_player.poll() is None:
                try:
                    current_player.terminate()
                except Exception:
                    pass
            current_player = None

            sys.stdout.write(json.dumps({"event": "done"}) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
