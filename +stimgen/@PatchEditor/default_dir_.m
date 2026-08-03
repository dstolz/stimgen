function d = default_dir_(obj)
% d = default_dir_(obj)
% Starting folder for the Save/Load file dialogs: this editor's current
% file, else the most recently modified patch on record, else a per-user
% fallback matching StimPlayer's DataPath default.

if strlength(obj.CurrentFile) > 0
    d = fileparts(char(obj.CurrentFile));
    return
end

recent = stimgen.PatchEditor.list_recent_files_(1);
if ~isempty(recent)
    d = fileparts(char(recent(1)));
    return
end

d = fullfile('C:\Users', getenv('USERNAME'));
end
