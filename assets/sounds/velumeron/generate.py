#!/usr/bin/env python3
"""Generate the velumeron sound pack.

The pack is SYNTHESISED, not recorded, and the generator ships with it — so the sounds can be
re-voiced (a different key, a longer tail, a brighter bell) by editing numbers here rather than by
finding whoever made the files.

The design is two PAIRS, and the pairing is the whole idea:

  login / logout   — long (4–6 s), the session beginning and ending. Same chord, opposite motion:
                     login builds upward and brightens; logout falls and settles low.
  lock  / unlock   — short (~0.8 s), the screen going away and coming back. Same two notes,
                     opposite direction, tight decay. A latch, not a fanfare.

So the two pairs can never be confused with each other (5 s vs 0.8 s, chord vs interval), while
inside each pair the direction alone tells you which way the thing went.

On the long ones: the reference is the Windows 95 chime, and what it actually does was MEASURED
rather than remembered, because remembering it gets it wrong. Three findings drive everything
below:

  1. The entry is a CUT, not a swell. Digital silence to −19 dB in 5 ms, full by 13 ms. There is
     no fade-in anywhere in that sound. (Believing otherwise is what made the first attempt here
     sound nothing like it.)
  2. The chord has NO THIRD. F–C–E♭–F–G–B♭–C is a stack of perfect fourths (E♭–B♭–F–C–G). That is
     where the open, unresolved, neither-happy-nor-sad quality comes from; put a third in it and
     it turns into a fanfare.
  3. It gets BRIGHTER as it dies. The spectral centroid climbs from ~1 kHz to ~4 kHz over the six
     seconds: the low end decays first and the shimmer on top outlives it.

And it arrives in three separate hard entries — low bed, then the upper structure ~0.85 s later
(the low root ducking ~15 dB as it lands), then bells on top ~1 s after that.

That STRUCTURE is what is reproduced here. The music is ours: root D instead of F, the colour
withheld from the bed and delivered by the second entry, our own bell voicing and timings. The
original is Brian Eno's and Microsoft's and is not ours to ship — not the file, and not the tune.

Run:  python3 generate.py    → writes *.ogg next to this file
"""

import numpy as np
from scipy.signal import fftconvolve, lfilter, butter, sosfilt
import subprocess, pathlib

SR = 48000
HERE = pathlib.Path(__file__).parent

# D MINOR — and the third is now deliberately IN, which is a reversal.
#
# The quartal reading came from the Windows 95 analysis: no third, so the chord commits to nothing
# and just stands open. That is right for a startup fanfare and wrong for this, because "commits to
# nothing" also means "feels nothing". Liminal is not neutral — it is wistful. It is a place that
# used to have people in it. The minor third (F over D) is what carries that, and without it these
# were four correct, characterless drones.
D2, A2, D3, F3, A3, C4, D4, E4, F4, G4, A4 = \
    73.42, 110.0, 146.83, 174.61, 220.0, 261.63, 293.66, 329.63, 349.23, 392.0, 440.0
C5, D5, E5, F5, A5, D6 = 523.25, 587.33, 659.26, 698.46, 880.0, 1174.66

# Eb sus4 (Eb–Ab–Bb), the pitch set measured on the reference the user picked. No third again, but
# for a different reason than the Windows 95 read: here it is a SEQUENCE, and an arpeggio through a
# sus chord keeps moving without ever landing, which is what makes a startup sound feel like an
# opening rather than an announcement.
EB2, EB3, AB3, BB3, EB4, AB4, BB4, EB5, AB5, BB5 = \
    77.78, 155.56, 207.65, 233.08, 311.13, 415.30, 466.16, 622.25, 830.61, 932.33


def _shape(n, points, sr=SR):
    """Gain curve from (seconds, dB) breakpoints, interpolated in dB.

    Written in dB on purpose: the reference was measured as a dB-against-time table, so the layer
    definitions below can be read straight across against those numbers.
    """
    t = np.arange(n) / sr
    return 10 ** (np.interp(t, [p[0] for p in points], [p[1] for p in points]) / 20.0)


def bell(f, dur, amp=1.0, ratio=1.41, index=5.0, bright=0.30, at=0.0):
    """FM bell (Chowning): an inharmonic modulator ratio is what makes metal sound like metal.

    The modulation index decays FASTER than the amplitude — that is the strike: bright and clangy
    at the attack, settling to a near-sine hum as it rings out. A fixed index just sounds buzzy.
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = index * np.exp(-t / (dur * bright))
    sig = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * ratio * t))
    sig *= np.exp(-t / (dur * 0.34)) * amp
    sig[:24] *= np.linspace(0, 1, 24)          # kill the DC step at the very onset
    return _place(sig, at)


# Harmonic recipes. A pad is only ever as interesting as its overtones, and these two are opposites:
# GLASS has enough upper partials to sparkle, WOOL is nearly a sine with a whisper of the fifth
# above it. The long sounds are built entirely out of WOOL — see the note on make_login.
GLASS = (1.0, 0.35, 0.16, 0.08, 0.05, 0.03)
WOOL  = (1.0, 0.16, 0.05, 0.015)


def pad(freqs, at, dur, gains, amp=1.0, attack=0.012, detune=0.004, drift=0.0018,
        glide=0.0, tone=GLASS, voices=2, wow=0.9, seed=0):
    """Sustained chord: each note a small harmonic stack, detuned copies for movement.

    `gains` is the dB-against-time schedule from `_shape` and does all the real shaping: the duck
    under the second entry, the plateau, the decay.

    `drift` and `wow` are the tape. `drift` is how far each voice wanders (as a fraction — 0.010 is
    about 17 cents, which is a LOT and is meant to be), `wow` how fast in Hz. Slow and wide is the
    sound of a tape that has been played too many times; fast and narrow is a chorus pedal. The
    difference between the two is most of the difference between "haunting" and "eighties".

    `voices` is how many detuned copies per partial. Three beat against each other in a way two
    cannot: two voices give you a steady throb, three give you something that never quite repeats.

    `glide` bends every note by that fraction over the whole layer — a small downward glide is
    what makes the logout read as winding down rather than merely stopping.
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    bend = np.exp(np.linspace(0.0, np.log(1.0 + glide) if glide else 0.0, n))
    spread = np.linspace(-detune, detune, voices) if voices > 1 else [0.0]
    for f in freqs:
        for k, h in enumerate(tone, start=1):
            for d in spread:
                # Two LFOs per voice at unrelated rates: one wander never lines up with the next,
                # so the beating never settles into a pattern the ear can lock onto.
                lfo = (1.0 + drift * np.sin(2 * np.pi * rng.uniform(0.13, 0.42) * wow * t + rng.uniform(0, 6.28))
                           + drift * 0.6 * np.sin(2 * np.pi * rng.uniform(0.5, 1.1) * wow * t + rng.uniform(0, 6.28)))
                ph = 2 * np.pi * np.cumsum(f * k * (1.0 + d) * bend * lfo) / SR + rng.uniform(0, 6.28)
                out += h * np.sin(ph)                       # random start phase: no summed spike
    out /= max(1.0, len(freqs) * voices)
    env = _shape(n, gains)
    a = int(attack * SR)
    env[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    return _place(out * env * amp, at)


def voice(f, at, dur, amp=1.0, attack=0.09, tail=0.45, detune=0.006, drift=0.010,
          wow=0.5, tone=WOOL, seed=0):
    """A single sung note: soft in, long out, badly-tuned against itself.

    This is what replaced `bell` everywhere the sound is meant to be HEARD rather than noticed. A
    bell announces; a voice remembers. Same tape treatment as `pad` (three detuned copies, two slow
    LFOs each) so a melody note and the chord under it are made of the same material — a melody in a
    different timbre from its own accompaniment is the fastest way to sound assembled.

    `tail` is the decay as a fraction of `dur`: bigger = it hangs on longer before it lets go.
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for k, h in enumerate(tone, start=1):
        for d in np.linspace(-detune, detune, 3):
            lfo = (1.0 + drift * np.sin(2 * np.pi * rng.uniform(0.13, 0.42) * wow * t + rng.uniform(0, 6.28))
                       + drift * 0.6 * np.sin(2 * np.pi * rng.uniform(0.5, 1.1) * wow * t + rng.uniform(0, 6.28)))
            out += h * np.sin(2 * np.pi * np.cumsum(f * k * (1.0 + d) * lfo) / SR + rng.uniform(0, 6.28))
    out /= 3.0
    env = np.exp(-t / (dur * tail))
    a = int(attack * SR)
    if a > 0:
        env[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    return _place(out * env * amp, at)


def lowpass(x, fc, order=2):
    """Gentle roll-off. Not an effect — a wall.

    Liminal is a sound you are hearing from the next room, and the next room takes the top off
    everything. It is also what stops a detuned stack of sines from turning glassy the moment more
    than three of them are sounding at once.
    """
    return sosfilt(butter(order, min(fc / (SR / 2), 0.99), btype="low", output="sos"), x)

def rhodes(f, at, dur, amp=1.0, strike=0.16, tail=0.42, trem=0.22, tremHz=5.2,
           detune=0.004, drift=0.006, wow=0.5, seed=0):
    """An electric piano tine, not an oscillator.

    A Rhodes is a metal tine struck by a hammer with a pickup next to it, and three things fall out
    of that — all three are what make it read as 1973 rather than as a synth:

      · the STRIKE. A short, bright, inharmonic chirp as the tine is hit, gone in ~60 ms. It is the
        whole attack; without it a Rhodes is just a sine and sounds like one.
      · a fat SECOND HARMONIC that dies faster than the fundamental, so the note darkens as it
        rings out instead of holding one colour.
      · TREMOLO. Not an effect added afterwards — the instrument has it built in, and its slow
        amplitude sway is most of what people hear as "electric piano".

    Everything here goes through `saturate` afterwards, which is the fourth thing: tape.
    """
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for d in (1.0 - detune, 1.0 + detune):
        lfo = 1.0 + drift * np.sin(2 * np.pi * rng.uniform(0.15, 0.45) * wow * t + rng.uniform(0, 6.28))
        ph  = 2 * np.pi * np.cumsum(f * d * lfo) / SR + rng.uniform(0, 6.28)
        out += np.sin(ph)                                        # fundamental
        out += 0.34 * np.sin(2 * ph) * np.exp(-t / (dur * 0.20))  # 2nd, decaying faster
        out += 0.10 * np.sin(3 * ph) * np.exp(-t / (dur * 0.12))
    out /= 2.0
    # The strike: inharmonic (6.4× is not a harmonic), bright, and over almost at once.
    out += 0.20 * np.sin(2 * np.pi * f * 6.4 * t) * np.exp(-t / max(1e-4, strike * 0.22))
    out += 0.09 * np.sin(2 * np.pi * f * 9.7 * t) * np.exp(-t / max(1e-4, strike * 0.14))

    env = np.exp(-t / (dur * tail))
    a = int(0.006 * SR)                     # 6 ms — a hammer, not a fade
    env[:a] *= np.linspace(0, 1, a)
    out *= env
    out *= 1.0 - trem * 0.5 * (1.0 - np.cos(2 * np.pi * tremHz * t))   # tremolo, never below 1-trem
    return _place(out * amp, at)


def amp_trem(x, depth=0.16, hz=5.0, seed=0):
    """Tremolo across the WHOLE mix — the amplifier's, not the instrument's.

    A Rhodes tremolo sways the piano; a combo amp sways everything plugged into it, pads included.
    Running it on the finished mix is what ties the melody and the chord under it into one performance
    instead of two layers that happen to be playing at once. Shallow on purpose: this should be felt
    as breathing, not heard as an effect.
    """
    t = np.arange(len(x)) / SR
    return x * (1.0 - depth * 0.5 * (1.0 - np.cos(2 * np.pi * hz * t)))


def saturate(x, drive=1.8):
    """Tape. Soft-knee compression of the peaks plus the harmonics that come with it.

    This is the single biggest difference between "synthesised" and "recorded in 1974". A clean sum
    of sines has no history; running it into something that cannot quite keep up gives it one.
    """
    return np.tanh(x * drive) / np.tanh(drive)


def spring(x, wet=0.30, seed=5):
    """Spring reverb: the tank on the back of every combo amp of the era.

    Not a room — a coil of wire that a signal travels down and bounces back along, which is why it
    CHIRPS: high frequencies arrive before low ones. Modelled as a short chain of dispersive
    all-pass sections plus a handful of discrete bounces, rather than as smoothed noise. A plate or
    hall would be the wrong century.
    """
    rng = np.random.default_rng(seed)
    y = x.copy()
    for g, d in ((0.62, 137), (0.55, 271), (0.48, 419), (0.41, 653)):   # dispersion
        pad_ = np.zeros(d)
        y = np.concatenate([pad_, y])[:len(x)] * g + y * (1 - g * 0.5)
    ech = np.zeros(len(x))
    for k, (d, g) in enumerate(((1789, 0.55), (3571, 0.34), (5303, 0.20), (7013, 0.12))):
        if d < len(x):
            ech[d:] += y[:len(x) - d] * g * rng.uniform(0.9, 1.1)
    y = lowpass(y + ech, 3400, order=2)
    y /= max(1e-9, np.abs(y).max())
    return x + wet * y




def air(at, dur, gains, amp=1.0, fc=1400.0, seed=0):
    """Filtered noise: the tape hiss, the room, the ventilation in the empty building.

    Almost inaudible on its own and the first thing you miss when it is gone — without it the
    silence between the notes is DIGITAL silence, and nothing recorded has ever sounded like that.
    """
    n = int(dur * SR)
    rng = np.random.default_rng(seed)
    x = lowpass(rng.standard_normal(n), fc, order=2)
    x = lowpass(x, fc * 1.6, order=2)
    x /= np.abs(x).max()
    return _place(x * _shape(n, gains) * amp, at)


def _place(sig, at):
    """Pad a fragment with leading silence so pieces can be written at absolute times."""
    lead = int(at * SR)
    return np.concatenate([np.zeros(lead), sig]) if lead else sig


def mix(parts, dur):
    """Sum fragments of different lengths into one buffer of `dur` seconds."""
    out = np.zeros(int(dur * SR))
    for p in parts:
        n = min(len(p), len(out))
        out[:n] += p[:n]
    return out


def reverb(x, tail=1.9, decay=3.4, wet=0.34, bright=0.25, seed=7):
    """Exponentially decaying filtered noise as an impulse response.

    Not a real room, but the only property that matters here is a smooth tail that outlives the
    notes — that is what turns a chord into an arrival. Two seeds (left/right) give width for free.

    `bright` sets how much top the tail keeps. Low values are the safe choice (bright reverb sounds
    cheap), but the login needs a high one: the reference's last second is almost nothing but high
    shimmer, and a dark tail cannot end that way.
    """
    rng = np.random.default_rng(seed)
    n = int(tail * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-decay * t)
    ir = lfilter([bright], [1.0, -(1.0 - bright)], ir)
    ir /= np.abs(ir).max()
    return x + wet * fftconvolve(x, ir)[:len(x)]


def stereo(x, wet=0.38, tail=1.9, decay=3.4, bright=0.25, tank=0.0):
    """Same source, two different rooms — a wide tail with a centred, mono-safe dry signal.

    `tank` mixes in the SPRING on top of the room. A plate/hall alone is the sound of a nice studio;
    the spring is the sound of the amplifier the thing was played through, and that is the one that
    places this in the right decade. Two different seeds again, so the tank is wide too.
    """
    l = reverb(x, seed=11, wet=wet, tail=tail, decay=decay, bright=bright)
    r = reverb(x, seed=29, wet=wet, tail=tail, decay=decay, bright=bright)
    if tank > 0:
        l = spring(l, wet=tank, seed=5)
        r = spring(r, wet=tank, seed=9)
    return np.stack([l, r], axis=1)


def write(name, sig, peak_db=-6.0):
    sig = sig / np.abs(sig).max() * (10 ** (peak_db / 20.0))
    sig[:64] *= np.linspace(0, 1, 64)[:, None]          # absolute guarantee of no click
    sig[-2400:] *= np.linspace(1, 0, 2400)[:, None]     # …and none at the end
    raw = (np.clip(sig, -1, 1) * 32767).astype("<i2").tobytes()
    out = HERE / f"{name}.ogg"
    subprocess.run(
        ["ffmpeg", "-nostdin", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "pipe:0",
         "-c:a", "libvorbis", "-q:a", "5", str(out), "-loglevel", "error"],
        input=raw, check=True)
    print(f"  {name}.ogg  {len(sig)/SR:.2f}s  {out.stat().st_size/1024:.0f} KB")


# ── login — arrival ──────────────────────────────────────────────────────────────
# A CHORD ALONE IS NOT A SOUND, it is a bed. Every version of this before had only the bed: a held
# D-something, tape-warped, reverberant, and completely inert — nothing ever happened in it. What
# liminal music actually has over its drones is a handful of notes, played slowly, that do not
# resolve to anything in a hurry. Three of them is enough.
#
# The motif rises A → C → D and lands on the root, which is the only "arrival" here; underneath it
# a D minor bed, and the third is what keeps the whole thing wistful rather than merely open.
def make_login():
    dur = 6.8
    # 0.22 s apart — the reference runs ~20 strikes in 7.7 s, and THAT is what was missing: three
    # slow notes over a pad is a drone with punctuation, not a piece of music. It climbs Eb-Bb-Eb-Ab
    # -Bb-Eb through two octaves and then simply stops, leaving the top note and the room.
    steps = [(EB3, 0.10), (BB3, 0.32), (EB4, 0.54), (AB4, 0.76),
             (BB4, 0.98), (EB5, 1.24), (BB4, 1.52), (EB5, 1.80)]
    notes = [rhodes(f, at=a, dur=2.6 + 0.9 * (i / len(steps)), amp=0.30 + 0.05 * (i % 3),
                    seed=20 + i, tail=0.34 + 0.03 * i, trem=0.18)
             for i, (f, a) in enumerate(steps)]
    return lowpass(amp_trem(saturate(mix(notes + [
        pad([EB3, BB3], at=0.06, dur=6.0, amp=0.30, seed=3, tone=WOOL, voices=3,
            attack=0.30, detune=0.006, drift=0.008, wow=0.5, gains=[
                (0.00, -8), (1.00, 0), (3.60, -3), (5.00, -13), (6.00, -90)]),
        pad([AB3], at=1.00, dur=4.8, amp=0.18, seed=13, tone=WOOL, voices=3,
            attack=0.40, detune=0.008, drift=0.010, wow=0.45, gains=[
                (0.00, -9), (1.20, 0), (3.00, -6), (4.80, -90)]),
        pad([EB2], at=0.06, dur=5.2, amp=0.07, seed=17, tone=WOOL, voices=2,
            attack=0.30, drift=0.004, wow=0.4, gains=[
                (0.00, -8), (1.00, 0), (3.20, -11), (5.20, -90)]),
        air(at=0.00, dur=6.8, amp=0.045, fc=1200, seed=77, gains=[
            (0.00, -14), (0.30, -2), (1.20, 0), (4.80, -6), (6.10, -17), (6.80, -90)]),
    ], dur)), depth=0.30, hz=4.6), 2600)


# ── logout — departure ───────────────────────────────────────────────────────────
# The same three notes, walked back down: D → C → A. Shorter, and it settles onto the low root
# instead of hanging — leaving should sound finished, arriving should not.
def make_logout():
    dur = 4.8
    steps = [(EB5, 0.08), (BB4, 0.30), (AB4, 0.52), (EB4, 0.74), (BB3, 1.00), (EB3, 1.28)]
    notes = [rhodes(f, at=a, dur=2.2 + 0.5 * (i / len(steps)), amp=0.30 + 0.04 * (i % 3),
                    seed=40 + i, tail=0.34, trem=0.18)
             for i, (f, a) in enumerate(steps)]
    return lowpass(amp_trem(saturate(mix(notes + [
        pad([EB3, BB3], at=0.06, dur=4.2, amp=0.30, seed=5, tone=WOOL, voices=3,
            attack=0.22, detune=0.007, drift=0.009, wow=0.5, glide=-0.007, gains=[
                (0.00, -5), (0.90, 0), (2.60, -5), (3.40, -13), (4.20, -90)]),
        pad([EB2, BB3], at=0.60, dur=3.8, amp=0.14, seed=27, tone=WOOL, voices=2,
            attack=0.30, drift=0.005, wow=0.4, glide=-0.006, gains=[
                (0.00, -11), (1.50, 0), (2.60, -6), (3.80, -90)]),
        air(at=0.00, dur=4.8, amp=0.042, fc=950, seed=83, gains=[
            (0.00, -14), (0.25, -2), (1.00, 0), (3.00, -7), (4.20, -18), (4.80, -90)]),
    ], dur)), depth=0.26, hz=4.2), 2200)


# ── the short ones ───────────────────────────────────────────────────────────────
# Same instrument, same room, a fraction of the length. These are heard many times a day, so they
# are built to be noticed once and then to stop existing: two notes at most, no low end to thud,
# and a tail short enough that it is over before you have thought about it.
#
# They were FM bells — the one thing the long sounds were rebuilt to get away from, left behind on
# the sounds you actually hear most often. Direction still carries the meaning: down = closed,
# up = open.
def _pair(f1, f2, gap, dur, amp=0.5, tail=0.34, fc=2600):
    return lowpass(saturate(mix([
        rhodes(f1, at=0.00, dur=dur, amp=amp,        seed=41, tail=tail, trem=0.16, strike=0.13),
        rhodes(f2, at=gap,  dur=dur, amp=amp * 0.92, seed=42, tail=tail, trem=0.18, strike=0.13),
        air(at=0.00, dur=dur + gap, amp=0.020, fc=1300, seed=43, gains=[
            (0.00, -20), (0.05, -6), (0.40, -12), (dur + gap, -90)]),
    ], dur + gap), 2.2), fc)

def make_lock():   return _pair(A4, F4, gap=0.16, dur=1.05)   # falling — it shuts
def make_unlock(): return _pair(F4, A4, gap=0.16, dur=1.05)   # rising  — it opens

# Notification: ONE note, mid-register, gone in under a second. A second note would make it an
# event worth turning around for, and most notifications are not.
def make_notification():
    return lowpass(saturate(mix([
        rhodes(A4, at=0.00, dur=0.85, amp=0.52, seed=51, tail=0.28, trem=0.14, strike=0.12),
        rhodes(D5, at=0.00, dur=0.85, amp=0.14, seed=52, tail=0.24, trem=0.14, strike=0.10),
        air(at=0.00, dur=0.85, amp=0.018, fc=1400, seed=53, gains=[
            (0.00, -20), (0.04, -7), (0.35, -14), (0.85, -90)]),
    ], 0.85), 2.0), 2800)

# Critical: a MINOR SECOND, F against E, held together. It is the same voice and the same room, so
# it still belongs to the shell — but two notes a semitone apart do not sit still, and that is the
# whole message. No extra loudness, no siren: the interval does the work.
def make_notification_critical():
    return lowpass(saturate(mix([
        rhodes(F5, at=0.00, dur=1.5, amp=0.46, seed=61, tail=0.32, trem=0.16, strike=0.12),
        rhodes(E5, at=0.10, dur=1.5, amp=0.42, seed=62, tail=0.34, trem=0.16, strike=0.12),
        rhodes(A4, at=0.22, dur=1.5, amp=0.24, seed=63, tail=0.38, trem=0.18, strike=0.11),
        air(at=0.00, dur=1.6, amp=0.024, fc=1500, seed=64, gains=[
            (0.00, -20), (0.04, -5), (0.50, -12), (1.60, -90)]),
    ], 1.6), 2.0), 3000)


if __name__ == "__main__":
    print("velumeron sound pack:")
    # Each sound gets its own room. The login's is long and bright so it can evaporate upward; the
    # logout's is shorter and darker so it settles; the latches are nearly dry, because a short
    # sound with a long tail just sounds like a mistake.
    for name, fn, peak, room in (
            ("login",  make_login,  -6.0, dict(wet=0.50, tail=3.4, decay=2.0, bright=0.24, tank=0.26)),
            ("logout", make_logout, -6.5, dict(wet=0.44, tail=2.6, decay=2.6, bright=0.20, tank=0.24)),
            # The short ones get a SMALL room. The same long tail that makes the login feel like a
            # place makes a notification feel like it happened somewhere else.
            ("lock",   make_lock,   -10.0, dict(wet=0.20, tail=1.0, decay=4.5, bright=0.28, tank=0.20)),
            ("unlock", make_unlock, -10.0, dict(wet=0.20, tail=1.0, decay=4.5, bright=0.28, tank=0.20)),
            ("notification",          make_notification,          -12.0,
             dict(wet=0.18, tail=0.8, decay=5.2, bright=0.28, tank=0.16)),
            ("notification-critical", make_notification_critical, -10.0,
             dict(wet=0.22, tail=1.1, decay=4.4, bright=0.26, tank=0.18))):
        write(name, stereo(fn(), **room), peak_db=peak)
