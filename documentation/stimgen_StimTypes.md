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
[Variants](stimgen_StimType.md#variant-selection)). `WindowFcn` selects the *shape*
of the onset/offset ramp from a catalog of window functions -- see
[Gate shape](stimgen_StimType.md#gate-shape-windowfcn).

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
| [`DMR`](#dmr) | Dynamic moving ripple and ripple noise, for STRF estimation | `"filter"` | `"rms"` |
| [`SoundFile`](#soundfile) | Playback of a catalog of sound files | overridden per instance (`CalibrationMode`) | overridden per instance (`LevelReference`) |
| [`BackgroundAM`](#backgroundam) | Amplitude modulation **of an ongoing background** | `"filter"` | `"rms"` (carrier-referenced) |
| [`BackgroundGap`](#backgroundgap) | A gap (or level decrement) **in an ongoing background** | `"filter"` | `"rms"` (carrier-referenced) |
| [`BackgroundFM`](#backgroundfm) | Frequency modulation **of an ongoing tone** | `"filter"` | `"rms"` (carrier-referenced) |

Every class above the last three can also be *embedded in* an ongoing background (a
tone in noise) by setting the inherited `Background` properties; the last three are a
change made *to* the background and add nothing. Both are covered in
[stimgen_Background.md](stimgen_Background.md).

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
| `Polarity` | yes | `1` positive, `-1` negative, `0` alternating across presentations |
| `WindowMethod` | no | `"Duration"` \| `"Proportional"` \| `"#Periods"` — reinterprets `WindowDuration` |

`Polarity = 0` does **not** alternate within the waveform the way `ClickTrain`'s
does — a tone pip is one event, with nothing inside it to flip. The positive
waveform is generated and `alternates_polarity()` returns true, which tells the
presenter to invert every other presentation of that variant:
`StimPlayer`'s hardware playback does (see
[Alternating polarity](stimgen_StimPlayer.md#alternating-polarity)), and so does
a host that owns presentation (MABR imports it as `alternatePolarity`). This is
the difference from `OnsetPhase = [0 180]`, which makes **two variants** and so
doubles the presentations: alternating keeps one variant and splits its
repetitions between the signs. `alternates_polarity()` reads the active
combination without reselecting, so it describes the waveform in `Signal`.

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

Gaussian noise band-limited between `HighPass` and `LowPass` by a linear-phase FIR
band-pass designed from what its edges must achieve.

- [+stimgen/Noise.m](../+stimgen/Noise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `HighPass` | yes | Hz, lower band edge: the -6 dB point |
| `LowPass` | yes | Hz, upper band edge: the -6 dB point |
| `TransitionWidth` | no | Hz, full width of the transition band centred on each edge. `0` (default) = a tenth of the narrowest of `HighPass`, `LowPass - HighPass` and `Fs/2 - LowPass` |
| `StopbandAttenuation` | no | dB, minimum rejection outside the transition bands (default 60) |
| `FilterOrder` | no | `0` (default) designs from the two settings above. A positive order is used as given with a Hamming window at the cutoffs — the design earlier versions used, at 40 — so a saved stimulus that names an order gets its filter back |

With `FilterOrder = 0` the filter is a Kaiser-window design whose order comes from
`kaiserord` (with a dB of margin): each cutoff sits in the middle of a transition band
`TransitionWidth` wide and everything beyond it is down by at least
`StopbandAttenuation`. At the defaults (500 Hz - 20 kHz at 97656.25 Hz) the transition
is 50 Hz and the filter about 7,000 taps; `tests/NoiseBandTest.m` checks the edges and
the generated spectrum. The 40-tap filter this replaced had a transition several kHz
wide at that rate, so a 500 Hz high-pass left most of the energy below 500 Hz in place.
A positive `FilterOrder` — including the 40 that banks saved by the previous release
carry — keeps that old behaviour; set it to 0 to get edges that mean what they say.

Filters that long run through `fftfilt`, and as many extra samples of noise as the filter's order are
generated and discarded so every kept sample has a full filter history: the record does
not fade in over the filter's length. The taps of the last waveform are on the object
as `FilterCoefficients`, with `DesignedOrder` and `DesignedTransition` (NaN for an
explicit order); they are redesigned only when the band, `Fs` or one of the three
settings changes.

`HighPass` must be above 0, `LowPass` above `HighPass` and below `Fs/2`; a violation
raises `stimgen:Noise:InvalidBand`. A `TransitionWidth` that does not fit the band
raises `stimgen:Noise:InvalidTransition`, and a design needing more than 2^20 taps
raises `stimgen:Noise:FilterTooLong`. `Noise` is also the superclass for `AMnoise` and
`AttackModNoise`, which reuse its carrier generation (`temporarilyDisableSignalMods`
guards the base class's own normalize/calibrate/gate calls while the carrier is only an
intermediate signal).

## AMnoise

`stimgen.Noise` carrier with sinusoidal amplitude modulation.

- [+stimgen/AMnoise.m](../+stimgen/AMnoise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `AMDepth` | yes | modulation depth, 0–1 |
| `AMRate` | yes | Hz |
| `OnsetPhase` | yes | degrees, modulator phase at t=0 |
| `EnvelopeOnly` | no | play the modulator alone (no carrier) — useful for verifying envelope shape |

Inherits `HighPass`/`LowPass` and the filter settings from `Noise`. The modulated waveform is
rms-normalized before calibration, so the rms of the delivered waveform does not depend
on `AMDepth`; no separate power compensation is needed. (An earlier `ApplyViemeisterCorrection`
option scaled the envelope by a constant that this normalization divided straight back
out, so it never changed the output; it has been removed, and older banks that still
carry it load with the field ignored.)

## AttackModNoise

`stimgen.Noise` carrier with a ramped/damped attack-and-decay modulation envelope
(one period repeated to fill `Duration`), rather than a sinusoid.

- [+stimgen/AttackModNoise.m](../+stimgen/AttackModNoise.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `AMRate` | yes | Hz, sets the modulation period `1/AMRate` |
| `Z` | yes | -1–1, envelope shape: negative ramps up (attack), positive damps down (decay) |
| `EnvelopeOnly` | no | play the modulator alone (no carrier) |

There is no depth parameter: the envelope always runs from zero to its peak, with its
shape set by `Z`. The `AMDepth` and `ApplyViemeisterCorrection` properties this class
used to carry fed only a constant factor that rms normalization removed, so neither
changed the output; both have been removed, and an older bank that still lists them
loads with those fields ignored. (A vectorized `AMDepth` in such a bank made variants
that were identical waveforms; it no longer adds variants.)

Unlike `AMnoise`, there is no `OnsetPhase`: the envelope's phase is fixed by
construction (one period of the `Z`-shaped envelope, repeated from t = 0). The unused `OnsetPhase`
and the broken `AddOnOffperiods` option (it doubled the envelope's length, so it either
errored against the carrier or returned a waveform twice `Duration` long) have been
removed.

## FMtone

Sine carrier with sinusoidal frequency modulation (true instantaneous-frequency
integration, not a simple phase wobble).

- [+stimgen/FMtone.m](../+stimgen/FMtone.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `CarrierFrequency` | yes | Hz, center frequency |
| `ModulationFrequency` | yes | Hz, modulator rate; `0` collapses to a pure tone at `CarrierFrequency` |
| `ModulationDepth` | yes | Hz, peak deviation of instantaneous frequency |
| `OnsetPhase` | yes | degrees, carrier phase at t=0 (same convention as `Tone`/`AMnoise`) |

`OnsetPhase` used to be in radians. It is now degrees like every other stimulus, so a
saved non-zero `FMtone` `OnsetPhase` from an older bank is reinterpreted (1 rad is
read as 1°); the default of 0 is unaffected.

`CalibrationType` is `"filter"` rather than `"tone"` — an FM tone sweeps a band, so it
is calibrated like broadband material (equalizer/filter LUT) rather than looked up at
a single frequency.

## ClickTrain

Train of rectangular clicks at `Rate`, each `ClickDuration` long, filling `Duration`.

- [+stimgen/ClickTrain.m](../+stimgen/ClickTrain.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `Rate` | yes | Hz, click repetition rate |
| `Polarity` | yes | `1` positive, `-1` negative, `0` alternating click by click within the train, `2` alternating whole presentations |
| `ClickDuration` | yes | seconds; must be ≤ `1/Rate` |
| `OnsetDelay` | yes | seconds before the first click |
| `Truncate` | yes | if false, zero-pads to `Duration` instead of cutting a partial train |
| `ClickInterval` | — | read-only, `1/Rate` |

Also read-only via the `Dependent` `ClickInterval`. Construction disables the
inherited window (`ApplyWindow = false`, `WindowFcn = ""`) because clicks are
already discrete pulses, not a continuous tone needing onset/offset ramping.
`ClickDuration` too long for `Rate`, or shorter than one sample at `Fs`, raises
`stimgen:ClickTrain:ClickDuration:InvalidValue`. The two alternating modes answer different questions. `0` flips each click
inside the train, so the waveform itself alternates and every presentation is
the same. `2` generates the positive train and returns `alternates_polarity()`
true, so the presenter inverts every other presentation of it — exactly as a
`Tone` with `Polarity = 0` does (see
[Alternating polarity](stimgen_StimPlayer.md#alternating-polarity)). A
single-click stimulus (`Duration` shorter than one `ClickInterval`) needs `2`:
with one click there is nothing to alternate within, so `0` plays every
presentation positive. Like the Tone's, `2` keeps one variant and splits its
repetitions between the signs.

`CalibrationType` is `"click"`: the
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

## DMR

Dynamic moving ripple (DMR) and ripple noise (RN) — a broadband sound whose
spectrotemporal envelope is a sinusoidal ripple on a log-frequency axis, with a ripple
density Ω(t) and a temporal modulation rate Fm(t) that wander slowly and randomly.
Ripple noise is the same carrier bank driven by the sum of several independent DMR
envelopes. Implements the stimulus of Escabí & Schreiner (2002), *Nonlinear
spectrotemporal sound analysis by neurons in the auditory midbrain*, J Neurosci
22(10):4114–4131, [doi:10.1523/JNEUROSCI.22-10-04114.2002](https://doi.org/10.1523/JNEUROSCI.22-10-04114.2002);
equation numbers below and in the source refer to that paper.

- [+stimgen/DMR.m](../+stimgen/DMR.m)

| Property | Vectorizable | Default | Meaning |
| --- | --- | --- | --- |
| `LowFrequency` | no | 500 | Hz, f₁ — the lowest carrier and the origin of the octave axis |
| `HighFrequency` | no | 20000 | Hz, the end of the carrier range; the top carrier is one step below it |
| `NumCarriers` | no | 230 | geometrically spaced carriers |
| `EnvelopeMode` | no | `"DMR"` | `"DMR"` \| `"RippleNoise"` |
| `NumEnvelopes` | no | 16 | L, independent DMR envelopes summed for ripple noise; ignored in DMR mode |
| `RippleDensityMin` / `Max` | no | 0 / 4 | cycles/octave, range of Ω |
| `RippleDensityChangeRate` | no | 3 | Hz, maximum rate of change of Ω; knots are drawn at twice this |
| `ModulationRateMin` / `Max` | no | −350 / 350 | Hz, range of Fm (signed: the sign is the direction of travel) |
| `ModulationRateChangeRate` | no | 1.5 | Hz, maximum rate of change of Fm; knots are drawn at twice this |
| `ModulationDepth` | yes | 30 | dB peak-to-peak, M (the paper used 30 and 45) |
| `ErfScaling` | no | `"Uniform"` | `"Uniform"` \| `"AsPrinted"` — see below; not a paper value |
| `Seed` | yes | 1 | non-negative integer fixing every random draw; not a paper value |

Every default except `ErfScaling` and `Seed` is the value the paper states. Construction
sets `Duration = 1` s and `WindowDuration = 10` ms, which are toolbox choices: the paper
presented the stimulus continuously for 10–20 minutes (and a 5 s segment, repeated, to a
subset of neurons).

Read-only outputs, refreshed by every `update_signal`: `CarrierFrequencies`,
`CarrierPhases`, `OctaveAxis`, `RawRms`, `RawPeak`.

**What the paper specifies.**

| Item | As stated in the paper |
| --- | --- |
| DMR envelope (Eq. 1) | `S(t,X_k) = M/2·sin[2πΩ(t)X_k + Φ(t)]` in dB, `X_k = log2(f_k/f_1)`, `f_1` = 500 Hz, `Φ(t) = ∫₀ᵗ Fm(τ)dτ` |
| Ω and Fm | independent; flat-distributed on 0–4 cycles/octave and −350…+350 Hz; maximum rates of change 3.0 Hz (Ω) and 1.5 Hz (Fm) |
| Trajectories | `randn` sequences sampled at 6 Hz (Ω) and 3 Hz (Fm), upsampled with `interp1`'s `'cubic'` option, passed through `erf` to map normal onto uniform amplitudes on −1…+1, then rescaled linearly |
| Ripple noise (Eq. 2–3) | `S̄ = (1/√L)·Σ S_DMR,l`, L = 16; `S_RN = M/2·erf(S̄/σ_DMR)`; `σ²_DMR = M²/8`, `σ²_RN = M²/12` |
| Waveform (Eq. 4–5) | `s(t) = Σ_k S_Lin(t,X_k)·sin(2πf_k t + φ_k)`, 230 carriers, `φ_k` random on 0–2π, `S_Lin = 10^((S − M/2)/20)` |
| Carriers | `f_k = α·f_(k−1)`, α = 1.01617, "43 carriers per octave", 5.32 octaves (500–20,000 Hz) |
| Sample rate | 44.1 kHz |
| Envelope for the STRF | sampled at 4 kHz in time, 43 samples per octave |

**Where this class reads or departs from the paper as printed.** Each is also named in
every generation record (`rec.Rules`).

- **Phase.** Eq. 1 prints `Φ = ∫Fm` without 2π. Fm is in Hz and Eq. 7 has `2πF_m τ`, so
  the class uses `Φ(t) = 2π∫₀ᵗ Fm`.
- **Carrier grid.** `(20000/500)^(1/230)` is 1.016168, which rounds to the printed α;
  `2^(1/43)` is 1.016250, which does not. The grid is therefore `NumCarriers` steps of
  `α = (HighFrequency/LowFrequency)^(1/NumCarriers)` from `LowFrequency`: 43.2 carriers per
  octave at the defaults, the top one at 19,682 Hz. A top carrier at or above Nyquist
  raises `stimgen:DMR:BandwidthExceedsNyquist`.
- **erf scaling.** The paper says `erf` maps normally distributed amplitudes onto
  uniformly distributed ones and reports `σ²_RN = M²/12`, the variance of a uniform
  distribution on [−M/2, M/2]. For a normal variable of standard deviation σ that
  requires `erf(x/(√2·σ))`. Eq. 3 and the parameter mapping are printed as `erf(x/σ)`,
  which gives `σ²_RN = M²/8.61` and a distribution weighted toward its limits.
  `ErfScaling = "Uniform"` (default) is the first, `"AsPrinted"` the second; it applies to
  the Ω and Fm trajectories and to the ripple-noise compression alike. The trajectories
  are only approximately flat either way, because the values between knots are
  interpolated before `erf` is applied — as in the paper.
- **Interpolant.** The meaning of `interp1`'s `'cubic'` option has changed between MATLAB
  releases, and the paper does not say which release it used. The class writes out cubic
  convolution (Keys, a = −½) over the four nearest knots, so the result does not depend on
  the release; `tests/DMRTest.m` compares it with `interp1` on the release the suite runs
  on.
- **Phase integral.** The paper does not say how the integral was evaluated. Here it is a
  fixed 32-point Gauss–Legendre rule per knot interval, accumulated at the knots. Ω(t),
  Fm(t) and Φ(t) are then functions of t alone — independent of `Fs` and of the grid they
  are asked for on — so synthesis and `envelope_at` evaluate one function.
- **Random numbers, segments, channels.** The paper gives no generator or seeds, and
  presented an independent sequence to each ear. The class makes one-channel segments,
  each starting at Φ = 0. It reproduces the published method, not the authors' stimulus
  files.

**Seeds and segments.** A waveform is a pure function of the properties, `Fs` and
`GeneratorVersion`. `Seed` must be a non-negative integer — there is no "reseed randomly"
value, because a stimulus whose seed was never recorded cannot be reconstructed.
Vectorizing it makes each seed a variant, so a `StimPlayer` run presents a different
segment per trial and logs which:

```matlab
s = stimgen.DMR('Duration', 5, 'Seed', 1:40);   % 40 five-second segments
s.update_signal;
s.plot_dynamic_spectrum
```

**Draw contract (`GeneratorVersion`, currently 1).** Random numbers come from a private
`RandStream('mrg32k3a','Seed',Seed,'NormalTransform','Inversion')` — the global stream is
never touched — with one substream per quantity:

| Substream | Draw |
| --- | --- |
| 1 | carrier phases, `2π·rand(1,NumCarriers)` |
| 10·l + 1 | envelope l: ripple-density knots, `randn` |
| 10·l + 2 | envelope l: modulation-rate knots, `randn` |

Changing the carrier count, the number of envelopes or `Duration` therefore leaves the
other draws as they were; a longer `Duration` appends knots, so a longer segment starts
with the shorter one's envelope. Knot j sits at j/rate seconds for j = −1, 0, 1, …. Any
change to the generator, the substream map, the knot grid, the interpolant, the erf
mapping, the phase quadrature, the carrier grid, the amplitude expression, the ripple-noise
combination or the summation order changes the waveform a seed produces and must bump
`GeneratorVersion`.

**Reconstructing what was played.** The envelope must be recoverable for reverse
correlation, so three things are kept:

- `rec = s.generation_record()` — the base record
  ([stimgen_StimType.md](stimgen_StimType.md#generation-record)) plus the seed, carriers
  and phases, every knot (the normal draws themselves), the running phase integral at the
  knots, the quadrature rule, the rule names, `RawRms`/`RawPeak`, the gate that was
  applied and `GenerationSeconds`. It is captured when `Signal` is made and is sufficient
  to rebuild the waveform without this class's random number generator;
  `tests/DMRTest.m` does exactly that.
- `[S, x] = s.envelope_at(t)` — the envelope in dB (−M/2 … M/2) at arbitrary times;
  `[S, t, x] = s.dynamic_spectrum(nTime)` on an even grid (the `TORC` contract);
  `tr = s.ripple_trajectory(nTime)` — Ω, Fm and Φ.
- `s.export_envelope(file, 'SampleRate', 4000)` — writes all of the above to one MAT
  file for every seed, so an analysis does not depend on this class regenerating the
  same numbers later (see below).
- The envelope is **not gated**: the onset/offset window is applied to the waveform
  afterwards and is described by `rec.Gate`.

**Envelope export.** `export_envelope(file, 'SampleRate', fs, 'Combinations', idx)`
generates each variant combination on a pinned copy — the object it is called on keeps
its `Signal`, active combination and selection order — and writes a version 7.3 MAT
file, in double precision, one combination at a time (so only one envelope matrix is in
memory, and a reader can load one combination without the rest). `SampleRate` defaults
to 4000 Hz, the rate the paper sampled its envelopes at, and is written into the file;
a rate below twice the fastest modulation rate raises `stimgen:DMR:EnvelopeRateTooLow`
before anything is written. An existing file is replaced.

| Variable | Contents |
| --- | --- |
| `FormatVersion`, `GeneratorVersion`, `CreatedAt` | 1; the draw contract; local time |
| `Source` | the stimulus's `toStruct` — restore with `stimgen.StimType.fromStruct` |
| `EnvelopeFs`, `Gated`, `EnvelopeUnits` | the sample rate used; `false`; text |
| `Seed`, `VariantIndex`, `RawRms`, `RawPeak` | one value per combination written |
| `CombinationVariables` | names of the per-combination variables |
| `C0001`, `C0002`, … | one struct per combination, named by its variant index |

Each `Cnnnn` holds `Seed`, `VariantIndex`, `Time` (`(0:nT-1)/EnvelopeFs`), `OctaveAxis`,
`CarrierFrequencies`, `Envelope` (carriers × time, dB), `Omega`, `Fm`, `Phase`
(envelopes × time) and `Record` (that segment's generation record).

```matlab
s = stimgen.DMR('Duration', 5, 'Seed', 1:40);
s.export_envelope('dmr_envelopes.mat');          % 40 segments at 4 kHz
m = matfile('dmr_envelopes.mat');
c = m.C0007;                                     % the segment StimVariant 7 played
imagesc(c.Time, c.OctaveAxis, c.Envelope); axis xy
```

**Level.** `SoundLevel` is the overall rms level of the segment, as for `Noise` and
`TORC`. The paper states levels per carrier and gives the overall level of its 230-carrier
stimuli as `10·log10(230)` = 23.6 dB above them. Each segment is normalized to
its own rms before calibration, so realizations differ slightly in how their envelope
maps to absolute level; `RawRms` and `RawPeak` hold the figures before normalization.

**Cost.** Synthesis is `NumCarriers × (NumEnvelopes + 2)` transcendental evaluations per
sample, so ripple noise with 16 envelopes costs about six times a DMR. `StimPlayer`
resynthesizes the presented stimulus inside its timer after every trial, so with a new
seed per trial the ISI has to leave room for it (`generation_record().GenerationSeconds`
reports what a generation took). The last synthesis is cached: presenting the same seed
again, or editing only `SoundLevel`, the gate or the calibration, does not synthesize
again.

## SoundFile

Playback of a catalog of pregenerated sound files (vocalizations, phonemes, natural
scenes) rather than a synthesized waveform. `FileIndex` is the vectorizable variant
axis, `Duration` is derived from the selected file, and calibration/normalization are
selected per instance (`CalibrationMode`, `LevelReference`) rather than fixed
`Constant`s. Full reference: [stimgen_SoundFile.md](stimgen_SoundFile.md).

- [+stimgen/SoundFile.m](../+stimgen/SoundFile.m)

## BackgroundAM

Amplitude modulation of an ongoing background for `Duration` seconds. The background
is the inherited `Background` (band-passed noise by default, or a tone) at `SoundLevel`;
a presenter that plays it continuously applies the gain

```
G(t) = 1 + AMDepth * w(t) * sin(2*pi*AMRate*t + OnsetPhase)
```

at each presentation, where `w` is the gate applied to the *modulation* (the background
is never gated).

- [+stimgen/BackgroundAM.m](../+stimgen/BackgroundAM.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `AMRate` | yes | Hz |
| `AMDepth` | yes | 0-1 about the steady level: gain between `1 - depth` and `1 + depth` |
| `OnsetPhase` | yes | degrees, of the modulator. Default 0: the envelope leaves the steady level rising |

`Duration` defaults to 0.5 s (five cycles at the default 10 Hz). Unlike
[`AMnoise`](#amnoise) nothing is renormalized: `SoundLevel` is the steady background's
level, and the modulated epoch is louder than it by `10*log10(1 + AMDepth^2/2)`
(1.76 dB at full depth). `Signal` is the stand-alone rendition — the background for
`Duration` with the modulation applied.

## BackgroundGap

A gap in an ongoing background: its gain is `G(t) = 1 - GapDepth * w(t)` for
`Duration` seconds.

- [+stimgen/BackgroundGap.m](../+stimgen/BackgroundGap.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `GapDepth` | yes | 0-1. 1 = silence; less is a decrement of `20*log10(1 - depth)` dB |

`Duration` (default 20 ms) is the whole gap, ramps included; `WindowDuration` is the
fall plus the rise (each half), and `ApplyWindow = false` makes the gap rectangular.

## BackgroundFM

Frequency modulation of an ongoing tone. The background must be `"Tone"` (the default
for this class, at `BackgroundFrequency`); its instantaneous frequency deviates by

```
df(t) = FMDeviation * w(t) * sin(2*pi*FMRate*t + OnsetPhase)      [Hz]
```

and the phase deviation handed to a presenter is the running integral of that, starting
at 0. The tone's amplitude never changes and it never stops: whatever phase the
modulation ends on is where the tone carries on from.

- [+stimgen/BackgroundFM.m](../+stimgen/BackgroundFM.m)

| Property | Vectorizable | Meaning |
| --- | --- | --- |
| `FMRate` | yes | Hz |
| `FMDeviation` | yes | Hz, peak deviation from `BackgroundFrequency` |
| `OnsetPhase` | yes | degrees, of the modulator |

A noise background is refused (`stimgen:BackgroundFM:NeedsToneBackground`). Unlike
[`FMtone`](#fmtone), a gated burst, this has no onset of its own.

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
- [stimgen_Background.md](stimgen_Background.md) — ongoing backgrounds and the stimuli embedded in them
- [stimgen_overview.md](stimgen_overview.md) — package orientation
