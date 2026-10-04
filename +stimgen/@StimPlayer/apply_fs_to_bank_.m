function failures = apply_fs_to_bank_(obj)
% failures = apply_fs_to_bank_() - Write obj.Fs onto every bank item.
% StimType.Fs is AbortSet, so items already at this rate are left
% alone and only the rest pay for a signal regeneration.
%
% The regeneration triggered by the assignment runs inside a
% PostSet listener, where MATLAB downgrades an error to a warning
% and leaves the old signal in place. update_signal is therefore
% called again here, where a failure is catchable — the same
% assign-then-rebuild pattern the parameter editor uses.
%
% Returns:
%   failures - (:,1) string, one "Name: reason" per item that
%              could not be generated at the new rate

failures = string.empty(0,1);
if isempty(obj.StimPlayObjs)
    return
end

obj.set_computing_(true);
computingCleanup = onCleanup(@() obj.set_computing_(false));

% Silence the listener's own stack dump for the assignment below:
% the rebuild that follows it raises the same failure where it can
% be caught and reported as one readable message.
warnState   = warning('off', 'MATLAB:callback:PropertyEventError');
warnCleanup = onCleanup(@() warning(warnState));

for i = 1:numel(obj.StimPlayObjs)
    sp = obj.StimPlayObjs(i);
    try
        sp.Fs = obj.Fs;
        sp.update_signal;
    catch ME
        failures(end+1,1) = sp.Name + ": " + string(ME.message);
    end
end
clear computingCleanup warnCleanup;
end
