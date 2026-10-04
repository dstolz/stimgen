function v = frequency_range_(text)
% The filter's frequency range: empty for the LUT span, else "lo hi".
v = stimgen.util.parse_numeric_vector(text, 'frequency range');
if ~isempty(v) && (numel(v) ~= 2 || v(1) >= v(2))
    error('stimgen:calibration:CalibrationGui:badFrequencyRange', ...
        'Enter two increasing values, "lo hi", or leave it empty for the LUT span.');
end
end
