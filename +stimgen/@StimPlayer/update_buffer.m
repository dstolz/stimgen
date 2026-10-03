function update_buffer(obj)
% update_buffer(obj) - Write the current stimulus signal to the hardware buffer.
% Uses double-buffering: TrigBufferID alternates 0/1 based on trialCount_.
% The signal is multiplied by nextPolarity_, which claim_polarity_ sets to -1
% on every other presentation of a stimulus that alternates polarity.
% No-op for a run without hardware output. A hardware run whose parameters
% have gone, or whose buffer write fails, raises instead: carrying on would
% trigger whatever the slot last held, or nothing, while the log recorded
% the intended stimulus. The timer callbacks catch it and stop the session.

if ~obj.HardwareAvailable
    obj.require_run_hardware_;   % errors when a hardware run lost its hardware
    return
end

sp = obj.CurrentSPObj;
if isempty(sp)
    return
end

obj.TrigBufferID = mod(obj.trialCount_, 2);
bid = obj.TrigBufferID;

% Zero-pad first and last sample (required by RPvds SerSource components)
buffer = [0, obj.nextPolarity_ .* sp.Signal, 0];
nSamps = numel(buffer);

try
    obj.PARAMS.("BufferSize_" + string(bid)).Value = nSamps;
    obj.PARAMS.("BufferData_" + string(bid)).Value = buffer;
catch ME
    stimgen.util.vprintf(0, 1, 'StimPlayer:update_buffer: failed to write buffer %d', bid);
    stimgen.util.vprintf(0, 1, ME);
    error('stimgen:StimPlayer:HardwareWriteFailed', ...
        'Could not write hardware buffer %d: %s', bid, ME.message);
end

stimgen.util.vprintf(4, 'StimPlayer:update_buffer: slot=%d  nSamps=%d', bid, nSamps);
end
