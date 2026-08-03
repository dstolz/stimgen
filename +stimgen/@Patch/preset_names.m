function [names, descriptions] = preset_names()
% [names, descriptions] = stimgen.Patch.preset_names()
% Named example patches available through stimgen.Patch.preset.

names = [ ...
    "AMTone", "FMTone", "PulsedTone", "Tremolo", ...
    "AMNoise", "RampedNoise", "DampedNoise", "GatedNoise", ...
    "ClickTrain", "Chirp", "TwoTone", "NoiseInNoise"];

descriptions = [ ...
    "Sinusoidally amplitude-modulated tone"
    "Sinusoidally frequency-modulated tone"
    "Tone gated by a rectangular pulse train"
    "Tone with a shallow, slow amplitude modulation"
    "Amplitude-modulated band-limited noise (cf. stimgen.AMnoise)"
    "Noise with a ramped attack envelope (cf. stimgen.AttackModNoise, Z < 0)"
    "Noise with a damped attack envelope (cf. stimgen.AttackModNoise, Z > 0)"
    "Noise gated into bursts by a pulse train"
    "Rectangular click train (cf. stimgen.ClickTrain)"
    "Log-sine frequency sweep (cf. stimgen.SweptSine)"
    "Two simultaneous tones summed in a Mixer"
    "A slow-modulated noise band added to a steady wideband noise"]';
end
