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

## Opening it

From `StimPlayer`, use the **Inspect Stimulus** toolbar button or
**File > Inspect Stimulus** (`Ctrl+I`). The button opens the window, or raises
it if it is already open — there is only ever one inspector per player. The
window then follows the player: changing the bank selection, editing a
parameter or stepping the variant combination all refresh it.

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
| `Waveform` | Waveform with its analytic envelope and ±RMS markers, over the envelope in dB re peak — the dB view is where an onset/offset ramp shape is actually readable |
| `Spectrum` | Single-sided magnitude spectrum, log or linear frequency axis, with markers at the harmonics found by `thd()` |
| `Spectrogram` | Power spectrogram at a selectable FFT length (128–2048) and window, log or linear frequency axis |
| `Distortion` | Harmonic levels relative to the fundamental, as a bar chart and a table of frequency / dBc / percent |

Only the visible tab is redrawn. A full refresh runs on every parameter edit in
`StimPlayer`, and drawing one set of axes instead of four keeps that
interactive. The tab group's `SelectionChangedFcn` brings a tab up to date as
it is selected.

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

## Variant safety

Reading a vectorized property through `selected_value()` outside a locked
update cycle *reselects* the active variant when `VariantReselectOnUpdate` is
true (see `get_selected_property_value_`). A window that refreshes on every
edit therefore must not use it, or merely looking at a stimulus would step it.

The inspector avoids this by construction:

- the time base comes from `numel(Signal)` and `Fs`, never from `StimType.Time`
  (which reads `Duration` through the variant selector)
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
  and `metrics`

## Related files

- [+stimgen/@StimInspector/StimInspector.m](../+stimgen/@StimInspector/StimInspector.m)
- [+stimgen/@StimInspector/signal_metrics.m](../+stimgen/@StimInspector/signal_metrics.m)
- [+stimgen/@StimPlayer/open_stim_inspector.m](../+stimgen/@StimPlayer/open_stim_inspector.m)

## Related documentation

- [stimgen_overview.md](stimgen_overview.md) — package orientation
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md) — the bank editor that hosts it
- [stimgen_StimType.md](stimgen_StimType.md) — stimulus properties and variants
