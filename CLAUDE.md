# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A MATLAB toolbox (R2021a+) for auditory stimulus generation, playback, and speaker/microphone
calibration, deliberately kept free of any dependency on a host application. Requires Signal
Processing Toolbox; Audio Toolbox only for sound-card playback/preview.

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
`SweptSine`, `ClickTrain`, `TORC`, `SoundFile`. The base class owns level/duration/gating/Fs, the
variant system, serialization, and GUI generation; subclasses only synthesize a waveform.
`SoundFile` is the exception that reads rather than synthesizes: it owns a catalog of sound files, uses a vectorizable
`FileIndex` as its variant axis, and derives `Duration` from the selected file.

**Playback** — `stimgen.StimPlay` wraps a StimType with reps/ISI/selection order.
`stimgen.StimPlayer` (in `@StimPlayer/`) manages a bank of StimPlay objects, double-buffers audio
into hardware, and triggers from its own MATLAB timer.

**Calibration** — `stimgen.calibration.Engine` (in `+calibration/@Engine/`) does all measurement
math and owns `.esgc` save/load. `stimgen.StimCalibration` is a thin headless wrapper that
delegates every property to an Engine; it exists so `StimType` sees stable property names, and
it is the form a calibration takes once serialized. `stimgen.calibration.CalibrationGui` is the
one interactive front end — `StimCalibration` had a second window of its own, which was removed
so there is a single GUI to maintain.

The engine never draws. Gated by `ShowLivePlots`, it broadcasts a `LiveUpdate` event carrying a
`stimgen.calibration.LiveUpdate` payload for every measurement; `stimgen.calibration.LiveMonitor`
renders that stream, either into its own window or into axes a host GUI supplies (which is how
`CalibrationGui` embeds it). Failures never abort a sweep: MATLAB itself
catches listener errors (warning per notify), `emit_live_` guards payload construction — every
`calibrate_*` treats an error as an aborted run and discards the partial data — and
`LiveMonitor.update` latches its own render errors so a plotting bug is one log line, not a
per-measurement warning storm. `Engine.plot_signal`/`plot_spectrum`/`plot_transfer`/`plot_reset`
remain only as deprecated shims that forward to an attached monitor.

### The two abstract seams — do not break these

`stimgen` never references a host-application type. All hardware coupling goes through:

- `stimgen.HardwareHost` — protocol load, connect/release, `setMode`, `findParameter`,
  `connectionState`, `calibrationAdapter`, and the optional `sampleRate` (concrete, returns
  NaN by default, so a host predating it still satisfies the contract). Consumed by
  `StimPlayer` and `CalibrationGui`.
- `stimgen.calibration.HwAdapter` — `sample_rate()` and `play_and_record(signal)`, plus a concrete
  `record(nSamples)` (silent `play_and_record` by default) that `calibrate_reference` uses so the
  reference step never drives the speaker. Consumed only
  by `Engine`. `WindowsSoundCardAdapter` is the one built-in implementation.

Both are optional at construction; omitting them puts the GUIs in offline mode where speaker
preview still works. New hardware support means a new `HwAdapter` subclass, never an edit inside
`Engine`.

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

**Subclass defaults are prepended to the superclass constructor, never assigned after it.**
`StimType`'s constructor assigns `Name,Value` pairs in order, so whatever comes last wins. A
subclass therefore passes its own defaults ahead of `varargin`:

```matlab
obj = obj@stimgen.StimType('DisplayName', 'Click Train', 'Duration', 1, varargin{:});
```

Assigning `obj.Duration = 1` after the super call instead would silently overwrite a caller's
`stimgen.ClickTrain('Duration', 0.3)`. Names are matched exactly and only publicly settable
properties are accepted; anything else raises rather than being dropped.

**Signal pipeline order is normalize → calibrate → gate**, uniformly across all subclasses.
Calibration must come before gating: `apply_calibration` renormalizes before scaling to the LUT
voltage, which would undo an earlier ramp.

**Variants.** Assigning a vector to a user property expands it into variant combinations, governed
by `VariantCombinationMode` (Cartesian / PairwiseStrict / PairwiseScalarExpand) and
`VariantSelectionMode` (Serial / ShuffleUniform / ShuffleLeastUsed / CustomSelector). The
combination table is cached and invalidated by a signature hash — see
`refresh_variant_cache_if_needed_`.

**Time is seconds in the object, milliseconds in the GUI.** `Duration`, `WindowDuration`,
`ClickDuration`, `OnsetDelay` and `ISI` are stored in seconds and used that way by every signal
computation and by `toStruct`/`fromStruct`. GUIs display and accept milliseconds. The factor is
declared per property in `propMeta` as `'scale', 1000` and read back via
`stimgen.StimType.display_scale(pm)`; `displayValue = propertyValue * scale`. Consequences:

- `label`, `format` and `limits` in `propMeta` are all in *display* units. Vectorizable properties
  render as expression text fields that ignore `format`, so the unit has to be in `label`.
- `build_expression_context_` returns display units, so `evalPropertyExpression` both takes and
  returns milliseconds. Every caller divides by the scale before assigning to the property — that
  single division is the only conversion, so don't add another.
- Time axes (`plot`, `plot_spectrogram`, StimPlayer signal plot, CalibrationGui temporal response)
  are drawn in ms. The CalibrationGui transfer plot keeps click duration in µs, because that axis
  is shared with frequency in Hz.
- A property whose units depend on another property overrides its own `propMeta` entry — see
  `Tone.WindowMethod`, where `WindowDuration` is ms/percent/periods depending on the mode.
  Widgets already on screen were built from the old metadata, so the subclass also implements
  the `on_gui_changed` hook and calls `refresh_gui_widget(prop)` to retitle/rescale the affected
  field. Both generators feed that hook: `create_gui` via `interpret_gui`, `StimPlayer` via
  `set_gui_handles` + `notify_gui_changed`. The hook fires for GUI edits only, so programmatic
  assignment and `fromStruct` are unaffected by it.
- A varying *stored* unit converts in `effective_window_duration_` (called by the `Window`
  getter), never in `update_signal` — that runs repeatedly and an in-place conversion would
  compound on every call.
- A derived time property should be removed from `propMeta` rather than shown read-only (there is no
  read-only widget). `SoundFile` does `base = rmfield(base,'Duration')` because `Duration` is slaved
  to the selected file, and writes it from inside `update_signal` behind a guard flag that
  suppresses the `SetObservable` listener for that one write.

**GUIs are generated, not hand-built.** `create_gui` reads `propMeta()` and builds a label+widget
grid; widget type is inferred from the property's class unless overridden. Subclass `propMeta`
defines its own fields then calls
`stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj))`. A subclass with clean
metadata appears in `StimPlayer` with no player-side changes.

Widget types are `numeric`, `text`, `checkbox`, `dropdown`, and `button`. A `button` entry is an
*action*, not a property: its field name is only a widget `Tag` (it need not name a real property),
and it declares `text` (caption) and `callback` (a public no-argument method on the stimulus
object) — see `SoundFile.BrowseFiles`. Two near-duplicate generators must both learn any new widget
type: `@StimType/create_gui.m` and `@StimPlayer/on_bank_selection_changed.m` (which re-implements
`resolve_widget_type` as a local function because the static is protected). Both wire
`ValueChangedFcn` across the widgets they build, so a widget without that callback — a `uibutton` —
has to be excluded there.

**Tooltip text lives in one JSON file, never in the code.** `+stimgen/tooltips.json` holds every
hover string in the package, in one section per class; `stimgen.util.tooltip(source, key)` is the
only way to read it. Every `propMeta` entry declares its `tooltip` as
`stimgen.util.tooltip(obj, propName)` — one line of plain text applied to both the label and the
widget by both generators, and re-applied by `refresh_gui_widget` (so a property whose metadata
varies, like `Tone.WindowDuration`, swaps tooltip along with label; those cases get one key per
case, e.g. `WindowDuration_Proportional`). A new property needs an entry in the JSON and a lookup
in `propMeta`. Lookup walks the class section then each superclass section, so a subclass overrides
an inherited entry just by declaring the same key — that is how `ClickTrain.Duration` retitles the
base-class text without editing `@StimType/propMeta.m`. GUI code with no stimulus object passes a
section name instead (`stimgen.util.tooltip('StimPlayer','RunBtn')`); `@StimPlayer/create.m`,
`@StimInspector/build_ui_.m` and `+calibration/CalibrationGui.m` all do
this for their own controls and toolbars. An unknown key returns `''` and logs a warning rather
than erroring, so a missing tooltip never blocks a GUI. The file is cached and re-read on change,
so edits take effect without `clear functions`.

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
(-1 log-only, 0 critical, 1 info, 2 debug, 3 verbose, 4 trace). With values `msg` is a printf
format string; with none it is literal text, so `ME.message` and Windows paths survive. It
accepts an `MException` directly. Nothing in the path throws — stimgen logs from inside catch
blocks.

By default it prints to the command window and appends to a daily log under
`fullfile(tempdir,'stimgen_error_logs')`. A host that has its own logger installs a
`stimgen.LogSink` (`stimgen.util.logSink(sink)`), after which every message is forwarded and
**stimgen writes nothing of its own** — one log per session instead of two. This is the third
abstract seam, alongside `HardwareHost` and `HwAdapter`, and the same rule applies: new `LogSink`
methods must be concrete with a safe default (`isEnabled` already is), or every host's subclass
becomes unconstructable. See `documentation/stimgen_logging.md`.

## File formats

- `.esgc` — calibration data (`Engine.save`/`Engine.load`). Legacy `.sgc` is not supported.
- `.spl` — stimulus banks (`StimPlayer.save_bank`/`load_bank`).
- `.eprot` — host protocol files; loaded only through `HardwareHost.loadProtocol`.
- `+stimgen/tooltips.json` — the tooltip catalog, read only through `stimgen.util.tooltip`. Ships
  with the package; a copy of `+stimgen/` without it loses all hover help.

## Hardware parameter contract

`StimPlayer` resolves these names from the host at Run time and disables hardware playback if any
are missing (falling back to speaker preview): `BufferData_0/1`, `BufferSize_0/1`,
`x_Trigger_0/1`. These match the `StimGenCircuit.rcx` RPvds circuit template that a host
application's hardware circuit must expose to support hardware-triggered playback.

## Documentation

`documentation/` holds per-class guides; `stimgen_overview.md` is the entry point. Keep them in
sync when changing public behavior.
