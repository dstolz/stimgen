classdef FakeHardwareHost < stimgen.HardwareHost
    % A stimgen.HardwareHost with no hardware behind it, for tests of a
    % StimPlayer Run that has hardware output: it has a "protocol" loaded
    % and exposes the six parameters a Run resolves (BufferData_0/1,
    % BufferSize_0/1, x_Trigger_0/1) as FakeHostParameter handles, so the
    % player's buffer writes and triggers land somewhere a test can read.
    %
    % It plays nothing and reports no sample rate (the inherited sampleRate
    % returns NaN, so the bank keeps its own rate).

    properties
        Parameters (1,1) struct = struct()   % name -> FakeHostParameter
        Connected  (1,1) logical = false
        Mode       (1,1) string = "Idle"
    end

    methods
        function obj = FakeHardwareHost()
            names = ["BufferData_0", "BufferData_1", "BufferSize_0", ...
                     "BufferSize_1", "x_Trigger_0", "x_Trigger_1"];
            for k = 1:numel(names)
                obj.Parameters.(names(k)) = FakeHostParameter(names(k));
            end
        end

        function loadProtocol(~, ~)
        end

        function tf = hasProtocol(~)
            tf = true;
        end

        function name = protocolName(~)
            name = "fake protocol";
        end

        function connect(obj)
            obj.Connected = true;
        end

        function release(obj)
            obj.Connected = false;
        end

        function setMode(obj, modeName)
            obj.Mode = string(modeName);
        end

        function p = findParameter(obj, name)
            p = [];
            name = char(name);
            if isfield(obj.Parameters, name)
                p = obj.Parameters.(name);
            end
        end

        function state = connectionState(obj)
            if obj.Connected
                state = "Ready";
            else
                state = "None";
            end
        end

        function adapter = calibrationAdapter(~)
            adapter = [];
        end
    end
end
