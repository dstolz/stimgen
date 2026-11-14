function B = get_background(obj)
% B = get_background(obj)
% The ongoing background this stimulus is embedded in, as a presenter needs
% it: a calibrated, seamlessly loopable noise segment, or a tone's frequency
% and amplitude. [] when Background is "None".
%
% Built by stimgen.util.background_source from the active combination's
% background settings and this stimulus's own calibration, so the level
% convention is the package's: a background at BackgroundLevel has the same
% rms dB SPL as a stimgen.Noise / stimgen.Tone at that SoundLevel.
%
% Nothing is cached on the object. background_source keeps a small memo
% keyed by B.Key, which is recomputed from the settings on every call -- a
% copy() of a stimulus carries none of its listeners, so a cache that relied
% on a listener to clear it would go stale there.
%
% Returns:
%   B - [] or struct (see stimgen.util.background_source):
%       Type        "Noise" | "Tone"
%       Key         text identical for two stimuli that share a background
%       Fs, Level, Calibrated, Normalization
%       Waveform    (1,:) double, the loop (Noise); [] for a Tone
%       Frequency, Amplitude   the tone (Tone); NaN for Noise
%       HighPass, LowPass, LoopDuration, Seed, Crossfade, Rms, Peak
%
% Example:
%   t = stimgen.Tone('Frequency', 8000, 'Background', "Noise", 'BackgroundLevel', 50);
%   B = t.get_background();
%
% See also: get_embedding, embedded_signal, stimgen.util.background_source

B = [];
if ~obj.supports_background_() || obj.Background == "None"
    return
end
B = stimgen.util.background_source(obj.background_spec_(), obj.Calibration);
end
