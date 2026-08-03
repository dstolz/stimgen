function [x, y] = wire_path_(p1, p2)
% [x, y] = stimgen.PatchEditor.wire_path_(p1, p2)
% Polyline for a connection wire: a cubic bezier with horizontal tangents, so
% wires leave and enter ports sideways and read as signal flow.
%
% Shared by the renderer and by hit testing. If these two ever computed the
% curve separately, clicks would land off the drawn wire.

t  = linspace(0, 1, 24);
dx = max(0.06, abs(p2(1) - p1(1)) * 0.5);
c1 = [p1(1) + dx, p1(2)];
c2 = [p2(1) - dx, p2(2)];

b = @(a, bb, c, d) (1-t).^3.*a + 3*(1-t).^2.*t.*bb + 3*(1-t).*t.^2.*c + t.^3.*d;
x = b(p1(1), c1(1), c2(1), p2(1));
y = b(p1(2), c1(2), c2(2), p2(2));
end
