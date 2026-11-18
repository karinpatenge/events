--------------------------------------------------------------------------------
-- File       : 09b_load_fma.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Loads the Foundational Model of Anatomy FMA into the RDF
--              network from 08_create_rdf_network.sql and completes the
--              RDF part:
--                0. checks; drops the graph collection and FMA and creates
--                   FMA again, empty
--                1. FMA (612,982 triples) with SEM_APIS.BULK_LOAD_RDF_GRAPH
--                2. graph collection KNEE_FMA_VM, if KNEE_KG is loaded
--                3. full-text index on the RDF literals (orardf:textContains)
--                4. statistics
--                5. checks and test queries
--              The knee knowledge graph is loaded by 09a_load_knee_kg.sql.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Tool       : SQLcl (LOAD is a SQLcl command)
-- Run        : in folder scripts\sql, so that the relative paths are correct:
--                cd <project>\scripts\sql
--                sql doag2026@<tns_alias> @09b_load_fma.sql
-- Before     : 08_create_rdf_network.sql, usually 09a_load_knee_kg.sql.
--              data/_load/fma_nt.csv must exist (= unzipped
--              data/rdf/fma.nt.gz, see README.md).
-- Re-runnable: yes, independently of 09a. FMA is created again empty on
--              every run; KNEE_KG and the entailment stay.
-- Duration   : a few minutes (LOAD of 92 MB, bulk load, text index)
-- Note       : On Autonomous AI Database the SEM_MATCH test queries need
--              Oracle Java (00_create_user.sql, section 6). Loading and
--              index work without it.
-- Log        : logs/sql/09b_load_fma.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET TIMING OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/09b_load_fma.log

-- Path to the data folder, relative to the current directory (folder scripts/sql)
DEFINE data_dir = ../../data

-- SQLcl LOAD reads only delimited text files (SET LOADFORMAT JSON applies
-- to UNLOAD only) and checks the file extension: it does not accept .nt
-- with LOADFORMAT DELIMITED. It therefore loads a copy with identical
-- content and extension .csv from data/_load (README.md, prerequisites).

-- Expected number of triples. Adjust after changing the dataset.
DEFINE exp_fma_triples  = 612982

-- Y = create the full-text index on the RDF literals (takes a few minutes
-- because of the FMA)
DEFINE text_index = Y

-- RDF network: on Autonomous AI Database only the default network
-- RDF_NETWORK. The owner is the demo user DOAG2026 by default
-- (in upper case, must match 00_create_user.sql).
DEFINE network_owner = DOAG2026
DEFINE network_name  = RDF_NETWORK

PROMPT
PROMPT === 09b Load the Foundational Model of Anatomy FMA ===

--==============================================================================
-- 0. Prerequisites; FMA empty again
--    The graph collection depends on FMA and is dropped first; step 2
--    creates it again.
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
  DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name exists');
END;
/

PROMPT
PROMPT --- 0. Drop graph collection and FMA; create FMA empty
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
    SEM_APIS.DROP_RDF_GRAPH('FMA', network_owner => '&network_owner', network_name => '&network_name');
    report('RDF graph FMA');
  EXCEPTION WHEN OTHERS THEN report('RDF graph FMA', SQLERRM);
  END;

  SEM_APIS.CREATE_RDF_GRAPH(
    rdf_graph_name => 'FMA',
    table_name     => NULL,
    column_name    => NULL,
    network_owner  => '&network_owner',
    network_name   => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      RDF graph FMA created empty (view &network_name.#RDFT_FMA)');
END;
/

--==============================================================================
-- 1. FMA: N-Triples line by line, then bulk load from the staging table
--    PARSE:             validate the triples, because they did not come
--                       through SEM_APIS.LOAD_INTO_STAGING_TABLE
--    MBV_METHOD=SHADOW: faster value loading strategy for large volumes
--==============================================================================

PROMPT
PROMPT --- 1. Foundational Model of Anatomy FMA
-- Unzipped data/rdf/fma.nt.gz (92 MB)
SET LOADFORMAT DEFAULT
SET LOADFORMAT DELIMITED DELIMITER | ENCLOSURES OFF COLUMN_NAMES OFF ENCODING UTF8
SET LOAD DEFAULT
SET LOAD BATCH_ROWS 5000 BATCHES_PER_COMMIT 10 ERRORS 0 TRUNCATE ON

LOAD stg_text_lines &data_dir/_load/fma_nt.csv

TRUNCATE TABLE stg_rdf_triples;
INSERT /*+ APPEND */ INTO stg_rdf_triples (rdf$stc_sub, rdf$stc_pred, rdf$stc_obj)
SELECT REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 1),
       REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 2),
       REGEXP_SUBSTR(line_text, '^(\S+)\s+(\S+)\s+(.*\S)\s*\.\s*$', 1, 1, NULL, 3)
FROM   stg_text_lines
WHERE  REGEXP_LIKE(line_text, '^\s*[<_]');
COMMIT;

DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM stg_rdf_triples;
  IF l_cnt <> &exp_fma_triples THEN
    RAISE_APPLICATION_ERROR(-20035, 'FMA: ' || l_cnt || ' triples in the staging table, expected &exp_fma_triples');
  END IF;

  SEM_APIS.BULK_LOAD_RDF_GRAPH(
    rdf_graph_name => 'FMA',
    table_owner    => USER,
    table_name     => 'STG_RDF_TRIPLES',
    flags          => 'PARSE MBV_METHOD=SHADOW',
    network_owner  => '&network_owner',
    network_name   => '&network_name');

  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_fma' INTO l_cnt;
  DBMS_OUTPUT.PUT_LINE(CASE WHEN l_cnt = &exp_fma_triples THEN 'OK      ' ELSE 'WARNING ' END
                       || RPAD('RDF graph FMA (bulk load)', 40) || LPAD(l_cnt, 8)
                       || CASE WHEN l_cnt <> &exp_fma_triples THEN ' (duplicates removed?)' END);
END;
/

-- Staging contents are no longer needed
TRUNCATE TABLE stg_text_lines;
TRUNCATE TABLE stg_rdf_triples;

--==============================================================================
-- 2. Graph collection KNEE_FMA_VM (formerly "virtual model")
--    This lets one query see the knee knowledge graph, the FMA and the
--    inferred triples at once, e.g. from the pattern via the cruciate
--    ligament to the FMA ID. Needs both graphs: whichever of 09a and 09b
--    runs last creates it.
--==============================================================================

PROMPT
PROMPT --- 2. Graph collection KNEE_FMA_VM
DECLARE
  l_knee PLS_INTEGER;
  l_fma  PLS_INTEGER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_knee_kg WHERE ROWNUM = 1' INTO l_knee;
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM &network_name.#rdft_fma WHERE ROWNUM = 1' INTO l_fma;
  IF l_knee = 0 OR l_fma = 0 THEN
    DBMS_OUTPUT.PUT_LINE('OK      skipped: graph KNEE_KG is still empty, 09a_load_knee_kg.sql creates the collection');
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
-- 3. Full-text index on the RDF literals
--    Enables FILTER(orardf:textContains(?label, "Plopp")) in SPARQL.
--    Needs EXECUTE on CTXSYS.CTX_DDL (00_create_user.sql). The index is on
--    the value table of the network, so it covers KNEE_KG and FMA.
--==============================================================================

PROMPT
PROMPT --- 3. Full-text index on RDF literals (text_index = &text_index)
BEGIN
  IF UPPER('&text_index') = 'Y' THEN
    BEGIN
      SEM_APIS.ADD_DATATYPE_INDEX(
        'http://xmlns.oracle.com/rdf/text',
        network_owner => '&network_owner',
        network_name  => '&network_name');
      DBMS_OUTPUT.PUT_LINE('OK      Datatype index http://xmlns.oracle.com/rdf/text created');
    EXCEPTION
      WHEN OTHERS THEN
        IF INSTR(LOWER(SQLERRM), 'exist') > 0 THEN
          DBMS_OUTPUT.PUT_LINE('OK      Datatype index http://xmlns.oracle.com/rdf/text already exists');
        ELSE
          RAISE;
        END IF;
    END;
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK      skipped');
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
PROMPT --- 5a. Triples per graph
SELECT 'KNEE_KG' AS rdf_graph, (SELECT COUNT(*) FROM &network_name.#rdft_knee_kg) AS triples FROM dual
UNION ALL
SELECT 'FMA', (SELECT COUNT(*) FROM &network_name.#rdft_fma) FROM dual;

PROMPT
PROMPT --- 5b. From the ACL pattern via the cruciate ligament to the FMA (graph collection)
COLUMN structure FORMAT A55
COLUMN fma       FORMAT A45
COLUMN fma_label FORMAT A40
SELECT structure, fma, fma_label
FROM   TABLE(SEM_MATCH(
         'PREFIX kg:   <https://doag2026.example/knee#>
          PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
          PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
          SELECT ?structure ?fma ?fma_label
          WHERE {
            kg:Pattern_ACL kg:affects       ?structure .
            ?structure     skos:exactMatch  ?fma .
            ?fma           rdfs:label       ?fma_label .
          }',
         SEM_MODELS('KNEE_FMA_VM'), NULL, NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name'));

PROMPT
PROMPT --- 5c. Full text in RDF: which finding is also called "Plopp" (pop)? (only with text_index = Y)
COLUMN finding   FORMAT A50
COLUMN alt_label FORMAT A20
SELECT finding, alt_label
FROM   TABLE(SEM_MATCH(
         'PREFIX skos:   <http://www.w3.org/2004/02/skos/core#>
          PREFIX orardf: <http://xmlns.oracle.com/rdf/>
          SELECT ?finding ?alt_label
          WHERE {
            ?finding skos:altLabel ?alt_label .
            FILTER (orardf:textContains(?alt_label, "Plopp"))
          }',
         SEM_MODELS('KNEE_KG'), NULL, NULL, NULL, NULL, ' ', NULL, NULL,
         '&network_owner', '&network_name'));

WHENEVER SQLERROR EXIT FAILURE ROLLBACK

PROMPT
PROMPT Done. FMA loaded, graph collection and full-text index created.

SPOOL OFF
