function set_control_visibility(obj, options)
% set_control_visibility(obj, Name, Value, ...) - Show or hide session controls.
%
% Lets an interfacing application take over session-level control of the
% player and remove the corresponding widgets from the GUI, so the operator
% cannot change them independently.  Hidden controls are collapsed out of
% their grid, not merely greyed out; the underlying properties (ISI, Reps,
% SelectionType) and playback_control remain fully usable programmatically.
%
% Name-value pairs (each accepts true/false or "on"/"off"):
%   All      - Set every control below at once (applied before the others)
%   Reps     - Per-stimulus repetition count field
%   ISI      - Inter-stimulus interval field
%   PlayMode - Playback order dropdown (Shuffle / Serial)
%   Run      - Run/Stop button
%   Pause    - Pause/Resume button
%
% The resulting state is readable from the ControlVisibility property.
%
% Example:
%   sp = stimgen.StimPlayer;
%   sp.set_control_visibility(ISI=false, Reps=false, PlayMode=false)
%   sp.set_control_visibility(All=false)      % host drives playback entirely
%   sp.playback_control("Run")                % ... via the programmatic API
%
% See also: stimgen.StimPlayer/ControlVisibility, stimgen.StimPlayer/playback_control

arguments
    obj (1,1) stimgen.StimPlayer
    options.All      (1,1) matlab.lang.OnOffSwitchState
    options.Reps     (1,1) matlab.lang.OnOffSwitchState
    options.ISI      (1,1) matlab.lang.OnOffSwitchState
    options.PlayMode (1,1) matlab.lang.OnOffSwitchState
    options.Run      (1,1) matlab.lang.OnOffSwitchState
    options.Pause    (1,1) matlab.lang.OnOffSwitchState
end

vis = obj.ControlVisibility;
names = fieldnames(vis);

% "All" is a bulk default that individual pairs may override.
if isfield(options, 'All')
    state = logical(options.All);
    for i = 1:numel(names)
        vis.(names{i}) = state;
    end
    options = rmfield(options, 'All');
end

specified = fieldnames(options);
for i = 1:numel(specified)
    vis.(specified{i}) = logical(options.(specified{i}));
end

obj.ControlVisibility = vis;

end
