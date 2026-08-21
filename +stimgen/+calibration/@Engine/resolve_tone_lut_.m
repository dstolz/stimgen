function [name, lut] = resolve_tone_lut_(obj)
% [name, lut] = resolve_tone_lut_(obj)
% Which lookup table serves tone lookups, and its contents.
%
% ToneLutSource redirects tone lookups to the swept sine table -- both are on
% the same SPL/voltage scale -- falling back to the direct tone table when no
% sweep has been run, so setting the source ahead of the measurement is
% harmless. This is the one definition of that choice: compute_adjusted_voltage
% scales stimuli through it and test_tones verifies it, and a second copy of
% the rule would let the test check a table nothing plays through.
%
% A redirect in force is announced in red, because it substitutes one measured
% table for another underneath every tone (and every "filter" lookup anchored
% to tones) with nothing in the stimulus, the bank, or the recording to say so.
% It is announced from HERE for the same reason the rule lives here: the notice
% has to cover playback, refinement and testing alike, and a copy per caller is
% a copy that goes stale. Latched, so a table consulted per variant does not
% print per variant -- loud once, then debug-level -- and re-armed by
% set.ToneLutSource, so toggling the source announces itself again.
%
% Returns:
%   name - "tone" | "swept_sine", the table lookups resolve to. Named even
%          when absent, so a caller can report which table it wanted.
%   lut  - the table struct, or [] when it does not exist

name = "tone";
lut  = [];

C = obj.CalibrationData;
if ~isstruct(C) || isempty(C)
    return
end

if obj.ToneLutSource == "swept_sine"
    if isfield(C, 'swept_sine') && ~isempty(C.swept_sine)
        name = "swept_sine";
        if obj.ToneLutRedirectWarned_
            stimgen.util.vprintf(2, 1, ...
                'Tone lookups still redirected to the swept sine LUT (ToneLutSource = "swept_sine").');
        else
            stimgen.util.vprintf(0, 1, ...
                ['Tone lookups are being served by the SWEPT SINE calibration, not the direct ' ...
                 'tone LUT (ToneLutSource = "swept_sine"). Every tone -- and every filter-type ' ...
                 'stimulus anchored to the tone table -- is scaled by the swept sine voltages.']);
            obj.ToneLutRedirectWarned_ = true;
        end
    else
        stimgen.util.vprintf(2, ...
            'ToneLutSource is "swept_sine" but no swept sine calibration exists; using the tone LUT.');
    end
end

if isfield(C, name) && ~isempty(C.(name))
    lut = C.(name);
end
end
