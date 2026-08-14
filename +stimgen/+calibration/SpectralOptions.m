classdef SpectralOptions
    % stimgen.calibration.SpectralOptions
    % Analysis window and transform length used by the calibration package's
    % spectral estimators.
    %
    % One value object carries the two choices that decide what a spectrum
    % measures: the taper applied to the record, and how many points the
    % transform runs over. Both the Engine's estimators and the LiveMonitor's
    % spectrum panel resolve their window and NFFT through this object, so the
    % peak drawn on screen is computed the same way as the number written into
    % the lookup table.
    %
    % Both properties default to "let each estimator choose", which is what
    % makes adding this class change no measured value: an engine that has
    % never been configured produces exactly the numbers it did before.
    %
    % Window
    %   "auto" defers to the estimator's own default -- flat top for the
    %   single-record periodograms that measure a tone's amplitude, Hann for
    %   the Welch averages that measure a noise floor. Naming a window applies
    %   it everywhere instead.
    %
    %   Flat top has the flattest passband of the set: a tone lands within
    %   ~0.01 dB of its true amplitude no matter where it falls between bins,
    %   which is why it is what a level measurement wants. It pays for that
    %   with a wide main lobe, so it cannot separate two close components.
    %   Hann, Hamming, Blackman and Blackman-Harris trade increasing sidelobe
    %   suppression against increasing main-lobe width and worsening amplitude
    %   accuracy; rectangular has the narrowest main lobe and the worst
    %   leakage, and is only right for a signal that is periodic in the record.
    %
    % FftLength
    %   0 defers to the estimator, which uses the next power of two at or
    %   above the record length. A nonzero value is a FLOOR on that, not a
    %   replacement: it can only zero-pad further, never truncate. A transform
    %   shorter than the record would make MATLAB wrap the record modulo the
    %   transform length and alias one part of the signal onto another, which
    %   is never what a calibration wants. Zero padding buys finer bin spacing
    %   -- an interpolated view of the same underlying resolution -- which
    %   places a peak more precisely without resolving anything new.
    %
    % Usage:
    %   s = stimgen.calibration.SpectralOptions();                 % defaults
    %   s = stimgen.calibration.SpectralOptions("hann", 2^16);
    %   w = s.taper(numel(y), "flattop");        % window vector for a record
    %   n = s.transform_length(2^nextpow2(numel(y)));
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.LiveMonitor,
    %           stimgen.calibration.CalibrationGui

    properties (Constant)
        % Offered in GUI order: the default first, then decreasing amplitude
        % accuracy and increasing frequency resolution.
        WindowList = ["auto", "flattop", "hann", "hamming", "blackman", ...
            "blackmanharris", "rectangular"]

        % Transform lengths a GUI offers. 0 is the automatic length; the rest
        % are powers of two, since that is the only thing zero padding is
        % worth expressing in.
        FftLengthList = [0, 2 .^ (10:20)]
    end

    properties
        Window (1,1) string {mustBeMember(Window, ["auto", "flattop", ...
            "hann", "hamming", "blackman", "blackmanharris", ...
            "rectangular"])} = "auto"
        FftLength (1,1) double {mustBeNonnegative, mustBeInteger, mustBeFinite} = 0
    end

    methods
        function obj = SpectralOptions(window, fftLength)
            % obj = stimgen.calibration.SpectralOptions()
            % obj = stimgen.calibration.SpectralOptions(window)
            % obj = stimgen.calibration.SpectralOptions(window, fftLength)
            %
            % Parameters:
            %   window    - (1,1) string in WindowList; "auto" by default
            %   fftLength - (1,1) double transform-length floor; 0 for
            %               automatic
            arguments
                window    (1,1) string = "auto"
                fftLength (1,1) double = 0
            end
            obj.Window = window;
            obj.FftLength = fftLength;
        end

        function w = taper(obj, n, defaultKind, sflag)
            % w = taper(obj, n)
            % w = taper(obj, n, defaultKind)
            % w = taper(obj, n, defaultKind, sflag)
            % Window vector of length n, resolving "auto" to defaultKind.
            %
            % sflag follows the caller's existing convention rather than
            % being chosen here: a periodogram of a whole record wants the
            % symmetric form, a Welch average of overlapped segments the
            % periodic one, and switching either would move numbers that
            % have nothing to do with the user's choice of window.
            %
            % Parameters:
            %   n           - (1,1) double window length in samples
            %   defaultKind - (1,1) string window "auto" resolves to
            %   sflag       - (1,1) string "symmetric" | "periodic"
            %
            % Returns:
            %   w - (n,1) double window vector
            arguments
                obj
                n (1,1) double {mustBePositive, mustBeInteger}
                defaultKind (1,1) string {mustBeMember(defaultKind, ...
                    ["flattop", "hann", "hamming", "blackman", ...
                     "blackmanharris", "rectangular"])} = "flattop"
                sflag (1,1) string {mustBeMember(sflag, ...
                    ["symmetric", "periodic"])} = "symmetric"
            end

            kind = obj.Window;
            if kind == "auto"
                kind = defaultKind;
            end

            % char(): the window functions take the flag as a character
            % vector on every release this package supports.
            s = char(sflag);
            switch kind
                case "flattop"
                    w = flattopwin(n, s);
                case "hann"
                    w = hann(n, s);
                case "hamming"
                    w = hamming(n, s);
                case "blackman"
                    w = blackman(n, s);
                case "blackmanharris"
                    w = blackmanharris(n, s);
                case "rectangular"
                    % No taper at all, and no periodic/symmetric distinction
                    % to make: every sample weighs the same either way.
                    w = rectwin(n);
            end
        end

        function nfft = transform_length(obj, autoLength)
            % nfft = transform_length(obj, autoLength)
            % Transform length to use, given what the estimator would have
            % chosen on its own.
            %
            % A configured length raises autoLength and never lowers it, so a
            % setting left over from a rig with longer records cannot quietly
            % start aliasing shorter ones. A GUI that wants to say the request
            % had no effect can compare the two.
            %
            % Parameters:
            %   autoLength - (1,1) double length the caller would have used
            %
            % Returns:
            %   nfft - (1,1) double transform length
            arguments
                obj
                autoLength (1,1) double {mustBePositive}
            end
            nfft = max(autoLength, obj.FftLength);
        end

        function tf = isDefault(obj)
            % tf = isDefault(obj)
            % True when neither choice has been made, i.e. every estimator
            % keeps its own window and transform length.
            tf = obj.Window == "auto" && obj.FftLength == 0;
        end

        function s = toStruct(obj)
            % s = toStruct(obj)
            % Plain struct, for the LiveUpdate context and saved files.
            s = struct('SpectralWindow', obj.Window, ...
                       'SpectralFftLength', obj.FftLength);
        end
    end

    methods (Static)
        function obj = fromStruct(s)
            % obj = stimgen.calibration.SpectralOptions.fromStruct(s)
            % Rebuild from a struct that may predate either field, which is
            % what a LiveUpdate payload or a saved calibration written before
            % these settings existed looks like. A missing field means the
            % automatic behavior, which is what that data was produced under.
            %
            % Parameters:
            %   s - struct with optional SpectralWindow/SpectralFftLength
            %
            % Returns:
            %   obj - stimgen.calibration.SpectralOptions
            obj = stimgen.calibration.SpectralOptions();
            if isfield(s, 'SpectralWindow') && ~isempty(s.SpectralWindow)
                obj.Window = string(s.SpectralWindow);
            end
            if isfield(s, 'SpectralFftLength') && ~isempty(s.SpectralFftLength)
                obj.FftLength = s.SpectralFftLength;
            end
        end

        function t = windowLabel(kind)
            % t = stimgen.calibration.SpectralOptions.windowLabel(kind)
            % Display text for one window name, for a GUI list.
            arguments
                kind (1,1) string
            end
            switch kind
                case "auto",           t = "Auto (per measurement)";
                case "flattop",        t = "Flat top";
                case "hann",           t = "Hann";
                case "hamming",        t = "Hamming";
                case "blackman",       t = "Blackman";
                case "blackmanharris", t = "Blackman-Harris";
                case "rectangular",    t = "Rectangular (none)";
                otherwise,             t = kind;
            end
        end

        function t = fftLengthLabel(n)
            % t = stimgen.calibration.SpectralOptions.fftLengthLabel(n)
            % Display text for one transform length, for a GUI list.
            arguments
                n (1,1) double
            end
            % The exponent is only shown when it is exact: a hand-set or
            % restored length need not be a power of two, and rounding one
            % into "(2^12)" would misstate the value sitting next to it.
            if n <= 0
                t = "Auto (next power of 2)";
            elseif n == 2 ^ round(log2(n))
                t = sprintf("%d  (2^%d)", n, round(log2(n)));
            else
                t = sprintf("%d", n);
            end
        end
    end
end
