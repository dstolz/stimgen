# stimgen.Patch — composable stimuli

`stimgen.Patch` is a stimulus whose signal chain is a graph you build, rather than a
recipe fixed by its class. It holds a set of **component nodes** and a set of
**connections**, where a connection routes one node's output into another node's
*parameter*.

That one mechanism covers the families that otherwise each need their own class:

| What you want | How you patch it |
| --- | --- |
| AM tone, AM noise, tremolo | modulator → carrier `Amplitude` |
| FM tone, vibrato | modulator → carrier `Frequency` |
| Pulsed tone, gated noise | `PulseTrain` → carrier `Amplitude` |
| Ramped / damped noise | `PulseTrain` (shape `ramped`) → noise `Amplitude` |
| Two-tone complex, noise + tone | several sources → `Mixer` inputs |
| Ring modulation | modulator → carrier `Amplitude`, mode `Ring` |

Related: [stimgen_PatchEditor.md](stimgen_PatchEditor.md) for the graphical editor,
[stimgen_StimType.md](stimgen_StimType.md) for the shared stimulus contract,
[stimgen_StimTypes.md](stimgen_StimTypes.md) for the monolithic stimulus classes.

---

## Quick start

```matlab
p = stimgen.Patch;                                    % starts as a 1 kHz tone, node "Osc1"
p.add_node("LFO1", "Oscillator", Frequency = 10);
p.add_connection("LFO1", "Osc1", "Amplitude", Mode = "AM", Depth = 1);
p.update_signal; p.plot                               % a 10 Hz AM tone
```

Or start from a preset and open the editor:

```matlab
p = stimgen.Patch.preset("PulsedTone");
stimgen.PatchEditor(p);
```

In `stimgen.StimPlayer`, add a **Patch** from the stimulus dropdown and press
**Edit Graph…** in the parameter panel.

---

## How graph parameters reach the rest of the toolbox

Every component parameter is exposed on the Patch as a property named
`<NodeLabel>_<ParamName>`:

```matlab
p.Osc1_Frequency = 4000;
p.LFO1_Frequency = 7;
```

These are dynamic properties, created and removed as you edit the graph, but they are
ordinary stimulus properties in every way that matters. In particular they can be
**vectorized into variants** exactly like any other property, including across
different nodes:

```matlab
p.Osc1_Frequency = [1000 2000 4000];
p.LFO1_Frequency = [2 4 8 16];
p.get_variant_info    % NumCombinations = 12
```

They also survive `.spl` bank save/load, appear in `StimInspector`, and can be typed as
expressions that reference their siblings:

```matlab
p.evalPropertyExpression('LFO1_Frequency', 'Osc1_Frequency/400')   % 10
```

> The separator is an underscore, not a dot, so that the name stays a legal MATLAB
> identifier and is not rewritten by `StimType.rewrite_qualified_property_refs_`, which
> strips a dotted prefix from expression text.

**Node labels must be valid MATLAB identifiers** and unique, because they become part of
these property names. `rename_node` carries values and connections across.

---

## Components

`stimgen.components.list()` enumerates what is available; dropping a new class into
`+stimgen/+components/` makes it appear with no registry to update.

| Kind | Generates | Modulatable parameters |
| --- | --- | --- |
| `Oscillator` | sine / square / triangle / sawtooth | `Frequency`, `Amplitude`, `Phase`, `Offset` |
| `NoiseSource` | band-limited Gaussian noise | `Amplitude` |
| `PulseTrain` | rect / cos² / ramped pulse train, or a one-shot envelope | `Amplitude` |
| `Sweep` | log-sine or linear chirp | `Amplitude` |
| `Mixer` | weighted sum of up to four inputs | `In1`…`In4` |
| `Constant` | DC | `Value` |
| `FileSource` | a waveform read from an audio file | `Amplitude` |
| `TORC` | temporally orthogonal ripple combination, for STRF estimation | `Amplitude` |

Notes:

- **`Oscillator` is both carrier and LFO.** There is no distinction in the code — a low
  `Frequency` makes it a modulator, an audio-rate one makes it a carrier. Driving its
  `Frequency` produces FM, by integrating instantaneous frequency, so any modulator
  shape works, not just a sinusoid.
- **`PulseTrain` with `Rate = 0`** emits a single pulse spanning the whole duration,
  which makes it a one-shot envelope generator rather than a train.
- **`NoiseSource.Seed`** makes a token reproducible; `0` draws a fresh one each render.
- **`Mixer` needs no special routing machinery.** Its inputs are ordinary modulatable
  parameters that default to 0, so connecting a node with mode `Direct` simply replaces
  the parameter with that node's waveform.
- **`FileSource` does not slave `Duration` to the file** the way `stimgen.SoundFile`
  does. A patch has one timebase, so the file is truncated or zero-padded to it — which
  is what lets a recording be mixed with, or gated by, synthesized sources.
- **`TORC` is the composable form of `stimgen.TORC`** — see [below](#torc-nodes).

---

## TORC nodes

`TORC` synthesizes a temporally orthogonal ripple combination: a broadband sound whose
dynamic spectrum is the sum of moving ripples with pairwise-distinct modulation rates,
from which an STRF is recovered by spectrotemporal reverse correlation. The parameters,
the equation numbers and the two component modes are documented on
[`stimgen.TORC`](stimgen_StimTypes.md#torc); as a node it can additionally be gated,
mixed or amplitude-modulated against other sources.

Reverse correlation needs the dynamic spectrum that drove the waveform, so the realized
ripple set is recorded after every render and `dynamic_spectrum` rebuilds `S(t,x)` from
it at whatever resolution the analysis needs — typically the PSTH bin rate, not `Fs`:

```matlab
p = stimgen.Patch;
p.add_node("Torc1", "TORC");
p.OutputNode     = "Torc1";
p.LevelReference = "rms";       % broadband: normalize on rms, not absmax
p.ApplyWindow    = false;       % gating breaks the periodicity the method relies on
p.update_signal;

c = p.component("Torc1");
[S, t, x] = c.dynamic_spectrum(500);
a = c.LastRipples.Amplitude;    % the scalar a of Eq. (28); STRF = C / a²
```

Vectorize `p.Torc1_Seed = 1:25` for the phase-averaging ensemble, or
`p.Torc1_RippleDensity` for the method I ensemble — they are ordinary patch parameters.

Four things differ from `stimgen.TORC`:

- **There is no `Duration` parameter.** The ripple period is `T = (N/Fs)/NumPeriods`,
  taken from the patch's global timebase. Rates live on the `1/T` grid, so `Duration` and
  `NumPeriods` decide which ripples are available at all. The defaults (10–40 Hz) are
  picked to render at the default patch `Duration` of 100 ms, whose 10 Hz fundamental
  rules out the paper's slow ripples; for the canonical configuration set
  `p.Duration = 0.25` and the band to 4–24 Hz, which lands exactly on 4, 8, 12, 16, 20,
  24 Hz.
- **A `LowestRate` below the fundamental is clamped up to it** in `Range` mode, with a
  note through `vprintf`, rather than erroring — a node does not own the `Duration` that
  sets its ripple period, so an edit elsewhere in the patch must not break it.
  `Explicit` mode still errors, because there each entry is a specific requested ripple
  rather than the edge of a band. A band lying *entirely* below the fundamental errors
  either way.
- **The waveform is divided by `sqrt(nCarriers)`.** Carriers add incoherently, so a raw
  sum grows with `ComponentsPerOctave` and a resolution knob would double as a level
  knob. `stimgen.TORC` does not need this because `StimType` renormalizes the finished
  waveform; a node is mixed against its siblings before any normalization happens. An
  overall gain leaves the dynamic spectrum — defined in dB about the mean level —
  untouched.
- **`Seed = 0` draws fresh phases**, matching `NoiseSource`. `stimgen.TORC` instead
  reseeds on a *negative* `Seed`, so `0` means different things in the two.

Keep `CalibrationMode` on `"Filtered"`. A TORC node carries no single carrier frequency,
so mode `"Tone"` falls through to the spectral centroid.

---

## Connections

Before a mode is applied the source is normalized through its component's **declared**
`nominal_range` (not its measured extremes) into

- `u` in `[0 1]` — unipolar
- `b` in `[-1 1]` — bipolar

so `Depth` means the same thing regardless of what the source happens to be doing on a
given render.

| Mode | Formula | Use |
| --- | --- | --- |
| `Add` | `p = base + Depth·b` | FM and other offsets. `Depth` is in the target's own units, so Hz for a frequency. |
| `AM` | `p = base·(1 − Depth + Depth·u)` | Classic amplitude modulation. `Depth = 1` modulates fully to zero. |
| `Ring` | `p = base·b` | Ring modulation. |
| `Exp` | `p = base·2^(Depth·b)` | Octave-scaled vibrato; `Depth` is in octaves. |
| `Gate` | `p = base·(u ≥ Depth)` | Hard gating at a threshold. |
| `Direct` | `p = m` | Replace outright — used to patch audio into a `Mixer` input. |

`PowerCompensate` (per connection, `AM` only) multiplies by `sqrt(1/(Depth²/2+1))`,
equalizing total power across modulation depths so that changing depth does not change
loudness. This is the Viemeister correction that `stimgen.AMnoise` applies.

Several connections into the same parameter compose in graph order.

**Cycles are rejected when the graph is assigned.** Every node renders its whole buffer
at once, so there is no sample-by-sample feedback and a loop has no meaning.

---

## Rendering

One global timebase: `Fs` and `Duration` come from the Patch, and every component
returns exactly `N` samples. Nodes are evaluated in topological order, so a source is
always rendered before anything it modulates.

The package-wide pipeline — **normalize → calibrate → gate** — is applied once, to the
output node's waveform. Individual nodes are never normalized or gated: doing so would
defeat modulation, since a modulator's amplitude is exactly what carries the
information.

A patch with no nodes, or no output node, renders silence rather than raising. Every
graph edit regenerates the signal through a property listener, and an intermediate state
must not leave the object unusable.

---

## Level and calibration

`CalibrationType` and `Normalization` are `Abstract, Constant` on `StimType` and cannot
vary per instance, but a patch can contain anything. So, like `stimgen.SoundFile`, it
declares constants and overrides the two methods:

| Property | Values | Meaning |
| --- | --- | --- |
| `LevelReference` | `"absmax"` (default), `"rms"`, `"peak"` | What the waveform is normalized against. Use `"rms"` for noise-based patches. |
| `CalibrationMode` | `"Filtered"` (default), `"Tone"`, `"None"` | `Filtered` equalizes with the measured FIR; `Tone` does a scalar LUT lookup. |
| `AnchorFrequency` | Hz, `0` = auto | The `Tone`-mode lookup frequency. |

With `AnchorFrequency = 0`, the anchor is the highest-frequency `Oscillator` or `Sweep`
that actually feeds the output node — for a modulated tone that is the carrier, not the
modulator — falling back to the spectral centroid when the chain has no
frequency-bearing node.

---

## Presets

`stimgen.Patch.preset_names()` lists them; each is just a few `add_node` /
`add_connection` calls and can be taken apart and rewired.

| Preset | Reproduces |
| --- | --- |
| `AMTone`, `FMTone`, `PulsedTone`, `Tremolo` | — |
| `AMNoise` | `stimgen.AMnoise` |
| `RampedNoise`, `DampedNoise` | `stimgen.AttackModNoise` (`Z < 0` / `Z > 0`) |
| `GatedNoise` | — |
| `ClickTrain` | `stimgen.ClickTrain` |
| `Chirp` | `stimgen.SweptSine` |
| `TwoTone`, `NoiseInNoise` | — |

---

## Relationship to the monolithic classes

`Patch` is purely additive. `Tone`, `Noise`, `AMnoise`, `AttackModNoise`, `FMtone`,
`SweptSine`, `ClickTrain`, `TORC` and `SoundFile` are unchanged, and existing `.spl`
banks are unaffected.

Two deliberate numerical differences, where the component was made to follow its
documented definition rather than reproduce the original:

- **`PulseTrain` runs the train to the end of the timebase.** `ClickTrain` tiles
  `floor(Duration / period)` whole periods after rounding the period to an integer
  sample count, so it silently drops a trailing partial pulse — a 200 ms train at 20 Hz
  yields three pulses, not four. A gate should not lose its final pulse.
- **`Oscillator` FM depth is the actual peak deviation in Hz.** `FMtone` multiplies its
  modulation term by an extra factor of 2π relative to its own documented
  `f(t) = Fc + D·sin(2π·Fm·t)`, so its `ModulationDepth` produces a deviation about 6.28×
  larger than the number entered. `Patch` FM with `Mode = "Add", Depth = D` deviates by
  `D` Hz. Existing `FMtone` stimuli are untouched; if you are matching a previous
  experiment built with `FMtone`, set the patch `Depth` to `2π ×` the old
  `ModulationDepth`.

---

## API

```matlab
% Topology
p.add_node(label, kind, ParamName = value, ...)
p.remove_node(label)
p.rename_node(oldLabel, newLabel)          % carries values and connections across
p.add_connection(from, to, param, Mode = "AM", Depth = 1, PowerCompensate = false)
p.remove_connection(from, to, param)
p.OutputNode = label

% Inspection
p.node_labels()                            % string array, graph order
p.component(label)                         % the component object
p.node_output(label)                       % that node's waveform from the last render
p.edit_graph()                             % open the editor

% Statics
stimgen.Patch.preset(name)
stimgen.Patch.preset_names()
stimgen.Patch.mode_names()                 % modes with their formulas
stimgen.components.list()                  % available component kinds
```

`Graph` holds topology only — labels, kinds, canvas positions, connections. Parameter
values live solely in the dynamic properties, so there is no second copy to keep in
sync. It is listed first in `UserProperties` because all restore paths assign in that
order and the nodes must exist before their parameters can be written.

---

## Adding a component

Drop a class into `+stimgen/+components/` deriving from
`stimgen.components.Component`:

```matlab
classdef MyThing < stimgen.components.Component
    properties (Constant)
        Kind        = "MyThing";
        Description = "One line for the editor palette";
    end
    methods
        function d = param_defs(~)
            pd = @stimgen.components.Component.pdef;
            d = struct();
            d.Rate      = pd('Rate (Hz)', 10, 'format','%.2f Hz', 'limits',[0 1e6], 'order',10);
            d.Amplitude = pd('Amplitude', 1, 'modulatable',true, 'order',20);
        end
        function y = render(obj, ctx, p)
            y = obj.fit(sin(2*pi*p.Rate*ctx.t) .* obj.expand(p.Amplitude, ctx.N), ctx.N);
        end
    end
end
```

Contract:

- `render` returns exactly `1 × ctx.N`. Use `obj.fit` to truncate or zero-pad.
- Each value in `p` is a scalar **or** a full-length vector — a modulated parameter
  arrives as a vector. Use `obj.expand(value, N)` to normalize.
- Override `nominal_range(obj, p)` if the output is not `[-1 1]`, so connections can map
  it to unipolar or bipolar form correctly.
- `pdef` fields mirror the `propMeta` schema (`label`, `format`, `limits`, `scale`,
  `widget`, `items`, `itemsData`, `order`) plus `default`, `modulatable` and `doc`.
  `items` takes **single** braces: `pdef` parses with `inputParser`, which does not
  unwrap a cell the way the `struct()` constructor does.
