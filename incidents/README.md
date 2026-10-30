# Incidents: debug it yourself

The modules show you each mechanism. These incidents give you a broken situation and a ticket,
like an on-call page, and leave the digging to you. Every clue you need is in a file you met in
the modules.

| # | Ticket | What you'll use |
|---|--------|-----------------|
| 1 | "Checkout is slow, but the CPU graph is under its limit" | `cpu.stat`, `cpu.max` (chapter 7) |
| 2 | "OOMKilled, but the dashboard never went above half" | `memory.peak`, `memory.events` (chapters 8 and 9) |
| 3 | "Pending for ages, the node's memory is almost empty" | `kubectl describe node`, requests (chapters 4 and 10) |

## How to play

```bash
make incident-1                      # starts the broken pods and prints the ticket
make watch POD=checkout-api          # optional: watch its cgroup files live in a second terminal
make hint-1                          # a nudge, if you're stuck
make answer-1 CAUSE=<your answer>    # one or two words; it checks you, then explains and shows the fix
make answer-1 CAUSE=show             # skip straight to the answer
make incident-clean                  # delete the incident pods
```

Each incident is a folder with four small files: the pods it starts (`pod.yaml`), the script that
starts them (`start.sh`), a hint (`hint.md`) and the answer (`answer.sh`). Open them if you want
to see exactly what's running. Every pod also carries a `what` annotation that says what it does:

```bash
kubectl -n lab get pods -l incident -o custom-columns=NAME:.metadata.name,WHAT:.metadata.annotations.what
```
