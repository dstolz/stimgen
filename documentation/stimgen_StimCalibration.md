# `stimgen.StimCalibration`

`stimgen.StimCalibration` is the calibration object that stimulus classes talk to. Since the calibration refactor it is a thin wrapper around the `stimgen.calibration` package: [stimgen.calibration.Engine](stimgen_calibration.md) does the measurement and lookup work, and an adapter handles hardware I/O. The wrapper exists so `stimgen.StimType` keeps working unchanged.

It is headless. The one interactive front end in the package is [`stimgen.calibration.CalibrationGui`](stimgen_CalibrationGui.md), which drives the same `Engine`; `StimCalibration` is what a calibration *is* once it has been measured — the form a `StimType` holds and `toStruct`/`saveobj` carry into `.spl` banks and host protocol files.

This is a developer reference. If you just want to calibrate a rig, follow [stimgen_calibration.md](stimgen_calibration.md).

Source class:

- [+stimgen/@StimCalibration/StimCalibration.m](../+stimgen/@StimCalibration/StimCalibration.m)

## Two construction modes

### Offline mode

```matlab
cal = stimgen.StimCalibration();
cal.load_calibration('Rig3_earphone.esgc');
```

Without arguments the object holds an offline `Engine`. Load a saved `.esgc` file and attach the object to stimuli; no hardware is required. This is the common case — it is what `loadobj`, `StimPlayer`, and `StimType.fromStruct` build.

### Online (measurement) mode

```matlab
cal = stimgen.StimCalibration(adapter);
```

Pass a `stimgen.calibration.HwAdapter` connected to your hardware and the constructor builds an `Engine` around it, so the measurement methods on `Engine` can be driven programmatically. stimgen ships `stimgen.calibration.WindowsSoundCardAdapter`; for lab hardware, use a host-supplied `HwAdapter`, e.g. `host.calibrationAdapter()`. To measure interactively, use `stimgen.calibration.CalibrationGui` instead.

## Delegated properties

These proxy directly to the underlying `Engine`:

- `CalibrationData`
- `MicSensitivity`
- `ReferenceLevel`
- `ReferenceFrequency`
- `NormativeValue`
- `ExcitationSignalVoltage`
- `ToneLutSource`
- `CalibrationTimestamp`
- `Fs`

The `Engine`'s parameters are `SetAccess = protected`, so every setter here routes through `Engine.set_configuration`, which is also what runs the property validators. A rejected value therefore raises rather than being silently stored.

## Key methods

- `compute_adjusted_voltage(...)` — proxy to the Engine; called by `stimgen.StimType.apply_calibration()` to convert a requested dB SPL level into an output voltage.
- `design_filter(...)` / `test_filter(...)` — proxies to `Engine.design_filter` and `Engine.test_filter`, arguments and all.
- `load_calibration(filename)` / `save_calibration(filename)` — read/write `.esgc` files. Called with no argument, each prompts for a file. `load_calibration` replaces the `Engine` outright.
- `toStruct()` / `saveobj()` / `loadobj(s)` — serialization. `loadobj` rebuilds an offline instance and repopulates it through `Engine.restore(s)`.

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
- This class had a second calibration window of its own (`gui()`, plus `refresh_plots`, a `LiveMonitor`, and a `ClickDurations` per-run property). It was removed in favour of a single front end; anything that called `cal.gui()` should open `stimgen.calibration.CalibrationGui` instead.

## Related documentation

- [stimgen_calibration.md](stimgen_calibration.md) — calibration concepts, GUI walkthrough, programmatic workflow, and data structure reference
- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md) — GUI reference
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md) — swept-sine method
- [stimgen_StimType.md](stimgen_StimType.md) — how stimuli consume calibration
