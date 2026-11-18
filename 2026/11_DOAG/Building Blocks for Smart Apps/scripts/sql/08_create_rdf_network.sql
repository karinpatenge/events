--------------------------------------------------------------------------------
-- File       : 08_create_rdf_network.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Sets up the RDF model for demo step 4:
--                1. RDF network RDF_NETWORK (default network on
--                   Autonomous AI Database), owner DOAG2026
--                2. staging table for the bulk load
--                3. drop existing graphs, entailment and rulebase
--                4. RDF graphs KNEE_KG (knee knowledge graph) and FMA
--                   (Foundational Model of Anatomy)
--                5. own rulebase KNEE_RB with three rules
--              09a_load_knee_kg.sql and 09b_load_fma.sql load the data.
--              There is no inference step here: the entailment KNEE_KG_RIX
--              (SEM_APIS.CREATE_ENTAILMENT with OWLPRIME and KNEE_RB) needs
--              the loaded triples and is created in 09a, section 2.
-- Blueprint  : Structure as in optional_example_family_rdf_knowledge_graph.sql
--              (github.com/karinpatenge/events, 2025/06_AOUG), with the
--              names from 23ai on: CREATE_RDF_NETWORK instead of
--              CREATE_SEM_NETWORK, CREATE_RDF_GRAPH instead of CREATE_SEM_MODEL.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user (network owner)
--                sql doag2026@<tns_alias> @08_create_rdf_network.sql
-- Re-runnable: yes. The network is kept, graphs, entailment and rulebase
--              are recreated empty on every run. With DEFINE rebuild = Y
--              the network is recreated as well.
-- Log        : logs/sql/08_create_rdf_network.log in the project folder,
--              overwritten on every run
--
-- Native data type SDO_RDF_TRIPLE_S
--   On Autonomous AI Database there is only the network RDF_NETWORK, and
--   it is schema-private (it belongs to one user, here DOAG2026). In a
--   schema-private network, table_name and column_name in
--   SEM_APIS.CREATE_RDF_GRAPH must be NULL.
--   An own application table like FAMILY_TPL (triple SDO_RDF_TRIPLE_S) in
--   the blueprint can therefore no longer be attached. Instead,
--   CREATE_RDF_GRAPH creates the updatable view RDF_NETWORK#RDFT_<GRAPH>
--   per graph. Its column TRIPLE has the type SDO_RDF_TRIPLE_S; INSERT and
--   DELETE with the constructor SDO_RDF_TRIPLE_S(...) run through this
--   view (see 09a).
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/08_create_rdf_network.log

-- RDF network: on Autonomous AI Database only the default network
-- RDF_NETWORK. The owner is the demo user DOAG2026 by default
-- (in upper case, must match 00_create_user.sql).
DEFINE network_owner = DOAG2026
DEFINE network_name  = RDF_NETWORK

-- Y = drop the network with all graphs and create it again
DEFINE rebuild = Y

PROMPT
PROMPT === 08 RDF network RDF_NETWORK and RDF model ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
  IF USER <> UPPER('&network_owner') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Connected as ' || USER || '. The RDF network &network_name belongs to '
                                    || UPPER('&network_owner') || '; run this script as that user.');
  END IF;
END;
/

--==============================================================================
-- 1. RDF network RDF_NETWORK in tablespace DATA, owner DOAG2026
--    The network owner creates the network itself. Privileges: CONNECT,
--    RESOURCE, CREATE VIEW and quota on DATA (00_create_user.sql).
--==============================================================================

PROMPT
PROMPT --- 1. RDF network RDF_NETWORK
DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_tables WHERE table_name = '&network_name.#RDF_VALUE$';

  IF l_cnt > 0 AND UPPER('&rebuild') = 'Y' THEN
    -- cascade => TRUE also drops graphs, entailments and rulebases
    SEM_APIS.DROP_RDF_NETWORK(cascade => TRUE, network_owner => '&network_owner', network_name => '&network_name');
    DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name dropped (rebuild = Y)');
    l_cnt := 0;
  END IF;

  IF l_cnt = 0 THEN
    SEM_APIS.CREATE_RDF_NETWORK(
      tablespace_name => 'DATA',
      network_owner   => '&network_owner',
      network_name    => '&network_name');
    DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name created');
  ELSE
    DBMS_OUTPUT.PUT_LINE('OK      RDF network &network_name already exists');
  END IF;
END;
/

--==============================================================================
-- 2. Staging table for SEM_APIS.BULK_LOAD_RDF_GRAPH
--    Column names and format (terms in N-Triples syntax) are defined by
--    the Oracle documentation. Annotations directly at creation time.
--==============================================================================

PROMPT
PROMPT --- 2. Staging table STG_RDF_TRIPLES
CREATE TABLE IF NOT EXISTS stg_rdf_triples (
  rdf$stc_sub   VARCHAR2(4000) NOT NULL
                ANNOTATIONS (Display 'Subject', Description 'IRI or blank node in N-Triples syntax'),
  rdf$stc_pred  VARCHAR2(4000) NOT NULL
                ANNOTATIONS (Display 'Predicate', Description 'IRI in N-Triples syntax'),
  rdf$stc_obj   VARCHAR2(4000) NOT NULL
                ANNOTATIONS (Display 'Object', Description 'IRI, blank node or literal in N-Triples syntax'))
ANNOTATIONS (
  Display     'Staging RDF triples',
  Description 'Subject, predicate, object for SEM_APIS.BULK_LOAD_RDF_GRAPH, only for 09a_load_knee_kg.sql and 09b_load_fma.sql',
  Source      'data/rdf/knee_kg.nt, data/rdf/fma.nt',
  License     'CC0 or CC BY 3.0 (FMA)',
  Feature     'RDF Graph');

--==============================================================================
-- 3. Drop existing objects (like "Start from scratch" in the blueprint)
--    Order: graph collection, entailment, graphs, rulebase.
--    If an object is missing (first run), the block only reports it.
--==============================================================================

PROMPT
PROMPT --- 3. Drop existing graphs, entailment and rulebase
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

  FOR g IN (SELECT COLUMN_VALUE AS graph_name
            FROM   TABLE(SYS.ODCIVARCHAR2LIST('KNEE_KG', 'FMA'))) LOOP
    BEGIN
      SEM_APIS.DROP_RDF_GRAPH(g.graph_name, network_owner => '&network_owner', network_name => '&network_name');
      report('RDF graph ' || g.graph_name);
    EXCEPTION WHEN OTHERS THEN report('RDF graph ' || g.graph_name, SQLERRM);
    END;
  END LOOP;

  BEGIN
    SEM_APIS.DROP_RULEBASE('KNEE_RB', network_owner => '&network_owner', network_name => '&network_name');
    report('Rulebase KNEE_RB');
  EXCEPTION WHEN OTHERS THEN report('Rulebase KNEE_RB', SQLERRM);
  END;
END;
/

--==============================================================================
-- 4. RDF graphs (formerly "semantic models")
--    table_name and column_name are NULL (mandatory in the schema-private
--    network). Oracle creates the views RDF_NETWORK#RDFT_KNEE_KG and
--    RDF_NETWORK#RDFT_FMA with the column TRIPLE (SDO_RDF_TRIPLE_S).
--==============================================================================

PROMPT
PROMPT --- 4. RDF graphs KNEE_KG and FMA
BEGIN
  -- Knee knowledge graph: anatomy, findings, injury patterns, Jonas' report
  SEM_APIS.CREATE_RDF_GRAPH(
    rdf_graph_name => 'KNEE_KG',
    table_name     => NULL,
    column_name    => NULL,
    network_owner  => '&network_owner',
    network_name   => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      RDF graph KNEE_KG created (view &network_name.#RDFT_KNEE_KG)');

  -- Foundational Model of Anatomy: shared vocabulary for the anatomy
  SEM_APIS.CREATE_RDF_GRAPH(
    rdf_graph_name => 'FMA',
    table_name     => NULL,
    column_name    => NULL,
    network_owner  => '&network_owner',
    network_name   => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      RDF graph FMA created (view &network_name.#RDFT_FMA)');
END;
/

--==============================================================================
-- 5. Own rulebase KNEE_RB
--    The rules derive from Jonas' report which injury pattern a finding
--    fits or argues against. A rulebase only stores rules; it derives
--    nothing by itself. The entailment KNEE_KG_RIX applies OWLPRIME and
--    KNEE_RB to the triples of KNEE_KG; it needs the loaded data and is
--    therefore created in 09a_load_knee_kg.sql, section 2, and checked in
--    09a, section 5c-5e.
--    OWLPRIME closes the class hierarchy rdfs:subClassOf (anterior cruciate
--    ligament -> cruciate ligament -> ligament of knee joint) and the
--    transitive property kg:partOf; KNEE_RB adds the domain rules.
--    Query results change only where the query uses the entailment:
--    SEM_MATCH with SEM_RULEBASES('OWLPRIME', 'KNEE_RB'), or the graph
--    collection KNEE_FMA_VM, which contains KNEE_KG_RIX.
--==============================================================================

PROMPT
PROMPT --- 5. Rulebase KNEE_RB
BEGIN
  SEM_APIS.CREATE_RULEBASE('KNEE_RB', network_owner => '&network_owner', network_name => '&network_name');
  DBMS_OUTPUT.PUT_LINE('OK      Rulebase KNEE_RB created');
END;
/

-- Rule 1: a reported finding is a strong indicator of a pattern
INSERT INTO &network_name.#semr_knee_rb VALUES (
  'strong_indicator_rule',
  '(?r kg:reportsFinding ?f) (?p kg:hasStrongIndicator ?f)',
  NULL,
  '(?r kg:showsIndicatorOf ?p)',
  SEM_ALIASES(SEM_ALIAS('kg', 'https://doag2026.example/knee#')));

-- Rule 2: a reported finding argues against a pattern
INSERT INTO &network_name.#semr_knee_rb VALUES (
  'counter_indicator_rule',
  '(?r kg:reportsFinding ?f) (?p kg:argumentAgainst ?f)',
  NULL,
  '(?r kg:showsCounterIndicatorOf ?p)',
  SEM_ALIASES(SEM_ALIAS('kg', 'https://doag2026.example/knee#')));

-- Rule 3: the reported injury mechanism matches the pattern
INSERT INTO &network_name.#semr_knee_rb VALUES (
  'mechanism_rule',
  '(?r kg:reportsMechanism ?m) (?p kg:requiresMechanism ?m)',
  NULL,
  '(?r kg:matchesMechanismOf ?p)',
  SEM_ALIASES(SEM_ALIAS('kg', 'https://doag2026.example/knee#')));

COMMIT;

--==============================================================================
-- 6. Checks
--==============================================================================

PROMPT
PROMPT --- 6. Graph views with the data type SDO_RDF_TRIPLE_S
SELECT table_name AS view_name, column_name, data_type_owner, data_type
FROM   user_tab_columns
WHERE  table_name IN ('&network_name.#RDFT_KNEE_KG', '&network_name.#RDFT_FMA')
ORDER  BY table_name, column_id;

PROMPT --- Rules in KNEE_RB
COLUMN rule_name   FORMAT A24
COLUMN antecedents FORMAT A60
COLUMN consequents FORMAT A40
SELECT rule_name, antecedents, consequents
FROM   &network_name.#semr_knee_rb
ORDER  BY rule_name;

PROMPT
PROMPT Done. Continue with 09a_load_knee_kg.sql (loads KNEE_KG, creates the entailment), then 09b_load_fma.sql.

SPOOL OFF
