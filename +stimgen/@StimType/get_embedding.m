function E = get_embedding(obj)
% E = get_embedding(obj)
% How a presenter embeds this stimulus in its ongoing background.
%
% A presenter that plays a background continuously renders
%
%   y(i) = G(i) .* B(i, theta(i)) + Signal(i - onset)
%
% and each stimulus supplies up to three per-presentation operators: a
% waveform ADDED to the background (this method's default: Signal itself --
% a tone in noise, clicks in noise), a GAIN envelope that multiplies it (AM,
% a silent gap) and a PHASE deviation of a tonal background (FM). The last
% two are what the stimgen.BackgroundModulation classes return; every other
% class adds.
%
% With Background = "None" the result is still valid: Mode "add" and an
% empty Background, i.e. the stimulus as it has always been presented.
%
% Returns:
%   E - struct:
%       Mode        "add" | "modulate"
%       Signal      (1,:) the additive waveform (zeros for a modulation)
%       Gain        (1,:) gain envelope over the stimulus, or []
%       Phase       (1,:) phase deviation in radians, starting at 0, or []
%       Background  struct from get_background, or []
%
% Describes the waveform currently in Signal (generating it first when there
% is none) and never advances the variant selection.
%
% See also: get_background, embedded_signal, stimgen.BackgroundModulation

if isempty(obj.Signal)
    obj.call_update_signal_with_variant_cycle_();
end
E = struct( ...
    'Mode',       "add", ...
    'Signal',     obj.Signal, ...
    'Gain',       [], ...
    'Phase',      [], ...
    'Background', []);
E.Background = obj.get_background();
end
