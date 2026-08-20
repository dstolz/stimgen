function load_stimulus(obj, ffn)
% load_stimulus(obj)
% load_stimulus(obj, ffn)
% Load a stimulus to spot check from a file.
%
% Two formats are understood, both of which stimgen already writes:
%
%   .spl  a stimgen.StimPlayer bank. A bank holds several stimuli, so one is
%         chosen -- the only item if there is one, otherwise from a list.
%   .mat  anything holding a serialized stimgen.StimType, whether saved as a
%         struct from toStruct or as the object itself. Every variable in the
%         file is examined, so a save() of a whole workspace works.
%
% A bank item is rebuilt through stimgen.StimType.fromStruct, so it arrives
% with its embedded calibration and its variant configuration intact -- which
% is the point: the stimulus is spot checked as it will run, not as a fresh
% object with defaults.
%
% Parameters:
%   ffn - full file path (optional); prompts with a dialog when omitted

arguments
    obj (1,1) stimgen.SpotCheck
    ffn (1,:) char = ''
end

if isempty(ffn)
    startDir = obj.DataPath_;
    if strlength(startDir) == 0 || ~isfolder(startDir)
        startDir = pwd;
    end
    [fn, pn] = uigetfile( ...
        {'*.spl;*.mat', 'Stimulus Files (*.spl, *.mat)'; ...
         '*.spl',       'Stimulus Banks (*.spl)'; ...
         '*.mat',       'MAT Files (*.mat)'; ...
         '*.*',         'All Files'}, ...
        'Load Stimulus to Spot Check', char(startDir));
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
end

if ~isfile(ffn)
    error('stimgen:SpotCheck:fileNotFound', ...
        'Stimulus file not found: %s', ffn);
end

try
    S = load(ffn, '-mat');
catch ME
    error('stimgen:SpotCheck:fileNotReadable', ...
        'Could not read "%s": %s', ffn, ME.message);
end

[stimObj, label] = extract_stimulus_(obj, S, ffn);

if isempty(stimObj)
    error('stimgen:SpotCheck:noStimulusInFile', ...
        ['No stimulus was found in "%s". Expected a .spl bank written by ' ...
         'stimgen.StimPlayer, or a .mat holding a stimgen.StimType object ' ...
         'or a struct from its toStruct method.'], ffn);
end

obj.StimulusFile = string(ffn);
obj.DataPath_    = string(fileparts(ffn));

obj.set_stimulus(stimObj, label);

stimgen.util.vprintf(1, 'SpotCheck: loaded "%s" from "%s"', char(label), ffn);
obj.set_status_("Loaded " + label + " from " + string(ffn));
end % load_stimulus


% =========================================================================

function [stimObj, label] = extract_stimulus_(obj, S, ffn)
% [stimObj, label] = extract_stimulus_(obj, S, ffn)
% Find a stimulus in a loaded file, asking which one where that is ambiguous.

stimObj = [];
label   = "";

% ---- A StimPlayer bank -------------------------------------------------
if isfield(S, 'Items') && isfield(S, 'NItems')
    [stimObj, label] = from_bank_(obj, S, ffn);
    return
end

% ---- A live object saved straight into a .mat --------------------------
names = fieldnames(S);
for k = 1:numel(names)
    v = S.(names{k});
    if isa(v, 'stimgen.StimType') && isscalar(v) && isvalid(v)
        stimObj = v;
        label   = stimgen.SpotCheck.default_label_(v);
        return
    end
end

% ---- A serialized struct -----------------------------------------------
for k = 1:numel(names)
    v = S.(names{k});
    if isstruct(v) && isscalar(v) && isfield(v, 'Class') && isfield(v, 'UserProperties')
        try
            stimObj = stimgen.StimType.fromStruct(v);
            label   = stimgen.SpotCheck.default_label_(stimObj);
            return
        catch ME
            stimgen.util.vprintf(1, 1, ...
                'SpotCheck: "%s" looked like a serialized stimulus but could not be rebuilt: %s', ...
                names{k}, ME.message);
        end
    end
end
end


function [stimObj, label] = from_bank_(obj, bank, ffn)
% [stimObj, label] = from_bank_(obj, bank, ffn)
% One item out of a .spl bank. A bank holds a list, and a spot check measures
% one stimulus, so the choice has to be made here.

stimObj = [];
label   = "";

n = double(bank.NItems);
if n < 1
    return
end

names = strings(1, n);
for k = 1:n
    item = bank.Items{k};
    if isfield(item, 'Name') && strlength(string(item.Name)) > 0
        names(k) = string(item.Name);
    else
        names(k) = "Item " + k;
    end
end

pick = 1;
if n > 1
    [~, base, ext] = fileparts(ffn);
    pick = pick_item_(obj, names, [base ext]);
    if isempty(pick)
        return      % dialog cancelled
    end
end

item = bank.Items{pick};
if ~isfield(item, 'StimObj')
    error('stimgen:SpotCheck:badBankItem', ...
        'Bank item "%s" holds no stimulus.', names(pick));
end

stimObj = stimgen.StimType.fromStruct(item.StimObj);
label   = names(pick);
end


function pick = pick_item_(obj, names, fileName)
% pick = pick_item_(obj, names, fileName)
% Index of the bank item to check. Uses a modal list dialog when there is a
% window to parent it to, and falls back to the first item with a logged note
% when running headless -- a script should not block on a dialog.

if ~obj.is_open()
    pick = 1;
    stimgen.util.vprintf(1, 1, ...
        ['SpotCheck: "%s" holds %d stimuli and there is no window to choose ' ...
         'in; using the first, "%s". Call set_stimulus directly to pick ' ...
         'another.'], fileName, numel(names), char(names(1)));
    return
end

[pick, ok] = listdlg( ...
    'PromptString', sprintf('Which stimulus from %s?', fileName), ...
    'ListString',   cellstr(names), ...
    'SelectionMode', 'single', ...
    'Name',          'Choose Stimulus', ...
    'ListSize',      [320 260]);

if ~ok
    pick = [];
end
end
