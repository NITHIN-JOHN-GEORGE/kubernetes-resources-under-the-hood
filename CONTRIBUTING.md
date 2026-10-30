# Contributing

Thanks for helping. A few rules keep the labs trustworthy.

## Adding or changing a lab

- **One lab = one blog chapter**, with the same number. Extras are `E<n>`.
- **The README is the lab.** Follow the rhythm: question → predict first → steps → what happened → in one line → check → clean up → next.
- **Readers type only real tools:** `kubectl`, `docker`, `cat` (and small helpers in `scripts/`). Put pods in YAML next to the README; use the `lab-tools` image and a `what` annotation on every pod.
- **Code blocks matter.** ` ```bash ` blocks are run, in order, by `make test LAB=N`. Use ` ```sh ` for commands that shouldn't run in tests (interactive ones, like `./scripts/watch.sh`) and ` ```text ` for output. Blocks under `## Clean up` run after the check.
- **Outputs come from real runs.** Run `make test LAB=N`; it saves everything to `labs/N-*/expected.txt`. Copy output into the README from there, never by hand.
- **`check.sh` only reads.** It never creates or deletes anything. Source `lib/common.sh` and use `pass`, `fail` and `finish`.
- A lab that needs a cluster profile or add-on says so in its first line, and `run-lab.sh` reads `PROFILE=<name>` from there.

## Before you open a pull request

```bash
shellcheck -S warning lib/*.sh scripts/*.sh labs/*/check.sh incidents/*/*.sh
make test LAB=<the lab you changed>
```

If a check fails on your machine, open an issue with the output of `make check-setup` and `make test LAB=N`.
