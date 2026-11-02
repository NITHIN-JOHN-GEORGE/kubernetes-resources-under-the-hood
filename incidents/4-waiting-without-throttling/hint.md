## Clue 1

Start with the three numbers side by side: `nr_throttled` in the controller's `cpu.stat`, the
`some` line of its `cpu.pressure`, and the `some` line of the node's `/proc/pressure/cpu`.
If the controller is **waiting** but **not throttled**, its own limit isn't what stops it. What else
can keep a ready thread from running?

## Clue 2

Compare the batch jobs' CPU **limits** with the number of CPUs on the node. A limit bigger than
the node never empties its wallet. What does that mean for how much CPU each job can grab?

## Clue 3

Now look at their **requests**. The scheduler only adds up requests when it places pods. With
requests this small, how many busy threads can end up on one node, and where does the
controller's thread wait when every core is busy?
