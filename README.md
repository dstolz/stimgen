# stimgen

MATLAB toolbox for auditory stimulus generation, playback, and speaker/microphone
calibration.

`stimgen` builds precisely parameterized acoustic stimuli (tones, noise, AM/FM,
swept sines, click trains), manages banks of them for playback, and converts
requested sound levels into hardware voltages via a measured calibration.

It was extracted from [EPsych v2](https://github.com/dstolz/epsych2) and has no
dependency on it — `stimgen` runs standalone, and any host application can drive
it through the two abstract interfaces described below.

## Requirements

- MATLAB R2024b or newer
- Signal Processing Toolbox (calibration filter design and spectral analysis)
- Audio Toolbox (only for sound-card playback/preview)

## Installation

Clone the repository and add its **root** to the MATLAB path — not the `+stimgen`
folder itself, which MATLAB resolves as a package:

```matlab
addpath('C:\src\stimgen')
```

```
stimgen/            <- add this to the path
  +stimgen/         <- the package; do not add directly
```

Verify:

```matlab
t = stimgen.Tone;
t.Frequency = 4000;
t.plot
```

## Quick start

```matlab
% Build a stimulus
t = stimgen.Tone;
t.Frequency = [1000 2000 4000];   % vectorized properties expand into variants
t.SoundLevel = 65;
t.Duration = 0.2;
t.play

% Stimulus bank editor and player (offline: speaker preview only)
stimgen.StimPlayer

% Calibration GUI (offline: inspect or load a saved .esgc calibration)
stimgen.calibration.CalibrationGui
```

## Stimulus types

| Class | Description |
|---|---|
| `stimgen.Tone` | Pure tone |
| `stimgen.Noise` | Band-limited noise |
| `stimgen.AMnoise` | Amplitude-modulated noise |
| `stimgen.AttackModNoise` | Noise with modulated attack |
| `stimgen.FMtone` | Frequency-modulated tone |
| `stimgen.SweptSine` | Swept sine (chirp) |
| `stimgen.ClickTrain` | Click train |

All derive from `stimgen.StimType`, which handles gating, normalization,
calibration, and variant expansion. To add a stimulus type, subclass
`stimgen.StimType` and implement `update_signal`.

## Calibration

The calibration subsystem separates measurement math from hardware I/O:

- `stimgen.calibration.Engine` — reference measurement, tone/click/swept-sine
  calibration, equalization filter design, `.esgc` save/load. Depends only on the
  abstract adapter below, never on hardware directly.
- `stimgen.calibration.HwAdapter` — abstract; implement `sample_rate()` and
  `play_and_record(signal)` to support a new device.
- `stimgen.calibration.WindowsSoundCardAdapter` — built-in adapter using the
  system sound card.

```matlab
adapter = stimgen.calibration.WindowsSoundCardAdapter();
eng = stimgen.calibration.Engine(adapter);
eng.ReferenceFrequency = 1000;
eng.calibrate_reference();
eng.calibrate_tones();
eng.save('my_cal.esgc');
```

## Integrating with a host application

Two abstract classes are the only integration points; implement them to drive
`stimgen` from your own experiment framework:

- **`stimgen.HardwareHost`** — protocol loading, connect/release, device mode,
  and parameter lookup for `stimgen.StimPlayer` and
  `stimgen.calibration.CalibrationGui`. Pass an instance to their constructors;
  omit it to stay in offline preview mode.
- **`stimgen.calibration.HwAdapter`** — play/record for `Engine`.

`stimgen` never references host types directly, which is what keeps this package
independent. For a worked example of both, see the `stimbridge` package in
[EPsych v2](https://github.com/dstolz/epsych2).

## Logging

`stimgen.util.vprintf(level, ...)` is gated by the global `GVerbosity`
(`-1` log only, `0` critical, `1` info, `2` debug, `3` verbose) and writes a
daily log under `fullfile(tempdir,'stimgen_error_logs')`.

## Documentation

See [`documentation/`](documentation/) for per-class guides, including
`stimgen_overview.md`, `stimgen_StimType.md`, `stimgen_StimPlayer.md`, and
`stimgen_calibration.md`.

## License

GNU GPL v3.0 — see [LICENSE](LICENSE).

Daniel Stolzberg, PhD — daniel.stolzberg@gmail.com
