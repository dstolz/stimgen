# stimgen tests

Class-based `matlab.unittest` tests for the parts of stimgen that need no audio
device and no hardware: the level scale and the LUT level convention, frequency
weighting, band arithmetic and sound level meter; Noise band edges; stimulus
serialization and the variant system; ongoing backgrounds and the stimuli
embedded in them; logging through a host sink; the tooltip
catalog; recent-file lists; and the calibration engine against the simulated rig
in `documentation/tools/SimRigAdapter.m`. A smoke test also builds both GUIs
offline and drives what needs no device or modal dialog.

## Running

From the repository root (the folder that contains `+stimgen`):

```matlab
addpath(pwd)                 % the ROOT, never +stimgen itself
results = runtests('tests');
table(results)
```

One file, or one test in it:

```matlab
runtests('tests/AcousticsTest.m')
runtests('tests/StimTypeTest.m', 'ProcedureName', 'cartesianCombinationTable')
```

Each test class also puts the root on the path for its own run (and
`documentation/tools` for the engine tests), so the tests do not depend on the
caller's path beyond finding `tests/` itself. Requires the Signal Processing
Toolbox; the Audio Toolbox is not needed.

After editing a classdef, `clear classes` before re-running, or MATLAB keeps
testing the cached definition.

## CI

`.github/workflows/tests.yml` runs the same suite on every push to `main` and
every pull request, through `matlab-actions/setup-matlab` and
`matlab-actions/run-tests`.

## Files

| File | Covers |
| --- | --- |
| `AcousticsTest.m` | `weighting_db` against IEC 61672-1, `volts_to_spl`/`spl_to_pressure`, `sound_levels` of a 1 Pa sine (93.98 dB SPL), `band_levels` on a flat PSD |
| `StimTypeTest.m` | `StimType.list`, `toStruct`/`fromStruct` for every listed class (and a `SoundFile` with a generated wav), Cartesian and Pairwise combination tables, `active_variant_values` not advancing the selection, a pinned `copy()` (Play All, CombinationViewer, capture) leaving its source's combination and selection order alone, `generation_record` describing the waveform on hand without selecting, `hold_updates` suspending regeneration, `fromStruct` generating once (a restored variant stimulus sits on combination 1; one that cannot be generated is still returned, with one critical log line) |
| `DMRTest.m` | `stimgen.DMR`: paper defaults and carrier grid, same seed → same waveform (and cached = fresh), the global random stream untouched, the interpolant against a reference kernel and against `interp1` on this release, trajectories in range and Φ = 2π∫Fm against `integral`, envelope bounds and variance (M²/8; ripple noise M²/12 or M²/8.61 by `ErfScaling`), the waveform rebuilt from `generation_record` alone, the gate, `Seed` as the variant axis, independence of the draws, what invalidates the synthesis cache, struct round trip, `export_envelope` writing the envelope a pinned stimulus reports and leaving its source alone, and the numbers seed 1 produces under `GeneratorVersion` 1 (the draw contract, pinned), and `envelope_from_record` / `trajectory_from_record` giving exactly what the object reports, after a MAT round trip too. Prints `DMRCHECK` / `DMRTIMING` / `DMRGOLD` lines for the log |
| `TORCTest.m` | `stimgen.TORC`'s generation record: the ripple rates, densities, phases, amplitude, period and carriers that made the waveform, one row per method I variant; `envelope_from_record` giving exactly what `dynamic_spectrum` reports (and Eq. 28 written out), after a MAT round trip too; bad records and times refused |
| `FakeHardwareHost.m`, `FakeHostParameter.m` | not tests: a `stimgen.HardwareHost` with no hardware behind it, exposing the six buffer/trigger parameters a Run resolves as handles that count their writes |
| `RecentPathsTest.m` | `stimgen.util.recent_paths`: add promotes without duplicates (case-insensitive), nine kept, remove, and the Recent submenu it builds |
| `LoggingTest.m` | `vprintf` through a `stimgen.FcnLogSink`: raw messages, the red flag, literal text, the sink's gate, uninstalling |
| `TooltipCatalogTest.m` | every `propMeta` entry has a tooltip, including the rows each `Background` type brings; every literal key passed to `stimgen.util.tooltip` resolves in `tooltips.json` |
| `BackgroundTest.m` | the ongoing background and the stimuli embedded in it: a stimulus with none is unchanged and an older struct loads as none; the noise loop's length, level (a `Noise`'s rms at that `SoundLevel`), band, seam and seed, with the global stream untouched; a tone background's amplitude is the table's voltage; `Key` equal exactly when the background is shared; an unused background setting is not a variant axis; `embedded_signal` is the tiled background plus the stimulus; the AM, gap and FM operators against their closed forms and FM refusing noise; a modulation's carrier-referenced level and `expected_offset_db`; the panel rows per background type; a `copy()` at another rate; `CapturedSignal` carrying no background |
| `LevelConventionTest.m` | a LUT voltage is a sine's peak: every rms-normalized stimulus carries a tone's rms at the same `SoundLevel` (flat table, offline), `filter_level_reference` agrees with `apply_calibration`, and on the simulated rig a Tone, an rms- and a peak-referenced `SoundFile` of the same sine and a narrow noise band all measure at their requested level the way SpotCheck measures |
| `NoiseBandTest.m` | `Noise`'s band-pass is -6 dB at each cutoff and `StopbandAttenuation` down beyond the transition, the generated spectrum is band-limited, the record does not fade in, an explicit `FilterOrder` keeps the old Hamming design, bad bands are refused |
| `GuiSmokeTest.m` | builds StimPlayer and CalibrationGui offline and drives what needs no audio device, hardware or modal dialog: every stimulus class in a bank, selection, stepping, duplicate, combination viewer, inspector, exports, bank save/load, Fs change; an offline dry run whose presentation log carries a generation record per trial, is saved and read back, and reproduces a presented segment from the file alone; a hardware Run on `FakeHardwareHost` (buffers loaded, slots triggered, hardware released) whose log is written automatically; the parameter panel rebuilt with the right rows as the Background dropdown is changed; every View item, the summary and the three settings windows on a calibration with every table; and on a live simulated rig the Measure Background, Measure Conduction Delay, Calibrate/Test Tones and Calibrate/Test Clicks buttons, each parameter window answered from a timer. Logs and returns where no uifigure can be made |
| `CalibrationEngineTest.m` | `calibrate_reference` recovering the simulated 50 mV/Pa microphone, its refusal with no calibrator, `.esgc` save/load; `MicSensitivityKnown`/`known_mic_sensitivity` before and after the reference step and across save/load; tone tables recording `normative_db` and lookups scaling from it rather than the live `NormativeValue`; `restore` stamping unversioned tables; a duplicated sweep frequency being dropped and logged; the background and conduction-delay report text |

Test data is generated into temporary folders and deleted afterwards. A
fixture that has to live in the repository goes under `tests/`, where
`.gitignore` does not exclude `.wav` and `.flac` files.
