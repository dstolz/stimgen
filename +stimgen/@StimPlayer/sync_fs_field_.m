function sync_fs_field_(obj)
% sync_fs_field_() - Show the current rate in the sample rate field.
h = obj.handles;
if ~isfield(h, 'FsField') || isempty(h.FsField) || ~isvalid(h.FsField)
    return
end
h.FsField.Value = obj.Fs;
end
