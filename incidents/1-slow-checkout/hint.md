## Clue 1

The average CPU is under the limit. But the limit isn't an average: `cpu.max` is a budget of
CPU time **per 100 ms period**. What is the budget here, in milliseconds?

## Clue 2

One request uses 4 processes **at the same time**. If 4 processes share a 20 ms budget,
how long does it take them to spend it? And what happens for the rest of the period?

## Clue 3

In `cpu.stat`, compare how fast `nr_throttled` grows with `nr_periods`. If they grow almost
together, the pod hits its budget in almost every period.
