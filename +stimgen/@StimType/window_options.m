function opts = window_options()
% opts = stimgen.StimType.window_options()
% Catalog of onset/offset gate shapes offered for WindowFcn.
%
% Returns:
%   opts - 1xN struct array with fields:
%            Name  - the value stored in WindowFcn
%            Label - display text used by the generated GUIs
%
% Name is "" (no taper), "cos2" (the historical spelling of a raised-cosine
% gate, synthesized with hann), or the name of a window function taking a
% single length argument. The Window getter fevals whatever name it is
% given, so this catalog is what the GUI offers rather than a restriction on
% what the property accepts: a WindowFcn assigned programmatically to an
% unlisted name still gates, and propMeta appends it to the dropdown so the
% value stays visible instead of being silently rewritten.
%
% Only single-argument windows are listed. kaiser, chebwin and taylorwin
% take a shape parameter that WindowFcn has nowhere to carry, so offering
% them here would show them as if they were fully specified; they remain
% settable by name, at their MATLAB defaults.

names = ["cos2"
         "hamming"
         "blackman"
         "blackmanharris"
         "nuttallwin"
         "flattopwin"
         "bartlett"
         "barthannwin"
         "bohmanwin"
         "parzenwin"
         "triang"
         "tukeywin"
         "gausswin"
         ""];

labels = ["Hann (cosine-squared)"
          "Hamming"
          "Blackman"
          "Blackman-Harris"
          "Nuttall"
          "Flat Top"
          "Bartlett"
          "Bartlett-Hann"
          "Bohman"
          "Parzen"
          "Triangular"
          "Tukey (r = 0.5)"
          "Gaussian (alpha = 2.5)"
          "Rectangular (no taper)"];

opts = struct('Name', num2cell(names(:)'), 'Label', num2cell(labels(:)'));
end
