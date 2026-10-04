function advance_variant_(~, stimObj)
% advance_variant_(stimObj) - Select the next combination of a presented stimulus.
% update_signal() outside a variant cycle selects through the
% stimulus's own VariantSelectionMode (Serial, ShuffleUniform,
% ShuffleLeastUsed or CustomSelector) and regenerates Signal for
% it, so the next presentation of this stimulus plays that
% combination. step_variant(1) used to be called here, which
% pins index+1 and so bypassed every mode but Serial.
if isempty(stimObj)
    return
end
stimObj.update_signal();
end
