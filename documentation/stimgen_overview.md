# Stimulus Generation Package

`stimgen` is a standalone stimulus authoring, calibration, and playback toolbox with no dependency on any host application; host applications integrate through the abstract `stimgen.HardwareHost` and `stimgen.calibration.HwAdapter` classes.

At a high level, the package lets you:

- define waveforms as MATLAB objects (tones, noise, clicks, and more)
- scale those waveforms with acoustic calibration data so requested dB SPL levels are accurate
- present them through MATLAB preview audio or hardware playback

This overview is the entry point for the subsystem. The first half is for users operating the tools; the developer notes at the end are for people extending the package.

## Documentation map

- [stimgen_StimType.md](stimgen_StimType.md): base stimulus contract and extension points (developer reference)
- [stimgen_StimTypes.md](stimgen_StimTypes.md): catalog of built-in stimulus classes and their properties
- [stimgen_StimPlay.md](stimgen_StimPlay.md): repetition and selection wrapper used by playback tools (developer reference)
- [stimgen_SoundFile.md](stimgen_SoundFile.md): playback of pregenerated sound files, including calibration of spectrotemporally complex material
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md): standalone stimulus-bank tool with `.spl` save/load support
- [stimgen_StimInspector.md](stimgen_StimInspector.md): detail window for one stimulus — waveform, spectrum, spectrogram, THD and signal metrics
- [stimgen_calibration.md](stimgen_calibration.md): calibration concepts, GUI walkthrough, and programmatic workflow
- [stimgen_CalibrationGui.md](stimgen_CalibrationGui.md): calibration GUI reference
- [stimgen_SweptSineCalibration.md](stimgen_SweptSineCalibration.md): swept-sine calibration method
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md): the `StimCalibration` wrapper used by stimulus objects
- [stimgen_TDT_RPvds.md](stimgen_TDT_RPvds.md): TDT/RPvds hardware circuit contract and legacy file types

## Core workflow

Most `stimgen` workflows follow the same model:

1. Create or edit a `stimgen.StimType` object such as `Tone` or `Noise`.
2. Wrap it in `stimgen.StimPlay` if you need repetitions, ISI handling, or ordered/shuffled presentation.
3. Attach calibration when output level must be tied to measured SPL.
4. Present the result through `stimgen.StimPlayer` or your experiment's hardware circuit.

Minimal example:

```matlab
tone = stimgen.Tone;
tone.Frequency = 4000;
tone.SoundLevel = 60;
tone.update_signal;
tone.play          % preview through the computer speakers

sp = stimgen.StimPlay(tone);
sp.Reps = 20;
sp.ISI = [0.8 1.2];
```

## Built-in stimulus classes

- `stimgen.Tone` — pure tone; `Frequency` and `OnsetPhase` may be vectorized to define variants
- `stimgen.Noise` — band-limited Gaussian noise
- `stimgen.AMnoise` — sinusoidally amplitude-modulated noise
- `stimgen.AttackModNoise` — attack-shaped modulated noise
- `stimgen.ClickTrain` — periodic click train
- `stimgen.FMtone` — frequency-modulated tone
- `stimgen.SweptSine` — logarithmic chirp (also used by calibration)
- `stimgen.TORC` — temporally orthogonal ripple combination, for STRF estimation by spectrotemporal reverse correlation
- `stimgen.SoundFile` — playback of pregenerated sound files (vocalizations, phonemes); see [stimgen_SoundFile.md](stimgen_SoundFile.md)

See [stimgen_StimTypes.md](stimgen_StimTypes.md) for the full property reference of each class.

To present a family of related stimuli (e.g., a frequency × level grid), assign vector values to the relevant properties and use the variant-selection controls on `stimgen.StimType` (`VariantSelectionMode`, `VariantCombinationMode`, and related methods). This replaced the older `multiTone` class, which has been removed.

## Choosing the right tool

### Use the calibration GUI (`stimgen.calibration.CalibrationGui`) when

- you need measured SPL-to-voltage mapping for a speaker or earphone
- you want to save or load reusable `.esgc` calibration files
- your stimulus classes will run with `ApplyCalibration = true`

See [stimgen_calibration.md](stimgen_calibration.md) for the full walkthrough.

### Use `StimPlayer` when

- you want a stimulus bank editor and player, with or without hardware
- you want easy local speaker preview even when hardware is absent
- you want to save and reload stimulus banks as `.spl` files

`stimgen.StimPlayer` optionally accepts a `stimgen.HardwareHost` that provides the hardware interfaces used for playback; omit it for speaker-preview-only operation. The older `StimGenInterface` and `StimGenInterface_Simple` GUIs have been removed; `StimPlayer` is the current playback tool.

## Runtime and hardware expectations

Hardware playback requires the host to expose a specific set of RPvds circuit parameters; if the
protocol is missing or those parameters are unavailable, the GUIs still open, but only speaker
preview is available. See [stimgen_TDT_RPvds.md](stimgen_TDT_RPvds.md) for the exact parameter
contract and TDT-specific legacy file types.

## Saved file types

- `.esgc`: calibration files from the `stimgen.calibration` package (legacy `.sgc` files can still be loaded)
- `.spl`: stimulus-bank files from `StimPlayer`
- `.eprot`: host protocol files, which a host can load to reach hardware (via `HardwareHost.loadProtocol`); see [stimgen_TDT_RPvds.md](stimgen_TDT_RPvds.md)

## Developer notes

Several package behaviors are driven by file and metadata conventions:

- `stimgen.StimType.list()` scans `+stimgen` to decide which classes appear in GUI lists.
- `propMeta()` and `create_gui()` control how stimulus editors are built; a new subclass with clean metadata usually appears in `StimPlayer` without any player changes.
- `StimType.apply_calibration()` and the calibration engine are coupled through the stimulus class's `CalibrationType` constant.
- Every tooltip in the package lives in `+stimgen/tooltips.json`, one section per class, and is read through `stimgen.util.tooltip()`. See [Hover help](stimgen_StimType.md#hover-help).

Practical implications:

- Adding a new stimulus class is usually straightforward: implement `update_signal()`, define user-facing properties with good `propMeta()` metadata, and keep the constructor callable with no required arguments. See [stimgen_StimType.md](stimgen_StimType.md).
- Adding a new calibration mode requires coordinated edits across the `stimgen.calibration` package and `StimType`.

## Related files

- [+stimgen/@StimType/StimType.m](../../+stimgen/@StimType/StimType.m)
- [+stimgen/StimPlay.m](../../+stimgen/StimPlay.m)
- [+stimgen/@StimPlayer/StimPlayer.m](../../+stimgen/@StimPlayer/StimPlayer.m)
- [+stimgen/@StimCalibration/StimCalibration.m](../../+stimgen/@StimCalibration/StimCalibration.m)
- [+stimgen/+calibration/](../../+stimgen/+calibration/)
