function [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode)
% [spl_db, voltage] = compute_spl_voltage_(obj, measurement, mode)
% Unified SPL and normative voltage calculation.
%
% For "peak" mode, converts peak amplitude to RMS equivalent
% (÷sqrt(2)) before computing dB SPL, giving a consistent reference.
%
% Parameters:
%   measurement - double scalar measured by the microphone
%   mode        - "rms" | "peak" | "specfreq"
%
% Returns:
%   spl_db  - double measured sound level in dB SPL
%   voltage - double output voltage to produce NormativeValue SPL
if mode == "peak"
    m_rms = measurement / sqrt(2);
else
    m_rms = measurement;
end

spl_db  = obj.spl_from_volts(m_rms);
voltage = obj.ExcitationVoltage * 10 ^ ((obj.NormativeValue - spl_db) / 20);
end
