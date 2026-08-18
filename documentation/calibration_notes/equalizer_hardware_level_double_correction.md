# Equalizer level applied twice in hardware: `Norm` = unityGainSpl and `Gain` = scale are the same correction

<!-- summary: Why an RPvds chain that sets both Norm to unityGainSpl and Gain to scale plays 12.7 dB too quiet, and which of the two numbers to keep -->

*2026-08-18. From reviewing an RZ6 noise-playback circuit against the calibration
GUI's Unity-Gain Noise Level readout; kept because the two figures are the same
correction wearing different units, and nothing in either the circuit or the GUI
says so.*

## Observation

Calibration GUI, filter designed: **Normative Value 60.0 dB SPL**, **Unity-Gain
Noise Level 72.7 dB SPL (x0.232)**.

RPvds chain on the RZ6 — `SoundOut -> FIR (Order=255, taps as exported) ->
ScaleAdd -> DAC-A`, with the scalar built as
`dBToLin(NoisedBSPL - Norm) x Gain`. The protocol wrote all three tags at
runtime: `Norm = 72.7`, `Gain = 0.232`, `NoisedBSPL = 60`.

Intended output 60 dB SPL. Inferred actual: **47.3 dB SPL**, 12.7 dB low. Not
verified acoustically at the time of writing — see the check below.

## Explanation

`Engine.filter_level_reference` returns the FIR's insertion gain twice, once as a
dB anchor and once as a linear factor. From `filter_level_reference.m`:

    unityGainSpl = NormativeValue - 20*log10(scale)
    72.7         = 60             - 20*log10(0.232)   =  60 + 12.68

Either number alone removes the +12.7 dB the raw taps add; using both removes it
twice:

    dBToLin(60 - 72.7) = 0.2317      <- already lands the source at 60 dB SPL
    x Gain 0.232                     <- the same 12.7 dB, a second time
    = 0.0537  ->  72.7 - 25.4 = 47.3 dB SPL

The correction is needed at all because nothing renormalizes after the FIR in
hardware. In software `apply_calibration` renormalizes the filtered waveform
before scaling it to the LUT voltage; a `source -> FIR -> gain -> DAC` chain has
no such step, so the taps' insertion gain lands directly on the output level.
`Copy Filter Coefficients` exports the taps **unscaled** (`tf(filt)` at `%.17g`,
no `scale` applied), which is why both correction styles are available and why
neither is automatic.

The tell: `20*log10(Gain)` equals `NormativeValue - Norm` exactly. A second tell
is that the error hides when the playback level happens to equal the Normative
Value — 60 and 60 here — because the `dBToLin` term is then exactly 1 in the
*correct* configuration, so the two configurations differ only by `Gain`.

## Practical consequences

- Pick one anchor, never both. **A:** `Norm = r.unityGainSpl`, `Gain = 1`.
  **B (preferred):** `Norm = r.normativeValue`, `Gain = r.scale`. Both give a
  scalar of ~0.232 at 60 dB SPL, so headroom is identical.
- B is preferred because `Norm` then keeps meaning what its name says — the LUT
  anchor, matching the GUI field and stable across redesigns — while the one
  quantity that changes with every `design_filter` (the taps' norm) lives alone
  in `Gain`. Under A, `Norm` must be rewritten after each redesign but still
  reads like a fixed rig constant.
- Refresh the values from a fresh `r = eng.filter_level_reference(1)` after
  **every** `design_filter`; `r.scale` and `r.unityGainSpl` both move with the
  taps.
- `r = filter_level_reference(1)` assumes a 1 V RMS spectrally white source, for
  which the filtered RMS is `1 * norm(b)`. Pass the actual waveform when the
  source is shaped or band-limited ahead of the FIR.
- Unaffected: software playback through `apply_calibration` (it renormalizes),
  the LUT itself, and unequalized hardware chains with no FIR — none of them
  carry an insertion-gain term.
- To check: play the noise at a known `NoisedBSPL` and measure with the
  calibration microphone (Test Filter, or an SLM). A reading 12.7 dB below the
  requested level with this rig's taps confirms the double correction; correcting
  either tag alone should recover it.
