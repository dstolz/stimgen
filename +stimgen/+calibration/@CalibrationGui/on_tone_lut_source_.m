function on_tone_lut_source_(obj)
% Applies immediately rather than at the next run: the source
% choice affects lookups on committed data, not measurements.
if obj.ToneSweptSineCheck.Value
    obj.Engine.set_configuration(ToneLutSource="swept_sine");
    C = obj.Engine.CalibrationData;
    if isstruct(C) && isfield(C, 'swept_sine') && ~isempty(C.swept_sine)
        obj.set_status_('Tone lookups now use the swept sine calibration, overriding any direct tone calibration.', false);
    else
        obj.set_status_('Tone lookups will use the swept sine calibration once one is run; until then the direct tone calibration applies.', false);
    end
else
    obj.Engine.set_configuration(ToneLutSource="tone");
    obj.set_status_('Tone lookups use the direct tone calibration.', false);
end
end
