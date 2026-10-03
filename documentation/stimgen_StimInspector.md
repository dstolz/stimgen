# `stimgen.StimInspector`

`stimgen.StimInspector` is a read-only detail window for a single stimulus. It
shows the waveform, its envelope, the magnitude spectrum, a spectrogram and a
harmonic-distortion breakdown, alongside a table of measured signal properties
and the stimulus parameters that produced them.

It exists because the `StimPlayer` signal plot answers "roughly what does this
look like", and some questions need more: *is the gate ramp the shape I asked
for, is the noise band where I set it, how much harmonic distortion does this
click train actually have, is the level clipping.*

The window never writes to the stimulus. In particular it never advances the
variant cycle, so opening it cannot change which combination a stimulus is
currently presenting (see [Variant safety](#variant-safety)).

It also reads **microphone recordings**. A `stimgen.CapturedSignal` that came
with a microphone sensitivity is shown as sound — pascals and dB SPL, with
sound-level-meter readouts, band levels, the noise floor under it, and the
level its stimulus asked for against the level that came back. See
[Recordings](#recordings-sound-pressure-and-db-spl).

## Opening it

From `StimPlayer`, use the **Inspect Stimulus** toolbar button or
**File > Inspect Stimulus** (`Ctrl+I`). The button opens the window, or raises
it if it is already open — there is only ever one inspector per player. The
window then follows the player: changing the bank selection, editing a
parameter or stepping the variant combination all refresh it.

`StimPlayer`'s **Capture Selected Stimulus** opens a second inspector — the
*capture inspector*, titled `Stimulus Inspector — Recording` — on what came
back through the microphone. `stimgen.SpotCheck` opens the same kind of window
on its recording.

Standalone, on any `stimgen.StimType`:

```matlab
t = stimgen.Tone;
t.Frequency = 4000;
t.update_signal;
stimgen.StimInspector(t, "my tone");
```

## Tabs

| Tab | Shows |
| --- | --- |
| `Waveform` | Waveform with its analytic envelope and ±RMS markers, over the envelope in dB re peak — the dB view is where an onset/offset ramp shape is actually readable. A recording shown as sound: pressure in Pa, over the envelope in dB SPL with the noise floor drawn across it |
| `Spectrum` | Single-sided magnitude spectrum, log or linear frequency axis, with markers at the harmonics found by `thd()`. **Density (per Hz)** divides out the bin width; **Noise floor** draws a recording's pre-stimulus silence underneath |
| `Spectrogram` | Power spectrogram at a selectable FFT length (128–2048) and window, log or linear frequency axis, per bin or as a density |
| `Distortion` | Harmonic levels relative to the fundamental, as a bar chart and a table of frequency / dBc / percent, plus each harmonic's own level (dB SPL for a recording shown as sound) |
| `Bands` | Octave, 1/3-, 1/6- or 1/12-octave band levels, Z/A/C weighted, with a recording's noise floor in the same bands and the SNR per band |
| `Sound Level` | What a sound level meter would read: the Fast or Slow time-weighted level against time, over a table of Leq, Lpeak, LFmax, LSmax and LE for Z, A and C, plus peSPL and ppeSPL |

Only the visible tab is redrawn. A full refresh runs on every parameter edit in
`StimPlayer`, and drawing one set of axes instead of six keeps that
interactive. The tab group's `SelectionChangedFcn` brings a tab up to date as
it is selected. The Bands and Sound Level tabs work on any stimulus; for one
without a microphone scale their levels are dB re 1 (dBV for a record in volts).

Time axes are in **milliseconds**, matching the rest of the package.

The spectrogram is drawn as an image on a linear frequency axis but as a
flat-shaded `surface` on a log one. MATLAB transforms an image object by its
four corners only, so a log axis smears the whole image into a wedge; a surface
is transformed per face and stays correct. The log view also drops the DC bin,
whose lower cell edge falls below 0 Hz.

## Measurements

`stimgen.StimInspector.signal_metrics(y, fs)` is a static method and is usable
on its own:

```matlab
M = stimgen.StimInspector.signal_metrics(y, fs);
```

It returns a struct covering:

- **Level** — peak, peak-to-peak, RMS, DC offset, crest factor, and peak/RMS in
  dB. Amplitudes are relative to full scale (1.0), so a calibrated signal
  scaled to volts reads in dBV rather than dBFS.
- **Spectrum** — the plotted single-sided spectrum, the fundamental (refined by
  parabolic interpolation across the peak), spectral centroid, RMS bandwidth,
  spectral flatness, and the −3 dB and −20 dB bands.
- **Distortion** — THD in percent and dB, plus SNR, SINAD and SFDR, from the
  Signal Processing Toolbox `thd`, `snr`, `sinad` and `sfdr` functions.

The spectrum uses a Hann window corrected for its coherent gain, so a
full-scale sinusoid reads 0 dB at its own frequency.

`M.Valid` is false — and every measurement `NaN` — when the waveform is
shorter than 8 samples, constant, or non-finite. Each distortion estimator is
computed independently and left at `NaN` if it fails, so one bad estimate never
blanks the rest.

### Tonality, and when the distortion numbers mean anything

THD, SNR, SINAD and SFDR all assume the signal is a sinusoid plus unwanted
extras. That assumption is false for most stimuli in this package: for noise,
"THD" is measuring the noise against an arbitrarily chosen peak.

`M.Tonality` is the fraction of spectral power falling within a few resolution
cells of the dominant peak: ~1.0 for a pure tone, near zero for anything
broadband. `M.Tonal` is `Tonality > 0.5`, and when it is false the status bar
says so explicitly. The numbers are still reported — they are useful for
comparing a stimulus against itself across parameter changes — but they should
not be read as distortion figures.

## Recordings: sound pressure and dB SPL

A recording is volts at the converter. What makes it sound pressure is the
microphone sensitivity of the chain it came through, and a
`stimgen.CapturedSignal` carries that number with its samples
(`MicSensitivity`, V/Pa) — copied in at capture time rather than looked up
through a calibration handle, so reloading a calibration later cannot silently
change the level of a record already taken. When it is there, every view
switches to sound:

- **Waveform** in pascals; **envelope** in dB SPL, on the rms scale of a sine
  with that envelope, so a steady tone's envelope reads its own level
- **Spectrum** and **spectrogram** in dB SPL per bin, or dB SPL/Hz with
  **Density (per Hz)** checked
- **Distortion** gains each harmonic's level in dB SPL — how a distortion
  product is judged against threshold rather than against its own fundamental
- **Bands** and **Sound Level** in dB re 20 µPa

Every one of those levels goes through
`stimgen.calibration.Engine.volts_to_spl`, the package's single conversion
from volts to dB SPL (`StimInspector.to_db_` is the one call site in the
window). The header shows the sensitivity in use.

The **Units** control at the top right switches the same record to volts —
**Signal (V, dB re 1 V)** — which is the view for input-stage headroom. It is
enabled only for a record that has a sensitivity; a generated stimulus, or a
record captured with no calibration loaded, is shown exactly as it always was.

### The metrics table for a recording

| Section | Rows |
| --- | --- |
| Sound pressure | peak, peak-to-peak and rms in Pa; DC offset in V (an input-stage offset, removed before every level below); crest factor; the sensitivity |
| Sound level | LZeq, LAeq, LCeq, LZpeak, LCpeak, peSPL, ppeSPL, LAFmax, LASmax, LAE |
| Against the request | the level the stimulus asked for, the level measured the way its calibration table was measured, what that measurement was, and the error. `(nominal)` marks a request that was never calibrated, and then there is no error to report |
| Noise floor | LZeq and LAeq of the silence recorded just before the stimulus, and the SNR against each |
| Capture | conduction delay, acquisitions averaged, lead-in and tail, and the rate the stimulus was regenerated at when the hardware's differed from the bank's |

The comparison with the request uses the same rule `stimgen.SpotCheck` does,
through the same code (`stimgen.util.level_request` and
`stimgen.util.level_as_calibrated`): spectral rms at the tone frequency for a
tone, peak as an rms equivalent for a click or a peak-referenced sound file,
broadband rms for everything else, with the calibration's own spectral window.

A recording's **warnings** — clipping, a delay search that hit its bound, a
level too close to the floor, averaging, an uncalibrated request — are listed
in a panel between the two tables, where a sentence has room to be read. The
panel folds away when there are none.

The parameter table becomes **Played: *class*** and lists the parameters of
the stimulus as it was played — the recording's `Played` snapshot, taken at
capture time, so editing the bank afterwards does not change what the
recording says produced it.

### The sound level meter

`stimgen.util.sound_levels(y, fs, micSens)` computes the Sound Level tab's
readouts and is usable on its own:

| Readout | Meaning |
| --- | --- |
| `Leq` | equivalent continuous level: the rms of the weighted record |
| `Lpeak` | the largest instantaneous weighted value (LCpeak is a meter's default peak) |
| `LFmax`, `LSmax` | maximum Fast (125 ms) and Slow (1 s) exponentially time-weighted level |
| `LE` | sound exposure level, energy re 1 s — for a stimulus shorter than a second, the number that does not depend on how much silence surrounds it |
| `peSPL` | rms level of a sine with the same peak (peak ÷ √2) — the scale the click table is built on |
| `ppeSPL` | rms level of a sine with the same peak-to-peak |

The A and C weightings are the IEC 61672-1 analog networks themselves,
evaluated on the record's FFT grid and applied to the waveform: the exact
magnitude — the curve `stimgen.util.weighting_db` draws — and the network's
own minimum phase, up to Nyquist at any sample rate. A bilinear-transformed
IIR, the usual digital realization, would have been simpler and wrong where it
matters: on a 48 kHz converter it puts the A curve 7 dB low at 16 kHz. Z is no
weighting at all over the full band up to Nyquist, rather than the
10 Hz – 20 kHz a Z-weighted meter guarantees, because on a rig presenting
ultrasonic stimuli the band above 20 kHz is the point.

Two things a meter would also do, and so this does too:

- **Short records read low on Fast and Slow.** The time weightings start from
  zero at the first sample, and a 5 ms tone pip never charges a 125 ms
  average; its LAFmax reads well below its Leq. Leq, LE and the peak levels
  are the ones to trust for brief stimuli.
- **A stimulus switched on abruptly excites the weighting network.** Over a
  record of a low-frequency tone that transient adds a little energy — about
  0.1 dB to a one-second 31.5 Hz tone.

DC is removed before anything is measured.

### Bands

Band levels are integrated from a Hann periodogram of the whole record through
`stimgen.util.band_levels`, the same IEC 61260 base-ten band arithmetic the
calibration's background analysis uses, and weighted at each band centre. A
band is only reported once the record resolves it — its lower edge at least
five resolution cells up — so a short tone pip shows fewer low bands rather
than one-bin guesses labelled as bands. Octave and third-octave centres are
labelled with their nominal values (1k, 1.25k, 3.15k …).

## Variant safety

Reading a vectorized property through `selected_value()` outside a locked
update cycle *reselects* the active variant when `VariantReselectOnUpdate` is
true (see `get_selected_property_value_`). A window that refreshes on every
edit therefore must not use it, or merely looking at a stimulus would step it.

The inspector avoids this by construction:

- the time base comes from `numel(Signal)` and `Fs`, never from `StimType.Time`
  (which no longer reselects, but describes the nominal `Duration` rather than
  the samples actually present)
- `Fs` is non-vectorizable, so reading it directly is safe
- the parameter table shows **raw** property values, listing vectorized
  properties in full and tagging them `(variant)`; the active combination is
  reported separately from `get_variant_info()`

## Following a moving selection

`set_source(stimObj, label)` pins the window to one object.
`set_source_provider(fcn)` instead stores a function that is re-run on every
refresh, returning `[stimObj, label]`:

```matlab
insp = stimgen.StimInspector;
insp.set_source_provider(@() deal(myStim, "current"));
insp.refresh    % re-resolves through the provider
```

`StimPlayer` uses the provider form (`StimPlayer.inspector_source_`), so the
inspector re-resolves the bank selection every time rather than holding a
stimulus handle that could go stale when the item is removed. A provider that
returns empty clears the window.

## Toolbar

- **Recompute From Stimulus** — force a refresh
- **Play Displayed Signal** — audition through the sound card (`StimType.play`)
- **Export Signal and Metrics to Workspace** — assigns a struct to the base
  workspace variable `stimInfo` with fields `label`, `class`, `Fs`, `signal`
  and `metrics`. A recording adds `units`, `mic_sensitivity`, `sound_levels`,
  `noise_levels`, `as_calibrated`, `request` and `warnings`, in the units on
  screen, so the numbers in the window travel with it

## Related files

- [+stimgen/@StimInspector/StimInspector.m](../+stimgen/@StimInspector/StimInspector.m)
- [+stimgen/@StimInspector/signal_metrics.m](../+stimgen/@StimInspector/signal_metrics.m)
- [+stimgen/@StimPlayer/open_stim_inspector.m](../+stimgen/@StimPlayer/open_stim_inspector.m)
- [+stimgen/@StimPlayer/capture_stim.m](../+stimgen/@StimPlayer/capture_stim.m) — opens the capture inspector
- [+stimgen/@CapturedSignal/CapturedSignal.m](../+stimgen/@CapturedSignal/CapturedSignal.m) — a recording, with its scale
- [+stimgen/+util/sound_levels.m](../+stimgen/+util/sound_levels.m) — the sound level meter
- [+stimgen/+util/band_levels.m](../+stimgen/+util/band_levels.m) — fractional-octave bands
- [+stimgen/+util/level_request.m](../+stimgen/+util/level_request.m), [+stimgen/+util/level_as_calibrated.m](../+stimgen/+util/level_as_calibrated.m) — the level a stimulus asked for, and how to measure it

## Related documentation

- [stimgen_overview.md](stimgen_overview.md) — package orientation
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md) — the bank editor that hosts it
- [stimgen_StimType.md](stimgen_StimType.md) — stimulus properties and variants
