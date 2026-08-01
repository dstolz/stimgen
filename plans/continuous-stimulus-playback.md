# Continuous (gapless) stimulus playback for stimgen

## Context

Every stimulus in `stimgen` today is strictly one-shot and finite. `StimType.Signal` is a fixed-length
vector; `@StimType/play.m` creates a fresh `audioplayer` per call and busy-waits for it to finish;
`@StimPlayer/update_buffer.m` writes a zero-padded one-shot buffer and `trigger_stim_playback.m`
pulses a trigger. `StimPlay.ISI` is `mustBePositive`, so even a zero-gap train is inexpressible.
There is no looping, streaming, or background-carrier concept anywhere in the repo.

The need: a stimulus that **plays continuously** — a sustained tone or filtered noise that starts,
runs indefinitely, and stops — where the **object itself owns the playback lifecycle**, and whose
amplitude can optionally be modulated by the **envelope of another `StimType` object**.

Outcome: two new stimulus classes (`ContinuousTone`, `ContinuousNoise`) that appear automatically in
every existing GUI dropdown, plot/calibrate/serialize like any other stimulus, and gain
`start()` / `stop()` plus envelope modulation.

### Decisions already made
- **Backend:** sound-card streaming only. Hardware (TDT) continuous output would need a new
  `HardwareHost` parameter contract *and* an RPvds circuit change in EPsych — out of scope here.
- **Envelope extraction:** user-selectable (`Direct` default, `Hilbert`, `RectifyLowpass`).
- **Envelope timing:** selectable looped *or* one-shot triggered.

---

## Class shape: mixin + composed engine (the deliberation)

The difference between a continuous and a discrete stimulus is **lifecycle, not synthesis**.
`sin(2*pi*f*t)` is the same math either way. What actually changes is: (1) the block must be
*seamlessly loopable*, (2) it must not be internally gated, (3) there is a stream to start and stop.
That is a cross-cutting concern layered onto existing synthesis — a mixin.

**Rejected — one class with a `CarrierType` dropdown.** Duplicates `Tone`/`Noise` synthesis
(including `Noise`'s `designfilt` handling at [Noise.m:67-78](+stimgen/Noise.m#L67-L78)), shows dead
widgets for the unselected carrier in the flat generated grid, and makes every future carrier a
`switch` edit. Least extensible of the three.

**Rejected — one class owning a nested carrier object.** More general, but it pays everywhere:
`create_gui` builds a flat grid keyed by `Tag = propName` and `interpret_gui` writes `obj.(src.Tag)`
([interpret_gui.m:21](+stimgen/@StimType/interpret_gui.m#L21)), so nested properties need changes to
shared `@StimType` code all seven existing classes depend on; `apply_calibration` reads
`obj.CalibrationType` and `obj.Frequency` off the object itself
([apply_calibration.m:23-39](+stimgen/@StimType/apply_calibration.m#L23-L39)) so calibration needs
forwarding; `toStruct`/`UserProperties` need nesting; and `StimType.list()` would offer one generic
entry instead of the carrier being a first-class choice.

**Chosen — mixin.** `ContinuousTone < stimgen.Tone & stimgen.continuous.Playable` inherits
`CalibrationType = "tone"` plus `Frequency`, so calibration works untouched. `ContinuousNoise <
stimgen.Noise & ...` inherits `"filter"` and the `digFilter` path. Both auto-appear in
`StimType.list()` (filename glob of `+stimgen/*.m`), in the StimPlayer type dropdown, in `.spl`
banks, and keep `plot`, `plot_spectrogram`, variants and expression fields working — with `Duration`
reinterpreted as **loop-block length**.

Critically, **this does not give up composition where composition is actually wanted**: the envelope
source is a nested `StimType` handle in all three options, so we still get the general
"modulate by any StimType" behavior, without paying the nesting cost on the carrier.

**Risk and fallback.** MATLAB multiple inheritance interacting with `matlab.mixin.Heterogeneous` /
`Copyable` (both in `StimType`'s superclass list,
[StimType.m:1](+stimgen/@StimType/StimType.m#L1)) needs an early smoke test. Mitigation: put *all*
real machinery in a plain composed engine class `stimgen.continuous.Stream`; the mixin is only ~40
lines of property declarations and forwarding. If `< Tone & Playable` misbehaves, delete the mixin
and paste that glue into each subclass — the engine is untouched either way.

Both new files go in a **subpackage** `+stimgen/+continuous/` so `StimType.list()`'s `*.m` glob
([list.m:4-10](+stimgen/@StimType/list.m#L4-L10)) never offers them as stimuli.

---

## Implementation

### Step 0 — Verify multiple inheritance (do this first)

```matlab
% scratch check before writing anything else
classdef Probe < stimgen.Tone & handle
```
Confirm a 3-line mixin deriving from `handle` can be combined with `stimgen.Tone`, that the
heterogeneous root is still `StimType`, and that `copy()` still works. If it fails, switch to the
paste-the-glue fallback above and continue unchanged.

### Step 1 — `+stimgen/+continuous/Stream.m` (the engine)

Standalone `handle` class, testable without any stimulus object. Owns:

- `audioDeviceWriter` (`SampleRate`, `SupportedSampleRates` validated at `start`).
- A MATLAB `timer`: `'fixedRate'`, `BusyMode = 'drop'`, `Period` ≈ half the frame duration, tagged
  `'stimgenContinuousStream'`. Mirror the stale-timer sweep in
  [playback_control.m:62-64](+stimgen/@StimPlayer/playback_control.m#L62-L64).
- **Two independent read pointers**, `carrierPtr_` and `envPtr_`, each wrapping modulo its own
  buffer length. This is what lets the envelope period be incommensurate with the carrier block.
- Per tick: assemble frames until the device is fed, `y = carrier(ci) .* env(ei) .* gain_`, then
  `nUnderrun = step(device, y')`. Log underruns via `stimgen.util.vprintf(1, ...)`.

Click-free behavior (the robustness requirement):

- **Ramp on start/stop** — `RampDuration` (default 20 ms) cosine-squared fade, reusing the shape from
  the `Window` dependent property. `stop()` fades out, *then* releases the device.
- **Crossfade on parameter change** — the carrier buffer is never mutated in place. `set_carrier()`
  fills `pendingCarrier_`; the tick swaps at the next frame boundary with an equal-power crossfade.
  This is why a live `Frequency` edit does not click.
- `delete()` releases the device and deletes the timer.

Public surface: `start()`, `stop()`, `isRunning`, `set_carrier(y, Fs)`, `set_envelope(y, mode)`,
`trigger_envelope()`, `RampDuration`, `CrossfadeDuration`, `SamplesPerFrame`, `Device`.

Error ids follow the house convention (`stimgen:continuous:Stream:UnsupportedSampleRate`, etc.).

**Sample-rate constraint — deliberate, document it.** `StimType.Fs` defaults to `97656.25` (a TDT
rate) and no sound card supports it. Rather than resample (which would destroy the integer-cycle
guarantee below), the continuous classes default `Fs = 48000` and `start()` raises
`stimgen:continuous:Stream:UnsupportedSampleRate` listing the device's supported rates. Note that
existing [play.m:9](+stimgen/@StimType/play.m#L9) has the same latent limitation and also does not
resample, so this is consistent — just made explicit.

### Step 2 — `+stimgen/+continuous/Playable.m` (the mixin)

Thin. Properties (all `SetObservable, AbortSet` so existing listeners recompute):

| Property | Purpose |
|---|---|
| `RampDuration` | stream fade in/out, seconds (ms in GUI via `'scale', 1000`) |
| `EnvelopeSourceClass` | dropdown, `StimType.list()` + `"None"` |
| `EnvelopeSource` | the nested `StimType` handle (not in `propMeta`) |
| `EnvelopeMode` | `"Off"` \| `"Loop"` \| `"OneShot"` |
| `EnvelopeMethod` | `"Direct"` \| `"Hilbert"` \| `"RectifyLowpass"` |
| `EnvelopeLowpass` | Hz, used only by `RectifyLowpass` |
| `EnvelopeDepth` | `[0 1]`, partial modulation |

Methods: `start()`, `stop()`, `isRunning`, `trigger_envelope()`, plus protected
`refresh_stream_()` (push `Signal` into the stream when it changes) and `build_envelope_()`.

- `EnvelopeSourceClass` changes are handled in an `on_gui_changed` override (the existing hook,
  [StimType.m:194](+stimgen/@StimType/StimType.m#L194)) which instantiates the class and attaches a
  **PostSet listener on the source's `Signal`** — `Signal` is already `SetObservable`
  ([StimType.m:47](+stimgen/@StimType/StimType.m#L47)), so editing the modulator live updates the
  running envelope for free.
- `build_envelope_()`: `Direct` = normalize to `[0 1]` (clamp negatives, documented);
  `Hilbert` = `abs(hilbert(x))`; `RectifyLowpass` = `abs(x)` through a `designfilt` lowpass. Then
  apply `EnvelopeDepth` using the same formula as
  [AMnoise.m:65-66](+stimgen/AMnoise.m#L65-L66) so depth means the same thing across the toolbox.
- `OneShot`: `trigger_envelope()` resets `envPtr_` and arms a single pass; the gain returns to 1 at
  the end of the buffer.
- Constructor sets `ApplyWindow = false` (a ramp *inside* a loop block is exactly wrong) and
  `Duration = 1`. `propMeta` **removes** `ApplyWindow`/`WindowDuration` and adds the table above.

### Step 3 — Seamless loop-block synthesis (the two subclasses)

This is the part that must be exactly right, and it differs per carrier.

**`+stimgen/ContinuousTone.m`** — the block must contain an integer number of cycles, so snap the
frequency to the nearest FFT bin of the block:

```matlab
nBlock  = round(Fs * Duration);
cycles  = max(1, round(nBlock * f / Fs));
fActual = cycles * Fs / nBlock;         % exact-periodic; report this
y       = sin(2*pi*fActual*(0:nBlock-1)/Fs + phase);
```
Snap error is `< Fs/(2*nBlock)` — ±0.5 Hz at `Fs=48000` with a 1 s block. Expose a dependent
`RealizedFrequency` and log the deviation at `vprintf` level 2 so it is never silent.

**`+stimgen/ContinuousNoise.m`** — `Noise`'s `randn` + `filter`
([Noise.m:53-56](+stimgen/Noise.m#L53-L56)) is **not** loop-safe: `filter` has a startup transient
and the block edges do not join. Replace with frequency-domain synthesis, which is circularly
continuous by construction:

```matlab
X = zeros(1, nBlock);
k = freq bins within [HighPass LowPass];
X(k) = exp(1i*2*pi*rand(1,numel(k)));
y = ifft(X, 'symmetric');
```
This is a **new synthesis path in the subclass only** — do not touch `stimgen.Noise`.

Both then run the standard pipeline in the mandated order — `apply_normalization` →
`apply_calibration` → *no* `apply_gate` (`ApplyWindow` is false, so
[apply_gate.m:7](+stimgen/@StimType/apply_gate.m#L7) already no-ops) — and both open with the
mandatory variant guard, exactly as in [Tone.m:34-37](+stimgen/Tone.m#L34-L37). `update_signal` ends
by calling `refresh_stream_()`, so editing a parameter while running crossfades to the new block.

Each subclass also declares `UserProperties` including the mixin's properties (otherwise they will
not survive `toStruct`/`fromStruct`) and merges `propMeta` parent-last, per
[AMnoise.m:95](+stimgen/AMnoise.m#L95).

### Step 4 — Minimal GUI/player integration

1. **New `'button'` widget type** — additive and backward-compatible: a `case 'button'` in
   [create_gui.m:40](+stimgen/@StimType/create_gui.m#L40) and in
   [resolve_widget_type.m](+stimgen/@StimType/resolve_widget_type.m). Note line 78 of `create_gui`
   does a blanket `structfun(... 'ValueChangedFcn' ...)` — buttons must be excluded there and wired
   to `ButtonPushedFcn` instead. Gives the panel a **Start/Stop** button and an
   **Edit Envelope Source…** button (the latter opens `obj.EnvelopeSource.create_gui(uifigure)` —
   `create_gui` already takes a parent container as `src`).
2. **Guard the trial loop** — a continuous item must never be triggered as a one-shot. Add an
   `isContinuous` test and early-return in
   [update_buffer.m](+stimgen/@StimPlayer/update_buffer.m) and skip such items in
   `select_next_idx`.
3. **Route preview** — [play_preview.m](+stimgen/@StimPlayer/play_preview.m) calls `start()`/`stop()`
   for continuous items instead of the blocking `stimObj.play`.
4. **Error mapping** — add the new `stimgen:continuous:*` ids to
   [StimPlayer.m:637-690](+stimgen/@StimPlayer/StimPlayer.m#L637-L690)
   (`format_gui_error_message_`), per the house convention.

*Drive-by (optional, one line):* `HardwareHost` currently leaks into `StimType.list()` because the
filter is a blocklist ([list.m:8](+stimgen/@StimType/list.m#L8)) — add it while touching that area.

### Step 5 — Documentation

New `documentation/stimgen_continuous.md` following the established per-class guide shape (H1 =
backticked class name, source-link block, What It Provides → lifecycle → key properties → key
methods → matlab usage example → caveats → Related documentation). Register it in
`documentation/stimgen_overview.md` (documentation map *and* the built-in stimulus list), the
`README.md` class table, and add the loop-block/no-internal-gating rule to `CLAUDE.md`.

---

## Verification

No test suite exists; verify by running in MATLAB. `clear classes` between edits.

```matlab
addpath('C:\src\stimgen'); clear classes

% 1. Loop-block seams — the whole point. Both must be ~0.
t = stimgen.ContinuousTone; t.Fs = 48000; t.Duration = 1; t.Frequency = 1000;
t.update_signal;
abs(t.Signal(end) - t.Signal(1))            % tone: wrap discontinuity
n = stimgen.ContinuousNoise; n.Fs = 48000; n.update_signal;
max(abs(diff([n.Signal n.Signal(1)])))      % noise: no edge step vs. interior

% 2. Frequency snapping is reported, not silent
t.Frequency, t.RealizedFrequency

% 3. Continuous playback, object-owned
t.start; pause(3); t.Frequency = 2000;      % must crossfade, no click
pause(3); t.stop                            % must fade out, no click
t.isRunning                                 % false

% 4. Envelope modulation, looped
m = stimgen.AMnoise; m.EnvelopeOnly = true; m.AMRate = 4; m.Duration = 0.25;
n.EnvelopeSource = m; n.EnvelopeMode = "Loop"; n.EnvelopeDepth = 1;
n.start; pause(5); n.stop                   % 4 Hz AM on continuous noise

% 5. One-shot envelope over a running carrier
n.EnvelopeMode = "OneShot"; n.start;
pause(2); n.trigger_envelope; pause(2); n.stop

% 6. Round-trip and discovery
any(strcmp(stimgen.StimType.list, 'ContinuousTone'))
isequal(stimgen.StimType.fromStruct(t.toStruct).Frequency, t.Frequency)

% 7. GUI paths
stimgen.StimPlayer      % ContinuousTone in dropdown; Start/Stop button works;
                        % Run with a discrete item present must not one-shot it
```

Also confirm: closing the StimPlayer figure or `delete(t)` while running stops the device and leaves
no orphan in `timerfindall('Tag','stimgenContinuousStream')`; and that an unsupported `Fs` (e.g. the
inherited `97656.25`) raises the clear `UnsupportedSampleRate` error rather than a raw DSP error.

## Out of scope

- Hardware/TDT continuous output — the seam is noted but needs an RPvds circuit change in EPsych.
- Absolute SPL calibration of continuous sound-card output. `apply_calibration` still runs and scales
  to a LUT voltage, but the stream peak-normalizes before writing to the device (as
  [play.m:9](+stimgen/@StimType/play.m#L9) does), so sound-card level is relative. Call this out in
  the docs.
