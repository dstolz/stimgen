function load_patch_(obj, ffn)
% load_patch_(obj)
% load_patch_(obj, ffn)
% Load a saved stimgen.Patch from a .spatch file and apply it to the patch
% being edited.
%
% The live obj.Patch handle is mutated in place rather than replaced by the
% loaded object: Patch.edit_graph (and any script driving the editor
% directly) opened this window on a handle it still holds, and only changes
% made in place are visible to it once the editor closes (see
% close_request_). Graph is assigned first so the dynamic parameter
% properties it creates exist before their values are copied over.

if nargin < 2 || isempty(ffn)
    [fn, pn] = uigetfile('*.spatch', 'Load Patch', obj.default_dir_());
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
end
ffn = char(ffn);

try
    data = load(ffn, '-mat');
    if ~isfield(data, 'StimObj') || ~strcmp(char(data.StimObj.Class), 'stimgen.Patch')
        error('stimgen:PatchEditor:InvalidPatchFile', ...
            '"%s" does not contain a stimgen.Patch.', ffn);
    end

    loaded = stimgen.StimType.fromStruct(data.StimObj);

    p = obj.Patch;
    p.Graph      = loaded.Graph;
    p.OutputNode = loaded.OutputNode;

    p.DisplayName      = loaded.DisplayName;
    p.Fs               = loaded.Fs;
    p.ApplyCalibration = loaded.ApplyCalibration;
    p.ApplyWindow      = loaded.ApplyWindow;
    p.WindowFcn        = loaded.WindowFcn;
    p.VariantSelectionMode    = loaded.VariantSelectionMode;
    p.VariantCombinationMode  = loaded.VariantCombinationMode;
    p.VariantSelectorClass    = loaded.VariantSelectorClass;
    p.VariantSelectorConfig   = loaded.VariantSelectorConfig;
    p.VariantReselectOnUpdate = loaded.VariantReselectOnUpdate;
    p.Calibration      = loaded.Calibration;

    for prop = loaded.UserProperties
        name = char(prop);
        if prop == "Graph" || prop == "OutputNode", continue, end
        if isprop(p, name) && isprop(loaded, name)
            p.(name) = loaded.(name);
        end
    end

    obj.CurrentFile = string(ffn);
    stimgen.PatchEditor.record_recent_file_(ffn);
    obj.refresh_recents_menu_();

    obj.selKind = ""; obj.selIdx = 0;
    stimgen.util.vprintf(1, 'PatchEditor: patch loaded from "%s"', ffn);
    obj.set_status_("Loaded patch: " + string(ffn), "info");
catch ME
    obj.set_status_(ME.message, "error");
end

obj.refresh_all_();
end
