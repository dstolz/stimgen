# `stimgen.StimCalibration`

`stimgen.StimCalibration` is the calibration controller that stimulus objects talk to. Since the calibration refactor it is a thin wrapper around the `stimgen.calibration` package: [stimgen.calibration.Engine](stimgen_calibration.md) does the measurement and lookup work, and an adapter handles hardware I/O. The wrapper exists so `stimgen.StimType` keeps working unchanged.

This is a developer reference. If you just want to calibrate a rig, follow [stimgen_calibration.md](stimgen_calibration.md).

Source class:

- [+stimgen/@StimCalibration/StimCalibration.m](../+stimgen/@StimCalibration/StimCalibration.m)

## Two construction modes

### Offline mode

```matlab
cal = stimgen.StimCalibration();
cal.load_calibration('Rig3_earphone.esgc');
```

Without arguments the object holds an offline `Engine`. Load a saved `.esgc` file and attach the object to stimuli; no hardware is required.

### Online (measurement) mode

```matlab
cal = stimgen.StimCalibration(adapter);
```

Pass a `stimgen.calibration.HwAdapter` connected to your hardware and the constructor builds an `Engine` around it and launches the calibration window so a new calibration can be measured. stimgen ships `stimgen.calibration.WindowsSoundCardAdapter`; for lab hardware, use a host-supplied `HwAdapter`, e.g. `host.calibrationAdapter()`.

## Delegated properties

These proxy directly to the underlying `Engine`:

- `CalibrationData`
- `MicSensitivity`
- `ReferenceLevel`
- `ReferenceFrequency`
- `NormativeValue`
- `ExcitationSignalVoltage`
- `CalibrationTimestamp`

The widgets mirror these automatically. The engine's parameters are `SetObservable`, and `gui()` registers a `PostSet` listener per field, so a value changed from anywhere — `calibrate_reference` replacing `MicSensitivity`, or a host calling `set_configuration` directly — reaches the display without the writer having to know the GUI exists. A value the engine accepts but the widget's `Limits` refuse is logged and left undisplayed rather than thrown, because these listeners can fire from inside a running sweep.

## Key methods

- `gui()` — build or raise the calibration window.
- `refresh_plots()` — redraw the panels from the Engine's current state.
- `compute_adjusted_voltage(...)` — proxy to the Engine; called by `stimgen.StimType.apply_calibration()` to convert a requested dB SPL level into an output voltage.
- `load_calibration(filename)` / `save_calibration(filename)` — read/write `.esgc` files (legacy `.sgc` files can still be loaded).
- `toStruct()` / `saveobj()` / `loadobj(s)` — serialization. `loadobj` rebuilds an offline instance and repopulates it through `Engine.restore(s)`.

## The window

Two columns: engine parameters and the two run buttons on the left, a
[`stimgen.calibration.LiveMonitor`](stimgen_calibration.md#watching-a-run) on the right.
The monitor's three panels are attached to axes in this figure rather than to a window of
its own, so a sweep fills in beside the controls driving it:

- **Waveform** — the response over time, the excitation behind it as a scaled ghost, and shading over the span the measurement was actually computed from. That span is the point of the panel: a level that looks wrong is usually a segmentation problem, and a whole tone train is a single record in which the individual bursts are otherwise indistinguishable.
- **Spectrum** — dB SPL, on the same scale as the calibration itself, with the previous measurement as a ghost and markers at the fundamental and its 2nd and 3rd harmonics.
- **Transfer** — the lookup table as it fills in, with the points still to come as a rug, a ±1 SD ribbon across repeats, and the drive voltage each point needs for `NormativeValue` against the rig's `MaxOutputVoltage` ceiling. Points above that line cannot be produced at the normative level.

`Max Output Voltage` sets that ceiling and the full scale the clipping test is judged
against. `Live Plots` gates the engine's `LiveUpdate` broadcast; with it off, the panels
refresh only when a run finishes, a file is loaded, or the toolbar's refresh button is
pressed. `Log X-Axis` switches the transfer panel between log and linear.

The monitor follows an *engine*, not this object, so `load_calibration` — which replaces
the engine outright — re-attaches it and re-registers the parameter listeners. Closing
the window detaches the monitor and stores the window position; the engine outlives the
GUI, because a `StimType` goes on using it to convert levels.

`stimgen.calibration.CalibrationGui` is a separate, fuller front end for the same engine —
use it when you want swept-sine runs, filter design, and protocol-driven hardware setup.

### Restoring engine state

The `Engine` measurement properties are `SetAccess = protected`, so `StimCalibration` cannot assign them directly. `stimgen.calibration.Engine.restore(s)` is the supported entry point, used by `loadobj` whenever a calibration is rebuilt from a serialized `StimType` or a `.spl` bank. It accepts either field naming in circulation — `ExcitationVoltage` (`.esgc` / `Engine.save`) or `ExcitationSignalVoltage` (`StimCalibration.toStruct`) — and leaves any missing field at its current value, so partial structs from older files are safe.

## Attaching calibration to stimuli

```matlab
tone = stimgen.Tone;
tone.Frequency = 4000;
tone.SoundLevel = 60;
tone.Calibration = cal;      % also settable via StimPlay/StimPlayer
tone.ApplyCalibration = true;
tone.update_signal();
```

Assigning `Calibration` on a `stimgen.StimPlay` wrapper forwards the object to the wrapped stimulus; `stimgen.StimPlayer` exposes the same through its **File > Calibration** menu.

## Caveats for developers

- Calibration behavior is coupled to the `CalibrationType` constant on each stimulus class; adding a new calibration mode usually requires coordinated changes in the `stimgen.calibration` package and `StimType.apply_calibration()`.
- The `CalibrationData` schema is defined by the Engine (see [stimgen_calibration.md](stimgen_calibration.md) for the structure reference).

## Related documentation

- [stimgen_calibration.md](stimgen_calibration.md) — calibration concepts, GUI walkthrough, programmatic workflow, and data structure reference
- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine method
- [stimgen_StimType.md](stimgen_StimType.md) — how stimuli consume calibration
