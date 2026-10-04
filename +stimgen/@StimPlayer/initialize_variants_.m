function initialize_variants_(obj)
% initialize_variants_() - Start each bank item's variant sequence for a run.
% Every stimulus forgets its selection history
% (reset_variant_selection: Serial cursor back to combination 1,
% ShuffleLeastUsed counts zeroed, a custom selector rebuilt) and
% then makes the first selection of the run through its own
% VariantSelectionMode, by regenerating outside a variant cycle.
% Previews and combination stepping before the run therefore do
% not shape its order, and Serial still starts at combination 1.
for i = 1:numel(obj.StimPlayObjs)
    sp = obj.StimPlayObjs(i);
    for k = 1:numel(sp.StimObj)
        stimObj = sp.StimObj(k);
        stimObj.reset_variant_selection();
        stimObj.update_signal();
    end
end
end
