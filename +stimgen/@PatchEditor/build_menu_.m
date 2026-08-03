function build_menu_(obj)
% build_menu_(obj)
% Construct the File menu: Save, Save As..., Load..., and a Recents submenu
% of the 9 most recently modified .spatch files.

m = uimenu(obj.fig, 'Text', 'File');

uimenu(m, 'Text', 'Save', 'Accelerator', 'S', ...
    'MenuSelectedFcn', @(~,~) obj.save_patch_(false));
uimenu(m, 'Text', 'Save As...', ...
    'MenuSelectedFcn', @(~,~) obj.save_patch_(true));

uimenu(m, 'Text', 'Load...', 'Accelerator', 'O', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) obj.load_patch_());

obj.h.RecentsMenu = uimenu(m, 'Text', 'Recents');

uimenu(m, 'Text', 'Close', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) obj.close_request_());

obj.refresh_recents_menu_();
end
