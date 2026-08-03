function save_patch_(obj, forcePrompt)
% save_patch_(obj)
% save_patch_(obj, forcePrompt)
% Save the patch being edited to a .spatch file (MATLAB mat format).
%
% Reuses the file from the last Save/Load without prompting, unless
% forcePrompt is true ("Save As...") or there is no such file yet.

if nargin < 2, forcePrompt = false; end

if forcePrompt || strlength(obj.CurrentFile) == 0
    if strlength(obj.CurrentFile) > 0
        startFile = char(obj.CurrentFile);
    else
        startFile = fullfile(obj.default_dir_(), 'Patch.spatch');
    end
    [fn, pn] = uiputfile('*.spatch', 'Save Patch', startFile);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
else
    ffn = char(obj.CurrentFile);
end

pf = struct();
pf.StimObj = obj.Patch.toStruct();
pf.SavedAt = datetime('now');

try
    save(ffn, '-struct', 'pf', '-v7');
    obj.CurrentFile = string(ffn);
    stimgen.PatchEditor.record_recent_file_(ffn);
    obj.refresh_recents_menu_();
    stimgen.util.vprintf(1, 'PatchEditor: patch saved to "%s"', ffn);
    obj.set_status_("Saved patch: " + string(ffn), "info");
catch ME
    obj.set_status_(ME.message, "error");
end
end
