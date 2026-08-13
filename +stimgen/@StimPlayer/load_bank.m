function load_bank(obj, ffn)
% load_bank(obj)
% load_bank(obj, ffn)
% Load a stimulus bank from a .spl file and rebuild StimPlayObjs.
%
% Parameters:
%   ffn - full file path (optional); prompts with dialog if omitted

if nargin < 2 || isempty(ffn)
    [fn, pn] = uigetfile('*.spl', 'Load Stimulus Bank', obj.DataPath);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
elseif ~isfile(ffn)
    % A remembered path whose file has since moved or been deleted.
    obj.forget_recent_bank_(ffn);
    obj.set_status_("Bank file not found: " + string(ffn), isError=true);
    return
end

ffn = char(ffn);

try
    bank = load(ffn, '-mat');

    obj.ISI           = bank.ISI;
    obj.SelectionType = string(bank.SelectionType);

    sps = stimgen.StimPlay.empty(0,1);
    for k = 1:bank.NItems
        S = bank.Items{k};

        % Reconstruct the StimType object from its serialized struct.
        % toStruct writes the fully-qualified name ("stimgen.Tone"), so strip
        % any package prefix before the dynamic package-scoped call.
        stimClass = char(S.StimObj.Class);
        dotIdx = find(stimClass == '.', 1, 'last');
        if ~isempty(dotIdx)
            stimClass = stimClass(dotIdx+1:end);
        end
        stimObj   = stimgen.(stimClass)();

        % Restore base StimType properties
        baseProps = {'SoundLevel','Duration','WindowDuration','WindowFcn', ...
                     'ApplyCalibration','ApplyWindow','Fs', ...
                     'VariantSelectionMode','VariantCombinationMode', ...
                     'VariantSelectorClass','VariantSelectorConfig', ...
                     'VariantReselectOnUpdate'};
        for j = 1:numel(baseProps)
            p = baseProps{j};
            if isfield(S.StimObj, p)
                stimObj.(p) = S.StimObj.(p);
            end
        end

        % Restore subclass-specific (UserProperties)
        if isfield(S.StimObj, 'UserProperties')
            for j = 1:numel(S.StimObj.UserProperties)
                p = char(S.StimObj.UserProperties(j));
                if isfield(S.StimObj, p)
                    stimObj.(p) = S.StimObj.(p);
                end
            end
        end

        if isfield(S.StimObj, 'Calibration')
            calData = S.StimObj.Calibration;
            if isa(calData, 'stimgen.StimCalibration')
                stimObj.Calibration = calData;
            elseif isstruct(calData)
                stimObj.Calibration = stimgen.StimCalibration.loadobj(calData);
            end
        end

        sp      = stimgen.StimPlay(stimObj);
        sp.Reps = S.Reps;
        sp.Name = S.Name;
        sp.ISI  = S.ISI;

        sps(end+1, 1) = sp; %#ok<AGROW>
    end

    obj.StimPlayObjs = sps;

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

    stimgen.util.vprintf(1, 'StimPlayer: bank loaded from "%s" (%d items).', ffn, numel(sps));
    obj.set_status_("Loaded bank with " + string(numel(sps)) + " item(s)." + fsNote);
catch ME
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
