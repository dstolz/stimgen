function [y, t] = embedded_signal(obj, pre, post)
% [y, t] = embedded_signal(obj)
% [y, t] = embedded_signal(obj, pre, post)
% One presentation of this stimulus rendered in its ongoing background: the
% reference for the arithmetic a presenter performs.
%
%   y(i) = G(i) .* B(i, theta(i)) + add(i)
%
% with the background running from the first rendered sample (its sample
% index 0: the start of the noise loop, or a tone at zero phase), G the
% stimulus's gain envelope (1 outside it), theta its phase deviation (held at
% its final value afterwards, which keeps a frequency-modulated tone
% continuous), and add its Signal placed after `pre` seconds. A presenter's
% own render of the same presentation, with the same background offset, must
% reproduce this -- which is what its tests compare against.
%
% With Background = "None" this is Signal between `pre` and `post` seconds of
% silence.
%
% Parameters:
%   pre  - seconds of background before the stimulus (default 0)
%   post - seconds of background after it (default 0)
%
% Returns:
%   y - (1,:) double
%   t - (1,:) double time in seconds, 0 at the stimulus onset
%
% See also: get_embedding, audition_signal

if nargin < 2 || isempty(pre),  pre  = 0; end
if nargin < 3 || isempty(post), post = 0; end
if ~(isscalar(pre) && isscalar(post) && pre >= 0 && post >= 0 && isfinite(pre + post))
    error('stimgen:StimType:InvalidEmbedPadding', ...
        'pre and post are non-negative durations in seconds.');
end

E  = obj.get_embedding();
fs = double(obj.Fs);
n  = numel(E.Signal);
nPre  = round(pre  * fs);
nPost = round(post * fs);
N     = nPre + n + nPost;

t   = ((0:N-1) - nPre) ./ fs;
add = [zeros(1, nPre), double(E.Signal), zeros(1, nPost)];

B = E.Background;
if isempty(B)
    y = add;
    return
end

ev = nPre + (1:n);          % the stimulus's own samples
g  = ones(1, N);
if ~isempty(E.Gain)
    g(ev) = E.Gain;
end

i = 0:N-1;                  % background sample index
switch B.Type
    case "Noise"
        bg = B.Waveform(mod(i, numel(B.Waveform)) + 1);
    case "Tone"
        theta = zeros(1, N);
        if ~isempty(E.Phase)
            theta(ev)          = E.Phase;
            theta(ev(end)+1:N) = E.Phase(end);
        end
        % Cycles are reduced before the 2*pi, so the phase keeps its
        % precision however far into a run the sample is.
        bg = B.Amplitude .* sin(2*pi .* mod(B.Frequency .* i ./ fs, 1) + theta);
    otherwise
        error('stimgen:StimType:UnknownBackground', ...
            'Unknown background type "%s".', B.Type);
end

y = g .* bg + add;
end
