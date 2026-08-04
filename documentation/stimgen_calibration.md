# stimgen.calibration

## What Is Calibration And Why Do You Need It

Calibration measures the relationship between the voltage your hardware outputs and the actual sound pressure level (SPL) it produces at the speaker or earphone. Without calibration, there is no reliable way to know what level a stimulus will be in dB SPL.

The result of a calibration session is a `.esgc` file. When your experiment loads that file, the software automatically scales stimulus voltages so that tones, clicks, or other signals are delivered at the levels you request.

## What You Need Before Starting

### Hardware

- A **measurement microphone** positioned at the location where sound levels matter (e.g. at the animal's ear, or inside a sound delivery tube).
- A **calibration source** (pistonphone or sound level calibrator) that produces a known SPL at a known frequency — most commonly 94 dB SPL at 1000 Hz. This is used to measure how sensitive your microphone is.
- The **speaker or earphone** you will use in experiments, connected to your data acquisition hardware and driven through the same amplifier chain you use experimentally.

### Software

- If using TDT or similar hardware: a host application **protocol file** (`.eprot`) that includes the calibration-capable hardware interface. See [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) for exact interface requirements.
- If using a Windows sound card: no protocol file is needed — use `WindowsSoundCardAdapter` directly.

---

## Workflow 1: GUI (Recommended For New Users)

The calibration GUI is the easiest starting point. It walks you through each step interactively.

### Step 1 — Open the GUI

In the MATLAB command window:

```matlab
stimgen.calibration.CalibrationGui()
```

The GUI opens. All calibration buttons will be disabled until hardware is connected.

### Step 2 — Connect Hardware

In the GUI menu: **File > Initialize Runtime From Protocol...**

Select your `.eprot` protocol file. The GUI will connect to the hardware interface defined in that file and attempt to attach a calibration adapter automatically.

When successful, the status bar at the bottom of the GUI will say something like *"Adapter attached. Ready for live calibration."* and the calibration buttons will become active.

If the buttons stay disabled, the protocol does not meet the hardware requirements — see [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) for troubleshooting.

> **No protocol file?** If you are using a Windows sound card, see [Workflow 2](#workflow-2-programmatic) below. The GUI currently does not support `WindowsSoundCardAdapter` through the menu; use the programmatic path instead.

### Step 3 — Set Parameters

Before measuring, fill in the fields on the left side of the GUI:

| Field | What it means | Typical value |
|---|---|---|
| Reference Level | SPL your calibrator produces | 94 dB |
| Reference Frequency | Frequency your calibrator uses | 1000 Hz |
| Mic Sensitivity | Will be measured automatically in the next step | leave as-is |
| Normative Level | Target SPL your system should be calibrated to reach | 80 dB |
| Excitation Voltage | Voltage amplitude used during calibration sweeps | 1 V |

### Step 4 — Measure Reference

Place the calibrator on the microphone and turn it on.

Click **Measure Reference**. The software plays a tone at the reference frequency, records the microphone output, and computes the microphone sensitivity (V/Pa). The *Mic Sensitivity* field will update automatically.

Remove the calibrator after this step and position the microphone at your experimental measurement point.

### Step 5 — Calibrate Tones

Click **Calibrate Tones**. A dialog will ask for:

- **Frequency vector** — the frequencies to sweep (e.g. `logspace(2, 4, 50)` for 50 points from 100 Hz to 10 kHz). Leave blank for the default 50-point log sweep to Nyquist.
- **Repeat count** — how many measurements to average per frequency (default 1; use 3–5 for noisy environments).

The sweep runs automatically. Progress is shown in the MATLAB command window. A transfer curve appears on the right plot when complete.

### Step 6 — Optional Additional Calibrations

These are not required for basic tone delivery but improve accuracy for specialized stimuli:

- **Calibrate Clicks** — sweep across click durations. Dialog collects a duration vector and repeat count.
- **Calibrate Swept Sine** — broadband transfer function measurement. Dialog collects chirp duration and repeat count.
- **Design Filter** — designs an equalization FIR filter from the tone LUT, or from the swept sine LUT if no tone calibration exists. Requires one of those two calibrations to have already completed. A dialog collects the design options (filter length, design method, interpolation, smoothing, correction limit, band — see [Reference: Filter Design Options](#reference-filter-design-options)), and the result opens in `fvtool`.

### Step 7 — Save

**File > Save .esgc** — save the calibration to disk. Use a descriptive filename that identifies the rig and date, e.g. `Rig3_earphone_2026-05-08.esgc`.

---

## Workflow 2: Programmatic

Use this path when you want to script calibration, run it headlessly, or use a Windows sound card.

### Step 1 — Create An Adapter

Choose the adapter that matches your hardware:

**Windows sound card** (simplest — no host-provided hardware interface needed):

```matlab
adapter = stimgen.calibration.WindowsSoundCardAdapter( ...
    SampleRate=48000, ...   % must match your device's native rate
    Device="", ...          % empty string uses the system default device
    InputChannel=1);        % microphone input channel index
```

**Lab hardware via a host application.** stimgen ships no hardware-specific adapter; the host provides one implementing `HwAdapter`. A typical pattern:

```matlab
protocol = host.loadProtocol('MyProtocol.eprot');
host.connect();
adapter = host.calibrationAdapter();
```

To support a different device, subclass `stimgen.calibration.HwAdapter` and implement `sample_rate()` and `play_and_record(signal)`.

### Step 2 — Create An Engine

```matlab
eng = stimgen.calibration.Engine(adapter);
```

### Step 3 — Configure The Engine

Set parameters before running any measurements. All parameters have defaults; only change what differs from the defaults:

```matlab
eng.set_configuration( ...
    ReferenceLevel=94, ...      % dB SPL your calibrator produces (default 94)
    ReferenceFrequency=1000, ...% Hz (default 1000)
    NormativeValue=80, ...      % target SPL for the experiment (default 80)
    ExcitationVoltage=1, ...    % volts; reduce if clipping warnings appear (default 1)
    ShowLivePlots=true);        % show plots during sweeps (default false)
```

### Step 4 — Measure The Microphone Reference

Place the calibrator on the microphone and turn it on, then:

```matlab
eng.calibrate_reference();
```

This plays a tone at `ReferenceFrequency` and uses the recorded level plus `ReferenceLevel` to compute `MicSensitivity`. Remove the calibrator after this step.

### Step 5 — Calibrate Tones

```matlab
% Default: 50-point log sweep from 100 Hz to Nyquist, 1 pass:
eng.calibrate_tones();

% Custom frequency vector, 3 passes (measurements averaged per point):
freqs = logspace(log10(500), log10(20000), 40);
eng.calibrate_tones(freqs, 3);

% Longer bursts and gaps, and a shorter train for a small output buffer:
eng.calibrate_tones(freqs, 3, BurstDuration=0.2, GapDuration=0.1, ...
    MaxSequenceDuration=1);
```

The whole sweep is pregenerated as a train of gated tone bursts separated by
silence and played with **one `play_and_record` per pass**, rather than one
hardware transaction per frequency. Each burst is then cut back out of the
recording at its known position — offset by the bulk acquisition delay, which
is measured once per train by cross-correlating excitation against response —
and measured spectrally over its steady-state middle. That per-burst estimate
is the same flat-top periodogram the per-frequency version used, so the LUT
stays on its original scale and remains directly comparable to the swept-sine
LUT.

Bursts are separated in *time*, not in frequency, so the analysis holds for any
frequency list: adjacent points may sit closer together than their spectral
lobes are wide.

| Option | Default | Meaning |
|---|---|---|
| `BurstDuration` | 0.1 s | Length of each tone burst. The gate is four carrier periods, so the steady-state middle shrinks toward the bottom of the sweep |
| `GapDuration` | 0.05 s | Silence before, between, and after bursts. Also bounds the delay search — raise it if the device's round-trip latency exceeds it |
| `MaxSequenceDuration` | 2 s | Longest single train. Sweeps longer than this are split into consecutive trains, which keeps the excitation inside a fixed hardware output buffer such as an RPvds serial buffer |

Each burst's steady-state span excludes only its own gating ramp; if that
would leave too little of the burst to estimate a level from, the whole
burst is measured instead. The spectral estimate at the burst's own
frequency is inherently robust to onset transients, so no separate guard
window is needed.

Two error paths are specific to this arrangement:

- `stimgen:calibration:Engine:sequenceTooLong` — `MaxSequenceDuration` cannot
  hold even one burst with its gaps.
- A warning that the response delay reached the search bound, meaning burst
  segmentation may be misaligned. Increase `GapDuration`.

### Step 6 — Optional Additional Calibrations

```matlab
% Click calibration (sweep over durations in seconds):
durs = [0.05 0.1 0.2 0.5 1.0] ./ 1000;  % 50 µs to 1 ms
eng.calibrate_clicks(durs, 3);

% Swept-sine (broadband transfer function, 1-second chirp, 4 averages):
eng.calibrate_swept_sine(1, [], 4);

% Equalization filter design (requires tone or swept sine calibration):
eng.design_filter();              % "auto": tone LUT, else swept sine
eng.design_filter("swept_sine");  % force the swept sine LUT

% Longer filter, 1/6-octave smoothing, correction capped at 20 dB, band limited:
eng.design_filter("swept_sine", NumCoefficients=257, SmoothingOctaves=1/6, ...
    MaxCorrectionDb=20, FrequencyRange=[500 32000]);
```

See [Reference: Filter Design Options](#reference-filter-design-options) for the full option list.

### Step 7 — Save

```matlab
eng.save('Rig3_earphone_2026-05-08.esgc');
```

---

## Using Calibration Data In Experiments

Load the `.esgc` file and ask the engine what voltage to use for a given stimulus:

```matlab
eng = stimgen.calibration.Engine.load('Rig3_earphone_2026-05-08.esgc');

% Voltage needed to produce a 4 kHz tone at 70 dB SPL:
V = eng.compute_adjusted_voltage("tone", 4000, 70);

% Voltage for a 0.1 ms click at 80 dB SPL:
V = eng.compute_adjusted_voltage("click", 0.0001, 80);
```

In practice, `stimgen.StimType.apply_calibration` calls this for you when a `.esgc` file is assigned to a stimulus generator — you do not need to call it manually during an experiment.

---

## Reference: Engine Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `MicSensitivity` | 1 V/Pa | Updated by `calibrate_reference`; can also be set manually if known |
| `ReferenceLevel` | 94 dB | SPL produced by your calibrator |
| `ReferenceFrequency` | 1000 Hz | Frequency used by your calibrator |
| `NormativeValue` | 80 dB | Target SPL for the voltage lookup table |
| `ExcitationVoltage` | 1 V | Amplitude of signals played during calibration sweeps |
| `ShowLivePlots` | false | Show waveform and spectrum plots during sweeps |

These are all `SetAccess = protected` — they are readable from anywhere but can only
be written through `eng.set_configuration(Name=value)`, which is what runs their
validators. Direct assignment (`eng.MicSensitivity = 0.05`) raises
`MATLAB:class:SetProhibited`. The same applies to `eng.Adapter`, which is attached or
detached with `eng.set_adapter(adapter)` / `eng.set_adapter([])`, and to
`CalibrationData`/`CalibrationTimestamp`, which are restored with `eng.restore(s)` and
otherwise written only by the calibration runs themselves.

---

## Reference: CalibrationData Structure

`eng.CalibrationData` is empty (`[]`) until a successful run completes. After a run it is a struct with these fields:

| Field | Populated by | Contents |
|---|---|---|
| `tone` | `calibrate_tones` | frequency, measurement, spl_db, voltage (Nx1); burst_duration, gap_duration; metrics sub-struct |
| `click` | `calibrate_clicks` | duration, measurement, spl_db, voltage (Nx1); metrics sub-struct |
| `swept_sine` | `calibrate_swept_sine` | frequency, measurement, spl_db, voltage (Nx1); metrics sub-struct |
| `filter` | `design_filter` | `digitalFilter` object, or `[]` |
| `filterGrpDelay` | `design_filter` | filter group delay in samples (0 until filter is designed) |
| `filterSource` | `design_filter` | `"tone"` or `"swept_sine"` — which LUT the filter was designed from |
| `filterDesign` | `design_filter` | struct recording the options the filter was designed with, plus `correctionDb` (the achieved correction span), `sampleRate` and `designedOn` |

The `metrics` sub-struct in `tone` and `swept_sine` contains per-frequency diagnostics: `noise_floor_db`, `snr_db`, `thd_db`, `h2_db`, `h3_db`, `repeatability`, and `clipping_headroom`. For `swept_sine`, the distortion fields (`thd_db`, `h2_db`, `h3_db`) are `NaN`: distortion on a chirp requires time-gating the harmonic impulses that precede the linear impulse response, which is not implemented. Swept-sine levels are derived from the deconvolved transfer function, not from the response spectrum — see `stimgen_SweptSineCalibration.md`.

---

## Reference: Filter Design Options

`design_filter` builds the equalizer in these steps:

1. Pick the LUT (`source`), keep the in-band points, and convert the voltage column to dB.
2. Resample it onto a dense design grid — `GridPoints` points spread over `FrequencyRange` on a `FrequencyScale` axis, joined by `Interpolation`.
3. Optionally smooth the target with a `SmoothingOctaves`-wide fractional-octave window.
4. Reference the peak to 0 dB and clamp the result at `MaxCorrectionDb` below it.
5. Fit an `NumCoefficients`-tap linear-phase FIR to that target with `DesignMethod`, hold it flat from DC to the low edge and from the high edge to Nyquist, and store the filter with its group delay.

Only the *shape* of the response matters: `stimgen.StimType.apply_calibration` renormalizes the filtered waveform before scaling it to the LUT voltage for the requested level.

| Option | Default | Meaning |
|---|---|---|
| `source` | `"auto"` | `"auto"` prefers the tone LUT and falls back to swept sine; `"tone"` or `"swept_sine"` forces one |
| `NumCoefficients` | `0` (auto) | Filter length in taps. Auto derives it from the number of LUT points. Always forced odd — an odd-order (even tap count) linear-phase FIR is silently pinned to zero gain at Nyquist |
| `DesignMethod` | `"freqsamp"` | `"freqsamp"` (frequency sampling) or `"ls"` (least squares). `"ls"` tracks the target more tightly at a given length but rings more at sharp transitions |
| `Interpolation` | `"pchip"` | `"pchip"`, `"linear"`, `"spline"`, or `"makima"`. `"pchip"` will not overshoot between measured points; `"spline"` is smoother but can |
| `FrequencyScale` | `"log"` | Axis the grid and interpolation use. Log spends resolution where transducers actually vary |
| `AmplitudeScale` | `"db"` | Axis the interpolation and smoothing operate on. Linear amplitude lets the loud end of the LUT dominate the fitted shape |
| `GridPoints` | `0` (auto) | Design grid resolution; auto scales it with the filter length |
| `SmoothingOctaves` | `0` | Fractional-octave smoothing width, e.g. `1/3`. Keeps measurement noise and single-point notches out of the filter |
| `MaxCorrectionDb` | `Inf` | Maximum correction depth in dB below the peak of the target. Caps how much of a short filter a deep notch can claim |
| `FrequencyRange` | LUT span | `[lo hi]` Hz to equalize. The target is held flat at the edge value outside it |
| `ShowResponse` | `true` | Open the design in `fvtool`, replacing the window from the previous design |

Results are recorded in `CalibrationData.filterDesign`, so a saved `.esgc` says how its filter was made — including `correctionDb`, the correction span the design actually asked for.

### How The Filter Is Applied

`stimgen.StimType.apply_calibration` and `stimgen.SoundFile.apply_calibration` both equalize through `stimgen.util.filter_aligned(Hd, x, gd)`, which appends `gd` zeros to the signal, filters, and drops the first `gd` output samples. The result is the same length as the input and aligned with it sample for sample, so equalization does not move a stimulus in time or shorten it. Gating runs after calibration, so the ramp lands on the samples it was meant for.

Filter length is therefore a free choice acoustically, but not a free choice in latency: a linear-phase FIR cannot be aligned in real time, only after the fact. `filterGrpDelay` is `(NumCoefficients-1)/2` samples — 128 samples (1.3 ms at 97.6 kHz) for a 257-tap design — and that is how much of the filter's output has to exist before the aligned signal can start. This is not an issue for stimuli generated ahead of playback, which is how stimgen works, but it is the reason a filter is not free to make arbitrarily long.

Three notes on behaviour:

- The LUT is resampled onto a dense grid before fitting, rather than being handed to `designfilt` point by point as in earlier versions. Filters designed now differ slightly from filters designed before, most visibly where the measured points are sparse.
- `DesignMethod="ls"` solves a system that is rank deficient by exactly one for every Type I arbitrary-magnitude FIR — on a four-point specification as readily as on a thousand-point one. `designfilt` keeps that warning to itself (it reaches `lastwarn` but is never displayed), and the minimum-norm result it returns is the intended design, so nothing needs doing about it.
- Equalized stimuli generated before this change were delayed by `filterGrpDelay` samples relative to their gate, and lost the last `filterGrpDelay` samples of their content, because the alignment step removed the wrong window. Anything comparing old and new recordings of the same protocol should expect that shift — at the previous auto filter length it was ~24 samples (0.25 ms at 97.6 kHz).

---

## Reference: Package Components

Source: `+stimgen/+calibration/`

- `Engine.m` — calibration orchestration, result storage, save/load, and voltage lookup.
- `HwAdapter.m` — abstract base class defining the adapter contract (`sample_rate`, `play_and_record`).
- `WindowsSoundCardAdapter.m` — concrete adapter using Windows Audio Toolbox (`audioPlayerRecorder`).
- `CalibrationGui.m` — interactive GUI wrapper around all engine operations.

Host-supplied adapters for lab hardware (TDT and similar) live outside this package; a host
application implements its own `HwAdapter` subclass to wrap its device interfaces.

---

## Related Documentation

- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference, protocol compatibility requirements, and error troubleshooting
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine calibration details
- [stimgen_StimType.md](stimgen_StimType.md) — how calibration is applied during stimulus generation
