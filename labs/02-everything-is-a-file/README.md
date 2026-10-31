# 02 · Everything in Linux is a file

> **Runs on:** Docker only · **Time:** 5 minutes · **Blog:** [chapter 2](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#2-everything-in-linux-is-a-file)
>
> **You'll learn:** that the kernel shows its live information as files that aren't stored anywhere.

## The question

How can a file with nothing in it tell you how much memory the machine has?

## Predict first

<details>
<summary><code>ls -l</code> says <code>/proc/meminfo</code> is 0 bytes. What will <code>cat</code> show?</summary>

The machine's memory, in detail. The file isn't stored on disk. The kernel writes the answer at the moment you read it.
</details>

## Steps

Start a small Linux container. We'll use the same one, with the same flags, in labs 02 to 05:

```bash
docker run -d --name lab-box --cpus=0.5 --memory=128m ubuntu sleep infinity
```

A normal file, and a device that throws away anything you write to it:

```bash
docker exec lab-box cat /etc/hostname
docker exec lab-box sh -c 'echo "gone" > /dev/null; echo "wrote to /dev/null"'
```

Now a kernel file. Check its size, then read it:

```bash
docker exec lab-box ls -l /proc/meminfo
docker exec lab-box head -3 /proc/meminfo
```

```text
-r--r--r-- 1 root root 0 Oct 30 11:06 /proc/meminfo
MemTotal:        8126480 kB
MemFree:         3512900 kB
MemAvailable:    6465152 kB
```

Run the `head` line again: the numbers change slightly. Nothing was stored; the kernel worked them out when you asked.

## What happened

`/proc` and `/sys` are **virtual filesystems**. Reading a file there asks the kernel a question; writing one changes a live setting. Tools like `free` and `top` just read these files and format them.

> **In one line:** the kernel shows its information and settings as files. Read a file to ask, write one to change.

Check your work: `make check LAB=02`

## Clean up

```bash
docker rm -f lab-box
```

**Next:** [lab 03 · /proc](../03-proc/)
