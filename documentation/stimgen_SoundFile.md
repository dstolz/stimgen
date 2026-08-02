# stimgen.SoundFile

Playback of pregenerated sound files — vocalizations, phonemes, natural scenes — as a first-class
`stimgen.StimType`.

Every other stimulus class synthesizes its waveform from parameters. `SoundFile` instead owns a
**catalog** of sound files and presents them the same way `stimgen.Tone` presents a vector of
frequencies: `FileIndex` is a vectorizable property, so it becomes a variant axis and participates
in the ordinary Serial / ShuffleUniform / ShuffleLeastUsed selection machinery.

```matlab
s = stimgen.SoundFile;
s.add_folder('C:\vocalizations');   % 8 .wav files
s.select_all;                        % FileIndex = 1:8  -> 8 variants
s.SoundLevel = [50 60 70];           % crosses to 24 variants
s.VariantSelectionMode = "ShuffleLeastUsed";
s.catalog_table
```

## The catalog

`Catalog` is a scalar struct of parallel `1×N` arrays:

| Field | Type | Meaning |
| --- | --- | --- |
| `Label` | `string` | user-facing name, unique within the catalog |
| `Path` | `string` | absolute path to the source file |
| `SourceFs` | `double` | native sample rate, Hz |
| `NativeSamples` | `double` | length in source samples |
| `NChannels` | `double` | channels in the source |
| `Embedded` | `logical` | true when samples are stored in the object |
| `Data` | `cell` | embedded samples at `SourceFs`, `[]` when on disk |

It is deliberately a *scalar* struct rather than parallel top-level properties. A `(1,:) string` of
paths would be picked up by `get_variant_source_values_` as a variant axis of its own, and would
break the generated GUI's `char(obj.(propName))` text branch. A scalar struct is invisible to both.

`Catalog` is absent from `propMeta`, so no widget is generated for it, and present in
`UserProperties`, so it survives `toStruct`/`fromStruct` and `StimPlayer.save_bank`. It is listed
**first** in `UserProperties` because `load_bank` restores those properties in order and each
assignment triggers a regeneration — the catalog has to exist before `FileIndex` is restored.

### Managing the catalog

```matlab
s.add_files("C:\sounds\usv_a.wav")            % one or many paths
s.add_files(paths, ["low" "mid" "high"])      % with explicit labels
s.add_folder('C:\sounds')                     % default pattern "*.wav"
s.add_folder('C:\sounds', ["*.wav" "*.flac"])
s.remove_files("usv_b")
s.set_label(3, "attack_call")
s.select_all                                  % FileIndex = 1:NFiles
```

Labels default to the file name without its extension, made unique with `_2`, `_3`, … on collision.
**Removing entries renumbers the rest**, so `FileIndex` is clamped to the new catalog size.

### Storing on disk vs. embedded

By default an entry is a reference to a file on disk — banks stay small, and editing the source
file is picked up automatically (the waveform cache is keyed on modification time).

```matlab
s.embed        % all entries: samples stored in the object
s.embed(1:3)
s.unembed(1)   % back to a disk reference
```

Embedding stores the samples at their native rate and channel count, so `Fs` and `Channel` still
work afterwards. An embedded bank is self-contained: `.spl` files are `-v7` MAT, so the samples
round-trip and the bank plays on a machine that has never seen the original files. `unembed` errors
rather than discarding samples when the original file is missing.

## Identification

The question "which sound just played" is answerable three ways, and one resolver — `find_file` —
accepts all of them interchangeably (case-insensitive; file names match with or without extension):

```matlab
s.find_file(3)              % index
s.find_file("attack_call")  % label
s.find_file("usv_b.wav")    % file name
s.file_info("attack_call")  % struct: Index, Label, FileName, Path, Duration, ...
s.catalog_table             % the whole catalog as a table
```

Read-only properties report the active variant without disturbing it — `selected_value` reselects
when called outside a locked update cycle, which would desynchronize a reported index from the
sound that was actually played:

```matlab
s.NFiles, s.Labels, s.FileNames
s.CurrentIndex, s.CurrentLabel, s.CurrentFileName
```

`current_parameter_summary` leads with the same identity, which is what `StimPlayer` prints above
the signal plot:

```
File 3/8: attack_call (usv_c.wav), Sound Level=60.0 dB SPL
```

## Duration is derived

`Duration` is slaved to the selected file, so `Time`, `N`, and `Signal` always agree and the player's
signal plot never sees mismatched `XData`/`YData`. It is removed from `propMeta` and is not offered
as an editable field.

Because `Duration` is `SetObservable`, `update_signal` writes it behind a guard flag that suppresses
the property listener for that one write — otherwise it would re-enter `update_signal`.

Two consequences worth knowing:

- Variants with different files have different durations. If your paradigm needs a fixed trial
  window, set `StimPlay.ISI` to accommodate the longest sound.
- `apply_gate` has no length check of its own, so a window longer than the sound raises
  `stimgen:SoundFile:WindowTooLong` before it can index out of range.

## Sample rate and channels

Files are resampled to `Fs` on load. The default `Fs` is 97656.25 Hz (the TDT rate), so the rate
ratio is generally not a small rational — `stimgen.util.read_audio` therefore uses `resample`'s
non-uniform form (source time vector plus an output rate) rather than `rat` plus `resample(x,p,q)`.

`Channel` selects one channel: `0` averages all channels to mono, `n` takes channel `n`. It is
vectorizable, so `Channel = [1 2]` presents left and right as separate variants.

Reading and resampling happen on **every** `update_signal`, which fires on every property change and
every variant step during timed playback. Results are cached (keyed on path, modification time,
channel, and target rate; capped at 64 entries). Assigning `Catalog` clears the cache so entries
never outlive the data they describe.

## Calibration

Spectrotemporally complex sounds have no single LUT lookup key the way a tone has `Frequency`.
`CalibrationMode` selects the strategy:

| Mode | Equalization | Level anchored to | Use when |
| --- | --- | --- | --- |
| `"Filtered"` (default) | whole-spectrum FIR from `CalibrationData.filter`, group-delay compensated | tone LUT at `Engine.ReferenceFrequency` | broadband material on an uncorrected speaker — flattens the transfer function first, which is what makes a single anchor valid |
| `"Direct"` | none | tone LUT at `AnchorFrequency`, or the waveform's spectral centroid when `AnchorFrequency = 0` | the recording is already equalized, or its native spectrum matters more than a flat response |
| `"None"` | none | — | no calibration voltage applied; normalized signal only |

`CalibrationType` is a `Constant` and cannot vary per instance, so `SoundFile` overrides
`apply_calibration` instead. Nothing in `stimgen.calibration` changes: both modes reach the tone LUT
through the existing `compute_adjusted_voltage("filter", value, level)`, which already substitutes
`ReferenceFrequency` when `value` is not finite.

`"Filtered"` with a calibration that has no equalizer raises `stimgen:SoundFile:NoEqualizer` — run
`Engine.design_filter` during calibration, or switch to `"Direct"`.

### Level reference

`Normalization` is also a `Constant`, so `LevelReference` selects it per instance via an
`apply_normalization` override:

- `"rms"` (default) — `SoundLevel` means dB SPL re: RMS. Correct for natural sounds, where peak
  level is a poor description of loudness.
- `"peak"` — `SoundLevel` is peak-referenced, matching how `absmax` classes behave.

RMS referencing makes the crest factor the binding constraint on output voltage. The base class only
warns when the scaling voltage itself exceeds 10 V, which misses the real failure: a vocalization
with a crest factor of 10 clips while its RMS-derived voltage is still small. `SoundFile` checks the
actual peak and raises `stimgen:SoundFile:VoltageOutOfRange` with both numbers.

Note that `"None"` leaves an RMS-normalized signal whose peak may exceed 1. That is fine for
`play()` (which rescales for preview) but is not a calibrated hardware level.

## GUI

`SoundFile` appears in the `StimPlayer` type dropdown automatically —
`stimgen.StimType.list()` globs `*.m` in `+stimgen/`. (This is also why `SoundFile` must be a loose
`.m` file rather than an `@SoundFile/` class folder, which the glob would not see.)

Its parameter panel adds two action buttons, using the `'button'` widget type introduced for this
class:

| propMeta field | Effect |
| --- | --- |
| `BrowseFiles` | multi-select file dialog, then `add_files` + `select_all` |
| `UseAllFiles` | `select_all` |

A `'button'` entry is an action, not a property: its field name is only a widget `Tag`, and no value
is read from or written to the object. Declare one with `widget`, `text` (caption), and `callback`
(the name of a public no-argument method):

```matlab
m.BrowseFiles = struct('label','Sound Files','widget','button', ...
                       'text','Browse...','callback','browse_files', ...
                       'group','Waveform','order',1);
```

Both GUI generators support it — `@StimType/create_gui.m` and
`@StimPlayer/on_bank_selection_changed.m`. In `StimPlayer` the panel is rebuilt after the callback
returns, because an action can change both the parameter values and the number of variant
combinations.

`FileIndex`, `Channel`, and `AnchorFrequency` are `double` and vectorizable, so they render as
expression text fields — type `1:8` into File Index directly.

## Errors

All are mapped to user-facing guidance by `StimPlayer.format_gui_error_message_`.

| Identifier | Cause |
| --- | --- |
| `stimgen:SoundFile:EmptyCatalog` | a selection was requested against an empty catalog |
| `stimgen:SoundFile:FileNotFound` | a referenced file is missing or unreadable |
| `stimgen:SoundFile:IndexOutOfRange` | `FileIndex` exceeds the catalog |
| `stimgen:SoundFile:InvalidChannel` | requested channel not present in the file |
| `stimgen:SoundFile:WindowTooLong` | gate window longer than the sound |
| `stimgen:SoundFile:NoEqualizer` | `"Filtered"` mode with no calibration filter |
| `stimgen:SoundFile:VoltageOutOfRange` | peak output would exceed 10 V |
| `stimgen:SoundFile:UnknownFile` | selection matched no label, file name, or path |
| `stimgen:SoundFile:InvalidCatalog` | catalog fields have inconsistent lengths |

An **empty catalog is never an error** during signal generation: `update_signal` emits
`zeros(1, N)` and returns. `StimPlayer.add_stim` constructs the class and immediately builds its
panel and plot, so a fresh `SoundFile` has to be harmless.

## Related files

- [+stimgen/SoundFile.m](../+stimgen/SoundFile.m)
- [+stimgen/+util/read_audio.m](../+stimgen/+util/read_audio.m)
- [stimgen_StimType.md](stimgen_StimType.md) — the base contract and variant system
- [stimgen_calibration.md](stimgen_calibration.md) — measuring the LUTs and designing the equalizer
