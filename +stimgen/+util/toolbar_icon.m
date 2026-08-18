function icon = toolbar_icon(name)
% icon = toolbar_icon(name)
% Procedurally-drawn flat glyph for a stimgen GUI toolbar button.
%
% Icons are generated as small RGB arrays rather than shipped as image
% files, keeping the toolbox free of binary assets. Background pixels are
% NaN, which uipushtool/uitoggletool render as transparent.
%
% Parameters:
%   name - one of "open", "save", "protocol", "calibration", "connect",
%          "disconnect", "help", "add", "remove", "play", "inspect",
%          "refresh", "transfer", "background", "ghost", "voltage", "logx",
%          "camera"
%
% Returns:
%   icon - 24-by-24-by-3 double array in [0,1] (NaN = transparent)

arguments
    name (1,1) string {mustBeMember(name, ["open","save","protocol", ...
        "calibration","connect","disconnect","help","add","remove","play", ...
        "inspect","refresh","transfer","background","ghost","voltage","logx", ...
        "camera"])}
end

N = 24;
[col, row] = meshgrid(1:N, 1:N);
mask = false(N);

switch name
    case "open" % folder
        mask = mask | (row>=6  & row<=10 & col>=4 & col<=11);
        mask = mask | (row>=10 & row<=20 & col>=4 & col<=21);

    case "save" % floppy disk
        body    = row>=4  & row<=21 & col>=4  & col<=21;
        shutter = row>=6  & row<=10 & col>=7  & col<=18;
        label   = row>=13 & row<=19 & col>=7  & col<=18;
        mask = body & ~shutter & ~label;

    case "protocol" % document with text lines
        doc   = row>=4  & row<=21 & col>=6 & col<=19;
        line1 = row>=7  & row<=8  & col>=8 & col<=17;
        line2 = row>=10 & row<=11 & col>=8 & col<=17;
        line3 = row>=13 & row<=14 & col>=8 & col<=17;
        line4 = row>=16 & row<=17 & col>=8 & col<=17;
        mask = doc & ~line1 & ~line2 & ~line3 & ~line4;

    case "calibration" % measurement gauge with needle
        cx = 12.5; cy = 13;
        d = sqrt((row-cy).^2 + (col-cx).^2);
        ring = d>=8 & d<=10 & row<=cy+1;
        hub  = d<=1.8;
        needle = false(N);
        for t = 0:0.25:7.5
            r = round(cy - t*0.9);
            c = round(cx + t*0.55);
            if r>=1 && r<=N && c>=1 && c<=N-1
                needle(r,c)   = true;
                needle(r,c+1) = true;
            end
        end
        mask = ring | hub | needle;

    case "connect" % plug, continuous cable
        prong1 = row>=4  & row<=9  & col>=10 & col<=11;
        prong2 = row>=4  & row<=9  & col>=14 & col<=15;
        head   = row>=9  & row<=14 & col>=7  & col<=18;
        cable  = row>=14 & row<=21 & col>=12 & col<=13;
        mask = prong1 | prong2 | head | cable;

    case "disconnect" % plug, broken cable
        prong1 = row>=4  & row<=9  & col>=10 & col<=11;
        prong2 = row>=4  & row<=9  & col>=14 & col<=15;
        head   = row>=9  & row<=14 & col>=7  & col<=18;
        cableA = row>=14 & row<=17 & col>=12 & col<=13;
        cableB = row>=19 & row<=21 & col>=12 & col<=13;
        mask = prong1 | prong2 | head | cableA | cableB;

    case "help" % question mark in a circle
        cx = 12.5; cy = 12.5;
        d = sqrt((row-cy).^2 + (col-cx).^2);
        ring    = d>=8 & d<=9.5;
        hookArc = d>=3 & d<=5 & row<=cy-1 & col>=cx-1;
        stem    = row>=12 & row<=15 & col>=11 & col<=14;
        dot     = row>=17 & row<=19 & col>=11 & col<=14;
        mask = ring | hookArc | stem | dot;

    case "add" % plus sign
        horiz = row>=11 & row<=13 & col>=5  & col<=20;
        vert  = row>=5  & row<=20 & col>=11 & col<=13;
        mask = horiz | vert;

    case "remove" % minus sign
        mask = row>=11 & row<=13 & col>=5 & col<=20;

    case "play" % right-pointing triangle
        topRow = 5; botRow = 20; baseCol = 7; apexCol = 19;
        midRow = (topRow + botRow) / 2;
        frac = max(0, 1 - abs(row - midRow) ./ (midRow - topRow));
        rightBound = baseCol + frac .* (apexCol - baseCol);
        mask = row>=topRow & row<=botRow & col>=baseCol & col<=rightBound;

    case "inspect" % magnifier over a waveform trace
        cx = 11; cy = 11;
        d = sqrt((row-cy).^2 + (col-cx).^2);
        lens   = d>=6 & d<=7.5;
        stem   = abs(row-col)<=1 & row>=15 & row<=21 & col>=15 & col<=21;
        % A half-cycle of a sine inside the lens marks it as a signal view.
        trace = false(N);
        for c = 6:16
            r = round(cy - 3.2*sin((c-6)/10 * 2*pi));
            if r>=1 && r<=N
                trace(r,c) = true;
            end
        end
        mask = lens | stem | (trace & d<=5.5);

    case "refresh" % circular arrow
        cx = 12; cy = 13;
        d = sqrt((row-cy).^2 + (col-cx).^2);
        ring = d>=6 & d<=8;
        gap  = col>=cx & row<=cy-4;                       % opening, upper right
        head = row>=3 & row<=10 & col>=13 & col<=21 & ... % arrowhead in the gap
               ((row-3) + (21-col) <= 7);
        mask = (ring & ~gap) | head;

    case "transfer" % axes carrying a rising, saturating response curve
        c = 6:21;
        mask = trace_(plot_frame_(), c, round(18 - 12*(1 - exp(-(c-6)/7))), 2);

    case "background" % axes carrying a low, ragged noise floor
        % Two incommensurate sinusoids, so the trace reads as noise without a
        % random draw that would make the icon differ between calls.
        c = 6:21;
        mask = trace_(plot_frame_(), c, ...
            round(15 - 1.5*sin(c*1.9) - 1.1*cos(c*0.8)), 1);

    case "ghost" % a spectral peak with the previous measurement behind it
        c = 4:21;
        mask = trace_(mask, c, round(17 - 11*exp(-((c-11)/3.8).^2)), 2);
        mask = trace_(mask, c, round(19 - 8*exp(-((c-14.5)/3.8).^2)), 1);

    case "voltage" % lightning bolt -- the required drive voltage
        % Both tips are blunted rather than brought to a point: a sub-pixel
        % tip rasterizes into a detached speck at this size.
        boltCol = [12 7 11  9 12 17 12 16];
        boltRow = [ 4 13 13 20 20 11 11  4];
        mask = inpolygon(col, row, boltCol, boltRow);

    case "camera" % camera body with lens -- capture the window
        bump = row>=5 & row<=8  & col>=8 & col<=15;
        body = row>=8 & row<=20 & col>=3 & col<=22;
        cx = 12.5; cy = 14;
        d = sqrt((row-cy).^2 + (col-cx).^2);
        ring = d>=2.4 & d<=4.4;   % transparent ring leaves a solid lens disc
        mask = (bump | body) & ~ring;

    case "logx" % baseline under log-spaced frequency ticks
        mask = row>=16 & row<=17 & col>=3 & col<=22;
        for k = [1 2 3 5 10]
            c = round(3 + 19*log10(k));
            if k == 1 || k == 10   % decade ends, drawn taller
                mask(11:15, c:c+1) = true;
            else
                mask(12:15, c) = true;
            end
        end
end

accent = [0.16 0.38 0.58];
icon = nan(N, N, 3);
for k = 1:3
    layer = nan(N);
    layer(mask) = accent(k);
    icon(:,:,k) = layer;
end

% ------------------------------------------------------------------------ %
    function m = plot_frame_()
        % L-shaped axis the plot-view icons hang a trace on, so those icons
        % differ only in the trace and read as a set.
        m = false(N);
        m(4:20, 4:5)  = true;
        m(19:20, 4:21) = true;
    end

    function m = trace_(m, cs, rs, thickness)
        % Polyline through (cs, rs), filled between consecutive rows so a
        % steep segment stays connected instead of breaking into a scatter.
        rs = min(max(rs, 1), N - thickness);
        for i = 1:numel(cs)
            j = min(i + 1, numel(cs));
            m(min(rs(i), rs(j)) : max(rs(i), rs(j)) + thickness - 1, cs(i)) = true;
        end
    end
end
