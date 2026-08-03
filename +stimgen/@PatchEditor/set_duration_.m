function set_duration_(obj, src, event)
% set_duration_(obj, src, event)
% Commit an edit to the stimulus Duration from the Output panel's field.
%
% Duration belongs to the stimulus rather than to any one node, so it is not
% reachable through the selection-scoped inspector. The write path is the same
% one node parameters take (local_set_param in build_inspector_) and the same
% one StimPlayer's panel takes: parse the text as an expression in display
% units, then divide by the display scale exactly once.
%
% Duration is vectorizable, so a vector typed here becomes a variant axis.

meta = obj.Patch.get_prop_meta();
sc   = stimgen.StimType.display_scale(meta, 'Duration');

try
    obj.Patch.Duration = ...
        obj.Patch.evalPropertyExpression('Duration', char(string(event.Value))) / sc;
    obj.set_status_("Duration updated.", "info");
catch ME
    % Restore the field from the property, which still holds the last value
    % that validated.
    try
        src.Value = stimgen.PatchEditor.format_field_value_(obj.Patch.Duration * sc);
    catch
        src.Value = event.PreviousValue;
    end
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
