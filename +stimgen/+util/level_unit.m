function u = level_unit(mode, electrical)
% u = stimgen.util.level_unit(mode)
% u = stimgen.util.level_unit(mode, electrical)
% The unit a level measured as mode is written in, so a peak-derived level
% says so wherever it is shown.
%
% A click table is built from the peak of the recorded click, turned into the
% rms of a sine with the same peak (divided by sqrt 2) before it becomes a
% level -- see Engine/compute_spl_voltage_ and stimgen.util.level_as_calibrated.
% That is peak-equivalent SPL, and a 60 dB peSPL click is not as loud as a
% 60 dB SPL tone by any rms reckoning: a click train is mostly silence. Every
% plot, table and status line that shows such a level labels it through here
% rather than hard-coding "dB SPL", so the peak and rms scales cannot be
% mistaken for one another on screen.
%
% Parameters:
%   mode       - (1,1) string measurement mode: "peak" | "rms" | "specfreq"
%                (as stimgen.util.level_request and Engine/measure_ name them)
%   electrical - (1,1) logical; true for a level in dB re 1 V rather than in
%                dB re 20 uPa (default false)
%
% Returns:
%   u - (1,:) char: 'dB peSPL' or 'dB SPL'; with electrical,
%       'dB re 1 V peak-equiv.' or 'dB re 1 V'
%
% Example:
%   ylabel(ax, sprintf('level (%s)', stimgen.util.level_unit("peak")));
%
% See also: stimgen.util.level_request, stimgen.util.level_as_calibrated
arguments
    mode       (1,1) string
    electrical (1,1) logical = false
end

peak = mode == "peak";
if electrical
    if peak
        u = 'dB re 1 V peak-equiv.';
    else
        u = 'dB re 1 V';
    end
elseif peak
    u = 'dB peSPL';
else
    u = 'dB SPL';
end
end
