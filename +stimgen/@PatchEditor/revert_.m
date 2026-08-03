function revert_(obj)
% revert_(obj)
% Restore the graph and parameter values captured when the editor opened.

try
    obj.restore_(obj.snapshot);
    obj.selKind = ""; obj.selIdx = 0;
    obj.set_status_("Reverted to the graph as it was when this window opened.", "info");
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
