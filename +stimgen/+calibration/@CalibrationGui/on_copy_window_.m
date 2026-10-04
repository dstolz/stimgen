function on_copy_window_(obj)
% Put the entire window on the system clipboard as an image.
% MATLAB's clipboard() is text-only and copygraphics skips UI
% components, so the window goes through exportapp to a
% temporary PNG and onto the clipboard through .NET -- which is
% why the full-window form is Windows-only. Elsewhere the plot
% area alone is copied via copygraphics, and the status line
% says which of the two happened.
tmp = [tempname, '.png'];
cleaner = onCleanup(@() delete_quietly_(tmp));
try
    if ispc
        exportapp(obj.Figure, tmp);
        NET.addAssembly('System.Windows.Forms');
        NET.addAssembly('System.Drawing');
        bmp = System.Drawing.Bitmap(tmp);
        err = [];
        try
            % SetImage copies the pixels into the clipboard, so
            % the bitmap -- which holds the PNG open -- can be
            % released as soon as it returns, and must be before
            % the temp file can be deleted.
            System.Windows.Forms.Clipboard.SetImage(bmp);
        catch err
        end
        bmp.Dispose();
        if ~isempty(err)
            rethrow(err);
        end
        obj.set_status_('Window copied to the clipboard.', false);
    else
        copygraphics(obj.Figure, ContentType='image');
        obj.set_status_(['Plots copied to the clipboard. ' ...
            '(The full window, controls included, is a Windows-only copy.)'], false);
    end
catch ME
    stimgen.util.vprintf(0, 1, ME);
    obj.set_status_(sprintf('Copy to clipboard failed: %s', ME.message), true);
end
end
