# Continuous stimuli

Every other stimulus in `stimgen` is one-shot: a finite, gated waveform that is triggered, plays, and
ends. The continuous classes are the exception. They produce a *seamlessly loopable block* and own
their own playback — call `start()` and the sound runs until `stop()`.

This guide covers `stimgen.ContinuousTone`, `stimgen.ContinuousNoise`, and the two pieces behind
them. It is both a user guide and a developer reference. Start at
[stimgen_overview.md](stimgen_overview.md) for the package as a whole.

Source classes:

- [+stimgen/ContinuousTone.m](../+stimgen/ContinuousTone.m)
- [+stimgen/ContinuousNoise.m](../+stimgen/ContinuousNoise.m)
- [+stimgen/+continuous/Playable.m](../+stimgen/+continuous/Playable.m) — the mixin
- [+stimgen/+continuous/Stream.m](../+stimgen/+continuous/Stream.m) — the streaming engine

## What These Classes Provide

- **Gapless, indefinite playback** through the sound card, driven by the stimulus object itself.
- **Click-free parameter changes.** Editing `Frequency` (or any other parameter) while running
  crossfades to the new waveform instead of restarting it.
- **Envelope modulation by another `StimType`.** Any stimulus object can act as the modulator; its
  waveform becomes a gain applied to the carrier, either looping continuously or fired one shot at a
  time.

## Quick Start

```matlab
t = stimgen.ContinuousTone;
t.Fs = 48000;          % must be a sound-card rate, see Sample Rate below
t.Frequency = 1000;
t.start;               % sounds indefinitely, fading in over RampDuration
t.Frequency = 2000;    % crossfades; no click
t.stop;                % fades out and releases the device
```

Continuous AM noise, modulated by the envelope of an `AMnoise` object:

```matlab
n = stimgen.ContinuousNoise;
n.Fs = 48000; n.HighPass = 2000; n.LowPass = 8000;

n.EnvelopeSourceClass = "AMnoise";       % builds a live stimgen.AMnoise
n.EnvelopeSource.EnvelopeOnly = true;    % edit the modulator like any stimulus
n.EnvelopeSource.AMRate = 4;
n.EnvelopeMode  = "Loop";
n.EnvelopeDepth = 1;

n.start; pause(5); n.stop
```

## The Architecture

Continuous and discrete stimuli differ in *lifecycle*, not synthesis — `sin(2*pi*f*t)` is the same
either way. So the continuous behavior is a mixin layered onto the existing carrier classes:

```
stimgen.Tone  ──┐
                ├── stimgen.ContinuousTone
stimgen.        │
  continuous.   ┤
  Playable    ──┤
                ├── stimgen.ContinuousNoise
stimgen.Noise ──┘
```

`ContinuousTone` therefore inherits `CalibrationType = "tone"` and `Frequency` from `stimgen.Tone`,
so calibration works unchanged; `ContinuousNoise` inherits `"filter"` from `stimgen.Noise`. Both are
discovered automatically by `stimgen.StimType.list()` and appear in the `StimPlayer` type dropdown,
plot, and serialize like any other stimulus.

`Playable` holds the engine by **composition**, so `stimgen.continuous.Stream` is testable on its own
and knows nothing about stimuli:

```matlab
s = stimgen.continuous.Stream;
s.set_carrier(sin(2*pi*1000*(0:47999)/48000), 48000);
s.start; pause(3); s.stop
```

## Duration Is The Loop-Block Length

This is the single most important difference from the discrete classes. `Duration` does not set how
long the stimulus lasts — playback is indefinite. It sets the length of the block that is looped, and
that has two consequences:

- **Frequency resolution.** `ContinuousTone` snaps `Frequency` to the nearest whole number of cycles
  per block so the block joins to itself with no phase step. The error is bounded by `Fs/(2*N)`:
  ±0.5 Hz for a 1 s block at 48 kHz, ±2 Hz for a 250 ms block. The value actually synthesized is
  reported by `RealizedFrequency`, and any deviation is logged at `vprintf` level 2.
- **Narrow noise bands need long blocks.** `ContinuousNoise` bins are spaced `Fs/N` apart. A band
  narrower than one bin raises `stimgen:ContinuousNoise:EmptyBand`; increase `Duration`.

The default `Duration` is 1 s for both classes, which is a good balance.

## No Gating — Use RampDuration

`ApplyWindow` is forced `false` in both constructors, and `ApplyWindow`, `WindowDuration` and
`WindowMethod` are removed from the GUI. A cosine ramp *inside* a looping block would fire once per
lap, which is exactly the artifact these classes exist to avoid.

Fading is instead applied to the **stream**: `RampDuration` (default 20 ms) fades in on `start()` and
out on `stop()`. `CrossfadeDuration` on the `Stream` (also 20 ms) governs the equal-power crossfade
used when a parameter changes mid-playback.

## How Seamlessness Is Achieved

**`ContinuousTone`** snaps to integer cycles per block, as described above.

**`ContinuousNoise`** synthesizes in the **frequency domain** rather than using the `randn` + `filter`
path of `stimgen.Noise`. That matters: a time-domain FIR has a startup transient and leaves the block
edges mismatched, so the loop would tick once per lap. An inverse FFT of a band-limited random-phase
spectrum is periodic by construction, so it does not.

For the same reason `ContinuousNoise` sets the protected `suppressCalFilter_` flag and folds the
calibration filter into the spectrum as a **magnitude response** instead of letting
`stimgen.StimType/apply_calibration` filter in the time domain. Only the magnitude is used: phase
would merely delay a loop of random-phase noise, and omitting it removes any group-delay compensation
to get wrong.

## Envelope Modulation

| Property | Meaning |
|---|---|
| `EnvelopeSourceClass` | Class name of the modulating stimulus, or `"None"`. Setting it builds a live instance at the carrier's `Fs`, with `ApplyCalibration` off. |
| `EnvelopeSource` | The live modulator object. Edit it like any stimulus; changes reach a running stream immediately. |
| `EnvelopeMode` | `"Off"`, `"Loop"`, or `"OneShot"`. |
| `EnvelopeMethod` | `"Direct"` (default), `"Hilbert"`, or `"RectifyLowpass"`. |
| `EnvelopeLowpass` | Cutoff for `RectifyLowpass` only, Hz. |
| `EnvelopeDepth` | `[0 1]`. Applied gain is `1 - depth + depth*envelope`, matching `stimgen.AMnoise`. |

**Extraction methods.** `Direct` clamps negatives to zero and normalizes — correct for the objects
worth using as modulators (`AMnoise` with `EnvelopeOnly`, `AttackModNoise`, `ClickTrain`), which
already *are* envelopes. `Hilbert` takes `abs(hilbert(x))`, which works on any waveform including a
raw tone. `RectifyLowpass` rectifies and zero-phase low-passes, preserving time alignment.

**Timing.** In `"Loop"` mode the envelope wraps on its **own read pointer**, independent of the
carrier's. The envelope period therefore does not have to divide the carrier block length, and either
can be changed without disturbing the other. In `"OneShot"` mode the carrier runs unmodulated until
`trigger_envelope()` is called, which plays the envelope once and returns the gain to unity.

## Sample Rate

Set `Fs` to a native sound-card rate: **44100, 48000, 88200, 96000, 176400 or 192000 Hz.** Both
constructors default to 48000 rather than inheriting the `stimgen` default of 97656.25 Hz, which is a
TDT rate.

Windows shared-mode audio will *accept* almost any rate and silently resample, so a non-native rate
does not fail — but the resampler destroys the sample-exact loop seam these classes work to produce.
`Stream.open_device_` detects this and warns at `vprintf` level 0. A device that genuinely cannot
open raises `stimgen:continuous:Stream:UnsupportedSampleRate`.

## Use In StimPlayer

Continuous classes appear in the type dropdown and can be added to a bank. Within `StimPlayer`:

- The parameter panel gains a **Start/Stop** button and an **Edit Source…** button that opens the
  modulator's own parameter window.
- The **Play** button toggles the stream rather than doing a blocking preview.
- The trial scheduler **skips** continuous items — they are not trials, and
  `select_next_idx`/`update_buffer` will never trigger one as a one-shot.

## Caveats

- **Sound-card output is not SPL-calibrated.** `apply_calibration` still scales the block to the LUT
  voltage, but `Stream.set_carrier` peak-normalizes before writing to the device (as
  [@StimType/play.m](../+stimgen/@StimType/play.m) does), so sound-card level is relative.
- **Hardware (TDT) continuous output is not supported.** The `HardwareHost` buffer/trigger contract
  is strictly one-shot and zero-pads both ends of the buffer. Continuous output there would need a
  new parameter contract and an RPvds circuit change.
- **`Stream` is not reentrant** and guards itself accordingly. `audioDeviceWriter` blocks when its
  queue is full, and a blocked write lets MATLAB's event queue dispatch the timer callback; without
  the `inFrame_` guard that corrupts the read pointers or releases the device mid-`step`. Preserve
  that guard, and keep `halt_()` retiring the timer *before* the device.
- **`copy()` detaches the stream.** A copied object gets its own (stopped) engine and its own
  modulator instance, so deleting one never silences the other.

## Related Documentation

- [stimgen_overview.md](stimgen_overview.md)
- [stimgen_StimType.md](stimgen_StimType.md)
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md)
- [stimgen_calibration.md](stimgen_calibration.md)
