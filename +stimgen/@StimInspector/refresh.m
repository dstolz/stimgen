function refresh(obj)
% refresh(obj)
% Re-read the inspected stimulus and redraw every table and plot.
%
% Safe to call at any time: when a source provider is attached the stimulus
% is resolved through it first, so the window follows whatever the provider
% currently points at. The signal is generated only when the stimulus does
% not already have one, and no property is written back.
%
% The scale is read before anything is drawn: a stimgen.CapturedSignal with a
% microphone sensitivity is shown as sound pressure, anything else as the
% signal it is (see read_capture_).

if ~obj.is_open()
    return
end

[stimObj, label] = obj.resolve_source_();

if isempty(stimObj)
    obj.Signal_ = [];
    obj.Fs_     = 1;
    obj.read_capture_([]);
    obj.Metrics = stimgen.StimInspector.signal_metrics([], 1, obj.NHarmonics);
    obj.handles.HeaderLabel.Text = 'No stimulus selected.';
    obj.update_info_([], obj.Metrics);
    obj.update_plots_(obj.Metrics);
    obj.set_status_("Select a stimulus to inspect.");
    return
end

% Generate lazily, exactly as StimPlayer's signal plot does.
try
    if isempty(stimObj.Signal)
        stimObj.update_signal();
    end
catch ME
    stimgen.util.vprintf(0, 1, 'StimInspector: could not generate the stimulus signal.');
    stimgen.util.vprintf(0, 1, ME);
    obj.set_status_("Could not generate signal: " + string(ME.message), isError=true);
end

y = double(stimObj.Signal);
% Fs is non-vectorizable, so reading it directly cannot advance the variant
% cycle.  The time base is derived from numel(y) rather than stimObj.Time for
% the same reason: Time reads Duration through the variant selector.
fs = double(stimObj.Fs);

obj.Signal_ = y;
obj.Fs_     = fs;
obj.read_capture_(stimObj);
obj.Metrics = stimgen.StimInspector.signal_metrics(y, fs, obj.NHarmonics);

% Two inspectors are often open at once -- one on the stimulus, one on what
% came back -- so the window says which it is.
if obj.is_capture_()
    obj.Figure.Name = 'Stimulus Inspector — Recording';
else
    obj.Figure.Name = 'Stimulus Inspector';
end

update_header_(obj, stimObj, label, obj.Metrics);
obj.update_info_(stimObj, obj.Metrics);
obj.update_plots_(obj.Metrics);

if isempty(y)
    obj.set_status_("The selected stimulus has no signal.", isError=true);
elseif ~obj.Metrics.Valid
    obj.set_status_("Signal is empty, constant or non-finite; metrics are unavailable.", isError=true);
elseif obj.is_capture_()
    capture_status_(obj);
elseif ~obj.Metrics.Tonal
    % Tonality is the fraction of spectral power at the dominant peak; it is
    % what gates this warning, so report it rather than spectral flatness.
    obj.set_status_(sprintf( ...
        'Broadband signal (tonality %.2f) — THD, SNR, SINAD and SFDR assume a dominant sinusoid and are only indicative here.', ...
        obj.Metrics.Tonality));
else
    obj.set_status_("Ready.");
end
end % refresh


% =========================================================================

function update_header_(obj, stimObj, label, M)
% update_header_(obj, stimObj, label, M) - Refresh the one-line title bar.
classParts = split(string(class(stimObj)), ".");

try
    info = stimObj.get_variant_info();
    comboText = sprintf('combo %d/%d', info.ActiveIndex, info.NumCombinations);
catch
    comboText = 'combo -/-';
end

nameText = strtrim(string(label));
if strlength(nameText) == 0
    nameText = classParts(end);
end

text = sprintf('%s  [%s]   |   %s   |   %.7g Hz   |   %d samples (%.2f ms)', ...
    nameText, classParts(end), comboText, M.Fs, M.N, M.DurationMs);
if obj.Scale.Acoustic
    text = sprintf('%s   |   mic %.4g mV/Pa', text, obj.Scale.MicSensitivity * 1e3);
end
obj.handles.HeaderLabel.Text = text;
end


function capture_status_(obj)
% capture_status_(obj) - One-line verdict on a recording.
% The headline levels, the comparison with what was asked for, and the floor
% under them; the warnings themselves are listed in full beside the metrics
% table, so the line only counts them.
S = obj.sound_levels_();
N = obj.noise_levels_();
m = obj.as_calibrated_();

if obj.Scale.Acoustic
    unit = 'dB SPL';
    head = sprintf('LZeq %.1f dB SPL, LAeq %.1f dBA', ...
        S.Leq(S.Weightings == "Z"), S.Leq(S.Weightings == "A"));
else
    unit = 'dB re 1 V';
    head = sprintf('Recording in volts: %.1f dB re 1 V rms', S.Leq(S.Weightings == "Z"));
    if ~obj.Scale.Available
        head = [head ' (no microphone sensitivity came with it)'];
    end
end

parts = {head};
if ~isempty(m)
    if obj.Scale.Acoustic
        measured = m.level_db;
    else
        measured = m.level_dbv;
    end
    if isfinite(m.error_db)
        parts{end+1} = sprintf('%.1f %s as calibrated (%s), %+.1f dB from the %.1f requested', ...
            measured, unit, m.level_reference, m.error_db, m.requested_db);
    elseif isfinite(measured)
        parts{end+1} = sprintf('%.1f %s as calibrated (%s)', measured, unit, m.level_reference);
    end
end
if ~isempty(N)
    zi = S.Weightings == "Z";
    parts{end+1} = sprintf('floor %.1f %s (SNR %.1f dB)', N.Leq(zi), unit, ...
        S.Leq(zi) - N.Leq(zi));
end

text = strjoin(parts, '; ') + ".";
nw = numel(obj.Warnings_);
if nw > 0
    text = sprintf('%s  %d warning(s) — see the list beside the metrics.', text, nw);
end
obj.set_status_(text, isError=nw > 0);
end
