# `stimgen.StimPlayer`

![StimPlayer window: waveform plot at top, stimulus bank list on the left with Tone and Noise entries, and the parameter editor panel on the right](images/StimPlayer.png)

`stimgen.StimPlayer` is a standalone stimulus-bank editor and playback tool
for the `stimgen` package.

The screenshot above shows the three areas described in [UI workflow](#ui-workflow): the signal plot for the selected bank entry (top), the stimulus bank panel with two items (bottom left), and the parameter editor panel for the selected `Noise` stimulus (right).

It is designed for cases where you want to assemble a reusable bank of
stimuli, edit one item at a time, preview signals locally, and optionally
drive the stimgen RPvds playback circuit — all outside a full experiment
session.

## What this class manages

`StimPlayer` owns a bank of `stimgen.StimPlay` objects. Each bank item wraps
one stimulus definition, tracks repetition counts, and exposes the currently
selected waveform.

At the `StimPlayer` level, the class adds:

- a bank list for adding, removing, and renaming stimulus entries
- a parameter editor that rebuilds itself for the selected stimulus type
- a shared playback schedule across bank items using a global `ISI` range
- a single sample rate (`Fs`) for the whole bank
- optional hardware-backed playback through a protocol's hardware interfaces
- save/load support for `.spl` bank files

Use `StimPlayer` when you want a lightweight stimulus workstation rather than
a full experiment session.

## Basic usage

Create the GUI without hardware (speaker preview only):

```matlab
sp = stimgen.StimPlayer;
```

Create it with a `stimgen.HardwareHost` so the `Run` button can write buffers
and trigger hardware playback:

```matlab
sp = stimgen.StimPlayer(HOST);   % a stimgen.HardwareHost implementation
```

A host application's `HardwareHost` implementation typically wraps a protocol, e.g.:

```matlab
sp = stimgen.StimPlayer(host);   % host already has a protocol loaded/connected
```

A protocol can also be loaded later from the GUI's **File** menu, which
delegates to the host. `StimPlayer` itself holds no runtime or protocol state:
it asks the host to connect the interfaces and put them in Preview mode, then
resolves buffer/trigger parameters through `host.findParameter`. It does not
use the main experiment timer or session runtime.

## UI workflow

The `create()` method builds a single-window UI with three main areas.

### Signal plot

The top panel shows the waveform for the currently selected bank entry.

`update_signal_plot()` refreshes that plot by:

- preferring the listbox selection when the GUI is idle
- falling back to `CurrentSPObj` during active playback
- lazily calling `stimObj.update_signal()` when the signal has not been
  generated yet

If no valid bank entry is available, the plot is cleared to `NaN` data.

`update_signal_plot()` is the single funnel for "the displayed stimulus
changed" — bank selection, parameter edits, combination stepping and
`Play All` all pass through it — so it is also where the stimulus inspector
is refreshed. A new code path that changes what should be on screen should
call it rather than updating the plot itself.

### Stimulus inspector

The **Inspect Stimulus** toolbar button (also **File > Inspect Stimulus**,
`Ctrl+I`) opens [`stimgen.StimInspector`](stimgen_StimInspector.md) on the
selected bank item, or raises the existing window if one is already open —
there is only ever one inspector per player.

It is a read-only detail view: waveform and envelope, magnitude spectrum,
spectrogram, harmonic distortion, and a table of measured signal properties.
It stays in sync with the bank because `open_stim_inspector()` attaches it
with a *source provider* (`inspector_source_`) rather than a stimulus handle,
so every refresh re-resolves the current selection instead of holding an
object that may since have been removed.

The inspector is deliberately left enabled during playback — it does not
write to the stimulus — and is closed with the player.

### All combinations of one item

**Tools > Show All Combinations...** (`Ctrl+G`, or the grid button beside
Inspect Stimulus) calls `show_all_combinations()`. It opens a
[`stimgen.CombinationViewer`](stimgen_CombinationViewer.md) that generates
every variant combination of the selected item and draws them side by side:
as tiles, overlaid, or stacked, as waveforms or spectra. A table lists the
parameter values, peak and rms of each combination, and any combination can
be opened from there in a `StimInspector`.

Unlike the inspector, each press opens a **new** window, so two items can be
compared. The viewer works on copies, so the bank item keeps its active
combination. Its Refresh button regenerates from the bank item and picks up
later edits. The command is disabled during a session (by
`lock_bank_controls_`, and refused by the method itself). Generating a large
family runs on the playback timer's thread, so it waits until the session
ends. Open viewers close with the player.

### Capturing through a microphone

**Capture Selected Stimulus** (Tools menu, `Ctrl+M`, or the microphone toolbar
button) plays the selected combination through hardware that records while it
plays, and opens the recording in a second inspector — the *capture
inspector* — that reads it as sound: the waveform in pascals, every spectrum
and level in dB SPL, sound-level-meter readouts, band levels, the noise floor
the recording sat on, and the level the stimulus asked for against the level
that came back. See [Recordings](stimgen_StimInspector.md#recordings-sound-pressure-and-db-spl)
in the inspector guide for what each view shows.

```matlab
sp = stimgen.StimPlayer;
sp.open_stim(stimgen.Tone('Frequency', 4000, 'SoundLevel', 70));
sp.load_calibration_('rigB.esgc');       % or Calibration > Load Calibration
sp.CaptureAdapter = stimgen.calibration.WindowsSoundCardAdapter(SampleRate=96000);
rec = sp.capture_stim;                   % or press the microphone button
```

What a capture does, in order:

1. **Finds the route.** `CaptureAdapter` — a `stimgen.calibration.HwAdapter`,
   or a function returning one, called at each capture so a host can build it
   from its device settings at that moment — else the host's calibration
   adapter, the same one hardware preview uses. With neither, the capture
   controls are disabled and the button's tooltip says why.
2. **Takes the waveform as it will be presented.** The generated waveform,
   verbatim, in volts — what a hardware Run plays, not the normalized copy
   speaker preview auditions. When the bank's sample rate differs from the
   hardware's, the combination is regenerated natively at the hardware rate on
   a copy pinned to the same combination; the bank keeps its own rate and
   signals. (A noise stimulus's copy is a fresh draw from the same parameters.)
3. **Takes the scale.** The stimulus's own calibration, else the one loaded
   into the player — and only one with measured tables, since an empty
   calibration carries a placeholder 1 V/Pa. Its microphone sensitivity is
   copied into the recording, and its AC-coupling and spectral-window settings
   are used for the capture, so a record is conditioned and measured the way
   the calibration's own measurements were. Without one, the capture still
   runs and the recording opens in volts, with a warning saying why.
4. **Plays and records** through `Engine.play_and_capture`: `CapturePreDelay`
   of silence first (the noise floor is measured over it), the stimulus,
   `CapturePostDelay` of silence after (it bounds the search for the response
   delay, so it must be longer than the rig's round trip), repeated
   `CaptureRepeats` times with each acquisition aligned on its own delay.
5. **Wraps and shows the result.** `stimgen.CapturedSignal.from_capture` turns
   the acquisition into a recording that carries its noise floor, its
   sensitivity, what the stimulus asked for, and every warning that qualifies
   it. It is left in `LastCapture` and shown in the capture inspector.

**Tools > Capture Settings...** sets the lead-in, tail and repeats, in
milliseconds. They are remembered in the `StimPlayer` preference group,
because the round trip the tail has to cover is a property of the rig, not of
one sitting; they are written only from the dialog, never from the property
setters.

The capture inspector is one window per player, reused by each new capture
and kept apart from the inspector that follows the bank selection: that one
shows what will be played, this one what came back. It is closed with the
player. Capture is refused while a session holds the hardware — running or
paused — and only one runs at a time.

### Stimulus bank panel

The left panel manages the bank itself.

Important controls:

- `StimTypeDD`: chooses which concrete `stimgen.StimType` subclass to add
- `Add Stim`: instantiates the selected stimulus type and wraps it in a new
  `stimgen.StimPlay`
- `Duplicate`: adds a copy of the currently selected bank item directly below
  it — see below
- `Remove`: deletes the currently selected bank item
- `BankList`: selects the item shown in the editor panel
- `RepsField`: updates the repetition target for the selected bank item
- `ISIField`: edits the global inter-stimulus interval range used by the
  player timer, entered in **milliseconds** (`StimPlayer.ISI` itself stays in
  seconds)
- `FsField`: edits the sample rate, in Hz, used to generate every stimulus in
  the bank — see [Sample rate](#sample-rate)
- `OrderDD`: chooses the cross-item playback order, `Serial` or `Shuffle`
- `OutputDD`: chooses where `Play` and `Play All` audition the stimulus —
  see [Preview output and calibration status](#preview-output-and-calibration-status)

`RepsField`, `ISIField`, `FsField`, `OrderDD`, and `OutputDD` can be hidden by an
interfacing application — see
[Hiding session controls](#hiding-session-controls-host-takeover).

When you add a new item, `add_stim()` creates the stimulus object at the bank's
current sample rate, constructs a `StimPlay`, assigns a default name such as
`Tone_1`, and then selects it so the editor panel is rebuilt immediately. A
calibration loaded earlier from the Calibration menu is applied to the new item
as well, so the whole bank always shares one calibration state.

`duplicate_stim()` copies the selected item into a new one inserted directly
below it, named `<name>_copy` (then `_copy2`, `_copy3`, … if taken) and
selected so it can be edited straight away. It carries the same settings a
saved bank does — the base `StimType` properties plus every `UserProperties`
entry — along with the item's `Reps`, `ISI` and selection order, and opens on
the variant combination the source was showing. The copy is a newly constructed
object given those values rather than a `copy()` of the original, which would
share the original's property listeners and editor widgets. The calibration
object is shared, not cloned, keeping the bank on one calibration state.
Presentation counters start from zero. Like a `.spl` round trip, anything not
listed in `UserProperties` (for example a `CapturedSignal`'s recorded waveform)
is not carried over.

#### Remembered settings per stimulus type

A new item does not start from the class defaults if you have already tuned one
of its type. Every parameter edit that takes effect in the editor panel stores
that stimulus's settings — level, duration, window, variant policy and every
`UserProperties` entry — under its class in the `StimPlayer` preference group
(`StimSettings`, one struct per class). `add_stim()` applies them to the new
object through `apply_remembered_settings_`, so a second `Tone` opens as the
first was left, and it does so in later sessions too.

- The whole set is stored at each edit, not only the property changed, because
  some properties change the meaning of others (`Tone.WindowMethod` sets the
  units of `WindowDuration`); the most recently edited stimulus of a type is
  what the next one copies.
- Only GUI edits are remembered. Programmatic assignment, `open_stim`,
  `load_bank` and `duplicate_stim` neither write nor read the preference, so a
  script or a loaded bank never rewrites what the operator chose.
- Not remembered: the sample rate (the bank owns it), `Reps`/`ISI` (bank-level
  presentation settings) and `SoundFile`'s `Catalog` and `FileIndex`, which
  describe a file list a new item does not have.
- Each property is applied on its own inside a `try`, so a stored value that no
  longer validates costs that property its memory, not the new item its other
  settings. A missing or unreadable preference is the same as none.
- To return to class defaults: `rmpref('StimPlayer','StimSettings')`.

### Sample rate

`stimgen.StimType` carries its own `Fs`, but `StimPlayer` holds **one rate for
the whole bank** — the hardware plays every item through the same converter, so
a per-item rate would have no meaning at Run time. The `Sample Rate` field in
the bank panel shows it, and `StimPlayer.Fs` is the same value programmatically:

```matlab
sp.Fs = 48000;        % rewrites Fs on every bank item and rebuilds their signals
```

Three things keep that single value true:

- `add_stim()` constructs new stimuli with `'Fs', obj.Fs`
- `load_bank()` adopts the first loaded item's rate and re-applies it to the
  rest, reporting in the status line when a bank held mixed rates
- `Run` calls `adopt_host_fs_()`, which takes the rate from
  `HardwareHost.sampleRate()` when the attached host can report one. A host
  that returns `NaN` — the default — leaves the operator's value in place.

A rate change moves Nyquist, so some stimuli cannot survive one: a noise band
above the new Nyquist, or a click shorter than one sample. Assigning `Fs`
therefore applies the rate to every item, rebuilds each signal, and if any item
fails, **rolls the whole bank back** and throws
`stimgen:StimPlayer:SampleRateNotSupported` naming the items and why. The bank
never sits at a rate its signals were not generated at. Bring the offending
stimulus's parameters inside the new range first, then set the rate again.

The rebuild is deliberately run twice per item: assigning `StimType.Fs`
regenerates the signal inside a `PostSet` listener, where MATLAB downgrades an
error to a warning and keeps the stale signal, so `apply_fs_to_bank_()` calls
`update_signal` again where the failure is catchable. This is the same
assign-then-rebuild pattern the parameter editor uses in `set_prop_`.

### Parameter editor panel

The right panel is rebuilt every time the bank selection changes.

`on_bank_selection_changed()` reads metadata from `stimObj.get_prop_meta()`
and buckets properties into sections via
`stimgen.StimType.group_prop_meta()`, in this fixed order:

- `Waveform`: stimulus-specific properties such as frequency or filter
  bounds — the default section for any property that doesn't declare one
- `Level`: `SoundLevel` plus `ApplyCalibration`
- `Timing`: duration and window settings, including any subclass property
  that reinterprets them (e.g. `Tone.WindowMethod`, which is tagged
  `'group', 'Timing'` so it renders next to `WindowDuration` instead of
  drifting into `Waveform`)
- `Variant`: variant selection/combination policy properties

A property opts into a section (and its position within it) via the
optional `group`/`order` fields in its `propMeta()` entry — see
[stimgen_StimType.md](stimgen_StimType.md#display-units). Properties
without a `group` default to `Waveform`, and without an `order` sort after
explicitly ordered ones in declaration order.

Timing fields are entered and displayed in **milliseconds**, and the signal
plot's time axis is in ms; the underlying `StimType` properties stay in
seconds. The conversion comes from the `scale` field in `propMeta`.

Every parameter row, label and widget alike, carries hover help taken from the
`tooltip` field of its `propMeta()` entry, so the explanation is keyed to the
stimulus class rather than to the player — see
[Hover help](stimgen_StimType.md#hover-help). The player's own controls (bank
list, bank label, Reps, ISI, order, combination stepping, preview, Run/Pause,
the status labels and the toolbar) read their text from the same catalog,
`+stimgen/tooltips.json`, under the `StimPlayer` section:

```matlab
tip = @(key) stimgen.util.tooltip('StimPlayer', key);
h.Tooltip = tip('RunBtn');
```

`create.m` builds all of them except the bank label, which belongs to the
rebuilt parameter panel and is set in `on_bank_selection_changed.m`.

The panel registers its widgets with `stimObj.set_gui_handles()` and calls
`stimObj.notify_gui_changed()` after each successful edit, so a stimulus can
repair fields that the edit invalidated — selecting `Tone.WindowMethod`
retitles `Window Duration` and resets it to the new method's default, because
`Tone.on_gui_changed` calls `refresh_gui_widget`. See
[GUI change hooks](stimgen_StimType.md#gui-change-hooks). A subclass writes
that hook once and gets the same behavior here and in the standalone
`create_gui` panel.

This means `StimPlayer` stays aligned with the underlying stimulus classes.
If a new `StimType` subclass exposes good `propMeta()` metadata — including
`group`/`order` where a property belongs somewhere other than `Waveform` —
the editor panel can usually handle it without any `StimPlayer` changes.

### Recent files

The File menu carries three Recent submenus — Recent Protocols, Recent
Stimulus Banks and Recent Calibrations — each listing up to nine
most-recently-used paths, newest first. The lists persist across sessions in
MATLAB preferences under the `StimPlayer` group (`RecentProtocols`,
`RecentBanks`, `RecentCalibrations`) and are separate from the equivalent
`StimCalibrationGui` lists.

An entry is recorded whenever the corresponding file is successfully loaded,
and also when a bank is saved. Re-selecting a path already in a list promotes
it to the top rather than duplicating it. Selecting an entry whose file has
since moved or been deleted does not error: the entry is dropped from the list
and the status label reports the missing path. An empty list shows a disabled
`(None)` item. All three submenus are disabled during playback by
`lock_bank_controls_`, like the load/save items they mirror.

### Toolbar

A toolbar above the signal plot gives one-click access to the most common
actions, each a duplicate of an existing menu item or button: Load Protocol,
Load Bank, Save Bank, Open Calibration GUI, Add Stimulus, Duplicate Stimulus,
Remove Stimulus, Inspect Stimulus, Show All Combinations and Play Selected.
Toolbar buttons that edit the bank (Load/Save Bank/Protocol, Open Calibration
GUI, Add/Duplicate/Remove Stimulus) are disabled during playback by
`lock_bank_controls_`, the same as their menu/button counterparts. Show All
Combinations is disabled too: it edits nothing, but generating every
combination would compete with the playback timer. Inspect Stimulus and Play
Selected stay enabled, since neither edits the bank.

The microphone button, Capture Selected, sits after Play Selected. It follows
its own rule rather than `lock_bank_controls_` alone: it is enabled only when
there is hardware to record through, no session holds the bank, and no capture
is already running.

## Preview output and calibration status

`Play` and `Play All` audition through one of two routes, chosen by the
`Output` dropdown in the bank panel (the `PlaybackOutput` property,
`"Speakers"` or `"Hardware"`):

- **Speakers** (default): the computer sound card, via `StimType.play`. The
  signal is normalized to unit peak for audition, so a loaded calibration
  determines spectral shape at most — **calibrated levels are NOT
  reproduced**.
- **Calibrated HW**: the attached host's hardware. The generated waveform
  is played **verbatim**, so a calibrated stimulus drives the output at its
  calibrated voltage. Two hardware contracts can carry the preview, and a
  circuit typically exposes only one of them; the player prefers its own
  playback tags (`BufferData_0`, `BufferSize_0`, `x_Trigger_0` — the same
  contract a Run uses, so a preview exercises the exact route a Run will),
  and falls back to the host's calibration adapter
  (`HardwareHost.calibrationAdapter`, the `BufferOut`/`BufferIn` circuits
  the calibration itself was measured through) when the playback tags are
  absent. The microphone response `play_and_record` returns on the adapter
  route is discarded. With **no host** attached, the route is
  `CaptureAdapter` instead: hardware that can capture a stimulus can play
  one, and an application that owns its own audio path (MABR, for one)
  supplies an adapter rather than a `HardwareHost`. The adapter is resolved
  at every play (a function handle is called each time), and its
  `play_and_record` return is likewise discarded.

Selecting `Calibrated HW` requires a host or a `CaptureAdapter` and raises
`stimgen:StimPlayer:NoHardwareHost` with neither; the dropdown callback
reverts the selection so the GUI never displays a route that cannot play.
Switching onto hardware adopts the host's sample rate (when it reports one)
so the bank is regenerated at the rate the converters run at; at play time
the rate is verified against the hardware and a mismatch raises
`stimgen:StimPlayer:HardwareRateMismatch` rather than playing a waveform at
the wrong pitch and duration. Waveforms peaking beyond ±10 V are refused
(`stimgen:StimPlayer:PreviewVoltageOutOfRange`), and hardware preview is
refused while a Run session is presenting
(`stimgen:StimPlayer:PreviewDuringRun`). If the host has a protocol loaded
but nothing connected yet, the first hardware preview connects it and puts
it in Preview mode — the same steps a Run performs. The resolved adapter is
cached and invalidated whenever the interfaces are released.

Hardware preview blocks until the waveform finishes, so during a hardware
`Play All` cycle the Stop button takes effect between combinations, not
mid-waveform.

A **calibration status label** in the status bar makes the calibration state
unmissable. It answers two questions at once — is a calibration in use, and
does the selected preview output actually reproduce it:

- **Green** `Cal: <file> > HW`: calibration loaded and the hardware route is
  selected — calibrated levels are played.
- **Amber** `Cal: <file> (speakers)`: calibration loaded but speaker preview
  normalizes the signal, so its levels are not reproduced.
- **Red** `No calibration`: no bank item carries calibration data.

Its tooltip carries the details: source path, measurement timestamp, how many
bank items apply it, a warning when the calibration's sample rate differs
from the bank rate, and a reminder that a hardware Run always plays the
generated (calibrated) waveform regardless of the preview output. The label
is maintained by `update_calibration_status_`, called after every event that
can change the answer: loading a calibration, adding or removing bank items,
loading a bank, and switching the preview output.

## Hiding session controls (host takeover)

An interfacing application that owns the session itself can hide the controls
that would otherwise let the operator change it. Hidden controls are made
invisible *and* their grid row/column is collapsed, so no empty space is left
in the layout.

```matlab
sp = stimgen.StimPlayer(HOST);
sp.set_control_visibility(ISI=false, Reps=false, PlayMode=false)  % host sets timing
sp.set_control_visibility(All=false)                              % host runs everything
sp.set_control_visibility(All=false, Run=true)                    % all but Run
```

Hideable controls: `Reps`, `ISI`, `SampleRate`, `PlayMode` (the
`Shuffle`/`Serial` dropdown), `Output` (the preview output dropdown), `Run`,
and `Pause`. A host whose hardware dictates
the converter rate typically hides `SampleRate` and lets `Run` adopt it from
`HardwareHost.sampleRate()`. `All` sets every one at once and is applied
before the individual pairs, so the two can be combined as above. Each accepts
`true`/`false` or `"on"`/`"off"`.

The same state is readable and writable through the `ControlVisibility`
property, which is a scalar struct of logicals:

```matlab
sp.ControlVisibility.Pause = false;   % applies immediately
tf = sp.ControlVisibility.Run;
```

Hiding a control removes only the widget. The corresponding state stays fully
available programmatically — `sp.ISI`, `sp.Fs`, `sp.SelectionType`,
`sp.StimPlayObjs(k).Reps` — and playback can be driven with the action-string
form of `playback_control`:

```matlab
sp.playback_control("Run")      % also "Stop", "Pause", "Resume"
```

Bank editing is unaffected: `lock_bank_controls_` still disables the editing
controls during playback whether or not they are visible.

## Playback model

`StimPlayer` uses its own MATLAB timer and does not depend on the main
experiment timer.

At run time the class:

1. Resolves hardware parameters through `host.findParameter`.
2. Adopts the host's sample rate, when it reports one.
3. Asks for confirmation when the run will do something the operator may not
   expect (see [Before a run starts](#before-a-run-starts)); Cancel abandons it.
4. Starts a fixed-rate timer, whose start function resets every count and
   starts each bank item's variant sequence (see
   [Variant combinations in a run](#variant-combinations-in-a-run)).
5. Chooses the next bank index using the player-level `SelectionType`.
6. Writes the stimulus waveform into one of two hardware buffers, inverted
   on every other presentation of a variant whose stimulus alternates
   polarity (see below).
7. Toggles the matching trigger parameter.
8. Logs presentation order, elapsed trigger time, the sign played and the
   variant combination played (`StimOrder`, `StimOrderTime`, `StimPolarity`,
   `StimVariant`, row-aligned).
9. Lets the presented stimulus select its next combination.

The player uses ping-pong buffering through `TrigBufferID`, alternating
between buffer `0` and buffer `1` on successive trials.

### Pause and resume

**Pause** (or `playback_control("Pause")`) holds a running session; it does
not stop it. The timer keeps running and `timer_runtimefcn` returns at once
while the private `Paused_` flag is set, so nothing is presented, but nothing
is torn down either: the rep counts, the presentation log, each item's variant
cursor, the buffer already loaded for the next trial and the hardware
connection all survive, and the bank stays locked. **Resume**
(`playback_control("Resume")`) shifts `lastTrigTime` forward by the length of
the pause, so the interval that was in progress when Pause was pressed
continues with the time it had left. `StimOrderTime` is real elapsed time and
therefore includes the pause.

A pause is still a session holding the hardware: hardware preview, capture
and protocol loading stay refused until the session is stopped. `"Pause"`
while already paused and `"Resume"` while running are no-ops.

### Alternating polarity

A stimulus whose `alternates_polarity()` is true (a `Tone` with
`Polarity = 0`, a `ClickTrain` with `Polarity = 2`) is generated positive and inverted here, on every other
presentation **of the same variant combination** — `claim_polarity_` keeps
one count per bank item per combination, reset at each start. Counting per
bank item instead would be wrong whenever an item has an even number of
combinations visited in turn: each combination would always land on the same
sign. The sign actually played is logged in `StimPolarity`, row-aligned with
`StimOrder`. Preview playback (Play / Play All / capture) always plays the
positive waveform.

### Required hardware parameters

Hardware playback is enabled only when the host resolves all of these
parameter names:

- `BufferData_0`
- `BufferData_1`
- `BufferSize_0`
- `BufferSize_1`
- `x_Trigger_0`
- `x_Trigger_1`

If any are missing, `Run` still starts the timer, but the player logs that
hardware output is unavailable. Local preview through `Play Stim` still
works because that path uses MATLAB audio playback from the underlying
stimulus object.

## Scheduling behavior

There are two scheduling layers to keep in mind.

- `StimPlayer.SelectionType` chooses which bank item is played next.
- Each bank item is a `stimgen.StimPlay`, which can also manage selection
  inside a multi-object or variant-carrying stimulus.

That separation lets you do things like:

- shuffle across several named bank entries
- present each entry serially within its own internal sweep
- repeat the whole bank using a shared `ISI` range

`select_next_idx()` returns `-1` when every bank item has reached its target
repetition count, which ends the session cleanly.

### Variant combinations in a run

Which combination of a vectorized stimulus is presented is decided by the
stimulus's own `VariantSelectionMode` (`Serial`, `ShuffleUniform`,
`ShuffleLeastUsed` or `CustomSelector` -- see
[stimgen_StimType.md](stimgen_StimType.md)), not by the player:

- At the start of a run (`timer_startfcn` -> `initialize_variants_`) every
  stimulus calls `reset_variant_selection()` -- the `Serial` cursor returns to
  combination 1, `ShuffleLeastUsed` counts are zeroed, a custom selector is
  rebuilt and `initialize()`d again -- and then `update_signal()`, which
  makes the run's first selection through the mode. Previews, combination
  stepping and earlier runs therefore do not shape the order.
- After each presentation, `advance_variant_` calls `update_signal()` on the
  stimulus just presented, which selects its next combination the same way
  and regenerates it.
- The combination index each presentation was generated from is logged in
  `StimVariant`, row-aligned with `StimOrder`. With a shuffled mode that log
  is the only record of the order.

Combination stepping (the `<`/`>` buttons and the arrow keys) is disabled
while a session holds the bank: the next trial's buffer is already loaded,
and the log records the combination it was made from.

**Reps is per bank item, not per combination.** A run presents exactly `Reps`
presentations of each bank item (of each stimulus object it holds), shared
among its combinations; it never rounds `Reps` to a multiple of the
combination count, so a saved bank always produces the same number of trials.
How the presentations fall on the combinations depends on the mode:

| Mode | Per-combination count |
| --- | --- |
| `Serial` | `floor(Reps/n)` or `ceil(Reps/n)`; combinations `1..mod(Reps,n)` get the extra one |
| `ShuffleLeastUsed` | `floor(Reps/n)` or `ceil(Reps/n)`; which ones get the extra one is random |
| `ShuffleUniform` | random -- drawn with replacement, expected `Reps/n` |
| `CustomSelector` | whatever the selector returns |

The bank panel's combination line shows the split for the selected item
(`Combo: 2 / 6 | 3-4 reps each`), in amber when a balanced mode cannot split
`Reps` evenly. Run lists every such item in its confirmation dialog and logs
each one as a warning.

### Before a run starts

`confirm_run_` runs after the hardware is resolved and before the timer
exists. Each finding is logged; when there is any, a single dialog lists them
all and **Cancel** (the default) abandons the run without changing anything:

- a bank item whose `Reps` is not a multiple of its combination count under a
  balanced selection mode (see above).

## Saving and loading banks

`StimPlayer` persists banks as `.spl` files saved with MATLAB `save -v7`.

`save_bank()` stores:

- the global `ISI`
- the player-level `SelectionType`
- one serialized struct per `StimPlay` item

`load_bank()` reconstructs each item through `StimType.fromStruct` — the one
restore path, which `duplicate_stim` also uses — which:

- creates a new stimulus object from `S.StimObj.Class`
- restores `DisplayName` and switches `ApplyCalibration` off for the duration
- restores the base properties in `StimType.CoreProperties` (`Fs`, `ApplyWindow`,
  `SoundLevel`, `Duration`, `WindowDuration`, `WindowFcn` and the variant policy),
  the same list `toStruct` writes
- restores the calibration serialized with the item
- restores the serialized `UserProperties`, in order
- sets `ApplyCalibration` to the saved value, **last**

and then `load_bank()`:

- wraps the result in a new `stimgen.StimPlay`
- adopting the first item's `Fs` as the bank rate and re-applying it to the
  rest (see [Sample rate](#sample-rate))

`ApplyCalibration` brackets the rest because every restored property
regenerates the signal, and until the item's calibration is back that would be
against an empty one. `apply_calibration` answers an empty calibration with a
critical `No calibration data available for stim`, so loading a **calibrated**
bank used to log the same line an uncalibrated one earns. Held off,
`apply_calibration` returns before it looks; the closing assignment is the one
regeneration made with every property and the calibration in place.
Because this is `StimType.fromStruct`, a stimulus loaded by `SpotCheck` or a
host application, or duplicated in the bank, is restored identically. A bank item that really has
no calibration still raises the warning, once.

### Compatibility note

The loader restores stimulus parameters, names, repetitions, ISI, and any
calibration serialized with each item. A calibration previously loaded at the
player level belongs to the previous bank, so loading a bank clears it — the
status label then reports the loaded items' own embedded calibrations, or
`No calibration` when they carry none.

For multi-object stimuli, bank persistence should also be tested carefully.
`StimPlay.toStruct()` serializes expanded child stimuli rather than the
original wrapper object, so round-tripping a multi-object entry through
`.spl` files is less straightforward than round-tripping a single `Tone` or
`Noise` entry.

## Extending the tool

When a new stimulus class is added under `+stimgen`, `StimPlayer` can
usually pick it up automatically because it relies on `stimgen.StimType.list`
and the metadata returned by `get_prop_meta()`.

For new stimulus classes, these details matter most:

- the constructor must be callable with no required positional arguments
- the class should expose clear `propMeta()` labels and limits
- the class should keep its public editable properties in `UserProperties`

If the editor panel looks wrong for a new type, check the class metadata
before changing `StimPlayer` itself.

## Related files

- [+stimgen/@StimPlayer/StimPlayer.m](../../+stimgen/@StimPlayer/StimPlayer.m)
- [+stimgen/StimPlay.m](../../+stimgen/StimPlay.m)

## Related documentation

- [stimgen_overview.md](stimgen_overview.md) — package orientation
- [stimgen_StimInspector.md](stimgen_StimInspector.md) — the stimulus detail window
- [stimgen_CombinationViewer.md](stimgen_CombinationViewer.md) — every combination of one item, side by side
- [stimgen_StimPlay.md](stimgen_StimPlay.md) — the per-item scheduling wrapper
- [stimgen_calibration.md](stimgen_calibration.md) — calibrating output levels