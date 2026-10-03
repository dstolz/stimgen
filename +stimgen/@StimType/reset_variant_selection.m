function reset_variant_selection(obj)
% reset_variant_selection(obj)
% Forget the selection history, so the next selection starts a fresh sequence.
%
% A presenter that runs a sequence of trials (StimPlayer's Run) calls this
% before the first one, so the sequence is not shaped by whatever selected
% combinations before it -- previews, combination stepping, an earlier run:
%   Serial           - the cursor returns to combination 1
%   ShuffleLeastUsed - every use count returns to zero
%   CustomSelector   - the selector is discarded, and rebuilt and
%                      initialize()d on the next selection
% ShuffleUniform keeps no history and is unaffected.
%
% Neither the active combination nor Signal is touched: the waveform on hand
% stays the one get_variant_info reports. The next update_signal() outside a
% variant cycle makes the first selection of the new sequence.
%
% See also: update_signal, set_variant_index, get_variant_info

obj.refresh_variant_cache_if_needed_();
obj.variantUseCount_    = zeros(1, numel(obj.variantCombinationTable_));
obj.variantCurrentIdx_  = 1;
obj.variantSelectorObj_ = [];
