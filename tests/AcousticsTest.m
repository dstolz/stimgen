classdef AcousticsTest < matlab.unittest.TestCase
    % Level scale, frequency weighting, band arithmetic and the sound level
    % meter: the pure numerical core every level in the package rests on.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function weightingIsZeroAtOneKilohertz(testCase)
            % Every weighting is defined to pass through 0 dB at 1 kHz.
            for wt = ["A", "C", "Z"]
                testCase.verifyEqual(stimgen.util.weighting_db(1000, wt), 0, ...
                    'AbsTol', 1e-12, sprintf('%s-weighting at 1 kHz', wt));
            end
        end

        function weightingMatchesIec61672Table(testCase)
            % IEC 61672-1:2013 Table 3 (frequency weightings A and C), at the
            % exact base-ten frequencies fm = 1000 * 10^(n/10) the table is
            % computed at. The table is rounded to 0.1 dB, so the analytic
            % curve has to land within half a step of it (plus a hair for the
            % numerical 1 kHz normalization). That is far inside the class 1
            % acceptance limits, which allow several tenths of a dB and more.
            n  = [-15 -12 -9 -6 -3 0 3 6 9 12];          % 31.5 Hz .. 16 kHz nominal
            fm = 1000 * 10 .^ (n / 10);
            tableA = [-39.4 -26.2 -16.1 -8.6 -3.2 0 1.2 1.0 -1.1 -6.6];
            tableC = [ -3.0  -0.8  -0.2  0.0  0.0 0 -0.2 -0.8 -3.0 -8.5];
            tol = 0.06;

            testCase.verifyEqual(stimgen.util.weighting_db(fm, "A"), tableA, 'AbsTol', tol);
            testCase.verifyEqual(stimgen.util.weighting_db(fm, "C"), tableC, 'AbsTol', tol);
        end

        function weightingKeepsShapeAndTakesMagnitude(testCase)
            f = [100 1000; 4000 10000];
            w = stimgen.util.weighting_db(f, "A");
            testCase.verifySize(w, size(f));
            testCase.verifyEqual(stimgen.util.weighting_db(-f, "A"), w, 'AbsTol', 1e-12);
            testCase.verifyEqual(stimgen.util.weighting_db(f, "Z"), zeros(size(f)));
        end

        function voltsToSplAndPressureAreInverse(testCase)
            spl  = [0 20 60 93.9794 114 130];
            sens = 0.0123;   % V/Pa
            pa   = stimgen.calibration.Engine.spl_to_pressure(spl);
            back = stimgen.calibration.Engine.volts_to_spl(pa * sens, sens);
            testCase.verifyEqual(back, spl, 'AbsTol', 1e-9);

            % 0 dB SPL is the 20 uPa reference itself; 1 Pa is 93.98 dB SPL.
            testCase.verifyEqual(stimgen.calibration.Engine.spl_to_pressure(0), ...
                stimgen.calibration.Engine.ReferencePressurePa, 'RelTol', 1e-12);
            testCase.verifyEqual(stimgen.calibration.Engine.volts_to_spl(1, 1), ...
                20 * log10(1 / 20e-6), 'AbsTol', 1e-9);

            % A silent input is -Inf, not an error.
            testCase.verifyEqual(stimgen.calibration.Engine.volts_to_spl(0, 1), -Inf);
        end

        function soundLevelsOfOnePascalSine(testCase)
            % A 1 kHz sine of 1 Pa rms, recorded through a 1 V/Pa microphone,
            % is 20*log10(1/20e-6) = 93.979 dB SPL. Whole cycles in the record,
            % so its sampled rms is exactly 1.
            fs = 48000;
            t  = (0:fs-1) / fs;                 % 1 s, 1000 whole cycles
            y  = sqrt(2) * sin(2*pi*1000*t);
            expected = 20 * log10(1 / 20e-6);   % 93.9794...

            S = stimgen.util.sound_levels(y, fs, 1);
            z = S.Weightings == "Z";
            a = S.Weightings == "A";
            c = S.Weightings == "C";

            testCase.verifyEqual(S.Unit, "dB SPL");
            testCase.verifyEqual(S.Leq(z), expected, 'AbsTol', 1e-6);
            % Over one second LE is Leq.
            testCase.verifyEqual(S.LE(z), expected, 'AbsTol', 1e-6);
            % Peak-equivalent: the peak over sqrt(2) is the rms of this sine.
            testCase.verifyEqual(S.peSPL, expected, 'AbsTol', 1e-6);
            testCase.verifyEqual(S.ppeSPL, expected, 'AbsTol', 1e-6);
            % Unweighted peak is 3.01 dB above the rms level.
            testCase.verifyEqual(S.Lpeak(z), expected + 20*log10(sqrt(2)), 'AbsTol', 1e-6);
            % A and C pass 1 kHz at 0 dB; the onset transient of the
            % network on a gated sine is what the tolerance allows for.
            testCase.verifyEqual(S.Leq(a), expected, 'AbsTol', 0.05);
            testCase.verifyEqual(S.Leq(c), expected, 'AbsTol', 0.05);
        end

        function soundLevelsWithoutSensitivityAreDbReOne(testCase)
            fs = 48000;
            t  = (0:fs-1) / fs;
            y  = sqrt(2) * sin(2*pi*1000*t);    % 1 V rms
            S  = stimgen.util.sound_levels(y, fs);
            testCase.verifyEqual(S.Unit, "dB re 1");
            testCase.verifyEqual(S.Leq(S.Weightings == "Z"), 0, 'AbsTol', 1e-6);
        end

        function soundLevelsOfConstantRecordAreNaN(testCase)
            % DC is not sound: a constant record, zero or not, has no level.
            S = stimgen.util.sound_levels(0.3 * ones(1, 4800), 48000, 1);
            testCase.verifyTrue(all(isnan(S.Leq)));
            testCase.verifyTrue(isnan(S.peSPL));
        end

        function bandLevelsOnFlatPsd(testCase)
            % A flat PSD of 1 unit^2/Hz puts in each band a power equal to its
            % width, to within one bin either way.
            df = 1;
            f  = (0:df:24000)';
            pxx = ones(size(f));
            b = stimgen.util.band_levels(pxx, f, df, 3, 20, 20000);

            G = 10 ^ (3/10);   % IEC 61260-1 base-ten octave ratio
            testCase.verifyNotEmpty(b.frequency);
            testCase.verifyEqual(b.fraction, 3);

            % Centres on the base-ten series through 1 kHz exactly.
            k = round(3 * log(b.frequency / 1000) / log(G));
            testCase.verifyEqual(b.frequency, 1000 * G .^ (k / 3), 'RelTol', 1e-12);
            testCase.verifyTrue(any(abs(b.frequency - 1000) < 1e-9));
            testCase.verifyEqual(diff(k), ones(1, numel(k) - 1));

            % Edges a sixth of an octave either side, all inside [fMin, fMax].
            testCase.verifyEqual(b.edges(2, :) ./ b.edges(1, :), ...
                repmat(G ^ (1/3), 1, numel(b.frequency)), 'RelTol', 1e-12);
            testCase.verifyGreaterThanOrEqual(b.edges(1, :), 20);
            testCase.verifyLessThanOrEqual(b.edges(2, :), 20000);

            width = b.edges(2, :) - b.edges(1, :);
            testCase.verifyLessThanOrEqual(abs(b.power - width), df);
        end

        function bandLevelsDropBandsWithNoBins(testCase)
            % A band that holds no bin is dropped rather than reported as 0.
            f   = (0:100:24000)';
            pxx = ones(size(f));
            b = stimgen.util.band_levels(pxx, f, 100, 12, 10, 20000);
            testCase.verifyNotEmpty(b.power);
            % Below ~1.7 kHz a twelfth-octave band is narrower than a bin, so
            % some are empty; each one reported holds at least one bin, and
            % its power is that many bins.
            for k = 1:numel(b.power)
                inBand = f >= b.edges(1, k) & f < b.edges(2, k);
                testCase.verifyTrue(any(inBand));
                testCase.verifyEqual(b.power(k), nnz(inBand) * 100, 'AbsTol', 1e-9);
            end
            dense = stimgen.util.band_levels(ones(24001, 1), (0:24000)', 1, 12, 10, 20000);
            testCase.verifyLessThan(numel(b.power), numel(dense.power));
            testCase.verifyTrue(all(isfinite(b.power)));
            testCase.verifyTrue(all(b.power > 0));
        end

    end
end
