function render_(obj, d)
% render_(obj, d)
% Draw all three panels from one payload. Each panel skips itself when its
% axes were never supplied or have since been deleted.

if isgraphics(obj.AxSignal)
    obj.render_signal_(d);
end
if isgraphics(obj.AxSpectrum)
    obj.render_spectrum_(d);
end
if isgraphics(obj.AxTransfer) && ~isempty(d.Table.x)
    obj.render_transfer_(d);
end
end
