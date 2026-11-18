--------------------------------------------------------------------------------
-- File       : 09a_load_knee_kg.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Loads the knee knowledge graph KNEE_KG into the RDF network
--              from 08_create_rdf_network.sql and prepares it for the queries:
--                0. checks; drops graph collection, entailment and KNEE_KG
--                   and creates KNEE_KG again, empty
--                1. KNEE_KG (353 triples) with INSERT using the constructor
--                   SDO_RDF_TRIPLE_S through the view RDF_NETWORK#RDFT_KNEE_KG
--                2. entailment KNEE_KG_RIX with OWLPRIME and KNEE_RB
--                3. graph collection KNEE_FMA_VM, if the FMA is loaded
--                4. statistics
--                5. checks and test queries on KNEE_KG; 5c-5e check the
--                   entailment and show its effect on query results
--              The FMA is loaded by 09b_load_fma.sql (takes a few minutes).
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Tool       : SQLcl (LOAD is a SQLcl command)
-- Run        : in folder scripts\sql, so that the relative paths are correct:
--                cd <project>\scripts\sql
--                sql doag2026@<tns_alias> @09a_load_knee_kg.sql
-- Before     : 08_create_rdf_network.sql (network, graphs, rulebase KNEE_RB).
--              data/_load/knee_kg_nt.csv must exist (README.md).
-- Re-runnable: yes, independently of 09b. KNEE_KG is created again empty on
--              every run; the FMA stays.
-- Note       : On Autonomous AI Database the SEM_MATCH test queries need
--              Oracle Java (00_create_user.sql, section 6). Loading and
--              entailment work without it.
-- Log        : logs/sql/09a_load_knee_kg.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/09a_load_knee_kg.log

-- Path to the data folder, relative to the current directory (folder scripts/sql)
DEFINE data_dir = ../../data

-- SQLcl LOAD reads only delimited text files (SET LOADFORMAT JSON applies
-- to UNLOAD only) and checks the file extension: it does not accept .nt
-- with LOADFORMAT DELIMITED. It therefore loads a copy with identical
-- content and extension .csv from data/_load (README.md, prerequisites).

-- Expected number of triples. Adjust after changing the dataset.
DEFINE exp_knee_triples = 353

-- RDF network: on Autonomous AI Database only the default network
-- RDF_NETWORK. The owner is the demo user DOAG2026 by default
-- (in upper case, must match 00_create_user.sql).
DEFINE network_owner = DOAG2026
DEFINE network_name  = RDF_NETWORK

PROMPT
PROMPT === 09a Load the knee knowledge graph KNEE_KG ===

--==============================================================================
-- 0. Prerequisites; KNEE_KG empty again
--    Graph collection and entailment depend on KNEE_KG and are dropped
--    first; steps 2 and 3 create them again.
--==============================================================================

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
  IF USER <> UPPER('&network_owner') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Connected as ' || USER || '. The RDF network &network_name belongs to '
                                    || UPPER('&network_owner') || '; run this script as that user.');
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = '&network_name.#RDF_VALUE$';
  IF l_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20031, 'The RDF network &network_name is missing. Run 08_create_rdf_network.sql first.');
  END IF;

  SELECT COUNT(*) INTO l_cnt FROM user_objects WHERE object_name = '&network_name.#SEMR_KNEE_RB';
  IF l_cnt = 0 THEN
    RAISE_APPLICATION_ERROR(-20036, 'The rulebase KNEE_RB is missing. Run 08_create_rdf_network.sql first.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name and rulebase KNEE_RB exist');
END;
/

PROMPT
PROMPT --- 0. Drop graph collection, entailment and KNEE_KG; create KNEE_KG empty
DECLARE
  PROCEDURE report(p_what IN VARCHAR2, p_err IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD(p_what, 34)
                         || CASE WHEN p_err IS NULL THEN 'dropped'
                                 ELSE 'not present (' || SUBSTR(p_err, 1, 60) || ')' END);
  END report;
BEGIN
  BEGIN
    SEM_APIS.DROP_RDF_GRAPH_COLLECTION('KNEE_FMA_VM', network_owner => '&network_owner', network_name => '&network_name');
    report('Graph collection KNEE_FMA_VM');
  EXCEPTION WHEN OTHERS THEN report('Graph collection KNEE_FMA_VM', SQLERRM);
  END;
  BEGIN
    SEM_APIS.DROP_ENTAILMENT(index_name_in => 'KNEE_KG_RIX', network_owner => '&network_owner', network_name => '&network_name');
    report('Entailment KNEE_KG_RIX');
  EXCEPTION WHEN OTHERS THEN report('Entailment KNEE_KG_RIX', SQLERRM);
  END;

  BEGIN
    SEM_APIS.DROP_RDF_GRAPH('KNEE_KG', network_owner => '&network_owner', network_name => '&network_name');
    report('RDF graph KNEE_KG');
  EXCEPTION WHEN OTHERS THEN report('RDF graph KNEE_KG', SQLERRM);
  END;

  SEM_APIS.CREATE_RDF_GRAPH(
    rdf_graph_name => 'KNEE_KG',
    table_name     => NULL,
    column_name    => NULL,
    network_owner  => '&network_owner',
    network_name   => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      RDF graph KNEE_KG created empty (view &network_name.#RDFT_KNEE_KG)');
END;
/

--==============================================================================
-- 1. KNEE_KG: load N-Triples line by line, then INSERT with SDO_RDF_TRIPLE_S
--    Subject and predicate never contain spaces, the object is the rest
--    of the line up to the final dot. Umlauts in literals are escaped
--    (SEM_APIS.ESCAPE_RDF_TERM).
--==============================================================================

PROMPT
PROMPT --- 1. Knee knowledge graph KNEE_KG
SET LOADFORMAT DEFAULT
SET LOADFORMAT DELIMITED DELIMITER | ENCLOSURES OFF COLUMN_NAMES OFF ENCODING UTF8
SET LOAD DEFAULT
SET LOAD BATCH_ROWS 5000 BATCHES_PER_COMMIT 10 ERRORS 0 TRUNCATE ON

-- Copy of data/rdf/knee_kg.nt with identical content
LOAD stg_text_lines &data_dir/_load/knee_kg_nt.csv

TRUNCATE TABLE stg_rdf_triples;
INSERT INTO stg_rdf_triples (rdf$stc_sub, rdf$stc_pred, rdf$stc_obj)
SELECT REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 1),
       REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 2),
       SEM_APIS.ESCAPE_RDF_TERM(
         REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 3),
         options => ' UNI_ONLY=T ')
FROM   stg_text_lines
WHERE  REGEXP_LIKE(line_text, '^\s*[<_]');
COMMIT;

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM stg_rdf_triples;
  IF l_cnt <> &exp_knee_triples THEN
    RAISE_APPLICATION_ERROR(-20033, 'KNEE_KG: ' || l_cnt || ' triples in the staging table, expected &exp_knee_triples');
  END IF;

  -- The constructor SDO_RDF_TRIPLE_S(graph, subject, predicate, object,
  -- network_owner, network_name) creates the triple in the network; the
  -- view RDF_NETWORK#RDFT_KNEE_KG takes it in. For 353 triples a loop is
  -- enough; large volumes are loaded with the bulk load (09b).
  FOR r IN (SELECT rdf$stc_sub AS s, rdf$stc_pred AS p, rdf$stc_obj AS o
            FROM   stg_rdf_triples) LOOP
    INSERT INTO &network_name.#rdft_knee_kg
    VALUES (SDO_RDF_TRIPLE_S('KNEE_KG', r.s, r.p, r.o, '&network_owner', '&network_name'));
  END LOOP;
  COMMIT;

  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_knee_kg' INTO l_cnt;
  IF l_cnt <> &exp_knee_triples THEN
    RAISE_APPLICATION_ERROR(-20034, 'KNEE_KG: ' || l_cnt || ' triples in the graph, expected &exp_knee_triples');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      ' || RPAD('RDF graph KNEE_KG (SDO_RDF_TRIPLE_S)', 40) || LPAD(l_cnt, 8));
END;
/

-- Staging contents are no longer needed
TRUNCATE TABLE stg_text_lines;
TRUNCATE TABLE stg_rdf_triples;

--==============================================================================
-- 2. Entailment for KNEE_KG with OWLPRIME and KNEE_RB
--    As in the blueprint with SEM_APIS.CREATE_ENTAILMENT. This is the
--    inference step: it applies the rules of OWLPRIME and of the own
--    rulebase KNEE_RB (08_create_rdf_network.sql, section 5) to the loaded
--    triples and stores the derived triples in the entailment. It runs
--    here and not in 08, because it needs the loaded data.
--    A SEM_MATCH query sees the derived triples only if it passes
--    SEM_RULEBASES('OWLPRIME', 'KNEE_RB') or queries the graph collection
--    KNEE_FMA_VM, which contains the entailment. Section 5c-5e checks it.
--    The FMA is left out: its class hierarchy would enlarge the entailment
--    a lot, and demo step 4 needs it only as vocabulary.
--==============================================================================

PROMPT
PROMPT --- 2. Entailment KNEE_KG_RIX
BEGIN
  SEM_APIS.CREATE_ENTAILMENT(
    'KNEE_KG_RIX',
    SEM_MODELS('KNEE_KG'),
    SEM_RULEBASES('OWLPRIME', 'KNEE_RB'),
    network_owner => '&network_owner',
    network_name  => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      Entailment KNEE_KG_RIX (OWLPRIME, KNEE_RB)');
END;
/

--==============================================================================
-- 3. Graph collection KNEE_FMA_VM (formerly "virtual model")
--    This lets one query see the knee knowledge graph, the FMA and the
--    inferred triples at once, e.g. from the pattern via the cruciate
--    ligament to the FMA ID. Needs both graphs: whichever of 09a and 09b
--    runs last creates it.
--==============================================================================

PROMPT
PROMPT --- 3. Graph collection KNEE_FMA_VM
DECLARE
  l_knee PLS_INTEGER;
  l_fma  PLS_INTEGER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_knee_kg WHERE ROWNUM = 1' INTO l_knee;
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_fma WHERE ROWNUM = 1' INTO l_fma;
  IF l_knee = 0 OR l_fma = 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK      skipped: graph FMA is still empty, 09b_load_fma.sql creates the collection');
  ELSE
    SEM_APIS.CREATE_RDF_GRAPH_COLLECTION(
      rdf_graph_collection_name => 'KNEE_FMA_VM',
      rdf_graphs                => SEM_MODELS('KNEE_KG', 'FMA'),
      inferred_graphs           => SEM_ENTAILMENTS('KNEE_KG_RIX'),
      options                   => 'REPLACE=T',
      network_owner             => '&network_owner',
      network_name              => '&network_name');
    DBMS_OUTPUT.PUT_LINE('OK      Graph collection KNEE_FMA_VM (KNEE_KG, FMA, KNEE_KG_RIX)');
  END IF;
END;
/

--==============================================================================
-- 4. Statistics for the network
--==============================================================================

PROMPT
PROMPT --- 4. Statistics
BEGIN
  SEM_PERF.GATHER_STATS(network_owner => '&network_owner', network_name => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      SEM_PERF.GATHER_STATS');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('WARNING SEM_PERF.GATHER_STATS -> ' || SQLERRM);
END;
/

--==============================================================================
-- 5. Checks and test queries
--    From here on, an error no longer stops the script: if Oracle Java is
--    missing, the SEM_MATCH queries report an error, but the data is there.
--==============================================================================

WHENEVER SQLERROR CONTINUE

PROMPT
PROMPT --- 5a. Strong indicators per pattern in Jonas' report (without entailment)
COLUMN pattern FORMAT A50
COLUMN label   FORMAT A40
SELECT pattern, label, strong_found, strong_needed
FROM   TABLE(SEM_MATCH(
         'PREFIX kg:   <https://doag2026.example/knee#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          SELECT ?pattern ?label (COUNT(DISTINCT ?f) AS ?strong_found) ?strong_needed
          WHERE {
            <https://doag2026.example/knee#Report_SR-2026-11-16-0001> kg:reportsFinding ?f .
            ?pattern kg:hasStrongIndicator  ?f .
            ?pattern kg:minStrongIndicators ?strong_needed .
            ?pattern rdfs:label             ?label .
          }
          GROUP BY ?pattern ?label ?strong_needed
          ORDER BY DESC(?strong_found)',
         SEM_MODELS('KNEE_KG'), NULL, NULL, NULL, NULL, ' PLUS_RDFT=VC ', NULL, NULL,
         '&network_owner', '&network_name'));

PROMPT
PROMPT --- 5b. Inferred statements about Jonas' report (with entailment KNEE_RB)
COLUMN relation FORMAT A60
SELECT relation, pattern
FROM   TABLE(SEM_MATCH(
         'PREFIX kg: <https://doag2026.example/knee#>
          SELECT ?relation ?pattern
          WHERE {
            <https://doag2026.example/knee#Report_SR-2026-11-16-0001> ?relation ?pattern .
            FILTER (?relation IN (kg:showsIndicatorOf, kg:showsCounterIndicatorOf, kg:matchesMechanismOf))
          }
          ORDER BY ?pattern ?relation',
         SEM_MODELS('KNEE_KG'), SEM_RULEBASES('OWLPRIME', 'KNEE_RB'), NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name'));

PROMPT
PROMPT --- 5c. Entailment KNEE_KG_RIX: status and inputs
-- Expected: STATUS VALID, MODEL_COUNT 1, RULEBASE_COUNT 2, inputs
-- MODEL KNEE_KG, RULEBASE KNEE_RB and RULEBASE OWLPRIME.
-- STATUS INVALID means KNEE_KG changed after the entailment was created;
-- SEM_MATCH with SEM_RULEBASES then reports an error. Run 09a again.
COLUMN index_name FORMAT A12
COLUMN status     FORMAT A10
COLUMN data_type  FORMAT A10
COLUMN data_name  FORMAT A12
SELECT i.index_name, i.status, i.model_count, i.rulebase_count, d.data_type, d.data_name
FROM   &network_name.#sem_rules_index_info i
JOIN   &network_name.#sem_rules_index_datasets d
       ON d.index_name = i.index_name
WHERE  i.index_name = 'KNEE_KG_RIX'
ORDER  BY d.data_type, d.data_name;

PROMPT
PROMPT --- 5d. Triples per predicate without and with the entailment
-- The same SPARQL query runs twice on KNEE_KG: once without rulebases
-- (asserted triples only), once with SEM_RULEBASES('OWLPRIME', 'KNEE_RB')
-- (asserted plus inferred triples). Only predicates that gain triples are
-- listed. Expected: 9 inferred triples in 4 rows (computed from knee_kg.nt):
--   rdfs:subClassOf              6 -> 8  OWLPRIME closes the class hierarchy
--   kg:matchesMechanismOf        0 -> 3  KNEE_RB, mechanism_rule
--   kg:showsCounterIndicatorOf   0 -> 2  KNEE_RB, counter_indicator_rule
--   kg:showsIndicatorOf          0 -> 2  KNEE_RB, strong_indicator_rule
-- kg:partOf is transitive, but all its triples point directly to the
-- knee joint, so OWLPRIME derives no further partOf triples.
COLUMN predicate FORMAT A55
SELECT w.p                                       AS predicate,
       NVL(TO_NUMBER(a.n), 0)                    AS asserted,
       TO_NUMBER(w.n)                            AS with_entailment,
       TO_NUMBER(w.n) - NVL(TO_NUMBER(a.n), 0)   AS inferred
FROM   TABLE(SEM_MATCH(
         'SELECT ?p (COUNT(*) AS ?n) WHERE { ?s ?p ?o } GROUP BY ?p',
         SEM_MODELS('KNEE_KG'), SEM_RULEBASES('OWLPRIME', 'KNEE_RB'), NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name')) w
LEFT JOIN TABLE(SEM_MATCH(
         'SELECT ?p (COUNT(*) AS ?n) WHERE { ?s ?p ?o } GROUP BY ?p',
         SEM_MODELS('KNEE_KG'), NULL, NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name')) a
       ON a.p = w.p
WHERE  TO_NUMBER(w.n) > NVL(TO_NUMBER(a.n), 0)
ORDER  BY predicate;

PROMPT
PROMPT --- 5e. Effect on a query: which ligaments are a "ligament of knee joint"?
-- Without the entailment only the direct subclasses match (4 rows). With
-- OWLPRIME the anterior and posterior cruciate ligament match as well:
-- they are subclasses of "cruciate ligament", which is a subclass of
-- "ligament of knee joint" (6 rows). In the same way the query of 5b
-- returns no rows without SEM_RULEBASES: the KNEE_RB triples exist only
-- in the entailment.
-- Expected: asserted  cruciate ligament, fibular collateral ligament,
--                     patellar ligament, tibial collateral ligament
--           inferred  anterior cruciate ligament, posterior cruciate ligament
COLUMN ligament FORMAT A30
COLUMN source   FORMAT A20
SELECT w.ligament,
       CASE WHEN a.ligament IS NULL THEN 'inferred (OWLPRIME)' ELSE 'asserted' END AS source
FROM   TABLE(SEM_MATCH(
         'PREFIX kg:   <https://doag2026.example/knee#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          SELECT ?ligament
          WHERE {
            ?c rdfs:subClassOf kg:LigamentOfKneeJoint .
            ?c rdfs:label      ?ligament .
            FILTER (lang(?ligament) = "en")
          }',
         SEM_MODELS('KNEE_KG'), SEM_RULEBASES('OWLPRIME', 'KNEE_RB'), NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name')) w
LEFT JOIN TABLE(SEM_MATCH(
         'PREFIX kg:   <https://doag2026.example/knee#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          SELECT ?ligament
          WHERE {
            ?c rdfs:subClassOf kg:LigamentOfKneeJoint .
            ?c rdfs:label      ?ligament .
            FILTER (lang(?ligament) = "en")
          }',
         SEM_MODELS('KNEE_KG'), NULL, NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name')) a
       ON a.ligament = w.ligament
ORDER  BY source, w.ligament;

WHENEVER SQLERROR EXIT FAILURE ROLLBACK

PROMPT
PROMPT Done. KNEE_KG loaded, entailment created. Continue with 09b_load_fma.sql.

SPOOL OFF
