function assert_filter_rate(calData, fs)
% assert_filter_rate(calData, fs)
% Refuse an equalization filter that is about to be run at a rate other than
% the one it was designed for.
%
% An FIR's coefficients are defined in cycles per sample, not in Hz, so running
% them at another rate rescales the entire response by the rate ratio: a
% correction fitted at 200 kHz applies at 10 kHz what it meant for 20 kHz.
% Nothing about the resulting waveform reveals this -- the stimulus comes out
% equalized, just for frequencies it does not contain -- which is why the check
% belongs here, before the filtering, rather than in whatever later analysis
% eventually notices the levels are wrong.
%
% Being below the lower Nyquist does not make the filter valid. That only makes
% the band representable; the correction still lands in the wrong place.
%
% The design rate is read from CalibrationData.filterDesign, falling back to
% the filter's own SampleRate. A filter carrying neither -- designed before
% either was recorded -- cannot be checked and is allowed through with a
% warning, since refusing it would reject the calibration rather than the
% mistake.
%
% Parameters:
%   calData - CalibrationData struct holding .filter
%   fs      - sample rate in Hz the filter is about to be run at
%
% Example:
%   stimgen.util.assert_filter_rate(C.CalibrationData, double(obj.Fs));
%
% See also: stimgen.calibration.Engine/design_filter, stimgen.util.filter_aligned

arguments
    calData (1,1) struct
    fs      (1,1) double {mustBePositive, mustBeFinite}
end

designFs = 0;
if isfield(calData, 'filterDesign') && isfield(calData.filterDesign, 'sampleRate')
    v = double(calData.filterDesign.sampleRate);
    if isscalar(v) && isfinite(v) && v > 0
        designFs = v;
    end
end

if designFs <= 0
    % Filters predating filterDesign still carry the rate when design_filter
    % passed one to designfilt; a normalized-frequency design carries nothing.
    Hd = calData.filter;
    if ~Hd.NormalizedFrequency && isfinite(Hd.SampleRate) && Hd.SampleRate > 0
        designFs = double(Hd.SampleRate);
    end
end

if designFs <= 0
    stimgen.util.vprintf(1, 1, ...
        ['Equalization filter records no design sample rate, so it cannot be checked ' ...
         'against the %g Hz signal it is about to filter. Redesign it to record one.'], fs);
    return
end

if abs(designFs - fs) > 1e-6 * fs
    error('stimgen:util:filterRateMismatch', ...
        ['Equalization filter was designed for Fs = %.4f Hz but the stimulus runs at ' ...
         '%.4f Hz, so its correction would land at %.4gx the frequencies it was fitted ' ...
         'to. Redesign it from the same calibration with ' ...
         'design_filter(..., SampleRate=%g) -- the lookup table is in Hz and volts and ' ...
         'needs no re-measuring -- or run the stimulus at %.4f Hz.'], ...
        designFs, fs, fs / designFs, fs, designFs);
end
