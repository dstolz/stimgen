function on_weighting_(obj, src)
% Toggle one weighting curve on the transfer panel.
src.Checked = ~strcmp(src.Checked, 'on');
obj.apply_weightings_();
end
