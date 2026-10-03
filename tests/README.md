# stimgen tests

Class-based `matlab.unittest` tests for the parts of stimgen that need no GUI,
no audio device and no hardware: the level scale, frequency weighting, band
arithmetic and sound level meter; stimulus serialization and the variant
system; logging through a host sink; the tooltip catalog; and the calibration
engine against the simulated rig in `documentation/tools/SimRigAdapter.m`.

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
| `StimTypeTest.m` | `StimType.list`, `toStruct`/`fromStruct` for every listed class (and a `SoundFile` with a generated wav), Cartesian and Pairwise combination tables, `active_variant_values` not advancing the selection |
| `LoggingTest.m` | `vprintf` through a `stimgen.FcnLogSink`: raw messages, the red flag, literal text, the sink's gate, uninstalling |
| `TooltipCatalogTest.m` | every `propMeta` entry has a tooltip; every literal key passed to `stimgen.util.tooltip` resolves in `tooltips.json` |
| `CalibrationEngineTest.m` | `calibrate_reference` recovering the simulated 50 mV/Pa microphone, its refusal with no calibrator, `.esgc` save/load; `MicSensitivityKnown`/`known_mic_sensitivity` before and after the reference step and across save/load; tone tables recording `normative_db` and lookups scaling from it rather than the live `NormativeValue`; `restore` stamping unversioned tables; a duplicated sweep frequency being dropped and logged |

Test data is generated into temporary folders and deleted afterwards. A
fixture that has to live in the repository goes under `tests/`, where
`.gitignore` does not exclude `.wav` and `.flac` files.
