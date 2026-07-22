function m = propMeta(~)
% propMeta(obj)
% Return display metadata for GUI-visible base properties.
% Subclasses can override this and merge with the base struct.
%
% Each field name matches a property name. Each value is a struct with:
%   label     (required) - display label string, including the unit
%   format    (optional) - printf format string for numeric fields
%   limits    (optional) - [min max] for numeric editfield, in DISPLAY units
%   scale     (optional) - display = property * scale (default 1). Time
%                          properties are stored in seconds and displayed
%                          in milliseconds, so they use scale = 1000.
%   widget    (optional) - 'numeric'|'text'|'checkbox'|'dropdown'
%   items     (optional) - dropdown display items
%   itemsData (optional) - dropdown underlying values
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
m = struct();
m.SoundLevel     = struct('label', 'Sound Level',          'format', '%.1f dB SPL', 'group', 'Level', 'order', 10);
m.ApplyCalibration = struct('label', 'Apply Calibration', 'group', 'Level', 'order', 20);
m.Duration       = struct('label', 'Duration (ms)',        'format', '%.1f ms',  'limits', [1 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 10);
m.WindowDuration = struct('label', 'Window Duration (ms)', 'format', '%.2f ms',  'limits', [0.001 10000], ...
                          'scale', 1000, 'group', 'Timing', 'order', 30);
m.ApplyWindow    = struct('label', 'Apply Window', 'group', 'Timing', 'order', 40);
m.VariantSelectionMode = struct('label', 'Variant Selection', 'widget', 'dropdown', ...
    'items', ["Serial" "ShuffleUniform" "ShuffleLeastUsed" "CustomSelector"], 'group', 'Variant', 'order', 10);
m.VariantCombinationMode = struct('label', 'Variant Combination', 'widget', 'dropdown', ...
    'items', ["Cartesian" "PairwiseStrict" "PairwiseScalarExpand"], 'group', 'Variant', 'order', 20);
m.VariantSelectorClass = struct('label', 'Variant Selector Class', 'group', 'Variant', 'order', 30);
m.VariantReselectOnUpdate = struct('label', 'Reselect Variant Each Update', 'group', 'Variant', 'order', 40);
end
