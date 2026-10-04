classdef StimTypeTest < matlab.unittest.TestCase
    % Serialization round trips, variant combination tables and variant
    % selection state for the concrete stimgen.StimType subclasses. No GUI,
    % no audio device, no hardware.
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

        function listOffersOnlyConcreteStimTypes(testCase)
            names = stimgen.StimType.list();
            testCase.verifyNotEmpty(names);
            testCase.verifyTrue(any(strcmp(names, 'Tone')));
            base = ?stimgen.StimType;
            for k = 1:numel(names)
                mc = meta.class.fromName(['stimgen.' names{k}]);
                testCase.verifyFalse(isempty(mc), names{k});
                testCase.verifyFalse(mc.Abstract, names{k});
                testCase.verifyTrue(mc < base, names{k});
            end
            % CapturedSignal is a StimType kept out of the list by living in
            % a class folder; the helper classes are not StimTypes at all.
            testCase.verifyFalse(any(strcmp(names, 'CapturedSignal')));
            testCase.verifyFalse(any(strcmp(names, 'StimPlay')));
            testCase.verifyFalse(any(strcmp(names, 'HardwareHost')));
        end

        function everyStimTypeRoundTripsThroughStruct(testCase)
            % toStruct -> fromStruct -> toStruct reproduces the struct, for
            % every class StimType.list() offers, at its defaults.
            % Calibration off so the restore never looks for a calibration
            % table that a default stimulus does not have. Generated once
            % first, because the restored object has been (every restored
            % property regenerates it), so both sides are compared after a
            % generation.
            names = stimgen.StimType.list();
            for k = 1:numel(names)
                cls = ['stimgen.' names{k}];
                obj = feval(cls, 'ApplyCalibration', false);
                obj.update_signal();
                testCase.verifyNotEmpty(obj.Signal, sprintf('%s generated no signal', cls));
                verify_round_trip_(testCase, obj, cls);
            end
        end

        function vectorizedToneRoundTripsWithVariantPolicy(testCase)
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, ...
                'Duration', 0.05, 'Frequency', [1000 2000 4000], ...
                'SoundLevel', [40 50 60], 'OnsetPhase', 90, ...
                'VariantCombinationMode', "PairwiseStrict", ...
                'VariantSelectionMode', "ShuffleLeastUsed", ...
                'DisplayName', "round trip");
            S = verify_round_trip_(testCase, t, 'stimgen.Tone');
            testCase.verifyEqual(S.Frequency, [1000 2000 4000]);
            testCase.verifyEqual(S.VariantCombinationMode, "PairwiseStrict");

            t2 = stimgen.StimType.fromStruct(S);
            testCase.verifyEqual(t2.get_variant_info().NumCombinations, 3);
        end

        function soundFileRoundTripsWithAFile(testCase)
            % A short wav written to a temporary folder, so the catalog has
            % an entry and the regenerated waveform can be compared sample
            % for sample.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            ffn = fullfile(tmp.Folder, 'tone_1k.wav');
            fsFile = 48000;
            tt = (0:round(0.1 * fsFile) - 1)' / fsFile;
            audiowrite(ffn, 0.5 * sin(2*pi*1000*tt), fsFile);

            s = stimgen.SoundFile('Fs', 48000, 'ApplyCalibration', false);
            s.add_files(string(ffn));
            testCase.verifyEqual(s.NFiles, 1);
            s.update_signal();
            testCase.verifyEqual(s.Duration, 0.1, 'AbsTol', 1 / 48000);

            S  = verify_round_trip_(testCase, s, 'stimgen.SoundFile');
            s2 = stimgen.StimType.fromStruct(S);
            s2.update_signal();
            testCase.verifyEqual(s2.Signal, s.Signal, 'AbsTol', 1e-12);
        end

        function cartesianCombinationTable(testCase)
            % The first vectorized property (in UserProperties order) varies
            % fastest: ndgrid order.
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000], 'SoundLevel', [50 60]);
            info = t.get_variant_info();
            testCase.verifyEqual(info.NumCombinations, 6);
            testCase.verifyEqual(sort(info.PropertyNames), sort(["Frequency" "SoundLevel"]));

            [freq, level] = combination_table_(t);
            testCase.verifyEqual(freq,  [1000 2000 4000 1000 2000 4000]);
            testCase.verifyEqual(level, [  50   50   50   60   60   60]);
        end

        function pairwiseStrictCombinationTable(testCase)
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000], 'SoundLevel', [50 60 70], ...
                'VariantCombinationMode', "PairwiseStrict");
            testCase.verifyEqual(t.get_variant_info().NumCombinations, 3);
            [freq, level] = combination_table_(t);
            testCase.verifyEqual(freq,  [1000 2000 4000]);
            testCase.verifyEqual(level, [  50   60   70]);
        end

        function pairwiseStrictRejectsUnequalLengths(testCase)
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000], 'SoundLevel', [50 60], ...
                'VariantCombinationMode', "PairwiseStrict");
            testCase.verifyError(@() t.get_variant_info(), ...
                'stimgen:StimType:PairwiseLengthMismatch');
        end

        function pairwiseScalarExpandCombinationTable(testCase)
            % A scalar property is not a variant axis at all, so it is simply
            % absent from the table; unequal vectors are still rejected.
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000], 'SoundLevel', 60, ...
                'VariantCombinationMode', "PairwiseScalarExpand");
            info = t.get_variant_info();
            testCase.verifyEqual(info.NumCombinations, 3);
            testCase.verifyEqual(info.PropertyNames, "Frequency");

            t2 = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000], 'SoundLevel', [50 60], ...
                'VariantCombinationMode', "PairwiseScalarExpand");
            testCase.verifyError(@() t2.get_variant_info(), ...
                'stimgen:StimType:PairwiseLengthMismatch');
        end

        function activeVariantValuesDoesNotAdvance(testCase)
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000]);   % Serial selection (default)
            t.update_signal();                   % generates combination 1

            v1 = t.active_variant_values();
            v2 = t.active_variant_values();
            testCase.verifyEqual(v1.Frequency, 1000);
            testCase.verifyEqual(v2.Frequency, 1000);
            testCase.verifyEqual(t.get_variant_info().ActiveIndex, 1);

            % selected_value outside a cycle is the call that DOES advance --
            % the contrast the read-only accessor exists for.
            testCase.verifyEqual(double(t.selected_value("Frequency")), 2000);
            v3 = t.active_variant_values();
            testCase.verifyEqual(v3.Frequency, 2000);
            v4 = t.active_variant_values();
            testCase.verifyEqual(v4.Frequency, 2000);
        end

        function pinnedCopyLeavesTheSourceAlone(testCase)
            % How StimPlayer's Play All, CombinationViewer and capture
            % generate: copy once, reselection off, then set_variant_index on
            % the copy. The source keeps its combination, its Signal and the
            % order its next update_signal selects in.
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01, ...
                'Frequency', [1000 2000 4000]);
            t.update_signal();                    % combination 1
            sig = t.Signal;

            c = copy(t);
            c.VariantReselectOnUpdate = false;
            for k = 1:3
                c.set_variant_index(k);
                testCase.verifyEqual(c.active_variant_values().Frequency, ...
                    1000 * 2^(k - 1));
            end

            testCase.verifyTrue(t.VariantReselectOnUpdate);
            testCase.verifyEqual(t.get_variant_info().ActiveIndex, 1);
            testCase.verifyEqual(t.active_variant_values().Frequency, 1000);
            testCase.verifyEqual(t.Signal, sig);
            t.update_signal();                    % Serial: the next is 2, as before
            testCase.verifyEqual(t.active_variant_values().Frequency, 2000);
        end

        function activeVariantValuesIsEmptyWithoutVariants(testCase)
            t = stimgen.Tone('Fs', 48000, 'ApplyCalibration', false, 'Duration', 0.01);
            t.update_signal();
            testCase.verifyEmpty(fieldnames(t.active_variant_values()));
        end

    end
end


% ====================================================================== %

function S = verify_round_trip_(testCase, obj, cls)
% Serialize, restore, serialize again; every field must survive unchanged.
S  = obj.toStruct();
o2 = stimgen.StimType.fromStruct(S);
testCase.verifyClass(o2, cls);
S2 = o2.toStruct();

testCase.verifyEqual(sort(fieldnames(S2)), sort(fieldnames(S)), ...
    sprintf('%s: serialized field set changed', cls));
fn = fieldnames(S);
for k = 1:numel(fn)
    if isfield(S2, fn{k})
        % isequaln: an unset calibration timestamp is NaT, and NaN-valued
        % defaults must compare equal to themselves.
        testCase.verifyTrue(isequaln(S.(fn{k}), S2.(fn{k})), ...
            sprintf('%s: field "%s" did not survive toStruct/fromStruct', cls, fn{k}));
    end
end
end


function [freq, level] = combination_table_(t)
% Walk every combination by index and read it back without advancing.
n = t.get_variant_info().NumCombinations;
freq  = zeros(1, n);
level = zeros(1, n);
for i = 1:n
    t.set_variant_index(i);
    v = t.active_variant_values();
    freq(i)  = v.Frequency;
    level(i) = v.SoundLevel;
end
end
