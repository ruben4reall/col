# Benchmark

**Col 3.0.0, 16 November 2026**, 14-inch MacBook Pro (M3 Pro), macOS 27.2.1, one minute after launch, nothing
playing: Col 23 MB and its music helper 3.9 MB of memory footprint, 0 % of the processor (`scripts/bench.sh`). The
tables below were measured with Col 2.0 on macOS 26.5.

Idle memory footprint and CPU of Col on a 14-inch MacBook Pro (M3 Pro, macOS 26.5), Release build, measured with
`footprint` and the kernel's CPU time counters (`proc_pid_rusage`) over 60 seconds without interaction, 20 seconds
after launch. Helper processes count.

| State | Col | Media helper | CPU |
|---|---|---|---|
| Closed, nothing playing, every feature on | 11 MB | 3.7 MB | 0.004 % |
| Same, while you use the Mac (clipboard checked every 2 s) | 11 MB | 3.7 MB | 0.013 % |
| Open, music playing | 16 MB | 4.5 MB | 0.1 % |

The pasteboard has no change notification, so clipboard history reads one counter every 2 seconds while the Mac is in
use, every 8 seconds after 30 seconds without input and every 30 seconds after 5 minutes. Without clipboard history,
Col wakes about once every 20 seconds.

Other notch apps, measured the same way on the same Mac in September 2026:

| App | Memory at rest | CPU at rest |
|---|---|---|
| Notch app A | 56 MB (49 + 6.7 helper) | 0.01 % |
| Notch app B | 71 MB | 3.9 % |
| Notch app C | 106 MB (peak 203) | 6.8 % |

To reproduce: `scripts/bench.sh <pid> [seconds]`.
