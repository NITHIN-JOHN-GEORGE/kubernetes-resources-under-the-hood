## Clue 1

The scheduler never looks at how much memory is **in use**. When it decides whether a pod
fits on a node, what number does it compare instead?

## Clue 2

"Allocated resources" in `kubectl describe node` shows what has been **promised** to pods
(their requests), not what they use. How much of the node is promised?

## Clue 3

Who was promised most of the node, and are they using it right now?
