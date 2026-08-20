function s = describe(obj)
% describe(obj)
% s = describe(obj)
% The last spot check in words. Prints when nothing takes the output.
%
% The same reduction the result table shows, as text, so a check can be pasted
% into a lab notebook or logged from a script that never opened a window.
%
% Returns:
%   s - (1,1) string, the full report

if isempty(fieldnames(obj.Results))
    s = "No spot check has been run yet.";
    if nargout == 0
        fprintf('%s\n', s);
        clear s
    end
    return
end

r = obj.Results;
L = string.empty(0, 1);

L(end+1) = "Spot check — " + r.stimulus.label;
L(end+1) = repmat('-', 1, 64);
L(end+1) = sprintf('  stimulus       %s, %.1f ms at %.7g Hz', ...
    short_class_(r.stimulus.class), r.stimulus.duration_s * 1e3, r.stimulus.fs);
if strlength(r.stimulus.file) > 0
    L(end+1) = sprintf('  from           %s', r.stimulus.file);
end
L(end+1) = sprintf('  parameters     %s', r.stimulus.parameters);
if r.stimulus.variant_info.NumCombinations > 1
    L(end+1) = sprintf('  variant        %d of %d', ...
        r.stimulus.variant_info.ActiveIndex, r.stimulus.variant_info.NumCombinations);
end
L(end+1) = sprintf('  measured as    %s', r.stimulus.level_reference);
L(end+1) = "";

L(end+1) = "Level";
if isfinite(r.measured.level_error_db)
    L(end+1) = sprintf('  requested      %.1f dB SPL', r.stimulus.requested_level_db);
    L(end+1) = sprintf('  measured       %.1f dB SPL', r.measured.level_db_spl);
    L(end+1) = sprintf('  error          %+.2f dB', r.measured.level_error_db);
else
    L(end+1) = sprintf('  measured       %.1f dB SPL', r.measured.level_db_spl);
    L(end+1) = "  requested      not comparable (see warnings)";
end
L(end+1) = sprintf('  noise floor    %s', fmt_(r.measured.noise_db_spl, '%.1f dB SPL'));
L(end+1) = sprintf('  SNR            %s', fmt_(r.measured.snr_db, '%.1f dB'));
L(end+1) = "";

L(end+1) = "Recording";
L(end+1) = sprintf('  rms / peak     %.4g V / %.4g V', ...
    r.measured.rms_v, r.measured.peak_v);
L(end+1) = sprintf('  crest factor   %s', fmt_(r.measured.crest_factor_db, '%.1f dB'));
L(end+1) = sprintf('  fundamental    %s', fmt_(r.measured.fundamental_hz, '%.4g Hz'));
L(end+1) = sprintf('  THD            %s', fmt_(r.measured.thd_percent, '%.3f %%'));
L(end+1) = sprintf('  conduction     %.2f ms', r.measured.delay_s * 1e3);
if r.capture.repeats > 1
    L(end+1) = sprintf('  acquisitions   %d averaged (delay sd %.3f ms)', ...
        r.capture.repeats, r.capture.delay_sd_s * 1e3);
end
L(end+1) = "";

L(end+1) = "Stimulus, for comparison";
L(end+1) = sprintf('  rms / peak     %.4g / %.4g', ...
    r.stimulus_metrics.RMS, r.stimulus_metrics.Peak);
L(end+1) = sprintf('  crest factor   %s', fmt_(r.stimulus_metrics.CrestFactorDb, '%.1f dB'));
L(end+1) = sprintf('  fundamental    %s', fmt_(r.stimulus_metrics.FundamentalHz, '%.4g Hz'));
L(end+1) = sprintf('  THD            %s', fmt_(r.stimulus_metrics.ThdPercent, '%.3f %%'));

if ~isempty(r.warnings)
    L(end+1) = "";
    L(end+1) = "Warnings";
    for k = 1:numel(r.warnings)
        L(end+1) = "  - " + r.warnings(k); %#ok<AGROW>
    end
end

L(end+1) = "";
L(end+1) = sprintf('  measured on    %s', string(r.measuredOn, 'yyyy-MM-dd HH:mm:ss'));

s = strjoin(L, newline);

if nargout == 0
    fprintf('%s\n', s);
    clear s
end
end % describe


% =========================================================================

function t = fmt_(v, spec)
% t = fmt_(v, spec) - Format a scalar, rendering a missing value as "n/a".
if isempty(v) || ~isscalar(v) || ~isfinite(v)
    t = "n/a";
else
    t = string(sprintf(spec, v));
end
end


function n = short_class_(fullName)
% n = short_class_(fullName) - Class name without its package prefix.
parts = split(string(fullName), ".");
n = parts(end);
end
