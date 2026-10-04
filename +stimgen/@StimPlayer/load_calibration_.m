function load_calibration_(obj, ffn)
% load_calibration_(obj) - Prompt for a calibration file and apply it.
% load_calibration_(obj, ffn) - Apply a calibration file by path.
% The calibration is applied to every item currently in the bank.

if nargin < 2 || isempty(ffn)
    [fn, pn] = uigetfile( ...
        {'*.esgc;*.sgc','Calibration Files (*.esgc, *.sgc)'; ...
         '*.esgc','EPsych Stim Calibration (*.esgc)'; ...
         '*.sgc','Legacy Calibration (*.sgc)'}, ...
        'Select Calibration File', obj.DataPath);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
elseif ~isfile(ffn)
    obj.forget_recent_calibration_(ffn);
    obj.set_status_("Calibration file not found: " + string(ffn), isError=true);
    return
end

ffn = char(ffn);
try
    [~, ~, ext] = fileparts(ffn);

    if strcmpi(ext, '.esgc')
        calObj = stimgen.StimCalibration();
        calObj.load_calibration(ffn);
    else
        cal = load(ffn, '-mat');
        fields = fieldnames(cal);
        if isempty(fields)
            error('StimPlayer:InvalidCalibrationFile', ...
                'The selected calibration file did not contain any variables.');
        end

        raw = cal.(fields{1});
        if isa(raw, 'stimgen.StimCalibration')
            calObj = raw;
        elseif isstruct(raw)
            calObj = stimgen.StimCalibration.loadobj(raw);
        else
            error('StimPlayer:InvalidCalibrationFile', ...
                'The selected calibration file did not contain a usable calibration object.');
        end
    end

    for i = 1:numel(obj.StimPlayObjs)
        obj.StimPlayObjs(i).StimObj.Calibration = calObj;
    end
    if ~isempty(obj.StimPlayObjs)
        obj.mark_bank_dirty_;  % each item saves its calibration
    end
    obj.Calibration     = calObj;
    obj.CalibrationFile = string(ffn);
    obj.remember_recent_calibration_(ffn);
    stimgen.util.vprintf(1, 'Calibration applied to %d bank items.', numel(obj.StimPlayObjs));
    statusText = "Calibration applied to " + string(numel(obj.StimPlayObjs)) + " bank item(s).";
    if obj.PlaybackOutput == "Speakers" && obj.has_hardware_route_
        statusText = statusText + " Set Output to Calibrated Hardware to preview at calibrated levels.";
    end
    obj.set_status_(statusText);
catch ME
    obj.report_gui_error_(ME, "Calibration Error", ...
        "StimPlayer could not load or apply the selected calibration file.");
end
obj.update_calibration_status_;
end
