function set_adapter(obj, adapter)
% set_adapter(obj, adapter)
% set_adapter(obj, [])
%
% Attach, replace, or detach the hardware adapter used for live measurement.
%
% Adapter is SetAccess = protected, so front ends -- notably
% stimgen.calibration.CalibrationGui -- cannot assign it directly. This is
% the supported entry point. Passing [] detaches the adapter and returns the
% engine to offline mode, where compute_adjusted_voltage still works.
%
% Parameters:
%   adapter - stimgen.calibration.HwAdapter | []

arguments
    obj     (1,1) stimgen.calibration.Engine
    adapter = []
end

if ~isempty(adapter) && ~isa(adapter, 'stimgen.calibration.HwAdapter')
    error('stimgen:calibration:Engine:badAdapter', ...
        'adapter must be a stimgen.calibration.HwAdapter.');
end

obj.Adapter = adapter;
