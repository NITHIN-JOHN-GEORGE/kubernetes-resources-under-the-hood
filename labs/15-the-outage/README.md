# 15 · The outage

> **Runs on:** the kind cluster (`make cluster`) · **Time:** 15 minutes · **Blog:** [chapter 15](https://nithinjohngeorge.com/blog/cgroups-deep-dive-kubernetes/#15-the-outage-explained)
>
> **You'll learn:** how throttling, with CPU usage that looks fine, turns into failed health probes, restarts and pods dropping out of a Service. The blog's outage, scaled down to a laptop.

## The question

How can pods that aren't using much CPU on average keep failing their health checks?

## Predict first

<details>
<summary>The load is only about 6 requests a second for 3 pods, but it arrives in bursts of 12. Will the pods stay healthy?</summary>

No. Each burst lands at once, and with a 500m limit the pods spend their budget in a few milliseconds and then wait. Requests queue behind each other, <code>/healthz</code> waits behind them for a free request thread, and the probes time out. Pods drop out of the Service (readiness) and get restarted (liveness).
</details>

## Steps

The service: 3 replicas, 4 request threads each, 200 ms of CPU per request fanned out to 4 workers, a **500m CPU request and limit**, and liveness and readiness probes every 3 seconds with a 1 second timeout (open `deployment.yaml` to see them):

```bash
kubectl apply -f labs/15-the-outage/deployment.yaml -f labs/15-the-outage/service.yaml
kubectl rollout status deployment/serve --timeout=120s
```

Now the bursty client: 12 requests at once, every 2 seconds:

```bash
kubectl apply -f labs/15-the-outage/load.yaml
sleep 90
kubectl logs load --tail=5
kubectl get pods -l app=serve
```

```text
burst of 12: 12 ok, 0 failed, slowest 5413 ms
burst of 12: 12 ok, 0 failed, slowest 6526 ms
burst of 12: 9 ok, 3 failed, slowest 1992 ms
NAME                     READY   STATUS    RESTARTS      AGE
serve-5dffd9f84f-8d29h   0/1     Running   3 (1s ago)    94s
serve-5dffd9f84f-jf5bb   0/1     Running   3 (19s ago)   94s
serve-5dffd9f84f-m6r74   1/1     Running   2 (10s ago)   94s
```

That's my run: requests taking up to 6.5 seconds, some failing, every pod restarted two or three times, and two of three pods out of the Service. The events say why:

```bash
kubectl get events --field-selector reason=Unhealthy --sort-by=.lastTimestamp -o custom-columns=POD:.involvedObject.name,MESSAGE:.message | tail -6
```

`Liveness probe failed` and `Readiness probe failed`, with `context deadline exceeded`: the probe got no answer within 1 second.

**What the dashboard shows.** Measure one pod's average CPU over 10 seconds, the way a CPU graph would. The whole measurement runs on the node, so the timing is exact:

```bash
P=$(kubectl get pod -l app=serve -o jsonpath='{.items[0].metadata.name}')
D=$(./scripts/pod-cgroup.sh $P)
docker exec under-the-hood-worker sh -c "a=\$(awk '/^usage_usec/{print \$2}' $D/cpu.stat); sleep 10; b=\$(awk '/^usage_usec/{print \$2}' $D/cpu.stat); echo average CPU over 10 s: \$(( (b - a) / 10000 ))m, request 500m"
```

```text
average CPU over 10 s: 384m, request 500m
```

77% of its request on my run: on a dashboard comparing usage with requests, nothing looks wrong. That's the trap from the blog's intro, where the service sat below 80% of its request.

**What the kernel recorded.** We read the **pod's** `cpu.stat` from the node, because a container's counters start again from zero every time it restarts:

```bash
docker exec under-the-hood-worker grep -E 'nr_periods|nr_throttled' "$D/cpu.stat"
```

```text
nr_periods 843
nr_throttled 790
```

Throttled in 790 of 843 periods, 94%, while the average said 77% of the request. (`./scripts/watch.sh $P` shows it live.)

**The fix the team used: a bigger limit.** Raise it from 500m to 2 CPUs and watch the restarts stop. On my run, after the change: 0 restarts, and the slowest request in a burst dropped to about 0.5 seconds.

```bash
kubectl set resources deployment/serve --limits=cpu=2,memory=128Mi
kubectl rollout status deployment/serve --timeout=120s
sleep 60
kubectl get pods -l app=serve
kubectl logs load --tail=3
```

## What happened

1. **A burst empties the wallet.** Four workers on four CPUs spend 50 ms of budget in about 12 ms, then the whole container waits for the next 100 ms period.
2. **CPU time turns into much longer real time.** A request that needs 200 ms of CPU takes 400 ms or more, so requests from a burst pile up behind each other.
3. **The probe waits too.** `/healthz` needs almost no CPU, but it waits for a free request thread, inside the same throttled cgroup.
4. **Readiness** failures pull the pod out of the Service, so the others get bigger bursts. **Liveness** failures restart the container, and a restart drops everything in flight.

Averaged over time, each pod uses less CPU than it requested, so a dashboard comparing usage with requests says everything is fine. The throttle ratio, `nr_throttled / nr_periods`, is what gives it away: most periods end with the budget used up.

> **In one line:** throttling hides behind averages, freezes your probes along with everything else, and comes from bursts, not average usage.

Check your work: `make check LAB=15`

## Clean up

```bash
kubectl delete -f labs/15-the-outage/ --ignore-not-found
```

**Next:** [lab 16 · Memory limits and the OOM killer](../16-memory-limits-and-oom/)
