# stimgen.calibration.CalibrationGui

![CalibrationGui in offline mode: the controls column on the left split into Microphone Reference, Calibration, Verification & Equalization and Display sections with every measurement button disabled, empty Response/Spectrum/Transfer Curve plots on the right, and a "No adapter attached" status message in the pinned footer](images/CalibrationGui.png)

Source file: +stimgen/+calibration/CalibrationGui.m  
Related reference: [stimgen_calibration.md](stimgen_calibration.md)

The screenshot above shows the GUI immediately after construction in [offline mode](#constructor), before `File > Initialize Runtime From Protocol...` has attached an adapter — the calibrate buttons are disabled per [Button Enable Rules](#button-enable-rules) and the status label explains the next step.

CalibrationGui is the standalone calibration UI for the stimgen calibration stack. It owns a `stimgen.calibration.Engine` and provides interactive controls for reference, tone, click, swept-sine, and filter design workflows.

It has no knowledge of any particular hardware or experiment framework. Protocol loading, hardware connection, and adapter construction are delegated to a `stimgen.HardwareHost` supplied by the host application; without one, the GUI runs offline and can still inspect and load saved calibrations.

## What This File Does

CalibrationGui.m implements:

1. Constructor wiring (offline default, pre-built Engine, or host-driven).
2. GUI creation (controls, plot axes, menu actions).
3. Delegation of runtime lifecycle to the host.
4. Calibration execution and state/status updates.
5. Load/save for .esgc calibration files.

## Plots

The three axes (waveform, spectrum, transfer curve) are drawn exclusively by a
[`stimgen.calibration.LiveMonitor`](stimgen_calibration.md#watching-a-run)
attached to them at construction. During a run with **Show Engine Live Plots**
checked, the monitor renders the engine's `LiveUpdate` stream measurement by
measurement — analysed-span shading and clipping limits on the waveform, the
spectrum with harmonic markers and a previous-measurement ghost, and the
transfer curve filling in with a ±1 SD repeat ribbon, required drive voltage
against the `MaxOutputVoltage` ceiling, and a progress/ETA title. Between runs
the same monitor draws the committed lookup tables and the last response, so
the live and static views are one rendering, not two.

**Max Output Voltage** feeds both the clipping test and the unreachable-voltage
line. Loading a .esgc re-attaches the monitor to the loaded engine, and closing
the window detaches and deletes the monitor so the engine does not keep
notifying a renderer whose axes are gone.

The transfer panel serves two views, one at a time — the lookup tables, and the
background noise analysis. The **View** menu and the toolbar switch between
`LiveMonitor.show_calibration` and `LiveMonitor.show_background` without
re-measuring anything. **Background Noise Analysis** is disabled until a
background capture exists, in the engine or in a loaded `.esgc`; a Reset that
takes the data away drops the panel back to the lookup tables rather than
leaving it on a view that can no longer be drawn.

### Choosing what the plots show

The toolbar's second group is the quick way to change what is on screen, since
a display choice is made while reading a plot rather than while setting a sweep
up. The first two buttons are the exclusive transfer-panel view; the rest toggle
one overlay each:

| Toolbar button | Also at | Sets |
|---|---|---|
| Calibration transfer curves | View ▸ Calibration Transfer Curves | the transfer panel's view |
| Background noise analysis | View ▸ Background Noise Analysis | the transfer panel's view |
| Previous-measurement ghost | View ▸ Previous-Measurement Ghost | `LiveMonitor.ShowGhost` |
| Drive-voltage axis | View ▸ Transfer Drive-Voltage Axis | `LiveMonitor.ShowVoltage` |
| Log frequency axis | Display ▸ Transfer Plot Log X-Axis | `LiveMonitor.LogX` |

Every one of these is a *mirror*: the state lives on the monitor (and, for the
view, on the GUI's own `TransferView_`), and `sync_display_controls_` is the one
writer that pushes it to the toolbar, the menu and the checkbox together. A
change made through any of them therefore shows on the others, and the toolbar
reads as a display readout as well as a control. Setting a toggle tool's `State`
programmatically does not fire its `ClickedCallback`, which is what keeps the
sync from re-entering the handler that triggered it.

Switching the ghost off redraws only the response panels — a transfer redraw
resets the monitor's whole graphics cache, which is where the measurement behind
the one on screen is held. Switching the drive-voltage axis off also hides the
right-hand axis itself, the same way `show_background` does, rather than leaving
an empty scale and a label behind.

### Spectrum y-axis

**View ▸ Spectrum Y-Axis** picks the unit the spectrum panel is drawn in, and
sets the monitor's [`SpectrumUnits`](stimgen_calibration.md#spectrum-units)
property. The items are exclusive checkmarks — one unit at a time — and the
choice applies to the measurement already on screen, so nothing is re-acquired:

| Menu item | Unit | What it answers |
|---|---|---|
| Sound Pressure Level | `dB SPL` | the level the LUT records; the default, and the scale the rest of the GUI is in |
| Spectral Density | `dB SPL/Hz` | how this noise floor compares to another, independent of the analysis window |
| Sound Pressure | `Pa` | the same acoustic quantity in linear pressure |
| Measured Voltage | `V` | what the microphone signal actually is, in the units the input stage is specified in |
| Measured Voltage | `dBV` | the same, as a level — a quiet room and an overloaded preamp are far apart here and identical in dB SPL |
| Voltage Density | `V/sqrt(Hz)` | electrical noise floor in the form a converter or preamp datasheet quotes |
| Relative to Peak | `dB re peak` | shape alone — harmonics and sidebands on a rig whose reference has not been measured yet |

The dB units are drawn on a linear axis and the linear units on a log axis: a
spectrum spans tens of dB whatever it is measured in, and on a linear volts axis
the noise floor lies on the axis with only the fundamental visible.

### Weighting overlays

**View ▸ Weighting Overlay** draws the standard A, B, C and D weighting curves
over whichever view the transfer panel is showing, and sets the monitor's
[`Weightings`](stimgen_calibration.md#weighting-overlays) property. The items are
checkable and independent — any combination at once — and **None** clears them.

They annotate the current view rather than replacing it, so toggling one while
the background analysis is up redraws the background analysis, not the lookup
tables. During a run the curve re-anchors as the sweep fills in.

## Constructor

Both inputs are optional and are identified by **type**, not position, so an `Engine` and a `HardwareHost` may be given in either order, either one alone, or as `Engine=`/`Host=` pairs:

```matlab
% Offline mode — no hardware; load/inspect a saved calibration:
gui = stimgen.calibration.CalibrationGui()

% Host-driven — enables File > Initialize Runtime From Protocol:
gui = stimgen.calibration.CalibrationGui(host)

% Pre-built Engine with adapter already attached:
eng = stimgen.calibration.Engine(adapter);
gui = stimgen.calibration.CalibrationGui(eng)

% Both — any of these are equivalent:
gui = stimgen.calibration.CalibrationGui(eng, host)
gui = stimgen.calibration.CalibrationGui(host, eng)
gui = stimgen.calibration.CalibrationGui(Engine=eng, Host=host)
```

Omitting the engine creates a fresh offline one, so a host application never has to pass `stimgen.calibration.Engine()` just to reach the second argument. An empty `[]` is accepted in place of either input, which is what lets a caller forward an optional host unconditionally. Anything else raises `stimgen:calibration:CalibrationGui:invalidArgument`.

If no adapter is attached at construction time, live calibration buttons are disabled until adapter attachment succeeds. The runtime menu actions require a host and raise `stimgen:calibration:CalibrationGui:noHost` without one.

## Creating An Engine

An `Engine` requires an `HwAdapter` for live measurement. stimgen ships `stimgen.calibration.WindowsSoundCardAdapter`; host applications supply their own `HwAdapter` implementation for lab hardware:

```matlab
% Built-in sound card adapter:
adapter = stimgen.calibration.WindowsSoundCardAdapter();
eng = stimgen.calibration.Engine(adapter);

% Or a host-supplied adapter:
adapter = host.calibrationAdapter();
eng = stimgen.calibration.Engine(adapter);
```

For offline use only (voltage lookup from a saved .esgc file):

```matlab
eng = stimgen.calibration.Engine.load('my_cal.esgc');
```

For a Windows sound card workflow:

```matlab
adapter = stimgen.calibration.WindowsSoundCardAdapter(...);
eng = stimgen.calibration.Engine(adapter);
```

Once an engine exists, pass it to `CalibrationGui` or let the GUI create its own via the no-argument constructor and attach hardware from the menu.

## Exact Protocol Requirements For CalibrationGui Compatibility

This section defines the exact requirements for a protocol to be usable with File > Initialize Runtime From Protocol... in CalibrationGui. These requirements are expressed against the abstract `stimgen.HardwareHost` contract; a host application is responsible for satisfying them with its own protocol and interface model.

### Required protocol-level conditions

1. The protocol must load successfully through `host.loadProtocol(path)`.
2. The host must expose at least one hardware interface after loading.
3. At least one interface must be connectable via `host.connect()`.
4. At least one connected interface must be able to produce a working `HwAdapter` through `host.calibrationAdapter()`.

### Required interface capabilities

A compatible interface must expose parameters equivalent to:

1. BufferSize (write)
2. BufferOut (write)
3. x_Trigger (write)
4. BufferIndex (read)
5. BufferIn (read)

If any required parameter is missing, `host.calibrationAdapter()` fails to build a working adapter for that interface.

### Required sample-rate availability

A compatible interface must provide a usable sample rate, surfaced through `HwAdapter.sample_rate()`. If no interface can report a nonzero sample rate, adapter attachment fails with a no-sample-rate error.

### Runtime integration behavior

When initialization is requested, CalibrationGui delegates every hardware step to its `stimgen.HardwareHost`:

1. `host.loadProtocol(path)` — load the protocol.
2. `host.connect()` — connect each interface.
3. `host.setMode("Preview")` — put devices in preview mode.
4. `host.calibrationAdapter()` — obtain an `HwAdapter` for the calibration-capable device.

Choosing *which* device can drive calibration is the host's decision, not the GUI's — `calibrationAdapter()` is free to scan available interfaces in whatever order it chooses and return the first that can build a working adapter.

Practical implication:

- If multiple interfaces exist, ordering matters if the host's `calibrationAdapter()` selects by interface order. Consult the host's documentation for how it picks the calibration-capable interface.

## Non-Compatible Protocol Patterns

CalibrationGui runtime init will not produce a usable adapter when:

1. The protocol contains only software-only interfaces without required buffer/trigger/readback parameters.
2. Hardware interfaces connect, but required calibration tags are absent.
3. Required tags exist but module Fs is unresolved or zero.
4. Interfaces are present but cannot connect at runtime.

## Controls Layout

The left column is a scrolling stack of titled sections above a footer that does
not scroll. Each section holds the settings a step consumes and then the button
that consumes them, so a control is found by what it is about rather than by its
position in one long list:

| Section | Contents |
|---|---|
| Microphone Reference | Reference Level, Reference Frequency, Mic Sensitivity, then Measure Reference and Measure Background — the two measurements that play nothing |
| Calibration | Excitation Voltage and Normative Value — the settings every sweep runs at — then Calibrate Tones, with the two optional sweeps below it, Tone Lookup From Swept Sine, and Iterative Level Refinement |
| Verification & Equalization | Test Tones beside Test Clicks — one per lookup table — then Design Filter beside Test Filter, Copy Filter Coefficients across the row below, and the Unity-Gain Noise Level readout under it |
| Display | Show Engine Live Plots, Transfer Plot Log X-Axis |
| Footer (pinned) | Stop, Reset Calibration, the Conduction Delay readout, and the status line |

Everything in the footer is there because it is what is needed while a sweep is
running, when the stack may be scrolled anywhere: Stop, the delay the sweep's
analysis windows are being cut with, and the status line. The status line
clips at one line; its tooltip always carries the whole message, which matters
for the test verdicts and background summaries that are wider than the column.

The remaining display options — spectrum y-axis unit, weighting overlays, the
previous-measurement ghost, and the drive-voltage axis — are checkable items on
the **View** menu rather than controls in this column. The four most-used of
them, plus the log frequency axis, are also toolbar buttons; see
[Choosing what the plots show](#choosing-what-the-plots-show).

Rig facts and acquisition settings live in their own window, opened from
**Hardware > Hardware Settings...**: the Sample Rate readout (read-only,
reported by the adapter), Max Output Voltage, and AC Couple Acquired Signal.
They are set once per rig, not once per sweep, so they earn a window over a
place in the per-sweep column. The conduction delay is not among them — it is
re-measured for every acquisition, so it belongs with the run rather than with
the rig, and its readout is in the footer. The window is non-modal and may
stay open during a run. Its two settings push to the engine the moment they
change, rather than when the next run starts, since the window may be closed
by then.

Every field and toggle in this column, the Hardware Settings window's two
settings, and the whole display state — spectrum unit, weighting overlays,
ghost, drive-voltage axis, log frequency axis — are remembered across MATLAB sessions as
`StimCalibrationGui` preferences. They are written when the window closes and
after each successful measurement start, and reapplied the next time the
window opens — per field, and only where the engine still holds its factory
default, so settings carried by a supplied engine, or by a loaded or
in-progress calibration, always win over remembered ones.

## GUI Menu Workflow (Current)

File menu actions:

1. Initialize Runtime From Protocol...
2. Recent Protocols (submenu)
3. Attach Adapter
4. Disconnect Runtime/Adapter
5. Load .esgc
6. Save .esgc
7. Recent Calibrations (submenu)

The toolbar's first group mirrors the five non-submenu File actions, plus the
Quick Start, as push buttons for one-click access; its second group is the
display controls (see [Choosing what the plots
show](#choosing-what-the-plots-show)). Both are built by `build_toolbar_` and
neither adds behavior the menus do not have.

View menu items, all checkable:

1. Calibration Transfer Curves / Background Noise Analysis — exclusive; which
   view the transfer panel serves
2. Weighting Overlay ▸ A / B / C / D, and None
3. Spectrum Y-Axis ▸ one item per `LiveMonitor.SpectrumUnitList` entry, exclusive
4. Previous-Measurement Ghost
5. Transfer Drive-Voltage Axis

The **Hardware** menu holds one item, **Hardware Settings...**, which opens
the [hardware window](#controls-layout) described above (reopening it when it
already exists brings it forward rather than making another).

Recent Protocols and Recent Calibrations each list up to nine most-recently-used
paths (newest first), persisted across MATLAB sessions as `StimCalibrationGui`
preferences (`RecentProtocols` / `RecentCalibrations`). Selecting an entry
re-runs the corresponding action (Initialize Runtime / Load .esgc) with that
path directly, skipping the file dialog. Successful Initialize Runtime and
Load/Save .esgc calls append to the relevant list; selecting an entry whose
file no longer exists removes it from the list instead of failing silently.

Recommended sequence:

1. Initialize Runtime From Protocol...
2. Attach Adapter (optional if auto-attach already succeeded)
3. Measure Reference — put an acoustic calibrator (e.g. PCB CAL150) on the
   microphone and switch it on first; the button prompts to confirm, then
   records for one second without playing anything. Remove the calibrator
   afterwards.
4. Build the tone lookup, one of two ways:
   - Calibrate Tones (direct per-frequency measurement), **or**
   - Calibrate Swept Sine, with the Tone Lookup From Swept Sine option checked
5. Test Tones — play tones at the levels the table says to use and check that
   those levels come back. Do this before trusting a calibration in an
   experiment; it is the only step that measures whether the lookup works
6. Optional: Calibrate Clicks and/or Calibrate Swept Sine. A click table earns
   the same closed loop as the tone table — Test Clicks
7. Optional: Design Filter, then Test Filter to verify it empirically. Copy
   Filter Coefficients exports the taps for use outside stimgen
8. Save .esgc

## Conduction Delay

The Conduction Delay row (in the pinned footer of the controls column, above
the status line) reports the rig's
speaker-to-microphone delay: acoustic propagation plus the converters'
round-trip latency, as one bulk offset. During every Calibrate Tones and
Test Tones run it is measured separately for each acquisition, from a brief
probe click embedded at the head of each played train (see
[the calibration guide](stimgen_calibration.md#step-5--calibrate-tones)) —
per acquisition because that latency is only guaranteed within a record and
need not repeat between records. Each record's burst analysis windows are
shifted by its own measured delay, so levels are measured over the response
rather than over the silence before it arrives.

The readout shows the delay in milliseconds with its equivalent air path at
343 m/s as a sanity check: a value far from the actual microphone distance
means converter latency dominates, which is normal for some devices but worth
knowing. It updates as each acquisition's probe lands (the GUI listens to the
engine's observable `ConductionDelay` property), not when the run finishes,
and being in the footer it stays in view however the stack is scrolled.
**Measurement unreliable** in red means the last record's click response was
not clearly above the noise or could not be aligned within the search bound
(`GapDuration`); that record then falls back to whole-record
cross-correlation and its analysis windows may include pre-response samples.
`Not measured` simply means no tone run has happened yet — clicks and swept
sine runs do not probe, because neither cuts per-burst windows.

## AC Couple Acquired Signal

The AC Couple Acquired Signal checkbox (in the Hardware > Hardware Settings... window) sets `Engine.AcCoupleResponse` the moment it changes. With the box checked, every record the engine acquires is high-passed at `Engine.AcCoupleFrequency` (fixed at its 20 Hz default; not exposed in the GUI) before anything is computed from it — the reference, the background, the tone and click sweeps, the swept sine, and both verification runs.

Check it when the input stage carries a DC offset or a wandering baseline. Either adds to the measured RMS (so levels read high, most visibly on quiet points), biases the cross-correlation that segments a tone-burst train, and puts low-frequency energy in the spectrum that leaks into the lowest analysis bins. Drift is the case a plain mean subtraction cannot reach: wander over a record averages to nearly nothing, so subtracting the mean leaves it entirely in place.

Semantics to be aware of:

- **Set the corner well below the lowest frequency you calibrate.** The filter is a second-order Butterworth, so the response is already down about 3 dB at the corner itself and rolls off below it. 20 Hz is the default and suits an audio rig; raise it to sit above mains hum, lower it if the calibration reaches into the low tens of Hz. A corner at or above Nyquist is skipped with a message rather than applied.
- **It shifts nothing in time.** The filter runs forwards and backwards (`filtfilt`), so the per-burst analysis windows and the conduction-delay probe still find the response where they expect it. A causal high-pass would move it out from under them.
- **It applies to what is measured next, not to what is already stored.** Checking the box does not re-analyze or redraw the record already on the waveform panel; re-run the measurement. Existing tables are not re-analyzed either, so a table measured with it off and one measured with it on should not be mixed.
- **The waveform panel title says what happened to the record**, so the setting's effect does not have to be judged by eye: `AC coupled 20 Hz (DC 12.34 mV removed)` whenever the option acted on the record, and `DC 12.34 mV` when an offset is still there and is worth more than 1% of the peak — the reading that tells you the option is worth turning on. Neither clause appears when the record is centered and nothing was removed.
- The record's mean is removed before it is filtered, and both happen *after* the trailing buffer padding is trimmed. Trimming still sees the zeros that mark the padding, and the filter never has to settle across a large DC step at the record's edges — which it would ring on for far longer than its padding covers, right where the delay-probe click sits. A record too short to filter at all keeps the mean removal alone and says so in the title.
- Measure Background is the one step it does not change the analysis of. That analysis already removes each record's mean and reports it as `dc_offset_v` acquisition health, and its band levels are meant to describe the floor the room actually has — so it is handed the record as acquired whatever this setting says. Only the displayed record follows the option.
- Like the other parameters both reach the engine when a run is started, and both are persisted in the `.esgc` file, so a loaded calibration records how its records were conditioned. A file saved before this replaced the older Demean Acquired Signal option loads with AC coupling on at the default corner if demeaning had been on.

## Tone Lookup From Swept Sine

The Tone Lookup From Swept Sine checkbox sets `Engine.ToneLutSource` ("tone" unchecked, "swept_sine" checked). It changes where tone lookups are *served from*, not what is stored: with it checked, `compute_adjusted_voltage("tone", ...)` — and therefore every StimType whose `CalibrationType` is `"tone"` (e.g. `Tone`), plus the `"filter"`/`"noise"` lookups anchored to the tone table — reads the swept sine LUT instead of the direct tone table. Both calibrations are on the same SPL/voltage scale, so the two sources are interchangeable at lookup time.

Semantics to be aware of:

- **While checked, the swept sine calibration overrides any direct tone calibration.** The direct tone table is not deleted — unchecking the box restores it instantly.
- If no swept sine data exists yet, the direct tone table still serves lookups (the option is a preference, not an error), and takes effect as soon as a sweep is run.
- The choice takes effect immediately when toggled, and is persisted in the `.esgc` file, so a calibration saved with it checked drives Tone stimuli from the swept sine table wherever that file is loaded.

## Iterative Level Refinement

With this checkbox (bottom of the Calibration section) checked, each tone or click
sweep is followed by `Engine.refine_tones`/`refine_clicks`: the finished table is
tested at its **own** points — each played at the drive voltage the table asks
for, through the same `test_tones`/`test_clicks` pathway that scales a real
stimulus — and every reliably measured point is corrected from the level error
that comes back (`e` dB high → stored voltage scaled by `10^(-e/20)`). Passes
repeat until a test lands every point within the target accuracy or the pass
limit is reached.

This buys absolute accuracy the one-shot sweep cannot: the sweep measures at the
excitation voltage and the table then assumes output scales as `20*log10` of
drive voltage, so any compression between those operating points becomes a level
error the refinement measures and removes. The sweep dialog collects the pass
limit and target while the box is checked; the refinement runs at the Normative
Value level with the sweep's repeat count.

Guarantees, all inherited from the Engine methods:

- A correction is never applied after the final test pass, so the committed
  table is always one a test just verified.
- Stop (or any error) restores the unrefined table; refinement is atomic like
  every other run.
- Points unreachable at the normative level or below the SNR floor are left
  uncorrected and reported.
- The refinement record is stored inside the refined table
  (`CalibrationData.tone.refinement` / `.click.refinement` /
  `.swept_sine.refinement`) and travels with the `.esgc`.

The status line reports the converged/not-converged verdict with the worst
residual; non-convergence also raises an alert, since the usual cause —
measurement spread larger than the target — has its own remedies (more
averages, or a looser target). Like every tone lookup, the refinement follows
Tone Lookup From Swept Sine, so with that checked it corrects the swept sine
table. The checkbox itself is a GUI preference (`iterativeCalibration`), not an
Engine setting.

## Calibration Parameter Dialogs

When Calibrate Tones, Calibrate Clicks, or Calibrate Swept Sine is invoked, the GUI prompts for measurement parameters via an input dialog. The previous values are remembered as MATLAB preferences between sessions.

For tones and clicks, the dialog collects:
- Frequency vector in Hz / click-duration vector in **milliseconds** (as a comma-separated or `linspace`/`logspace` expression)
- Repeat count (default 1). For clicks this is averages per point; for tones it is passes over the pregenerated burst train, which amounts to the same thing per frequency
- With **Iterative Level Refinement** checked, two more fields: the refinement's maximum test passes (default 3) and its target accuracy in dB (default 1). See [Iterative Level Refinement](#iterative-level-refinement)

For swept sine, the dialog collects:
- Chirp duration in **milliseconds** (default 1000)
- Frequency vector (optional override)
- Repeat count (number of chirp captures to average; default 4)

Durations are entered in milliseconds and converted to seconds before reaching the `Engine`, whose `calibrate_clicks` and `calibrate_swept_sine` signatures are unchanged and still take seconds. The stored preferences use `clickDurationsMs` and `sweptSineDurationMs` keys, so values remembered from a pre-milliseconds session are not silently reinterpreted.

The repeat count is passed directly to `Engine.calibrate_tones`, `Engine.calibrate_clicks`, or `Engine.calibrate_swept_sine` as the `repeatCount` argument.

Leaving the click-duration vector blank uses the `Engine` default, an octave series from 0.01 ms to 5.12 ms. It is specified in duration rather than sample counts, so the same sweep is requested regardless of the rig's sample rate. Durations that do not reach one sample at the current `Fs` cannot be rendered and are dropped before the sweep starts, with the skipped values logged; a vector in which none are resolvable raises `stimgen:calibration:Engine:unresolvableClickDurations`.

## Measure Background

Measure Background records the rig with nothing presented and characterizes what
comes back. Like Measure Reference it plays nothing — it acquires through
`HwAdapter.record` — but where that step is scaling the microphone, this one is
measuring the floor every later measurement sits on top of. Run it after Measure
Reference, with the calibrator off the microphone: without a reference the levels
are volts wearing a dB SPL label.

A dialog collects the record duration (default 2 s), how many records to take
(default 3), and how far a spectral peak must stand above the local floor to be
called tonal (default 6 dB). All three are remembered between sessions. The run
is cancellable with Stop.

`Engine.measure_background` power-averages the records' spectra and reports:

- **broadband level**, unweighted and A-weighted — the gap between them says how
  much of the noise is where hearing actually is;
- **fractional-octave band levels** (third-octave by default), the form a noise
  floor is comparable in and the form to read a stimulus spectrum against;
- **tonal components** — narrowband peaks against a running-median local floor,
  with sub-bin frequency refinement, plus whether they line up with 50 or 60 Hz
  mains harmonics;
- **acquisition health** — DC offset, crest factor, headroom to full scale, and
  whether the input is sitting on its quantization floor;
- **stability** — the spread of the per-record levels, which is what says whether
  a single number describes the room at all.

The panel is drawn on the transfer axes by `LiveMonitor.show_background`: the
1/12-octave spectrum behind, the analysis bands on top, the A-weighted bands
alongside, the broadband level across, and the tonal components marked and
labelled. A dialog gives the numbers that are awkward to read off a curve, and
the status line carries the headline. Findings — clipping, a quantizer-limited
input, an unsteady room, mains hum, a floor close to the normative level — turn
that dialog into a warning and are listed in it.

The result is stored in `CalibrationData.background` and saved in the `.esgc`, so
a calibration file records the noise floor its tables were measured over.
`CalibrationTimestamp` is deliberately left alone: a background capture does not
re-date the transfer measurements. A file holding only a background capture is
saveable, and loads with its timestamp reported as unknown.

## Test Tones

Test Tones is the closed loop on the tone calibration: `Engine.test_tones` asks
the lookup table what voltage a given frequency needs for a given dB SPL, plays
a gated burst at exactly that voltage, measures what came back, and reports the
difference. The drive voltage comes from `compute_adjusted_voltage` — the same
call `StimType.apply_calibration` makes when it scales a `Tone` — so what is
verified is the level normalization a real stimulus gets, not a reimplementation
of it. Which table is tested follows Tone Lookup From Swept Sine.

The dialog collects a frequency list, a level list, and an average count, all
remembered as preferences. Both lists may be left empty, which is the
recommended way to run it:

| Field | Empty means | Why |
|---|---|---|
| Test frequencies (Hz) | geometric midpoints between successive LUT points, at most 15 | These are the frequencies the sweep never measured. At the LUT's own frequencies the interpolant reproduces the measurement by construction, so testing there proves nothing; halfway between two points is where `makima` is doing all the work |
| Requested levels (dB SPL) | Normative Value and 10 and 20 dB below it | One level only checks the table. Three check the other half of the model — that level scales as 20·log10 of drive voltage away from `NormativeValue` |
| Number of averages | 2 | A second pass gives the ±1 SD ribbon, which is the only evidence on screen that a point converged rather than drifted |

The status line reports the verdict, the worst error and where it occurred, and
the mean bias, against the pass tolerance (default 3 dB). A failure raises an
alert; the shape of the error says what to fix:

- **A uniform bias at every frequency and level** — the reference measurement or
  Normative Value moved since the sweep. Re-run Measure Reference.
- **Errors at scattered frequencies, small elsewhere** — the table is too sparse
  to interpolate through a response with structure between its points. Re-run
  Calibrate Tones with a finer frequency list.
- **Errors that grow with level** — the rig is running out of range. Check
  `results.clipping` and the drive voltages against Max Output Voltage.

Points whose required drive exceeds Max Output Voltage are skipped rather than
played — they would clip, and clipping measures the amplifier, not the table.
They are counted in the status line and listed in `results.skipped`, never
dropped silently. Points that come back below the SNR floor (default 10 dB) are
measured but excluded from the verdict, since noise reads *high* and would fail
the test for something the table did not do. Clipped points are kept in the
verdict: clipping reads low, and a level the rig cannot deliver cleanly is a
level the calibration does not deliver.

The full result is stored in `CalibrationData.toneTest`, so a saved `.esgc`
carries the evidence that its tone table reproduces the levels it promises. The
run is cancellable with Stop. With live plots on, the transfer panel fills in
the measured level against frequency one requested level at a time — a correct
table draws a flat line at the level under test.

## Test Clicks

Test Clicks is the same closed loop on the click calibration: `Engine.test_clicks`
asks the lookup table what voltage a click of a given duration needs for a given
dB SPL, plays one click at exactly that voltage, measures its peak the way
Calibrate Clicks measures one, and reports the difference. The drive voltage comes
from `compute_adjusted_voltage("click", …)` — the same call
`StimType.apply_calibration` makes when it scales a `ClickTrain`.

The dialog collects a duration list (in milliseconds, as the click sweep's does),
a level list, and an average count, all remembered as preferences. Both lists may
be left empty:

| Field | Empty means | Why |
|---|---|---|
| Test click durations (ms) | geometric midpoints between successive LUT durations, at most 10 | The durations the sweep never measured, where `makima` is doing all the work; at the LUT's own durations the interpolant reproduces the measurement by construction |
| Requested levels (dB SPL) | Normative Value and 10 and 20 dB below it | Checks that level scales as 20·log10 of drive voltage away from `NormativeValue`, not just that one point of the table is right |
| Number of averages | 2 | A second pass gives the ±1 SD ribbon |

There is no burst schedule and no conduction delay to resolve: a click is brief
and broadband, so the peak of the record is the peak of the click wherever in the
record it landed. Durations below one sample at the current rate are dropped with
a message, the same floor Calibrate Clicks applies; unreachable and
noise-dominated points are treated exactly as in Test Tones. Expect short
durations to be the first to fall below the SNR floor at low requested levels —
they put little energy into the room — and to be reported as excluded rather than
failed.

The status line reports the verdict, the worst error and the duration it occurred
at, and the mean bias against the pass tolerance (default 3 dB); the full result
is stored in `CalibrationData.clickTest`. With live plots on, the transfer panel
draws measured level against click duration in µs, one requested level at a time.

## Filter Design Dialog

Design Filter prompts for the equalizer design options before running, and remembers them as preferences the same way. Each field maps onto one `Engine.design_filter` argument — see `stimgen_calibration.md` for what they do:

| Field | Argument | Default |
|---|---|---|
| LUT source | `source` | `auto` |
| Number of coefficients | `NumCoefficients` (omitted when 0) | `0` |
| Design method | `DesignMethod` | `freqsamp` |
| Interpolation | `Interpolation` | `pchip` |
| Frequency scale | `FrequencyScale` | `log` |
| Fractional-octave smoothing | `SmoothingOctaves` | `0` |
| Maximum correction depth | `MaxCorrectionDb` | `Inf` |
| Frequency range | `FrequencyRange` (empty = LUT span) | empty |
| Design sample rate | `SampleRate` (empty or 0 = hardware rate) | empty |

**Design sample rate** is how a calibration measured on one rig produces a filter for another. The LUT is in Hz and volts and holds at any rate, but the taps fitted to it only realize the designed response at the rate they were cut for — run a 200 kHz design at 100 kHz and every correction lands an octave low. The prompt names the attached hardware's rate so leaving it empty is the obvious choice; with no adapter attached the field is required, which is what makes offline redesign of a loaded `.esgc` possible. See [Changing The Design Sample Rate](stimgen_calibration.md#changing-the-design-sample-rate).

Designing for a rate other than the attached adapter's is reported in red on the status line, and the **Sample Rate** display then reads e.g. `100000 Hz (filter designed at 200000 Hz)` in red for as long as the mismatch stands — including after loading a `.esgc` whose filter was cut elsewhere. Test Filter (its sweep branch) refuses such a filter rather than reporting the rate error as a design failure.

The status line reports the resulting tap count, correction span and design rate, and the design opens in `fvtool`. Each design replaces the fvtool window left by the previous one, so tuning by repeated redesign does not accumulate windows.

## Test Filter

Test Filter verifies the equalizer empirically, and which verification runs follows what the filter was designed from (`CalibrationData.filterSource`):

- **Filter designed from the tone table** — the button runs the same discrete-tone verification as Test Tones (`Engine.test_tones`): actual tones are played at the drive voltages the lookup table asks for, and the levels that come back are compared to the levels requested. The tone table, not the sweep, is what scales a `Tone` stimulus, so it is the thing to verify. The usual tone-test dialog collects the frequency/level grid, and the result is stored in `CalibrationData.toneTest`.
- **Filter designed from the swept sine** — the button runs `Engine.test_filter`: the sweep is played raw and again through the filter, both responses are measured against the raw chirp, and the flatness of the equalized response is compared to the speaker's own. The status line reports the ripple before and after against the pass tolerance (default 6 dB peak-to-peak), a failure raises an alert with redesign advice, and the full result is stored in `CalibrationData.filterTest` so the saved `.esgc` records that its filter was verified.

Either run is cancellable with Stop, and with live plots on the transfer panel fills in as the measurement proceeds — for the sweep branch, the raw response first and then the flattened one. The sweep flatness test remains available programmatically as `eng.test_filter()` regardless of the filter's source.

## Copy Filter Coefficients

Copy Filter Coefficients puts the current equalizer's FIR taps (`tf(CalibrationData.filter)`) on the system clipboard as plain text: one coefficient per line, printed `%.17g` so a double round-trips exactly, CRLF-terminated on Windows. Nothing else is in the text — no header, no brackets, no separators — so it pastes as-is into an RPvds coefficient file, a spreadsheet column, MATLAB's `[ ]`, or another language's array literal.

The tap count and the rate the filter was designed for go to the status line rather than into the clipboard, since a filter only realizes its designed response at the rate it was cut for and the text has to stay purely numeric. The button needs no adapter — it reads taps that already exist, so a `.esgc` loaded on a machine with no rig attached is still exportable. A non-FIR filter (nothing `design_filter` produces) is reported on the status line instead of copied, having no single tap list.

## Unity-Gain Noise Level

Under Copy Filter Coefficients, the **Unity-Gain Noise Level** readout reports what the exported taps do to a level once they run in hardware: the dB SPL a 1 V RMS spectrally white source produces at unity hardware gain after passing through the equalization filter, followed by the factor (×) that scales it down to the Normative Value level. Both come from `Engine.filter_level_reference(1)`.

The number exists because `design_filter` produces a shape-only filter and `apply_calibration` renormalizes after filtering — in software the filter's insertion loss never reaches the output level. A hardware chain that runs the taps itself (an RPvds FIR component, for instance) has no renormalization step, so its gain stage must be anchored to this readout rather than to the lookup table alone. Multiply the filtered signal — or the taps themselves, before loading them — by the scale, and a hardware gain of `10^((level − NormativeValue)/20)` then plays the source at `level` dB SPL, on exactly the convention `apply_calibration` uses for an RMS-normalized noise stimulus.

The readout assumes a 1 V RMS white source, for which the filtered RMS has a closed form; a source that is shaped, band-limited before the FIR, or generated in software should be passed to `Engine.filter_level_reference` as its actual waveform instead. The value refreshes with every filter design, calibration load, and Normative Value edit, and the same figures are appended to the status line when a design completes. `Not designed` means there is no filter, or no tone/swept-sine table to anchor it to.

## Reset Calibration

Reset Calibration discards `Engine.CalibrationData` (tone/click/swept-sine tables, any designed filter, and any background capture), the last response record, and the calibration timestamp, then redraws the plots empty via `Engine.reset_calibration()`. If a calibration is currently loaded, it prompts for confirmation first.

Everything else is left untouched: the attached adapter, the loaded protocol/host, and every persistent Engine parameter — Reference Level, Reference Frequency, **Mic Sensitivity** (including one set by Measure Reference), Normative Value, Excitation Voltage, Max Output Voltage, AC Couple Acquired Signal and its corner, Show Engine Live Plots, and Tone Lookup From Swept Sine. Use it to redo a calibration run from scratch without re-attaching hardware or re-measuring the microphone.

## Button Enable Rules

1. Measure Reference, Measure Background, Calibrate Tones, Calibrate Clicks, Calibrate Swept Sine: enabled only when Engine.Adapter is attached.
2. Test Tones: enabled when tone **or** swept sine calibration data exists **and** an adapter is attached — verification is a live measurement. The condition is deliberately not tone-only: with Tone Lookup From Swept Sine checked, the sweep is the table a `Tone` stimulus is scaled by, so it is the one that has to be verified.
3. Test Clicks: enabled when click calibration data exists **and** an adapter is attached. Only `calibrate_clicks` ever writes that table, so unlike Test Tones there is no alternative source to account for.
4. Design Filter: enabled when tone **or** swept sine calibration data exists — no adapter needed, since the design sample rate can be entered in the dialog. `Engine.design_filter` prefers the tone LUT and falls back to swept sine.
5. Test Filter: enabled when a filter has been designed or loaded **and** an adapter is attached — verification is a live measurement.
6. Copy Filter Coefficients: enabled when a filter has been designed or loaded — no adapter needed, since it only reads taps that already exist.
7. Tone Lookup From Swept Sine: always enabled — it is a lookup preference on committed data, meaningful with or without an adapter.
8. Reset Calibration: always enabled (except while a calibration run is in progress) — it only clears acquired data, not the adapter or settings.

## Runtime Ownership And Independence

CalibrationGui holds no runtime or protocol state of its own. It keeps a single `Host` reference (a `stimgen.HardwareHost`, or empty when offline) and asks the host for everything hardware-related. All runtime and protocol objects live on the host side.

This is what keeps stimgen independent of any experiment framework, and it means CalibrationGui does not require a StimPlayer runtime handoff to function.

## Error Surfaces You Should Expect

Raised by the GUI itself:

1. `stimgen:calibration:CalibrationGui:noHost` — a runtime menu action was used with no host attached.

Raised by the host (identifiers are host-specific; the ones below are representative):

2. `<host>:noRuntimeInterfaces` — no interfaces available on the loaded protocol.
3. `<host>:attachAdapterFailed` — no interface could build a working `HwAdapter`.
4. `<host>:missingParameter` — a required buffer/trigger parameter was not found.
5. `<host>:noSampleRate` — no interface reported a usable sample rate.
6. `<host>:connectFailed` — the interface failed to connect.

These are surfaced in the status label and a uialert dialog.

## Minimal Compatibility Test

Use this quick test after protocol changes:

```matlab
gui = stimgen.calibration.CalibrationGui(stimgen.calibration.Engine(), host);
% In GUI: File > Initialize Runtime From Protocol... and select protocol
% Expect: status shows adapter attached, calibration buttons enabled
```

If buttons remain disabled, the selected protocol does not satisfy interface/tag/sample-rate requirements above.

## Maintenance Notes

When editing protocol hardware circuits for calibration support:

1. Keep required parameter names stable.
2. Ensure module Fs is configured and non-zero.
3. Verify connectability before launching CalibrationGui.
4. Re-run the minimal compatibility test.

## See Also

1. [stimgen_calibration.md](stimgen_calibration.md)
2. [stimgen_StimCalibration.md](stimgen_StimCalibration.md)
3. +stimgen/+calibration/Engine.m
