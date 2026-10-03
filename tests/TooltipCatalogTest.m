classdef TooltipCatalogTest < matlab.unittest.TestCase
    % Every tooltip key the package asks for resolves in +stimgen/tooltips.json.
    %
    % Two checks. A runtime one: every concrete stimulus's propMeta() carries
    % a non-empty tooltip on every entry. A source scan: every literal key
    % passed to stimgen.util.tooltip -- with an object (resolved against the
    % calling class and its superclasses, as the lookup does), with a section
    % name, or through a one-argument alias such as
    %   tip = @(key) stimgen.util.tooltip('StimPlayer', key);
    % -- names an entry in the catalog. A key built at run time (a variable)
    % is out of reach of the scan.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties
        Root
    end

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            testCase.Root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.Root));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function catalogIsValidJson(testCase)
            f = fullfile(testCase.Root, '+stimgen', 'tooltips.json');
            testCase.assertTrue(isfile(f), 'tooltips.json is missing');
            c = jsondecode(fileread(f));
            testCase.verifyClass(c, 'struct');
            testCase.verifyTrue(isfield(c, 'StimType'));
        end

        function everyPropMetaEntryHasATooltip(testCase)
            names = stimgen.StimType.list();
            for k = 1:numel(names)
                obj = feval(['stimgen.' names{k}], 'ApplyCalibration', false);
                verify_prop_meta_tooltips_(testCase, obj, names{k});
            end
        end

        function toneWindowMethodTooltipsResolve(testCase)
            % WindowDuration swaps its metadata, tooltip included, with the
            % window method; each case has its own catalog key.
            for method = ["Duration", "Proportional", "#Periods"]
                t = stimgen.Tone('ApplyCalibration', false, 'WindowMethod', method);
                verify_prop_meta_tooltips_(testCase, t, "Tone/" + method);
            end
        end

        function everyLiteralKeyInSourceResolves(testCase)
            pkg = fullfile(testCase.Root, '+stimgen');
            files = dir(fullfile(pkg, '**', '*.m'));
            nChecked = 0;
            for k = 1:numel(files)
                ffn = fullfile(files(k).folder, files(k).name);
                [~, parent] = fileparts(files(k).folder);
                if startsWith(parent, '@')
                    section = extractAfter(string(parent), 1);
                else
                    [~, section] = fileparts(files(k).name);
                    section = string(section);
                end

                refs = tooltip_refs_(fileread(ffn), section);
                for r = 1:size(refs, 1)
                    txt = stimgen.util.tooltip(char(refs(r, 1)), char(refs(r, 2)));
                    testCase.verifyNotEmpty(txt, sprintf( ...
                        'No tooltip for key "%s" under section "%s" (used in %s)', ...
                        refs(r, 2), refs(r, 1), ffn));
                    nChecked = nChecked + 1;
                end
            end
            % The scan has to be finding the calls for the check to mean
            % anything: propMeta alone holds dozens.
            testCase.verifyGreaterThan(nChecked, 50);
        end

    end
end


% ====================================================================== %

function verify_prop_meta_tooltips_(testCase, obj, label)
m  = obj.get_prop_meta();
fn = fieldnames(m);
testCase.verifyNotEmpty(fn, sprintf('%s: propMeta is empty', label));
for k = 1:numel(fn)
    e = m.(fn{k});
    ok = isstruct(e) && isfield(e, 'tooltip') && ~isempty(e.tooltip);
    testCase.verifyTrue(ok, sprintf('%s: propMeta entry "%s" has no tooltip', label, fn{k}));
end
end


function refs = tooltip_refs_(txt, fileSection)
% refs - (n,2) string of [section key] for every literal tooltip lookup.
refs = strings(0, 2);

% Full-line comments are documentation, not lookups (tooltip.m's own
% example among them).
lines = splitlines(string(txt));
lines = lines(~startsWith(strtrim(lines), '%'));
code  = char(strjoin(lines, newline));   % char: regexp tokens come back as char

q = '[''"]';   % either quote

% stimgen.util.tooltip(obj, 'Key') -- resolved against the calling class.
t = regexp(code, ['stimgen\.util\.tooltip\(\s*obj\s*,\s*' q '(\w+)' q '\s*\)'], 'tokens');
for k = 1:numel(t)
    refs(end+1, :) = [fileSection, string(t{k}{1})]; %#ok<AGROW>
end

% stimgen.util.tooltip('Section', 'Key')
t = regexp(code, ['stimgen\.util\.tooltip\(\s*' q '(\w+)' q '\s*,\s*' q '(\w+)' q '\s*\)'], 'tokens');
for k = 1:numel(t)
    refs(end+1, :) = [string(t{k}{1}), string(t{k}{2})]; %#ok<AGROW>
end

% Aliases: name = @(key) stimgen.util.tooltip('Section', key)
aliases = strings(0, 2);   % [alias section]
t = regexp(code, ['(\w+)\s*=\s*@\(\s*(\w+)\s*\)\s*stimgen\.util\.tooltip\(\s*' ...
    q '(\w+)' q '\s*,\s*(\w+)\s*\)'], 'tokens');
for k = 1:numel(t)
    if strcmp(t{k}{2}, t{k}{4})
        aliases(end+1, :) = [string(t{k}{1}), string(t{k}{3})]; %#ok<AGROW>
    end
end

% ... and local functions: function t = name(key) whose body is the lookup.
for i = 1:numel(lines)
    h = regexp(char(lines(i)), '^\s*function\s+\w+\s*=\s*(\w+)\s*\(\s*(\w+)\s*\)', 'tokens', 'once');
    if isempty(h)
        continue
    end
    for j = i+1 : min(i+5, numel(lines))
        b = regexp(char(lines(j)), ['stimgen\.util\.tooltip\(\s*' q '(\w+)' q '\s*,\s*' ...
            char(h{2}) '\s*\)'], 'tokens', 'once');
        if ~isempty(b)
            aliases(end+1, :) = [string(h{1}), string(b{1})]; %#ok<AGROW>
            break
        end
    end
end

for a = 1:size(aliases, 1)
    t = regexp(code, ['(?<![\w.])' char(aliases(a, 1)) '\(\s*' q '(\w+)' q '\s*\)'], 'tokens');
    for k = 1:numel(t)
        refs(end+1, :) = [aliases(a, 2), string(t{k}{1})]; %#ok<AGROW>
    end
end
end
