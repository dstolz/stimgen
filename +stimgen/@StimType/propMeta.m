function m = propMeta(obj)
% propMeta(obj)
% Return display metadata for GUI-visible base properties.
% Subclasses can override this and merge with the base struct.
%
% Each field name matches a property name. Each value is a struct with:
%   label     (required) - display label string, including the unit
%   tooltip   (optional) - hover text for the label and the widget. Never
%                          written out here: look it up with
%                          stimgen.util.tooltip(obj, propName), which reads
%                          the one catalog of tooltip text in
%                          +stimgen/tooltips.json. Both GUI builders apply
%                          it, and refresh_gui_widget re-applies it when the
%                          metadata changes.
%   format    (optional) - printf format string for numeric fields
%   limits    (optional) - [min max] for numeric editfield, in DISPLAY units
%   scale     (optional) - display = property * scale (default 1). Time
%                          properties are stored in seconds and displayed
%                          in milliseconds, so they use scale = 1000.
%   widget    (optional) - 'numeric'|'text'|'checkbox'|'dropdown'|'button'
%   items     (optional) - dropdown display items
%   itemsData (optional) - dropdown underlying values
%   text      (button)   - button caption
%   callback  (button)   - name of a public no-argument method on the
%                          stimulus object to invoke when pressed
%   group     (optional) - 'Waveform'|'Level'|'Timing'|'Background'|'Variant', used by
%                          stimgen.StimType.group_prop_meta to lay out the
%                          GUI in logically related sections. Defaults to
%                          'Waveform' when omitted, so a subclass with
%                          plain metadata needs no grouping changes.
%   order     (optional) - numeric sort key within its group (ascending).
%                          Properties without 'order' sort after ordered
%                          ones, in propMeta declaration order.
%
% NOTE: 'limits', 'format' and the value shown in the widget are all in
% display units. GUI code converts back to property units (seconds) on
% write, using stimgen.StimType.display_scale. Vectorizable properties
% render as expression text fields, which ignore 'format' entirely -- so
% the unit has to live in 'label' to be visible.
%
% NOTE: a 'button' entry is an action, not a property. Its field name is
% only a widget Tag, so it need not name a real property, and no value is
% read from or written to the object. See stimgen.SoundFile.BrowseFiles.
%
% NOTE: the set of fields returned may depend on the object's state -- the
% Background group lists only the rows the chosen Background uses. Both GUI
% generators rebuild their panel when an edit changes that set
% (interpret_gui, StimPlayer's set_prop_), so a widget is never left showing
% a property that no longer applies.
m = struct();
m.SoundLevel     = struct('label', 'Sound Level (dB SPL)', 'format', '%.1f dB SPL', 'group', 'Level', 'order', 10, ...
                          'tooltip', stimgen.util.tooltip(obj, 'SoundLevel'));
m.ApplyCalibration = struct('label', 'Apply Calibration', 'group', 'Level', 'order', 20, ...
                          'tooltip', stimgen.util.tooltip(obj, 'ApplyCalibration'));
m.Duration       = struct('label', 'Duration (ms)',        'format', '%.1f ms',  'limits', [1 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 10, ...
                          'tooltip', stimgen.util.tooltip(obj, 'Duration'));
m.WindowDuration = struct('label', 'Window Duration (ms)', 'format', '%.2f ms',  'limits', [0.001 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 30, ...
                          'tooltip', stimgen.util.tooltip(obj, 'WindowDuration'));
% The gate shape sits between the ramp length (order 30) and the on/off
% switch (order 40), since it only means anything between the two.
% WindowFcn accepts any single-argument window function by name, so a value
% set programmatically that the catalog does not list is appended as its own
% item: a dropdown cannot show a value it has no item for, and the
% alternative -- letting the widget rewrite the property to whatever happens
% to be first -- would gate the stimulus with a window nobody asked for.
wopts  = stimgen.StimType.window_options();
wLabel = [wopts.Label];
wName  = [wopts.Name];
current = string(obj.WindowFcn);
if ~any(wName == current)
    wLabel(end+1) = current;
    wName(end+1)  = current;
end
m.WindowFcn      = struct('label', 'Window Shape', 'widget', 'dropdown', ...
                          'items', wLabel, 'itemsData', wName, ...
                          'group', 'Timing', 'order', 35, ...
                          'tooltip', stimgen.util.tooltip(obj, 'WindowFcn'));
m.ApplyWindow    = struct('label', 'Apply Window', 'group', 'Timing', 'order', 40, ...
                          'tooltip', stimgen.util.tooltip(obj, 'ApplyWindow'));
m.VariantSelectionMode = struct('label', 'Variant Selection', 'widget', 'dropdown', ...
    'items', ["Serial" "ShuffleUniform" "ShuffleLeastUsed" "CustomSelector"], 'group', 'Variant', 'order', 10, ...
    'tooltip', stimgen.util.tooltip(obj, 'VariantSelectionMode'));
m.VariantCombinationMode = struct('label', 'Variant Combination', 'widget', 'dropdown', ...
    'items', ["Cartesian" "PairwiseStrict" "PairwiseScalarExpand"], 'group', 'Variant', 'order', 20, ...
    'tooltip', stimgen.util.tooltip(obj, 'VariantCombinationMode'));
m.VariantSelectorClass = struct('label', 'Variant Selector Class', 'group', 'Variant', 'order', 30, ...
    'tooltip', stimgen.util.tooltip(obj, 'VariantSelectorClass'));
m.VariantReselectOnUpdate = struct('label', 'Reselect Variant Each Update', 'group', 'Variant', 'order', 40, ...
    'tooltip', stimgen.util.tooltip(obj, 'VariantReselectOnUpdate'));

if obj.supports_background_()
    m = add_background_meta_(obj, m);
end
end


function m = add_background_meta_(obj, m)
% The Background group: the type, then only the settings that type uses.
% "None" is one row, so a stimulus with no background costs the panel one
% line; choosing a type rebuilds the panel with the rest (see the NOTE above).
m.Background = struct('label', 'Background', 'widget', 'dropdown', ...
    'items', ["None" "Noise" "Tone"], 'group', 'Background', 'order', 10, ...
    'tooltip', stimgen.util.tooltip(obj, 'Background'));

switch obj.Background
    case "Noise"
        m.BackgroundLevel = level_meta_(obj);
        m.BackgroundHighPass = struct('label', 'Background High Pass Fc (Hz)', ...
            'format', '%.1f Hz', 'limits', [100 40000], 'group', 'Background', 'order', 30, ...
            'tooltip', stimgen.util.tooltip(obj, 'BackgroundHighPass'));
        m.BackgroundLowPass = struct('label', 'Background Low Pass Fc (Hz)', ...
            'format', '%.1f Hz', 'limits', [100 40000], 'group', 'Background', 'order', 40, ...
            'tooltip', stimgen.util.tooltip(obj, 'BackgroundLowPass'));
        % Stored in seconds, shown in ms like every other time property.
        m.BackgroundLoopDuration = struct('label', 'Background Loop (ms)', ...
            'format', '%.0f ms', 'limits', [1000 60000], 'scale', 1000, ...
            'group', 'Background', 'order', 50, ...
            'tooltip', stimgen.util.tooltip(obj, 'BackgroundLoopDuration'));
        m.BackgroundSeed = struct('label', 'Background Seed', ...
            'format', '%d', 'limits', [0 2^31-1], 'group', 'Background', 'order', 60, ...
            'tooltip', stimgen.util.tooltip(obj, 'BackgroundSeed'));
    case "Tone"
        m.BackgroundLevel = level_meta_(obj);
        m.BackgroundFrequency = struct('label', 'Background Frequency (Hz)', ...
            'format', '%.1f Hz', 'limits', [100 40000], 'group', 'Background', 'order', 30, ...
            'tooltip', stimgen.util.tooltip(obj, 'BackgroundFrequency'));
end
end


function pm = level_meta_(obj)
pm = struct('label', 'Background Level (dB SPL)', 'format', '%.1f dB SPL', ...
    'group', 'Background', 'order', 20, ...
    'tooltip', stimgen.util.tooltip(obj, 'BackgroundLevel'));
end
