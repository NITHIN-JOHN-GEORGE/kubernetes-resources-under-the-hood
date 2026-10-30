# Incidents: debug it yourself

The labs show you each mechanism. These incidents give you a broken situation and a ticket, like an on-call page, and leave the digging to you. Every clue is in a file you met in the labs.

| # | Ticket | Labs that help |
|---|--------|----------------|
| [1](1-slow-checkout/) | "Checkout is slow, but the CPU graph is under its limit" | 14, 15 |
| [3](3-oom-at-half/) | "OOMKilled, but the dashboard never went above half" | 16, 17 |
| [4](4-pending-with-free-memory/) | "Pending for ages, the node's memory is almost empty" | 09, 18 |

(Incidents 2, "the restart loop", and 5, "Go on a big node", are coming in the next version of the lab.)

## How to play

Each incident runs like a short on-call shift. Take your time between the steps.

```sh
make incident-1                      # 1. the scene  2. what the dashboard shows  3. the ticket
                                     #    (it pauses between steps: press Enter to go on)

# Now investigate yourself, using the numbered things to look at that it prints.

make hint-1                          # stuck? one clue at a time; run it again for the next
make answer-1 CAUSE=<your answer>    # one or two words. Then: the evidence, why it happened,
                                     # the fix applied live, and one line to remember
make answer-1 CAUSE=show             # or skip straight to the answer
make reset                           # clean up
```

Each incident folder has the ticket (`ticket.md`), the pods it starts, the script that starts them (`start.sh`), a hint and the answer. Every pod carries a `what` annotation that says what it does:

```sh
kubectl get pods -l incident -o custom-columns=NAME:.metadata.name,WHAT:.metadata.annotations.what
```
