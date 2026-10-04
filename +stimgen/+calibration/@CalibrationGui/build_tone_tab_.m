function build_tone_tab_(obj)
% Levels against frequency, and under them the distortion and SNR
% measured at each of those frequencies. A tone sweep is the only
% calibration here that measures the rig one frequency at a time,
% and so the only one that can say where it stops behaving.
[obj.ToneTab, tg] = obj.add_stacked_tab_('Tones', 'TabTones', ...
    {'1.5x', '1x'});
obj.AxTone       = obj.tab_axes_(tg, 1, 1);
obj.AxToneDetail = obj.tab_axes_(tg, 2, 1);
end
