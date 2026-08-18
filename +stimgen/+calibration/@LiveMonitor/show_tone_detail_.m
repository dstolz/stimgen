function show_tone_detail_(obj, eng)
% show_tone_detail_(obj, eng)
% Harmonic distortion and signal-to-noise against frequency, under the tone
% panel.
%
% A tone sweep is the only calibration that measures a rig one frequency at a
% time, and so the only one that can say WHERE a speaker starts distorting or
% where the record runs out of signal. Those numbers are already computed and
% stored per point; without a panel of their own they are only readable by
% opening the .esgc, which is not something anyone does while deciding
% whether a sweep is good enough to keep.
%
% All four traces are in dB and share one axis on purpose: what is being read
% is the GAP between them -- an SNR of 60 dB above a THD of -40 dB is a clean
% point, and the frequency where those two approach each other is where the
% table stops being trustworthy. Two axes would put that comparison behind a
% pair of scales.
%
% Nothing here is live. The figures are computed when the sweep is committed,
% so this panel fills in when the run ends rather than point by point.
%
% Parameters:
%   eng - stimgen.calibration.Engine
arguments
    obj
    eng (1,1) stimgen.calibration.Engine
end

ax = obj.detail_axes_("tone", 1);
if isempty(ax)
    return
end

m = stimgen.calibration.LiveMonitor.lut_metrics_(eng, "tone");
x = [];
if ~isempty(m) && isfield(m, 'frequency_response_hz')
    x = m.frequency_response_hz(:).';
end

obj.draw_quality_panel_(ax, "tone", x, m, ...
    'frequency (Hz)', 'Tone distortion & SNR');
end
