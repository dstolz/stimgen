function refresh_combo_controls_(obj)
% refresh_combo_controls_() - Update combo-step button state and label.
h = obj.handles;
required = {'ComboPrevBtn','ComboNextBtn','ComboStatusLbl','BankList'};
if ~all(isfield(h, required))
    return
end
if ~isvalid(h.ComboPrevBtn) || ~isvalid(h.ComboNextBtn) || ...
        ~isvalid(h.ComboStatusLbl) || ~isvalid(h.BankList)
    return
end

idx = [];
if ~isempty(h.BankList.Value) && h.BankList.Value >= 1 && h.BankList.Value <= numel(obj.StimPlayObjs)
    idx = h.BankList.Value;
end

COLOR_NORMAL = [0 0 0];
COLOR_UNEVEN = [0.80 0.50 0.05];

if isempty(idx)
    h.ComboPrevBtn.Enable = 'off';
    h.ComboNextBtn.Enable = 'off';
    h.ComboStatusLbl.Text = 'Combo: - / -';
    h.ComboStatusLbl.FontColor = COLOR_NORMAL;
    h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLbl');
    return
end

sp      = obj.StimPlayObjs(idx);
stimObj = sp.CurrentStimObj;
info    = stimObj.get_variant_info();

% How Reps divides over the combinations, so an uneven split is
% visible while the bank is edited, not only when Run warns.
[repsText, uneven] = obj.reps_per_combination_(sp.Reps, stimObj);
if strlength(repsText) > 0
    h.ComboStatusLbl.Text = char(sprintf('Combo: %d / %d | %s', ...
        info.ActiveIndex, info.NumCombinations, repsText));
else
    h.ComboStatusLbl.Text = sprintf('Combo: %d / %d', info.ActiveIndex, info.NumCombinations);
end
if uneven
    h.ComboStatusLbl.FontColor = COLOR_UNEVEN;
    h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLblUneven');
else
    h.ComboStatusLbl.FontColor = COLOR_NORMAL;
    h.ComboStatusLbl.Tooltip   = stimgen.util.tooltip('StimPlayer', 'ComboStatusLbl');
end

% Stepping changes the combination a bank item will present
% next, so it is closed while a session holds the bank: the
% buffer for the next trial is already loaded, and the
% presentation log records the combination it was made from.
if info.NumCombinations > 1 && ~obj.CaptureLocked_
    h.ComboPrevBtn.Enable = 'on';
    h.ComboNextBtn.Enable = 'on';
else
    h.ComboPrevBtn.Enable = 'off';
    h.ComboNextBtn.Enable = 'off';
end
end
