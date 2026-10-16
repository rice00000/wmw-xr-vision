"""Native desktop speech -> PCM WAV. No Godot or cache logic lives here."""
import subprocess
import sys


def synthesizer(voices, platform=sys.platform):
    if platform not in ("darwin", "win32"):
        raise RuntimeError("Speech authoring supports Windows and macOS. Cached audio plays everywhere.")
    settings = voices[platform]
    if platform == "darwin":
        def write(text, path):
            subprocess.run(["/usr/bin/say", "-v", settings["name"], "-r", str(settings["rate"]),
                            "--file-format=WAVE", "--data-format=LEI16@22050", "-o", str(path), "-f", "-"],
                           input=text, text=True, check=True, capture_output=True)
        return write
    try:
        from win32com.client import Dispatch
    except ImportError:
        raise RuntimeError("Install the Windows adapter: python -m pip install -r tools/requirements.txt") from None
    voice = Dispatch("SAPI.SpVoice")
    tokens = list(voice.GetVoices())
    matches = [token for token in tokens if token.GetDescription().startswith(settings["name"])]
    if not matches:
        raise RuntimeError("Voice not installed. Available: " + ", ".join(t.GetDescription() for t in tokens))
    voice.Voice = matches[0]
    voice.Rate = settings["rate"]
    voice.AllowAudioOutputFormatChangesOnNextSet = False

    def write(text, path):
        stream = Dispatch("SAPI.SpFileStream")
        stream.Format.Type = 22 # SAFT22kHz16BitMono
        stream.Open(str(path), 3) # SSFMCreateForWrite
        try:
            voice.AudioOutputStream = stream
            voice.Speak(text, 16) # SVSFIsNotXML: authored text is always literal.
        finally:
            stream.Close()
    return write
