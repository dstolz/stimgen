classdef LoggingTest < matlab.unittest.TestCase
    % stimgen.util.vprintf delivered through a host sink (stimgen.FcnLogSink):
    % the message arrives raw, the red flag is parsed, the sink's own gate is
    % honoured, and uninstalling restores whatever was there before.
    %
    % Run from the repository root:
    %   addpath(pwd); results = runtests('tests');
    % See tests/README.md.

    properties
        Log   % containers.Map (a handle) the sink appends records to
    end

    methods (TestClassSetup)
        function addPackageRoot(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(root));
        end
    end

    methods (TestMethodSetup)
        function installCapturingSink(testCase)
            previous = stimgen.util.logSink();
            testCase.addTeardown(@() stimgen.util.logSink(previous));

            testCase.Log = containers.Map('KeyType', 'double', 'ValueType', 'any');
            records = testCase.Log;
            % Gate: deliver levels up to 2 only, independent of GVerbosity.
            sink = stimgen.FcnLogSink(@(level, red, msg, args) append_(records, level, red, msg, args), ...
                @(level) level <= 2);
            stimgen.util.logSink(sink);
        end
    end

    % ------------------------------------------------------------------ %
    methods (Test)

        function sinkIsInstalled(testCase)
            testCase.verifyClass(stimgen.util.logSink(), 'stimgen.FcnLogSink');
        end

        function formattedMessageArrivesRaw(testCase)
            stimgen.util.vprintf(1, 'value %d of %s', 5, 'five');
            testCase.verifyEqual(double(testCase.Log.Count), 1);
            r = testCase.Log(1);
            testCase.verifyEqual(r.level, 1);
            testCase.verifyFalse(r.red);
            % Forwarded unexpanded: the format and its values separately.
            testCase.verifyEqual(r.msg, 'value %d of %s');
            testCase.verifyEqual(r.args, {5, 'five'});
        end

        function redFlagAndLiteralText(testCase)
            % With no values the message is literal text: a Windows path and
            % a percent sign must survive.
            literal = 'C:\new\data.mat at 100%';
            stimgen.util.vprintf(0, 1, literal);
            testCase.verifyEqual(double(testCase.Log.Count), 1);
            r = testCase.Log(1);
            testCase.verifyEqual(r.level, 0);
            testCase.verifyTrue(r.red);
            testCase.verifyEqual(r.msg, literal);
            testCase.verifyEmpty(r.args);
        end

        function stringMessageIsNotReadAsRedFlag(testCase)
            stimgen.util.vprintf(1, "a string message");
            r = testCase.Log(1);
            testCase.verifyFalse(r.red);
            testCase.verifyEqual(string(r.msg), "a string message");
        end

        function exceptionIsForwardedUnexpanded(testCase)
            ME = MException('stimgen:Test:Example', 'something failed');
            stimgen.util.vprintf(0, 1, ME);
            r = testCase.Log(1);
            testCase.verifyClass(r.msg, 'MException');
            testCase.verifyEqual(r.msg.identifier, 'stimgen:Test:Example');
        end

        function sinkGateSuppresses(testCase)
            stimgen.util.vprintf(3, 'verbose detail %d', 1);
            stimgen.util.vprintf(4, 'trace detail');
            testCase.verifyEqual(double(testCase.Log.Count), 0);
            stimgen.util.vprintf(2, 'debug detail');
            testCase.verifyEqual(double(testCase.Log.Count), 1);
        end

        function uninstallReturnsToBuiltInLogger(testCase)
            stimgen.util.logSink([]);
            testCase.verifyEmpty(stimgen.util.logSink());
            stimgen.util.vprintf(-1, 'goes to the built-in log file only');
            testCase.verifyEqual(double(testCase.Log.Count), 0);
        end

        function rejectsANonSink(testCase)
            testCase.verifyError(@() stimgen.util.logSink(42), ...
                'stimgen:logSink:InvalidSink');
        end

    end
end


% ====================================================================== %

function append_(records, level, red, msg, args)
% The sink callback: one record per message, keyed in arrival order.
% records is a containers.Map, a handle, so the caller sees the addition.
records(records.Count + 1) = struct('level', level, 'red', red, 'msg', {msg}, 'args', {args}); %#ok<NASGU>
end
