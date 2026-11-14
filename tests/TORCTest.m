classdef TORCTest < matlab.unittest.TestCase
    % stimgen.TORC's generation record (Klein et al. 2000): that it carries
    % what made the waveform -- the ripple components, carriers and phases --
    % and that the record alone gives back the dynamic spectrum that was
    % played (envelope_from_record), as an analysis rebuilds it from a
    % presentation log.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests/TORCTest.m');
    % See tests/README.md.

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (Test)

        function recordCarriesTheRippleComponents(testCase)
            s = small_('Seed', 3, 'NumPeriods', 2, 'Duration', 0.5);
            s.update_signal();
            r = s.generation_record();
            testCase.assertTrue(r.Generated);
            testCase.verifyEqual(r.Class, "stimgen.TORC");
            testCase.verifyEqual(r.RippleRates, s.RippleRates);
            testCase.verifyEqual(r.RippleDensities, s.RippleDensities);
            testCase.verifyEqual(r.RipplePhases, s.RipplePhases);
            testCase.verifyEqual(r.RippleAmplitude, s.RippleAmplitude);
            testCase.verifyEqual(r.RipplePeriod, 0.25, 'AbsTol', 1e-15);
            testCase.verifyEqual(r.NumPeriods, 2);
            testCase.verifyEqual(r.Duration, 0.5, 'AbsTol', 1e-12);
            testCase.verifyEqual(r.OctaveAxis, s.OctaveAxis);
            testCase.verifyEqual(r.CarrierFrequencies, s.CarrierFrequencies);
            testCase.verifyEqual(r.CarrierPhases, s.CarrierPhases);
            testCase.verifyEqual(r.Seed, 3);
            testCase.verifyEqual(r.LowFrequency, 125);
            testCase.verifyEqual(r.Bandwidth, 5);
            testCase.verifyFalse(r.Gate.Applied);   % a TORC is ungated by default
            % The rates are on the 1/T grid of the ripple period.
            testCase.verifyEqual(r.RippleRates * r.RipplePeriod, round(r.RippleRates * r.RipplePeriod), 'AbsTol', 1e-9);

            u = small_();
            testCase.verifyFalse(u.generation_record().Generated);
        end

        function recordAloneGivesTheDynamicSpectrum(testCase)
            % The same values dynamic_spectrum reports, exactly, also after
            % the record has been through a MAT file.
            s = small_('Seed', 5, 'RippleDensity', -0.8);
            s.update_signal();
            r = s.generation_record();
            [S0, t, x0] = s.dynamic_spectrum(64);
            [S, x] = stimgen.TORC.envelope_from_record(r, t);
            testCase.verifyTrue(isequal(S, S0));
            testCase.verifyEqual(x, x0);

            % Eq. 28 written out: a sum of cosines of amplitude 2a.
            ref = zeros(size(S));
            for i = 1:numel(r.RippleRates)
                ref = ref + 2 * r.RippleAmplitude .* cos(2*pi .* (r.RippleRates(i) .* t + ...
                    r.RippleDensities(i) .* x(:)) + r.RipplePhases(i));
            end
            testCase.verifyEqual(S, ref, 'AbsTol', 1e-10);
            % Its peak-to-peak excursion is the requested ModulationDepth.
            [Sf, ~, ~] = s.dynamic_spectrum(numel(s.Signal));
            testCase.verifyEqual(max(abs(Sf(:))), r.ModulationDepth / 2, 'RelTol', 1e-12);

            f = [tempname '.mat'];
            testCase.addTeardown(@() delete(f));
            StimRecord = {r}; %#ok<NASGU>
            save(f, 'StimRecord', '-v7');
            L = load(f);
            testCase.verifyTrue(isequal(stimgen.TORC.envelope_from_record(L.StimRecord{1}, t), S));
        end

        function eachVariantRecordsItsOwnRipples(testCase)
            % TORC method I: RippleDensity vectorized, one row of the ripple
            % domain per variant; each variant's record names its own row.
            s = small_('Seed', 2, 'RippleDensity', [-0.4 0.4]);
            s.VariantReselectOnUpdate = false;
            s.set_variant_index(1);
            r1 = s.generation_record();
            s.set_variant_index(2);
            r2 = s.generation_record();
            testCase.verifyEqual(unique(r1.RippleDensities), -0.4);
            testCase.verifyEqual(unique(r2.RippleDensities), 0.4);
            testCase.verifyEqual(r1.GeneratedVariantIndex, 1);
            testCase.verifyEqual(r2.GeneratedVariantIndex, 2);
        end

        function badRecordsAndTimesAreRefused(testCase)
            s = small_();
            testCase.verifyError(@() stimgen.TORC.envelope_from_record(s.generation_record(), 0), ...
                'stimgen:TORC:NotGenerated');
            s.update_signal();
            r = s.generation_record();
            testCase.verifyError(@() stimgen.TORC.envelope_from_record(r, 0.3), 'stimgen:TORC:TimeOutOfRange');
            testCase.verifyError(@() stimgen.TORC.envelope_from_record(r, -0.01), 'stimgen:TORC:TimeOutOfRange');
            r.Class = "stimgen.DMR";
            testCase.verifyError(@() stimgen.TORC.envelope_from_record(r, 0), 'stimgen:TORC:NotATorcRecord');
        end

    end
end


function s = small_(varargin)
% The default 250 ms, 5-octave TORC at 48 kHz, uncalibrated, few carriers.
s = stimgen.TORC('Fs', 48000, 'ApplyCalibration', false, 'ComponentsPerOctave', 4, varargin{:});
end
