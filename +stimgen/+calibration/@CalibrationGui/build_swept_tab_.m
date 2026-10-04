function build_swept_tab_(obj)
% Three plots, because a swept sine measures more than a table:
% the table on top, then the deconvolved response -- flatness and
% group delay together, since a rig can be flat and still smear a
% transient -- beside the impulse response that same
% deconvolution produced. The bottom two share a row because they
% are two readings of one measurement, and side by side is how
% they get compared.
[obj.SweptTab, tg] = obj.add_stacked_tab_('Swept Sine', 'TabSweptSine', ...
    {'1.2x', '1x'}, {'1x', '1x'});
obj.AxSwept        = obj.tab_axes_(tg, 1, [1 2]);
obj.AxSweptDetail  = obj.tab_axes_(tg, 2, 1);
obj.AxSweptImpulse = obj.tab_axes_(tg, 2, 2);
end
