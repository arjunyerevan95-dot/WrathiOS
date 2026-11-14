# WRATH v22 diagnostic memory cutoff

This is a practical instrumented test, not a verified fix for the underlying allocation growth. v21 jetsam recorded LiveContainer at roughly6.4-6.6GiB and killed SpringBoard/backboardd under memory pressure.

Zink only: before loading Mesa, open a bounded numeric diagnostic file, validate physical-footprint telemetry, start a serial background20ms sampler, and publish current/peak footprint and available app memory to atomics. A separate250ms logger writes these values and stage; it cannot block the sampler. No filesystem work precedes the cutoff exit, so the last written sample may precede the breach. At footprint>=1536MiB, remaining headroom<512MiB, or failed task_info, terminate the host using _Exit(78). A deliberate exit is expected if the threshold trips. No configuration or save files are written. Abrupt termination does not gracefully save a running game, so first test must be startup only. GLES rollback does not include this mechanism.

Stage numbers:0 predriver,1 driver loading/symbols,2 before context,3 after context creation,4 presenter/context ready,5 presentation begun. Diagnostic file: Application Support/WrathiOS/Runtime/zink-memory.json. This contains numeric metrics only, no assets or private paths.

Scene reduced from2x to1x UIKit points, quartering per-pixel surfaces. This may change visual quality; it does not identify or prove removal of the leak. Full device runtime still unverified.

Residual risk: sampling is not an allocator-enforced cap; one huge driver allocation or scheduler stall can outrun the sampler. The process-wide metric intentionally includes engine, driver and LiveContainer. A threshold trip exits LiveContainer, not just a guest thread. User must know this before a single controlled test. Do not repeatedly relaunch after a cutoff or system reset.

Host boundary tests cover limit equality, one byte below, headroom equality, one byte below and unavailable telemetry. Existing backend symbol gates, native controls tests and GLES rollback remain mandatory.

