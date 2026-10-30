#!/usr/bin/env bash
# Live view of a pod's cgroup files, refreshed every second. Press Ctrl-C to stop.
#
#   ./scripts/watch.sh <pod> [namespace]          watch a pod (default namespace: lab)
#   ./scripts/watch.sh --cgroup /sys/fs/cgroup/x   watch any cgroup folder on the node
#
# Every line says which file it comes from, so you can cat that file yourself.
set -u
NODE=under-the-hood-worker

if [ "${1:-}" = "--cgroup" ]; then
  DIR="$2"; NAME="$2"
else
  NAME="${1:?usage: $0 <pod> [namespace]}"
  DIR="$("$(dirname "$0")/pod-cgroup.sh" "$NAME" "${2:-lab}")"
fi
[ -n "$DIR" ] || { echo "could not find the cgroup for $NAME"; exit 1; }

# Read all the files we need in one go, each under a "== file" header.
read_all() {
  docker exec "$NODE" sh -c "cd $DIR && echo \"== now\"; date +%s%N; for f in cpu.max cpu.stat memory.current memory.max memory.stat memory.events cpu.pressure memory.pressure; do echo \"== \$f\"; cat \$f 2>/dev/null; done"
}
# get <file> [key]: the whole file, or the value of one key in it
get() { echo "$OUT" | awk -v f="$1" -v k="${2:-}" '$1=="=="{s=($2==f); next} s{ if (k=="") print; else if ($1==k) print $2 }'; }
mib() { [ "$1" = "max" ] && echo "no limit" || echo "$(( $1 / 1048576 )) MiB"; }

prev_use=""; prev_per=""; prev_thr=""; prev_now=""
while :; do
  OUT="$(read_all)"
  now=$(( $(get now) / 1000 ))   # node clock in microseconds
  use=$(get cpu.stat usage_usec); per=$(get cpu.stat nr_periods); thr=$(get cpu.stat nr_throttled)
  read -r quota period <<<"$(get cpu.max)"
  cur=$(get memory.current); max=$(get memory.max)
  anon=$(get memory.stat anon); file=$(get memory.stat file); inact=$(get memory.stat inactive_file)

  clear
  echo "watching $NAME   (Ctrl-C to stop)"
  echo "cgroup: ${DIR#/sys/fs/cgroup/}" | cut -c1-110
  echo
  echo "CPU"
  if [ "$quota" = "max" ]; then echo "  limit        no limit                         (cpu.max: max $period)"
  else echo "  limit        $(( quota * 1000 / period ))m                             (cpu.max: $quota $period)"; fi
  if [ -n "$prev_use" ]; then
    echo "  used         $(( (use - prev_use) * 1000 / (now - prev_now) ))m in the last second           (cpu.stat: usage_usec)"
    echo "  throttled    $(( thr - prev_thr )) of $(( per - prev_per )) periods in the last second   (cpu.stat: nr_throttled / nr_periods)"
  else
    echo "  used         measuring..."
  fi
  echo
  echo "MEMORY"
  echo "  in use       $(mib "$cur") of $(mib "$max")              (memory.current / memory.max)"
  echo "  anon         $(mib "$anon")   programs' own memory     (memory.stat: anon)"
  echo "  file cache   $(mib "$file")   can be dropped           (memory.stat: file)"
  echo "  working set  $(mib $(( cur - inact )))                         (memory.current - inactive_file)"
  echo "  events       max $(get memory.events max) · oom $(get memory.events oom) · oom_kill $(get memory.events oom_kill)     (memory.events)"
  echo
  echo "PRESSURE (share of time something waited, last 10 s)"
  echo "  cpu          $(get cpu.pressure some | tr ' ' '\n' | grep avg10 | cut -d= -f2)%       (cpu.pressure: some avg10)"
  echo "  memory       $(get memory.pressure some | tr ' ' '\n' | grep avg10 | cut -d= -f2)%       (memory.pressure: some avg10)"

  prev_now=$now; prev_use=$use; prev_per=$per; prev_thr=$thr
  sleep 1
done
