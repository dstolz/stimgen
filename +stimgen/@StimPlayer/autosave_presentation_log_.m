function autosave_presentation_log_(obj)
% autosave_presentation_log_() - Write a hardware run's log when the run ends.
% Called by timer_stopfcn. The presentation log is the only record of what
% a run presented and in what order, and it lives in memory: the next Run
% clears it and closing the player discards it. A run that drove hardware
% is therefore written to PresentationLogDir as it ends, without asking,
% as stimgen_run_<yyyymmdd_HHMMSS>.mat (the time the run started).
%
% Not saved: a dry run (no hardware output), a run that presented nothing,
% and any run while PresentationLogDir is "". save_presentation_log writes
% those on request.
%
% Nothing here throws -- this runs inside the timer's StopFcn, where an
% error would leave the controls locked. A failure is one critical log
% line, and the log stays in memory for save_presentation_log.
try
    if ~isfield(obj.RunInfo, 'HardwareRun') || ~obj.RunInfo.HardwareRun
        return
    end
    if isempty(obj.StimOrder) || strlength(obj.PresentationLogDir) == 0
        return
    end

    folder = char(obj.PresentationLogDir);
    if ~isfolder(folder)
        mkdir(folder);
    end
    stamp = regexprep(obj.RunInfo.StartedAt, '[-:]', '');   % yyyymmddTHHMMSS
    stamp = strrep(stamp, 'T', '_');
    ffn = fullfile(folder, ['stimgen_run_' stamp '.mat']);

    S = obj.presentation_log_struct_(); %#ok<NASGU>
    save(ffn, '-struct', 'S', '-v7');
    obj.PresentationLogFile = string(ffn);
    stimgen.util.vprintf(1, 'StimPlayer: presentation log saved to "%s"', ffn);
catch ME
    stimgen.util.vprintf(0, 1, ['StimPlayer: the presentation log could not be saved ' ...
        'automatically (%s). It is still in memory: save it with save_presentation_log ' ...
        'before the next Run.'], ME.message);
end
end
