## Clue 1

A dashboard that samples every 15 seconds sees only 4 moments a minute. The kernel checks
`memory.max` on every single allocation. What could happen between two samples?

## Clue 2

The log shows what the worker does every 20 seconds. Which step is it in when it dies?
How much memory might that step need, on top of the cache?

## Clue 3

`memory.peak` is the highest `memory.current` the pod's cgroup has ever reached. If it equals
`memory.max`, something hit the ceiling, however briefly.
