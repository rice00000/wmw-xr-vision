"""Bake speech on Windows/macOS; --watch keeps the Godot editor nonblocking."""
from pathlib import Path
from contextlib import contextmanager
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
import time
from speech_backend import synthesizer

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "content/audio/speech.tts"
OUT = ROOT / "content/audio/generated"
INDEX = OUT / "index.json"
FIELDS = re.compile(r'(?m)^\s*(?:@export(?:_multiline)?\s+var\s+)?(instruction|completed_text|title|display_name|description|prompt|retry)\s*(?::=|=)\s*("(?:\\.|[^"\\])*")')


def strings(path):
    """Read Godot string literals, preserving escaped characters and multiline copy."""
    for match in re.finditer(r'#.*|"(?:\\.|[^"\\])*"', path.read_text(encoding="utf-8")):
        if match[0].startswith('"'):
            yield decode(match[0])


def decode(token):
    return json.loads(token.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t"))


def fields(path):
    return [(m[1], decode(m[2])) for m in FIELDS.finditer(path.read_text(encoding="utf-8"))]


def collect(config):
    phrases, prompts = {}, []

    def add(text):
        for part in re.split(r'%[-+0-9.]*[sdf]', text.replace("%%", " percent")):
            key = " ".join(re.sub(r"(?:[^\w']|_)+", " ", part.lower()).split())
            if key:
                phrases.setdefault(key, part.strip())

    for line in config["lines"]:
        add(line)
    for source in config["script_sources"]:
        for text in strings(ROOT / source):
            add(text)
    for source in config["defaults"]:
        for field, text in fields(ROOT / source):
            add(text)
            if field == "prompt" and text.count("%s") == 1:
                prompts.append(text)
    for directory in config["resource_roots"]:
        for path in sorted((ROOT / directory).rglob("*")):
            if path.suffix not in (".tres", ".tscn") or "visuals" in path.parts:
                continue
            values = fields(path)
            for _, text in values:
                add(text)
            name = dict(values).get("display_name") or path.stem.replace("_", " ").capitalize()
            if directory == "content/items":
                add(name)
                add(name if name.endswith("s") else name + "s")
            if directory == "content/trials/objects":
                add(name)
                for prompt in prompts:
                    add(prompt % name)
    phrases.update({str(n): str(n) for n in range(100)})
    phrases.update({"percent": "percent", "degrees": "degrees"})
    return dict(sorted(phrases.items()))


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


@contextmanager
def bake_lock():
    """Serialize an editor bake and a simultaneous CLI build."""
    path = ROOT / ".godot/speech-bake.lock"
    path.parent.mkdir(exist_ok=True)
    with path.open("a+b") as lock:
        if lock.tell() == 0:
            lock.write(b"0")
            lock.flush()
        lock.seek(0)
        if sys.platform == "win32":
            import msvcrt
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        yield # Closing the file releases the lock on both OSes.


def bake(check, report):
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    phrases = collect(config)
    # Shared cache keys deliberately exclude the host OS. Checking out teammates'
    # files never regenerates them merely because their computer has another voice.
    settings = {"format": "ogg-vorbis-mono-q0-v1", "voices": config["voices"]}
    clips = {key: "res://content/audio/generated/" + digest([settings, text])[:24] + ".ogg"
             for key, text in phrases.items()}
    pending = [key for key, path in clips.items() if not (ROOT / path[6:]).exists()]
    fingerprint = digest([settings, phrases])
    previous = json.loads(INDEX.read_text(encoding="utf-8")) if INDEX.exists() else {}
    fresh = not pending and previous.get("fingerprint") == fingerprint
    if check:
        if not fresh:
            raise RuntimeError("Speech is stale. Run python3 tools/bake_speech.py (Windows: python).")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    if pending:
        import soundfile as sf
        speak = synthesizer(config["voices"])
        for done, key in enumerate(pending, 1):
            report(state="generating", done=done, total=len(pending))
            descriptor, name = tempfile.mkstemp(prefix=".speech-", suffix=".tmp", dir=OUT)
            os.close(descriptor)
            temporary = Path(name)
            encoded = temporary.with_suffix(".ogg.tmp")
            try:
                speak(phrases[key], temporary)
                audio, rate = sf.read(temporary, dtype="float32", always_2d=True)
                if len(audio) == 0:
                    raise RuntimeError("Empty speech audio: " + phrases[key])
                # Maximum Vorbis compression; WAV is only a synthesis intermediate.
                sf.write(encoded, audio.mean(axis=1), rate, format="OGG", subtype="VORBIS", compression_level=1.0)
                encoded.replace(ROOT / clips[key][6:])
            finally:
                temporary.unlink(missing_ok=True)
                encoded.unlink(missing_ok=True)
    if not fresh:
        write_json(INDEX, {"fingerprint": fingerprint, "clips": clips})
        active = {Path(path).name for path in clips.values()}
        for path in OUT.iterdir():
            if path.suffix in (".wav", ".ogg") and path.name not in active:
                path.unlink()
                path.with_suffix(path.suffix + ".import").unlink(missing_ok=True)
    report(state="ready", generated=len(pending), total=len(clips))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--watch", action="store_true")
    parser.add_argument("--status", type=Path)
    args = parser.parse_args()

    def report(**value):
        if args.status:
            write_json(args.status, value)

    def run():
        try:
            with bake_lock():
                bake(args.check, report)
            return 0
        except Exception as error:
            message = getattr(error, "stderr", None) or str(error)
            report(state="error", message=message)
            print("SPEECH_ERROR:", message, file=sys.stderr, flush=True)
            return 1

    if not args.watch:
        return run()
    # Only this worker scans source files. Godot reads a tiny status file.
    seen, due = None, 0.0
    while True:
        sources = [CONFIG, *ROOT.glob("modules/**/*.gd"), *ROOT.glob("content/**/*.tres"), *ROOT.glob("content/**/*.tscn")]
        stamp = [(str(p), p.stat().st_mtime_ns) for p in sorted(sources)]
        if stamp != seen:
            seen, due = stamp, time.monotonic() + 0.8
            report(state="waiting")
        if due and time.monotonic() >= due:
            run()
            due = 0.0
        time.sleep(0.25)


if __name__ == "__main__":
    sys.exit(main())
