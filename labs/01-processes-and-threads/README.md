# 01 · Processes and threads

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 1](https://nithin-john-george.github.io/blog/cgroups-deep-dive-kubernetes/#1-what-happens-when-you-run-a-program)
>
> **You'll learn:** what a process and a thread are, and why "one core runs one thread at a time" matters for everything later.

## The question

When you start a program, what actually starts? And what does the CPU run?

## Predict first

<details>
<summary>The <code>serve</code> program below starts with <code>--workers 4</code>. How many processes will you see, and how many threads?</summary>

At least five processes: the server itself plus its four worker processes. The server also runs a few threads of its own. Each worker is a process, and every process has at least one thread. The CPU runs threads, not "programs".
</details>

## Steps

This lab uses the `lab-tools` image. Build it once (about a minute):

```bash
make image
```

Start a small web service in a container. It runs one main process and four worker processes:

```bash
docker run -d --name lab-box lab-tools:1.0 serve --workers 4
sleep 2
```

List every process, and every thread inside each process. `PID` is the process, `LWP` is the thread ("light-weight process"), `NLWP` is how many threads that process has:

```bash
docker exec lab-box ps -eLo pid,lwp,nlwp,comm
```

The kernel keeps one folder per thread under `/proc/<pid>/task`. Look at the main process, PID 1:

```bash
docker exec lab-box ls /proc/1/task
```

And how many CPUs can this container use?

```bash
docker exec lab-box nproc
```

## What happened

- Every program you start becomes a **process** with its own **PID**. Inside a container, the first one is PID 1.
- A process can split its work into **threads**. They show up as extra `LWP` numbers under one PID, and as extra folders in `/proc/<pid>/task`.
- `nproc` is the number of CPU cores. Each core runs **one thread at a time**; the kernel's scheduler switches between them thousands of times a second.

Keep this in mind: later, a CPU limit is shared by *all* the threads in a container.

> **In one line:** programs run as processes, processes run as threads, and each CPU core runs one thread at a time.

Check your work: `make check LAB=01`

## Clean up

```bash
docker rm -f lab-box
```

**Next:** [lab 02 · Everything is a file](../02-everything-is-a-file/)
