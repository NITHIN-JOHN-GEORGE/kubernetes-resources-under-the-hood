# The ticket

> "Checkout takes almost a second. The target is under 100 ms. The CPU graph shows the pod well under its limit, so it can't be CPU. Right?"

**Your job:** find out why each request is so slow.

Start it with `make incident-1`. When you know the cause, `make answer-1 CAUSE=<one or two words>`. Stuck? `make hint-1`.
