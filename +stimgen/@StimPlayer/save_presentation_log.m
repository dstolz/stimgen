function ffn = save_presentation_log(obj, ffn)
% ffn = save_presentation_log(obj)
% ffn = save_presentation_log(obj, ffn)
% Write the presentation log of the last run to a MAT file.
%
% The log is what a run presented, in order: the bank item, time, polarity
% and variant combination of every presentation, how late each trigger was,
% and the generation record of each stimulus triggered -- for a stimulus
% with a random draw (stimgen.DMR) that is what reconstructs the waveform.
% With it go the run's settings and the bank as it was when the run started.
% See presentation_log_struct_ for the layout.
%
% A hardware Run is also written automatically when it ends (see
% PresentationLogDir); this writes any log, a dry run's included, wherever
% asked. The log is cleared by the next Run, so save it first.
%
% Parameters:
%   ffn - full file path (optional). With none, a save dialog opens in
%         DataPath; cancelling it returns "" and writes nothing. ".mat" is
%         added to a name with no extension.
%
% Returns:
%   ffn - the file written, as a string ("" if cancelled)
%
% Errors:
%   stimgen:StimPlayer:NoPresentationLog - no run has presented anything
%   stimgen:StimPlayer:SessionRunning    - a session is running; the log is
%                                          still being written
if isempty(obj.StimOrder)
    error('stimgen:StimPlayer:NoPresentationLog', ...
        'There is no presentation log to save: no run has presented anything yet.');
end
if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
    error('stimgen:StimPlayer:SessionRunning', ...
        'A session is running. Stop it before saving its presentation log.');
end

if nargin < 2 || isempty(ffn) || strlength(string(ffn)) == 0
    stamp = '';
    if isfield(obj.RunInfo, 'StartedAt')
        stamp = ['_' strrep(regexprep(obj.RunInfo.StartedAt, '[-:]', ''), 'T', '_')];
    end
    startIn = fullfile(char(obj.DataPath), ['stimgen_run' stamp '.mat']);
    [fn, pn] = uiputfile({'*.mat', 'Presentation log (*.mat)'}, ...
        'Save Presentation Log', startIn);
    if isequal(fn, 0)
        ffn = "";
        return
    end
    ffn = fullfile(pn, fn);
end

ffn = char(ffn);
[~, ~, ext] = fileparts(ffn);
if isempty(ext)
    ffn = [ffn '.mat'];
end

S = obj.presentation_log_struct_(); %#ok<NASGU>
save(ffn, '-struct', 'S', '-v7');

obj.PresentationLogFile = string(ffn);
stimgen.util.vprintf(1, 'StimPlayer: presentation log saved to "%s"', ffn);
obj.set_status_("Saved presentation log: " + string(ffn));
ffn = string(ffn);
end
