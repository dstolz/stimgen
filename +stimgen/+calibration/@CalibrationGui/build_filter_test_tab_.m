function build_filter_test_tab_(obj)
% The equalizer's verification, and the only tab that is not a
% lookup table. Two plots because the test measures the same
% quantity twice and the answer is the difference: the two
% responses in dB SPL on top -- where an equalizer that bought
% flatness by throwing output away is visible -- and under them
% each one's deviation from flat, which is what the pass
% criterion is applied to.
%
% It had no tab of its own until it had two plots to put on one:
% drawn on the Tones tab it either painted over the tone table or
% was wiped by the next redraw of it, and the unfiltered curve was
% overwritten by the filtered one halfway through the run.
[obj.FilterTestTab, tg] = obj.add_stacked_tab_('Filter Test', ...
    'TabFilterTest', {'1.2x', '1x'});
obj.AxFilterTest   = obj.tab_axes_(tg, 1, 1);
obj.AxFilterDetail = obj.tab_axes_(tg, 2, 1);
end
