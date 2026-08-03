function txt = tooltip(source, key)
% txt = stimgen.util.tooltip(source, key)
%
% Hover help for one stimgen parameter or GUI control, read from the single
% tooltip catalog +stimgen/tooltips.json. Every tooltip string in the
% package lives in that file; nothing hardcodes its own text.
%
% Parameters:
%   source - a stimgen object, or a section name (char/string) for GUI code
%            that has no stimulus object to hand, e.g. "StimPlayer".
%   key    - catalog key, normally the property name.
%
% Returns:
%   txt    - the tooltip text, or '' if the key is not in the catalog.
%
% Given an object, the object's own class section is searched first and then
% each superclass section in turn, so stimgen.Tone picks up 'Frequency' from
% the Tone section and 'Duration' from StimType. A subclass overrides an
% inherited entry simply by declaring the same key -- see ClickTrain.Duration,
% which retitles the base-class Duration as the length of the click train.
%
% A property whose text depends on another property declares one key per
% case, named Property_Case by convention -- see Tone.WindowDuration_Proportional.
%
% An unknown key returns '' and logs a warning: a missing tooltip should be
% noticed, but must never stop a GUI from building.
%
% Example:
%   m.Frequency = struct('label', 'Frequency', 'format', '%.1f Hz', ...
%                        'tooltip', stimgen.util.tooltip(obj, 'Frequency'));
%
% See also stimgen.StimType.propMeta, stimgen.StimType.create_gui

narginchk(2, 2)

key      = char(key);
sections = section_chain_(source);
catalog  = load_catalog_();

for i = 1:numel(sections)
    s = sections{i};
    if isfield(catalog, s) && isfield(catalog.(s), key)
        txt = catalog.(s).(key);
        return
    end
end

txt = '';
stimgen.util.vprintf(1, 1, 'No tooltip for ''%s'' under section %s in %s', ...
    key, strjoin(sections, ' -> '), catalog_path_());
end


% =========================================================================

function names = section_chain_(source)
% names = section_chain_(source) - Catalog sections to search, most specific first.
% Class names are stored without their package prefix, so stimgen.Tone is
% looked up as "Tone".
if ischar(source) || isstring(source)
    name = short_name_(char(source));
    % A section name that is also a class inherits its parents' entries,
    % matching what an instance of it would resolve.
    mc = meta.class.fromName(['stimgen.' name]);
    if isempty(mc)
        mc = meta.class.fromName(char(source));
    end
    if isempty(mc)
        names = {name};
        return
    end
else
    mc = metaclass(source);
end

% Breadth-first over the class hierarchy. Not superclasses(), which omits
% classes marked Hidden -- and stimgen.StimType is one, so it would drop the
% section holding every shared parameter.
names = {};
queue  = mc;
while ~isempty(queue)
    c        = queue(1);
    queue(1) = [];
    n = short_name_(c.Name);
    if ~any(strcmp(names, n))
        names{end+1} = n; %#ok<AGROW>
    end
    queue = [queue; c.SuperclassList(:)]; %#ok<AGROW>
end
names = names(:);
end


function s = short_name_(name)
% s = short_name_(name) - Strip the package prefix from a class name.
parts = split(string(name), '.');
s     = char(parts(end));
end


function c = load_catalog_()
% c = load_catalog_() - Decoded tooltip catalog, cached until the file changes.
% Re-stats on every call so that editing tooltips.json takes effect without
% having to clear the function.
persistent cache stamp

c = struct();

f = catalog_path_();
d = dir(f);
if isempty(d)
    if ~isequal(stamp, 'missing')
        stamp = 'missing';
        cache = struct();
        stimgen.util.vprintf(0, 1, 'Tooltip catalog not found: %s. GUIs will be built without hover help.', f);
    end
    return
end

thisStamp = [d(1).datenum d(1).bytes];
if ~isequal(stamp, thisStamp)
    stamp = thisStamp;
    try
        cache = jsondecode(fileread(f));
    catch ME
        cache = struct();
        stimgen.util.vprintf(0, 1, 'Tooltip catalog %s is not valid JSON (%s). GUIs will be built without hover help.', ...
            f, ME.message);
    end
end

if isstruct(cache)
    c = cache;
end
end


function f = catalog_path_()
% f = catalog_path_() - Full path of the tooltip catalog.
% This file is +stimgen/+util/tooltip.m, so the catalog is one level up.
f = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'tooltips.json');
end
