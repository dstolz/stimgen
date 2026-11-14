function rec = generation_record(obj)
% rec = generation_record(obj)
% What the waveform currently in Signal was generated from.
%
% A presenter logs this next to each presentation so that the stimulus a
% trial played can be identified afterwards without regenerating anything.
% Nothing is selected and nothing is regenerated -- the variant state is
% read with get_variant_info and active_variant_values, which touch no
% selection state, and the level figures are measured from the samples on
% hand.
%
% Only the vectorized properties are reported, as the values the active
% combination took. A scalar property is the same for every presentation of
% the stimulus and is already in toStruct (the bank), and reporting every
% property here would copy bulk data -- a SoundFile catalog can embed audio
% -- into every trial.
%
% A subclass whose waveform depends on more than its property values (a
% random draw, a derived trajectory) overrides this and adds what is needed
% to reconstruct the waveform; see stimgen.DMR. An override starts from
% generation_record@stimgen.StimType(obj) so the fields below are always
% present.
%
% Returns:
%   rec - scalar struct:
%     RecordVersion     - layout version of these base fields (1)
%     Class             - class name, with package
%     DisplayName       - the stimulus's DisplayName
%     Fs                - sample rate, Hz
%     N                 - number of samples in Signal
%     VariantIndex      - active combination, 1-based
%     NumCombinations   - number of combinations (1 with no variant axis)
%     VariantProperties - names of the vectorized properties
%     VariantValues     - struct: the active combination's value of each
%     CalibrationType   - the class constant
%     Normalization     - the class constant
%     ApplyCalibration  - whether calibration was requested
%     ApplyWindow       - whether the gate was requested
%     SignalRms         - rms of Signal as it stands (NaN when empty)
%     SignalPeak        - max(abs(Signal)) as it stands (NaN when empty)
%
% See also: active_variant_values, get_variant_info, toStruct

info = obj.get_variant_info();
vals = obj.active_variant_values();

sig = double(obj.Signal);

rec = struct();
rec.RecordVersion     = 1;
rec.Class             = string(class(obj));
rec.DisplayName       = string(obj.DisplayName);
rec.Fs                = double(obj.Fs);
rec.N                 = numel(sig);
rec.VariantIndex      = info.ActiveIndex;
rec.NumCombinations   = info.NumCombinations;
rec.VariantProperties = info.PropertyNames;
rec.VariantValues     = vals;
rec.CalibrationType   = string(obj.CalibrationType);
rec.Normalization     = string(obj.Normalization);
rec.ApplyCalibration  = logical(obj.ApplyCalibration);
rec.ApplyWindow       = logical(obj.ApplyWindow);
if isempty(sig)
    rec.SignalRms  = NaN;
    rec.SignalPeak = NaN;
else
    rec.SignalRms  = sqrt(mean(sig .^ 2));
    rec.SignalPeak = max(abs(sig));
end
end
