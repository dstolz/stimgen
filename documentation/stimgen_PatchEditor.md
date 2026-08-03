# stimgen.PatchEditor — the signal graph editor

Drag-and-drop editor for a [`stimgen.Patch`](stimgen_Patch.md) graph.

```matlab
p = stimgen.Patch.preset("AMTone");
stimgen.PatchEditor(p);              % modal
stimgen.PatchEditor(p, false);       % non-modal, for scripting
```

From `stimgen.StimPlayer`, add a **Patch** to the bank and press **Edit Graph…** in the
parameter panel.

---

## Layout

```
┌ Components ┬──────────── Signal Graph ─────────────┬ Inspector ┐
│ Constant   │                                       │           │
│ FileSource │   ┌────────────┐      ┌───────────┐   │  Label    │
│ Mixer      │   │ LFO1  Osc  │─────▶│ Osc1  Osc │   │  Is Output│
│ NoiseSrc   │   │ ○ Frequency│ AM 1 │○ Frequency│   │  Frequency│
│ Oscillator │   │ ○ Amplitude│      │○ Amplitude│──▶│  Amplitude│
│ PulseTrain │   │ ○ Phase    │      │○ Phase    │ ● │  Phase    │
│ Sweep      │   └────────────┘      └───────────┘OUT│  Shape    │
│            ├─────────────── Preview ───────────────┤           │
│ Add Node   │  ╱╲╱╲╱╲╱╲╱╲  waveform of selection    │           │
│ Delete     │                                       │           │
│ Auto Layout│                                       │           │
└────────────┴───────────────────────────────────────┴───────────┘
 [Preset ▾]  status line                      [Revert] [Close]
```

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

Numeric fields in the inspector accept **expressions and vectors**, exactly like the
StimPlayer panel, so a graph parameter can be turned into a variant axis from inside the
editor by typing `1000 2000 4000`.

`FileSource` nodes get a **Browse…** button in the inspector. This is the one control
the StimPlayer panel cannot offer: a `propMeta` button callback is a bare no-argument
method name, so the panel has no way to tell one `FileSource` node from another.

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
  shows.

- **Node positions are canvas coordinates in `0..1`**, and a position is the box's
  **top-left** corner. Layouts stop short of the right edge to stay clear of the OUT
  terminal at `x = 0.955`.
