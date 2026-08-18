# Background noise reads high with a 1/4" microphone: instrument floor, not room noise

<!-- summary: Why a 1/4" measurement mic reports ~10 dB more background than a 1/2" sound level meter, and when the panel's broadband figure is the instrument rather than the room -->

*2026-08-18. From a rig measurement with a PCB 378C01 on an RZ6; kept because the
question will recur every time the background panel is compared against a sound
level meter.*

## Observation

The calibration GUI reported a background of 49.2 dB SPL / 43.5 dB(A), while a
B&K Type 2232 sound level meter in the same location read **< 34 dB(A)**. Both
instruments were referenced to 94 dB SPL at 1 kHz (CAL150) and agreed there.

## Explanation

The reference measurement calibrates **scale**, not **noise**. At 94 dB SPL both
chains have enormous SNR; near the floor they diverge, because each instrument
bottoms out at its own microphone's inherent noise:

- PCB 378C01 (1/4", 1.98 mV/Pa): inherent noise spec **<= 40.5 dB(A)**. 1/4"
  capsules trade noise floor for bandwidth and max SPL.
- The 2232 carries a 1/2" capsule with a self-noise around 15-20 dB(A), so it
  measures the room.

The arithmetic closes: mic floor ~40.5 dB(A) power-summed with a real room at
~33 dB(A) gives ~41.2 dB(A); the RZ6's input-referred noise and the analysis
bandwidth (the engine integrates to Nyquist, ~49 kHz on TDT hardware, while the
mic spec and the SLM stop near 20 kHz) account for the rest of the 43.5.

The spectral signature that gives it away: the 1/3-octave curve is flat-to-
rising with frequency out past 20 kHz — white electrical/thermal noise — where a
genuinely quiet room is dominated by low-frequency HVAC rumble that A-weighting
removes.

Sensitivity cross-check for the same rig: 1.98 mV/Pa x 55 dB RZ6 gain (x562.3)
predicts 1.113 V/Pa at the ADC; the CAL150-derived value was 1.197 V/Pa, 0.6 dB
high — inside the mic's +/-1.5 dB tolerance.

## Practical consequences

- A broadband background near the mic's inherent-noise spec is
  **instrument-limited**: the room may be substantially quieter than the number.
  Verify with an SLM, or re-measure with a 1/2" low-noise mic.
- Narrowband calibration (tones, sweeps) is unaffected — it rides on the per-bin
  spectrum floor (14 dB SPL in this measurement), not the broadband figure.
- Read "headroom to normative" accordingly: with the floor instrument-limited it
  understates the real acoustic headroom (here 11 dB reported vs ~26 dB against
  the actual room).
- To split the mic's contribution from the back end, replace the mic with a
  terminated plug and re-measure: what remains is the RZ6 + cabling floor.
