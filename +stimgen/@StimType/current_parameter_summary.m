function text = current_parameter_summary(obj)
% text = current_parameter_summary(obj)
% Return a compact summary of currently active stimulus parameters
% that differ from their class defaults. Only non-default values are included.
%
% Returns:
%   text - Comma-separated "label=value" string.

meta = obj.get_prop_meta();
propNames = string(obj.UserProperties);
propNames = propNames(~ismember(propNames, [ ...
    "VariantSelectionMode", ...
    "VariantCombinationMode", ...
    "VariantSelectorClass", ...
    "VariantSelectorConfig", ...
    "VariantReselectOnUpdate" ...
]));

% Build a map of property default values from metaclass
mc = metaclass(obj);
mcPropList = mc.PropertyList;
mcNames = string({mcPropList.Name});

% Report the already-active combination without re-triggering selection:
% selected_value() on a vectorized property auto-advances/reselects when
% called outside a locked update_signal cycle (VariantReselectOnUpdate),
% which would silently override a manual step_combination()/step_variant().
cycleWasActive = obj.variantCycleActive_;
obj.variantCycleActive_ = true;

parts = strings(1, 0);
for k = 1:numel(propNames)
    propName = propNames(k);
    if ~isprop(obj, char(propName))
        continue
    end

    try
        value = obj.selected_value(propName);
    catch
        value = obj.(char(propName));
    end

    % Skip if value matches the class default
    mcIdx = find(mcNames == propName, 1);
    if ~isempty(mcIdx) && mcPropList(mcIdx).HasDefault
        defVal = mcPropList(mcIdx).DefaultValue;
        if isequal(value, defVal)
            continue
        end
    end

    if isfield(meta, char(propName)) && isfield(meta.(char(propName)), 'label')
        label = string(meta.(char(propName)).label);
    else
        label = propName;
    end

    % Report in the same units the GUI shows (e.g. ms for time properties);
    % the unit itself is carried by the label.
    if isnumeric(value)
        value = value * stimgen.StimType.display_scale(meta, propName);
    end

    parts(end+1) = label + "=" + stimgen.StimType.format_summary_value_(value); %#ok<AGROW>
end

obj.variantCycleActive_ = cycleWasActive;

text = strjoin(parts, ", ");
