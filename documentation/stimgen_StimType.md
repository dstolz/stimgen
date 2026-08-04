# stimgen.StimType

`stimgen.StimType` is the abstract base class for editable stimulus objects in the `stimgen` package. This is a developer reference for subclassing and integration; for tool usage start at [stimgen_overview.md](stimgen_overview.md).

Source class:

- [+stimgen/@StimType/StimType.m](../../+stimgen/@StimType/StimType.m)

Concrete subclasses: `Tone`, `Noise`, `AMnoise`, `AttackModNoise`, `FMtone`, `ClickTrain`, `SweptSine` (loose `.m` files in `+stimgen/`). Subclasses define the constants `CalibrationType` and `Normalization`, and the `IsMultiObj` property that tells wrappers whether the object expands into multiple presentable stimuli.

## What The Base Class Provides

- shared stimulus properties (`SoundLevel`, `Duration`, `Fs`, windowing controls)
- waveform storage (`Signal`)
- calibration integration (`ApplyCalibration`, `Calibration`)
- plotting and preview playback helpers
- serialization helpers (`toStruct`, `fromStruct`)
- GUI-generation and property metadata hooks

Subclasses implement `update_signal` and set class constants for calibration and normalization behavior.

## Construction

Every subclass constructor takes `Name,Value` pairs and assigns them to public properties:

```matlab
t = stimgen.Tone('Fs', 48000, 'Frequency', 4000, 'Duration', 0.05);
n = stimgen.Noise('HighPass', 500, 'LowPass', 16000, 'Calibration', cal);
```

Rules the base constructor enforces, all of them fail-fast:

- Arguments come in pairs. An odd count raises `stimgen:StimType:badConstructorArgs`, so `stimgen.Tone('Fs')` cannot quietly do nothing.
- Names are matched **exactly**. `'fs'` does not find `Fs`.
- Only publicly settable properties can be assigned. Unknown names, protected properties (`Signal`), and constants (`CalibrationType`) all raise `stimgen:StimType:unknownProperty`.
- There is no positional form. `stimgen.FMtone(48000, cal)` raises rather than being ignored.

Values are assigned before listeners are attached, so construction does not regenerate the waveform once per argument. Call `update_signal` when you want the signal.

### Subclass defaults must be prepended, not assigned afterwards

A subclass that wants its own defaults passes them to the superclass constructor **ahead of** `varargin`, so a caller's value is applied last and wins:

```matlab
function obj = ClickTrain(varargin)
    obj = obj@stimgen.StimType( ...
        'DisplayName', 'Click Train', ...
        'UserProperties', [...], ...
        'Duration', 1, ...
        'ApplyWindow', false, ...
        varargin{:});
end
```

Assigning those defaults *after* the superclass call — the older pattern — silently overwrites whatever the caller asked for. That is a quiet failure with no error to follow, so it is worth checking whenever a new subclass is added.

## Signal Update Lifecycle

The base class listens to observable property changes and recomputes waveform data.

Typical subclass update flow:

1. generate raw signal in `update_signal`
2. normalize (`apply_normalization`)
3. apply calibration (`apply_calibration`)
4. apply gating/windowing (`apply_gate`)

All concrete subclasses follow this order. Calibration must precede gating: `apply_calibration` renormalizes the waveform before scaling it to the voltage returned by the calibration lookup, so any onset/offset ramp applied earlier would be undone.

`refresh_plot_if_valid` keeps open plot handles synchronized.

## Variant Selection

Vectorized user properties (for example a `Tone` with `Frequency = [1000 2000 4000]`) define a set of stimulus *variants*. The class has explicit variant-control properties and cache management:

- `VariantSelectionMode`
- `VariantCombinationMode`
- `VariantSelectorClass`
- `VariantSelectorConfig`
- `VariantReselectOnUpdate`

Supporting methods include:

- `build_variant_combinations_`
- `refresh_variant_cache_if_needed_`
- `select_variant_index_`
- `begin_variant_cycle_` / `end_variant_cycle_`
- `apply_variant_index_and_update_`
- `set_variant_index` / `step_variant`
- `get_variant_info`

This enables deterministic, shuffled, and custom selector-driven traversal of vectorized property combinations.

## Expression Evaluation

Stimulus property expressions are evaluated through guarded helper methods:

- `evalPropertyExpression`
- `evaluate_property_expression_`
- `build_expression_context_`
- `rewrite_qualified_property_refs_`

These are used by editing workflows that support computed property values.

## GUI Integration

`create_gui` builds widget controls from metadata (`propMeta`) and property definitions.

Recent UI sync behavior includes `update_handle_value`, which keeps control state aligned after property updates and variant changes.

### Hover help

A `propMeta` entry may declare `tooltip`, a single line of plain text applied to
both the property's label and its widget. The text itself is never written in
the class — it is looked up in the one tooltip catalog, `+stimgen/tooltips.json`:

```matlab
m.Frequency = struct('label','Frequency','format','%.1f Hz','limits',[100 40000], ...
                     'tooltip', stimgen.util.tooltip(obj, 'Frequency'));
```

```json
"Tone": {
  "Frequency": "Tone frequency in Hz. Also the key used to look up the calibrated level. ..."
}
```

`stimgen.util.tooltip(source, key)` searches the section named after the
object's class, then each superclass section in turn, so `Tone.Frequency` comes
from the `Tone` section and `Tone.Duration` from `StimType`. A subclass
overrides an inherited entry by declaring the same key: `ClickTrain` retitles
`Duration` as the length of the click train that way, without touching the
`propMeta` call in the base class. GUI code with no stimulus object passes a
section name instead — `stimgen.util.tooltip('StimPlayer','RunBtn')` — which is
how the player, the inspector and the calibration GUIs get the hover text for
their own controls. An unknown key returns `''` and logs a warning through
`stimgen.util.vprintf`, so a missing tooltip is noticed but never stops a GUI
from building. The catalog is cached and re-read whenever the file changes, so
editing `tooltips.json` takes effect without clearing anything.

Both builders apply the text — `create_gui` and
`stimgen.StimPlayer.on_bank_selection_changed` — so a subclass declares the
lookup once and it shows up in the standalone panel and the bank editor alike.
`refresh_gui_widget` re-applies it along with the label, which matters for a
property whose metadata varies: `Tone.WindowDuration` swaps in a different
tooltip under each `WindowMethod`, using one catalog key per case
(`WindowDuration_Proportional`, `WindowDuration_Periods`). Every base and
subclass property carries one; keep new ones to a line, saying what the
parameter does plus any non-obvious consequence (which properties are
vectorizable, what a value of 0 means, which other setting overrides it).

### Display units

Time properties are stored in **seconds** but shown in **milliseconds**. The
conversion is declared per property in `propMeta` and applied only at the GUI
boundary:

```matlab
m.Duration = struct('label','Duration (ms)','format','%.1f ms', ...
                    'limits',[1 10000],'scale',1000);
```

`stimgen.StimType.display_scale(pm)` returns that factor (1 when absent), and
the relation is always:

```text
displayValue = propertyValue * scale
```

Rules that follow from this:

- `label`, `format` and `limits` are all in **display** units. Vectorizable
  properties render as expression text fields, which ignore `format` entirely,
  so the unit must appear in `label` to be visible.
- `build_expression_context_` also returns display units, so an expression
  typed into a millisecond field (`Duration/20`) stays in milliseconds
  end-to-end. `evalPropertyExpression` therefore returns display units and its
  callers divide by the scale before assigning.
- Nothing downstream of assignment changes: `Duration`, `WindowDuration`,
  `ClickDuration` and `OnsetDelay` remain seconds in the object, in
  `toStruct`/`fromStruct`, and in every signal computation.
- Time axes on `plot` and `plot_spectrogram` are drawn in ms to match.

A property whose meaning depends on another property can vary its own scale.
`Tone.WindowMethod` does this: `WindowDuration` is ms under `"Duration"`, but a
percentage or a period count under `"Proportional"` / `"#Periods"`, so
`Tone.propMeta` overrides the entry (dropping `scale`) for those modes.

### GUI change hooks

A `propMeta` entry that varies is only half the job: a widget already on screen
was built from the *previous* metadata. The protected hook

```matlab
on_gui_changed(obj, propName, value)
```

runs after a GUI-driven property assignment and before the signal is rebuilt, and
is where a subclass repairs the widgets that the edit invalidated. Inside it, call

```matlab
obj.refresh_gui_widget('WindowDuration')
```

to re-apply the current `propMeta` entry to that property's live widget — label
caption, tooltip, numeric format and limits, and the value in display units. It is
a no-op when no widget exists, so the hook is safe to reach from headless code.

Both GUI builders participate:

- `create_gui` registers its widgets in `GUIHandles` itself and calls the hook
  from `interpret_gui`.
- A host GUI that builds its own widgets from `propMeta` registers them with
  `set_gui_handles(handleStruct)` and calls `notify_gui_changed(propName, value)`
  after it assigns the property. `stimgen.StimPlayer.on_bank_selection_changed`
  does both, which is why `Tone`'s hook works identically in the bank editor.
  Only one panel can be registered at a time; the most recent caller wins.

Each builder stores the property's label handle in the widget's
`UserData.labelHandle`, along with a `UserData.labelFormat` caption template
(`'%s'` for `create_gui`, `'%s:'` for the StimPlayer panel), so
`refresh_gui_widget` can retitle the label in either layout.

Note the hook fires for GUI edits only. Programmatic assignment stays untouched,
which keeps `fromStruct` from clobbering a loaded value depending on the order in
which properties happen to be restored.

### Unit seams below the GUI

Display scale only governs presentation. When a property's *stored* unit varies,
the conversion belongs in a computation seam instead — never in `update_signal`,
which runs repeatedly and would compound the conversion each time. `Window` calls
the protected

```matlab
d = effective_window_duration_(obj)   % total onset+offset gate length, seconds
```

whose base implementation returns `WindowDuration` unchanged. `Tone` overrides it
to divide by 100 and multiply by `Duration` (`"Proportional"`), or to convert a
per-ramp period count into seconds (`"#Periods"`; doubled, since `apply_gate`
splits the window in half between onset and offset).

### Parameter grouping

Each `propMeta` entry may also declare `group` (`'Waveform'` | `'Level'` |
`'Timing'` | `'Variant'`, default `'Waveform'`) and `order` (a numeric sort
key within that group, default last-and-by-declaration-order).
`stimgen.StimType.group_prop_meta(meta)` buckets a `propMeta()` struct into
`{groupName, propNames}` sections in that fixed group order; `create_gui`
flattens the sections into row order, and `StimPlayer`'s bank editor
(`on_bank_selection_changed`) uses them directly as visual sections with
headers. This is how a subclass keeps related controls adjacent even when
one lives in the subclass's own properties and the others are inherited —
`Tone.WindowMethod` tags itself `'group','Timing','order',20` so it renders
between the base class's `Duration` (order 10) and `WindowDuration`
(order 30) instead of drifting off into the `Waveform` section.

## Common Public Methods

- `plot`, `plot_spectrogram`, `play`
- `selected_value`
- `current_parameter_summary`
- `toStruct`, `fromStruct`
- `list` (discover available stimulus classes)

## Minimal Example

```matlab
t = stimgen.Tone('Frequency', 4000, 'Duration', 0.1, 'SoundLevel', 60);
t.update_signal();
t.plot();
```

or equivalently, assigning after construction:

```matlab
t = stimgen.Tone;
t.Frequency = 4000;
t.Duration = 0.1;
t.SoundLevel = 60;
t.update_signal();
t.plot();
```

Variant stepping example:

```matlab
t.Frequency = [1000 2000 4000];   % three variants
info = t.set_variant_index(1);
info = t.step_variant(1);
```

## Related Documentation

- [stimgen_overview.md](stimgen_overview.md) — package orientation
- [stimgen_StimCalibration.md](stimgen_StimCalibration.md) — how stimuli consume calibration
- [stimgen_calibration.md](stimgen_calibration.md) — calibration workflow
