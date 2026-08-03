function [kinds, descriptions] = list()
% [kinds, descriptions] = stimgen.components.list()
% Enumerate the component types available to a stimgen.Patch.
%
% Discovery is filename-based, mirroring stimgen.StimType.list: every class in
% +stimgen/+components that derives from stimgen.components.Component is
% offered, so dropping in a new component file makes it appear in the patch
% editor palette with no registry to update.
%
% Returns:
%   kinds        - 1-by-N string array of Kind names
%   descriptions - 1-by-N string array of one-line summaries

pth = fileparts(mfilename('fullpath'));
d   = dir(fullfile(pth, '*.m'));
f   = string({d.name});
f(f == "Component.m" | f == "list.m") = [];

kinds        = string.empty(1,0);
descriptions = string.empty(1,0);

for i = 1:numel(f)
    name = extractBefore(f(i), strlength(f(i)) - 1);
    mc   = meta.class.fromName("stimgen.components." + name);
    if isempty(mc) || mc.Abstract || ~(mc < ?stimgen.components.Component)
        continue
    end
    obj = feval("stimgen.components." + name);
    kinds(end+1)        = obj.Kind;        %#ok<AGROW>
    descriptions(end+1) = obj.Description; %#ok<AGROW>
end

[kinds, order] = sort(kinds);
descriptions   = descriptions(order);
end
