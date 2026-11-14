function tf = is_inactive_background_property_(obj, propName)
% tf = is_inactive_background_property_(obj, propName)
% True for a Background* property the current Background type does not use.
%
% A vector left in such a property must not count: with Background = "None"
% a BackgroundLevel of [40 50 60] typed earlier would otherwise triple the
% variant combinations (and a presenter's conditions) of a stimulus that has
% no background at all. get_variant_source_values_ and
% current_parameter_summary skip what this names.
%
%   None   every Background* property but Background itself
%   Noise  BackgroundFrequency
%   Tone   the band edges, the loop length and the seed
tf   = false;
name = string(propName);
if name == "Background" || ~any(name == stimgen.StimType.BackgroundProperties)
    return
end
switch obj.Background
    case "None"
        tf = true;
    case "Noise"
        tf = name == "BackgroundFrequency";
    case "Tone"
        tf = any(name == ["BackgroundHighPass","BackgroundLowPass", ...
            "BackgroundLoopDuration","BackgroundSeed"]);
end
end
