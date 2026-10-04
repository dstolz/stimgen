function on_weighting_none_(obj)
% Clear every weighting curve in one step.
set(obj.WeightingMenus, Checked='off');
obj.apply_weightings_();
end
