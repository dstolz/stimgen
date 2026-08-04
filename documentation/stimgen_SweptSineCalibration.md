# Swept Sine Calibration — Log-Sine Chirp Implementation

> **Files:**
> - `SweptSine.m` — stimulus generator implementing log-sine chirps
> - `Engine.calibrate_swept_sine()` — broadband calibration method
> - `CalibrationGui` — integrated UI button and controls
>
> **Reference:** Chan, I.H. (2010) "Swept Sine Chirps for Measuring Impulse Response," Stanford Research Systems

---

## Overview

The **log-sine chirp** (swept sine) is a specialized test signal for fast, broadband calibration measurements. Unlike traditional discrete-frequency methods (tone sweeps) or transient methods (clicks), the swept sine:

- **Covers the full frequency range in one measurement** (e.g., 100 Hz → 20 kHz in 1 second)
- **Has naturally pink spectrum** without filtering, reducing crest factor to ~4 dB (vs. 11–14 dB for filtered MLS or noise)
- **Separates harmonic distortion products in time**, enabling distortion-free fundamental measurement via two-channel FFT analysis
- **Reduces measurement time** by 10–100× versus stepped-sine, enabling real-time feedback during experimental setup

### Advantages over other broadband methods

| Property | Log-Sine Chirp | Filtered MLS | Pink Noise |
|----------|---|---|---|
| **Crest Factor** | 4 dB | 11 dB | 14 dB (Gaussian) |
| **SNR Advantage** | baseline | –7 dB | –10 dB |
| **Distortion Separation** | Yes (time-gated) | No | No |
| **Spectrum Control** | Pink (inherent) | Requires filter | Requires filter |
| **Duration** | 0.5–2 s | Same | Same |

---

## Math: Log-Sine Chirp Generation

The fundamental equation is:

$$x(t) = \sin\left(\frac{2\pi f_1 T}{\ln(f_2/f_1)} \left(\exp\left(\frac{\ln(f_2/f_1) \cdot t}{T}\right) - 1\right)\right)$$

where:
- $f_1$ = starting frequency (Hz)
- $f_2$ = ending frequency (Hz)  
- $T$ = total duration (s)
- $t \in [0, T]$ = time

**Key insight:** Frequency increases *exponentially* with time. Each octave (2× frequency) takes equal time, making the spectrum naturally pink (–3 dB/octave).

---

## Usage: Swept Sine Calibration Workflow

### 1. Basic calibration run

```matlab
adapter = host.calibrationAdapter()  % a host-supplied HwAdapter for the connected interface
eng = stimgen.calibration.Engine(adapter);

% Measure reference (single 1 kHz tone)
eng.calibrate_reference();

% Run swept sine calibration (1 second, default 50-point analysis)
eng.calibrate_swept_sine();

% Optionally run tone/click sweeps for comparison
eng.calibrate_tones();
eng.calibrate_clicks();

eng.save('my_calibration.esgc');
```

### 2. Custom frequency analysis points

```matlab
% Analyze response at specific frequencies
freqs = [100, 250, 500, 1000, 2000, 4000, 8000, 16000];
eng.calibrate_swept_sine(1, freqs);
```

### 3. Longer chirp for lower SNR requirements

```matlab
% 2-second chirp (×4 averaging equivalent to 1-second × longer integration)
eng.calibrate_swept_sine(2);
```

### 4. From GUI

The `stimgen.CalibrationGui` includes:
- **Swept Sine Duration (ms)** — default 1000 ms (converted to seconds before
  it reaches `Engine.calibrate_swept_sine`, which still takes seconds)
- **Swept Sine Freqs (Hz)** — default empty (auto: 50-point log across the swept band,
  100 Hz to `min(0.95·Nyquist, 20 kHz)`)
- **Calibrate Swept Sine** — button to run the measurement

All three calibration methods (reference → tones, clicks, swept sine) can be run independently and combined in the same `.esgc` file. The GUI plots all available calibration curves overlaid.

---

## Measurement Flow

1. **Generate signal:** Log-sine chirp from 100 Hz to ~95% Nyquist over specified duration
2. **Play & record:** Hardware plays excitation, microphone returns response. Only trailing
   buffer padding is stripped — the onset window is kept, because it carries the
   low-frequency start of the sweep
3. **Deconvolve:** Recover the transfer function from the excitation/response pair
4. **Sample:** At each frequency point $f_i$, convert $|H(f_i)|$ to an equivalent
   steady-tone level, then to dB SPL and normalized voltage
5. **Store LUT:** Frequency → SPL/voltage table, interpolable via `makima` spline

### Why the level comes from the transfer function

A chirp visits each frequency for only a few milliseconds, so the response periodogram
read at one frequency is **not** a level. It sits far below the true steady-tone level,
and drops another 3 dB every time the sweep duration doubles. The transfer function is
duration-invariant:

$$H(f) = \frac{Y(f)}{X(f)}$$

$H$ is microphone volts per drive volt, so a steady sinusoid of peak `ExcitationVoltage`
would measure

$$m(f) = |H(f)| \cdot \frac{V_{\text{exc}}}{\sqrt{2}}$$

which is exactly what `calibrate_tones` measures directly. Feeding $m(f)$ through the same
`compute_spl_voltage_` puts the swept-sine and tone LUTs on one scale — they agree to
within 0.01 dB on a synthetic system of known response.

Two implementation details matter:

- **Kirkeby regularization.** $H = Y\overline{X} / (|X|^2 + \lambda\,\overline{|X|^2})$ with
  $\lambda = 10^{-6}$. A plain $Y/X$ diverges outside the swept band where $|X| \to 0$.
- **1/12-octave power smoothing** of $|H|$. Single-bin estimates are unbiased but noisy;
  the band average costs no accuracy on a smooth response and cuts measurement-noise error
  roughly tenfold at 20 dB SNR.

Analysis frequencies outside the swept band carry no excitation energy and are dropped with
a log message rather than being filled with noise-floor readings.

### Distortion separation (not implemented)

The log sweep places all $N$-th harmonic distortion products at time
$\Delta t_N = -T \ln(N) / \ln(f_2/f_1)$ *before* the fundamental in the impulse response,
which permits time-gating them out. That is not implemented here, so `metrics.thd_db`,
`h2_db` and `h3_db` are `NaN` for swept-sine runs — MATLAB's `thd()` assumes a stationary
sinusoid and returns a meaningless number on a chirp.

---

## Performance & Best Practices

### Signal parameters

| Parameter | Range | Notes |
|-----------|-------|-------|
| **Duration** | 0.5–2 s | Longer = lower quantization noise, slower feedback |
| **Start freq** | 20–100 Hz | Limited by room/acoustic reverb |
| **Stop freq** | 10–20 kHz | Set to ~95% Nyquist to avoid aliasing |
| **Analysis points** | 20–100 | More points = smoother LUT but slower |

### Quality metrics

- **SNR** — reported at end of sweep; broadband 95th-percentile-over-median of the response spectrum
- **THD** — `NaN` for swept sine (see *Distortion separation* above); use a tone sweep when you need it
- **Peak-to-RMS ratio** — inherent 4 dB crest factor; avoid clipping
- **Repeatability** — compare with repeated 1-second runs; <0.5 dB variation expected

### When to use swept sine vs. other methods

| Scenario | Method | Reason |
|----------|--------|--------|
| **First setup** | Swept sine (1 s) | Fast, immediate feedback, reveals frequency response |
| **High precision** | Tone sweep (50 points) | Narrow windowing, peak-picking, distortion control |
| **Stimulus timing** | Clicked staircase | Direct pulse response, minimal latency |
| **Filter design** | Tone sweep LUT | FIR design requires dense frequency grid |
| **Field/portable** | Swept sine (2 s) | Single fast measurement, less affected by drift |

---

## Implementation details

### `stimgen.SweptSine` class

Inherits from `stimgen.StimType`, produces log-sine or linear chirps.

**Key properties:**
- `StartFrequency` (double, > 0, default 100 Hz)
- `StopFrequency` (double, > 0, default 20000 Hz)
- `ChirpType` (string, "log-sine" or "linear", default "log-sine")
- `Duration` (inherited from StimType)

**Methods:**
- `update_signal()` — generates waveform via `generate_log_sine_chirp_()` or `generate_linear_chirp_()`

### `Engine.calibrate_swept_sine()` method

```matlab
calibrate_swept_sine(obj, duration, freqs)
```

**Parameters:**
- `duration` (1×1 double, default 1 s) — chirp length
- `freqs` (1×N double, default []) — analysis frequencies; auto-fills if empty

**Behavior:**
- Creates a SweptSine stimulus and plays it through the adapter
- Records the response, stripping only trailing buffer padding
- Deconvolves excitation against response and samples the transfer function at each
  frequency point, dropping any that fall outside the swept band
- Builds a `swept_sine` struct in `CalibrationData` with fields:
  - `frequency` — analysis frequencies
  - `measurement` — measured RMS at each frequency
  - `spl_db` — computed SPL
  - `voltage` — normalized excitation voltage
  - `duration`, `chirp_type`, `start_freq`, `stop_freq` — metadata

### `Engine.compute_adjusted_voltage()` support

Once swept sine calibration is complete, you can compute required voltages:

```matlab
v = eng.compute_adjusted_voltage("swept_sine", 4000, 75);  % 4 kHz, 75 dB SPL
```

Uses MATLAB `makima` spline interpolation (shape-preserving, no overshoot) over the LUT.

---

## Troubleshooting

### Low SNR or noisy measurement

- **Increase duration** to 2 s (longer averaging window)
- **Increase ExcitationVoltage** (if not clipping)
- **Check mic placement** — should be at acoustic reference (usually ~30 cm from speaker)

### Distorted response

- **Reduce ExcitationVoltage** — avoid amplifier/driver saturation
- **Check acoustic environment** — room reflections or loudspeaker nonlinearity
- **Increase start frequency** (e.g., 200 Hz instead of 100 Hz) if low-frequency clipping
- Check `metrics.clipping_headroom`; `thd_db` is not available for swept sine

### Comparison with tone sweep shows discrepancies

- **Expected**: ±1–2 dB near measurement boundaries (Nyquist, very low frequencies)
- **Investigate if >3 dB:** Room reflections, microphone positioning, or nonlinear distortion at high levels
- **A large, systematic offset that grows with sweep duration** means the level is being
  read off the response spectrum rather than the transfer function — the failure mode
  described in *Why the level comes from the transfer function*. Any `.esgc` swept-sine
  data measured that way must be re-measured; it cannot be corrected after the fact,
  because the offset depends on sweep duration and on the analysis FFT length.

### Save/load .esgc files with swept sine

- Fully compatible with existing tone/click calibrations
- `compute_adjusted_voltage()` auto-selects the correct LUT based on `type` argument
- Mixed calibration (tone + swept sine) is valid; use whichever is most appropriate for your stimulus type

---

## References

1. **Chan, I.H.** (2010). "Swept Sine Chirps for Measuring Impulse Response." Stanford Research Systems.
   - Comprehensive theory and measurement validation
   - Log-sine vs. variable-speed chirps
   - Distortion separation via time-gating

2. **Farina, A.** (2000). "Simultaneous measurement of impulse response and distortion with a swept sine technique." *AES Convention, Paris.*
   - Pioneering work on log-sine distortion separation

3. **Müller, S. & Massarini, P.** (2001). "Transfer-Function Measurement with Sweeps." *J. Audio Eng. Soc.*, 49:6, 443–471.
   - Variable-speed chirps and group delay design
   - FFT analysis methodology
