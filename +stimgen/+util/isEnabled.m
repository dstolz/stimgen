function tf = isEnabled(level)
% tf = stimgen.util.isEnabled(level)
% True when a stimgen.util.vprintf call at this level would produce output.
%
% Use it to guard log arguments that are expensive to BUILD. vprintf already
% returns before doing any work when a level is suppressed, but it cannot stop
% the caller computing what it was about to pass:
%
%   if stimgen.util.isEnabled(4)
%       stimgen.util.vprintf(4,'buffer: %s',mat2str(obj.read_buffer()));
%   end
%
% For an ordinary message with cheap arguments, call vprintf directly -- the
% guard costs more than it saves.
%
% The gate is delegable: when a host has installed a stimgen.LogSink, its
% isEnabled decides, so a host that keeps verbosity somewhere other than the
% GVerbosity global still controls stimgen. Otherwise stimgen's own gate
% answers.
%
% Parameters:
%   level - numeric verbosity level
%
% Returns:
%   tf - logical scalar
%
% See also: stimgen.util.vprintf, stimgen.util.verbosityGate, stimgen.LogSink

s = stimgen.util.logSink();

if ~isempty(s)
    try
        tf = logical(s.isEnabled(level));
        if isscalar(tf), return; end
    catch
        % A host gate that throws or returns nonsense must not silence stimgen;
        % fall through to the built-in gate rather than guessing.
    end
end

tf = stimgen.util.verbosityGate(level);
end
