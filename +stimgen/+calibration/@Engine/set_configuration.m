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
%   AdcGain            - (1,1) double, dB. Input-stage gain the rig was set
%                        to. Recorded only; nothing here reads it, since the
%                        measurement it labels already includes it.
%   DacAttenuation     - (1,1) double, dB. Output-stage attenuation, recorded
%                        on the same terms. Both default to 0 dB.
%   AcCoupleResponse   - (1,1) logical. Zero-phase high-pass each acquired
%                        record before analyzing it, so an input DC offset or
%                        slow drift does not inflate levels or bias burst
%                        alignment.
%   AcCoupleFrequency  - (1,1) double, > 0. Corner of that high-pass, Hz.
%   ToneRampDuration   - (1,1) double, > 0. Per-edge rise/fall time applied to
%                        every tone burst calibrate_tones/test_tones play,
%                        seconds. Doubled into the total onset+offset gate,
%                        clamped to half the burst duration.
%   AmbientTemperature - (1,1) double, > -273.15. Air temperature in the test
%                        space, degrees Celsius. Sets the speed of sound every
%                        distance derived from a time of flight is computed
%                        with -- the air path of a conduction delay, the path
%                        difference of a reflection. No level depends on it.
%   SpectralWindow     - (1,1) string. Analysis window every spectral
%                        estimator applies: "auto" (each keeps its own -- flat
%                        top for level measurements, Hann for Welch averages),
%                        or one of "flattop", "hann", "hamming", "blackman",
%                        "blackmanharris", "rectangular" applied to all of
%                        them.
%   SpectralFftLength  - (1,1) double, >= 0. Transform length those estimators
%                        run over. 0 leaves each with the next power of two at
%                        or above its record; a nonzero value raises that and
%                        never lowers it, so it can only zero-pad.
%   Notes              - (1,1) string. Free text about this calibration, in
%                        the operator's own words -- the rig, the placement,
%                        anything the tables cannot state for themselves.
%                        Never parsed; saved into the .esgc and printed by
%                        describe().
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
    options.AdcGain            (1,1) double {mustBeReal,mustBeFinite} = obj.AdcGain
    options.DacAttenuation     (1,1) double {mustBeReal,mustBeFinite} = obj.DacAttenuation
    options.AcCoupleResponse   (1,1) logical = obj.AcCoupleResponse
    options.AcCoupleFrequency  (1,1) double {mustBePositive,mustBeFinite} = obj.AcCoupleFrequency
    options.ToneRampDuration   (1,1) double {mustBePositive,mustBeFinite} = obj.ToneRampDuration
    options.AmbientTemperature (1,1) double {mustBeFinite, ...
        mustBeGreaterThan(options.AmbientTemperature, -273.15)} = obj.AmbientTemperature
    options.SpectralWindow     (1,1) string {mustBeMember(options.SpectralWindow, ...
        ["auto", "flattop", "hann", "hamming", "blackman", ...
         "blackmanharris", "rectangular"])} = obj.SpectralWindow
    options.SpectralFftLength  (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = obj.SpectralFftLength
    options.Notes              (1,1) string {mustBeNonmissing} = obj.Notes
    options.ShowLivePlots      (1,1) logical = obj.ShowLivePlots
    options.ToneLutSource      (1,1) string {mustBeMember(options.ToneLutSource, ["tone", "swept_sine"])} = obj.ToneLutSource
end

obj.MicSensitivity    = options.MicSensitivity;
obj.ReferenceLevel    = options.ReferenceLevel;
obj.ReferenceFrequency = options.ReferenceFrequency;
obj.NormativeValue    = options.NormativeValue;
obj.ExcitationVoltage = options.ExcitationVoltage;
obj.MaxOutputVoltage  = options.MaxOutputVoltage;
obj.AdcGain           = options.AdcGain;
obj.DacAttenuation    = options.DacAttenuation;
obj.AcCoupleResponse  = options.AcCoupleResponse;
obj.AcCoupleFrequency = options.AcCoupleFrequency;
obj.ToneRampDuration  = options.ToneRampDuration;
obj.AmbientTemperature = options.AmbientTemperature;
obj.SpectralWindow    = options.SpectralWindow;
obj.SpectralFftLength = options.SpectralFftLength;
obj.Notes             = options.Notes;
obj.ShowLivePlots     = options.ShowLivePlots;
obj.ToneLutSource     = options.ToneLutSource;
end
