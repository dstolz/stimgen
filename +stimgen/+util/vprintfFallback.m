function vprintfFallback(level, red, msg, args)
% stimgen.util.vprintfFallback(level, red, msg, args)
% stimgen.util.vprintfFallback('-close')
%
% stimgen's built-in logger: the destination used when no host stimgen.LogSink
% is installed. Writes a timestamped line to the command window and appends it
% to a daily file under fullfile(tempdir,'stimgen_error_logs').
%
% Split out of stimgen.util.vprintf so the registry can hand the file back on
% install (Windows keeps a log locked while its handle is open) and so the
% standalone path can be exercised on its own.
%
% Nothing here throws. stimgen logs from inside catch blocks, and an exception
% raised while reporting an exception destroys the report.
%
% Parameters:
%   level - numeric verbosity; a negative level is written to the file but
%           never echoed to the command window
%   red   - logical; route the console line to stderr
%   msg   - char, string, MException, or a struct carrying .message
%   args  - cell array of format values; empty means msg is literal text
%
% See also: stimgen.util.vprintf, stimgen.util.logSink

persistent logFid logDate logFailed

if nargin == 1 && (ischar(level) || isstring(level)) && strcmp(level,'-close')
    if ~isempty(logFid) && isnumeric(logFid) && logFid > 2
        try
            fclose(logFid);
        catch
            % Already closed, or the handle went stale; nothing to recover.
        end
    end
    logFid  = [];
    logDate = [];
    return
end

try
    if nargin < 4, args = {}; end

    % A malformed call site can reach here with a non-numeric level: the gate
    % deliberately lets those through so the mistake is loud. Normalize once so
    % the comparisons below stay scalar rather than going elementwise over char
    % codes.
    if ~isnumeric(level) || ~isscalar(level) || ~isfinite(level)
        level = 0;
    end

    % Exceptions become ONE block, not one record per stack frame. The old
    % implementation recursed through vprintf per frame, which made the dbstack
    % lookup below report vprintf itself as the caller -- so every
    % "catch ME; vprintf(0,1,ME); end" site lost the location that mattered.
    if isa(msg,'MException') || (isstruct(msg) && isfield(msg,'message'))
        text = localFormatException(msg);
    else
        text = localFormat(msg, args);
    end

    % clock, not datetime('now'): rendering a datetime to 'HH:mm:ss.SSS' costs
    % roughly 275 us against ~1 us here, and this runs on every message.
    c = clock;
    stamp = sprintf('%02d:%02d:%06.3f', c(4), c(5), c(6));

    [name, line] = localCallerFrame();

    [logFid, logDate, logFailed] = localWrite( ...
        logFid, logDate, logFailed, level, c, stamp, name, line, text);

    % Negative levels are log-only: recorded, but never put in front of the
    % operator. That is what makes level -1 usable for probes and audit trails.
    if level >= 0
        if red, fid = 2; else, fid = 1; end
        % '%s' throughout: text is finished, never a format string.
        fprintf(fid, '%s: %s\n', stamp, text);
    end
catch fallbackErr
    % Last resort. Say so once per call on stderr and carry on; the caller is
    % usually already handling a more important failure.
    fprintf(2, 'stimgen: dropped a log message (%s)\n', fallbackErr.message);
end
end


function [fid, dateVec, failed] = localWrite(fid, dateVec, failed, level, c, stamp, name, line, text)
% Append one record to the daily file, opening or rotating as needed.

if failed
    % The open already failed once. Retrying meant isfolder + mkdir + fopen on
    % every subsequent message, silently, forever.
    return
end

today = c(1:3);

needOpen = isempty(fid) || ~isnumeric(fid) || fid <= 2 ...
    || isempty(dateVec) || ~isequal(dateVec, today);

if needOpen
    if ~isempty(fid) && isnumeric(fid) && fid > 2
        try
            fclose(fid);
        catch
            % Already closed, or the handle went stale; nothing to recover.
        end
    end

    d = fullfile(tempdir, 'stimgen_error_logs');
    if ~isfolder(d)
        [made, ~] = mkdir(d);
        if ~made
            failed = true;
            fprintf(2, 'stimgen: cannot create the log directory %s; file logging disabled.\n', d);
            fid = -1;
            return
        end
    end

    p = fullfile(d, sprintf('error_log_%s.txt', localDateTag(c)));
    fid = fopen(p, 'at');
    if fid <= 2
        failed = true;
        fprintf(2, 'stimgen: cannot open the log file %s; file logging disabled.\n', p);
        return
    end
    dateVec = today;
end

% Continuation lines are indented so a multi-line exception stays visibly one
% record when the file is read back.
body = strrep(text, newline, [newline '    ']);
fprintf(fid, '%s,%s,%d: %s\n', stamp, name, line, body);

% Critical messages are made durable immediately. MATLAB exposes no fflush, so
% the only way is to close and reopen in append mode -- and a buffered tail is
% exactly what gets lost in the crash the log exists to explain.
if level <= 0
    p = fopen(fid);
    try
        fclose(fid);
        fid = fopen(p, 'at');
    catch
        fid = -1;
    end
    if fid <= 2
        failed = true;
        fid = -1;
    end
end
end


function s = localDateTag(c)
% ddMMMyyyy, matching the filenames stimgen has always written.
mons = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
m = round(c(2));
if m < 1 || m > 12, m = 1; end
s = sprintf('%02d%s%04d', round(c(3)), mons{m}, round(c(1)));
end


function [name, line] = localCallerFrame()
% Identify the function that raised the message.
%
% Scans for the first frame outside the logger rather than indexing a fixed
% depth. The old code hardcoded frame 3, which assumed exactly
% "caller -> vprintf -> logmessage"; that broke for exception logging, for
% calls inside cellfun bodies, and at the command window. Splitting the logger
% across two files would have broken it again.
name = 'base';
line = 0;

st = dbstack('-completenames');
for k = 2:numel(st)
    f = st(k).file;
    if ~isempty(f) && (endsWith(f,'vprintf.m') || endsWith(f,'vprintfFallback.m'))
        continue
    end
    name = st(k).name;
    line = st(k).line;
    return
end

if numel(st) >= 2
    name = st(end).name;
    line = st(end).line;
end
end


function txt = localFormat(msg, args)
% Render a message to a single char row.
%
%   no values  : LITERAL text. '100% done' and 'C:\new\tmp\run.mat' survive.
%   with values: a printf format string, as documented.
%
% Keeping the no-values path literal matters because the messages built at
% runtime -- ME.message, a data path, tool output -- are exactly the ones
% carrying stray '%' and Windows backslashes.

m = localToChar(msg);

if isempty(args)
    txt = m;
else
    try
        txt = sprintf(m, args{:});
    catch fmtErr
        % '%s' below, so the offending text is an argument and cannot recurse.
        txt = sprintf('%s   [log format failed: %s]', m, fmtErr.message);
    end
end

% The line ending is added by the writer; many call sites append '\n' against
% convention, and stripping here makes that harmless rather than a blank line.
n = numel(txt);
while n > 0 && (txt(n) == newline || txt(n) == char(13))
    n = n - 1;
end
txt = txt(1:n);
end


function txt = localFormatException(err, depth)
% Render an exception as one multi-line block:
%
%   identifier: message
%       at name (line N) file
%     caused by:
%       ...

if nargin < 2, depth = 0; end

identifier = '';
msgText    = '';
stack      = [];

if localHas(err,'identifier')
    identifier = localToChar(err.identifier);
elseif localHas(err,'messageID')
    % A timer's ErrorFcn event data names the field messageID.
    identifier = localToChar(err.messageID);
end
if localHas(err,'message'), msgText = localToChar(err.message); end
if localHas(err,'stack'),   stack   = err.stack;                end

if isempty(identifier)
    head = msgText;
else
    head = sprintf('%s: %s', identifier, msgText);
end

nStack = numel(stack);
lines = cell(1, 1 + nStack);
lines{1} = head;
for k = 1:nStack
    lines{1+k} = sprintf('    at %s (line %d) %s', ...
        localToChar(stack(k).name), stack(k).line, localToChar(stack(k).file));
end

% Nested causes, indented. Guard the depth: a self-referential cause chain
% would otherwise recurse until the stack blows, inside an error handler.
if depth < 5 && localHas(err,'cause')
    causes = err.cause;
    extra = cell(1, 2*numel(causes));
    for k = 1:numel(causes)
        sub = localFormatException(causes{k}, depth+1);
        extra{2*k-1} = '  caused by:';
        extra{2*k}   = ['    ' strrep(sub, newline, [newline '    '])];
    end
    lines = [lines extra];
end

txt = strjoin(lines, newline);
end


function tf = localHas(s, f)
tf = isprop(s, f) || (isstruct(s) && isfield(s, f));
end


function m = localToChar(msg)
% Coerce anything a caller might hand us into a char row, without throwing.
if ischar(msg)
    m = reshape(msg, 1, []);
    return
end

try
    if isstring(msg)
        msg(ismissing(msg)) = "<missing>";
        if isscalar(msg)
            m = char(msg);
        else
            m = char(strjoin(msg(:).', ' '));
        end
    else
        m = char(strjoin(string(msg(:)).', ' '));
    end
catch
    m = sprintf('<unprintable %s>', class(msg));
end

if isempty(m)
    m = '';
else
    m = reshape(m, 1, []);
end
end
