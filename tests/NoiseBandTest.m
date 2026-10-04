classdef NoiseBandTest < matlab.unittest.TestCase
    % stimgen.Noise puts its energy where HighPass and LowPass say: the
    % designed band-pass is -6 dB at each cutoff and down by
    % StopbandAttenuation beyond TransitionWidth/2, the generated noise shows
    % the same in its spectrum, and the record does not fade in while a long
    % filter starts up.
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

    methods (TestMethodSetup)
        function seed(testCase)
            previous = rng;
            testCase.addTeardown(@() rng(previous));
            rng(20261004, 'twister');
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function designedFilterMeetsItsEdges(testCase)
            % The defaults: 500 Hz - 20 kHz at 97656.25 Hz, automatic
            % transition (a tenth of 500 Hz), 60 dB stopband.
            n = make_noise_();
            fs = n.Fs;
            b  = n.FilterCoefficients;
            tw = n.DesignedTransition;
            testCase.assertEqual(tw, 50, 'AbsTol', 1e-9);
            testCase.verifyEqual(n.DesignedOrder, numel(b) - 1);

            f = [n.HighPass - tw/2, n.HighPass, n.HighPass + tw/2, 1000, 8000, ...
                 n.LowPass - tw/2, n.LowPass, n.LowPass + tw/2];
            hDb = 20*log10(abs(freqz(b, 1, f, fs)));
            fprintf('NOISEBAND default: %d taps; |H| at %s Hz = %s dB\n', numel(b), ...
                mat2str(f, 6), mat2str(hDb, 4));

            % -6 dB at the cutoffs (a Kaiser design is amplitude 1/2 there).
            testCase.verifyEqual(hDb([2 7]), 20*log10(0.5) * [1 1], 'AbsTol', 0.2);
            % Flat in the band, rejected beyond the transition.
            testCase.verifyEqual(hDb([3 4 5 6]), zeros(1, 4), 'AbsTol', 0.03);
            testCase.verifyLessThanOrEqual(hDb([1 8]), -60 * [1 1]);

            % And everywhere outside: the worst stopband point, densely.
            fStop = [linspace(1, n.HighPass - tw/2, 2000), ...
                     linspace(n.LowPass + tw/2, fs/2 - 1, 2000)];
            worst = max(20*log10(abs(freqz(b, 1, fStop, fs))));
            testCase.verifyLessThanOrEqual(worst, -60);
        end

        function generatedSpectrumIsBandLimited(testCase)
            % What the review asked to check in the inspector's Spectrum tab:
            % the 40-tap filter this replaced left the region below a 500 Hz
            % high-pass only a few dB down.
            n = make_noise_('Duration', 4);
            fs = n.Fs;
            nfft = 2^15;
            [p, f] = pwelch(n.Signal(:), hann(nfft), nfft/2, nfft, fs);
            pass = mean(p(f >= 1000 & f <= 10000));
            below = 10*log10(mean(p(f >= 50 & f <= 400)) / pass);
            above = 10*log10(mean(p(f >= 21000 & f <= 45000)) / pass);
            fprintf('NOISEBAND spectrum: 50-400 Hz %.1f dB, 21-45 kHz %.1f dB re passband\n', ...
                below, above);
            testCase.verifyLessThan(below, -50);
            testCase.verifyLessThan(above, -50);
        end

        function recordDoesNotFadeIn(testCase)
            % A 7000-tap filter started from rest ramps its output up over
            % its own length (72 ms here). The start-up is generated and
            % discarded, so the first 10 ms carry the same power as the rest.
            n = make_noise_('Duration', 1);
            y = n.Signal;
            k = round(0.010 * n.Fs);
            ratioDb = 20*log10(sqrt(mean(y(1:k).^2)) / sqrt(mean(y.^2)));
            fprintf('NOISEBAND first 10 ms: %+.2f dB re whole record\n', ratioDb);
            testCase.verifyEqual(ratioDb, 0, 'AbsTol', 1.5);
            testCase.verifyEqual(numel(y), numel(n.Time));
        end

        function explicitOrderKeepsTheOldDesign(testCase)
            % A saved stimulus that names an order gets the Hamming-window
            % design of that order back, the filter it was made with.
            n = make_noise_('FilterOrder', 40);
            expected = fir1(40, [n.HighPass n.LowPass] / (n.Fs/2), 'bandpass');
            testCase.verifyEqual(n.FilterCoefficients, expected, 'AbsTol', 1e-15);
            testCase.verifyEqual(n.DesignedOrder, 40);
            testCase.verifyTrue(isnan(n.DesignedTransition));
        end

        function explicitTransitionWidthIsHonoured(testCase)
            n = make_noise_('Fs', 48000, 'HighPass', 2000, 'LowPass', 4000, ...
                'TransitionWidth', 200, 'StopbandAttenuation', 80);
            b = n.FilterCoefficients;
            testCase.verifyEqual(n.DesignedTransition, 200);
            hDb = 20*log10(abs(freqz(b, 1, [1900 2000 2100 3900 4000 4100], 48000)));
            testCase.verifyEqual(hDb([2 5]), 20*log10(0.5) * [1 1], 'AbsTol', 0.2);
            testCase.verifyLessThanOrEqual(hDb([1 6]), -80 * [1 1]);
        end

        function modulatedNoiseUsesTheSameFilter(testCase)
            a = stimgen.AMnoise('Fs', 48000, 'Duration', 0.5, 'ApplyWindow', false, ...
                'ApplyCalibration', false, 'HighPass', 1000, 'LowPass', 4000);
            a.update_signal();
            testCase.verifyEqual(a.DesignedTransition, 100, 'AbsTol', 1e-9);
            testCase.verifyEqual(numel(a.Signal), numel(a.Time));
            testCase.verifyTrue(all(isfinite(a.Signal)));
        end

        function bandOutsideNyquistIsRefused(testCase)
            n = stimgen.Noise('Fs', 48000, 'LowPass', 30000, 'ApplyCalibration', false);
            testCase.verifyError(@() n.update_signal(), 'stimgen:Noise:InvalidBand');
            n = stimgen.Noise('Fs', 48000, 'HighPass', 0, 'ApplyCalibration', false);
            testCase.verifyError(@() n.update_signal(), 'stimgen:Noise:InvalidBand');
        end

        function transitionWiderThanTheBandIsRefused(testCase)
            n = stimgen.Noise('Fs', 48000, 'HighPass', 1000, 'LowPass', 1200, ...
                'TransitionWidth', 300, 'ApplyCalibration', false);
            testCase.verifyError(@() n.update_signal(), 'stimgen:Noise:InvalidTransition');
        end

    end
end


% ====================================================================== %

function n = make_noise_(varargin)
n = stimgen.Noise('ApplyWindow', false, 'ApplyCalibration', false, varargin{:});
n.update_signal();
end
