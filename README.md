# stimgen

MATLAB toolbox for auditory stimulus generation, playback, and speaker/microphone
calibration — standalone, with no dependency on any host application.

## Requirements

- MATLAB R2021a or newer
- Signal Processing Toolbox (required)
- Audio Toolbox (only for sound-card playback/preview)

## Installation

Clone the repository and add its **root** to the MATLAB path — not the `+stimgen`
folder itself, which MATLAB resolves as a package:

```matlab
addpath('C:\src\stimgen')
```

Verify:

```matlab
t = stimgen.Tone;
t.Frequency = 4000;
t.plot
```

## Documentation

Full documentation — architecture, stimulus types, the `Patch` component system,
calibration, and host integration — lives on the
**[wiki](https://github.com/dstolz/stimgen/wiki)**.

## License

GNU GPL v3.0 — see [LICENSE](LICENSE).

Daniel Stolzberg, PhD — daniel.stolzberg@gmail.com
