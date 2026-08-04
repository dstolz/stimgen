function attach(obj, eng)
% attach(obj, eng)
% Follow eng's LiveUpdate event, replacing any engine already followed.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

obj.detach();
obj.Engine = eng;
obj.Listener_ = addlistener(eng, 'LiveUpdate', @(~, d) obj.update(d));
eng.register_monitor_(obj);
end
