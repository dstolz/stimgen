function commit_notes_(obj)
% Push the notes text onto the engine, where save() will find it.
% Called on every edit and again before a save, because a click
% straight from the text area to a toolbar button need not have
% fired the edit callback first, and the note would then be left
% out of the file it was written for.
if isempty(obj.NotesArea) || ~isvalid(obj.NotesArea)
    return
end
v = obj.NotesArea.Value;
if isempty(v)
    txt = "";
else
    txt = join(string(v(:)), newline);
end
obj.Engine.set_configuration(Notes=txt);
end
