# stimgen.PatchEditor — the signal graph editor

Drag-and-drop editor for a [`stimgen.Patch`](stimgen_Patch.md) graph.

```matlab
stimgen.PatchEditor();                % blank editor, opens on a new default patch
p = stimgen.Patch.preset("AMTone");
stimgen.PatchEditor(p);              % modal
stimgen.PatchEditor(p, false);       % non-modal, for scripting
```

From `stimgen.StimPlayer`, add a **Patch** to the bank and press **Edit Graph…** in the
parameter panel.

Called with no patch, the editor never opens on an empty window: it constructs a fresh
`stimgen.Patch`, which comes with a single default oscillator node (the same starting
point `stimgen.Patch`'s own constructor gives any other caller), and hands that back
through `obj.Patch` when the window closes.

---

## Layout

![PatchEditor window on the AMTone preset: component palette on the left; signal graph canvas in the middle with a blue-outlined LFO1 node wired into the green-outlined Osc1 node (wire labelled "AM 1") and Osc1 wired on to OUT; Preview plot showing the 10 Hz modulator and Output plot showing the finished AM tone underneath; LFO1's parameters in the inspector on the right](images/PatchEditor.png)

- **Node boxes** carry one labelled input port per modulatable parameter on the left,
  and one output port on the right. The header is tinted by component kind.
- **Green outline** marks the node currently feeding OUT.
- **Blue outline** marks the selection.
- **Wire labels** show the connection mode and depth, so routing reads without clicking.

---

## Interactions

| Action | Result |
| --- | --- |
| Drag a node body | Move it. Position is saved in the graph, so layouts survive save/load. |
| Drag output port → input port | Create a connection. Defaults to `Direct` into a `Mixer` input, `AM` depth 1 otherwise. |
| Drag output port → **OUT** | Make that node the stimulus output. |
| Click a node or wire | Select it; the inspector and preview follow. |
| `Delete` / `Backspace` | Remove the selection. |
| `Esc` | Cancel an in-progress drag. |
| **Add Node** | Add the palette selection at the first free slot. |
| **Auto Layout** | Arrange nodes left to right by graph depth. |
| **Preset ▾** | Replace the graph with a named preset, leaving level and timing alone. |
| **Revert** | Restore the graph and every parameter value as of when the window opened. |

Edits apply to the patch immediately — the preview would be useless otherwise — so
**Revert** is the undo story: one restore point, taken at open.

The **preview** shows the selected node's own output, pre-level and pre-gate, or the
finished stimulus when nothing is selected. Seeing a modulator's waveform is usually
what explains what a connection is doing.

The **output** panel always shows the finished stimulus, whatever is selected, so the
effect of an edit stays visible without deselecting. **Play** auditions it through the
computer speakers.

**Duration (ms)** sits under the output plot rather than in the inspector, because it
belongs to the stimulus rather than to any one node — as do level, gating and
calibration, which stay in the StimPlayer panel. It is the same `Duration` property every
other stimulus type has, in the same milliseconds-in-the-GUI convention. Changing it
changes the timebase every node renders onto at once: `Patch.update_signal` derives `N`
from `Duration` and `Fs` and each component returns exactly that many samples, so nodes
stretch with it rather than being padded or truncated to fit.

Numeric fields in the inspector accept **expressions and vectors**, exactly like the
StimPlayer panel, so a graph parameter can be turned into a variant axis from inside the
editor by typing `[1000 2000 4000]`. The Duration field is the same kind of field, so
`[50 100 200]` there gives three durations.

The text is evaluated as a MATLAB expression, so a vector literal needs its brackets:
`[50 100 200]` and `50:50:200` both work, a bare `50 100 200` does not.

`FileSource` nodes get a **Browse…** button in the inspector. This is the one control
the StimPlayer panel cannot offer: a `propMeta` button callback is a bare no-argument
method name, so the panel has no way to tell one `FileSource` node from another.

---

## File menu

| Item | Result |
| --- | --- |
| **Save** | Write the patch to its current `.spatch` file, or prompt for one if it doesn't have one yet. |
| **Save As...** | Always prompt for a `.spatch` file. |
| **Load...** | Replace the graph and every property with the contents of a `.spatch` file. |
| **Recents** | Submenu of the 9 most recently *modified* `.spatch` files on record — by file timestamp, not by when this editor last touched them, so a file re-saved elsewhere still sorts correctly. Shared across editor windows and MATLAB sessions via `getpref`/`setpref` (`record_recent_file_`, `list_recent_files_`). |

A `.spatch` file is a MATLAB `-mat` file holding `stimgen.Patch.toStruct()`, the same
serialization every stimulus type uses. **Load** does not swap in a new `stimgen.Patch`
object: it copies the loaded values onto the live `obj.Patch` handle (`Graph` first, so the
dynamic parameter properties it creates exist before their values are copied), because
`Patch.edit_graph` and any other caller hold a reference to that exact handle and only
in-place changes are visible to them once the editor closes.

---

## Modality

The editor is modal by default. `stimgen.StimPlayer` rebuilds its entire parameter panel
as soon as a `propMeta` button action returns (`run_action_` in
`@StimPlayer/on_bank_selection_changed.m`), and the new node set has to exist by then.

Pass `false` as the second argument for a non-modal window — useful for scripting, for
driving the editor from a host application, or for testing.

---

## Implementation notes

Worth knowing before changing this class:

- **Drags are driven from figure-level `WindowButtonDownFcn` / `MotionFcn` / `UpFcn`**,
  hit-tested against stored geometry in data units. Per-object picking inside a `uiaxes`
  is unpredictable once objects overlap, and the default axes interactions claim the
  mouse before any `ButtonDownFcn` runs — so `disableDefaultInteractivity`,
  `Interactions = []` and `Toolbar.Visible = 'off'` are all required, not cosmetic.

- **Geometry, hit testing and the wire path are pure static functions**
  (`node_geometry_for_`, `hit_test_at_`, `wire_path_`). Drawing and hit testing share
  `wire_path_`, so a click cannot land off a drawn wire, and the layout can be verified
  without opening a window.

- **Nothing is written to the patch during a drag.** A new position or connection is
  applied on release, so dragging never triggers a re-render.

- **The canvas is fully redrawn on each change.** A patch holds at most a few dozen
  primitives, which stays interactive and avoids a class of stale-handle bugs.

- **The inspector reads widget type, label, scale, format and limits from the patch's own
  `propMeta`**, keyed by flattened name, so it cannot drift from what StimPlayer's panel
  shows. The Output panel's Duration field reads the same metadata and takes the same
  write path (parse as an expression in display units, divide by the display scale
  exactly once) — see `set_duration_`.

- **Stimulus-level properties are not in the inspector**, which is scoped to the
  selection. Duration is the one exposed here, next to the output plot it governs; it is
  refreshed from the property in `update_output_`, because **Revert** restores it without
  going through its field.

- **Node positions are canvas coordinates in `0..1`**, and a position is the box's
  **top-left** corner. Layouts stop short of the right edge to stay clear of the OUT
  terminal at `x = 0.955`.
