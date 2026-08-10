function tf = verbosityGate(level)
% tf = stimgen.util.verbosityGate(level)
% stimgen's built-in verbosity gate, and the only place GVerbosity is read.
%
% Kept deliberately cheap: on the suppressed path -- the common case at normal
% verbosity -- nothing is formatted, no timestamp is taken and no file is
% touched. StimPlayer.update_buffer logs at level 4 from the buffer-write path,
% so this runs at buffer rate and must stay a global read and a comparison.
%
% Guards the global against values that silently broke the old comparison
% "level > GVerbosity":
%   NaN       - always false, so EVERY message printed
%   Inf       - never false, same outcome
%   []        - reset to the documented default of 1
%   [0 3]     - an array made "if" require all elements, suppressing nothing
%
% A non-numeric level returns true rather than false, so a malformed call site
% is loud instead of dropping its message forever.
%
% A host that decides verbosity somewhere other than this global overrides
% stimgen.LogSink.isEnabled instead of changing this function.
%
% Parameters:
%   level - numeric verbosity level (-1 log only, 0 critical, 1 info,
%           2 debug, 3 verbose, 4 trace)
%
% Returns:
%   tf - logical scalar
%
% See also: stimgen.util.isEnabled, stimgen.util.vprintf, stimgen.LogSink

% GVerbosity is the established shared control: stimgen has always read it, and
% a host that sets it (EPsych's RunExpt does) still steers stimgen through it.
% Taking it as an argument would split the setting in two.
global GVerbosity

v = GVerbosity;
if isempty(v) || ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
    v = 1;
    GVerbosity = v;
end

if ~isnumeric(level) || ~isscalar(level)
    tf = true;
    return
end

tf = level <= v;
end
