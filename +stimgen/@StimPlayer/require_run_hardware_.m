function require_run_hardware_(obj)
% require_run_hardware_() - Error when a hardware run has lost its hardware.
% A run that started with hardware output must not carry on as a
% silent dry run because a parameter or the connection went
% away: the presentation log would record trials nobody heard.
% No-op for a run that started without hardware (confirmed as
% a dry run, or offline).
if obj.HardwareRun_ && ~obj.HardwareAvailable
    error('stimgen:StimPlayer:HardwareLost', ...
        'Hardware output was lost during the run after %d of %d presentations. %s', ...
        obj.presented_count_(), obj.total_count_(), char(obj.hardware_unavailable_reason_()));
end
end
