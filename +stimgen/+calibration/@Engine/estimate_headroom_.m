function m = estimate_headroom_(obj, excitation, response)
% Clipping and headroom margins against the rig's output ceiling. Reads
% MaxOutputVoltage rather than assuming +/-10 V, so a rig with a different
% converter reports real headroom -- and so the live monitor's ceiling line
% and the flag stored in the calibration metrics come from one number.
fullScaleV = obj.MaxOutputVoltage;
m = struct( ...
    'assumedFullScaleV', fullScaleV, ...
    'excitationPeakV', nan, ...
    'excitationHeadroomDb', nan, ...
    'excitationClippingLikely', false, ...
    'responsePeakV', nan, ...
    'responseHeadroomDb', nan, ...
    'responseFlatTopFraction', nan, ...
    'responseClippingLikely', false);

if ~isempty(excitation)
    exPeak = max(abs(excitation));
    m.excitationPeakV = exPeak;
    m.excitationHeadroomDb = 20 * log10(fullScaleV / max(exPeak, eps));
    m.excitationClippingLikely = exPeak >= fullScaleV;
end

if ~isempty(response)
    rspPeak = max(abs(response));
    m.responsePeakV = rspPeak;
    m.responseHeadroomDb = 20 * log10(fullScaleV / max(rspPeak, eps));

    % Relative to the record's own peak: a flat top is a shape, not a
    % voltage. An absolute floor tied to 1 V instead called every quiet
    % recording clipped -- a mic at a normal level returns a few millivolts,
    % where a 1e-5 V window spans a percent of the peak and any clean sine
    % dwells inside it for more than the 1% that trips the flag.
    tol = max(1e-12, 1e-5 * rspPeak);
    flatTopFraction = mean(abs(abs(response) - rspPeak) <= tol);
    m.responseFlatTopFraction = flatTopFraction;
    m.responseClippingLikely = (rspPeak >= fullScaleV) || (flatTopFraction > 0.01);
end
end
