function p = canvas_point_(obj)
% p = canvas_point_(obj)
% Current pointer position in canvas (0..1) coordinates, or [] when the
% pointer is outside the canvas.
%
% CurrentPoint keeps reporting the last in-axes position once the pointer
% leaves, so the figure's own pointer location decides whether the point is
% usable, and the axes only supplies the data-space mapping.

if isempty(obj.ax) || ~isvalid(obj.ax)
    p = [];
    return
end

figPt = obj.fig.CurrentPoint;
axPos = getpixelposition(obj.ax, true);

inside = figPt(1) >= axPos(1) && figPt(1) <= axPos(1) + axPos(3) && ...
         figPt(2) >= axPos(2) && figPt(2) <= axPos(2) + axPos(4);
if ~inside
    p = [];
    return
end

cp = obj.ax.CurrentPoint;
p  = [cp(1,1), cp(1,2)];
end
