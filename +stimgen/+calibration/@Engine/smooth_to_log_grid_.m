function out = smooth_to_log_grid_(~, fax, vals, grid, fracOct, mode)
% out = smooth_to_log_grid_(obj, fax, vals, grid, fracOct, mode)
% Fractional-octave average of a linearly spaced spectrum onto a log grid.
%
% Serves two purposes at once. It suppresses the bin-to-bin measurement noise
% that makes raw phase and group delay unreadable, and it collapses a
% half-million-bin FFT onto a few hundred points so the curves can be stored in
% an .esgc without dominating the file.
%
% Parameters:
%   fax     - (:,1) double source frequency axis in Hz, ascending
%   vals    - (:,1) double or complex values on that axis
%   grid    - (:,1) double target frequencies in Hz
%   fracOct - (1,1) double averaging bandwidth denominator, e.g. 12 for 1/12 oct
%   mode    - "power" root-mean-square of magnitude (use for |H|)
%             "linear" plain mean (use for unwrapped phase, group delay)
%
% Returns:
%   out - (:,1) double averaged values, NaN where the grid point falls outside
%         the source axis

r = 2 ^ (1 / (2 * fracOct));
fax = fax(:);
vals = vals(:);
grid = grid(:);
n = numel(fax);
out = nan(numel(grid), 1);

% Band edges by binary search rather than a mask per grid point: the source
% axis runs to hundreds of thousands of bins and the masked form costs a full
% pass over it for every one of the few hundred grid points.
lo = discretize(grid / r, fax);
hi = discretize(grid * r, fax);
lo(isnan(lo) & grid / r < fax(1)) = 1;
hi(isnan(hi) & grid * r > fax(end)) = n;

for i = 1:numel(grid)
    a = lo(i);
    b = hi(i);
    if isnan(a) || isnan(b)
        continue   % grid point lies entirely outside the source axis
    end
    if b < a
        % Averaging band narrower than one FFT bin: take the nearest bin.
        [~, k] = min(abs(fax - grid(i)));
        a = k;
        b = k;
    end
    switch mode
        case "power"
            out(i) = sqrt(mean(abs(vals(a:b)) .^ 2));
        otherwise
            out(i) = mean(vals(a:b), 'omitnan');
    end
end
end
