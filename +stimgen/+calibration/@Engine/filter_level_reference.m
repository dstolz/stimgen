function r = filter_level_reference(obj, x)
% r = filter_level_reference(obj)
% r = filter_level_reference(obj, x)
% Level reference for running the equalization filter in hardware.
%
% design_filter produces a shape-only filter: its magnitude is referenced to
% 0 dB at its peak, and apply_calibration renormalizes the filtered waveform
% before scaling it to the LUT voltage for the requested level. A hardware
% chain (source -> FIR -> gain -> DAC) has no renormalization step, so the
% filter's spectrum-dependent insertion loss lands directly on the output
% level. This method computes that accounting once, for a known source, so
% the hardware gain stage can be driven on the same dB SPL scale the LUT
% promises in software.
%
% Parameters:
%   x - the source the hardware feeds through the FIR, in volts at the DAC.
%       A scalar is the RMS of a spectrally white source (default 1 V), for
%       which the filtered RMS has the closed form x * norm(taps). A vector
%       is the actual source waveform, which is filtered here instead — use
%       this form whenever the source is shaped or band-limited before the
%       FIR, or was generated in software and uploaded.
%
% Returns r, a struct:
%   scale        - factor that brings the filtered source to the
%                  NormativeValue level: multiply the filtered signal — or,
%                  equivalently, the taps themselves before loading them —
%                  by this, and unity hardware gain produces NormativeValue
%                  dB SPL
%   unityGainSpl - dB SPL the *unscaled* filtered source produces at unity
%                  hardware gain (NormativeValue - 20*log10(scale))
%   filteredRms  - RMS of the filtered source, in volts
%   lutVoltage   - LUT voltage at ReferenceFrequency for NormativeValue dB
%                  SPL: the anchor apply_calibration uses for "filter"-type
%                  stimuli, reused here so hardware and software levels agree
%   normativeValue, referenceFrequency - engine parameters echoed for the record
%
% With the scale applied, a hardware gain of 10^((level - NormativeValue)/20)
% plays the source at `level` dB SPL — the same convention, anchor, and
% accuracy as apply_calibration on an RMS-normalized ("filter"-type)
% stimulus, so no new acoustic assumption is introduced. Recompute after
% every design_filter: the taps' norm changes with each design.
%
% Example — RPvds chain  noise -> FIR -> ScaleAdd, with the ScaleAdd's SF
% driven by dBToLin(level - NormativeValue):
%   r = eng.filter_level_reference(1);                 % 1 V RMS white noise
%   b = tf(eng.CalibrationData.filter) * r.scale;      % taps to load
%
% See also: design_filter, compute_adjusted_voltage
arguments
    obj
    x (1,:) double {mustBeNonempty, mustBeFinite} = 1
end

C = obj.CalibrationData;
if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter)
    error('stimgen:calibration:Engine:noFilter', ...
        'No equalization filter has been designed. Run design_filter first.');
end

filt = C.filter;
if ~isfir(filt)
    error('stimgen:calibration:Engine:notFir', ...
        'The equalization filter is not FIR, so a tap-based level reference cannot be computed.');
end
b = tf(filt);

if isscalar(x)
    if x <= 0
        error('stimgen:calibration:Engine:badSourceRms', ...
            'A scalar source must be a positive RMS voltage.');
    end
    % White source: the expected RMS through an FIR is rms_in * ||b||_2.
    filteredRms = x * norm(b);
else
    filteredRms = sqrt(mean(filter(b, 1, x(:)) .^ 2));
    if ~(filteredRms > 0)
        error('stimgen:calibration:Engine:badSourceWaveform', ...
            'The source waveform is silent after filtering; no level reference exists for it.');
    end
end

% The anchor apply_calibration uses for "filter"-type stimuli: the voltage at
% ReferenceFrequency that produces NormativeValue dB SPL. Raises the usual
% engine errors when no calibration or no tone/swept-sine LUT exists.
v0 = obj.compute_adjusted_voltage("filter", nan, obj.NormativeValue);

r = struct( ...
    'scale',              v0 / filteredRms, ...
    'unityGainSpl',       obj.NormativeValue + 20 * log10(filteredRms / v0), ...
    'filteredRms',        filteredRms, ...
    'lutVoltage',         v0, ...
    'normativeValue',     obj.NormativeValue, ...
    'referenceFrequency', obj.ReferenceFrequency);
end
