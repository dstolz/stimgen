function g = harmonic_geometry_(~, sweep, maxOrder)
% g = harmonic_geometry_(obj, sweep)
% g = harmonic_geometry_(obj, sweep, maxOrder)
% Where the harmonic distortion products land in the circular impulse response
% of a log sweep, and where the linear response therefore has to stop.
%
% A log sweep spends equal time in every octave, so the N-th harmonic response
% arrives a fixed interval
%
%   dt_N = T * ln(N) / ln(f2/f1)
%
% *ahead of* the linear impulse response, independent of frequency. Circular
% deconvolution wraps those arrivals to the tail of the buffer, at index
% nfft - dt_N*fs.
%
% dt_N grows with N, so higher orders sit at *lower* indices: scanning forward
% from the linear response the first product met is the highest order and H2 is
% the last one before the wrap point. A window meant to contain only the linear
% response must therefore stop short of the whole cluster, not short of H2 --
% cutting at H2 excludes H2 alone and leaves every higher order inside, where
% the burst energy seeds the Lundeby noise estimate and flattens the Schroeder
% decay curve. That is what linear_limit_s is for.
%
% Both the harmonic gating and the linear-window cut read their geometry from
% here so the two cannot disagree about where the cluster begins.
%
% Parameters:
%   sweep    - struct with fields duration, start_freq, stop_freq
%   maxOrder - (1,1) double highest harmonic accounted for (default 5)
%
% Returns:
%   g - struct with fields
%       order          (:,1) harmonic orders, 2..maxOrder
%       dt_s           (:,1) arrival ahead of the linear response
%       edge_before_s  (:,1) gate edge further back in time, midway to N+1
%       edge_after_s   (:,1) gate edge towards the linear response
%       linear_limit_s how far past the linear response a window may extend
%                      before it reaches the cluster; the outermost gate edge
%       valid          false when the sweep spec cannot support the geometry

if nargin < 3 || isempty(maxOrder), maxOrder = 5; end

g = struct('order', zeros(0,1), 'dt_s', zeros(0,1), ...
           'edge_before_s', zeros(0,1), 'edge_after_s', zeros(0,1), ...
           'linear_limit_s', nan, 'valid', false);

if ~(sweep.duration > 0) || ~(sweep.start_freq > 0) || ...
        ~(sweep.stop_freq > sweep.start_freq) || maxOrder < 2
    return
end

dt = @(N) sweep.duration .* log(N) ./ log(sweep.stop_freq / sweep.start_freq);

g.order          = (2:maxOrder)';
g.dt_s           = dt(g.order);
g.edge_before_s  = (dt(g.order) + dt(g.order + 1)) / 2;   % further back in time
g.edge_after_s   = (dt(g.order) + dt(g.order - 1)) / 2;   % towards the linear IR
g.linear_limit_s = g.edge_before_s(end);
g.valid          = true;
end
