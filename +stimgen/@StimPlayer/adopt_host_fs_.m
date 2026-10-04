function adopt_host_fs_(obj)
% adopt_host_fs_() - Take the sample rate from the attached host.
% Called at Run time: the converter rate is the hardware's to
% decide, so a host that knows it overrides whatever was typed.
% Hosts predating stimgen.HardwareHost.sampleRate, or that cannot
% determine a rate, leave the bank untouched.

if isempty(obj.Host)
    return
end

try
    hostFs = double(obj.Host.sampleRate());
catch ME
    stimgen.util.vprintf(1, 1, ...
        'StimPlayer: host could not report a sample rate: %s', ME.message);
    return
end

if ~isscalar(hostFs) || ~isfinite(hostFs) || hostFs <= 0 || hostFs == obj.Fs
    return
end

previousFs = obj.Fs;
obj.Fs = hostFs;
stimgen.util.vprintf(1, 'StimPlayer: sample rate set from hardware: %g Hz (was %g Hz).', ...
    hostFs, previousFs);
obj.set_status_(sprintf('Sample rate set from hardware: %g Hz.', hostFs));
end
