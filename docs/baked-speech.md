# Baked speech

Edit task/menu text as usual; standalone lines and OS voices live in `content/audio/speech.tts`.
Windows rate is SAPI -10..10; macOS rate is words/minute.

Generate: `python3 tools/bake_speech.py` on macOS (`python` on Windows).
Install tools once: `python3 -m pip install -r tools/requirements.txt` (`python` on Windows).
macOS uses `say`; Windows uses SAPI. SoundFile encodes low-quality mono Ogg Vorbis.
`--check` checks freshness; `--watch` watches saves in the background.
The editor runs the worker automatically. Wait for **Speech: ready** before export.
`tools/quest.cmd build` also bakes before exporting and stops on failure.

Commit `content/audio/generated/`: changing OS reuses the cache. New/changed lines use
the author's configured voice, so voices can differ. Only OGGs and the index are kept;
WAV intermediates are deleted. The game only plays files;
exports exclude tools/config. Dynamic text combines baked phrases, names and numbers.

Debug: `tools/bake_speech.py` collects/caches; `tools/speech_backend.py` calls the OS;
`modules/audio/baked_speech.gd` resolves files. Errors appear in Godot's output.
Short check: `tests/baked_speech_test.tscn`, `--xr-mode off -- --profile=baked_speech_test`.
