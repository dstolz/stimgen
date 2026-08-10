classdef (Abstract) LogSink < handle
    % stimgen.LogSink
    %
    % Abstract contract that lets a host application take delivery of every
    % message stimgen logs, without stimgen naming any host type.
    %
    % stimgen ships a self-contained logger so it can run standalone, but a
    % host that already has one ends up with two log files describing one
    % session. A host supplies a concrete subclass, installs it with
    % stimgen.util.logSink, and from then on stimgen forwards instead of
    % writing its own file. Installing nothing leaves the built-in logger in
    % charge, which is the standalone case.
    %
    % This mirrors the seam already used by stimgen.HardwareHost and
    % stimgen.calibration.HwAdapter: stimgen owns the abstract class, the host
    % owns the implementation.
    %
    % Methods:
    %   emit      - (Abstract) receive one log message
    %   isEnabled - verbosity gate; override to replace GVerbosity entirely
    %
    % Example:
    %   % Host application supplies the concrete implementation:
    %   stimgen.util.logSink(myapp.LogBridge());
    %
    %   % Or wrap a plain function:
    %   stimgen.util.logSink(stimgen.FcnLogSink(@(lvl,red,msg,args) disp(msg)));
    %
    %   % Back to the built-in logger:
    %   stimgen.util.logSink([]);
    %
    % See also: stimgen.FcnLogSink, stimgen.util.logSink,
    %           stimgen.util.vprintf, stimgen.util.isEnabled

    methods (Abstract)
        % emit(obj, level, red, msg, args)
        % Receive one log message. Called only after the gate has passed.
        %
        % Parameters:
        %   level - numeric scalar verbosity, as the call site passed it:
        %           -1 log only (record it, do not print), 0 critical,
        %            1 info, 2 debug, 3 verbose, 4 trace. Not clamped and not
        %           translated -- a host that wants its own scale maps it here.
        %   red   - logical scalar. A FLAG meaning "this is bad news", never a
        %           stream number. stimgen normalizes any nonzero value to true.
        %   msg   - RAW message, never pre-formatted and never expanded: char
        %           row, string scalar, an MException, or a struct carrying
        %           .message. Forwarding the exception object rather than its
        %           text is what lets a host render the identifier, stack and
        %           nested causes its own way.
        %   args  - 1xN cell of format values, {} when there are none.
        %
        % The implementation MUST NOT throw. stimgen logs from inside catch
        % blocks, and an exception raised while reporting an exception destroys
        % the report. A sink that throws anyway is caught: the message falls
        % back to the built-in logger and a note goes to stderr once.
        %
        % The implementation MUST treat an empty args as literal text. With
        % values msg is a printf format string; with none it is the message
        % itself, so a runtime-built string such as ME.message or
        % 'C:\new\data.mat' survives instead of being mangled by '%' and '\n'.
        %
        % The implementation MUST treat level < 0 as log-only, and SHOULD
        % attribute the record to the stimgen call site rather than to its own
        % adapter. It SHOULD also return promptly: StimPlayer.update_buffer
        % logs at level 4 from the buffer-write path.
        emit(obj, level, red, msg, args)
    end

    methods
        function tf = isEnabled(~, level)
            % tf = isEnabled(obj, level)
            % True when a message at this level should be delivered.
            %
            % Optional: override this when the host decides verbosity somewhere
            % other than the GVerbosity global -- a preference, a per-rig
            % setting, a property. The default defers to stimgen's own gate,
            % which keeps hosts written before this method working unchanged.
            %
            % Overriding it is also how a host keeps ONE reader of the
            % verbosity setting across both code bases instead of two that can
            % disagree.
            %
            % Parameters:
            %   level - numeric verbosity level
            %
            % Returns:
            %   tf - logical scalar
            tf = stimgen.util.verbosityGate(level);
        end
    end
end
