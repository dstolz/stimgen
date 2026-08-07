function w = weighting_db(f, type)
% w = weighting_db(f, type)
% Standard acoustic frequency weighting, in dB, at the given frequencies.
%
% Evaluated directly from the pole/zero forms of IEC 61672-1 (A, C) and
% IEC 60651 (B, D) so the package does not gain an Audio Toolbox dependency
% for four analytic curves. Each is normalized numerically to 0 dB at 1 kHz,
% the frequency all of them are defined to pass through, rather than by the
% rounded constants the standards tabulate.
%
% What each is for: A tracks the ear at conversational levels and is what a
% sound level meter reports by default; C is nearly flat through the audio
% band and is used for peak and high-level measurements; B is the disused
% middle ground between them; D was written for aircraft noise and peaks
% around 6 kHz.
%
% Parameters:
%   f    - frequencies in Hz; any size, negatives taken as their magnitude
%   type - "A" | "B" | "C" | "D" | "Z" (Z is flat, i.e. no weighting)
%
% Returns:
%   w - weighting in dB, same size as f. The response is floored at realmin
%       before the log, so f = 0 returns a large negative number rather than
%       -Inf.
%
% Example:
%   stimgen.util.weighting_db([20 1000 10000], "A")   % -50.4  0.0  -2.5
%
% See also: stimgen.calibration.LiveMonitor
arguments
    f double
    type (1,1) string {mustBeMember(type, ["A", "B", "C", "D", "Z"])}
end

if type == "Z"
    w = zeros(size(f));
    return
end

w = reshape(response_db_(abs(double(f(:))), type), size(f)) - response_db_(1000, type);
end

% ------------------------------------------------------------------------ %
function r = response_db_(f, type)
% Unnormalized magnitude response of the weighting network, in dB. Constant
% gain factors are omitted throughout: the caller divides them out again by
% referencing every curve to its own value at 1 kHz.
f2 = f .^ 2;
switch type
    case "A"
        num = 12194 ^ 2 .* f2 .^ 2;
        den = (f2 + 20.6 ^ 2) .* sqrt((f2 + 107.7 ^ 2) .* (f2 + 737.9 ^ 2)) .* (f2 + 12194 ^ 2);
    case "B"
        num = 12194 ^ 2 .* f2 .* f;
        den = (f2 + 20.6 ^ 2) .* sqrt(f2 + 158.5 ^ 2) .* (f2 + 12194 ^ 2);
    case "C"
        num = 12194 ^ 2 .* f2;
        den = (f2 + 20.6 ^ 2) .* (f2 + 12194 ^ 2);
    case "D"
        h   = ((1037918.48 - f2) .^ 2 + 1080768.16 .* f2) ./ ...
              ((9837328 - f2) .^ 2 + 11723776 .* f2);
        num = f .* sqrt(h);
        den = sqrt((f2 + 79919.29) .* (f2 + 1345600));
end
r = 20 * log10(max(num ./ den, realmin));
end
