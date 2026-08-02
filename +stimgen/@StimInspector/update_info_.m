function update_info_(obj, stimObj, M)
% update_info_(obj, stimObj, M) - Refresh the metrics and parameter tables.
%
% Parameters:
%   stimObj - stimgen.StimType being inspected, or [] to clear
%   M       - metrics struct from stimgen.StimInspector.signal_metrics
%
% Parameter values are read raw rather than through selected_value(), which
% would advance the variant cycle for a vectorized property.  Values are
% shown in the same display units as the GUIs (ms for time properties), and
% vectorized properties are listed in full and tagged "(variant)".

h = obj.handles;

if isempty(stimObj) || ~isvalid(stimObj)
    h.MetricsTable.Data = cell(0, 2);
    h.ParamsTable.Data  = cell(0, 2);
    return
end

h.MetricsTable.Data = metric_rows_(stimObj, M);
h.ParamsTable.Data  = parameter_rows_(stimObj);
end % update_info_


% =========================================================================

function rows = metric_rows_(stimObj, M)
% metric_rows_(stimObj, M) - Build the Metric/Value cell array.

rows = { ...
    'Samples',            num_(M.N, '%d'); ...
    'Duration (ms)',      num_(M.DurationMs, '%.3f'); ...
    'Sample rate (Hz)',   num_(M.Fs, '%.7g'); ...
    '— Level —',          ''; ...
    'Peak',               num_(M.Peak, '%.5g'); ...
    'Peak-to-peak',       num_(M.PeakToPeak, '%.5g'); ...
    'RMS',                num_(M.RMS, '%.5g'); ...
    'DC offset',          num_(M.DC, '%.3g'); ...
    'Peak (dB re 1.0)',   num_(M.PeakDb, '%.2f'); ...
    'RMS (dB re 1.0)',    num_(M.RmsDb, '%.2f'); ...
    'Crest factor (dB)',  num_(M.CrestFactorDb, '%.2f'); ...
    '— Spectrum —',       ''; ...
    'Fundamental (Hz)',   num_(M.FundamentalHz, '%.4g'); ...
    'Fundamental (dB)',   num_(M.FundamentalDb, '%.2f'); ...
    'Spectral centroid (Hz)', num_(M.CentroidHz, '%.4g'); ...
    'RMS bandwidth (Hz)', num_(M.RmsBandwidthHz, '%.4g'); ...
    '-3 dB band (Hz)',    band_(M.Band3dB); ...
    '-20 dB band (Hz)',   band_(M.Band20dB); ...
    'Spectral flatness',  num_(M.Flatness, '%.4f'); ...
    'Tonality (0-1)',     num_(M.Tonality, '%.3f'); ...
    '— Distortion —',     ''; ...
    'THD (%)',            num_(M.ThdPercent, '%.4f'); ...
    'THD (dB)',           num_(M.ThdDb, '%.2f'); ...
    'SNR (dB)',           num_(M.SnrDb, '%.2f'); ...
    'SINAD (dB)',         num_(M.SinadDb, '%.2f'); ...
    'SFDR (dB)',          num_(M.SfdrDb, '%.2f'); ...
    };

rows = [rows; stimulus_rows_(stimObj)];
end


function rows = stimulus_rows_(stimObj)
% stimulus_rows_(stimObj) - Variant, gating and calibration state rows.

rows = {'— Stimulus —', ''};

try
    info = stimObj.get_variant_info();
    rows(end+1, :) = {'Variant combination', sprintf('%d of %d', info.ActiveIndex, info.NumCombinations)};
    if isempty(info.PropertyNames)
        rows(end+1, :) = {'Variant properties', '(none)'};
    else
        rows(end+1, :) = {'Variant properties', char(strjoin(string(info.PropertyNames), ', '))};
    end
catch
end

rows(end+1, :) = {'Normalization',   char(string(stimObj.Normalization))};
rows(end+1, :) = {'Window applied',  yesno_(stimObj.ApplyWindow)};
if stimObj.ApplyWindow
    rows(end+1, :) = {'Window function', char(string(stimObj.WindowFcn))};
end

rows(end+1, :) = {'— Calibration —', ''};
rows(end+1, :) = {'Calibration type', char(string(stimObj.CalibrationType))};
rows(end+1, :) = {'Apply calibration', yesno_(stimObj.ApplyCalibration)};

try
    C = stimObj.Calibration;
    hasData = isa(C, 'stimgen.StimCalibration') && isstruct(C.CalibrationData) && ~isempty(C.CalibrationData);
    rows(end+1, :) = {'Calibration data', yesno_(hasData)};
    if hasData
        rows(end+1, :) = {'Reference level (dB SPL)', num_(C.ReferenceLevel, '%.2f')};
        ts = C.CalibrationTimestamp;
        if ~isnat(ts)
            rows(end+1, :) = {'Calibrated', char(string(ts, 'yyyy-MM-dd HH:mm'))};
        end
    end
catch
    rows(end+1, :) = {'Calibration data', 'unavailable'};
end
end


function rows = parameter_rows_(stimObj)
% parameter_rows_(stimObj) - Build the Parameter/Value cell array.

meta  = stimObj.get_prop_meta();
props = string(stimObj.UserProperties);

rows = cell(0, 2);
for k = 1:numel(props)
    propName = props(k);
    if ~isprop(stimObj, char(propName))
        continue
    end

    value = stimObj.(char(propName));

    label = propName;
    if isfield(meta, char(propName)) && isfield(meta.(char(propName)), 'label')
        label = string(meta.(char(propName)).label);
    end

    % propMeta labels and limits are in display units (ms for time
    % properties); scale the value to match before formatting.
    if isnumeric(value)
        value = value * stimgen.StimType.display_scale(meta, propName);
    end

    text = format_value_(value);
    if numel(value) > 1
        text = [text '  (variant)']; %#ok<AGROW>  text is rebuilt each iteration
    end

    rows(end+1, :) = {char(label), text}; %#ok<AGROW>
end

rows = [rows; {'Sample rate (Hz)', num_(stimObj.Fs, '%.7g')}];
end


function text = format_value_(value)
% format_value_(value) - Compact display text for a property value.
if islogical(value) && isscalar(value)
    text = yesno_(value);
elseif isnumeric(value) || islogical(value)
    value = double(value);
    if isempty(value)
        text = '(empty)';
    elseif isscalar(value)
        text = num2str(value, '%g');
    elseif numel(value) <= 8
        text = mat2str(value, 5);
    else
        text = sprintf('%d values, %g ... %g', numel(value), min(value), max(value));
    end
elseif isstring(value) || ischar(value)
    value = string(value);
    if isscalar(value)
        text = char(value);
    else
        text = char(strjoin(value, ', '));
    end
else
    text = ['<' class(value) '>'];
end
end


function text = num_(value, spec)
% num_(value, spec) - Format a scalar, rendering NaN as "n/a".
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    text = 'n/a';
    return
end
text = sprintf(spec, value);
end


function text = band_(edges)
% band_(edges) - Format a [low high] frequency band.
if numel(edges) ~= 2 || any(~isfinite(edges))
    text = 'n/a';
    return
end
text = sprintf('%.4g - %.4g', edges(1), edges(2));
end


function text = yesno_(tf)
% yesno_(tf) - Render a logical as yes/no.
if tf
    text = 'yes';
else
    text = 'no';
end
end
