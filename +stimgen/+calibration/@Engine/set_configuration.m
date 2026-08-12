function set_configuration(obj, options)
% set_configuration(obj)
% set_configuration(obj, Name=Value)
%
% Update engine calibration parameters in one call.
%
% Parameters (Name=Value):
%   MicSensitivity     - (1,1) double, > 0
%   ReferenceLevel     - (1,1) double, > 0
%   ReferenceFrequency - (1,1) double, > 0
%   NormativeValue     - (1,1) double, > 0
%   ExcitationVoltage  - (1,1) double, > 0
%   MaxOutputVoltage   - (1,1) double, > 0 (rig output ceiling, V)
%   DemeanResponse     - (1,1) logical. Subtract the mean from each acquired
%                        record before analyzing it, so an input DC offset does
%                        not inflate levels or bias burst alignment.
%   ShowLivePlots      - (1,1) logical
%   ToneLutSource      - (1,1) string, "tone" or "swept_sine". Which LUT serves
%                        tone lookups; "swept_sine" overrides any direct tone
%                        calibration whenever swept sine data exists.
arguments
    obj
    options.MicSensitivity     (1,1) double {mustBePositive,mustBeFinite} = obj.MicSensitivity
    options.ReferenceLevel     (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceLevel
    options.ReferenceFrequency (1,1) double {mustBePositive,mustBeFinite} = obj.ReferenceFrequency
    options.NormativeValue     (1,1) double {mustBePositive,mustBeFinite} = obj.NormativeValue
    options.ExcitationVoltage  (1,1) double {mustBePositive} = obj.ExcitationVoltage
    options.MaxOutputVoltage   (1,1) double {mustBePositive,mustBeFinite} = obj.MaxOutputVoltage
    options.DemeanResponse     (1,1) logical = obj.DemeanResponse
    options.ShowLivePlots      (1,1) logical = obj.ShowLivePlots
    options.ToneLutSource      (1,1) string {mustBeMember(options.ToneLutSource, ["tone", "swept_sine"])} = obj.ToneLutSource
end

obj.MicSensitivity    = options.MicSensitivity;
obj.ReferenceLevel    = options.ReferenceLevel;
obj.ReferenceFrequency = options.ReferenceFrequency;
obj.NormativeValue    = options.NormativeValue;
obj.ExcitationVoltage = options.ExcitationVoltage;
obj.MaxOutputVoltage  = options.MaxOutputVoltage;
obj.DemeanResponse    = options.DemeanResponse;
obj.ShowLivePlots     = options.ShowLivePlots;
obj.ToneLutSource     = options.ToneLutSource;
end
