"""Original background music and sound effects for 甜点三连, synthesized here.
No samples, no third-party melodies. Deterministic: same output every run.
Run: python3 tools/make_audio.py  (needs numpy)
"""
import json, math, struct, hashlib, pathlib
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
SR = 32000
rng = np.random.default_rng(20261107)

def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)

def env(n, attack, release, decay=0.0):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    if decay:
        e *= np.exp(-t * decay)
    tail = np.minimum(1.0, (n / SR - t) / max(release, 1e-4))
    return e * np.clip(tail, 0, 1)

def tone(freq, dur, kind="marimba", amp=0.3):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if kind == "marimba":      # warm wooden mallet
        y = np.sin(2*np.pi*freq*t) + 0.35*np.sin(2*np.pi*freq*4*t)*np.exp(-t*30)
        y *= env(n, 0.004, 0.04, decay=7)
    elif kind == "glock":      # bright bell for sparkles
        y = np.sin(2*np.pi*freq*t) + 0.5*np.sin(2*np.pi*freq*2.76*t)*np.exp(-t*9) + 0.25*np.sin(2*np.pi*freq*5.4*t)*np.exp(-t*20)
        y *= env(n, 0.002, 0.05, decay=4)
    elif kind == "pluck":      # bouncy bass
        y = np.sin(2*np.pi*freq*t) + 0.3*np.sin(2*np.pi*freq*2*t) + 0.1*np.sin(2*np.pi*freq*3*t)
        y *= env(n, 0.006, 0.05, decay=6)
    elif kind == "keys":       # soft chord pad
        y = np.sin(2*np.pi*freq*t) + 0.2*np.sin(2*np.pi*freq*2*t) + 0.05*np.sin(2*np.pi*freq*3.01*t)
        y *= env(n, 0.03, 0.12, decay=1.6)
    else:
        raise ValueError(kind)
    return y * amp

def place(buf, sig, start, gain=1.0, pan=0.0, wrap=True):
    i0 = int(start * SR)
    idx = np.arange(len(sig)) + i0
    if wrap:
        idx %= len(buf)
    else:
        keep = idx < len(buf); idx = idx[keep]; sig = sig[keep]
    l = math.sqrt((1 - pan) / 2); r = math.sqrt((1 + pan) / 2)
    np.add.at(buf[:, 0], idx, sig * gain * l)
    np.add.at(buf[:, 1], idx, sig * gain * r)

def drum(kind, dur=0.18):
    n = int(dur * SR); t = np.arange(n) / SR
    if kind == "kick":
        y = np.sin(2*np.pi*(55*t + 90*(1-np.exp(-t*30))/30)) * np.exp(-t*18)
    elif kind == "clap":
        noise = rng.uniform(-1, 1, n)
        y = noise * (np.exp(-t*40) + 0.6*np.exp(-np.maximum(t-0.012, 0)*45)*(t > 0.012))
        y = np.convolve(y, [0.25, 0.5, 0.25], mode="same")
    elif kind == "shaker":
        noise = rng.uniform(-1, 1, n)
        y = (noise - np.convolve(noise, np.ones(8)/8, mode="same")) * np.exp(-t*60)
    else:
        raise ValueError(kind)
    return y * env(n, 0.002, 0.02)

def write_wav(path, data, loop=False):
    """16-bit stereo or mono WAV; looping files carry a 'smpl' chunk so Godot loops them."""
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2")
    ch = 1 if pcm.ndim == 1 else pcm.shape[1]
    frames = len(pcm)
    raw = pcm.tobytes()
    fmt = struct.pack("<HHIIHH", 1, ch, SR, SR*ch*2, ch*2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9/SR), 60, 0, 0, 0, 1, 0) + struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    chunks += b"data" + struct.pack("<I", len(raw)) + raw
    path.write_bytes(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)

def master(x, peak=0.85):
    return x / max(1e-9, np.max(np.abs(x))) * peak

# ------------------------------------------------------------------ music
BPM = 124
BEAT = 60 / BPM
BARS = 16
N = int(round(BARS * 4 * BEAT * SR))
mix = np.zeros((N, 2))

# Bright major progression, two 8-bar phrases: C G Am F | C G F G // F G Em Am | Dm G C C
PROG = [(48, [60, 64, 67]), (43, [59, 62, 67]), (45, [60, 64, 69]), (41, [60, 65, 69]),
        (48, [60, 64, 67]), (43, [59, 62, 67]), (41, [60, 65, 69]), (43, [59, 62, 67]),
        (41, [60, 65, 69]), (43, [59, 62, 67]), (40, [59, 64, 67]), (45, [60, 64, 69]),
        (38, [57, 62, 65]), (43, [59, 62, 67]), (48, [60, 64, 67]), (48, [60, 64, 67])]
# Melody: (bar, beat, midi, beats) — bouncy, mostly stepwise, answers itself in phrase 2.
MEL = [
 (0,0,76,.5),(0,.5,79,.5),(0,1,81,.5),(0,1.5,79,.5),(0,2,76,1),(0,3,72,1),
 (1,0,74,.5),(1,.5,76,.5),(1,1,79,1),(1,2,74,1.5),(1,3.5,71,.5),
 (2,0,72,.5),(2,.5,76,.5),(2,1,81,1),(2,2,79,.5),(2,2.5,76,.5),(2,3,72,1),
 (3,0,77,1),(3,1,76,.5),(3,1.5,74,.5),(3,2,72,2),
 (4,0,76,.5),(4,.5,79,.5),(4,1,84,1),(4,2,83,.5),(4,2.5,81,.5),(4,3,79,1),
 (5,0,79,.5),(5,.5,81,.5),(5,1,79,.5),(5,1.5,76,.5),(5,2,74,2),
 (6,0,72,.5),(6,.5,74,.5),(6,1,77,1),(6,2,81,1),(6,3,79,1),
 (7,0,79,1.5),(7,1.5,76,.5),(7,2,74,1),(7,3,79,1),
 (8,0,81,.5),(8,.5,79,.5),(8,1,77,1),(8,2,76,.5),(8,2.5,77,.5),(8,3,81,1),
 (9,0,79,1),(9,1,76,.5),(9,1.5,74,.5),(9,2,71,1),(9,3,74,1),
 (10,0,76,.5),(10,.5,79,.5),(10,1,83,1),(10,2,79,.5),(10,2.5,76,.5),(10,3,71,1),
 (11,0,72,1),(11,1,76,1),(11,2,81,2),
 (12,0,77,.5),(12,.5,76,.5),(12,1,74,1),(12,2,69,.5),(12,2.5,72,.5),(12,3,77,1),
 (13,0,79,.5),(13,.5,81,.5),(13,1,83,1),(13,2,86,1),(13,3,83,1),
 (14,0,84,1),(14,1,79,.5),(14,1.5,76,.5),(14,2,72,1),(14,3,76,.5),(14,3.5,79,.5),
 (15,0,84,2),(15,2,79,.5),(15,2.5,81,.5),(15,3,79,.5),(15,3.5,76,.5),
]

def at(bar, beat):
    return (bar * 4 + beat) * BEAT

for bar, (bass, chord) in enumerate(PROG):
    # Bouncy bass: root, fifth, octave pattern.
    for beat, off in [(0, 0), (1, 7), (2, 12), (3, 7)]:
        place(mix, tone(midi_hz(bass + off), BEAT * 0.9, "pluck", 0.32), at(bar, beat), pan=-0.1)
    # Off-beat chord stabs.
    for beat in [0.5, 1.5, 2.5, 3.5]:
        for i, m in enumerate(chord):
            place(mix, tone(midi_hz(m), BEAT * 0.45, "keys", 0.07), at(bar, beat), pan=(-0.3, 0, 0.3)[i])
    # Drums.
    for beat in [0, 2]:
        place(mix, drum("kick", 0.22), at(bar, beat), 0.55)
    for beat in [1, 3]:
        place(mix, drum("clap", 0.16), at(bar, beat), 0.22, pan=0.1)
    for k in range(8):
        place(mix, drum("shaker", 0.08), at(bar, k * 0.5), 0.10 if k % 2 else 0.06, pan=0.4)

for bar, beat, m, beats in MEL:
    dur = max(0.18, beats * BEAT * 1.1)
    place(mix, tone(midi_hz(m), dur, "marimba", 0.34), at(bar, beat), pan=0.05)
    # A soft bell an octave up on long notes for sparkle.
    if beats >= 1:
        place(mix, tone(midi_hz(m + 12), dur * 0.8, "glock", 0.06), at(bar, beat), pan=0.25)

# Light stereo echo, wrapped so the loop is seamless.
echo = np.roll(mix[:, ::-1], int(0.18 * SR), axis=0) * 0.18
mix = master(mix + echo, 0.8)
write_wav(OUT / "bgm_game.wav", mix, loop=True)

# ------------------------------------------------------------------ effects
def fx_tap():
    n = int(0.09 * SR); t = np.arange(n) / SR
    f = 880 * np.exp(-t * 9)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.03, decay=28)
    return master(y, 0.7)

def fx_match():
    out = np.zeros(int(0.55 * SR))
    for i, m in enumerate([84, 88, 91]):
        s = tone(midi_hz(m), 0.42, "glock", 0.5)
        i0 = int(i * 0.06 * SR)
        out[i0:i0 + len(s)] += s[: len(out) - i0]
    sp = rng.uniform(-1, 1, len(out)) * np.exp(-np.arange(len(out)) / SR * 14) * 0.05
    return master(out + sp, 0.75)

def fx_win():
    dur = 2.2; out = np.zeros((int(dur * SR), 2))
    seq = [(0.00, 72), (0.11, 76), (0.22, 79), (0.33, 84)]
    for t0, m in seq:
        place(out, tone(midi_hz(m), 0.35, "marimba", 0.5), t0, wrap=False)
    for m in [72, 76, 79, 84, 88]:
        place(out, tone(midi_hz(m), 1.6, "glock", 0.18), 0.48, pan=(m - 80) / 20, wrap=False)
    for m in [48, 55, 60]:
        place(out, tone(midi_hz(m), 1.4, "keys", 0.25), 0.48, wrap=False)
    place(out, drum("kick", 0.25), 0.48, 0.6, wrap=False)
    return master(out, 0.85)

def fx_lose():
    out = np.zeros(int(0.9 * SR))
    for i, m in enumerate([67, 64, 60]):
        s = tone(midi_hz(m), 0.5, "marimba", 0.5)
        i0 = int(i * 0.18 * SR)
        out[i0:i0 + len(s)] += s[: len(out) - i0]
    return master(out, 0.6)

def fx_booster():
    n = int(0.4 * SR); t = np.arange(n) / SR
    f = 500 + 1400 * t / 0.4
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.01, 0.12, decay=4) * 0.5
    y += rng.uniform(-1, 1, n) * np.exp(-t * 12) * 0.08
    return master(y, 0.6)

def fx_nope():
    n = int(0.16 * SR); t = np.arange(n) / SR
    y = (np.sin(2 * np.pi * 220 * t) + 0.5 * np.sin(2 * np.pi * 233 * t)) * env(n, 0.004, 0.05, decay=18)
    return master(y, 0.45)

def fx_unlock():
    out = np.zeros(int(0.5 * SR))
    for i, m in enumerate([91, 96]):
        s = tone(midi_hz(m), 0.35, "glock", 0.5)
        i0 = int(i * 0.08 * SR)
        out[i0:i0 + len(s)] += s[: len(out) - i0]
    return master(out, 0.6)

for name, fn in [("tap", fx_tap), ("match", fx_match), ("win", fx_win), ("lose", fx_lose),
                 ("booster", fx_booster), ("nope", fx_nope), ("unlock", fx_unlock)]:
    y = fn()
    fade = int(0.005 * SR)
    ramp = np.linspace(1.0, 0.0, fade)
    y[-fade:] = (y[-fade:].T * ramp).T  # no click at the end
    write_wav(OUT / f"sfx_{name}.wav", y)

manifest = {"generator": "tools/make_audio.py", "original_composition": True, "external_samples": False,
            "sample_rate": SR, "bgm_bpm": BPM, "bgm_seconds": round(N / SR, 2),
            "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.glob("*.wav"))}}
(OUT / "AUDIO_SOURCES.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
print(json.dumps(manifest, ensure_ascii=False, indent=1))
