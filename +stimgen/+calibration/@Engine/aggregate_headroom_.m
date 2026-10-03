function out = aggregate_headroom_(~, metricsArray)
% out = aggregate_headroom_(obj, metricsArray)
% Summarize estimate_headroom_ results over repeats: mean peaks and margins,
% any() of the clipping flags, and the ceilings they were judged against.
out = stimgen.calibration.Engine.empty_headroom_();
if isempty(metricsArray)
    return
end

out.assumedFullScaleV = metricsArray(1).assumedFullScaleV;
out.assumedInputFullScaleV = metricsArray(1).assumedInputFullScaleV;
out.excitationPeakV = mean([metricsArray.excitationPeakV], 'omitnan');
out.excitationHeadroomDb = mean([metricsArray.excitationHeadroomDb], 'omitnan');
out.excitationClippingLikely = any([metricsArray.excitationClippingLikely]);
out.responsePeakV = mean([metricsArray.responsePeakV], 'omitnan');
out.responseHeadroomDb = mean([metricsArray.responseHeadroomDb], 'omitnan');
out.responseFlatTopFraction = mean([metricsArray.responseFlatTopFraction], 'omitnan');
out.responseClippingLikely = any([metricsArray.responseClippingLikely]);
end
