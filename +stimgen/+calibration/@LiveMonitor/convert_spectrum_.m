function [v, info] = convert_spectrum_(vrms, unit, micSens, noiseBw)
% [v, info] = convert_spectrum_(vrms, unit, micSens, noiseBw)
% Convert an rms-volts spectrum into one of the display units listed in
% stimgen.calibration.LiveMonitor.SpectrumUnitList, and describe how it should
% be drawn.
%
% Every unit here is a monotone function of vrms, which is what lets the peak
% -hold thinning happen in volts and the conversion happen afterwards.
%
% dB SPL is the calibration's own scale and the default. The two electrical
% units answer a different question -- whether the input stage is anywhere near
% its range, or how close a floor is to the converter's -- which no amount of
% acoustic scaling makes visible. The per-Hz forms are the ones to compare a
% noise floor in, since a level per bin depends on the analysis window and a
% density does not. dB re peak drops the calibration entirely and shows shape
% alone, which is how harmonics and sidebands are read on an uncalibrated or
% not-yet-referenced rig.
%
% The dB SPL forms go through stimgen.calibration.Engine.volts_to_spl, so the
% level read off this axis is the same number the engine would put in a lookup
% table for the same voltage. They took the calibrator's ReferenceLevel as an
% offset until that was found to double-count it -- the scale is fixed by the
% 20 uPa reference, and the calibrator enters only through micSens.
%
% Parameters:
%   vrms     - (1,:) double magnitude spectrum (V rms per bin)
%   unit     - (1,1) string display unit
%   micSens  - (1,1) double microphone sensitivity (V/Pa)
%   noiseBw  - (1,1) double equivalent noise bandwidth of the window (Hz)
%
% Returns:
%   v    - (1,:) double curve in the display unit
%   info - (1,1) struct with fields Label (y-axis label), Format (sprintf spec
%          for a single value), Suffix (unit text for annotations), and IsDb
%          (true when the scale is logarithmic and may go negative, which
%          selects the decade-rounded y-limits)

vrms    = max(vrms, eps);
micSens = max(micSens, eps);
noiseBw = max(noiseBw, eps);

switch unit
    case "dB SPL"
        v = stimgen.calibration.Engine.volts_to_spl(vrms, micSens);
        info = info_('level (dB SPL)', '%.0f', 'dB SPL', true);

    case "dB SPL/Hz"
        v = stimgen.calibration.Engine.volts_to_spl(vrms, micSens) ...
            - 10 * log10(noiseBw);
        info = info_('density (dB SPL/Hz)', '%.0f', 'dB SPL/Hz', true);

    case "Pa"
        v = vrms ./ micSens;
        info = info_('pressure (Pa rms)', '%.3g', 'Pa', false);

    case "V"
        v = vrms;
        info = info_('measured (V rms)', '%.3g', 'V', false);

    case "dBV"
        v = 20 * log10(vrms);
        info = info_('measured (dB re 1 V)', '%.1f', 'dBV', true);

    case "V/sqrt(Hz)"
        v = vrms ./ sqrt(noiseBw);
        info = info_('density (V/\surdHz)', '%.3g', 'V/\surdHz', false);

    case "dB re peak"
        v = 20 * log10(vrms);
        if ~isempty(v)
            v = v - max(v, [], 'omitnan');
        end
        info = info_('relative (dB re peak)', '%.1f', 'dB', true);

    otherwise
        error('stimgen:calibration:LiveMonitor:badSpectrumUnit', ...
            'Unknown spectrum unit "%s".', unit);
end
end

% ------------------------------------------------------------------------ %
function s = info_(label, fmt, suffix, isDb)
s = struct(Label=label, Format=fmt, Suffix=suffix, IsDb=isDb);
end
