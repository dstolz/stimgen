function [eng, host] = parse_construction_args_(args)
% [eng, host] = parse_construction_args_(args)
% Resolve the constructor inputs by type so an Engine and a HardwareHost can
% be supplied in any order, alone, or as Engine=/Host= pairs. A missing engine
% becomes a fresh offline Engine; a missing host leaves the runtime menu
% actions disabled.

eng  = stimgen.calibration.Engine.empty;
host = [];

k = 1;
while k <= numel(args)
    a = args{k};
    if isa(a, 'stimgen.calibration.Engine')
        eng = a;
        k = k + 1;
    elseif isa(a, 'stimgen.HardwareHost')
        host = a;
        k = k + 1;
    elseif isempty(a) && ~ischar(a) && ~isstring(a)
        % Tolerate [] placeholders forwarded by callers with an optional host.
        k = k + 1;
    elseif (ischar(a) || (isstring(a) && isscalar(a))) && k < numel(args)
        value = args{k+1};
        switch lower(string(a))
            case "engine"
                mustBeA(value, 'stimgen.calibration.Engine');
                eng = value;
            case "host"
                if ~isempty(value)
                    mustBeA(value, 'stimgen.HardwareHost');
                end
                host = value;
            otherwise
                error('stimgen:calibration:CalibrationGui:invalidArgument', ...
                    'Unrecognized option "%s". Valid options are Engine and Host.', a);
        end
        k = k + 2;
    else
        error('stimgen:calibration:CalibrationGui:invalidArgument', ...
            ['Unrecognized argument of class "%s". Expected a ' ...
            'stimgen.calibration.Engine, a stimgen.HardwareHost, or ' ...
            'Engine=/Host= pairs.'], class(a));
    end
end

if isempty(eng)
    eng = stimgen.calibration.Engine();
end
eng = eng(1);
end
