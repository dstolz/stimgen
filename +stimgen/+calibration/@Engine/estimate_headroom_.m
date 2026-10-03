function m = estimate_headroom_(obj, excitation, response)
% m = estimate_headroom_(obj, excitation, response)
% Clipping and headroom margins, each against the ceiling it actually meets.
%
% The excitation is judged against output_ceiling_ -- MaxOutputVoltage,
% lowered to the adapter's full_scale() when it reports one -- and the
% response against input_ceiling_ -- the adapter's input_range(), or
% MaxOutputVoltage when it does not say. Judging both against
% MaxOutputVoltage alone, as this once did, let a sound card (full scale 1)
% clip an ExcitationVoltage of 2 and report 14 dB of headroom, and judged a
% microphone input against the speaker's output range. With an adapter that
% reports neither, both ceilings are MaxOutputVoltage and the numbers are
% unchanged. The live monitor's ceiling lines and the flags stored in the
% calibration metrics read the same two ceilings.
%
% An excitation is clipped when it EXCEEDS full scale; a sample at full scale
% is representable. A response that reaches the input range is taken as
% saturated, since a converter pinned at its rail reads exactly that.
outV = obj.output_ceiling_();
inV  = obj.input_ceiling_();
m = stimgen.calibration.Engine.empty_headroom_();
m.assumedFullScaleV      = outV;
m.assumedInputFullScaleV = inV;

if ~isempty(excitation)
    exPeak = max(abs(excitation));
    m.excitationPeakV = exPeak;
    m.excitationHeadroomDb = 20 * log10(outV / max(exPeak, eps));
    m.excitationClippingLikely = exPeak > outV * (1 + 1e-9);
end

if ~isempty(response)
    rspPeak = max(abs(response));
    m.responsePeakV = rspPeak;
    m.responseHeadroomDb = 20 * log10(inV / max(rspPeak, eps));

    % Relative to the record's own peak: a flat top is a shape, not a
    % voltage. An absolute floor tied to 1 V instead called every quiet
    % recording clipped -- a mic at a normal level returns a few millivolts,
    % where a 1e-5 V window spans a percent of the peak and any clean sine
    % dwells inside it for more than the 1% that trips the flag.
    tol = max(1e-12, 1e-5 * rspPeak);
    flatTopFraction = mean(abs(abs(response) - rspPeak) <= tol);
    m.responseFlatTopFraction = flatTopFraction;
    m.responseClippingLikely = (rspPeak >= inV) || (flatTopFraction > 0.01);
end
end
