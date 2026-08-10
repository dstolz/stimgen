function s = logSink(newSink)
% s = stimgen.util.logSink()          current sink, [] when none is installed
%     stimgen.util.logSink(sinkObj)   install a host sink
%     stimgen.util.logSink([])        uninstall, back to the built-in logger
%
% The registry for the host logging seam. While a sink is installed, every
% stimgen.util.vprintf call is forwarded to it and stimgen writes nothing of
% its own -- no console line, no file under tempdir. With none installed,
% stimgen logs the way it always has, which is the standalone case.
%
% The sink lives in a persistent, the same mechanism the rest of stimgen and
% its hosts use for session-wide singletons. "clear functions" therefore
% uninstalls it; a host that cares re-installs from its startup routine, and
% doing so is cheap and idempotent.
%
% A handle whose host has since been deleted is treated as absent and dropped,
% so a closed application cannot take stimgen's logging down with it.
%
% Unlike the rest of the logging path this DOES throw, because it is
% configuration rather than logging: a rejected sink must be visible to the
% programmer installing it, not swallowed the way a bad log message is.
%
% Parameters:
%   newSink - a stimgen.LogSink, or [] to uninstall
%
% Returns:
%   s - the sink now in effect, or [] when none
%
% Example:
%   stimgen.util.logSink(stimgen.FcnLogSink(@(l,r,m,a) disp(m)));
%   stimgen.util.vprintf(1,'hello');
%   stimgen.util.logSink([]);
%
% See also: stimgen.LogSink, stimgen.FcnLogSink, stimgen.util.vprintf

persistent theSink

if nargin >= 1
    if isempty(newSink)
        theSink = [];
    else
        if ~isa(newSink,'stimgen.LogSink') || ~isscalar(newSink)
            error('stimgen:logSink:InvalidSink', ...
                ['A log sink must be a scalar stimgen.LogSink; got %s. ' ...
                 'Wrap a function handle in stimgen.FcnLogSink, or pass [] ' ...
                 'to uninstall.'], class(newSink));
        end
        if ~isvalid(newSink)
            error('stimgen:logSink:DeletedSink', ...
                'The log sink has already been deleted.');
        end

        theSink = newSink;

        % Hand the daily log file back before the host takes over. Windows
        % keeps the file locked while the handle is open, which would stop the
        % operator archiving or deleting a log stimgen is no longer writing to.
        try
            stimgen.util.vprintfFallback('-close');
        catch
            % Closing is a courtesy; failing to must not block the install.
        end
    end
end

% Drop a sink whose host object has been deleted. Doing it on read rather than
% on delete means stimgen needs no listener on a type it does not own.
if ~isempty(theSink) && ~isvalid(theSink)
    theSink = [];
end

if nargout > 0
    s = theSink;
end
end
