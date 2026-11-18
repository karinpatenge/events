--------------------------------------------------------------------------------
-- File       : 05_create_embeddings.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Loads the embedding model all-MiniLM-L12-v2 (ONNX) into the
--              database and uses it to fill the column
--              SYMPTOM_REPORTS.REPORT_EMBEDDING from REPORT_TEXT.
-- Based on   : Blog post "Getting started with vectors in 23ai"
--              https://blogs.oracle.com/coretec/getting-started-with-vectors-in-23ai
--              - model all-MiniLM-L12-v2, provided by Oracle as ONNX file with
--                tokenizer and post-processing
--              - import with DBMS_VECTOR.LOAD_ONNX_MODEL from a directory
--              - embeddings with VECTOR_EMBEDDING(<model> USING <text> AS data)
--              - 384 dimensions, FLOAT32, distance metric COSINE
--              Autonomous AI Database has no own server directory: the file
--              is copied with DBMS_CLOUD.GET_OBJECT from object storage into
--              DATA_PUMP_DIR and imported from there.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, after 03_load_data.sql
--                sql doag2026@<tns_alias> @05_create_embeddings.sql
-- Privileges : CREATE MINING MODEL (DB_DEVELOPER_ROLE), EXECUTE ON DBMS_CLOUD,
--              READ and WRITE on DATA_PUMP_DIR (all from 00_create_user.sql)
-- Re-runnable: yes. An existing model is kept, only rows without an
--              embedding are calculated. With DEFINE rebuild = Y the model
--              and all embeddings are created again.
-- Log        : logs/sql/05_create_embeddings.log in the project folder,
--              overwritten on every run
--------------------------------------------------------------------------------

SET DEFINE ON
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/05_create_embeddings.log

-- Model. Name in the database, file name and location in object storage.
-- The location is a pre-authenticated request (PAR) of Oracle Machine
-- Learning. If the link is no longer valid: take the current link from the
-- Oracle Machine Learning blog "Pre-built embedding generation model"
-- or put the file into your own bucket and enter its PAR here.
DEFINE model_name = ALL_MINILM_L12_V2
DEFINE onnx_file  = all_MiniLM_L12_v2.onnx
DEFINE model_uri  = https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/p/eLddQappgBJ7jNi6Guz9m9LOtYe2u8LWY19GfgU8flFK4N9YgP4kTlrE9Px3pE12/n/adwc4pm/b/OML-Resources/o/

-- Y = reload the model and recalculate all embeddings
DEFINE rebuild = Y

PROMPT
PROMPT === 05 Embeddings for SYMPTOM_REPORTS with &model_name ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

-- No parallel DML (as in 03). Autonomous AI Database enables parallel DML by
-- default for the HIGH and MEDIUM services. A parallel UPDATE of
-- SYMPTOM_REPORTS after the reset UPDATE in the same transaction fails with
-- ORA-12839. 1,459 short texts are embedded quickly enough in serial.
ALTER SESSION DISABLE PARALLEL DML;

--==============================================================================
-- 1. Load the ONNX model (only if not present yet or rebuild = Y)
--==============================================================================

PROMPT
PROMPT --- 1. Load embedding model
DECLARE
  l_cnt PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_mining_models WHERE model_name = UPPER('&model_name');

  IF l_cnt > 0 AND UPPER('&rebuild') <> 'Y' THEN
    DBMS_OUTPUT.PUT_LINE('OK      Model &model_name already exists');
  ELSE
    IF l_cnt > 0 THEN
      DBMS_DATA_MINING.DROP_MODEL(model_name => UPPER('&model_name'), force => TRUE);
      DBMS_OUTPUT.PUT_LINE('OK      Old model &model_name dropped');
    END IF;

    -- Copy the ONNX file from object storage into DATA_PUMP_DIR
    DBMS_CLOUD.GET_OBJECT(
      credential_name => NULL,
      object_uri      => '&model_uri' || '&onnx_file',
      directory_name  => 'DATA_PUMP_DIR');
    DBMS_OUTPUT.PUT_LINE('OK      &onnx_file copied to DATA_PUMP_DIR');

    -- Import the model (tokenizer and post-processing are included in the file)
    DBMS_VECTOR.LOAD_ONNX_MODEL(
      directory  => 'DATA_PUMP_DIR',
      file_name  => '&onnx_file',
      model_name => UPPER('&model_name'));
    DBMS_OUTPUT.PUT_LINE('OK      Model &model_name imported');

    -- The file is no longer needed afterwards
    DBMS_CLOUD.DELETE_FILE(directory_name => 'DATA_PUMP_DIR', file_name => '&onnx_file');
  END IF;
END;
/

PROMPT --- Model and output format (expected: EMBEDDING, ONNX, VECTOR(384,FLOAT32))
SELECT m.model_name, m.mining_function, m.algorithm, a.data_type, a.vector_info
FROM   user_mining_models m
LEFT   JOIN user_mining_model_attributes a
       ON  a.model_name = m.model_name
       AND a.attribute_name = 'ORA$ONNXTARGET'
WHERE  m.model_name = UPPER('&model_name');

--==============================================================================
-- 2. Fill REPORT_EMBEDDING
--==============================================================================

PROMPT
PROMPT --- 2. Calculate embeddings
BEGIN
  IF UPPER('&rebuild') = 'Y' THEN
    UPDATE symptom_reports SET report_embedding = NULL;
    DBMS_OUTPUT.PUT_LINE('OK      ' || SQL%ROWCOUNT || ' embeddings reset');
    COMMIT;
  END IF;
END;
/

-- VECTOR_EMBEDDING returns a VECTOR directly; TO_VECTOR as in the blog is not needed.
UPDATE symptom_reports
SET    report_embedding = VECTOR_EMBEDDING(&model_name USING report_text AS data)
WHERE  report_embedding IS NULL;
COMMIT;

DECLARE
  l_missing PLS_INTEGER;
  l_dims    PLS_INTEGER;
  l_total   PLS_INTEGER;
BEGIN
  -- COUNT(report_embedding) is not allowed for VECTOR (ORA-22849),
  -- therefore count with IS NULL
  SELECT COUNT(*),
         COUNT(CASE WHEN report_embedding IS NULL THEN 1 END),
         MAX(VECTOR_DIMENSION_COUNT(report_embedding))
  INTO   l_total, l_missing, l_dims
  FROM   symptom_reports;

  IF l_missing > 0 THEN
    RAISE_APPLICATION_ERROR(-20020, l_missing || ' of ' || l_total || ' reports without embedding.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      ' || l_total || ' reports with embedding, ' || l_dims || ' dimensions');
END;
/

--==============================================================================
-- 3. Test: the five reports closest to Jonas' report
--    (exact search, COSINE as used when training the model). Jonas' vector
--    is passed into the query through a scalar subquery.
--==============================================================================

PROMPT
PROMPT --- 3. Test: most similar reports to Jonas' symptoms
COLUMN report_id       FORMAT A12
COLUMN distance        FORMAT 0.0000
COLUMN diagnosis_label FORMAT A30
COLUMN report_text     FORMAT A70 TRUNCATED

SELECT s.report_id,
       VECTOR_DISTANCE(s.report_embedding,
                       (SELECT j.report_embedding
                        FROM   symptom_reports j
                        WHERE  j.report_id = 'SR-2026-11-16-0001'),
                       COSINE) AS distance,
       d.diagnosis_label,
       s.report_text
FROM   symptom_reports s
LEFT   JOIN diagnoses d ON d.report_id = s.report_id
WHERE  s.source = 'fhir'
ORDER  BY distance
FETCH  FIRST 5 ROWS ONLY;

PROMPT
PROMPT Done.

SPOOL OFF
