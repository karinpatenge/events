/*
 * Hands-on workshop "Create a lexical graph by chunking a text, extracting nodes, and edges to build a graph" by Eduard Cuba
 * published on Oracle LiveLabs (https://livelabs.oracle.com/pls/apex/f?p=133:180:::::wid:4174)
 * Adapted for the TDWI 2025 Conference by Karin Patenge (June 2025)
 *
 * Oracle Cloud services used:
 * 1. Oracle Autonomous Database (version 23ai) (https://www.oracle.com/autonomous-database/free-trial/)
 * 2. Object Storage
 * 3. GenAI service
 *
 * Development:
 * - SQL
 * - TinyBERT (Local inside the database)
 *     * BERT -> Bidirectional Encoder Representations from Transformers.
 *     * TinyBERT is a small version of BERT.
 *     * Official TinyBERT paper: https://arxiv.org/pdf/1909.10351
 */



--
-- Start with Lab 2
--

-- ================================================================
-- !! Execute as user ADMIN (once)
-- ================================================================

--
-- Set up prerequisites
--

-- Grant privileges to the database user
GRANT CREATE ANY MINING MODEL TO tdwiuser;
GRANT SELECT ANY MINING MODEL TO tdwiuser;
GRANT CREATE ANY DIRECTORY TO tdwiuser;
GRANT DROP ANY DIRECTORY TO tdwiuser;
GRANT EXECUTE ON DBMS_CLOUD TO tdwiuser;
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO tdwiuser;
GRANT EXECUTE ON DBMS_CLOUD_AI TO tdwiuser;

-- ================================================================
-- !! All following statements need to be executed as user TDWIUSER
-- ================================================================

--
-- Load the book text and TinyBERT model into the Oracle Database
--

-- Set up directory to hold the ONNX model and the book fragment
DROP DIRECTORY IF EXISTS GRAPHDIR;

CREATE OR REPLACE DIRECTORY GRAPHDIR AS 'scratch/';

BEGIN

  -- Download the sample text
  DBMS_CLOUD.GET_OBJECT(
    object_uri => 'https://objectstorage.us-chicago-1.oraclecloud.com/n/idb6enfdcxbl/b/Livelabs/o/sample-data/blue.txt',
    directory_name => 'GRAPHDIR'
  );

  -- Download the TinyBERT model as ONNX from object storage bucket
  DBMS_CLOUD.GET_OBJECT (
    object_uri => 'https://objectstorage.us-chicago-1.oraclecloud.com/n/idb6enfdcxbl/b/Livelabs/o/onnx-embedding-models/tinybert.onnx',
    directory_name => 'GRAPHDIR'
  );

  -- Load ONNX model into the user schema
  DBMS_VECTOR.DROP_ONNX_MODEL(
    model_name => 'TINYBERT_MODEL'
  );

  -- Load ONNX model into the user schema
  DBMS_VECTOR.LOAD_ONNX_MODEL(
    'GRAPHDIR',
    'tinybert.onnx',
    'TINYBERT_MODEL',
    json('{"function":"embedding","embeddingOutput":"embedding","input":{"input":["DATA"]}}')
  );

END;
/

-- List files in the database directory
SELECT * FROM DBMS_CLOUD.LIST_FILES('GRAPHDIR');

-- Check ONNX model
SELECT
  model_name,
  algorithm,
  mining_function
FROM
  user_mining_models;

-- Show model stats
SELECT
  *
FROM
  DM$VMTINYBERT_MODEL
ORDER BY
  name;


-- More information can be found here:
-- 1. https://oracle-base.com/articles/23/ai-vector-search-23
-- 2. https://docs.oracle.com/en/database/oracle/oracle-database/23/vecse/import-onnx-models-oracle-database-end-end-example.html


--
-- Set up credentials to use OCI´s GenAI Service
--

-- Check your credentials
SELECT
  credential_name,
  username,
  comments
FROM
  all_credentials;


-- Create your credentials
BEGIN

  DBMS_CLOUD.DROP_CREDENTIAL( credential_name => 'GENAI_CRED' );

  -- Replace placeholders with proper values
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'GENAI_CRED',
    user_ocid       => '<user_ocid>',
    tenancy_ocid    => '<tenancy_ocid>',
    private_key     => '<private_key>',
    fingerprint     => '<fingerprint>'
  );
END;
/

-- Set up an AI Profile using OCI GenAI and your credentials
BEGIN
  DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'GENAI_PROFILE');

  DBMS_CLOUD_AI.CREATE_PROFILE(
      profile_name =>'GENAI_PROFILE',
      attributes   =>'{
          "provider": "oci",
          "credential_name": "GENAI_CRED",
          "conversation" : "true",
          "comments":"true"
      }'
  );
END;
/

-- Set the AI Profile
BEGIN
  DBMS_CLOUD_AI.SET_PROFILE(
      profile_name => 'GENAI_PROFILE'
  );
END;
/

-- Re-check your credentials
SELECT
  credential_name,
  username,
  comments
FROM
  all_credentials;


--
-- Process the book text
--

-- Clean up the tables
DROP TABLE IF EXISTS sholmes_tab;
DROP TABLE IF EXISTS sholmes_tab_clob;
DROP TABLE IF EXISTS sholmes_tab_chunks;

-- Set up tables to store the book text (blob, clob) and text chunks
CREATE TABLE sholmes_tab (
  id NUMBER,
  data BLOB
);
CREATE TABLE sholmes_tab_clob (
  id NUMBER,
  data CLOB
);
CREATE TABLE sholmes_tab_chunks (
  doc_id NUMBER,
  chunk_id NUMBER,
  chunk_data VARCHAR2(4000),
  chunk_embedding VECTOR
);

-- Insert the book text as BLOB into a table
TRUNCATE TABLE sholmes_tab DROP STORAGE;
INSERT INTO sholmes_tab VALUES (1, TO_BLOB(BFILENAME('GRAPHDIR', 'blue.txt')));
COMMIT;

SELECT * FROM sholmes_tab;

-- Convert the BLOB to CLOB. Column DATA contains the book text as CLOB.
TRUNCATE TABLE sholmes_tab_clob DROP STORAGE;
INSERT INTO sholmes_tab_clob SELECT id, TO_CLOB(data) FROM sholmes_tab;
COMMIT;

SELECT * FROM sholmes_tab_clob;

-- Split into text chunks and generate the embeddings
TRUNCATE TABLE sholmes_tab_chunks DROP STORAGE;
INSERT INTO sholmes_tab_chunks
SELECT
  dt.id AS doc_id,
  et.embed_id AS chunk_id,
  et.embed_data AS chunk_data,
  -- Generate embeddings
  TO_VECTOR (et.embed_vector) AS chunk_embedding
FROM
  sholmes_tab_clob dt,
  DBMS_VECTOR_CHAIN.UTL_TO_EMBEDDINGS (         -- Convert text chunks into embeddings
    DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS (           -- Split the plain text into smaller chunks
      DBMS_VECTOR_CHAIN.UTL_TO_TEXT (dt.data),  -- Convert the CLOB to plain text
      JSON ('{"split":"sentence","normalize":"all"}')
    ),
    -- Use TinyBERT to generate the embeddings
    JSON ('{"provider":"database", "model":"tinybert_model"}')
  ) t,
  -- Convert the JSON output to columns
  JSON_TABLE (
    t.column_value,
    '$[*]' COLUMNS (
      embed_id NUMBER PATH '$.embed_id',
      embed_vector CLOB PATH '$.embed_vector',
      embed_data VARCHAR2 ( 4000 ) PATH '$.embed_data'
    )
  ) et;
COMMIT;

SELECT * FROM sholmes_tab_chunks;

-- Perform a similarity search. Convert the prompt into a vector using the same model.
SELECT
  doc_id,
  chunk_id,
  chunk_data
FROM
  sholmes_tab_chunks
ORDER BY
  VECTOR_DISTANCE (
    chunk_embedding,
    VECTOR_EMBEDDING ( TINYBERT_MODEL using 'Who stole the blue carbuncle?' AS data ),
    COSINE
  )
FETCH FIRST 10 ROWS ONLY;

--
-- Extract entities and relationships between them from the text chunks to create a Property Graph
--

-- Define a function to extract entities and relationships from the text chunks
CREATE OR REPLACE FUNCTION extract_graph (
  text_chunk CLOB
) RETURN CLOB IS
BEGIN
  RETURN DBMS_CLOUD_AI.GENERATE (
    -- Provide detailed instructions for extracting entities and their relationships and
    -- the expected format of the output. The output will be used to create a graph.
    prompt => '
      You are a top-tier algorithm designed for extracting information in structured formats to build a knowledge graph.
      Your task is to identify the entities and relations requested with the user prompt from a given text.
      You must generate the output in a JSON format containing a list with JSON objects.
      Each object should have the keys: "head", "head_type", "relation", "tail", and "tail_type".
      The "head" key must contain the text of the extracted entity with one of the types from the provided list in the
      user prompt.\n
      Attempt to extract as many entities and relations as you can, but avoid to create entities for filler words, such as pronouns.
      Maintain Entity Consistency: When extracting entities, it''s vital to ensure consistency.
      If an entity, such as "John Doe", is mentioned multiple times in the text but is referred to by different names
      or pronouns (e.g., "Joe", "he"), always use the most complete identifier for that entity.
      The knowledge graph should be coherent and easily understandable, so maintaining consistency in entity references
      is crucial.\n
      IMPORTANT NOTES:\n
      - Don''t add any explanation and text.
      The output should be formatted as a JSON instance that conforms to the JSON schema below.\n\n
      as an example, for the schema {"properties": {"foo": {"title": "Foo", "description": "a list of strings", "type":
      "array", "items": {"type": "string"}}}, "required": ["foo"]}\n
      the object {"foo": ["bar", "baz"]} is a well-formatted instance of the schema. The object {"properties": {"foo":
      ["bar", "baz"]}} is not well-formatted.\n\n
      Here is the output schema:\n\n
      {"properties":
      {"head": {"description": "extracted head entity like Oracle, Apple, John. Must use human-readable unique
      identifier.", "title": "Head", "type": "string"},
      "head_type": {"description": "type of the extracted head entity like Person, Company, etc", "title": "Head
      Type", "type": "string"},
      "relation": {"description": "relation between the head and the tail entities", "title": "Relation", "type":
      "string"},
      "tail": {"description": "extracted tail entity like Oracle, Apple, John. Must use human-readable unique
      identifier.", "title": "Tail", "type": "string"},
      "tail_type": {"description": "type of the extracted tail entity like Person, Company, etc", "title": "Tail
      Type", "type": "string"}},
      "required": ["head", "head_type", "relation", "tail", "tail_type"]
      }\n
      Examples:
      [{"text": "Adam is a software engineer in Oracle since 2009, and last year he got an award as the Best Talent",
      "head": "Adam",
      "head_type": "Person",
      "relation": "WORKS_FOR",
      "tail": "Oracle",
      "tail_type": "Company"},
      {"text": "Adam is a software engineer in Oracle since 2009, and last year he got an award as the Best Talent",
      "head": "Adam",
      "head_type": "Person",
      "relation": "HAS_AWARD",
      "tail": "Best Talent",
      "tail_type": "Award"},
      {"text": "Microsoft is a tech company that provide several products such as Microsoft Word",
      "head": "Microsoft Word",
      "head_type": "Product",
      "relation": "PRODUCED_BY",
      "tail": "Microsoft",
      "tail_type": "Company"},
      {"text": "Microsoft Word is a lightweight app that accessible offline",
      "head": "Microsoft Word",
      "head_type": "Product",
      "relation": "HAS_CHARACTERISTIC",
      "tail": "lightweight app",
      "tail_type": "Characteristic"},
      {"text": "Microsoft Word is a lightweight app that accessible offline",
      "head": "Microsoft Word",
      "head_type": "Product",
      "relation": "HAS_CHARACTERISTIC",
      "tail": "accessible offline",
      "tail_type": "Characteristic"}]
      Input text:\n\n' || text_chunk,
    profile_name => 'GENAI_PROFILE',
    action       => 'chat'
  );
END;
/

-- Clean up the staging table
DROP TABLE IF EXISTS graph_extraction_stg;

-- Create a staging table to be populated with extracted entities and relationships
CREATE TABLE IF NOT EXISTS graph_extraction_stg (
  chunk_id NUMBER,
  response CLOB
);

-- Create a function that calls the function EXTRACT_GRAPH and
-- stores the response in a staging table.
CREATE OR REPLACE PROCEDURE load_extract_table AS
BEGIN
  DECLARE
    x NUMBER := 0;
  BEGIN

    -- Loop through chunks that have not been added to the staging table but only 10 times
    FOR text_chunk IN (
      SELECT
        c.chunk_id,
        c.chunk_data
      FROM
        sholmes_tab_chunks c
        LEFT JOIN graph_extraction_stg s ON s.chunk_id = c.chunk_id
      WHERE
        s.chunk_id IS NULL
        AND c.chunk_id > 0
        AND c.chunk_id <= 1000
      ORDER BY
        c.chunk_id
    ) LOOP
      x := x + 1;
      --Execute function to send prompt to Gen AI and insert response into staging table
      INSERT INTO graph_extraction_stg (
        chunk_id,
        response
      )
      SELECT
        text_chunk.chunk_id,
        extract_graph ( text_chunk.chunk_data ) AS response
      FROM
        dual;

      EXIT WHEN x > 10;
    END LOOP;
    COMMIT;
  END;
END;
/

-- Schedule a job to run function LOAD_EXTRACT_TABLE repeatedly for 10 chunks
-- until all text chunks are processed.
BEGIN
  SYS.DBMS_SCHEDULER.CREATE_JOB (
    job_name   => 'runExtractStagingStoredProcedure',
    job_type   => 'STORED_PROCEDURE',
    job_action => 'LOAD_EXTRACT_TABLE'
  );
END;
/

-- Run the job
DECLARE
  startjob TIMESTAMP;
  endjob   TIMESTAMP;
BEGIN
  startjob := current_timestamp;
  endjob := startjob + 1 / 24;
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE (
    name      => 'runExtractStagingStoredProcedure',
    attribute => 'START_DATE',
    value     => startjob
  );

  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE (
    name      => 'runExtractStagingStoredProcedure',
    attribute => 'REPEAT_INTERVAL',
    value     => 'FREQ=MINUTELY; INTERVAL=2'
  );

  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE (
    name      => 'runExtractStagingStoredProcedure',
    attribute => 'END_DATE',
    value     => endjob
  );

  SYS.DBMS_SCHEDULER.ENABLE (
    name => 'runExtractStagingStoredProcedure'
  );
END;
/

-- Check how the job progresses
SELECT
  count(*) AS "Chunks of text due to process."
FROM
  sholmes_tab_chunks c LEFT JOIN
  graph_extraction_stg S ON s.chunk_id  = c.chunk_id
WHERE
  s.chunk_id IS NULL;

-- Check the response of the model (extracted entities and relationships)
SELECT * FROM graph_extraction_stg;


--
-- Lab 3
--

-- Set up a staging table to store the relations retrieved (detected) by the LLM
DROP TABLE IF EXISTS graph_relations_stg;

CREATE TABLE graph_relations_stg (
  id RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
  chunk_id NUMBER,
  head VARCHAR(256) NOT NULL,
  head_type VARCHAR(256),
  relation VARCHAR(256) NOT NULL,
  tail VARCHAR(256) NOT NULL,
  tail_type VARCHAR(256),
  text VARCHAR(512)
);

-- Convert the JSON response (entities and relationships) in the GRAPH_EXTRACTION_STG table
-- into a relational representation
INSERT INTO graph_relations_stg (chunk_id, head, head_type, relation, tail, tail_type, text)
SELECT
  mt.chunk_id,
  jt.head,
  jt.head_type,
  jt.relation,
  jt.tail,
  jt.tail_type,
  jt.head_type || ': ' || jt.head || ' -[' || jt.relation || ']-> ' || jt.tail_type || ': ' || jt.tail
FROM
  graph_extraction_stg mt,
  JSON_TABLE (
    mt.RESPONSE,
    '$[*]' COLUMNS (
      head VARCHAR2(256) PATH '$.head',
      head_type VARCHAR2(256) PATH '$.head_type',
      relation VARCHAR2(256) PATH '$.relation',
      tail VARCHAR2(256) PATH '$.tail',
      tail_type VARCHAR2(256) PATH '$.tail_type'
    )
  ) jt
WHERE
  mt.response is json and
  jt.head IS NOT NULL and
  jt.relation IS NOT NULL and
  jt.tail IS NOT NULL;
COMMIT;

SELECT * FROM graph_relations_stg ORDER BY head, head_type, relation, tail, tail_type;

--
-- Clean up entities and relationships
--
SELECT DISTINCT head, head_type FROM graph_relations_stg ORDER BY 1;
SELECT DISTINCT tail, tail_type FROM graph_relations_stg ORDER BY 1;

DELETE
FROM graph_relations_stg
WHERE lower(HEAD) IN ('you','she','he','i','narrator','the man','man', 'we', 'us', 'wife', 'they', 'thing', '24 geese');
DELETE
FROM graph_relations_stg
WHERE lower(tail) IN ('you','she','he','i','narrator','the man','man', 'we', 'us', 'wife', 'they', 'thing', '24 geese');

UPDATE graph_relations_stg
SET head ='Alpha Inn'
WHERE lower(head) IN ('alpha','alpha club' );
UPDATE graph_relations_stg
SET tail ='Alpha Inn'
WHERE lower(tail) IN ('alpha','alpha club' );

UPDATE graph_relations_stg
SET head ='Henry Baker'
WHERE lower(head) IN ('baker', 'henry baker', 'mr. baker', 'mr. henry baker', 'henry bakers', 'h. b.', 'bakers' );
UPDATE graph_relations_stg
SET tail ='Henry Baker'
WHERE lower(tail) IN ('baker', 'henry baker', 'mr. baker', 'mr. henry baker', 'henry bakers', 'h. b.', 'bakers'  );

UPDATE graph_relations_stg
SET head ='Watson'
WHERE lower(head) IN ('doctor');
UPDATE graph_relations_stg
SET tail ='Watson'
WHERE lower(tail) IN ('doctor');

UPDATE graph_relations_stg
SET head ='Catherine Cusack'
WHERE lower(head) IN ('catherine cusack', 'cusack' );
UPDATE graph_relations_stg
SET tail ='Catherine Cusack'
WHERE lower(tail) IN ('catherine cusack', 'cusack' );

UPDATE graph_relations_stg
SET head ='Sherlock Holmes'
WHERE lower(head) IN ('holmes', 'mr. holmes' ,'sherlock holmes');
UPDATE graph_relations_stg
SET tail ='Sherlock Holmes'
WHERE lower(tail) IN ('holmes', 'mr. holmes' ,'sherlock holmes');

UPDATE graph_relations_stg
SET head ='John Horner'
WHERE lower(head) IN ('horner', 'john horner' ,'');
UPDATE graph_relations_stg
SET tail ='John Horner'
WHERE lower(tail) IN ('horner', 'john horner' ,'');

UPDATE graph_relations_stg
SET head ='James Ryder'
WHERE lower(head) IN ('james ryder', 'mr. ryder' ,'ryder');
UPDATE graph_relations_stg
SET tail ='James Ryder'
WHERE lower(tail) IN ('james ryder', 'mr. ryder' ,'ryder');

UPDATE graph_relations_stg
SET head ='Mr. Windigate'
WHERE lower(head) IN ('mr. windigate', 'windigate');
UPDATE graph_relations_stg
SET tail ='Mr. Windigate'
WHERE lower(tail) IN ('mr. windigate', 'windigate');

UPDATE graph_relations_stg
SET head ='Countess of Morcar'
WHERE lower(head) IN ('countess of morcar', 'countess');
UPDATE graph_relations_stg
SET tail ='Countess of Morcar'
WHERE lower(tail) IN ('countess of morcar', 'countess');

UPDATE graph_relations_stg
SET head ='Hat'
WHERE lower(head) IN ('hat', 'the hat', 'old hat', 'battered hat' );
UPDATE graph_relations_stg
SET tail ='Hat'
WHERE lower(tail)  IN ('hat', 'the hat', 'old hat', 'battered hat' );

UPDATE graph_relations_stg
SET head ='Blue Carbuncle'
where lower(head) in ('gem', 'blue stone', 'jewel', 'the stone', 'stone', 'jewel-case', 'blue carbuncle' );
UPDATE graph_relations_stg
SET tail ='Blue Carbuncle'
WHERE lower(tail) IN ('gem', 'blue stone', 'jewel', 'the stone', 'stone', 'jewel-case', 'blue carbuncle' );

UPDATE graph_relations_stg
SET head ='Goose'
WHERE lower(head) IN ('goose', 'good fat goose' ,'christmas goose','the bird','the goose','bird');
UPDATE graph_relations_stg
SET tail ='Goose'
WHERE lower(tail) IN  ('goose', 'good fat goose' ,'christmas goose','the bird','the goose','bird');

COMMIT;

--
-- Store entities (nodes / vertices) and relations (edges) in separate tables.
-- For simplicity, store all entities in one table, and all relationships in another table.
--

-- Table to store the vertices from graph_relations_stg
DROP TABLE IF EXISTS graph_entities;

CREATE TABLE graph_entities (
  id NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 1 CACHE 20 )  NOT NULL,
  entity_name VARCHAR2 (250),
  entity_type VARCHAR2 (250)
);

TRUNCATE TABLE graph_entities DROP STORAGE;

-- Populate the vertex table
INSERT INTO graph_entities (
  entity_name,
  entity_type
)
SELECT
  head,
  head_type
FROM
  graph_relations_stg
UNION
SELECT
  tail,
  tail_type
FROM
  graph_relations_stg;
COMMIT;

SELECT * FROM graph_entities ORDER BY 1,2;

-- Table to store the edges from graph_relations_stg
DROP TABLE IF EXISTS graph_relations;

CREATE TABLE graph_relations (
  id NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 1 CACHE 20 ) NOT NULL ,
  chunk_id NUMBER ,
  head_id  NUMBER ,
  tail_id  NUMBER ,
  relation VARCHAR2 (256) NOT NULL ,
  text VARCHAR2 (512)
);

TRUNCATE TABLE graph_relations DROP STORAGE;

-- Populate the edge table
INSERT INTO graph_relations (chunk_id, head_id, tail_id, relation, text)
SELECT
  chunk_id,
  head.id AS head_id,
  tail.id AS tail_id,
  s.relation,
  s.text
FROM
  graph_relations_stg s INNER JOIN
  graph_entities head ON head.entity_name = s.head AND head.entity_type = s.head_type INNER JOIN
  graph_entities tail ON tail.entity_name = s.tail AND tail.entity_type = s.tail_type;
COMMIT;

SELECT * FROM graph_relations ORDER BY 2,3,4;

--
-- Lab 4
-- Create and query a graph
-- 1. PGQL (Oracle-native)
-- 2. SQL/PGQ (SQL:2023 Part 16)
--

-- Set up a Property Graph using PGQL

/* Use Graph Studio or SQLcl plus PGQL plugin

DROP PROPERTY GRAPH sholmes_lexical_graph_pgql;

CREATE PROPERTY GRAPH sholmes_lexical_graph_pgql
  VERTEX TABLES (
    graph_entities
      KEY ( id )
      LABEL Entity
      PROPERTIES ( entity_name, entity_type )
  )
  EDGE TABLES (
    graph_relations
      KEY ( id )
      SOURCE KEY ( head_id ) REFERENCES graph_entities ( id )
      DESTINATION KEY ( tail_id ) REFERENCES graph_entities ( id )
      LABEL related_to
      PROPERTIES ( chunk_id, relation, text )
  )
  OPTIONS ( PG_PGQL );

 */

-- Set up a Property Graph using SQL/PGQ
DROP PROPERTY GRAPH IF EXISTS sholmes_lexical_graph_sql;

CREATE PROPERTY GRAPH IF NOT EXISTS sholmes_lexical_graph_sql
  VERTEX TABLES (
    graph_entities
      KEY ( id )
      LABEL Entity
      PROPERTIES ( entity_name, entity_type )
  )
  EDGE TABLES (
    graph_relations
      KEY ( id )
      SOURCE KEY ( head_id ) REFERENCES graph_entities ( id )
      DESTINATION KEY ( tail_id ) REFERENCES graph_entities ( id )
      LABEL related_to
      PROPERTIES ( chunk_id, relation, text )
  );

-- Query the graph using SQL/PGQ
SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e IS RELATED_TO]->(n2 IS ENTITY)
    WHERE n1.entity_name ='Blue Carbuncle'
    COLUMNS ( VERTEX_ID(n1) AS src_id, EDGE_ID(e) AS edge_id, VERTEX_ID(n2) AS dst_id)
  );

-- Variable length-path queries
SELECT
  *
FROM GRAPH_TABLE (
  sholmes_lexical_graph_sql
  MATCH (n IS entity) -[e1 IS related_to]->{1,3} (IS entity)
  WHERE n.entity_name = 'Blue Carbuncle'
  ONE ROW PER STEP (src, e2, dst)
  COLUMNS (
    LISTAGG(e1.relation, ', ') AS relation_list,
    src.entity_name AS src_entity_name,
    src.entity_type AS src_entity_type,
    e2.relation,
    dst.entity_name AS dst_entity_name,
    dst.entity_type AS dst_entity_type
  )
)
ORDER BY
  1,2,3,4,5;

SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
  MATCH (n IS entity) -[e1 IS related_to]->{1,3} (IS entity)
  WHERE n.entity_name = 'Blue Carbuncle'
  ONE ROW PER STEP (src, e2, dst)
  COLUMNS (
    VERTEX_ID(src) AS src_id,
    EDGE_ID(e2) AS edge_id,
    VERTEX_ID(dst) AS dst_id
  )
);

-- Fixed length-path queries
SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e IS RELATED_TO]->(n2 IS ENTITY)
    WHERE n1.entity_name ='Blue Carbuncle'
    COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e.relation AS relation,
      n2.entity_name AS entity_name_dst,
      n2.entity_type AS entity_type_dst
    )
  )
ORDER BY
  1,2,3,4,5;

SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e1 IS RELATED_TO]->(n2 IS ENTITY)-[e2 IS RELATED_TO]->(n3 IS ENTITY)
    WHERE n1.entity_name ='Blue Carbuncle'
    COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e1.relation AS relation_1,
      n2.entity_name AS entity_name_mid,
      n2.entity_type AS entity_type_mid,
      e2.relation AS second_relation,
      n3.entity_name AS entity_name_dst,
      n3.entity_type AS entity_type_dst
    )
  )
ORDER BY
  1,2,3,4,5;

SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e1 IS RELATED_TO]->(n2 IS ENTITY)-[e2 IS RELATED_TO]->(n3 IS ENTITY)-[e3 IS RELATED_TO]->(n4 IS ENTITY)
    WHERE n1.entity_name ='Blue Carbuncle'
    COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e1.relation AS relation_1,
      n2.entity_name AS entity_name_mid1,
      n2.entity_type AS entity_type_mid1,
      e2.relation AS relation_2,
      n3.entity_name AS entity_name_mid2,
      n3.entity_type AS entity_type_mid2,
      e3.relation AS relation_3,
      n4.entity_name AS entity_name_dst,
      n4.entity_type AS entity_type_dst
    )
  )
ORDER BY
  1,2,3,4,5;

SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e1 IS RELATED_TO]->(n2 IS ENTITY)-[e2 IS RELATED_TO]->(n3 IS ENTITY)-[e3 IS RELATED_TO]->(n4 IS ENTITY)
    WHERE n1.entity_name ='James Ryder'
    COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e1.relation AS relation_1,
      n2.entity_name AS entity_name_mid1,
      n2.entity_type AS entity_type_mid1,
      e2.relation AS relation_2,
      n3.entity_name AS entity_name_mid2,
      n3.entity_type AS entity_type_mid2,
      e3.relation AS relation_3,
      n4.entity_name AS entity_name_dst,
      n4.entity_type AS entity_type_dst
    )
  )
ORDER BY
  1,2,3,4,5;

SELECT
  *
FROM
  GRAPH_TABLE (
    sholmes_lexical_graph_sql
    MATCH (n1 IS ENTITY)-[e IS RELATED_TO]->(n2 IS ENTITY)
    WHERE n1.entity_name ='Hat'
    COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e.relation AS relation,
      n2.entity_name AS entity_name_dst,
      n2.entity_type AS entity_type_dst
    )
  )
ORDER BY
  1,2,3,4,5;

SELECT
  ROWNUM AS row_num,
  entity_name_src || ' (' || entity_type_src || ') ' || relation || ' ' || entity_name_dst  || ' (' || entity_type_dst || ')' AS information
FROM GRAPH_TABLE (
  sholmes_lexical_graph_sql
  MATCH (n1 IS ENTITY)-[e IS RELATED_TO]->(n2 IS ENTITY)
  WHERE n1.entity_name = 'Blue Carbuncle'
  COLUMNS (
      n1.entity_name AS entity_name_src,
      n1.entity_type AS entity_type_src,
      e.relation,
      n2.entity_name AS entity_name_dst,
      n2.entity_type AS entity_type_dst
  )
);

--
-- Lab 5
--

SET SERVEROUTPUT ON;

-- Procedure for basic queries on the SQL property graph that pivots the results and
-- sends them as prompt to the LLM.
CREATE OR REPLACE PROCEDURE vertex_25_edge_prompt (
  debugPrompt      IN NUMBER DEFAULT 0,
  entityName       IN VARCHAR2,
  promptBegin      IN VARCHAR2,
  response         OUT VARCHAR2,
  propertyGraphRag OUT VARCHAR2
)
  IS
    query VARCHAR2(4000);
  BEGIN
    --Use dynamic SQL to parameterize bind variables for graph query
    query := '
      WITH
        cteGraphData AS (
          SELECT
            ROWNUM AS row_num,
            entity_name_src || '' ('' || entity_type_src || '') '' || relation || '' '' || entity_name_dst  || '' ('' || entity_type_dst || '')'' AS information
          FROM GRAPH_TABLE (
            sholmes_lexical_graph_sql
            MATCH (n1 IS ENTITY)-[e IS RELATED_TO]->(n2 IS ENTITY)
            WHERE n1.entity_name = :a
            COLUMNS (
                n1.entity_name AS entity_name_src,
                n1.entity_type AS entity_type_src,
                e.relation,
                n2.entity_name AS entity_name_dst,
                n2.entity_type AS entity_type_dst
            )
          )
        ),
        -- Pivot on 25 vertex-edge-relationships
        ctePivotGraphData AS (
          SELECT
            graphfact_1,
            graphfact_2,
            graphfact_3,
            graphfact_4,
            graphfact_5,
            graphfact_6,
            graphfact_7,
            graphfact_8,
            graphfact_9,
            graphfact_10,
            graphfact_11,
            graphfact_12,
            graphfact_13,
            graphfact_14,
            graphfact_15,
            graphfact_16,
            graphfact_17,
            graphfact_18,
            graphfact_19,
            graphfact_20,
            graphfact_21,
            graphfact_22,
            graphfact_23,
            graphfact_24,
            graphfact_25
          FROM (
            SELECT
              row_num,
              information
            FROM
              cteGraphData
          )
          PIVOT (
            MAX ( information )
            FOR row_num IN (
              ''1'' AS graphfact_1,
              ''2'' AS graphfact_2,
              ''3'' AS graphfact_3,
              ''4'' AS graphfact_4,
              ''5'' AS graphfact_5,
              ''6'' AS graphfact_6,
              ''7'' AS graphfact_7,
              ''8'' AS graphfact_8,
              ''9'' AS graphfact_9,
              ''10'' AS graphfact_10,
              ''11'' AS graphfact_11,
              ''12'' AS graphfact_12,
              ''13'' AS graphfact_13,
              ''14'' AS graphfact_14,
              ''15'' AS graphfact_15,
              ''16'' AS graphfact_16,
              ''17'' AS graphfact_17,
              ''18'' AS graphfact_18,
              ''19'' AS graphfact_19,
              ''20'' AS graphfact_20,
              ''21'' AS graphfact_21,
              ''22'' AS graphfact_22,
              ''23'' AS graphfact_23,
              ''24'' AS graphfact_24,
              ''25'' AS graphfact_25
            )
          )
        )
  -- Combine columns into one
  SELECT
    REPLACE(
      JSON_OBJECT (
        graphfact_1,
        graphfact_2,
        graphfact_3,
        graphfact_4,
        graphfact_5,
        graphfact_6,
        graphfact_7,
        graphfact_8,
        graphfact_9,
        graphfact_10,
        graphfact_11,
        graphfact_12,
        graphfact_13,
        graphfact_14,
        graphfact_15,
        graphfact_16,
        graphfact_17,
        graphfact_18,
        graphfact_19,
        graphfact_20,
        graphfact_21,
        graphfact_22,
        graphfact_23,
        graphfact_24,
        graphfact_25
      ),
      ''graphfact_'',
      '''') AS response
  FROM
    ctePivotGraphData';

  EXECUTE IMMEDIATE query INTO propertyGraphRag USING entityName;

  IF debugPrompt = 1 THEN
    DBMS_OUTPUT.PUT_LINE ( promptBegin || '  with the following information  ' || propertyGraphRag );
  END IF;

  -- Send prompt to LLM with information from the graph
  SELECT
    DBMS_CLOUD_AI.GENERATE (
      prompt       => promptBegin || '  with the following information extracted from the graph: ' || propertyGraphRag ,
      profile_name => 'GENAI_PROFILE',
      action       => 'chat'
    )
  INTO response
  FROM dual;

  -- Output LLM response
  DBMS_OUTPUT.PUT_LINE('LLM response using the graph: ' || response);
END;
/

SET ECHO OFF;
SET SERVEROUTPUT ON;

--
-- Putting everything together:
-- Use procedure VERTEX_25_EDGE_PROMPT to perform Graph RAG
--

-- Example 1: Create evidence report querying the SQL Property Graph for the "Blue Carbuncle".
DECLARE
  l_entityname       VARCHAR2(200) := 'Blue Carbuncle';
  l_promptbegin      VARCHAR2(200) := 'Write an official evidence report';
  l_response         VARCHAR2(8000);
  l_propertygraphrag VARCHAR2(4000);
BEGIN
  vertex_25_edge_prompt (
    entityName       => l_entityname,
    promptBegin      => l_promptbegin,
    response         => l_response,
    propertyGraphRag => l_propertygraphrag
  );
END;
/

-- Example 2: Who stole the jewel?
DECLARE
  l_entityname       VARCHAR2(200) := 'Blue Carbuncle';
  l_promptbegin      VARCHAR2(200) := 'Who stole the jewel';
  l_response         VARCHAR2(8000);
  l_propertygraphrag VARCHAR2(4000);
BEGIN
  vertex_25_edge_prompt (
    entityName       => l_entityname,
    promptBegin      => l_promptbegin,
    response         => l_response,
    propertyGraphRag => l_propertygraphrag
  );
END;
/

-- -- Example 3: Write a prosecution argument outline against James Ryder.
DECLARE
  l_entityname       VARCHAR2(200) := 'James Ryder';
  l_promptbegin      VARCHAR2(200) := 'Write a bulleted outline of a prosecution argument';
  l_response         VARCHAR2(8000);
  l_propertygraphrag VARCHAR2(4000);
BEGIN
  vertex_25_edge_prompt (
    entityName       => l_entityname,
    promptBegin      => l_promptbegin,
    response         => l_response,
    propertyGraphRag => l_propertygraphrag
  );
END;
/

-- -- Example 4: Write a defense argument outline for James Ryder.
DECLARE
  l_entityname       VARCHAR2(200) := 'James Ryder';
  l_promptbegin      VARCHAR2(200) := 'Write a bulleted outline of a defense argument';
  l_response         VARCHAR2(8000);
  l_propertygraphrag VARCHAR2(4000);
BEGIN
  vertex_25_edge_prompt (
    entityName       => l_entityname,
    promptBegin      => l_promptbegin,
    response         => l_response,
    propertyGraphRag => l_propertygraphrag
  );
END;
/

-- -- Example 5: Write poem using property graph query on the hat entity.
DECLARE
  l_entityname       VARCHAR2(200) := 'Hat';
  l_promptbegin      VARCHAR2(200) := 'Write a poem about';
  l_response         VARCHAR2(8000);
  l_propertygraphrag VARCHAR2(4000);
BEGIN
  vertex_25_edge_prompt (
    entityName       => l_entityname,
    promptBegin      => l_promptbegin,
    response         => l_response,
    propertyGraphRag => l_propertygraphrag
  );
END;
/

--
-- Finish
--
