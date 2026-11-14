classdef FakeHostParameter < handle
    % One hardware parameter of FakeHardwareHost: a handle with a Value, as
    % a host's parameter objects are, that counts the writes made to it so a
    % test can see that a Run triggered and loaded its buffers.

    properties
        Name (1,1) string = ""
        Value = []
        NumWrites (1,1) double = 0   % assignments to Value since construction
    end

    methods
        function obj = FakeHostParameter(name)
            if nargin > 0
                obj.Name = name;
            end
        end

        function set.Value(obj, v)
            obj.Value = v;
            obj.NumWrites = obj.NumWrites + 1; %#ok<MCSUP>
        end
    end
end
