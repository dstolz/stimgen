function sections = group_prop_meta(meta)
% sections = stimgen.StimType.group_prop_meta(meta)
% Bucket a propMeta() struct into canonically ordered display sections.
%
% Returns a cell array of {groupName, propNames} pairs in a fixed group
% order: Waveform, Level, Timing, Variant. A group is omitted if none of
% the supplied properties belong to it.
%
% Each propMeta entry may declare:
%   group (optional) - 'Waveform'|'Level'|'Timing'|'Variant'. Properties
%                       without a 'group' field default to 'Waveform',
%                       so a subclass with plain metadata needs no
%                       grouping changes.
%   order (optional) - numeric sort key within its group (ascending).
%                       Properties without 'order' sort after ordered
%                       ones, in propMeta declaration order.
GROUP_ORDER = ["Waveform", "Level", "Timing", "Variant"];

allProps = fieldnames(meta);
groupOf  = repmat("Waveform", numel(allProps), 1);
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

sections = {};
for g = 1:numel(GROUP_ORDER)
    idx = find(groupOf == GROUP_ORDER(g));
    if isempty(idx)
        continue
    end
    [~, sidx] = sort(orderOf(idx), 'ascend');
    idx = idx(sidx);
    sections{end+1} = {char(GROUP_ORDER(g)), allProps(idx)}; %#ok<AGROW>
end
end
