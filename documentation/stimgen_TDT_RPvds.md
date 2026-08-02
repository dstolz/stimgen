# TDT / RPvds Hardware Integration

`stimgen` itself has no dependency on TDT hardware or RPvds — all hardware coupling goes through
the host-supplied `stimgen.HardwareHost` and `stimgen.calibration.HwAdapter` classes (see
[stimgen_overview.md](stimgen_overview.md)). This page documents the specific RPvds circuit
contract that a host application's hardware circuit must satisfy for `StimPlayer` to drive
hardware-triggered playback, and the legacy TDT-era file types that predate `stimgen`'s current
save/load paths.

## RPvds circuit parameter contract

Hardware playback assumes the host exposes the parameter names expected by the stimgen RPvds
circuit template (`StimGenCircuit.rcx`):

- `BufferData_0`, `BufferData_1` — audio data buffers
- `BufferSize_0`, `BufferSize_1` — buffer length in samples
- `x_Trigger_0`, `x_Trigger_1` — playback trigger pulses

`StimPlayer` resolves these names from the host at Run time and disables hardware playback if any
are missing, falling back to speaker preview; the GUIs still open, but only speaker preview is
available. See [stimgen_StimPlayer.md](stimgen_StimPlayer.md) for how this fallback surfaces in
the player GUI.

## Legacy TDT file types

- `.eprot` — host protocol files, loaded only through `HardwareHost.loadProtocol`. These describe
  the RPvds circuit and connection details a host needs to reach TDT hardware.
- `StimGen.prot` / `StimGen.ecfg` — assets from earlier tooling generations. They deserialize into
  host-specific objects and are not used by current `stimgen` save/load paths, which revolve
  around `.esgc` and `.spl`.

## Related files

- [+stimgen/@StimPlayer/StimPlayer.m](../../+stimgen/@StimPlayer/StimPlayer.m)
- [stimgen_StimPlayer.md](stimgen_StimPlayer.md)
- [stimgen_overview.md](stimgen_overview.md)
