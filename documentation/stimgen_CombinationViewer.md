# stimgen.CombinationViewer

Every variant combination of one stimulus, side by side.

A stimulus with vectorized properties is a family of waveforms. A `Tone` with
`Frequency = [4000 8000 16000]` and `SoundLevel = [30 60]` has six, and
StimPlayer's signal plot shows one at a time. `CombinationViewer` generates
all of them and draws them together.

```matlab
t = stimgen.Tone('Frequency', [4000 8000 16000], 'SoundLevel', [30 60]);
v = stimgen.CombinationViewer(t, "tone family");
v.View   = "Overlay";     % "Tiles" | "Overlay" | "Stacked"
v.Domain = "Spectrum";    % "Waveform" | "Spectrum"
v.SharedScale = false;    % each trace scaled to its own peak
v.set_shown([1 3 5]);     % draw only these
insp = v.inspect(3);      % open combination 3 in a StimInspector
```

From StimPlayer: **Tools > Show All Combinations...** (`Ctrl+G`), or the
grid button in the toolbar next to Inspect Stimulus. Each press opens a
**new** window, so you can compare two bank items, or one item before and
after an edit, side by side.

## The window

- **Table (left).** One row per combination: its index, the value of each
  varying property in the GUI's display units (ms for times), then the peak
  and the rms of the generated signal. The **Show** column picks which
  combinations are drawn; **All** and **None** set it wholesale. Clicking a
  row makes that combination *current*.
- **View.** *Tiles* draws one small plot per combination, titled with its
  parameter values. *Overlay* draws them all on one axes, with a legend when
  there are 16 or fewer. *Stacked* offsets them down one axes and puts each
  combination's name on the y axis, so a series reads top to bottom without a
  legend.
- **Show.** *Waveform* is amplitude against time in ms. *Spectrum* is the
  single-sided magnitude in dB against frequency in kHz, with a floor at
  −100 dB.
- **Shared scale.** On, every trace uses one amplitude scale, so level
  differences between combinations stay visible. For spectra that means
  dB relative to the loudest trace shown. Off, each trace is scaled to its
  own peak, which is the view for comparing shapes.
- **Current combination.** It is drawn bold, and in Tiles its axes are
  outlined. **Inspect** (or the magnifier button, or double-clicking a trace)
  opens it in a [`stimgen.StimInspector`](stimgen_StimInspector.md).
  Inspectors opened here close with the window.
- **Refresh** (the circular-arrow button) regenerates every combination from
  the source object, so edits made since the window opened show up. The Show
  ticks are kept if the number of combinations is unchanged.

At most `MaxTraces` combinations (64 by default) are drawn at once; the table
still lists all of them, and the status line says when the cap applies.
Generating more than 16 combinations shows a progress dialog that can be
cancelled; a cancelled run keeps the combinations generated so far.

With no calibration loaded, `SoundLevel` never reaches the amplitude (see
[stimgen_calibration.md](stimgen_calibration.md)), so a level series draws as
identical traces. The status line says so when the family varies
`SoundLevel` and is uncalibrated.

## The source is never touched

The combinations are generated on **copies** of the stimulus. The source is
copied once, `VariantReselectOnUpdate` is forced off on that copy, and each
combination is a further copy pinned with `set_variant_index`. The source
object therefore keeps its active combination, its selection order and its
use counts, so opening the viewer from StimPlayer does not move the bank. See
*Reading a variant value without advancing it* in the repository `CLAUDE.md`
for why the reselect switch matters.

The copies are kept in `Combos(c).Stim`, so the waveform that Inspect opens is
the one on screen. For a noise stimulus each copy is a fresh draw from the
same parameters, which is also what the bank would generate next time.

StimPlayer refuses to open a viewer while a session is running. Generating a
large family runs on the same thread as the playback timer, and a late
trigger is worse than a window that opens after the run. Open viewers close
with the player.

## Properties

| Property | Meaning |
| --- | --- |
| `View` | `"Tiles"`, `"Overlay"` or `"Stacked"` (default `"Stacked"`) |
| `Domain` | `"Waveform"` or `"Spectrum"` |
| `SharedScale` | one amplitude scale for every trace (`true`) or each its own (default `false`) |
| `MaxTraces` | most combinations drawn at once |
| `StimObj` | the source `StimType` (read-only, never modified) |
| `Combos` | one element per combination: `Index`, `Stim` (the pinned copy), `Signal`, `Fs`, `Values` (varying properties, stored units), `Short`/`Full` (descriptions) |
| `PropNames` | the varying properties, in table-column order |
| `Current` | the current combination |

Methods: `refresh`, `set_shown(idx)`, `select(c)`, `inspect([c])`, `show`,
`is_open`.

`View`, `Domain`, `SharedScale` and the window position persist in the
`CombinationViewer` preference group. A second window opened while one is
already up is offset from it rather than stacked exactly on top.

## Related

- [stimgen_StimPlayer.md](stimgen_StimPlayer.md) — the bank editor that opens it
- [stimgen_StimInspector.md](stimgen_StimInspector.md) — the single-stimulus detail window
- [stimgen_StimType.md](stimgen_StimType.md) — variants and combination modes
