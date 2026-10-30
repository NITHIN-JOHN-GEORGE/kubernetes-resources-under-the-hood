Hint for incident 2

- A dashboard that samples every 15 seconds only sees 4 moments a minute. What happens between samples?
- What was the container doing just before it died? (kubectl logs --previous)
- memory.peak records the highest memory.current the cgroup has ever reached. Compare it with memory.max.
