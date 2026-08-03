function auto_layout_(obj)
% auto_layout_(obj)
% Rearrange the nodes left to right by graph depth.

try
    obj.Patch.Graph = stimgen.Patch.auto_layout_(obj.Patch.Graph);
    obj.set_status_("Nodes arranged by signal flow.", "info");
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
