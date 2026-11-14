function proceed = confirm_run_(obj)
% proceed = confirm_run_() - Say what a run will do that may be unexpected; allow a cancel.
% Called by Run after the hardware is resolved and before the
% timer exists. Each finding is logged; when there is any, one
% confirmation dialog lists them all and Cancel (the default)
% abandons the run. Nothing is changed to make a finding go
% away -- in particular a run always presents exactly the Reps
% each bank item asks for.
%
% Returns:
%   proceed - false when the operator cancelled
issues = strings(0, 1);

% A host is attached but the run would drive nothing. Without a
% host the player is offline by construction and says so in its
% status bar, so that case is not asked about.
reason = obj.hardware_unavailable_reason_();
if strlength(reason) > 0
    stimgen.util.vprintf(0, 1, 'StimPlayer: Run has no hardware output: %s', char(reason));
    issues(end+1, 1) = "No hardware output. " + reason + newline + ...
        "This would be a dry run: the timer runs and the presentation log fills, " + ...
        "but nothing is played. A hardware Run needs " + ...
        strjoin(string(obj.RequiredParams_), ", ") + ".";
end

uneven = obj.uneven_reps_report_();
if ~isempty(uneven)
    issues(end+1, 1) = "Reps does not divide evenly over the variant combinations:" + newline + ...
        strjoin(("  - " + uneven).', newline) + newline + ...
        "A run presents exactly Reps per bank item, so these combinations will be " + ...
        "presented unequal numbers of times. Set Reps to a multiple of the " + ...
        "combination count for equal counts.";
end

% ISI runs from one onset to the next, so a stimulus longer than the
% shortest ISI is still playing when the next presentation is triggered.
% Advisory: if the comparison itself fails, that is logged and the run is
% not held up by it.
try
    late = obj.outlasting_isi_report_();
catch ME
    late = strings(0, 1);
    stimgen.util.vprintf(0, 1, 'StimPlayer: could not compare stimulus durations with the ISI: %s', ...
        ME.message);
end
if ~isempty(late)
    issues(end+1, 1) = "These bank items are longer than the shortest ISI (" + ...
        string(sprintf('%.6g', 1e3 * obj.ISI(1))) + " ms):" + newline + ...
        strjoin(("  - " + late).', newline) + newline + ...
        "ISI is measured from one onset to the next, so the next presentation would " + ...
        "be triggered while such a stimulus is still playing. Lengthen ISI or shorten " + ...
        "the stimulus.";
end

% A Run plays each stimulus's Signal on its own. A bank item set to be
% embedded in an ongoing background would be presented WITHOUT it, and the
% presentation log would not say so.
nBg = obj.count_background_items_();
if nBg > 0
    stimgen.util.vprintf(0, 1, ['StimPlayer: %d bank item(s) have a Background, ' ...
        'which a StimPlayer Run does not play.'], nBg);
    issues(end+1, 1) = sprintf(['%d bank item(s) are set to be embedded in an ongoing ' ...
        'Background. A StimPlayer Run does not play a background: each stimulus is ' ...
        'played on its own, with silence between presentations (a background ' ...
        'modulation plays as a burst of its modulated background). A background is ' ...
        'played by a presenter that supports one.'], nBg);
end

proceed = true;
if isempty(issues) || isempty(obj.hFig) || ~isvalid(obj.hFig)
    return
end
msg = strjoin(issues.', string(newline) + newline) + newline + newline + "Run anyway?";
choice = uiconfirm(obj.hFig, char(msg), 'Check Before Running', ...
    'Options', {'Run', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, ...
    'Icon', 'warning');
proceed = strcmp(choice, 'Run');
end
