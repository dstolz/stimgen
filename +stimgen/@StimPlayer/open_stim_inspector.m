function open_stim_inspector(obj)
% open_stim_inspector(obj)
% Open the stimulus inspector window, or raise it if it is already open.
%
% The inspector shows detailed plots and measurements for whichever bank
% item is currently selected. It is attached with a source provider rather
% than a fixed object, so it follows the bank selection, parameter edits and
% variant combination steps for as long as it stays open.
%
% See also: stimgen.StimInspector

if ~isempty(obj.Inspector) && isvalid(obj.Inspector) && obj.Inspector.is_open()
    obj.Inspector.show();
    obj.Inspector.refresh();
    return
end

try
    insp = stimgen.StimInspector();
    insp.set_source_provider(@() obj.inspector_source_());
    obj.Inspector = insp;
    obj.set_status_("Stimulus inspector opened.");
catch ME
    obj.report_gui_error_(ME, "Stimulus Inspector Error", ...
        "StimPlayer could not open the stimulus inspector.");
end
end
