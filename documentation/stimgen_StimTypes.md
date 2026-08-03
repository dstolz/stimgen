# Stimulus Type Catalog

Reference for every concrete `stimgen.StimType` subclass: what it generates, its
class-specific properties, and its calibration/normalization behavior. For the shared
contract (lifecycle, variants, display units, GUI generation) see
[stimgen_StimType.md](stimgen_StimType.md); for the file-catalog stimulus type see the
dedicated [stimgen_SoundFile.md](stimgen_SoundFile.md).

All classes inherit `SoundLevel`, `Duration`, `WindowDuration`, `WindowFcn`,
`ApplyWindow`, `ApplyCalibration`, and `Fs` from `stimgen.StimType`; only properties
introduced by each subclass are listed below. Time-valued properties are stored in
**seconds** and shown in **milliseconds** in the GUI unless noted otherwise. Any
property marked vectorizable can be assigned a vector to define variants (see
[Variants](stimgen_StimType.md#variant-selection)).

| Class | Summary | `CalibrationType` | `Normalization` |
| --- | --- | --- | --- |
| [`Tone`](#tone) | Pure sine tone | `"tone"` | `"absmax"` |
| [`Noise`](#noise) | Band-limited Gaussian noise | `"filter"` | `"rms"` |
| [`AMnoise`](#amnoise) | Sinusoidally amplitude-modulated noise | `"filter"` | `"rms"` |
| [`AttackModNoise`](#attackmodnoise) | Attack/decay-shaped modulated noise | `"filter"` | `"rms"` |
| [`FMtone`](#fmtone) | Sinusoidally frequency-modulated tone | `"filter"` | `"absmax"` |
| [`ClickTrain`](#clicktrain) | Periodic train of rectangular clicks | `"click"` | `"absmax"` |
| [`SweptSine`](#sweptsine) | Logarithmic or linear chirp | `"swept_sine"` | `"absmax"` |
| [`TORC`](#torc) | Temporally orthogonal ripple combination, for STRF estimation | `"filter"` | `"rms"` |
| [`SoundFile`](#soundfile) | Playback of a catalog of sound files | overridden per instance (`CalibrationMode`) | overridden per instance (`LevelReference`) |

`CalibrationType` selects which LUT `apply_calibration` looks up and which property
supplies the key — see [Calibration coupling](../CLAUDE.md) in the repo root guide.
`Normalization` selects how the raw waveform is scaled before calibration:
`"absmax"` normalizes to the signal's peak, `"rms"` normalizes to its RMS.

## Tone

Pure sine tone at `Frequency` for `Duration` seconds.

- [+stimgen/Tone.m](../+stimgen/Tone.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `Frequency` | yes | Hz, 100–40000 |
| `OnsetPhase` | yes | degrees |
| `WindowMethod` | no | `"Duration"` \| `"Proportional"` \| `"#Periods"` — reinterprets `WindowDuration` |

`WindowMethod` changes both the meaning and display scale of the inherited
`WindowDuration`: a fixed time (ms), a percentage of total duration, or a count of
carrier periods per ramp. `Tone.propMeta` overrides the `WindowDuration` entry per
mode; see [Display units](stimgen_StimType.md#display-units) for how `scale` drives
that.

`WindowDuration` is stored in whichever unit the active method declares. The
conversion to seconds happens in `Tone.effective_window_duration_`, which the base
class `Window` getter calls, so the stored value is never rewritten and repeated
`update_signal` calls are idempotent.

Because the units differ per method, switching `WindowMethod` from a GUI resets
`WindowDuration` to that method's default (2 ms / 10 % / 5 periods) and re-renders
the field's label and value — see `Tone.on_gui_changed` and
[GUI change hooks](stimgen_StimType.md#gui-change-hooks). Setting `WindowMethod`
programmatically leaves `WindowDuration` alone, so a save/load round-trip keeps
whatever was stored.

## Noise

Gaussian noise band-limited between `HighPass` and `LowPass` with an FIR bandpass
filter (`FilterOrder` taps).

- [+stimgen/Noise.m](../+stimgen/Noise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `HighPass` | yes | Hz, filter low cutoff |
| `LowPass` | yes | Hz, filter high cutoff |
| `FilterOrder` | no | FIR order used by `designfilt` |

`LowPass` must exceed `HighPass`; a violation raises
`stimgen:Noise:InvalidBand`. The digital filter is rebuilt on every `update_signal`
via `update_digFilter` and cached on the object as `digFilter`, not recomputed
per-sample. `Noise` is also the superclass for `AMnoise` and `AttackModNoise`, which
reuse its carrier generation (`temporarilyDisableSignalMods` guards the base class's
own normalize/calibrate/gate calls while the carrier is only an intermediate signal).

## AMnoise

`stimgen.Noise` carrier with sinusoidal amplitude modulation.

- [+stimgen/AMnoise.m](../+stimgen/AMnoise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `AMDepth` | yes | modulation depth, 0–1 |
| `AMRate` | yes | Hz |
| `OnsetPhase` | yes | degrees, modulator phase at t=0 |
| `EnvelopeOnly` | no | play the modulator alone (no carrier) — useful for verifying envelope shape |
| `ApplyViemeisterCorrection` | no | scales the modulator so average power matches the unmodulated carrier |

Inherits `HighPass`/`LowPass`/`FilterOrder` from `Noise`. `ApplyViemeisterCorrection`
keeps loudness roughly constant across `AMDepth` values by compensating for the power
lost to modulation (Viemeister 1979).

## AttackModNoise

`stimgen.Noise` carrier with a ramped/damped attack-and-decay modulation envelope
(one period repeated to fill `Duration`), rather than a sinusoid.

- [+stimgen/AttackModNoise.m](../+stimgen/AttackModNoise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `AMDepth` | yes | modulation depth, 0–1 (kept for `ApplyViemeisterCorrection`; the envelope shape itself is set by `Z`) |
| `AMRate` | yes | Hz, sets the modulation period `1/AMRate` |
| `Z` | yes | -1–1, envelope shape: negative ramps up (attack), positive damps down (decay) |
| `AddOnOffperiods` | no | prepend/append a partial period so the envelope starts and ends near zero crossing |
| `EnvelopeOnly` | no | play the modulator alone (no carrier) |
| `ApplyViemeisterCorrection` | no | same power-compensation as `AMnoise` |

Unlike `AMnoise`, `OnsetPhase` here is scalar and not exposed in `UserProperties` —
the envelope's phase is fixed by construction (`Z` sign), not by a phase offset.

## FMtone

Sine carrier with sinusoidal frequency modulation (true instantaneous-frequency
integration, not a simple phase wobble).

- [+stimgen/FMtone.m](../+stimgen/FMtone.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `CarrierFrequency` | yes | Hz, center frequency |
| `ModulationFrequency` | yes | Hz, modulator rate; `0` collapses to a pure tone at `CarrierFrequency` |
| `ModulationDepth` | yes | Hz, peak deviation of instantaneous frequency |
| `OnsetPhase` | yes | radians (not degrees, unlike `Tone`/`AMnoise`) |

`CalibrationType` is `"filter"` rather than `"tone"` — an FM tone sweeps a band, so it
is calibrated like broadband material (equalizer/filter LUT) rather than looked up at
a single frequency.

## ClickTrain

Train of rectangular clicks at `Rate`, each `ClickDuration` long, filling `Duration`.

- [+stimgen/ClickTrain.m](../+stimgen/ClickTrain.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `Rate` | yes | Hz, click repetition rate |
| `Polarity` | yes | `1` positive, `-1` negative, `0` alternating |
| `ClickDuration` | yes | seconds; must be ≤ `1/Rate` |
| `OnsetDelay` | yes | seconds before the first click |
| `Truncate` | yes | if false, zero-pads to `Duration` instead of cutting a partial train |
| `ClickInterval` | — | read-only, `1/Rate` |

Also read-only via the `Dependent` `ClickInterval`. Construction disables the
inherited window (`ApplyWindow = false`, `WindowFcn = ""`) because clicks are
already discrete pulses, not a continuous tone needing onset/offset ramping.
`ClickDuration` too long for `Rate`, or shorter than one sample at `Fs`, raises
`stimgen:ClickTrain:ClickDuration:InvalidValue`. `CalibrationType` is `"click"`: the
LUT is keyed on `ClickDuration`, and the CalibrationGui transfer plot keeps that axis
in µs rather than ms (see [Time is seconds…](../CLAUDE.md)).

## SweptSine

Logarithmic (default) or linear frequency sweep from `StartFrequency` to
`StopFrequency` over `Duration`. Also used internally by the calibration engine to
measure transfer functions — see
[stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md).

- [+stimgen/SweptSine.m](../+stimgen/SweptSine.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `StartFrequency` | no (scalar only) | Hz |
| `StopFrequency` | no (scalar only) | Hz |
| `ChirpType` | no | `"log-sine"` \| `"linear"` |

`StartFrequency`/`StopFrequency`/`ChirpType` are the only base properties declared
`(1,1)` rather than `(1,:)` among the built-in stimuli — a swept sine is not intended
to be vectorized into variants the way a tone or noise band is. `StartFrequency` must
be less than `StopFrequency`, or `update_signal` raises
`stimgen:SweptSine:badFreqRange`. The log-sine form has a naturally pink spectrum and
low crest factor (~4 dB), which is what makes it usable for broadband calibration
measurements; `CalibrationType` is `"swept_sine"`, keyed on the geometric mean of
`StartFrequency`/`StopFrequency`.

## TORC

Temporally Orthogonal Ripple Combination — a broadband sound whose dynamic spectrum is
the sum of moving ripples whose modulation rates all differ, so that spectrotemporal
reverse correlation recovers a spectrotemporal receptive field (STRF) from a single
stimulus-response pair without averaging. Implements Klein, Depireux, Simon & Shamma
(2000), *Robust spectrotemporal reverse correlation for the auditory system:
optimizing stimulus design*, J Comput Neurosci 9:85–111; equation numbers below and in
the source refer to that paper.

- [+stimgen/TORC.m](../+stimgen/TORC.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `LowFrequency` | yes | Hz, f0 — the bottom of the tonotopic axis `x = log2(f/f0)` |
| `Bandwidth` | yes | octaves, X |
| `ComponentsPerOctave` | yes | carriers per octave sampling the dynamic spectrum |
| `ComponentMode` | no | `"Range"` (TORC method I) \| `"Explicit"` (method II) |
| `RippleDensity` | yes | c/o, **signed**; Range mode only |
| `LowestRate` / `HighestRate` | yes | Hz, ends of the rate run; Range mode only |
| `ComponentRates` | no (text) | Hz, explicit rate list; Explicit mode only |
| `ComponentDensities` | no (text) | c/o, explicit density list, recycled to fit; Explicit mode only |
| `ModulationDepth` | yes | dB peak-to-peak excursion of the dynamic spectrum |
| `NumPeriods` | yes | ripple periods within `Duration`; T = `Duration`/`NumPeriods` |
| `RandomizeRipplePhase` | no | randomize ψ to reduce peakiness (Section 4.1) |
| `Seed` | yes | RNG seed for ripple and carrier phases; negative reseeds each update |

Read-only outputs, refreshed by every `update_signal`: `RippleRates`,
`RippleDensities`, `RipplePhases`, `RippleAmplitude`, `RipplePeriod`,
`CarrierFrequencies`, `CarrierPhases`, `OctaveAxis`. They are deliberately not
`SetObservable` (writing them must not retrigger the update) and not in
`UserProperties` (they are recomputed, not restored).

**Synthesis.** The dynamic spectrum is built from Eq. (28),
`S(t,x) = Σᵢ 2a·cos(2π(wᵢt + Ωᵢx) + ψᵢ)` in dB, and the waveform is the sum of the
carriers, each a random-phase tone driven by S at its own tonotopic position:
`s(t) = Σⱼ 10^(S(t,xⱼ)/20)·sin(2πfⱼt + φⱼ)`. Components are equal-amplitude
(Section 4.1), so recovering the STRF from the reverse-correlation function C is a
division by the scalar `RippleAmplitude²` (Eq. 38) rather than a deconvolution.

**Direction of travel** is carried by the sign of the ripple density, not the rate:
rates are always positive here, which spans the same physical ripples as the paper's
signed-rate convention because (w,−Ω) is the complex conjugate of (−w,Ω). Positive
density is downward-moving (quadrant 1 of the paper's Fig. 3), negative is upward.

**Rate quantization.** Rates are snapped to multiples of 1/T so the envelope is
exactly periodic and can be period-averaged against a PSTH (Eq. 11). In `"Range"`
mode the component set is the contiguous run of those harmonics from `LowestRate` to
`HighestRate` — the paper's method I, one row of the ripple domain per stimulus. Two
components landing on the same rate raises `stimgen:TORC:TemporalOrthogonality`, since
that is precisely the condition a TORC exists to avoid; a rate below the 1/T
fundamental raises `stimgen:TORC:RateBelowFundamental`.

**Tonotopic axis.** Carriers occupy the half-open range `[0, Bandwidth)` octaves,
because Eq. (10)–(11) treat that range as one period of a Fourier series — `x = 0` and
`x = Bandwidth` are the same phase of every ripple. Including both would double-count
a period point and leave a residual in the reverse correlation. The top carrier
therefore sits one step below `LowFrequency · 2^Bandwidth`; exceeding Nyquist raises
`stimgen:TORC:BandwidthExceedsNyquist`. Densities that are whole multiples of
`1/Bandwidth` land exactly on the Fourier grid; others are allowed and do not affect
temporal orthogonality.

**Mapping the paper's ensembles onto the variant system.** Vectorizing
`RippleDensity` turns the M rows of the ripple domain into M variants, which is the
full method I ensemble; vectorizing `Seed` instead gives the phase-averaging method of
Section 4.2, a set of stimuli sharing one ripple set but drawing new random phases.

```matlab
t = stimgen.TORC;                        % 250 ms, 5 oct from 125 Hz
t.RippleDensity = [-1.6:0.4:-0.4 0.4:0.4:1.6];   % 8-TORC method I ensemble
t.update_signal;
t.plot_dynamic_spectrum
[S, tt, x] = t.dynamic_spectrum(250);    % S(t,x) at 1 ms bins for correlation
```

`dynamic_spectrum` recomputes the envelope at whatever resolution the analysis needs —
typically the PSTH bin rate, not `Fs` — because the full-rate envelope is large and is
not retained. `Duration` is taken from the rendered signal rather than the property so
that reading it cannot advance the variant index and decouple S from `Signal`.

Construction sets `Duration = 0.25` (the paper's value) and disables the inherited
window (`ApplyWindow = false`, `WindowFcn = ""`): an onset/offset gate breaks the exact
periodicity the method relies on. Enable it only for single, unrepeated presentations.

## SoundFile

Playback of a catalog of pregenerated sound files (vocalizations, phonemes, natural
scenes) rather than a synthesized waveform. `FileIndex` is the vectorizable variant
axis, `Duration` is derived from the selected file, and calibration/normalization are
selected per instance (`CalibrationMode`, `LevelReference`) rather than fixed
`Constant`s. Full reference: [stimgen_SoundFile.md](stimgen_SoundFile.md).

- [+stimgen/SoundFile.m](../+stimgen/SoundFile.m)

## Adding a new stimulus type

A new class in `+stimgen/` (loose `.m` file, not a class folder) is picked up
automatically by `stimgen.StimType.list()` and appears in `StimPlayer`'s type
dropdown with no player-side changes, provided it implements `update_signal` per the
[lifecycle contract](stimgen_StimType.md#signal-update-lifecycle) and defines clean
`propMeta()`. Add a row to the table at the top of this document and a section below
it when you do.

## Related files

- [+stimgen/@StimType/StimType.m](../+stimgen/@StimType/StimType.m)
- [stimgen_StimType.md](stimgen_StimType.md) — base contract, variant system, GUI generation
- [stimgen_SoundFile.md](stimgen_SoundFile.md) — `SoundFile` deep dive
- [stimgen_overview.md](stimgen_overview.md) — package orientation
