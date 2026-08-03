function sections = group_prop_meta(meta)
% sections = stimgen.StimType.group_prop_meta(meta)
% Bucket a propMeta() struct into ordered display sections.
%
% Returns a cell array of {groupName, propNames} pairs. A group is omitted if
% none of the supplied properties belong to it.
%
% Group order is:
%   Waveform, <any custom groups>, Level, Timing, Variant
%
% Custom groups -- any group name that is not one of the four canonical ones --
% appear between Waveform and Level, in the order they are first encountered
% while walking the propMeta fields. This is what lets a composite stimulus
% give each of its components its own section (e.g. stimgen.Patch emitting
% "Osc1 (Oscillator)"). Classes that only use canonical names are unaffected.
%
% Each propMeta entry may declare:
%   group (optional) - a section name. Properties without a 'group' field
%                       default to 'Waveform', so a subclass with plain
%                       metadata needs no grouping changes.
%   order (optional) - numeric sort key within its group (ascending).
%                       Properties without 'order' sort after ordered
%                       ones, in propMeta declaration order.
LEADING_GROUP  = "Waveform";
TRAILING_ORDER = ["Level", "Timing", "Variant"];

allProps = fieldnames(meta);
groupOf  = repmat(LEADING_GROUP, numel(allProps), 1);
orderOf  = inf(numel(allProps), 1);
for k = 1:numel(allProps)
    pm = meta.(allProps{k});
    if isfield(pm, 'group')
        groupOf(k) = string(pm.group);
    end
    if isfield(pm, 'order')
        orderOf(k) = pm.order;
    end
end

% Custom groups keep first-appearance order; 'unique' with 'stable' preserves it.
presentGroups = unique(groupOf, 'stable');
customGroups  = presentGroups(~ismember(presentGroups, [LEADING_GROUP, TRAILING_ORDER]));
groupOrder    = [LEADING_GROUP, reshape(customGroups, 1, []), TRAILING_ORDER];

sections = {};
for g = 1:numel(groupOrder)
    idx = find(groupOf == groupOrder(g));
    if isempty(idx)
        continue
    end
    [~, sidx] = sort(orderOf(idx), 'ascend');
    idx = idx(sidx);
    sections{end+1} = {char(groupOrder(g)), allProps(idx)}; %#ok<AGROW>
end
end
