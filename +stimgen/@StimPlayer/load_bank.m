function load_bank(obj, ffn)
% load_bank(obj)
% load_bank(obj, ffn)
% Load a stimulus bank from a .spl file and rebuild StimPlayObjs.
% Unsaved edits to the current bank are offered for saving first (Save /
% Discard / Cancel). The loaded file becomes BankFile and the bank is marked
% saved -- unless loading had to change it (mixed sample rates unified), in
% which case it is marked unsaved.
%
% Parameters:
%   ffn - full file path (optional); prompts with dialog if omitted

if nargin >= 2 && ~isempty(ffn) && ~isfile(ffn)
    % A remembered path whose file has since moved or been deleted.
    obj.forget_recent_bank_(ffn);
    obj.set_status_("Bank file not found: " + string(ffn), isError=true);
    return
end

if ~obj.confirm_discard_changes_("loading another bank")
    obj.set_status_("Load Bank cancelled.");
    return
end

if nargin < 2 || isempty(ffn)
    [fn, pn] = uigetfile('*.spl', 'Load Stimulus Bank', obj.DataPath);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
end

ffn = char(ffn);

replaced = false;  % true once the current bank has been given up
try
    bank = load(ffn, '-mat');

    sps = stimgen.StimPlay.empty(0,1);
    for k = 1:bank.NItems
        S = bank.Items{k};

        % Reconstruct the StimType object through the one restore path, so
        % a bank item comes back with exactly what toStruct wrote. fromStruct
        % holds calibration off until the item is whole.
        stimObj = stimgen.StimType.fromStruct(S.StimObj);

        sp      = stimgen.StimPlay(stimObj);
        sp.Reps = S.Reps;
        sp.Name = S.Name;
        sp.ISI  = S.ISI;

        sps(end+1, 1) = sp; %#ok<AGROW>
    end

    % Every item rebuilt: only now is the current bank replaced, so a file
    % that fails part-way leaves it, and its ISI and order, untouched.
    obj.ISI           = bank.ISI;
    obj.SelectionType = string(bank.SelectionType);
    obj.StimPlayObjs  = sps;
    replaced = true;

    % A bank stores Fs per stimulus, but the player runs one rate for the
    % whole bank, so the first item's rate wins and is re-applied to the rest.
    fsNote = "";
    if ~isempty(sps)
        loadedFs = arrayfun(@(sp) sp.CurrentStimObj.Fs, sps);
        obj.Fs   = loadedFs(1);
        if any(loadedFs ~= loadedFs(1))
            fsNote = sprintf(' Bank items had differing sample rates; all set to %g Hz.', obj.Fs);
            stimgen.util.vprintf(1, 1, ...
                'StimPlayer: bank contained %d distinct sample rates; all items set to %g Hz.', ...
                numel(unique(loadedFs)), obj.Fs);
        end
    end

    ISIField_sync_(obj);

    obj.refresh_listbox_;
    obj.clear_tabs_;
    obj.update_counter_;
    obj.refresh_combo_controls_;

    % Any bank-level calibration belonged to the previous bank; the loaded
    % items carry their own embedded calibrations (or none).
    obj.Calibration     = [];
    obj.CalibrationFile = "";
    obj.update_calibration_status_;

    obj.DataPath = string(fileparts(ffn));
    obj.remember_recent_bank_(ffn);

    % The bank now matches the file, except where loading changed it.
    obj.mark_bank_clean_(ffn);
    if strlength(fsNote) > 0
        obj.mark_bank_dirty_;
    end

    stimgen.util.vprintf(1, 'StimPlayer: bank loaded from "%s" (%d items).', ffn, numel(sps));
    obj.set_status_("Loaded bank with " + string(numel(sps)) + " item(s)." + fsNote);
catch ME
    if replaced
        % The bank in memory is neither the old one nor exactly the file.
        % Saving it must not silently overwrite either: no file, unsaved.
        obj.BankFile = "";
        obj.mark_bank_dirty_;
        ISIField_sync_(obj);
        obj.refresh_listbox_;
        obj.clear_tabs_;
        obj.update_counter_;
    end
    obj.report_gui_error_(ME, "Load Bank Error", ...
        "StimPlayer could not load the selected bank file.");
end
end


function ISIField_sync_(obj)
% Sync the ISI editfield text with obj.ISI after a load (seconds -> ms).
h = obj.handles;
if isfield(h, 'ISIField') && isvalid(h.ISIField)
    h.ISIField.Value = mat2str(obj.ISI * 1e3);
end
if isfield(h, 'OrderDD') && isvalid(h.OrderDD)
    h.OrderDD.Value = obj.SelectionType;
end
end
