function finish_dialog_(fig, ok)
% Cancel, Escape, or the window's own close button.
fig.UserData = struct('ok', ok);
uiresume(fig);
end
