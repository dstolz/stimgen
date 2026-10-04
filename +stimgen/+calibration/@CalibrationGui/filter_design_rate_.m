function fs = filter_design_rate_(obj)
% fs = filter_design_rate_(obj)
% Rate the current equalization filter was designed for, or 0 when
% there is no filter or it predates the filterDesign metadata.
fs = 0;
C = obj.Engine.CalibrationData;
if ~isstruct(C) || ~isfield(C, 'filter') || isempty(C.filter), return; end
if ~isfield(C, 'filterDesign') || ~isfield(C.filterDesign, 'sampleRate'), return; end
v = double(C.filterDesign.sampleRate);
if isscalar(v) && isfinite(v) && v > 0
    fs = v;
end
end
