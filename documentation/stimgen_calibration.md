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

Place the acoustic calibrator (e.g. PCB CAL150, B&K 4231) on the microphone and turn it on. It must be set to the same frequency and level as the *Reference Frequency* and *Reference Level* fields.

Click **Measure Reference** and confirm the prompt. Nothing is played through the speaker: the reference tone comes from the calibrator, and the software only records the microphone for one second, reads the level at the reference frequency, and computes the microphone sensitivity (V/Pa). The *Mic Sensitivity* field will update automatically.

If the recording contains no tone at the reference frequency, the step fails with `stimgen:calibration:Engine:noReferenceTone` rather than storing a meaningless sensitivity — check that the calibrator is switched on and seated, and that the microphone reaches the acquisition input.

Remove the calibrator after this step and position the microphone at your experimental measurement point.

### Step 4b — Measure Background (optional, recommended)

With the calibrator removed, the microphone where it will sit during an experiment, and the rig running as it normally does, click **Measure Background**. Nothing is played: this records the noise floor that every later measurement sits on top of, and it is the only step whose answer changes when someone leaves a fan on.

The dialog asks for the record duration, how many records to take, and the prominence a spectral peak needs to be called tonal. The defaults (2 s, 3 records, 6 dB) are reasonable for a sound-attenuating booth.

What comes back, on the transfer panel and in a summary dialog:

- **broadband level, unweighted and A-weighted.** The gap between them is how much of the noise is where hearing is. A floor that is 62 dB SPL but 47 dB(A) is almost all low-frequency rumble.
- **fractional-octave band levels.** This is the comparable form — read a stimulus spectrum against it to see which parts of a stimulus are actually clear of the room.
- **tonal components,** with their frequencies refined below the FFT bin spacing, and a note when they line up with 50 or 60 Hz mains harmonics. Hum is the one background component that is nearly always the rig's own wiring rather than the room, and it is fixed by grounding, not by acoustic treatment.
- **acquisition health** — DC offset, crest factor, headroom to full scale, and whether the input is quantizer-limited. A "silent" room measured through a converter that has run out of bits is measuring the converter.
- **stability** across the records. If the level moved several dB between them, something intermittent is running and one number will not describe it.

The result is stored as `background` in the calibration and saved with it, so a `.esgc` records the floor its tables were measured over. It does not change `CalibrationTimestamp` — a background capture does not re-date the transfer measurements. In `CalibrationGui` it has a tab of its own, so it stays on screen alongside the transfer curves rather than replacing them.

### Step 5 — Calibrate Tones

Click **Calibrate Tones**. A dialog will ask for:

- **Frequency vector** — the frequencies to sweep (e.g. `logspace(2, 4, 50)` for 50 points from 100 Hz to 10 kHz). Leave blank for the default 50-point log sweep to Nyquist.
- **Repeat count** — how many measurements to average per frequency (default 1; use 3–5 for noisy environments).

The sweep runs automatically. Progress is shown in the MATLAB command window. A transfer curve appears on the right plot when complete.

With **Iterative Level Refinement** checked (beside Calibrate Tones), the dialog also asks for a pass limit and a target accuracy in dB, and the sweep is followed by an automatic refinement: the finished table is tested at its own points — each played at the drive voltage the table asks for, exactly as an experiment would — and corrected from the level errors that come back, repeating until every point lands within the target or the pass limit is reached. This removes what a one-shot sweep cannot see: gain that does not scale exactly as `20*log10(V)` between the excitation voltage the sweep played at and the drive the table actually commands (amplifier or speaker compression, typically). The table is always left in the state the last test pass verified, and Stop or an error restores the unrefined table. The same toggle applies to **Calibrate Clicks**.

### Step 6 — Test The Tone Table

Click **Test Tones**. This is the step that tells you whether the calibration works: the software asks the table what voltage each test frequency needs for a requested dB SPL, plays a tone at exactly that voltage, measures it, and reports the difference. It is the same lookup a `Tone` stimulus goes through in an experiment.

A dialog asks for test frequencies, requested levels, and an average count. Leave the first two blank — the defaults are the ones worth running:

- **Frequencies** default to the geometric midpoints between the calibrated points. Testing *at* the calibrated frequencies would only confirm that the interpolant passes through its own knots; halfway between two of them is where the interpolation is actually deciding the level.
- **Levels** default to the Normative Value and 10 and 20 dB below it, which also checks that level scales correctly with drive voltage away from the normative point.

The status line reports PASS/FAIL, the worst error and where it happened, and the mean bias, against a 3 dB tolerance. A uniform bias points at the reference measurement or the Normative Value; scattered errors point at a tone sweep too sparse for the response's structure — recalibrate with a finer frequency list. The result is stored in the calibration as `toneTest`, so the saved file records that its table was verified.

Points needing more than Max Output Voltage are skipped rather than played, and reported; points that come back below the SNR floor are measured but left out of the verdict.

### Step 7 — Optional Additional Calibrations

These are not required for basic tone delivery but improve accuracy for specialized stimuli:

- **Calibrate Clicks** — sweep across click durations. Dialog collects a duration vector (in ms) and repeat count. Leave the vector blank for the default octave series from 0.01 ms to 5.12 ms. Any requested duration shorter than one sample at the current sample rate is skipped, and the skipped values are listed in the log.
- **Test Clicks** — the click counterpart of Test Tones, and worth running for the same reason: clicks are played at the drive voltages the click table asks for and the peak levels that come back are compared to the levels requested. Defaults probe midway between the calibrated durations, at three levels. Short durations at low levels are the first to fall below the SNR floor, and are reported as excluded rather than failed. Stored as `clickTest`. Enabled once a click calibration exists and hardware is attached.
- **Calibrate Swept Sine** — broadband transfer function measurement. Dialog collects chirp duration and repeat count.
- **Design Filter** — designs an equalization FIR filter from the tone LUT, or from the swept sine LUT if no tone calibration exists. Requires one of those two calibrations to have already completed. A dialog collects the design options (filter length, design method, interpolation, smoothing, correction limit, band — see [Reference: Filter Design Options](#reference-filter-design-options)), and the result opens in `fvtool`.
- **Test Filter** — verifies the equalizer empirically, matched to what the filter was designed from. A filter designed from the tone table is tested with actual discrete tones (the same run as Test Tones): tones are played at the drive voltages the lookup table asks for and the levels that come back are compared to the levels requested, stored as `toneTest`. A swept sine design is tested with the sweep: played raw and again through the filter, reporting the ripple of the equalized response against the speaker's own, stored as `filterTest`. Enabled once a filter exists and hardware is attached.

**Test Tones** (Step 6 above) follows Tone Lookup From Swept Sine, so after switching a rig to the swept sine table, re-run it: the table serving tone lookups has changed, and it is the one that now has to be right.

### Step 8 — Save

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

To support a different device, subclass `stimgen.calibration.HwAdapter` and implement `sample_rate()` and `play_and_record(signal)`. `record(nSamples)` — used by the reference measurement, which must not drive the speaker — is concrete and defaults to a silent `play_and_record`, so it only needs overriding if the device can acquire without arming its output.

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
    MaxOutputVoltage=10, ...    % volts the rig can actually produce (default 10)
    AcCoupleResponse=true, ...  % high-pass the acquired record before analysis (default false)
    AcCoupleFrequency=20, ...   % Hz corner of that high-pass (default 20)
    AmbientTemperature=20, ...  % deg C of the test space; sets the speed of
                            ... % sound distances are derived at (default 20)
    SpectralWindow="auto", ...  % taper every spectral estimator applies (default "auto")
    SpectralFftLength=0, ...    % transform-length floor; 0 = automatic (default 0)
    ShowLivePlots=true);        % broadcast progress during sweeps (default false)
```

`AcCoupleResponse` high-passes every acquired record before anything is computed
from it, at every acquisition site: the reference, the background, the tone and
click sweeps, the swept sine, and both verification runs. Turn it on when the
input stage carries a DC offset or a wandering baseline — either adds to the
measured RMS, biases the cross-correlation that segments a burst train, and puts
low-frequency energy in the spectrum that leaks into the lowest analysis bins.
Drift is the case subtracting a mean cannot reach: wander over a record averages
to nearly nothing, so a mean subtraction leaves it in place. It is off by default
so an existing rig's numbers do not change underneath it, and it applies only to
what is measured next; nothing already in the tables is re-analyzed.

The filter is a second-order Butterworth run forwards and backwards, so it shifts
nothing in time — the per-burst analysis windows and the conduction-delay probe
still find the response where they expect it, which a causal high-pass would break.
Set `AcCoupleFrequency` well below the lowest frequency you calibrate: the response
is already about 3 dB down at the corner itself. The record's mean is removed before
it is filtered, so the filter never has to settle across a large DC step at the
record's edges, and a record too short to filter keeps that mean removal alone.

Two things it deliberately does not do. `measure_background` is handed the record
as acquired either way — its analysis already removes each record's mean and
reports it as `dc_offset_v`, which coupling first would zero out, and its band
levels are meant to describe the floor the room actually has — so there only the
record kept for display follows the setting. And whatever the setting, the
`LiveUpdate` metrics report `dc_v` (the offset still in `Response`),
`dc_removed_v` (what was taken off it) and `ac_coupled_hz` (the corner it was
filtered at), the last two NaN when the record was not coupled, which
`LiveMonitor` states in the waveform title so the option's effect is legible
rather than inferred.

#### Spectral Analysis Settings

`SpectralWindow` and `SpectralFftLength` decide how an acquired record is turned
into a spectrum, and so what every level read out of a transform becomes: the
tone measurement written into the LUT (`Engine.spectral_rms`), the SNR and noise
floor (`estimate_noise_snr_`), the THD and harmonic levels
(`estimate_harmonics_`), the background Welch analysis, and the spectrum panel
`LiveMonitor` draws. They are resolved through
[`stimgen.calibration.SpectralOptions`](../+stimgen/+calibration/SpectralOptions.m),
which `eng.spectral_options()` returns.

Both defaults mean "leave each estimator with the choice it makes for itself",
so an engine that has never been configured produces exactly the numbers it did
before these settings existed:

```matlab
eng.set_configuration(SpectralWindow="hann", SpectralFftLength=2^16);
s = eng.spectral_options();     % the two, as one value object
w = s.taper(numel(y), "flattop");            % window vector for a record
n = s.transform_length(2^nextpow2(numel(y))); % transform length to use
```

The window is what trades amplitude accuracy against frequency resolution. Flat
top — the automatic choice wherever a *level* is measured — puts a tone within
about 0.01 dB of its true amplitude wherever it falls between bins, at the cost
of a main lobe too wide to separate close components. Hann (the automatic choice
for the Welch averages that measure a *floor*), Hamming, Blackman and
Blackman-Harris suppress progressively more leakage at progressively worse
amplitude accuracy. Rectangular is no taper at all: the sharpest resolution and
the worst leakage, right only for a signal exactly periodic in the record.
Reading a 4 kHz tone with Hann instead of flat top moves it by roughly 0.2 dB,
which is the scale of what changing this costs.

`SpectralFftLength` is a **floor** on the transform length, not a replacement for
it. It can only zero-pad further and never truncates, because a transform
shorter than the record would make MATLAB wrap the record modulo the transform
length and fold one part of the signal onto another. Padding buys finer bin
spacing — a more precisely placed peak and a smoother curve — not resolution the
record did not already contain.

Both apply to what is measured next; nothing already in a lookup table is
recomputed, so tables measured under different windows should not be mixed. Both
are saved in the `.esgc` file, so a calibration records how its tables were
analysed, and both ride in the `LiveUpdate` context, so a renderer transforms a
record the same way the engine measured it rather than computing a second,
differing number. A file written before these settings existed loads with the
automatic behavior, which is what it was measured under.

`ShowLivePlots` does not itself draw anything. It gates a `LiveUpdate` event that
the engine broadcasts for every measurement; attach a
[`stimgen.calibration.LiveMonitor`](#watching-a-run) to render it, or listen to it
yourself to log or forward progress.

### Step 4 — Measure The Microphone Reference

Place the acoustic calibrator on the microphone and turn it on, then:

```matlab
eng.calibrate_reference();
```

This records only — nothing is played. The tone is produced by the calibrator, so the recorded level at `ReferenceFrequency` is by definition `ReferenceLevel` dB SPL, which is what makes `MicSensitivity` (V/Pa) computable. A recording with no tone at `ReferenceFrequency` (SNR below 20 dB) raises `stimgen:calibration:Engine:noReferenceTone` instead of storing a sensitivity derived from noise. Remove the calibrator after this step.

The acquisition goes through `HwAdapter.record()`, whose default implementation is a silent `play_and_record`; a backend that can acquire without arming its output may override it.

### Step 4b — Measure The Background (optional, recommended)

With the calibrator off the microphone and the rig in the state an experiment would find it:

```matlab
r = eng.measure_background();          % 2 s x 3 records, third-octave bands
r = eng.measure_background(5, 5, FractionalOctave=12, TonalProminenceDb=8);

fprintf('%.1f dB SPL, %.1f dB(A)\n', r.spl_db, r.spl_dba);
fprintf('worst band %.0f Hz at %.1f dB SPL\n', ...
    r.worst_band.frequency, r.worst_band.level_db);
disp(r.flags);                         % findings worth acting on, if any
```

This also records only. It power-averages the records' spectra into fractional-octave band levels, computes the broadband level both unweighted and A-weighted, picks out tonal components against a running-median local floor, and checks the acquisition chain itself — DC offset, crest factor, headroom, and whether the input has run out of quantization steps. An all-zero record raises `stimgen:calibration:Engine:silentAcquisition` rather than reporting a floor of `-Inf` dB: a microphone always returns something, so zeros mean it is not reaching the input.

The result is stored in `CalibrationData.background` and saved with the calibration. It does not set `CalibrationTimestamp` — the transfer measurements have not been re-dated by it.

Run it against the levels you intend to use: `r.bands.snr_at_normative_db` is the margin each band has at `NormativeValue`, and `r.headroom_to_normative_db` is that margin broadband.

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
recording at its known position — offset by the rig's conduction delay — and
measured spectrally over its steady-state middle. That per-burst estimate
is the same flat-top periodogram the per-frequency version used, so the LUT
stays on its original scale and remains directly comparable to the swept-sine
LUT.

The conduction delay — acoustic propagation from the speaker to the
microphone plus the converters' round-trip latency, as one bulk offset — is
measured **per acquisition**, from a brief probe click embedded at the head
of every train the run plays. A click is the right probe because its
autocorrelation is a single sharp peak; estimating the delay from the tone
train itself (which is what earlier versions did) gives the correlation a
quasi-periodic ridge to wander along, and every analysis window then lands
early by the unaccounted delay — visibly including pre-response silence in
the waveform panel's measured span. The probe rides in the very record it
corrects because acquisition latency is only guaranteed *within* a record:
it can differ with record length and buffer size, so a delay measured on
one record cannot be assumed for another. Each measurement lands in the
engine's observable `ConductionDelay` property as it happens; the run's
median and spread are logged and recorded in the committed table as
`tone.conduction_delay_s` / `tone.conduction_delay_sd_s`. If a record's
click response cannot be trusted (nothing above the noise, or nothing
within the search bound aligns), that record is warned about and falls
back to whole-record cross-correlation. `measure_conduction_delay` remains
as a standalone probe for checking a rig by hand — from the command line, or
from the CalibrationGui's **Measure Conduction Delay** button, which reports
the delay and the air path it implies in a dialog. It shares the same
estimator, so the two cannot disagree about what a latency is. Nothing
consumes the standalone reading: a tone run always measures its own.

Every reading carries the conditions its distance was read under —
`temperature_c`, `speed_of_sound_ms` and `path_m` alongside `delay_s` — so a
[temperature](#reference-engine-parameters) changed afterwards cannot restate
an old measurement as a distance it never implied. The standalone probe also
returns a second output, the evidence behind the verdict:

```matlab
[info, diag] = eng.measure_conduction_delay();
plot(diag.lag_ms, diag.corr);   % the correlation the lag was chosen from
```

`diag` carries that correlation over every lag searched (normalized to its own
peak), the probe-region record on the same click-anchored lag axis
(`probe_v`, `probe_lag0_ms`), the bound it was searched to, and the peak and
noise the verdict compared. It is also broadcast as the `LiveUpdate` payload's
`Latency`, so `LiveMonitor` draws the same panel live or after the fact — see
[the GUI guide](stimgen_CalibrationGui.md#measuring-it-on-its-own). It is
returned rather than stored on `ConductionDelay`, because a tone sweep fills
that property once per acquisition and a curve per acquisition is not a rig
fact worth keeping.

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
- A warning that an acquisition's conduction delay probe could not be trusted
  (no click response above the noise, or nothing within the search bound
  aligns), after which that acquisition falls back to whole-record
  cross-correlation. If the true delay exceeds the bound, increase
  `GapDuration`.

### Step 6 — Test The Tone Table

```matlab
% Play tones at the voltages the LUT asks for and check what comes back.
% Both arguments may be [] -- see the note below on why the defaults matter.
r = eng.test_tones();                       % also stored in CalibrationData.toneTest
r = eng.test_tones([1400 5600], [50 60 70], RepeatCount=2, ToleranceDb=2);

fprintf('worst %.2f dB at %.0f Hz / %g dB SPL, bias %+.2f dB (passed: %d)\n', ...
    r.max_abs_error_db, r.worst.frequency, r.worst.level_db, r.bias_db, r.passed);
```

`test_tones` takes the drive voltage from `compute_adjusted_voltage("tone", f, level)` —
the same call `StimType.apply_calibration` makes — so it measures the level
normalization a real stimulus receives rather than a reimplementation of it. Which
table is exercised follows `ToneLutSource`; `results.lut_source` records which one it
was.

Both defaults are chosen to test what a sweep cannot check itself:

- **Frequencies** default to the geometric midpoints between successive LUT points.
  At the LUT's own frequencies `makima` reproduces the measurement by construction,
  so an error there is impossible and a pass there means nothing. Between them the
  interpolation is the only thing setting the level.
- **Levels** default to `NormativeValue - [20 10 0]`. The LUT is solved at
  `NormativeValue`; every other level comes from the `20*log10(V)` scaling in
  `compute_adjusted_voltage`, which a single-level test never exercises.

Other options: `RepeatCount`, `BurstDuration`, `GapDuration`, `MaxSequenceDuration`
(all as in `calibrate_tones`), `ToleranceDb` (default 3) and `MinSnrDb` (default 10).

Points needing more than `MaxOutputVoltage` are skipped rather than played — they
would clip, and clipping measures the amplifier, not the table — and are listed in
`results.skipped`. Points below `MinSnrDb` are measured but excluded from the verdict,
since noise reads *high* and would fail the test for something the LUT did not do.
Clipped points stay in the verdict: clipping reads low, and that error is real.

In `CalibrationGui` this runs from the **Test Tones** button.

### Step 6b — Refine The Tables (optional)

```matlab
% Iteratively test-and-correct the tone LUT at its own points until every
% point lands within tolerance (or MaxIterations tests have run):
r = eng.refine_tones(ToleranceDb=0.5, MaxIterations=4, RepeatCount=2);
fprintf('worst error %.2f -> %.2f dB in %d pass(es) (converged: %d)\n', ...
    r.initial_max_abs_error_db, r.final_max_abs_error_db, ...
    r.n_iterations, r.converged);

r = eng.refine_clicks();                % same loop for the click table
```

Where `test_tones` only reports the table's error, `refine_tones` removes it. Each
pass runs the test at the table's **own** points — the opposite of the test's
midpoint default, and deliberately so: at `NormativeValue` each knot plays at a
drive voltage different from the sweep's excitation voltage, so any departure from
the `20*log10(V)` level model between those two operating points (amplifier or
speaker compression is the usual cause) lands as a per-point error. A point
measured `e` dB high has its stored voltage scaled by `10^(-e/20)`; interpolation
between the corrected knots inherits the fix. Passes repeat until a test passes at
`ToleranceDb` (default 1 dB, tighter than the test's 3) or `MaxIterations`
(default 3) tests have run.

A correction is never applied after the final test, so the committed table is
always one a test just verified — `results.converged` says whether that test
passed. Cancellation or an error restores the table to its pre-refinement state.
Points that are unreachable at the refinement level or fall below `MinSnrDb` are
left uncorrected and counted in `results.n_unreliable`. Single-pass corrections
larger than `MaxCorrectionDb` (default 12 dB) are clamped and logged: an error
that size is usually a rig fault, not a table one. `refine_tones` follows
`ToneLutSource`, so it corrects the swept sine table when that table is serving
tone lookups. The refinement record is stored inside the refined table
(`CalibrationData.tone.refinement`, `.click.refinement` or
`.swept_sine.refinement`) and the final test remains in `toneTest`/`clickTest`.

In `CalibrationGui` this runs automatically after each sweep when **Iterative
Level Refinement** is checked; the sweep dialog collects the pass limit and
target accuracy.

### Step 7 — Optional Additional Calibrations

```matlab
% Click calibration (sweep over durations in seconds):
durs = [0.05 0.1 0.2 0.5 1.0] ./ 1000;  % 50 µs to 1 ms
eng.calibrate_clicks(durs, 3);

% ...and its own closed loop, the click counterpart of test_tones: plays a
% click at the voltage the LUT asks for and compares the peak level that
% comes back. Defaults probe midway between the calibrated durations, at
% NormativeValue and 10/20 dB below it.
r = eng.test_clicks();                  % also stored in CalibrationData.clickTest
r = eng.test_clicks([80 240] .* 1e-6, [60 70 80], RepeatCount=2);
fprintf('worst %.2f dB at %.1f us / %g dB SPL (passed: %d)\n', ...
    r.max_abs_error_db, r.worst.duration*1e6, r.worst.level_db, r.passed);

% Swept-sine (broadband transfer function, 1-second chirp, 4 averages):
eng.calibrate_swept_sine(1, [], 4);

% Serve tone lookups from the swept sine calibration instead of the direct
% tone table. Both LUTs are on the same SPL/voltage scale, so either can
% answer compute_adjusted_voltage("tone", ...). While set to "swept_sine"
% this OVERRIDES any direct tone calibration; nothing is deleted, and
% setting it back to "tone" restores the direct table instantly. If no
% swept sine data exists yet the direct tone table still applies. The
% choice is saved in the .esgc file. In the CalibrationGui this is the
% "Tone Lookup From Swept Sine" checkbox.
eng.set_configuration(ToneLutSource="swept_sine");
eng.set_configuration(ToneLutSource="tone");       % back to the direct table

% Equalization filter design (requires tone or swept sine calibration):
eng.design_filter();              % "auto": tone LUT, else swept sine
eng.design_filter("swept_sine");  % force the swept sine LUT

% Longer filter, 1/6-octave smoothing, correction capped at 20 dB, band limited:
eng.design_filter("swept_sine", NumCoefficients=257, SmoothingOctaves=1/6, ...
    MaxCorrectionDb=20, FrequencyRange=[500 32000]);

% Same measurement, filter for hardware running at a different rate. The LUT is
% rate independent; the taps are not. No adapter is needed for this.
eng.design_filter("swept_sine", SampleRate=100e3, FrequencyRange=[500 32000]);

% Verify the filter empirically: plays the sweep raw and through the filter,
% measures both, and reports how flat the equalized response came out.
r = eng.test_filter();            % result also stored in CalibrationData.filterTest
fprintf('ripple %.1f -> %.1f dB (passed: %d)\n', ...
    r.unfiltered.ripple_db, r.filtered.ripple_db, r.passed);

% Level reference for running the taps in hardware (e.g. an RPvds FIR), where
% nothing renormalizes after the filter:
r = eng.filter_level_reference(1);   % source: 1 V RMS white noise
fprintf('unity gain = %.1f dB SPL; scale taps by %.3g for %g dB SPL\n', ...
    r.unityGainSpl, r.scale, r.normativeValue);
```

See [Reference: Filter Design Options](#reference-filter-design-options) for the full option list.

`test_filter` deconvolves both responses against the *raw* chirp, so the second
measurement is the filter+speaker chain — the transfer function a calibrated stimulus
actually passes through. Options: `Duration`, `RepeatCount`, `TailDuration`, `NumPoints`,
and `RippleToleranceDb` (default 6), the peak-to-peak ripple of the equalized response at
or below which the test is reported passed. In `CalibrationGui` this runs from the
**Test Filter** button regardless of whether the filter was designed from the tone
table or the swept sine.

### Running the filter in hardware — `filter_level_reference`

The taps carry only the *shape* of the correction: `design_filter` references the
target magnitude to 0 dB at its peak, and `StimType.apply_calibration` renormalizes
the filtered waveform before scaling it to the LUT voltage for the requested level.
A hardware chain that convolves the taps itself — an RPvds FIR component fed from a
noise source, say — has no renormalization step, so the filter's spectrum-dependent
insertion loss (up to the full correction span) would land directly on the output
level. `filter_level_reference` computes the accounting once, for a known source:

```matlab
r = eng.filter_level_reference(1);      % source: 1 V RMS spectrally white noise
r = eng.filter_level_reference(0.5);    % same, 0.5 V RMS
r = eng.filter_level_reference(x);      % source: the actual waveform, in volts
```

The returned struct anchors the hardware to the same tone-LUT-at-`ReferenceFrequency`
convention `apply_calibration` uses for `"filter"`-type (RMS-normalized) stimuli, so
no new acoustic assumption is introduced:

| Field | Meaning |
|-------|---------|
| `scale` | multiply the filtered signal — or the taps themselves, before loading them — by this, and unity hardware gain produces `NormativeValue` dB SPL |
| `unityGainSpl` | dB SPL the *unscaled* filtered source produces at unity hardware gain |
| `filteredRms` | RMS of the filtered source, in volts |
| `lutVoltage` | LUT voltage at `ReferenceFrequency` for `NormativeValue` dB SPL — the anchor used |
| `normativeValue`, `referenceFrequency` | the engine parameters the numbers are stated against |

With the scale applied, a hardware gain of `10^((level − NormativeValue)/20)` plays
the source at `level` dB SPL. A scalar source is treated as spectrally white, for
which the filtered RMS has the closed form `rms · ‖taps‖₂`; pass the actual waveform
whenever the source is shaped or band-limited before the FIR. Recompute after every
`design_filter` — the taps' norm changes with each design — and spot-check the result
with a microphone once per rig, as with any calibration constant. In `CalibrationGui`
the 1 V RMS white-noise figures appear as the **Unity-Gain Noise Level** readout and
on the status line after each design. Raises
`stimgen:calibration:Engine:noFilter` when no filter has been designed, and the usual
LUT errors when no tone or swept sine calibration exists to anchor to.

### Step 8 — Save

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

## Watching A Run

The engine does not draw. With `ShowLivePlots=true` it broadcasts a `LiveUpdate`
event for every measurement, carrying a
[`stimgen.calibration.LiveUpdate`](../+stimgen/+calibration/LiveUpdate.m) payload: the
waveform just acquired, the span of it that was measured, the partial lookup table, and
the scalar metrics for that point.

`stimgen.calibration.LiveMonitor` renders that stream into the waveform and spectrum
panels and the transfer curve as it fills in:

```matlab
eng.set_configuration(ShowLivePlots=true);
mon = stimgen.calibration.LiveMonitor(eng);   % opens its own window
eng.calibrate_tones();
```

A host GUI supplies its own axes instead, which is how `stimgen.calibration.CalibrationGui`
shows a run beside the controls driving it:

```matlab
mon = stimgen.calibration.LiveMonitor(eng, Axes=[axSignal axSpectrum axTransfer]);
```

The transfer curve, the background analysis and the delay probe are one family
of views. With three axes they share the third one and each clears the last on
its way in — one panel, one measurement at a time. Pass **five** to give each
its own, and a redraw of one leaves the other two standing:

```matlab
mon = stimgen.calibration.LiveMonitor(eng, ...
    Axes=[axSignal axSpectrum axTransfer axBackground axLatency]);
```

That is what lets a host keep three measurements on screen at once;
`CalibrationGui` puts each on a tab. Either way each view clears only what it
must: with separate axes, only its own objects.

Outside a run, `mon.show_engine_state(eng)` redraws the response panels,
`mon.show_calibration(eng)` draws the committed lookup tables,
`mon.show_background(eng)` the stored noise analysis, and `mon.show_latency(d)`
a delay probe's diagnostics (`mon.show_latency()` draws its not-measured
placeholder). They may be called in any order — each clears only its own
panel, so none of them can undo another.

### Waveform resolution

Time-domain traces are decimated to a min/max envelope of at most `MaxPoints`
blocks, so a redraw costs the same on a record of ten thousand samples as on one
of a million. Every block's peak survives, so clipping and transients still read
correctly; the shape within a block does not.

```matlab
mon.DecimateWaveforms = false;   % every sample, for a zoomed-in look
mon.MaxPoints = 8000;            % or just more blocks
```

### Spectrum units

`mon.SpectrumUnits` selects what the spectrum panel's y-axis measures. Anything
in `LiveMonitor.SpectrumUnitList` is accepted; anything else is rejected at
assignment rather than at draw time:

```matlab
mon.SpectrumUnits = "V";   % "dB SPL" (default), "dB SPL/Hz", "Pa", "V",
                           % "dBV", "V/sqrt(Hz)", "dB re peak"
```

dB SPL is the calibration's own scale. The electrical units read the microphone
signal as the input stage sees it, which is what separates a quiet room from an
overloaded preamp — in dB SPL those look the same. The per-Hz densities are the
comparable form for a noise floor, since a per-bin level depends on the analysis
window and a density does not. `dB re peak` drops the calibration entirely and
shows shape alone, which is all a rig without a measured reference can be judged
on.

The measurement is held in volts and converted at draw time, so changing units
redraws the record already on screen, ghost included, without re-acquiring
anything. The dB units are drawn on a linear axis and the linear units on a log
one: a spectrum spans tens of dB in any unit, and a linear volts axis shows the
fundamental and nothing else.

### Weighting overlays

`mon.Weightings` overlays the standard frequency weightings on the transfer
panel — any combination of `"A"`, `"B"`, `"C"` and `"D"`, empty for none:

```matlab
mon.Weightings = ["A" "C"];   % live sweep, lookup tables and background view alike
```

A weighting is a relative curve — 0 dB at 1 kHz by definition — so each is
offset to pass through the measured level at 1 kHz, and the legend carries that
offset. The vertical distance between curve and measurement is then the thing
the overlay is for: how much of the response the ear discards. Where 1 kHz falls
outside the measured span, the nearest measured frequency anchors it instead.

Each curve is drawn only across the span of the data it is anchored to and is
clipped to that data's level range, so it can never rescale the axis — an
unclipped A-weighting reaches -50 dB by 20 Hz and would flatten every measured
curve on the panel. A click sweep is plotted against duration rather than
frequency and carries no overlay.

The curves come from `stimgen.util.weighting_db(f, type)`, evaluated from the
pole/zero forms in IEC 61672-1 (A, C) and IEC 60651 (B, D) and normalized to
0 dB at 1 kHz. It also accepts `"Z"` (flat), and it is the same function the
background analysis weights its band levels with, so the overlay and the
reported dB(A) cannot disagree.

Nothing obliges you to plot. The event is a plain data stream, so a host application can
listen to it to log progress, drive a progress bar, or forward it over a network:

```matlab
addlistener(eng, 'LiveUpdate', @(~, d) fprintf('%s %d/%d — %.0f%%\n', ...
    d.Stage, d.Index, d.Total, 100 * d.Progress));
```

A listener that throws is logged and skipped rather than allowed to abort the sweep: a
plotting bug must not discard a measurement that took minutes to acquire.

`Engine.plot_signal`, `plot_spectrum`, `plot_transfer` and `plot_reset` still exist and
forward to an attached monitor, creating one if none is attached. They are deprecated;
prefer a `LiveMonitor`.

---

## Reference: Engine Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `MicSensitivity` | 1 V/Pa | Updated by `calibrate_reference`; can also be set manually if known |
| `ReferenceLevel` | 94 dB | SPL produced by your calibrator |
| `ReferenceFrequency` | 1000 Hz | Frequency used by your calibrator |
| `NormativeValue` | 80 dB | Target SPL for the voltage lookup table |
| `ExcitationVoltage` | 1 V | Amplitude of signals played during calibration sweeps |
| `MaxOutputVoltage` | 10 V | Output ceiling of the rig. Sets the full scale the clipping test is judged against, and the line above which a required drive voltage is unreachable |
| `AcCoupleResponse` | false | Zero-phase high-pass each acquired record before analyzing it, so an input DC offset or slow baseline drift does not inflate levels, bias burst alignment, or leak into the lowest spectrum bins. Applies to every acquisition path. Saved in the `.esgc` file |
| `AcCoupleFrequency` | 20 Hz | Corner of that high-pass. Put it well below the lowest frequency being calibrated — the response is about 3 dB down at the corner itself. Saved in the `.esgc` file |
| `AmbientTemperature` | 20 °C | Air temperature of the test space. Sets the dependent `SpeedOfSound` (`331.3*sqrt(1+T/273.15)`, 343.2 m/s at the default), which is the speed every distance derived from a time of flight uses: the air path of a conduction delay, and each reflection's `path_difference_m` in a swept-sine analysis. No level, delay or arrival time depends on it. About 0.6 m/s per degree, so 5 °C is 1% of a distance. Saved in the `.esgc` file. Celsius here and everywhere the package computes; `CalibrationGui` is the one place it is entered and shown in Fahrenheit |
| `SpectralWindow` | `"auto"` | Analysis window every spectral estimator applies. `"auto"` leaves each with its own — flat top where a level is read, Hann where a floor is averaged — and is the behavior these settings were added underneath. `"flattop"`, `"hann"`, `"hamming"`, `"blackman"`, `"blackmanharris"` or `"rectangular"` applies one everywhere. Saved in the `.esgc` file. See [Spectral Analysis Settings](#spectral-analysis-settings) |
| `SpectralFftLength` | 0 | Transform length those estimators run over. 0 leaves each with the next power of two at or above its record; a nonzero value raises that and never lowers it, so it can only zero-pad. Saved in the `.esgc` file |
| `ShowLivePlots` | false | Broadcast a `LiveUpdate` event per measurement during sweeps |
| `ToneLutSource` | `"tone"` | Which LUT serves `"tone"` lookups (and the `"filter"`/`"noise"` lookups anchored to them): the direct tone table, or `"swept_sine"` to override it with the swept sine calibration whenever swept sine data exists. Saved in the `.esgc` file |

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
| `toneTest` | `test_tones` | struct recording the tone-LUT verification run: the `frequency`-by-`level_db` grid, `lut_source`, `drive_voltage`, `measured_spl_db`, `error_db`, `sd_db`, `snr_db`, `thd_db`, the `tested`/`reliable`/`clipping`/`extrapolated` masks, summary statistics (`max_abs_error_db`, `rms_error_db`, `bias_db`, per-level and per-frequency breakdowns, `worst`), `skipped`, the criteria applied, `passed`, and `testedOn` |
| `clickTest` | `test_clicks` | struct recording the click-LUT verification run: the `duration`-by-`level_db` grid, `drive_voltage`, `measured_spl_db`, `error_db`, `sd_db`, `snr_db`, `thd_db`, the `tested`/`reliable`/`clipping`/`extrapolated` masks, summary statistics (`max_abs_error_db`, `rms_error_db`, `bias_db`, per-level and per-duration breakdowns, `worst`), `skipped`, the criteria applied, `passed`, and `testedOn` |
| `filterTest` | `test_filter` | struct recording the verification run: sampled `frequency`, `band`, `unfiltered`/`filtered` levels and flatness statistics (`ripple_db`, `flatness_std_db`), the improvement, `passed`, and `testedOn` |
| `background` | `measure_background` | struct recording a silent capture: `spl_db`/`spl_dba` and the per-record `repeat_spl_db` with its `sd_db`/`range_db`/`stable` verdict; `bands` (frequency, `level_db`, `level_dba`, `snr_at_normative_db`, `edges`, `fraction`) and a finer `spectrum` for redrawing; `peaks` (frequency, `level_db`, `prominence_db`) and `mains`; `worst_band`; acquisition health (`rms_v`, `peak_v`, `crest_factor_db`, `dc_offset_v`, `headroom_db`, `clipping`, `distinct_levels`); the scale it is on (`reference_level_db`, `mic_sensitivity`, `normative_value_db`, `headroom_to_normative_db`); `flags`, and `measuredOn` |

After `refine_tones`/`refine_clicks` has run, the refined table (`tone`, `click` or `swept_sine`) also carries a `refinement` sub-struct: `lut_source`, `level_db`, the per-pass `iterations` record (`max_abs_error_db`, `rms_error_db`, `bias_db`, `n_reliable`, `n_corrected`, `max_correction_db`), `initial_`/`final_max_abs_error_db`, `n_unreliable`, `converged`, the criteria applied, and `refinedOn`. The next sweep of that table replaces both together.

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
| `SampleRate` | `0` (adapter) | Rate in Hz the filter will be run at. Set it to design for hardware other than the attached adapter, or with no adapter at all — see [Changing The Design Sample Rate](#changing-the-design-sample-rate) |
| `ShowResponse` | `true` | Open the design in `fvtool`, replacing the window from the previous design |

Results are recorded in `CalibrationData.filterDesign`, so a saved `.esgc` says how its filter was made — including `correctionDb`, the correction span the design actually asked for.

### Changing The Design Sample Rate

An FIR's coefficients are defined in cycles per *sample*, not in Hz. Running a tap set at a different rate than it was fitted for rescales its entire response by the rate ratio: a filter designed at 200 kHz, run at 100 kHz, applies its 20 kHz correction at 10 kHz. Being below the lower Nyquist does not help — that only makes the band representable, not correctly equalized. Both `test_filter` and `apply_calibration` refuse a mismatch (`stimgen:util:filterRateMismatch`); see [Rate Checking](#rate-checking) for what the check does and does not cover.

The measurement itself is not rate bound. The `tone` and `swept_sine` LUTs hold frequency in Hz against voltage, which is a property of the transducer, so **the same calibration can be re-fitted for any rate without re-measuring anything**:

```matlab
eng = stimgen.calibration.Engine.load('Rig3_earphone.esgc');   % measured at 200 kHz
eng.design_filter("swept_sine", SampleRate=100e3);             % filter for the 100 kHz rig
eng.save('Rig3_earphone_100k.esgc');
```

Two consequences of the lower rate: the equalized band is clipped to the new Nyquist (LUT points at or above it are dropped and the target holds flat at the last kept value), and `filterGrpDelay` is the same number of *samples* but twice the duration in seconds. Alignment is unaffected — `filter_aligned` works in samples.

One thing re-fitting cannot recover: the LUT was measured through the output path at its original rate, so any rate-dependent behaviour of the DAC's reconstruction filtering is baked into it. `test_filter`, run on hardware at the new rate, is what settles whether that matters.

In `CalibrationGui` this is the last field of the Filter Design dialog; the Sample Rate line turns red and names the design rate whenever a loaded filter does not match the attached adapter.

#### Rate Checking

`stimgen.util.assert_filter_rate` runs before any equalization — from `StimType.apply_calibration` and `SoundFile.apply_calibration` — and raises `stimgen:util:filterRateMismatch` rather than filtering at the wrong rate. `test_filter` refuses the same case with `stimgen:calibration:Engine:filterRateMismatch`, which is separate because there the mismatch is between the filter and the *adapter*, not the stimulus.

The design rate is read from `CalibrationData.filterDesign.sampleRate`, falling back to the filter's own `SampleRate`. A filter carrying neither — designed with normalized frequencies, before either was recorded — cannot be checked; it is allowed through with a log warning, since refusing it would reject the calibration rather than the mistake. Redesign such a filter to make it checkable.

A failed check also clears `Signal`. Assigning `Fs` recomputes the waveform under a `PostSet` listener, and MATLAB downgrades an error raised inside a listener to a warning — so the throw alone would leave a stale, unequalized waveform behind, and `StimPlayer` regenerates only when `Signal` is empty. Clearing it means the error is re-raised at play time, where it reaches the user.

### How The Filter Is Applied

`stimgen.StimType.apply_calibration` and `stimgen.SoundFile.apply_calibration` both check the filter's design rate against the stimulus `Fs` (see [Rate Checking](#rate-checking)) and then equalize through `stimgen.util.filter_aligned(Hd, x, gd)`, which appends `gd` zeros to the signal, filters, and drops the first `gd` output samples. The result is the same length as the input and aligned with it sample for sample, so equalization does not move a stimulus in time or shorten it. Gating runs after calibration, so the ramp lands on the samples it was meant for.

Filter length is therefore a free choice acoustically, but not a free choice in latency: a linear-phase FIR cannot be aligned in real time, only after the fact. `filterGrpDelay` is `(NumCoefficients-1)/2` samples — 128 samples (1.3 ms at 97.6 kHz) for a 257-tap design — and that is how much of the filter's output has to exist before the aligned signal can start. This is not an issue for stimuli generated ahead of playback, which is how stimgen works, but it is the reason a filter is not free to make arbitrarily long.

Three notes on behaviour:

- The LUT is resampled onto a dense grid before fitting, rather than being handed to `designfilt` point by point as in earlier versions. Filters designed now differ slightly from filters designed before, most visibly where the measured points are sparse.
- `DesignMethod="ls"` solves a system that is rank deficient by exactly one for every Type I arbitrary-magnitude FIR — on a four-point specification as readily as on a thousand-point one. `designfilt` keeps that warning to itself (it reaches `lastwarn` but is never displayed), and the minimum-norm result it returns is the intended design, so nothing needs doing about it.
- Equalized stimuli generated before this change were delayed by `filterGrpDelay` samples relative to their gate, and lost the last `filterGrpDelay` samples of their content, because the alignment step removed the wrong window. Anything comparing old and new recordings of the same protocol should expect that shift — at the previous auto filter length it was ~24 samples (0.25 ms at 97.6 kHz).

---

## Reference: Package Components

Source: `+stimgen/+calibration/`

- `Engine.m` — calibration orchestration, result storage, save/load, and voltage lookup.
- `HwAdapter.m` — abstract base class defining the adapter contract (`sample_rate`, `play_and_record`, plus the concrete `record`).
- `WindowsSoundCardAdapter.m` — concrete adapter using Windows Audio Toolbox (`audioPlayerRecorder`).
- `LiveUpdate.m` — immutable payload broadcast per measurement by the `LiveUpdate` event.
- `SpectralOptions.m` — value object resolving the analysis window and transform length every spectral estimator here uses; see [Spectral Analysis Settings](#spectral-analysis-settings).
- `@LiveMonitor/` — renderer for that stream; owns its own window or attaches to a host's axes. Also draws the two off-run views of the transfer axes: `show_calibration` (the lookup tables) and `show_background` (a background capture).
- `CalibrationGui.m` — interactive GUI wrapper around all engine operations.

From `+stimgen/+util/`:

- `weighting_db.m` — A/B/C/D/Z frequency weighting in dB, used by both the transfer-panel [overlays](#weighting-overlays) and the background analysis's band and broadband dB(A).

Host-supplied adapters for lab hardware (TDT and similar) live outside this package; a host
application implements its own `HwAdapter` subclass to wrap its device interfaces.

---

## Related Documentation

- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference, protocol compatibility requirements, and error troubleshooting
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine calibration details
- [stimgen_StimType.md](stimgen_StimType.md) — how calibration is applied during stimulus generation
