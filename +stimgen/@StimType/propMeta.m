function m = propMeta(~)
% propMeta(obj)
% Return display metadata for GUI-visible base properties.
% Subclasses can override this and merge with the base struct.
%
% Each field name matches a property name. Each value is a struct with:
%   label     (required) - display label string, including the unit
%   tooltip   (optional) - hover text for the label and the widget. One
%                          short line of plain text: what the parameter
%                          does, plus any non-obvious consequence. Both GUI
%                          builders apply it, and refresh_gui_widget
%                          re-applies it when the metadata changes.
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
%   group     (optional) - 'Waveform'|'Level'|'Timing'|'Variant', used by
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
m = struct();
m.SoundLevel     = struct('label', 'Sound Level',          'format', '%.1f dB SPL', 'group', 'Level', 'order', 10, ...
                          'tooltip', 'Target output level in dB SPL. Only meaningful with a loaded calibration. Enter a vector, e.g. 40:10:80, to make one variant per level.');
m.ApplyCalibration = struct('label', 'Apply Calibration', 'group', 'Level', 'order', 20, ...
                          'tooltip', 'Scale the waveform to the calibrated voltage for the requested level. Off: output is normalized only and Sound Level is nominal.');
m.Duration       = struct('label', 'Duration (ms)',        'format', '%.1f ms',  'limits', [1 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 10, ...
                          'tooltip', 'Total waveform length in ms. The onset/offset gate is applied inside this duration, not added to it.');
m.WindowDuration = struct('label', 'Window Duration (ms)', 'format', '%.2f ms',  'limits', [0.001 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 30, ...
                          'tooltip', 'Combined onset + offset gate length in ms; each ramp is half this value. Ignored when Apply Window is off.');
m.ApplyWindow    = struct('label', 'Apply Window', 'group', 'Timing', 'order', 40, ...
                          'tooltip', 'Gate the waveform on and off to suppress the spectral splatter caused by abrupt transitions.');
m.VariantSelectionMode = struct('label', 'Variant Selection', 'widget', 'dropdown', ...
    'items', ["Serial" "ShuffleUniform" "ShuffleLeastUsed" "CustomSelector"], 'group', 'Variant', 'order', 10, ...
    'tooltip', 'Order in which variant combinations are presented: Serial = table order; ShuffleUniform = random; ShuffleLeastUsed = random, favoring the least-presented; CustomSelector = defer to Variant Selector Class.');
m.VariantCombinationMode = struct('label', 'Variant Combination', 'widget', 'dropdown', ...
    'items', ["Cartesian" "PairwiseStrict" "PairwiseScalarExpand"], 'group', 'Variant', 'order', 20, ...
    'tooltip', 'How vector-valued parameters combine: Cartesian = every combination; PairwiseStrict = element-wise, all vectors must be the same length; PairwiseScalarExpand = element-wise with scalars repeated.');
m.VariantSelectorClass = struct('label', 'Variant Selector Class', 'group', 'Variant', 'order', 30, ...
    'tooltip', 'Class name of a custom variant selector, used only when Variant Selection is CustomSelector. Leave empty otherwise.');
m.VariantReselectOnUpdate = struct('label', 'Reselect Variant Each Update', 'group', 'Variant', 'order', 40, ...
    'tooltip', 'Pick the next variant every time the signal is regenerated. Off: the active variant stays put until you step it with < / >.');
end
