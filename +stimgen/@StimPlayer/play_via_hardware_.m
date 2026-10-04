function play_via_hardware_(obj, stimObj)
% play_via_hardware_(obj, stimObj) - Play Signal through host hardware.
% The waveform is played verbatim — no normalization — so a
% calibrated stimulus drives the output at its calibrated
% voltage. Blocks until the hardware finishes so Play All can
% pace combinations and Stop takes effect between them.
%
% Two hardware contracts can carry a preview, and a circuit
% typically exposes only one of them. The player's own playback
% tags (BufferData_0, BufferSize_0, x_Trigger_0 — the Run
% contract) are preferred, so a preview exercises the exact
% route a Run will use. When they are absent, playback falls
% back to the host's calibration adapter (BufferOut/BufferIn
% circuits), whose play_and_record return is discarded. With no
% host, CaptureAdapter is played through the same way.

if ~isempty(obj.Timer) && isvalid(obj.Timer) && strcmp(obj.Timer.Running, 'on')
    error('stimgen:StimPlayer:PreviewDuringRun', ...
        'Stop the running session before previewing through hardware.');
end

obj.require_hardware_route_;
if ~isempty(obj.Host)
    obj.ensure_host_connected_;
end

signal = double(stimObj.Signal);
peak = max(abs(signal));
if peak > 10
    error('stimgen:StimPlayer:PreviewVoltageOutOfRange', ...
        'The waveform peaks at %.2f V, beyond the +/-10 V output range.', peak);
end

if isempty(fieldnames(obj.PARAMS)) && ~isempty(obj.Host)
    obj.resolve_params_;
end

if obj.HardwareAvailable
    obj.check_preview_rate_(double(obj.Host.sampleRate()), stimObj.Fs);

    % Same write sequence as update_buffer/trigger_stim_playback,
    % pinned to slot 0: the Run timer is stopped, so the
    % double-buffer cursor is not in play.
    buffer = [0, signal(:).', 0];
    obj.PARAMS.BufferSize_0.Value = numel(buffer);
    obj.PARAMS.BufferData_0.Value = buffer;
    obj.PARAMS.x_Trigger_0.Value = 1;
    obj.PARAMS.x_Trigger_0.Value = 0;

    % The trigger returns immediately; hold here for the signal
    % duration to keep the blocking contract stated above.
    pause(numel(signal) / stimObj.Fs);
    return
end

adapter = obj.resolve_preview_adapter_;
obj.check_preview_rate_(double(adapter.sample_rate()), stimObj.Fs);
adapter.play_and_record(signal(:).');
end
