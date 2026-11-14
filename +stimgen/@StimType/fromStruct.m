function obj = fromStruct(S, calibration)
% obj = stimgen.StimType.fromStruct(S)
% obj = stimgen.StimType.fromStruct(S, calibration)
% Reconstruct a stimgen.StimType subclass instance from a serialized struct.
%
% This is the one restore path: StimPlayer.load_bank and duplicate_stim both
% come through here, so a property restored for one is restored for all.
% The base-class set is stimgen.StimType.CoreProperties, the same list
% toStruct writes; the subclass's own set is S.UserProperties, assigned in
% order (SoundFile relies on that order). Fields missing from an older
% struct keep the class default; a saved name the class no longer has as a
% property (one removed since the struct was written) is skipped with a
% debug-level log line.
%
% The stimulus is generated ONCE, after everything is back. Regeneration on
% property change is held (hold_updates) while the properties are assigned,
% and a single update_signal() follows. Assigning them live instead
% synthesized the waveform once per restored property -- each time against a
% stimulus that was only partly restored, each time advancing the variant
% selection, and for a long stimulus each time at full cost. The one
% generation makes the first selection of the variant sequence, so a
% restored stimulus with a variant axis starts on the combination its
% selection mode picks first (combination 1 in Serial mode).
%
% Calibration is restored before that generation, and ApplyCalibration last
% of all, so the one generation runs with the saved calibration in place.
% Generating against the default, empty StimCalibration logged a critical
% "No calibration data available for stim" about a stimulus that is in fact
% calibrated -- word for word the line a stimulus with no calibration earns,
% so a log could not tell the two apart.
%
% A stimulus whose generation fails is still returned -- one item must not
% cost a bank the rest -- with the failure logged as critical and Signal
% left empty.
%
% Parameters:
%   S           - struct from toStruct (a .spl bank item's StimObj, etc.)
%   calibration - (optional) stimgen.StimCalibration to attach instead of
%                 rebuilding the one serialized in S. duplicate_stim passes
%                 the source's, so the copy shares one calibration state.
cls = char(S.Class);
if ~contains(cls, '.')
    cls = ['stimgen.' cls];   % a struct naming the class without its package
end
obj = feval(cls);

if isfield(S, 'DisplayName')
    obj.DisplayName = S.DisplayName;
end

applyCal = obj.ApplyCalibration;   % class default, if unsaved
if isfield(S, 'ApplyCalibration')
    applyCal = S.ApplyCalibration;
end

% Held until every property is back; released on any exit, so an error in an
% assignment below cannot leave the object deaf to later edits.
obj.hold_updates(true);
release = onCleanup(@() obj.hold_updates(false));

obj.ApplyCalibration = false;      % restored last; see above

core = stimgen.StimType.CoreProperties;
for k = 1:numel(core)
    pname = char(core(k));
    if isfield(S, pname)
        obj.(pname) = S.(pname);
    end
end

if nargin >= 2 && isa(calibration, 'stimgen.StimCalibration')
    obj.Calibration = calibration;
elseif isfield(S, 'Calibration')
    calData = S.Calibration;
    if isa(calData, 'stimgen.StimCalibration')
        obj.Calibration = calData;
    elseif isstruct(calData)
        obj.Calibration = stimgen.StimCalibration.loadobj(calData);
    end
end

if isfield(S, 'UserProperties')
    for k = 1:numel(S.UserProperties)
        pname = char(S.UserProperties(k));
        if strcmp(pname, 'ApplyCalibration'), continue; end   % restored last
        if ~isprop(obj, pname)
            % A property the class no longer has, e.g. the removed
            % ApplyViemeisterCorrection in an older bank. Skipped, not an
            % error, so old banks still load.
            stimgen.util.vprintf(2, 'fromStruct: %s has no property "%s"; saved value ignored.', ...
                cls, pname);
            continue
        end
        if isfield(S, pname)
            obj.(pname) = S.(pname);
        end
    end
end

obj.ApplyCalibration = applyCal;

clear release   % regeneration on property change is live again

% The one generation. Explicit, because nothing above triggers it: the
% listeners were held, and the ApplyCalibration assignment is not even an
% event when the saved value is false (AbortSet).
try
    obj.update_signal();
catch ME
    stimgen.util.vprintf(0, 1, 'fromStruct: %s could not be generated after restore: %s', ...
        cls, ME.message);
end
end
