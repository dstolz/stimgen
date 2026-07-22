# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A MATLAB toolbox (R2021a+) for auditory stimulus generation, playback, and speaker/microphone
calibration. Extracted from [EPsych v2](https://github.com/dstolz/epsych2) and deliberately kept
free of any dependency on it. Requires Signal Processing Toolbox; Audio Toolbox only for
sound-card playback/preview.

## Working in this repo

There is no build, no test suite, and no CI. Verification is done by running code in MATLAB.

```matlab
addpath('C:\src\stimgen')   % the ROOT, never +stimgen itself (MATLAB resolves it as a package)

t = stimgen.Tone; t.Frequency = 4000; t.update_signal; t.plot   % smoke test
stimgen.StimPlayer                        % bank editor/player (offline = speaker preview only)
stimgen.calibration.CalibrationGui        % offline: inspect/load a .esgc
```

After editing a classdef, MATLAB caches the old definition. `clear classes` (or restart) before
re-testing, otherwise changes appear not to take effect.

`.esgc` files are gitignored — they are calibration output written during local testing.

Commit messages follow Conventional Commits (`docs:`, `feat:`, …).

## Architecture

Three subsystems, plus two abstract seams that keep the package standalone.

**Stimulus generation** — `stimgen.StimType` (abstract, in `@StimType/`) plus concrete subclasses
as loose `.m` files in `+stimgen/`: `Tone`, `Noise`, `AMnoise`, `AttackModNoise`, `FMtone`,
`SweptSine`, `ClickTrain`. The base class owns level/duration/gating/Fs, the variant system,
serialization, and GUI generation; subclasses only synthesize a waveform.

**Playback** — `stimgen.StimPlay` wraps a StimType with reps/ISI/selection order.
`stimgen.StimPlayer` (in `@StimPlayer/`) manages a bank of StimPlay objects, double-buffers audio
into hardware, and triggers from its own MATLAB timer.

**Calibration** — `stimgen.calibration.Engine` (in `+calibration/@Engine/`) does all measurement
math and owns `.esgc` save/load. `stimgen.StimCalibration` is a thin GUI-state wrapper that
delegates every property to an Engine; it exists so `StimType` sees stable property names.
`stimgen.calibration.CalibrationGui` is the interactive front end.

### The two abstract seams — do not break these

`stimgen` never references a host-application type. All hardware coupling goes through:

- `stimgen.HardwareHost` — protocol load, connect/release, `setMode`, `findParameter`,
  `connectionState`, `calibrationAdapter`. Consumed by `StimPlayer` and `CalibrationGui`.
- `stimgen.calibration.HwAdapter` — `sample_rate()` and `play_and_record(signal)`. Consumed only
  by `Engine`. `WindowsSoundCardAdapter` is the one built-in implementation.

Both are optional at construction; omitting them puts the GUIs in offline mode where speaker
preview still works. New hardware support means a new `HwAdapter` subclass, never an edit inside
`Engine`. Reference host implementation: the `stimbridge` package in EPsych v2.

## Conventions that will bite you

**Class-folder layout.** `@StimType/`, `@StimPlayer/`, `@StimCalibration/`, `@Engine/` each hold
one method per file, declared as signature-only lines in the classdef. When adding a method you
must add both the file and its declaration. A trailing underscore (`select_variant_index_`,
`commit_cal_data_`) marks a private/protected helper.

**`update_signal` must guard the variant cycle.** Every subclass opens with:

```matlab
function update_signal(obj)
    if ~obj.variantCycleActive_
        obj.call_update_signal_with_variant_cycle_();
        return
    end
    ...
```

Inside the body, read vectorized properties through `obj.selected_value("Frequency")` — never
`obj.Frequency` directly, which may be a vector. `Fs`, `ApplyCalibration`, and `ApplyWindow` are
non-vectorizable (`is_non_vectorizable_property_`).

**Signal pipeline order is normalize → calibrate → gate**, uniformly across all subclasses.
Calibration must come before gating: `apply_calibration` renormalizes before scaling to the LUT
voltage, which would undo an earlier ramp.

**Variants.** Assigning a vector to a user property expands it into variant combinations, governed
by `VariantCombinationMode` (Cartesian / PairwiseStrict / PairwiseScalarExpand) and
`VariantSelectionMode` (Serial / ShuffleUniform / ShuffleLeastUsed / CustomSelector). The
combination table is cached and invalidated by a signature hash — see
`refresh_variant_cache_if_needed_`.

**GUIs are generated, not hand-built.** `create_gui` reads `propMeta()` and builds a label+widget
grid; widget type is inferred from the property's class unless overridden. Subclass `propMeta`
defines its own fields then calls
`stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj))`. A subclass with clean
metadata appears in `StimPlayer` with no player-side changes.

**Class discovery is filename-based.** `StimType.list()` globs `*.m` in `+stimgen/` and filters out
a hardcoded exclusion list plus anything containing `Calib`. A new stimulus file in that folder is
automatically offered in GUI dropdowns.

**Calibration coupling.** A subclass's `CalibrationType` constant (`"tone"`, `"click"`,
`"filter"`, `"swept_sine"`) selects which LUT `apply_calibration` interpolates and which property
supplies the lookup key (Frequency, ClickDuration, or geometric mean of Start/StopFrequency). A new
calibration mode therefore requires coordinated edits in `Engine`, `apply_calibration`, and the
subclass constant.

**Error identifiers** follow `stimgen:Class:Reason`. `StimPlayer.format_gui_error_message_` maps
known identifiers to user-facing guidance — a new user-triggerable error should get a case there.

**Serialization.** `toStruct`/`fromStruct` persist only the properties listed in the instance's
`UserProperties` string array, plus the core base-class set. A subclass property missing from
`UserProperties` will not survive a save/load round-trip.

**Logging.** `stimgen.util.vprintf(level, [red], msg, ...)`, gated by the global `GVerbosity`
(-1 log-only, 0 critical, 1 info, 2 debug, 3 verbose). Writes a daily log under
`fullfile(tempdir,'stimgen_error_logs')`. It accepts an `MException` directly and expands the
stack. Deliberately standalone, but shares the `GVerbosity` global with the host.

## File formats

- `.esgc` — calibration data (`Engine.save`/`Engine.load`). Legacy `.sgc` is not supported.
- `.spl` — stimulus banks (`StimPlayer.save_bank`/`load_bank`).
- `.eprot` — host protocol files; loaded only through `HardwareHost.loadProtocol`.

## Hardware parameter contract

`StimPlayer` resolves these names from the host at Run time and disables hardware playback if any
are missing (falling back to speaker preview): `BufferData_0/1`, `BufferSize_0/1`,
`x_Trigger_0/1`. These match the `StimGenCircuit.rcx` RPvds circuit shipped with EPsych.

## Documentation

`documentation/` holds per-class guides; `stimgen_overview.md` is the entry point. Keep them in
sync when changing public behavior.
