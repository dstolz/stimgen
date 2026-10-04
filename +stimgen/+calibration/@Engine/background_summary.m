function s = background_summary(r)
% s = stimgen.calibration.Engine.background_summary(r)
% One-line status-bar summary of a background capture.
s = sprintf('Background: %.1f dB SPL (%.1f dB(A)), loudest band %.0f Hz at %.1f dB SPL.', ...
    r.spl_db, r.spl_dba, r.worst_band.frequency, r.worst_band.level_db);
if ~isempty(r.flags)
    s = sprintf('%s %d finding(s) -- see the report.', s, numel(r.flags));
end
end
