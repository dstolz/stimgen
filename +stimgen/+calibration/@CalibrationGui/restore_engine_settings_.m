function restore_engine_settings_(obj)
% Preference keys are the Engine property names. Numeric values
% are validated against the field each is headed for via
% sync_controls_: a hand-edited preference outside its range
% would otherwise throw there rather than here. Max Output,
% Excitation Voltage, Tone Rise/Fall Time, the ambient
% temperature, the two recorded hardware gains and the FFT
% length state their limits literally because their controls
% live in an on-demand settings window and do not exist yet.
% Every value here is in the unit the Engine property holds --
% the temperature in Celsius (as its field shows it), the ramp in
% seconds, not the milliseconds its field shows.
factory = stimgen.calibration.Engine();
numericPairs = {
    'ReferenceLevel',     obj.RefLevelField.Limits
    'ReferenceFrequency', obj.RefFreqField.Limits
    'MicSensitivity',     obj.MicSensField.Limits
    'AmbientTemperature', obj.AmbientTempLimitsC
    'NormativeValue',     obj.NormativeField.Limits
    'ExcitationVoltage',  [eps, 10]
    'ToneRampDuration',   [0.1e-3, 50e-3]
    'MaxOutputVoltage',   [eps, 1000]
    'AdcGain',            [-200, 200]
    'DacAttenuation',     [-200, 200]
    'SpectralFftLength',  [0, 2^24]
    };

opts = struct();
for k = 1:size(numericPairs, 1)
    prop = numericPairs{k, 1};
    limits = numericPairs{k, 2};
    v = str2double(obj.get_pref_(prop, ''));
    if isfinite(v) && v >= limits(1) && v <= limits(2) && ...
            obj.Engine.(prop) == factory.(prop)
        opts.(prop) = v;
    end
end

for prop = ["AcCoupleResponse" "ShowLivePlots"]
    stored = obj.get_pref_(char(prop), '');
    if any(strcmp(stored, {'0', '1'})) && ...
            obj.Engine.(prop) == factory.(prop)
        opts.(prop) = strcmp(stored, '1');
    end
end

stored = obj.get_pref_('ToneLutSource', '');
if any(strcmp(stored, {'tone', 'swept_sine'})) && ...
        obj.Engine.ToneLutSource == factory.ToneLutSource
    opts.ToneLutSource = string(stored);
end

stored = string(obj.get_pref_('SpectralWindow', ''));
if ismember(stored, stimgen.calibration.SpectralOptions.WindowList) && ...
        obj.Engine.SpectralWindow == factory.SpectralWindow
    opts.SpectralWindow = stored;
end

if isempty(fieldnames(opts))
    return
end
args = namedargs2cell(opts);
try
    obj.Engine.set_configuration(args{:});
catch ME
    % A stale preference must never block the window opening.
    stimgen.util.vprintf(-1, ME);
end
end
