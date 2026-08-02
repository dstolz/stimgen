function refresh(obj)
% refresh(obj)
% Re-read the inspected stimulus and redraw every table and plot.
%
% Safe to call at any time: when a source provider is attached the stimulus
% is resolved through it first, so the window follows whatever the provider
% currently points at. The signal is generated only when the stimulus does
% not already have one, and no property is written back.

if ~obj.is_open()
    return
end

[stimObj, label] = obj.resolve_source_();

if isempty(stimObj)
    obj.Signal_ = [];
    obj.Fs_     = 1;
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
obj.Metrics = stimgen.StimInspector.signal_metrics(y, fs, obj.NHarmonics);

update_header_(obj, stimObj, label, obj.Metrics);
obj.update_info_(stimObj, obj.Metrics);
obj.update_plots_(obj.Metrics);

if isempty(y)
    obj.set_status_("The selected stimulus has no signal.", isError=true);
elseif ~obj.Metrics.Valid
    obj.set_status_("Signal is empty, constant or non-finite; metrics are unavailable.", isError=true);
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

obj.handles.HeaderLabel.Text = sprintf('%s  [%s]   |   %s   |   %.7g Hz   |   %d samples (%.2f ms)', ...
    nameText, classParts(end), comboText, M.Fs, M.N, M.DurationMs);
end
