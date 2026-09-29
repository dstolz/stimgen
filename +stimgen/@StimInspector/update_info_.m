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
%
% A recording gets its own level rows: in pascals and dB SPL when it carries a
% microphone sensitivity and is shown as sound, in volts otherwise, followed
% by what its stimulus asked for, the noise floor it sat on, and how it was
% captured. Its warnings go to the list beside the tables, where a sentence
% has room to be read. A generated stimulus gets the rows it always had.

h = obj.handles;

if isempty(stimObj) || ~isvalid(stimObj)
    h.MetricsTable.Data = cell(0, 2);
    h.ParamsTable.Data  = cell(0, 2);
    h.ParamsTable.Parent.Parent.Title = 'Parameters';
    show_warnings_(obj, string.empty(1, 0));
    return
end

% The parameter table of a recording describes what was PLAYED: the snapshot
% of the stimulus it carries. Its own properties would be misleading there --
% a CapturedSignal has a Sound Level only because every StimType does.
paramsPanel = h.ParamsTable.Parent.Parent;
if obj.is_capture_()
    h.MetricsTable.Data = capture_rows_(obj, stimObj, M);
    show_warnings_(obj, obj.Warnings_);
    played = stimObj.Played;
    if ~isempty(played) && isa(played, 'stimgen.StimType') && isvalid(played)
        parts = split(string(class(played)), ".");
        paramsPanel.Title = char("Played: " + parts(end));
        h.ParamsTable.Data = parameter_rows_(played);
    else
        paramsPanel.Title = 'Played: not recorded';
        h.ParamsTable.Data = {'Sample rate (Hz)', num_(stimObj.Fs, '%.7g')};
    end
else
    h.MetricsTable.Data = metric_rows_(stimObj, M);
    show_warnings_(obj, string.empty(1, 0));
    paramsPanel.Title = 'Parameters';
    h.ParamsTable.Data = parameter_rows_(stimObj);
end
end % update_info_


% =========================================================================

function show_warnings_(obj, warnings)
% show_warnings_(obj, warnings) - Fill the warning list, or fold it away.
% The row is collapsed to nothing when there is nothing to say, so a clean
% record -- and every generated stimulus -- keeps the full height for its
% tables.
h = obj.handles;
if ~isfield(h, 'WarningsArea') || ~isvalid(h.WarningsArea)
    return
end
heights = h.InfoGrid.RowHeight;
if isempty(warnings)
    h.WarningsArea.Value = {''};
    h.WarningsPanel.Visible = 'off';
    heights{2} = 0;
else
    h.WarningsArea.Value = cellstr("• " + warnings(:));
    h.WarningsPanel.Visible = 'on';
    heights{2} = obj.WarningsHeight;
end
h.InfoGrid.RowHeight = heights;
end


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
    };

rows = [rows; spectrum_rows_(M, 'Fundamental (dB)', num_(M.FundamentalDb, '%.2f'))];
rows = [rows; distortion_rows_(M)];
rows = [rows; stimulus_rows_(stimObj)];
end


function rows = capture_rows_(obj, stimObj, M)
% capture_rows_(obj, stimObj, M) - Metric rows for a recording.
% Every level comes from stimgen.util.sound_levels or level_as_calibrated,
% in the units on screen, and DC is out of all of them: an offset in the
% input stage is not sound. The DC row itself stays in volts, which is the
% only unit it means anything in.
acoustic = obj.Scale.Acoustic;
S = obj.sound_levels_();
N = obj.noise_levels_();
m = obj.as_calibrated_();
z = S.Weightings == "Z";
a = S.Weightings == "A";
c = S.Weightings == "C";

y  = obj.Signal_;
ac = y - mean(y);
if acoustic
    k   = 1 / obj.Scale.MicSensitivity;   % V -> Pa
    dbU = 'dB SPL';
else
    dbU = 'dB re 1 V';
end

rows = { ...
    'Samples',            num_(M.N, '%d'); ...
    'Duration (ms)',      num_(M.DurationMs, '%.3f'); ...
    'Sample rate (Hz)',   num_(M.Fs, '%.7g')};

if acoustic
    rows = [rows; {
        '— Sound pressure —',       ''; ...
        'Peak (Pa)',                num_(max(abs(ac)) * k, '%.4g'); ...
        'Peak-to-peak (Pa)',        num_(M.PeakToPeak * k, '%.4g'); ...
        'RMS (Pa)',                 num_(rms_(ac) * k, '%.4g'); ...
        'DC offset (V)',            num_(M.DC, '%.3g'); ...
        'Crest factor (dB)',        num_(S.Lpeak(z) - S.Leq(z), '%.2f'); ...
        'Mic sensitivity (mV/Pa)',  num_(obj.Scale.MicSensitivity * 1e3, '%.4g'); ...
        '— Sound level (dB re 20 µPa) —', ''; ...
        'LZeq',                     num_(S.Leq(z), '%.2f'); ...
        'LAeq (dBA)',               num_(S.Leq(a), '%.2f'); ...
        'LCeq (dBC)',               num_(S.Leq(c), '%.2f'); ...
        'LZpeak',                   num_(S.Lpeak(z), '%.2f'); ...
        'LCpeak',                   num_(S.Lpeak(c), '%.2f'); ...
        'peSPL (sine of equal peak)',   num_(S.peSPL, '%.2f'); ...
        'ppeSPL (sine of equal p-p)',   num_(S.ppeSPL, '%.2f'); ...
        'LAFmax (dBA)',             num_(S.LFmax(a), '%.2f'); ...
        'LASmax (dBA)',             num_(S.LSmax(a), '%.2f'); ...
        'LAE, SEL re 1 s (dBA)',    num_(S.LE(a), '%.2f')}];
else
    rows = [rows; {
        '— Level (volts) —',        ''; ...
        'Peak (V)',                 num_(M.Peak, '%.5g'); ...
        'Peak-to-peak (V)',         num_(M.PeakToPeak, '%.5g'); ...
        'RMS (V)',                  num_(M.RMS, '%.5g'); ...
        'DC offset (V)',            num_(M.DC, '%.3g'); ...
        'Peak (dB re 1 V)',         num_(M.PeakDb, '%.2f'); ...
        'RMS (dB re 1 V)',          num_(M.RmsDb, '%.2f'); ...
        'Crest factor (dB)',        num_(M.CrestFactorDb, '%.2f')}];
    if obj.Scale.Available
        rows(end+1, :) = {'Sound level', 'switch Units to Pa, dB SPL'};
    else
        rows(end+1, :) = {'Sound level', 'n/a — no mic sensitivity'};
    end
end

% --- What was asked for, measured the way its calibration was ----------
if ~isempty(m)
    if acoustic
        measured = m.level_db;
    else
        measured = m.level_dbv;
    end
    requested = num_(m.requested_db, '%.2f');
    if isfinite(m.requested_db) && ~m.calibrated
        requested = [requested ' (nominal)'];
    end
    rows = [rows; {
        '— Against the request —',  ''; ...
        'Requested (dB SPL)',       requested; ...
        ['Measured (' dbU ')'],     num_(measured, '%.2f'); ...
        'Measured as',              char(m.level_reference); ...
        'Error (dB)',               num_(m.error_db, '%+.2f')}];
end

% --- The floor the record sat on ----------------------------------------
if ~isempty(N)
    rows = [rows; {
        '— Noise floor —',          ''; ...
        ['Floor LZeq (' dbU ')'],   num_(N.Leq(z), '%.2f'); ...
        'Floor LAeq (A-wtd)',       num_(N.Leq(a), '%.2f'); ...
        'SNR, LZeq (dB)',           num_(S.Leq(z) - N.Leq(z), '%.2f'); ...
        'SNR, LAeq (dB)',           num_(S.Leq(a) - N.Leq(a), '%.2f')}];
end

% --- Spectrum and distortion, with the fundamental on the record's scale -
f0Level = obj.to_db_(10 .^ (M.FundamentalDb / 20) / sqrt(2));
rows = [rows; spectrum_rows_(M, ['Fundamental (' dbU ')'], num_(f0Level, '%.2f'))];
rows = [rows; distortion_rows_(M)];

% --- How it was captured -------------------------------------------------
p = obj.Provenance_;
rows(end+1, :) = {'— Capture —', ''};
if isfield(p, 'delay_s')
    rows(end+1, :) = {'Conduction delay (ms)', num_(p.delay_s * 1e3, '%.3f')};
end
if isfield(p, 'repeats')
    rows(end+1, :) = {'Acquisitions averaged', num_(p.repeats, '%d')};
end
if isfield(p, 'pre_delay_s') && isfield(p, 'post_delay_s')
    rows(end+1, :) = {'Lead-in / tail (ms)', sprintf('%s / %s', ...
        num_(p.pre_delay_s * 1e3, '%.0f'), num_(p.post_delay_s * 1e3, '%.0f'))};
end
if isfield(p, 'regenerated_at_hz') && isfinite(p.regenerated_at_hz)
    rows(end+1, :) = {'Played at (Hz)', ...
        sprintf('%s (regenerated from %s)', num_(p.regenerated_at_hz, '%.7g'), ...
        num_(p.stimulus_fs, '%.7g'))};
end
if strlength(stimObj.SourceLabel) > 0
    rows(end+1, :) = {'Recording of', char(stimObj.SourceLabel)};
end
end


function rows = spectrum_rows_(M, fundamentalLabel, fundamentalValue)
% spectrum_rows_(M, ...) - The spectral-shape rows, with the fundamental's
% level in whichever unit the caller reads it in.
rows = { ...
    '— Spectrum —',       ''; ...
    'Fundamental (Hz)',   num_(M.FundamentalHz, '%.4g'); ...
    fundamentalLabel,     fundamentalValue; ...
    'Spectral centroid (Hz)', num_(M.CentroidHz, '%.4g'); ...
    'RMS bandwidth (Hz)', num_(M.RmsBandwidthHz, '%.4g'); ...
    '-3 dB band (Hz)',    band_(M.Band3dB); ...
    '-20 dB band (Hz)',   band_(M.Band20dB); ...
    'Spectral flatness',  num_(M.Flatness, '%.4f'); ...
    'Tonality (0-1)',     num_(M.Tonality, '%.3f')};
end


function rows = distortion_rows_(M)
% distortion_rows_(M) - THD and the related ratios; unit-free by nature.
rows = { ...
    '— Distortion —',     ''; ...
    'THD (%)',            num_(M.ThdPercent, '%.4f'); ...
    'THD (dB)',           num_(M.ThdDb, '%.2f'); ...
    'SNR (dB)',           num_(M.SnrDb, '%.2f'); ...
    'SINAD (dB)',         num_(M.SinadDb, '%.2f'); ...
    'SFDR (dB)',          num_(M.SfdrDb, '%.2f')};
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


function r = rms_(y)
% rms_(y) - Root mean square; 0 for an empty record.
if isempty(y)
    r = 0;
else
    r = sqrt(mean(y .^ 2));
end
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
