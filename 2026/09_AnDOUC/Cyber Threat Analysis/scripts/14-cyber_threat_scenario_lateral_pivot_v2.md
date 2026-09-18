# Scenario 2: Lateral Pivot / Broad Concentrated-Movement Triage

## Purpose

Find computers that contact several other computers in a concentrated one-hour window. The workflow is intentionally broad: a small concentrated movement is a valid triage candidate, but it is not automatically a confirmed beachhead.

`C17693` is the validated loud-beachhead reference. The final workflow uses it for calibration while keeping smaller, previously unknown candidates in scope.

## Workflow and final interpretation

### Step 1 — Calibrate the known beachhead shape

**Purpose:** Establish the real behavior of confirmed staging hosts before choosing a broad detection threshold.

**Expected outcome:** A reference profile showing victim volume, active time span, and hourly compromise concentration for known hosts.

Ground truth shows that `C17693` reached 296 victims and exceeded five compromised victims per hour in 30 of 69 active hours. `C19932` reached 8 victims and `C22409` reached 3; neither exceeded two compromised victims in one hour.

This establishes that the 5+ hourly threshold is meaningful for the loud reference, but it is not a complete classifier for smaller movements.

### Step 2 — Detect broad hourly bursts

**Purpose:** Find possible concentrated lateral movement in the full, mostly unlabeled cyber graph using `AUTH_CONNECTED` activity.

**Expected outcome:** Hourly host/bucket rows containing at least five distinct target computers, with confirmed REDTEAM status and overall host fan-out for context.

Search the full cyber graph for `AUTH_CONNECTED` edges from one computer to at least five distinct computers in one hour. The result includes both confirmed activity and ordinary infrastructure behavior.

In the final output, `C17693` had 525 overall `AUTH_CONNECTED` targets and peaked at 67 per hour. `C19932` and `C22409` each had 24 overall targets and peaked at 17 per hour, demonstrating that `AUTH_CONNECTED` is broader than the ground-truth `COMPROMISED` signal.

### Step 3 — Isolate new triage candidates

**Purpose:** Remove known staging hosts and confirmed buckets, then produce a manageable list of previously unknown hosts for investigation.

**Expected outcome:** One representative qualifying bucket per unknown host, including the host baseline and the number of recurring qualifying buckets.

Exclude known staging hosts and buckets containing confirmed REDTEAM activity. Return one representative bucket per unknown host and include `qualifying_bucket_count` to distinguish isolated from recurring activity.

The final run returned 500 unique hosts, all with 5–11 overall targets because the result is ordered toward the lowest-baseline hosts. Of these, 182 had one qualifying bucket and 318 had recurring qualifying buckets; 136 had at least 10 qualifying buckets and 55 had at least 25.

`C15758` was an isolated candidate with 5 overall targets and one qualifying bucket. `C5868` was a recurring comparison candidate with 6 overall targets and 23 qualifying buckets.

### Step 3a — Validate the detector against known hosts

**Purpose:** Check how the known staging hosts rank within the broad candidate population and expose the scale of background activity.

**Expected outcome:** Bucket-level burst and fan-out ranks that show whether the detector is narrowly specific or broadly noisy.

The diagnostic population contained 867,238 qualifying bucket rows. `C17693` peaked at 67 targets per hour and ranked 350 by burst volume; the 17-target peaks of `C19932` and `C22409` ranked 6,512.

These are bucket-level ranks, not unique-host ranks. The results confirm that many unlabeled bursts exist and that the detector should be used for triage rather than automatic attribution.

### Step 4 — Review identity context

**Purpose:** Identify successful or failed authentication activity associated with a selected candidate and its burst window.

**Expected outcome:** User or machine identities, authentication types, orientations, and statuses that help distinguish human-driven activity from routine system authentication.

Run with the final reviewed bindings:

```text
Primary:    :candidate_staging_host = 'C15758', :time_bucket = 302
Comparison: :candidate_staging_host = 'C5868',  :time_bucket = 160
```

`C15758` showed successful network logons and TGS activity from `C22621$`, `U3771`, and `U6448`, mostly using Kerberos with some NTLM. `C5868` showed recurring successful network logons from machine accounts including `C1065$`, `C529$`, `C586$`, `C612$`, `C457$`, and `C1640$`.

The mixed identity pattern around the isolated `C15758` burst is more interesting for triage. The recurring machine-only pattern around `C5868` is more consistent with automated infrastructure, although it should not be automatically discarded.

### Step 5 — Separate direct and two-hop reach

**Purpose:** Determine whether a small direct movement also provides broader graph reach, while avoiding self-loops and repeated-vertex paths.

**Expected outcome:** Counts for direct targets, two-hop-only targets, overlap, total reach, and the intermediate computers responsible for the expansion.

Run once for each candidate:

```text
:candidate_staging_host = 'C15758'
:candidate_staging_host = 'C5868'
```

The query excludes self-reach and repeated-vertex paths, then reports direct targets, two-hop-only targets, overlap, and intermediate computers.

Final results:

| Candidate | Direct | Two-hop only | Overlap | Total | Total/direct |
|---|---:|---:|---:|---:|---:|
| C15758 | 5 | 100 | 3 | 105 | 21.0x |
| C5868 | 6 | 99 | 6 | 105 | 17.5x |

Both candidates have the same total reach, so total 1–2 hop reach is largely a graph-topology signal. `C15758` expands mainly through `C457`, `C467`, and `C528`; all six direct targets of `C5868` participate in valid two-hop paths.

### Step 6 — Add PageRank context

**Purpose:** Estimate the structural importance of the candidate and reached computers in the full cyber graph.

**Expected outcome:** PageRank scores annotated with hop distance and reach class, helping prioritize potentially important assets while exposing hub-inflation effects.

Run with the same candidate bindings as Step 5. The query uses the cleaned reach set and reports `MIN_HOP` and `REACH_CLASS` with PageRank.

For `C15758`, the highest-PageRank computers were mostly two-hop or shared hubs, including `C586`, `C612`, `C529`, and `C625`, followed by direct hubs `C467`, `C457`, and `C528`. `C15758` itself had very low PageRank.

PageRank is therefore structural context, not proof of maliciousness. A high score for a two-hop hub should not outweigh the temporal and identity evidence from Steps 3 and 4.

## Final findings

1. **The 5+ hourly burst is a broad triage signal.** It is validated by `C17693`, but the full `AUTH_CONNECTED` graph contains many smaller and recurring bursts that require corroboration.

2. **C15758 is the stronger broad-triage candidate.** Its signal was isolated and accompanied by successful mixed machine/user-style authentication, while `C5868` showed recurring machine-only activity consistent with infrastructure.

3. **Reach and PageRank are hub-driven.** Both candidates reached 105 computers, and PageRank favored shared two-hop hubs; neither measure independently confirms a lateral pivot.

## Final conclusion

`C15758` should be prioritized for investigation, with `C5868` retained as a useful infrastructure comparison. Scenario 2 identifies candidates for analyst review; it does not establish a confirmed beachhead without additional evidence.
