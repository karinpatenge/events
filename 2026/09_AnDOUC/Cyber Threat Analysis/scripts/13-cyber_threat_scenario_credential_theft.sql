/******************************************************************************
 *
 * Cyber Threat Scenario 1: Credential Theft / Fraudulent Cross-Computer
 * Authentication ("impossible travel" / shared or stolen credential abuse)
 *
 * Narrative:
 *   A legitimate user_domain's credentials get stolen or shared, and are
 *   then used repeatedly against a computer that isn't normally part of
 *   that identity's routine -- a sustained secondary relationship held for
 *   days to weeks, not a one-off login. (The original hypothesis behind
 *   this scenario was a fan-out burst instead -- one identity suddenly
 *   touching many computers in a short window. Step 1 checks that against
 *   ground truth first and rules it out: confirmed REDTEAM users touch at
 *   most 2 distinct computers, ever.) This script finds that persistence
 *   shape in AUTH data, checks it against the REDTEAM ground truth to see
 *   how many known compromises it already catches, and surfaces the
 *   same-shaped cases that are NOT yet labeled as compromised -- a hunting
 *   list for identity/credential fraud, ranked for review rather than
 *   worked in arrival order.
 * *
 * Analysis flow (step titles match 13-cyber_threat_scenario_credential_theft.md):
 *   1. Shape Verification -- verify the "one identity, many computers"
 *      shape actually appears in confirmed REDTEAM ground truth before
 *      trusting the burst heuristic
 *   2. Authentication Baseline -- establish each user's overall
 *      authentication fan-out
 *   3. Persistence Detection -- users maintaining a sustained
 *      authentication relationship with a secondary computer well beyond
 *      a one-off login. Two variants are kept side by side -- a per-user
 *      ratio (Step 3) and an absolute event-count band (Step 3b) -- plus
 *      a diagnostic (Step 3a) that checks whether the rank>1 filter they
 *      share hides compromises sitting on a user's PRIMARY computer
 *      instead
 *   4. Precision Check -- of Step 3b's candidates, how many are already
 *      confirmed fraud vs. currently unlabeled
 *   5. Evidence Trail -- pull process + network evidence around a
 *      candidate, over its own detected time span
 *   6. Structural Ranking -- rank the full candidate list by PageRank and
 *      by how many other users share the same target computer, so
 *      Step 5's manual review has a defensible order to work through
 *
 * File name: 13-cyber_threat_scenario_credential_theft.sql
 * Author: Karin Patenge (drafted using Claude Sonnet 5 Max)
 * Last updated: 2026-09-09
 *
 *****************************************************************************/

-------------------
-- Session settings
-------------------

ALTER SESSION FORCE PARALLEL QUERY;
ALTER SESSION ENABLE PARALLEL DDL;
ALTER SESSION ENABLE PARALLEL DML;

------------------------------------------------------------------------
-- Step 1: Shape verification
-- does "one identity, many computers" actually appear in the confirmed
-- ground truth? Before trusting the
-- fan-out-burst heuristic in Step 4 as a proxy for this fraud pattern,
-- confirm it is the shape REDTEAM events actually take. If most
-- user_domains below show up with distinct_computers = 1, the
-- burst-per-user signal is not where the real signal lives, and Step 5's
-- evidence trail should be retargeted around single-touch anomalies
-- instead (e.g. "the first time this user ever touched this computer").
------------------------------------------------------------------------

SELECT
  user_domain,
  COUNT(*)                               AS confirmed_redteam_events,
  COUNT(DISTINCT authenticated_computer) AS distinct_computers,
  MIN(auth_time)                         AS first_event,
  MAX(auth_time)                         AS last_event
FROM
  GRAPH_TABLE (
    lanl_ground_truth_graph
    MATCH (u IS user_domain) -[a IS authenticated]-> (c IS computer)
    COLUMNS (
      u.user_domain AS user_domain,
      c.computer    AS authenticated_computer,
      a.time        AS auth_time
    )
  )
GROUP BY
  user_domain
ORDER BY
  distinct_computers DESC,
  confirmed_redteam_events DESC;

------------------------------------------------------------------
-- Step 2: Baseline -- overall authentication fan-out per user
-- How many DISTINCT computers has each user ever authenticated to,
-- across the full 58-day window? This is the "normal" reference point
-- that Step 3's short-window burst gets compared against.
------------------------------------------------------------------

SELECT
  user_domain,
  COUNT(DISTINCT authenticated_computer) AS distinct_computers_overall,
  COUNT(*)                               AS total_auth_events
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
    COLUMNS (
      u.user_domain AS user_domain,
      c.computer    AS authenticated_computer
    )
  )
GROUP BY
  user_domain
ORDER BY
  distinct_computers_overall DESC
FETCH APPROX FIRST 1000 ROWS ONLY;

------------------------------------------------------------------------
-- Step 3: Persistence detection -- users with a sustained, repeated
-- authentication relationship to a computer that is NOT their normal,
-- dominant one.
--
-- Step 1 showed the ground-truth shape is NOT "one identity fans out to
-- many computers in a burst" -- confirmed REDTEAM users authenticate to
-- at most 2 distinct computers total, but often rack up dozens to 100+
-- repeated events against a SINGLE computer, spread across days to
-- weeks (e.g. U66@DOM1: 118 events, 1 computer, ~18.6 days).
--
-- Step 2 then showed two reasons a flat threshold on top of that isn't
-- enough: (a) ANONYMOUS LOGON / machine ($) / NETWORK SERVICE accounts
-- dominate the fan-out baseline with values in the thousands and are
-- not human-identity fraud candidates -- excluded in auth_edges below;
-- (b) confirmed REDTEAM users are themselves high-fan-out accounts
-- (e.g. U1653@DOM1: 1,517 computers / 27,931 events overall), so a
-- flat "not this user's #1 computer" + flat event-count threshold
-- barely narrows anything down for them while over-flagging quieter
-- users. The fix: normalize each candidate secondary relationship
-- against that SAME user's own average events-per-computer (from a
-- baseline recomputed here, mirroring Step 2) -- flag only pairs that
-- persist over time AND concentrate a disproportionate share of that
-- user's activity onto one non-dominant computer, disproportionate
-- relative to how thin their own attention normally spreads.
------------------------------------------------------------------------

WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam  -- 1 if this specific AUTH row matches a known REDTEAM event
      )
    )
),
user_baseline AS (
  SELECT
    user_domain,
    COUNT(DISTINCT authenticated_computer)            AS distinct_computers_overall,
    COUNT(*)                                          AS total_auth_events,
    COUNT(*) / COUNT(DISTINCT authenticated_computer) AS avg_events_per_computer
  FROM
    auth_edges
  GROUP BY
    user_domain
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    b.distinct_computers_overall,
    b.avg_events_per_computer,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    )                                          AS computer_rank_for_user,  -- 1 = this user's most-used computer
    p.auth_events / b.avg_events_per_computer AS events_vs_user_average    -- multiple of this user's own per-computer average
  FROM
    pair_stats p
    JOIN user_baseline b ON b.user_domain = p.user_domain
)
SELECT *
FROM ranked
WHERE
  computer_rank_for_user > 1       -- exclude the user's own/primary computer
  AND auth_events >= 3             -- floor: guards against ratio blow-ups when a user's own average is tiny
  AND span_seconds >= 86400        -- threshold: persists over at least 1 day
  AND events_vs_user_average >= 3  -- threshold: 3x+ this user's own average events-per-computer
ORDER BY
  pair_has_confirmed_redteam_event DESC,
  events_vs_user_average DESC,
  auth_events DESC;

------------------------------------------------------------------------
-- Step 3a (diagnostic): does the "secondary computer" framing miss a
-- compromise sitting on the user's PRIMARY (rank 1) computer?
--
-- U66@DOM1 carries 118 confirmed REDTEAM events against exactly 1
-- computer in Step 1's ground truth, but none of its Step-3-flagged
-- secondary relationships above carry the REDTEAM flag. The hypothesis:
-- Step 3 only ever looks at computer_rank_for_user > 1 by design, so if
-- the REDTEAM-flagged computer IS this user's #1 (most-used) computer,
-- Step 3 structurally cannot see it. This lists ALL of U66@DOM1's
-- computers, unfiltered, ranked by usage, to test that.
--
-- Result: the hypothesis was wrong. C17693 -- the confirmed compromise
-- (215 auth events total) -- is rank 102 of ~135, not rank 1; U66@DOM1's
-- actual #1 computer is C1823 (106,859 events, unrelated automated-
-- looking traffic). So computer_rank_for_user > 1 does NOT hide this
-- compromise -- it was always eligible to be flagged by rank alone. What
-- actually buries it is scale, not rank: see Step 4, which shows this
-- pair is 1 of only 3 confirmed hits among 69,648 total candidates the
-- persistence band produces. Swap the literal below for any other
-- candidate user to re-run this per-user check (U737@DOM1 was checked
-- the same way -- its confirmed pair, C19932, came back as rank 3).
------------------------------------------------------------------------

WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain = 'U66@DOM1'
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam
      )
    )
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
)
SELECT
  user_domain,
  authenticated_computer,
  auth_events,
  first_event,
  last_event,
  span_seconds,
  pair_has_confirmed_redteam_event,
  RANK() OVER (ORDER BY auth_events DESC) AS computer_rank_for_user
FROM
  pair_stats
ORDER BY
  computer_rank_for_user;

--------------------------------------------------------------------------
-- Step 3b: Persistence-band detection -- an alternative to Step 3's
-- per-user ratio, using an absolute event-count band instead.
--
-- The diagnostic above (U66@DOM1) showed Step 3's ratio filter has a
-- real blind spot: this user's avg_events_per_computer is inflated to
-- ~5,286 by 101 of their 182 computers, each carrying thousands to
-- 100,000+ events -- almost certainly automated/service-account
-- traffic rather than normal human behavior. Against that inflated
-- average, the confirmed compromise (215 events on C17693, ~18.6 days)
-- looks like only ~4% of "normal" and never reaches the 3x-average
-- bar. A per-user mean (or median -- more than half of U66@DOM1's
-- computers sit in that same extreme range, so a median would be
-- pulled up too) cannot describe "typical" for a user whose own
-- history is already majority-abnormal.
--
-- This version drops the per-user ratio and instead uses an absolute
-- event-count band, calibrated against BOTH confirmed cases found so
-- far:
--   U737@DOM1 -> C19932: 573 events, ~24.4 days (Scenario 2 beachhead)
--   U66@DOM1  -> C17693: 215 events, ~18.6 days (Scenario 2 beachhead)
-- Both sit comfortably inside [50, 5000]: well above one-off noise
-- (single-digit events at the bottom of the U66@DOM1 diagnostic) and
-- well below the automated-bulk scale (958+ events per computer in
-- U66@DOM1's heavy cluster). distinct_computers_overall and
-- avg_events_per_computer are still joined in as CONTEXT columns, to
-- see how broad a user's footprint is when reviewing candidates, but
-- no longer drive the filter. This band was calibrated from these two
-- examples, but Step 4 shows a third confirmed pair also falls inside
-- it -- 69,648 total candidates match rank>1 + band + span, of which
-- exactly 3 carry pair_has_confirmed_redteam_event = 1 (see Step 4).
-- That's real signal, not zero, but nowhere near a short list --
-- Step 6 ranks the full candidate set so Step 5 has a defensible order
-- to review it in. Keep this alongside Step 3 and compare their
-- candidate lists rather than assuming one strictly supersedes the
-- other.
--------------------------------------------------------------------------

WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam  -- 1 if this specific AUTH row matches a known REDTEAM event
      )
    )
),
user_baseline AS (
  SELECT
    user_domain,
    COUNT(DISTINCT authenticated_computer)            AS distinct_computers_overall,
    COUNT(*)                                          AS total_auth_events,
    COUNT(*) / COUNT(DISTINCT authenticated_computer) AS avg_events_per_computer
  FROM
    auth_edges
  GROUP BY
    user_domain
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    b.distinct_computers_overall,
    b.avg_events_per_computer,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    )                                          AS computer_rank_for_user,  -- 1 = this user's most-used computer
    p.auth_events / b.avg_events_per_computer AS events_vs_user_average    -- context only -- see header, not used as a filter here
  FROM
    pair_stats p
    JOIN user_baseline b ON b.user_domain = p.user_domain
)
SELECT *
FROM ranked
WHERE
  computer_rank_for_user > 1          -- exclude the user's own/primary computer
  AND auth_events BETWEEN 50 AND 5000 -- moderate band: above one-off noise, below automated-bulk scale
  AND span_seconds >= 86400           -- threshold: persists over at least 1 day
ORDER BY
  pair_has_confirmed_redteam_event DESC,
  auth_events DESC;

--------------------------------------------------------------------------
-- Step 4: Precision check -- of Step 3b's persistence-band candidates, how
-- many are already confirmed fraud (REDTEAM = 1) vs. currently unlabeled?
--
-- The original version of this step measured a different, unrelated shape:
-- an hourly fan-out burst (>=10 distinct computers touched by one
-- user_domain within the same hour). Step 1 already ruled that shape out --
-- confirmed REDTEAM users touch at most 2 distinct computers, ever -- and
-- that version never consumed Step 3 or 3b's actual candidate list, so it
-- couldn't validate either of them. This version checks the real
-- candidates: Step 3b's rank>1 + 50-5000 events + >=1 day band.
--
-- Measured result: 69,648 total candidates match the band, of which
-- exactly 3 carry pair_has_confirmed_redteam_event = 1 (~0.0043% hit
-- rate). Not zero -- see 4b for the confirmed pairs, which include one
-- beyond the two Step 3b's header was originally calibrated from -- but
-- nowhere near a short list either. 69,645 unlabeled candidates is too
-- many for Step 5's one-row-at-a-time evidence pull; see Step 6, which
-- ranks this same candidate set by structural importance so Step 5 has
-- somewhere sensible to start.
--------------------------------------------------------------------------

-- 4a. How many candidates are confirmed vs. unlabeled?
WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam
      )
    )
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    ) AS computer_rank_for_user
  FROM
    pair_stats p
)
SELECT
  pair_has_confirmed_redteam_event,
  COUNT(*) AS candidate_pairs
FROM ranked
WHERE
  computer_rank_for_user > 1
  AND auth_events BETWEEN 50 AND 5000
  AND span_seconds >= 86400
GROUP BY
  pair_has_confirmed_redteam_event;

-- 4b. Which specific pairs are the confirmed ones?
WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam
      )
    )
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    ) AS computer_rank_for_user
  FROM
    pair_stats p
)
SELECT *
FROM ranked
WHERE
  computer_rank_for_user > 1
  AND auth_events BETWEEN 50 AND 5000
  AND span_seconds >= 86400
  AND pair_has_confirmed_redteam_event = 1
ORDER BY
  user_domain;

------------------------------------------------------------------------
-- Step 5: Evidence trail for a candidate
-- For a (user_domain, authenticated_computer) candidate surfaced by
-- Step 4 and prioritized by Step 6, pull the processes that ran and the
-- network flows that occurred on the touched computer across the
-- candidate's own detected window (first_event to last_event) -- not a
-- fixed hour, since this shape is sustained persistence over days to
-- weeks, not a one-hour burst. This is the fraud "fingerprint" an
-- analyst reviews to confirm or dismiss the candidate. Replace the bind
-- values with a row's user_domain / authenticated_computer / first_event
-- / last_event before running. A multi-week window can return a lot of
-- rows in 5b/5c -- narrow :window_start_time / :window_end_time further
-- (e.g. just the first day or two of the relationship) if the full span
-- is too much to review at once. If 5c's per-destination aggregation
-- shows one destination carrying disproportionate volume relative to
-- its flow count, 5d and 5e follow up on that specific destination.
------------------------------------------------------------------------

-- 5a. Which computers did the candidate user touch, and with what auth details?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
    WHERE
      u.user_domain = 'U3486@DOM1'
      --u.user_domain = :candidate_user_domain
      AND e.time BETWEEN 830008 AND 2462741
      --AND e.time BETWEEN :window_start_time AND :window_end_time
      --AND c.computer = :authenticated_computer  -- uncomment to narrow to just the flagged relationship, instead of the full window fan-out
    COLUMNS (
      u.user_domain      AS user_domain,
      c.computer         AS authenticated_computer,
      e.time             AS auth_time,
      e.logon_type       AS logon_type,
      e.auth_type        AS auth_type,
      e.auth_orientation AS auth_orientation
    )
  )
ORDER BY
  auth_time;

-- 5b. What processes ran on the touched computer during the same window?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (c IS computer) -[r IS ran]-> (p IS process)
    WHERE
      c.computer = 'C22409'  -- one computer at a time from 5a, or IN (...) for all of them
      --c.computer = :authenticated_computer  -- one computer at a time from 5a, or IN (...) for all of them
      AND r.time BETWEEN 830008 AND 2462741
      -- AND r.time BETWEEN :window_start_time AND :window_end_time
    COLUMNS (
      c.computer  AS computer,
      p.process   AS process_name,
      r.time      AS time,
      r.start_end AS start_end
    )
  )
ORDER BY
  time;

-- 5c. Was there unusually large network activity from that computer in the same window?
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (src IS computer) -[f IS flows_connected]-> (dst IS computer)
    WHERE
      src.computer = 'C22409'
      AND f.time BETWEEN 830008 AND 2462741
    COLUMNS (
      src.computer AS src_computer,
      dst.computer AS dst_computer,
      f.protocol   AS protocol,
      f.dst_port   AS dst_port,
      f.packet_cnt AS packet_cnt,
      f.byte_cnt   AS byte_cnt,
      f.time       AS time
    )
  )
ORDER BY
  byte_cnt DESC;

-- 5c (aggregated). Roll 5c's raw flow list up by destination to see
-- where volume concentrates -- flow_count vs. total_bytes tells you
-- whether a destination looks like routine repeated session overhead
-- (many flows, small total) or bulk data movement (few flows, large
-- total). This surfaced the C22409 -> C2651 outlier below: 17 flows /
-- 18.49 MB / one single flow of 2.13 MB, vs. the next-largest
-- destination C5721's 367 flows averaging ~5 KB each.
SELECT
  dst_computer,
  protocol,
  dst_port,
  COUNT(*)        AS flow_count,
  SUM(packet_cnt) AS total_packets,
  SUM(byte_cnt)   AS total_bytes,
  MAX(byte_cnt)   AS largest_single_flow_bytes
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (src IS computer) -[f IS flows_connected]-> (dst IS computer)
    WHERE
      src.computer = 'C22409'
      AND f.time BETWEEN 830008 AND 2462741
    COLUMNS (
      dst.computer AS dst_computer,
      f.protocol   AS protocol,
      f.dst_port   AS dst_port,
      f.packet_cnt AS packet_cnt,
      f.byte_cnt   AS byte_cnt
    )
  )
GROUP BY dst_computer, protocol, dst_port
ORDER BY total_bytes DESC;

-- 5d. Drill into one destination's individual flows, once 5c
-- (aggregated) shows its volume is disproportionate to its flow count.
-- Bind :destination_computer to that outlier -- currently C2651 for the
-- C22409 case above. Compare these timestamps against 5a's auth events
-- and 5b's process activity for the same window; 5b needs no separate
-- query here, it's already parameterized for :authenticated_computer /
-- :window_start_time / :window_end_time.
SELECT *
FROM
  GRAPH_TABLE (
    lanl_cyber_graph
    MATCH (src IS computer) -[f IS flows_connected]-> (dst IS computer)
    WHERE
      src.computer = 'C22409'
      -- src.computer = :authenticated_computer
      AND dst.computer = 'C2651'
      -- AND dst.computer = :destination_computer
      AND f.time BETWEEN 830008 AND 2462741
      -- AND f.time BETWEEN :window_start_time AND :window_end_time
    COLUMNS (
      f.protocol   AS protocol,
      f.dst_port   AS dst_port,
      f.packet_cnt AS packet_cnt,
      f.byte_cnt   AS byte_cnt,
      f.time       AS time
    )
  )
ORDER BY
  time;

-- 5e. Does :destination_computer also show up as a target elsewhere in
-- the candidate list -- i.e. do OTHER users maintain a persistence-band
-- relationship with it too, not just this candidate's computer reaching
-- it over the network? A hit here means the outlier destination isn't
-- just something C22409-like computers happen to talk to, it's itself a
-- computer other flagged identities persistently authenticate to.
-- Reuses Step 4/6's exact candidate definition.
WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam
      )
    )
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    ) AS computer_rank_for_user
  FROM
    pair_stats p
)
SELECT *
FROM ranked
WHERE
  computer_rank_for_user > 1
  AND auth_events BETWEEN 50 AND 5000
  AND span_seconds >= 86400
  AND authenticated_computer = 'C2651'
  -- AND authenticated_computer = :destination_computer
ORDER BY
  pair_has_confirmed_redteam_event DESC,
  auth_events DESC;

------------------------------------------------------------------------
-- Step 6: Rank the candidate list by structural importance
-- PageRank over the full cyber graph shows whether a candidate's target
-- computer is structurally critical (potential domain controller, jump
-- host) rather than a low-value workstation -- turning a detection hit
-- into a statement about business impact, and giving Step 5 a defensible
-- order to work through.
--
-- First run exposed a real problem: sorted by pagerank_score DESC alone,
-- every slot past the 3 confirmed pairs was the SAME computer, C586 --
-- ~190+ distinct users each individually satisfy the persistence band
-- against it. C586's pagerank_score (0.0400) is ~700x the graph average
-- and dwarfs all three confirmed pairs' target computers (0.0000114 -
-- 0.0000735 -- average to below-average). That's consistent with C586
-- being shared infrastructure (file/print server, DC, etc.) that nearly
-- everyone persistently touches as routine business, not a targeted
-- relationship -- and it swamped FETCH FIRST 200 entirely, crowding out
-- every other candidate computer.
--
-- It also answers the sanity check this step's design already called
-- for ("do confirmed pairs score high or low?"): they score LOW, not
-- high. All three sit at or below the graph's average pagerank_score.
-- So "prioritize by pagerank_score DESC" alone points AWAY from the
-- confirmed profile -- the same shape of mistake as Step 3b's
-- auth_events DESC ordering (the confirmed pairs sit at the low end of
-- that band too, not the high end -- see Step 3b/4).
--
-- Fix: compute candidate_user_fan_in (how many distinct candidate users
-- share this same target computer) and sort with LOW fan-in first -- a
-- computer only one or two candidate users persistently touch looks like
-- a targeted relationship; one dozens or hundreds touch looks like
-- shared infrastructure. pagerank_score DESC remains the tiebreaker
-- within that, so it still answers "how critical is this target" once
-- shared-infrastructure noise isn't drowning out everything else.
-- Nothing is hard-excluded -- candidate_user_fan_in is visible on every
-- row so this can be reviewed and re-tuned like every other threshold in
-- this script. Feed the user_domain / authenticated_computer /
-- first_event / last_event from the top rows into Step 5.
------------------------------------------------------------------------

WITH auth_edges AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      lanl_cyber_graph
      MATCH (u IS user_domain) -[e IS auth_src_authenticated]-> (c IS computer)
      WHERE
        u.user_domain NOT LIKE 'ANONYMOUS LOGON@%'
        AND u.user_domain NOT LIKE 'NETWORK SERVICE@%'
        AND u.user_domain NOT LIKE '%$@%'   -- machine/computer accounts, not human identities
      COLUMNS (
        u.user_domain AS user_domain,
        c.computer    AS authenticated_computer,
        e.time        AS auth_time,
        e.redteam     AS is_confirmed_redteam
      )
    )
),
user_baseline AS (
  SELECT
    user_domain,
    COUNT(DISTINCT authenticated_computer) AS distinct_computers_overall
  FROM
    auth_edges
  GROUP BY
    user_domain
),
pair_stats AS (
  SELECT
    user_domain,
    authenticated_computer,
    COUNT(*)                        AS auth_events,
    MIN(auth_time)                  AS first_event,
    MAX(auth_time)                  AS last_event,
    MAX(auth_time) - MIN(auth_time) AS span_seconds,
    MAX(is_confirmed_redteam)       AS pair_has_confirmed_redteam_event
  FROM
    auth_edges
  GROUP BY
    user_domain,
    authenticated_computer
),
ranked AS (
  SELECT
    p.*,
    b.distinct_computers_overall,
    RANK() OVER (
      PARTITION BY p.user_domain
      ORDER BY p.auth_events DESC
    ) AS computer_rank_for_user  -- 1 = this user's most-used computer
  FROM
    pair_stats p
    JOIN user_baseline b ON b.user_domain = p.user_domain
),
candidates AS (
  SELECT *
  FROM ranked
  WHERE
    computer_rank_for_user > 1          -- exclude the user's own/primary computer
    AND auth_events BETWEEN 50 AND 5000 -- moderate band: above one-off noise, below automated-bulk scale
    AND span_seconds >= 86400           -- threshold: persists over at least 1 day
),
computer_fan_in AS (
  SELECT
    authenticated_computer,
    COUNT(DISTINCT user_domain) AS candidate_user_fan_in  -- how many distinct candidate users share this target
  FROM
    candidates
  GROUP BY
    authenticated_computer
),
computer_importance AS (
  SELECT *
  FROM
    GRAPH_TABLE (
      DBMS_OGA.PAGERANK (
        lanl_cyber_graph,
        PROPERTY (VERTEX OUTPUT rank),
        10, 1.0, 0.85d, FALSE
      )
      MATCH (c IS computer)
      COLUMNS (
        c.computer AS computer,
        c.rank     AS pagerank_score
      )
    )
)
SELECT
  cand.user_domain,
  cand.authenticated_computer,
  cand.auth_events,
  cand.first_event,
  cand.last_event,
  cand.span_seconds,
  cand.distinct_computers_overall,
  cand.computer_rank_for_user,
  cand.pair_has_confirmed_redteam_event,
  fi.candidate_user_fan_in,
  imp.pagerank_score
FROM
  candidates cand
  JOIN computer_importance imp ON imp.computer = cand.authenticated_computer
  JOIN computer_fan_in fi ON fi.authenticated_computer = cand.authenticated_computer
ORDER BY
  cand.pair_has_confirmed_redteam_event DESC,
  fi.candidate_user_fan_in ASC,
  imp.pagerank_score DESC
FETCH APPROX FIRST 200 ROWS ONLY;

-- For a quick one-off check on specific computers instead of the full
-- candidate list, skip `candidates` and filter computer_importance
-- directly, e.g.:
--   SELECT * FROM computer_importance
--   WHERE computer IN (:computer_1, :computer_2) ORDER BY pagerank_score DESC;
