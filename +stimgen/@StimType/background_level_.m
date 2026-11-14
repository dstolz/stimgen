function L = background_level_(obj)
% L = background_level_(obj)
% Level of the background for the active combination, in dB SPL when
% calibrated: BackgroundLevel.
%
% Seam for stimgen.BackgroundModulation, whose stimulus IS a modulation of
% the background and therefore has one level, not two: there SoundLevel is
% the carrier level and this returns it.
L = double(obj.active_value_("BackgroundLevel"));
end
