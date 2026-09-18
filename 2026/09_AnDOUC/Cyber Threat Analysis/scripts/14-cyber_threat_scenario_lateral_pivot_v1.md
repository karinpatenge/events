# Scenario 2: Lateral Pivot / C17693-Like Beachhead Reuse

## Purpose

Find previously unknown staging hosts whose behavior resembles the validated `C17693` beachhead: recurring, high-volume, multi-victim lateral movement. This v1 workflow is intentionally high-precision; smaller or isolated movements remain in scope for v2 broad triage.

`C17693` is used as the empirical reference. The workflow identifies candidates for analyst review; it does not confirm compromise by itself.

## Workflow and final interpretation

### Step 1 — Calibrate the known beachhead shape

**Purpose:** Establish the real behavior of confirmed staging hosts before defining the C17693-like profile.

**Expected outcome:** Victim volume, activity span, and hourly burst distributions for the known hosts.

Ground truth shows that `C17693` reached 296 victims and exceeded five compromised victims per hour in 30 of 69 active hours. `C19932` reached 8 victims and `C22409` reached 3; neither exceeded two compromised victims in one hour.

This confirms that the 5+ hourly threshold is meaningful for the loud C17693 pattern, but it is not designed to capture smaller movements.

### Step 2 — Build the broad reference population

**Purpose:** Find hourly computer-to-computer `AUTH_CONNECTED` bursts without relying on the REDTEAM label.

**Expected outcome:** Host/bucket rows with at least five distinct targets, REDTEAM status, and overall host fan-out for context.

The final output showed:

- `C17693`: 525 overall `AUTH_CONNECTED` targets; peak of 67 in one hour.
- `C19932` and `C22409`: 24 overall targets each; peak of 17 each in the broader `AUTH_CONNECTED` data.
- Many unknown hosts: small overall fan-out values, typically 5–7 in the visible results.

This is a calibration and entry-population query, not the final candidate ranking. The broader `AUTH_CONNECTED` signal is not equivalent to ground-truth `COMPROMISED` activity.

### Step 3 — Isolate new C17693-like candidates

**Purpose:** Exclude known staging hosts and confirmed buckets, require recurring clean bursts, and rank unknown hosts by similarity to C17693.

**Expected outcome:** One representative peak bucket per unknown host, with overall fan-out, recurrence, maximum burst, average burst, and profile distance.

The inferred C17693 reference profile was 525 overall targets, a maximum hourly burst of 67, and 42 qualifying hourly buckets. The closest final candidates were:

| Candidate | Peak bucket | Targets in bucket | Overall targets | Qualifying buckets | Maximum | Average | Profile distance |
|---|---:|---:|---:|---:|---:|---:|---:|
| `C5400` | 326 | 51 | 70 | 50 | 51 | 6.88 | 1.2959 |
| `C3435` | 206 | 82 | 103 | 66 | 82 | 8.00 | 1.5991 |
| `C23055` | 514 | 26 | 33 | 38 | 26 | 10.47 | 1.6443 |
| `C21488` | 368 | 25 | 40 | 46 | 25 | 8.13 | 1.6459 |
| `C467` | 637 | 66 | 90 | 78 | 66 | 7.62 | 1.7006 |

`C5400` is the closest profile match. `C3435` has a larger peak and broader overall fan-out but is farther from the combined reference profile. `C467` is retained as an infrastructure-like comparison because its high recurrence and reach may reflect shared graph infrastructure.

Profile distance is a relative ranking measure, not a probability or confirmation of compromise.

### Step 3a — Validate the profile calculation

**Purpose:** Expose the profile statistics for C17693 and the known control hosts so the Step 3 reference calculation can be checked independently.

**Expected outcome:** Diagnostic profile rows for `C17693`, `C19932`, and `C22409` using the same bucket definition as Step 3.

The `C17693` diagnostic row must agree with Step 3: 525 overall targets, 42 qualifying 5+ buckets, and a maximum bucket of 67. The two control rows provide context for comparing their broader `AUTH_CONNECTED` burst shapes; this query does not generate new candidates.

### Step 4 — Identify the identity behind the candidate

**Purpose:** Review authentication activity immediately before and during the selected peak bucket.

**Expected outcome:** User or machine identities, authentication types, orientations, and success/failure status that help distinguish concentrated activity from routine authentication.

Run one candidate at a time with the corresponding Step 3 row:

```text
Primary:          :candidate_staging_host = 'C5400', :time_bucket = 326
Secondary:        :candidate_staging_host = 'C3435', :time_bucket = 206
Infrastructure:   :candidate_staging_host = 'C467',  :time_bucket = 637
```

Final identity interpretation:

- `C5400`: dominated by `U3635@DOM1`, with repeated successful Kerberos and NTLM network logons plus TGS activity. `ANONYMOUS LOGON@C625` is a secondary source clue; `U1944@DOM1` and `C5570$@DOM1` occur less often.
- `C3435`: dominated by `U66@DOM1`, with dense Kerberos, TGS/AuthMap, and some NTLM activity. `C3435$@DOM1` is the host account and may represent machine or automated activity.
- `C467`: dominated by its own machine account in the non-`LogOff` records and contains many principals, making it a useful infrastructure comparison rather than a clean identity signal.

The final query excludes `LogOff` records and retains `LogOn`, `TGS`, `TGT`, and `AuthMap` records, including failures. The supplied earlier `C3435`/`C467` extracts included `LogOff` rows and should be rerun when a clean final extract is required. None of the identity results proves malicious use.

### Step 5 — Separate direct and two-hop reach

**Purpose:** Determine whether the candidate’s direct movement expands through valid two-hop paths, while excluding self-reach and repeated-vertex paths.

**Expected outcome:** Direct targets, two-hop-only targets, overlap, total reach, and intermediate computers.

Run with the same candidate bindings:

```text
:candidate_staging_host = 'C5400'
:candidate_staging_host = 'C3435'
:candidate_staging_host = 'C467'
```

Final results:

| Candidate | Direct | Two-hop only | Direct/two-hop overlap | Total | Total/direct |
|---|---:|---:|---:|---:|---:|
| `C5400` | 69 | 601 | 28 | 670 | 9.71x |
| `C3435` | 102 | 655 | 31 | 757 | 7.42x |
| `C467` | 89 | 1,687 | 89 | 1,776 | 19.96x |

`TOTAL` equals direct plus two-hop-only; overlap is reported separately and is not added again. `C5400` and `C3435` both show broad expansion beyond their direct reach. `C467` expands much more strongly and has complete direct/two-hop overlap, consistent with shared-hub infrastructure behavior rather than necessarily stronger beachhead evidence.

### Step 6 — Add PageRank context

**Purpose:** Estimate the structural importance of the candidate and reached computers in the full cyber graph.

**Expected outcome:** PageRank scores annotated with minimum hop distance and reach class, providing impact context while exposing hub-inflation effects.

Run with the same bindings as Step 5. The cleaned reach set includes the candidate staging host with `MIN_HOP = 0` and excludes repeated-vertex paths.

The final outputs for `C5400` and `C3435` returned the same leading global hubs, including:

- `C586`: approximately 0.04000135
- `C612`: approximately 0.03067915
- `C529`: approximately 0.03052434
- `C625`: approximately 0.02815230
- `C467`: approximately 0.02739128
- `C457`: approximately 0.02670583
- `C1065`: approximately 0.02519077
- `C528`: approximately 0.02066926

`C3435` itself had a low score of approximately 0.0000189. `C5400` was not present in the displayed top 200, which does not mean its score is zero. `C467` itself scored approximately 0.02739, reinforcing its role as a central infrastructure comparison.

PageRank is shared graph-centrality context, not candidate-specific evidence of maliciousness. Steps 3 and 4 provide the primary profile and identity evidence; Step 5 provides the reach context.

## Scope resolution

`C19932` and `C22409` are not C17693-shaped beachheads: in ground-truth `COMPROMISED` data they remain quiet, few-victim hosts. Alternative daily-burst and novelty measures were either inconsistent between the controls or overwhelmed by full-graph infrastructure noise; for example, `C1798` reached 8,052 overall `AUTH_CONNECTED` targets without confirmation. These hosts are better addressed through the Scenario 1 identity-persistence lens than through this high-volume lateral-pivot search.

## Final findings

1. **C5400 is the strongest C17693-like match.** It had the smallest profile distance (1.2959), recurring clean bursts, and a concentrated identity signal led by `U3635@DOM1`.

2. **C3435 shows substantial but potentially automated activity.** It had the largest candidate peak and broader direct reach, but its `U66@DOM1`/machine-account pattern requires analyst validation before interpreting it as a beachhead.

3. **C467 is an infrastructure comparison, not the primary finding.** Its 1,776 reachable computers and high PageRank reflect strong shared connectivity and should not outweigh the profile and identity evidence for `C5400` or `C3435`.

## Final conclusion

Prioritize `C5400` for investigation, retain `C3435` as a second C17693-like candidate, and use `C467` as an infrastructure comparison. Scenario 2 identifies candidates for analyst review; it does not establish a confirmed beachhead without additional evidence.
