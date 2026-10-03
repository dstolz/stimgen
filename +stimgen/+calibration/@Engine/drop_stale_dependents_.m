function cd = drop_stale_dependents_(obj, cd, table) %#ok<INUSL>
% cd = drop_stale_dependents_(obj, cd, table)
% Remove what was derived from the previous version of a table that a sweep
% is about to replace.
%
% A test record or an equalizer describes the table it was made from. Left in
% place after a re-sweep, toneTest/clickTest would vouch for a table nobody
% tested, and the filter would equalize against a response that is no longer
% the stored one while filterDesign still names that table as its source.
% Each is dropped only when it names this table: a tone sweep leaves a filter
% designed from the swept sine table alone.
%
% Parameters:
%   cd    - CalibrationData struct about to be committed (from commit_cal_data_)
%   table - "tone" | "click" | "swept_sine", the table being replaced
%
% Returns:
%   cd    - the same struct with the stale dependents removed
table = string(table);
dropped = strings(1, 0);

if table == "click"
    testField = "clickTest";
    testSource = "click";
else
    testField = "toneTest";
    testSource = "";
    if isfield(cd, 'toneTest') && isstruct(cd.toneTest) && isfield(cd.toneTest, 'lut_source')
        testSource = string(cd.toneTest.lut_source);
    end
end
if isfield(cd, testField) && (table == "click" || testSource == table)
    cd = stimgen.calibration.Engine.rmfield_safe_(cd, testField);
    dropped(end+1) = testField;
end

if table ~= "click" && isfield(cd, 'filter') && ~isempty(cd.filter) ...
        && isfield(cd, 'filterSource') && string(cd.filterSource) == table
    cd.filter = [];
    cd.filterGrpDelay = 0;
    for f = ["filterSource", "filterDesign", "filterTest"]
        cd = stimgen.calibration.Engine.rmfield_safe_(cd, f);
    end
    dropped(end+1) = "filter";
    stimgen.util.vprintf(0, 1, ...
        ['The equalization filter was designed from the previous %s table and ' ...
         'has been removed with it. Run Design Filter again to equalize ' ...
         'against the new table.'], table);
end

if ~isempty(dropped)
    stimgen.util.vprintf(1, 'Re-sweep of the %s table cleared: %s', ...
        table, strjoin(dropped, ', '));
end
end
