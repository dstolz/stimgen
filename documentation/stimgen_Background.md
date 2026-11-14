# Ongoing Backgrounds

How a stimulus is embedded in a sound that plays continuously around it: a tone in
noise, a silent gap in noise, 10 Hz amplitude modulation of a steady band-passed noise,
frequency modulation of a steady tone.

Related: [stimgen_StimType.md](stimgen_StimType.md) (the base contract),
[stimgen_StimTypes.md](stimgen_StimTypes.md) (the class catalog),
[stimgen_StimPlayer.md](stimgen_StimPlayer.md) (the designer).

## The model

A presenter that plays a background continuously renders, for each presentation,

```
y(i) = G(i) * B(i, theta(i)) + add(i)
```

| Term | What it is | Who supplies it |
| --- | --- | --- |
| `B` | the background: a noise loop, tiled, or a tone `A*sin(2*pi*f*t + theta)` | `get_background()` |
| `add` | a waveform added to the background (a tone in noise) | `get_embedding().Signal` |
| `G` | a gain envelope multiplying the background (AM, a gap); 1 outside the stimulus | `get_embedding().Gain` |
| `theta` | a phase deviation of a tonal background (FM); held at its last value afterwards | `get_embedding().Phase` |

So there are two kinds of embedded stimulus:

- **An addition to the background.** Any existing stimulus class with `Background`
  set. `Signal` is the stimulus alone, exactly as without a background, and a
  presenter sums it onto the background.
- **A modulation of the background.** The `stimgen.BackgroundModulation` classes
  ([`BackgroundAM`](stimgen_StimTypes.md#backgroundam),
  [`BackgroundGap`](stimgen_StimTypes.md#backgroundgap),
  [`BackgroundFM`](stimgen_StimTypes.md#backgroundfm)). Nothing is added; the
  background's own gain or phase changes for the stimulus's `Duration`.

The background is modulated in place rather than replaced by a pre-made modulated
segment because a tone cannot be spliced phase-continuously at an arbitrary onset.

**stimgen does not play a background continuously.** It defines and calibrates one;
a presenter that owns the audio stream plays it (MABR does, through
`get_embedding`). `StimPlayer`'s own hardware Run plays `Signal` alone and says so
before starting (see [Before a run starts](stimgen_StimPlayer.md#before-a-run-starts)).
Play, the signal plot and a hardware preview audition the stimulus *in* a short
stretch of its background.

## Background properties

Every `StimType` carries them (except `CapturedSignal`, a recording). They are appended
to each instance's `UserProperties`, so they serialize with the stimulus and a vector
is a variant axis.

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `Background` | no | `"None"` (default) \| `"Noise"` \| `"Tone"` |
| `BackgroundLevel` | yes | dB SPL (rms) when calibrated; independent of `SoundLevel` |
| `BackgroundHighPass`, `BackgroundLowPass` | yes | Hz, the noise band's -6 dB edges (Noise) |
| `BackgroundFrequency` | yes | Hz (Tone) |
| `BackgroundLoopDuration` | no | seconds, 1-60 (default 10); shown in ms. Length of the noise segment a presenter repeats |
| `BackgroundSeed` | no | non-negative integer (default 1). Same settings and seed give the same noise |

A setting the chosen type does not use is ignored everywhere: it is not shown, not a
variant axis and not in the parameter summary. A `BackgroundLevel` vector left behind
with `Background = "None"` does not multiply the combinations.

`Signal` does not depend on any of them for an additive stimulus. A bank saved before
they existed loads with no background.

A presenter plays **one background per run**, so:

- a series made by varying the *stimulus* (the tone's level, for a signal-to-noise
  series) shares one background and its conditions can be interleaved;
- a series made by varying the *background* (`BackgroundLevel`, or
  `BackgroundFrequency` for FM detection at several carriers) is several backgrounds
  and has to run one condition per run.

`get_background().Key` is text that is equal exactly when two stimuli (or two variants)
share a background; that is what a presenter compares.

## How the background is made

`stimgen.util.background_source` builds it from the package's own stimulus classes — a
`stimgen.Noise` or a `stimgen.Tone` on the same calibration object, ungated — so no
level convention is restated: a background at 50 dB SPL has the rms a `Noise` or `Tone`
stimulus at `SoundLevel = 50` has, with the same equalizer and LUT anchoring.

**Noise** is returned as a segment that loops seamlessly:

1. `LoopDuration` plus a 50 ms cross-fade of noise is generated (plus guard samples at
   each end, discarded, when an equalizer is applied — `filter_aligned` starts and ends
   on zeros).
2. The extra tail is cross-faded, equal power, into the head. The last sample of a lap
   is then followed by the sample the noise itself continued with.
3. The loop is scaled back to the rms the calibrated record had, so the loop *as
   played* is at `BackgroundLevel`.

The noise is drawn from a private stream seeded with `BackgroundSeed`
(`Noise.RandomStream`); the global stream is neither read nor changed. The same noise
recurs with period `LoopDuration` — a property of the looped design, to be kept in mind
when the inter-stimulus interval divides it evenly.

**A tone** needs no waveform: its frequency and peak amplitude are returned and a
presenter computes it in closed form.

Loops are memoized by `Key` (the three most recent); nothing is cached on the stimulus,
because a `copy()` carries none of its source's listeners.

Without a calibration (or with `ApplyCalibration` off) the background is normalized
only — noise to rms 1, a tone to peak 1 — and `Calibrated` is false.

## The methods

```matlab
B = stim.get_background();          % [] for "None"
E = stim.get_embedding();           % Mode, Signal, Gain, Phase, Background
[y, t] = stim.embedded_signal(pre, post);   % reference render of one presentation
[y, t] = stim.audition_signal();    % what Play auditions
```

`embedded_signal` is the reference for the arithmetic above: the background runs from
the first rendered sample (the start of the loop, or a tone at zero phase), and `t` is
0 at the stimulus onset. A presenter's own render of the same presentation, with the
same background offset, must reproduce it.

None of them advances the variant selection; all describe the waveform currently in
`Signal`.

## Modulations of the background

`stimgen.BackgroundModulation` is the abstract base (in a class folder, so
`StimType.list()` does not offer it). Three rules hold for its subclasses:

- **The gate shapes the modulation, not the carrier.** `WindowDuration`/`WindowFcn`
  ramp the *deviation* (from gain 1, from zero frequency deviation) in and out, so the
  event joins the steady background smoothly whatever its phase or cycle count. The
  background itself is never gated.
- **There is one level.** `SoundLevel` is the level of the steady background;
  `BackgroundLevel` is unused and not shown.
- **The level is carrier-referenced.** Nothing is renormalized after the modulation is
  applied. A 100 % AM epoch therefore has more power than the steady background by
  `10*log10(mean(G.^2))` = +1.76 dB, and a gap has less. `level_offset_db()` reports
  that figure, `stimgen.util.level_request` passes it on as `expected_offset_db`, and
  `level_as_calibrated` subtracts it, so SpotCheck and the inspector do not read it as
  a calibration error.

`Signal` is the stand-alone rendition: the background over the stimulus's `Duration`
with the modulation applied (fresh noise of that length, not the loop). That is what
Play without a presenter, the inspector, and a `StimPlayer` Run use.

These classes are distinct from `AMnoise` and `FMtone`, which are gated *bursts* with
an onset and offset of their own, renormalized to `SoundLevel`.

## Examples

```matlab
% Tone-in-noise, signal-to-noise series by tone level (one background: can interleave)
t = stimgen.Tone('Frequency', 8000, 'SoundLevel', 20:10:70, 'Duration', 0.005, ...
    'Background', "Noise", 'BackgroundLevel', 50, ...
    'BackgroundHighPass', 4000, 'BackgroundLowPass', 16000);

% 10 Hz AM of a continuous band-passed noise, three depths
am = stimgen.BackgroundAM('AMRate', 10, 'AMDepth', [0.25 0.5 1], 'Duration', 0.5, ...
    'SoundLevel', 60, 'BackgroundHighPass', 4000, 'BackgroundLowPass', 16000);

% Gap detection: gap duration series in 60 dB noise, 1 ms ramps
gap = stimgen.BackgroundGap('Duration', [0.002 0.005 0.01 0.02 0.05], ...
    'WindowDuration', 0.002, 'SoundLevel', 60);

% FM of a steady tone, at three carriers (three backgrounds: one per run)
fm = stimgen.BackgroundFM('BackgroundFrequency', [4000 8000 16000], ...
    'FMRate', 10, 'FMDeviation', 200, 'Duration', 0.5, 'SoundLevel', 60);

E = am.get_embedding();     % E.Mode "modulate", E.Gain the envelope, E.Signal zeros
[y, t] = gap.embedded_signal(0.1, 0.1);   plot(t*1e3, y)
```

## Limits

- A tone background is level-correct at its own frequency; the frequency deviation of
  an FM is not equalized.
- A stimgen or host from before this feature loads a new bank's *additive* stimulus
  without its background (the properties are unknown to it and skipped). The
  modulation classes do not exist there, so those fail to load instead.
- Not provided: power-compensated AM, a level-increment class, a background that is
  itself continuously modulated.

## Related files

- [+stimgen/+util/background_source.m](../+stimgen/+util/background_source.m)
- [+stimgen/@StimType/get_background.m](../+stimgen/@StimType/get_background.m),
  [get_embedding.m](../+stimgen/@StimType/get_embedding.m),
  [embedded_signal.m](../+stimgen/@StimType/embedded_signal.m),
  [audition_signal.m](../+stimgen/@StimType/audition_signal.m)
- [+stimgen/@BackgroundModulation/BackgroundModulation.m](../+stimgen/@BackgroundModulation/BackgroundModulation.m)
- [+stimgen/BackgroundAM.m](../+stimgen/BackgroundAM.m),
  [BackgroundGap.m](../+stimgen/BackgroundGap.m),
  [BackgroundFM.m](../+stimgen/BackgroundFM.m)
- [tests/BackgroundTest.m](../tests/BackgroundTest.m)
