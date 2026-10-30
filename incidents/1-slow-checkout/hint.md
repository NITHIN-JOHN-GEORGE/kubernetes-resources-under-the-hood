Hint for incident 1

- The average CPU is under the limit. But the limit isn't an average: it's a budget per 100 ms period.
- How many processes does one request use at the same time? How fast would they spend 20 ms together?
- Look at nr_throttled in cpu.stat, or the "throttled" line in ./scripts/watch.sh checkout-api.
