classdef FcnLogSink < stimgen.LogSink
    % stimgen.FcnLogSink
    %
    % A stimgen.LogSink that forwards to a plain function handle.
    %
    % The contract is a class so it can grow new methods with safe defaults
    % (see stimgen.LogSink). That is the right shape for a host application,
    % but it is heavy for a script, a test, or a quick "show me what stimgen is
    % saying" session. This wrapper gives those the one-liner without weakening
    % the contract.
    %
    % Properties:
    %   Fcn       - function handle called as Fcn(level, red, msg, args)
    %   GateFcn   - optional handle called as GateFcn(level) -> logical;
    %               empty (default) leaves the inherited GVerbosity gate
    %
    % Example:
    %   captured = {};
    %   stimgen.util.logSink(stimgen.FcnLogSink(@(l,r,m,a) ...
    %       assignin('base','lastLogMessage',m)));
    %
    % See also: stimgen.LogSink, stimgen.util.logSink

    properties
        Fcn     function_handle = @(level,red,msg,args) []
        GateFcn = []
    end

    methods
        function obj = FcnLogSink(fcn, gateFcn)
            % obj = stimgen.FcnLogSink(fcn [,gateFcn])
            if nargin >= 1 && ~isempty(fcn), obj.Fcn = fcn; end
            if nargin >= 2, obj.GateFcn = gateFcn; end
        end

        function emit(obj, level, red, msg, args)
            obj.Fcn(level, red, msg, args);
        end

        function tf = isEnabled(obj, level)
            if isempty(obj.GateFcn)
                tf = isEnabled@stimgen.LogSink(obj, level);
            else
                tf = obj.GateFcn(level);
            end
        end
    end
end
