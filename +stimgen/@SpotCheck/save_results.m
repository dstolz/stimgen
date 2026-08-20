function ffn = save_results(obj, ffn)
% save_results(obj)
% save_results(obj, ffn)
% ffn = save_results(obj, ...)
% Write the last spot check to a .mat file.
%
% Everything needed to re-read the measurement later goes in: the comparison,
% both waveforms, the full metrics of each, the engine settings the levels
% were computed on, and the stimulus itself in serialized form. A saved spot
% check is meant to be readable in a year, when the rig has moved and the bank
% has been edited, so it carries its own context rather than a reference to it.
%
% Deliberately not a new file format. It is a plain .mat, so `load` opens it
% and every field is a struct of doubles and strings.
%
% Parameters:
%   ffn - full file path (optional); prompts with a dialog when omitted
%
% Returns:
%   ffn - the resolved path, or '' when the dialog was cancelled

arguments
    obj (1,1) stimgen.SpotCheck
    ffn (1,:) char = ''
end

if isempty(fieldnames(obj.Results))
    error('stimgen:SpotCheck:noResults', ...
        'Nothing to save - no spot check has been run yet.');
end

if isempty(ffn)
    startDir = obj.DataPath_;
    if strlength(startDir) == 0 || ~isfolder(startDir)
        startDir = pwd;
    end
    suggested = fullfile(char(startDir), default_name_(obj));
    [fn, pn] = uiputfile({'*.mat', 'MAT Files (*.mat)'}, ...
        'Save Spot Check', suggested);
    if isequal(fn, 0)
        ffn = '';
        return
    end
    ffn = fullfile(pn, fn);
end

[~, ~, ext] = fileparts(ffn);
if ~strcmpi(ext, '.mat')
    ffn = [ffn '.mat'];
end

s = struct();
s.spotCheck = obj.Results;

% The stimulus in serialized form, so the file says what was played and not
% only what came back. A handle would not survive the save; toStruct is the
% package's own persistence format and rebuilds through StimType.fromStruct.
try
    s.stimulus = obj.Stimulus.toStruct();
catch ME
    stimgen.util.vprintf(1, 1, ...
        'SpotCheck: the stimulus could not be serialized into the result file: %s', ...
        ME.message);
end

s.recording = struct( ...
    'waveform',   obj.Capture.response, ...
    'fs',         obj.Capture.fs, ...
    'provenance', obj.Recording.Provenance);

s.savedOn  = datetime('now');
s.stimgenVersion = "spotcheck-1";

try
    save(ffn, '-struct', 's', '-v7.3');
catch ME
    error('stimgen:SpotCheck:saveFailed', ...
        'Could not write "%s": %s', ffn, ME.message);
end

obj.DataPath_ = string(fileparts(ffn));

stimgen.util.vprintf(0, 'Saved spot check: "%s"', ffn);
obj.set_status_("Saved spot check: " + string(ffn));
end % save_results


% =========================================================================

function name = default_name_(obj)
% name = default_name_(obj)
% Suggested file name: the stimulus and when it was checked, so a folder of
% these sorts into something readable.
label = char(obj.StimulusLabel);
label = regexprep(label, '[^\w-]+', '_');
if isempty(label)
    label = 'stimulus';
end
name = sprintf('spotcheck_%s_%s.mat', label, ...
    char(string(datetime('now'), 'yyyyMMdd_HHmmss')));
end
