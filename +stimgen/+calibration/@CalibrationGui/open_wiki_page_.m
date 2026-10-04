function open_wiki_page_(obj, url, dlgTitle, what)
% Hand a wiki page to the system browser, and if there is none,
% put the address where the operator can copy it. The address is
% what they need either way, so a failure states it rather than
% just reporting that nothing opened.
status = web(url, '-browser');
if status ~= 0
    uialert(obj.Figure, sprintf('No browser could be opened.\n\n%s is at:\n%s', ...
        what, url), dlgTitle, Icon='info');
end
end
