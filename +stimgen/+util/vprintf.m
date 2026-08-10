function vprintf(verbose_level,varargin)
% stimgen.util.vprintf(verbose_level,msg)
% stimgen.util.vprintf(verbose_level,red,msg)
% stimgen.util.vprintf(verbose_level,msg,value1,value2,...)
% stimgen.util.vprintf(verbose_level,red,msg,value1,value2,...)
% stimgen.util.vprintf(verbose_level,[red],exception)
%
% Verbosity-gated console and log printing, and the only logging entry point
% in the package.
%
% Messages are filtered against the global GVerbosity, an integer normally
% between -1 and 4:
%  -1 log message, but do not print to screen
%   0 critical; suppresses nearly all other text
%   1 low, information that may be generally useful to the user
%   2 medium, information that can be helpful for debugging
%   3 high, lots of information about nearly all processes (debugging)
%   4 trace, per-buffer/per-trial detail
%
% Where the message GOES depends on whether a host application has installed a
% stimgen.LogSink:
%
%   installed - the message is forwarded to the host and stimgen writes
%               nothing of its own, so a host with its own logger ends up with
%               ONE log describing the session instead of two
%   none      - stimgen's built-in logger prints to the command window and
%               appends to a daily file under
%               fullfile(tempdir,'stimgen_error_logs')
%
% Either way stimgen names no host type, so the package still runs standalone.
%
% Format policy:
%   With values, msg is a printf format string, exactly as documented.
%   With no values, msg is LITERAL text -- nothing is interpreted -- so a
%   runtime-built message such as ME.message or 'C:\new\data.mat' survives
%   intact instead of being mangled by '\n' and '%' conversions.
% A trailing newline is never needed and is stripped if present.
%
% The msg input may also be an MException, or any struct carrying .message.
% It is forwarded to the host UNEXPANDED, which is what lets a host render the
% identifier, stack and nested causes as a single record attributed to the
% catch site.
%
% Nothing here throws. stimgen logs from inside catch blocks, and an exception
% raised while reporting an exception destroys the report.
%
% ex:
%      global GVerbosity
%      GVerbosity = 2;
%      stimgen.util.vprintf(2,'This is a level %d message: %s',2,'medium verbosity')
%      18:51:35.958: This is a level 2 message: medium verbosity
%
%      stimgen.util.vprintf(1,1,'This is a red level %d message',1)
%      18:51:35.958: This is a red level 1 message
%
% See documentation/stimgen_logging.md for the seam overview.
%
% See also: stimgen.util.isEnabled, stimgen.LogSink, stimgen.util.logSink
%
% Daniel.Stolzberg@gmail.com 2015

% Copyright (C) 2016  Daniel Stolzberg, PhD

% The gate comes first and is the only cost a suppressed message pays: no
% timestamp, no dbstack, no formatting. StimPlayer.update_buffer logs at
% level 4 from the buffer-write path, so that difference is a timing concern
% rather than a micro-optimization.
%
% The sink is fetched here rather than through stimgen.util.isEnabled, which
% would fetch it a second time further down. That one saved lookup is about a
% third of the whole suppressed path.
sink = stimgen.util.logSink();

if isempty(sink)
    if ~stimgen.util.verbosityGate(verbose_level), return; end
else
    try
        if ~sink.isEnabled(verbose_level), return; end
    catch
        % A host gate that throws must not silence stimgen.
        if ~stimgen.util.verbosityGate(verbose_level), return; end
    end
end

if isempty(varargin)
    % Nothing to say. Historically this left msg undefined and errored inside
    % the logger, which is the worst possible place to raise.
    return
end

try
    % Calling convention: an optional red flag sits between the level and the
    % message. It is only a flag when something follows it, and only when it is
    % a numeric or logical scalar -- the old test was ~ischar, which read a
    % string scalar message as the flag and then failed on it.
    if numel(varargin) >= 2 && (isnumeric(varargin{1}) || islogical(varargin{1})) ...
            && isscalar(varargin{1})
        red    = logical(varargin{1});
        msg    = varargin{2};
        values = varargin(3:end);
    else
        red    = false;
        msg    = varargin{1};
        values = varargin(2:end);
    end

    if ~isempty(sink)
        try
            % Forward the RAW message, before any exception expansion: the host
            % gets to make one nested record out of an MException instead of
            % receiving text stimgen already flattened.
            sink.emit(verbose_level,red,msg,values);
            return
        catch sinkErr
            % A broken host sink must never make stimgen go mute, and must not
            % latch off either -- latching is the host's job (its own file sink
            % already does it). Warn once, then let THIS message through to the
            % built-in logger so it is not simply lost.
            localWarnOnce(sinkErr);
        end
    end

    stimgen.util.vprintfFallback(verbose_level,red,msg,values);
catch vprintfErr
    % Last resort: say so on stderr and carry on.
    fprintf(2,'stimgen: dropped a log message (%s)\n',vprintfErr.message);
end
end


function localWarnOnce(err)
% One note per session. A sink that fails once usually fails on every message,
% and a warning storm from inside the logger buries the failure being reported.
persistent warned
if isempty(warned)
    warned = true;
    fprintf(2,['stimgen: the installed log sink (%s) failed; ' ...
        'falling back to the built-in logger.\n'],err.message);
end
end
