function s = background_report(r)
% s = stimgen.calibration.Engine.background_report(r)
% Full text of a background capture, for the dialog shown after a run.
%
% The plots carry the shape of the noise; this carries the numbers that are
% awkward to read off a curve -- the broadband levels, the quietest and
% loudest bands, the tonal components and what they line up with, and whatever
% the analysis flagged as worth acting on.
lines = {};
lines{end+1} = sprintf('%g s x %d record(s) at %g Hz, %s', ...
    round(r.duration_s, 2), r.repeat_count, r.fs, ...
    char(datetime(r.measuredOn, Format='dd-MMM-yyyy HH:mm')));
lines{end+1} = '';
lines{end+1} = sprintf('Broadband        %.1f dB SPL   |   A-weighted  %.1f dB(A)', ...
    r.spl_db, r.spl_dba);
lines{end+1} = sprintf('Below normative  %.1f dB (normative %g dB SPL)', ...
    r.headroom_to_normative_db, r.normative_value_db);

if r.repeat_count > 1
    lines{end+1} = sprintf('Across records   %.1f dB spread, SD %.2f dB (%s)', ...
        r.range_db, r.sd_db, steadiness_(r.stable));
end
lines{end+1} = sprintf('Input            peak %.4f V, %.1f dB below full scale, crest %.0f dB', ...
    r.peak_v, r.headroom_db, r.crest_factor_db);

lines{end+1} = '';
lines{end+1} = sprintf('1/%d-octave bands (%d):', r.bands.fraction, numel(r.bands.frequency));
if isempty(r.bands.frequency)
    lines{end+1} = '  none resolvable at this duration and sample rate';
else
    [~, iHi] = max(r.bands.level_db);
    [~, iLo] = min(r.bands.level_db);
    lines{end+1} = sprintf('  loudest   %6.0f Hz   %.1f dB SPL', ...
        r.bands.frequency(iHi), r.bands.level_db(iHi));
    lines{end+1} = sprintf('  quietest  %6.0f Hz   %.1f dB SPL', ...
        r.bands.frequency(iLo), r.bands.level_db(iLo));
    lines{end+1} = sprintf('  span      %6.0f-%.0f Hz', ...
        r.bands.frequency(1), r.bands.frequency(end));
end

lines{end+1} = '';
if isempty(r.peaks.frequency)
    lines{end+1} = sprintf('Tonal components: none more than %g dB above the local floor.', ...
        r.tonal_prominence_db);
else
    lines{end+1} = sprintf('Tonal components (>= %g dB above the local floor):', ...
        r.tonal_prominence_db);
    for k = 1:numel(r.peaks.frequency)
        lines{end+1} = sprintf('  %7.1f Hz   %.1f dB SPL   (+%.0f dB)', ...
            r.peaks.frequency(k), r.peaks.level_db(k), r.peaks.prominence_db(k));
    end
    if isfinite(r.mains.frequency)
        lines{end+1} = sprintf('  %d of these are %g Hz mains harmonics, %.1f dB SPL combined.', ...
            r.mains.n_harmonics, r.mains.frequency, r.mains.level_db);
    end
end

if ~isempty(r.flags)
    lines{end+1} = '';
    lines{end+1} = 'Findings:';
    for k = 1:numel(r.flags)
        lines{end+1} = sprintf('  - %s', r.flags(k));
    end
end

s = strjoin(string(lines), newline);
end


function s = steadiness_(tf)
if tf
    s = 'steady';
else
    s = 'not steady';
end
end
