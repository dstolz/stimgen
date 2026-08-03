function obj = preset(name)
% obj = stimgen.Patch.preset(name)
% Build a named example patch.
%
% These are ordinary patches with no special status: each one is just a few
% add_node / add_connection calls, and every one can be taken apart and
% rewired in the editor. Several reproduce a monolithic stimulus class and are
% named in stimgen.Patch.preset_names with the class they correspond to.
%
% See also stimgen.Patch.preset_names.

name  = string(name);
names = stimgen.Patch.preset_names();
if ~any(names == name)
    error('stimgen:Patch:UnknownPreset', ...
        'Unknown preset "%s". Available: %s.', name, strjoin(names, ', '));
end

obj = stimgen.Patch;
obj.remove_node("Osc1");   % drop the default single-oscillator graph

switch name

    case "AMTone"
        obj.DisplayName = 'AM Tone';
        obj.Duration    = 1;
        obj.add_node("Osc1", "Oscillator", Frequency = 4000);
        obj.add_node("LFO1", "Oscillator", Frequency = 10, Phase = -90);
        obj.add_connection("LFO1", "Osc1", "Amplitude", Mode = "AM", Depth = 1);
        obj.OutputNode = "Osc1";

    case "FMTone"
        obj.DisplayName = 'FM Tone';
        obj.Duration    = 1;
        obj.add_node("Osc1", "Oscillator", Frequency = 4000);
        obj.add_node("LFO1", "Oscillator", Frequency = 10);
        % Depth is in the target's units, so this is a 1000 Hz peak deviation.
        obj.add_connection("LFO1", "Osc1", "Frequency", Mode = "Add", Depth = 1000);
        obj.OutputNode = "Osc1";

    case "PulsedTone"
        obj.DisplayName = 'Pulsed Tone';
        obj.Duration    = 1;
        obj.add_node("Osc1",  "Oscillator", Frequency = 4000);
        obj.add_node("Pulse1","PulseTrain", Rate = 10, Width = 0.02, Shape = "cos2");
        obj.add_connection("Pulse1", "Osc1", "Amplitude", Mode = "AM", Depth = 1);
        obj.OutputNode = "Osc1";

    case "Tremolo"
        obj.DisplayName = 'Tremolo Tone';
        obj.Duration    = 1;
        obj.add_node("Osc1", "Oscillator", Frequency = 1000);
        obj.add_node("LFO1", "Oscillator", Frequency = 5, Phase = -90);
        obj.add_connection("LFO1", "Osc1", "Amplitude", Mode = "AM", Depth = 0.3);
        obj.OutputNode = "Osc1";

    case "AMNoise"
        obj.DisplayName    = 'AM Noise';
        obj.Duration       = 1;
        obj.LevelReference = "rms";
        obj.add_node("Noise1", "NoiseSource", HighPass = 500, LowPass = 20000);
        obj.add_node("LFO1",   "Oscillator",  Frequency = 5, Phase = 180);
        obj.add_connection("LFO1", "Noise1", "Amplitude", ...
            Mode = "AM", Depth = 1, PowerCompensate = true);
        obj.OutputNode = "Noise1";

    case {"RampedNoise", "DampedNoise"}
        isRamped = (name == "RampedNoise");
        if isRamped
            obj.DisplayName = 'Ramped Noise';
            z = -0.4;
        else
            obj.DisplayName = 'Damped Noise';
            z = 0.4;
        end
        obj.Duration       = 1;
        obj.LevelReference = "rms";
        obj.add_node("Noise1", "NoiseSource", HighPass = 500, LowPass = 20000);
        obj.add_node("Env1",   "PulseTrain",  Rate = 5, Shape = "ramped", Z = z);
        obj.add_connection("Env1", "Noise1", "Amplitude", Mode = "AM", Depth = 1);
        obj.OutputNode = "Noise1";

    case "GatedNoise"
        obj.DisplayName    = 'Gated Noise';
        obj.Duration       = 1;
        obj.LevelReference = "rms";
        obj.add_node("Noise1", "NoiseSource", HighPass = 500, LowPass = 20000);
        obj.add_node("Gate1",  "PulseTrain",  Rate = 4, Width = 0.1, Shape = "cos2");
        obj.add_connection("Gate1", "Noise1", "Amplitude", Mode = "AM", Depth = 1);
        obj.OutputNode = "Noise1";

    case "ClickTrain"
        obj.DisplayName = 'Click Train';
        obj.Duration    = 1;
        obj.ApplyWindow = false;
        obj.WindowFcn   = "";
        obj.add_node("Pulse1", "PulseTrain", ...
            Rate = 10, Width = 20e-6, Shape = "rect", Polarity = 1);
        obj.OutputNode = "Pulse1";

    case "Chirp"
        obj.DisplayName = 'Chirp';
        obj.Duration    = 1;
        obj.add_node("Sweep1", "Sweep", ...
            StartFrequency = 100, StopFrequency = 20000, ChirpType = "log-sine");
        obj.OutputNode = "Sweep1";

    case "TwoTone"
        obj.DisplayName = 'Two-Tone Complex';
        obj.Duration    = 1;
        obj.add_node("Osc1", "Oscillator", Frequency = 1000);
        obj.add_node("Osc2", "Oscillator", Frequency = 1500);
        obj.add_node("Mix1", "Mixer", Gain1 = 0.5, Gain2 = 0.5);
        obj.add_connection("Osc1", "Mix1", "In1", Mode = "Direct");
        obj.add_connection("Osc2", "Mix1", "In2", Mode = "Direct");
        obj.OutputNode = "Mix1";

    case "NoiseInNoise"
        obj.DisplayName    = 'Modulated Band in Noise';
        obj.Duration       = 1;
        obj.LevelReference = "rms";
        obj.add_node("Band1",  "NoiseSource", HighPass = 3000, LowPass = 4000, Seed = 1);
        obj.add_node("Wide1",  "NoiseSource", HighPass = 500,  LowPass = 20000, Seed = 2);
        obj.add_node("LFO1",   "Oscillator",  Frequency = 8, Phase = 180);
        obj.add_node("Mix1",   "Mixer",       Gain1 = 1, Gain2 = 0.5);
        obj.add_connection("LFO1",  "Band1", "Amplitude", Mode = "AM", Depth = 1);
        obj.add_connection("Wide1", "Mix1",  "In1", Mode = "Direct");
        obj.add_connection("Band1", "Mix1",  "In2", Mode = "Direct");
        obj.OutputNode = "Mix1";

end

% Lay the graph out by depth so a preset opens in the editor already readable.
obj.Graph = stimgen.Patch.auto_layout_(obj.Graph);
end
