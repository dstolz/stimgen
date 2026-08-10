# Logging

`stimgen.util.vprintf` is the only logging entry point in the package. It is
verbosity-gated, it never throws, and it works with or without a host
application.

```matlab
global GVerbosity
GVerbosity = 2;

stimgen.util.vprintf(1,'loaded %d stimuli',n)
stimgen.util.vprintf(0,1,'calibration aborted: %s',reason)   % red
stimgen.util.vprintf(0,1,ME)                                  % an exception
```

## Levels

| Level | Meaning |
|---|---|
| `-1` | write to the log, but do not print to the screen |
| `0` | critical |
| `1` | info (default `GVerbosity`) |
| `2` | debug |
| `3` | verbose |
| `4` | trace — per-buffer / per-trial detail |

A message is emitted when `level <= GVerbosity`. `GVerbosity` that is empty,
non-numeric, non-scalar, `NaN` or `Inf` is repaired to `1`;
`stimgen.util.verbosityGate` is the only place the global is read.

## Format policy

**With values** the message is a `printf` format string. **With no values it is
literal text** — nothing is interpreted, so a runtime-built string survives:

```matlab
stimgen.util.vprintf(1,'wrote %s',p)     % format string
stimgen.util.vprintf(1,ME.message)       % literal: '%' and '\' survive
```

Never append `\n`; a trailing newline is stripped and the writer adds its own.

## Where messages go

By default stimgen prints to the command window and appends to a daily file
under `fullfile(tempdir,'stimgen_error_logs')`. That is the standalone case and
needs no configuration.

A host application that already has a logger would otherwise end up with two
files describing one session. To avoid that, a host implements
`stimgen.LogSink` and installs it:

```matlab
stimgen.util.logSink(myapp.LogBridge());   % install
stimgen.util.logSink()                     % query; [] when none
stimgen.util.logSink([])                   % uninstall
```

**While a sink is installed stimgen writes nothing of its own** — no console
line, no file under `tempdir`. Every message is forwarded instead.

For a quick capture, or a test, wrap a function handle:

```matlab
stimgen.util.logSink(stimgen.FcnLogSink(@(level,red,msg,args) disp(msg)));
```

## Implementing a sink

```matlab
classdef LogBridge < stimgen.LogSink
    methods
        function emit(~,level,red,msg,args)
            myapp.log(level,red,msg,args);
        end
    end
end
```

`emit` receives:

| arg | type | meaning |
|---|---|---|
| `level` | numeric scalar | as the call site passed it; already past the gate |
| `red` | logical scalar | a **flag** meaning "bad news", never a stream number |
| `msg` | raw | `char`, `string`, `MException`, or a struct with `.message` |
| `args` | `1xN` cell | format values; `{}` means `msg` is literal |

An implementation **must not throw**, must treat empty `args` as literal text,
must accept an `MException` as `msg`, and must treat `level < 0` as log-only.
It should attribute the record to the stimgen call site rather than to its own
adapter, and should return promptly — `StimPlayer.update_buffer` logs at level 4
from the buffer-write path.

A sink that throws anyway is caught: a note goes to stderr once and that message
falls through to the built-in logger. stimgen never goes mute because a host
misbehaved, and never latches logging off — latching is the host's job.

### Overriding the gate

`stimgen.LogSink.isEnabled(level)` is **concrete**, defaulting to the
`GVerbosity` gate. Override it when the host keeps verbosity somewhere else, or
to keep a single reader of the setting across both code bases:

```matlab
function tf = isEnabled(~,level)
    tf = myapp.isEnabled(level);
end
```

### Adding to the contract later

New `LogSink` methods must be **concrete, with a safe default**, exactly as with
`stimgen.HardwareHost.sampleRate` and `stimgen.calibration.HwAdapter.record`.
Adding a method as `Abstract` makes every existing host's subclass
unconstructable, and the failure surfaces as silent logging loss.

## Guarding expensive arguments

`vprintf` returns before doing any work when a level is suppressed, but it
cannot stop the caller building what it was about to pass:

```matlab
if stimgen.util.isEnabled(4)
    stimgen.util.vprintf(4,'buffer: %s',mat2str(obj.read_buffer()));
end
```

Only worth it for genuinely expensive arguments — the guard costs more than it
saves otherwise.

## Files

| File | Role |
|---|---|
| `+util/vprintf.m` | the front door: gate, parse, forward or fall back |
| `+util/isEnabled.m` | the gate, delegated to the sink when one is installed |
| `+util/verbosityGate.m` | the built-in gate; the only reader of `GVerbosity` |
| `+util/logSink.m` | the sink registry (install / query / uninstall) |
| `+util/vprintfFallback.m` | the built-in console + daily-file logger |
| `LogSink.m` | the abstract host contract |
| `FcnLogSink.m` | a `LogSink` wrapping a function handle |

## Notes

- The registry lives in a `persistent`, so `clear functions` uninstalls the
  sink and stimgen reverts to its own log. A host re-installs from its startup
  routine; doing so is cheap and idempotent.
- Only one sink is installed at a time. Two applications driving stimgen in one
  MATLAB session would contend for the slot.
- Exceptions are forwarded unexpanded. The built-in logger renders one
  multi-line block per exception (identifier, stack, nested causes), not one
  record per frame.
