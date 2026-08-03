function set_gui_handles(obj, handleStruct)
% set_gui_handles(obj, handleStruct)
% Register the widget handles of an externally built parameter panel so that
% refresh_gui_widget (and any other handle-driven update) can reach them.
%
% create_gui does this for its own panel. A host GUI that builds its own
% widgets from propMeta -- stimgen.StimPlayer does -- calls this instead.
% Each field name must be a property name and each value a widget handle;
% store the property's label handle in the widget's UserData.labelHandle so
% captions can be refreshed too.
%
% Only one panel at a time can be registered: the most recent caller wins.
% Stale handles are harmless, since every consumer checks isvalid first.
%
% Parameters:
%   handleStruct - struct of widget handles keyed by property name.

arguments
    obj (1,1) stimgen.StimType
    handleStruct (1,1) struct
end

obj.GUIHandles = handleStruct;
