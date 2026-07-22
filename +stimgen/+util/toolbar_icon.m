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
%          "disconnect", "help", "add", "remove", "play"
%
% Returns:
%   icon - 24-by-24-by-3 double array in [0,1] (NaN = transparent)

arguments
    name (1,1) string {mustBeMember(name, ["open","save","protocol", ...
        "calibration","connect","disconnect","help","add","remove","play"])}
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
end

accent = [0.16 0.38 0.58];
icon = nan(N, N, 3);
for k = 1:3
    layer = nan(N);
    layer(mask) = accent(k);
    icon(:,:,k) = layer;
end

end
