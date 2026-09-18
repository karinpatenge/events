# Scenario 1 explained: Credential Theft

## Steps

### Step 1 — Shape Verification

Checks the confirmed REDTEAM ground truth before trusting any heuristic: does a stolen identity really authenticate to *many* computers in a burst? No — confirmed compromises touch at most 2 computers. This rules out fan-out and points the whole analysis toward **persistence** instead.

### Step 2 — Authentication Baseline

Establishes how many distinct computers each user normally authenticates to across the full 58-day window — the "normal" reference point later steps compare candidates against.

### Step 3 — Persistence Detection

Flags users with a sustained, repeated relationship to a secondary (non-primary) computer. Two detection variants are kept side by side — a per-user ratio and an absolute event-count band — plus a diagnostic (3a) that tested, and ruled out, one theory for why known compromises weren't being caught.

### Step 4 — Precision Check

Measures how many persistence candidates are already confirmed fraud versus unlabeled. Result: 3 confirmed out of 69,648 candidates — real signal, but far too many to review one by one.

### Step 5 — Evidence Trail

For a specific candidate, pulls its authentication details, processes, and network flows over its own detected time window to build a fraud "fingerprint." Applied to a live candidate, this surfaced a disproportionate SMB data transfer to a secondary computer.

### Step 6 — Structural Ranking

Ranks candidates by PageRank (business impact) and by how many other users share the same target computer, so likely-targeted relationships sort ahead of shared-infrastructure noise — giving Step 5 a defensible starting order.

## Findings

### Finding 1 — Persistence, Not Fan-Out

Confirmed compromises don't fan out to many computers — they persist on one, for weeks. This overturned the scenario's original hypothesis and reset the whole detection approach around persistence instead of burst activity. That holds at the identity level specifically — one of these same target computers, C17693, turns out to be a major fan-out hub when measured host-to-host instead (Scenario 2's lens); see Finding 3.

### Finding 2 — Compromises Hide in the Middle

On both event volume (215–573 events) and target importance (PageRank at or below average), confirmed compromises sit in the unremarkable middle, not at either extreme. Sorting candidates by "most events" or "most important target" actually points away from them. Scenario 2 found the identical pattern independently, on a completely different axis: host-to-host connectivity volume also fails to separate its confirmed cases from ordinary infrastructure, even after six different attempts to fix it.

### Finding 3 — Real Signal, Huge Haystack

69,648 candidate relationships match the persistence pattern; only 3 are confirmed so far. Much of that volume comes from a handful of shared-infrastructure computers (one touched by 190+ different users), not from genuinely distinct relationships. Those 3 confirmed cases aren't a uniform group either: cross-checking them against Scenario 2's host-level view showed only C17693 is also a major pivot point (296 victims reached as a staging host); C19932 and C22409 stay small, contained footholds with no comparable onward reach. The full picture only emerges by combining both scenarios' lenses.
