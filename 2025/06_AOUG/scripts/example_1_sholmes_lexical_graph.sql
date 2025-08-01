/*
 * Hands-on workshop "Create a lexical graph by chunking a text, extracting nodes,and edges to build a graph" by Eduard Cuba
 * published on Oracle LiveLabs (https://livelabs.oracle.com/pls/apex/f?p=133:180:::::wid:4174)
 * Adapted for the AOUG 2025 Conference by Karin Patenge (June 2025)
 */

--
-- Start with Lab 2
--

-- !! Execute as user ADMIN
GRANT CREATE ANY MINING MODEL TO aouguser;
GRANT SELECT ANY MINING MODEL TO aouguser;
GRANT CREATE ANY DIRECTORY TO aouguser;
GRANT DROP ANY DIRECTORY TO aouguser;
GRANT EXECUTE ON DBMS_CLOUD TO aouguser;
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO aouguser;
GRANT EXECUTE ON DBMS_CLOUD_AI TO aouguser;

-- !! All following statements need to be executed as user AOUGUSER

-- Create directory to hold the ONNX model and the book fragment
CREATE OR REPLACE DIRECTORY GRAPHDIR AS 'scratch/';

BEGIN
  -- Download ONNX model from object storage bucket
  DBMS_CLOUD.GET_OBJECT (
    object_uri => 'https://objectstorage.us-chicago-1.oraclecloud.com/n/idb6enfdcxbl/b/Livelabs/o/onnx-embedding-models/tinybert.onnx',
    directory_name => 'GRAPHDIR'
  );

  -- Load ONNX model into schema
  DBMS_VECTOR.LOAD_ONNX_MODEL(
    'GRAPHDIR',
    'tinybert.onnx',
    'TINYBERT_MODEL',
    json('{"function":"embedding","embeddingOutput":"embedding","input":{"input":["DATA"]}}')
  );

  -- Load sample text
  DBMS_CLOUD.GET_OBJECT(
    object_uri => 'https://objectstorage.us-chicago-1.oraclecloud.com/n/idb6enfdcxbl/b/Livelabs/o/sample-data/blue.txt',
    directory_name => 'GRAPHDIR'
  );
END;
/

-- Check your credentials
SELECT
  credential_name,
  username,
  comments
FROM
  all_credentials;

-- If necessary, set up credentials to use OCI GenAI. Replace the placeholders with real values.
BEGIN
  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'GENAI_CRED',
    user_ocid       => '<user_ocid>',
    tenancy_ocid    => '<tenancy_ocid>',
    private_key     => '<private_key>',
    fingerprint     => '<fingerprint>'
  );
END;
/

-- Create an AI Profile using OCI GenAI and your credentials
BEGIN
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

SELECT * FROM DBMS_CLOUD.LIST_FILES('GRAPHDIR');

-- Create tables for text and text chunks and populate them
DROP TABLE IF EXISTS sholmes_tab;
DROP TABLE IF EXISTS sholmes_tab_clob;
DROP TABLE IF EXISTS sholmes_tab_chunks;

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

INSERT INTO sholmes_tab VALUES (1, TO_BLOB(BFILENAME('GRAPHDIR', 'blue.txt')));
SELECT * FROM sholmes_tab;

INSERT INTO sholmes_tab_clob SELECT id, TO_CLOB(data) FROM sholmes_tab;
SELECT * FROM sholmes_tab_clob;

COMMIT;

INSERT INTO sholmes_tab_chunks
SELECT
  dt.id AS doc_id,
  et.embed_id AS chunk_id,
  et.embed_data AS chunk_data,
  TO_VECTOR (et.embed_vector) AS chunk_embedding
FROM
  sholmes_tab_clob dt,
  DBMS_VECTOR_CHAIN.UTL_TO_EMBEDDINGS (
    DBMS_VECTOR_CHAIN.UTL_TO_CHUNKS (
      DBMS_VECTOR_CHAIN.UTL_TO_TEXT (dt.data),
      JSON ('{"split":"sentence","normalize":"all"}')
    ),
    JSON ('{"provider":"database", "model":"tinybert_model"}')
  ) t,
  JSON_TABLE (
    t.column_value,
    '$[*]' COLUMNS (
      embed_id NUMBER PATH '$.embed_id',
      embed_data VARCHAR2 ( 4000 ) PATH '$.embed_data',
      embed_vector CLOB PATH '$.embed_vector'
    )
  ) et;

COMMIT;

-- Perform a similarity search by creating vector embeddings to find out, who stole the blue carbuncle
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
FETCH FIRST 20 ROWS ONLY;

-- Create a function to extract entities and relationships between entities to further on create a graph
CREATE OR REPLACE FUNCTION extract_graph (
  text_chunk CLOB
) RETURN CLOB IS
BEGIN
  RETURN DBMS_CLOUD_AI.GENERATE (
    prompt => '
      You are a top-tier algorithm designed for extracting information in structured formats to build a knowledge graph.
      Your task is to identify the entities and relations requested with the user prompt from a given text.
      You must generate the output in a JSON format containing a list with JSON objects.
      Each object should have the keys: "head", "head_type", "relation", "tail", and "tail_type".
      The "head" key must contain the text of the extracted entity with one of the types from the provided list in the
      user prompt.\n
      Attempt to extract as many entities and relations as you can. Maintain Entity Consistency: When extracting
      entities, it''s vital to ensure consistency.
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

DROP TABLE IF EXISTS graph_extraction_stg;

CREATE TABLE graph_extraction_stg (
  chunk_id NUMBER,
  response CLOB
);

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
      --Execute function to send prompt to Gen AI and Insert response into staging table
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
  END;
END;
/

-- Define and schedule a job to extract entities and relationships
BEGIN
  SYS.DBMS_SCHEDULER.CREATE_JOB (
    job_name   => 'runExtractStagingStoredProcedure',
    job_type   => 'STORED_PROCEDURE',
    job_action => 'LOAD_EXTRACT_TABLE'
  );
END;
/

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

SELECT
  count(*) AS "Chunks of text to send"
FROM
  sholmes_tab_chunks c LEFT JOIN
  graph_extraction_stg S ON s.chunk_id  = c.chunk_id
WHERE
  s.chunk_id IS NULL;

--
-- Lab 3
--

-- Create a staging table to store the relations retrieved (detected) by the LLM
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

-- Populate the detected relations
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

SELECT * FROM graph_relations_stg;
SELECT DISTINCT head FROM graph_relations_stg ORDER BY 1;
SELECT DISTINCT tail FROM graph_relations_stg ORDER BY 1;

-- Clean up relations that do n
DELETE
FROM graph_relations_stg
WHERE lower(HEAD) IN ('you','she','he','i','narrator','the man','man', 'we', 'us', 'wife', 'they', 'thing');

DELETE
FROM graph_relations_stg
WHERE lower(tail) IN ('you','she','he','i','narrator','the man','man', 'we', 'us', 'wife', 'they', 'thing');

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

-- Create the graph_entities tables containing the vertices from graph_relations_stg with the cleaned relations.
DROP TABLE IF EXISTS graph_entities;

CREATE TABLE graph_entities (
  id NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 1 CACHE 20 )  NOT NULL,
  entity_name VARCHAR2 (250),
  entity_type VARCHAR2 (250)
);

-- Populate the vertex table
TRUNCATE TABLE graph_entities DROP STORAGE;

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

-- Create the edge table
DROP TABLE IF EXISTS graph_relations;

CREATE TABLE graph_relations (
  id NUMBER GENERATED ALWAYS AS IDENTITY ( START WITH 1 CACHE 20 ) NOT NULL ,
  chunk_id NUMBER ,
  head_id  NUMBER ,
  tail_id  NUMBER ,
  relation VARCHAR2 (256) NOT NULL ,
  text VARCHAR2 (512)
);

-- Populate the edge table
TRUNCATE TABLE graph_relations DROP STORAGE;

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
-- Switch to ADB -> Graph Studio -> PGQL Query Playground.
-- You can also use SQL Developer -> PGQL Worksheet or SQLcl using the PGQL Plugin.
--

-- Drop the graph
DROP PROPERTY GRAPH sholmes_lexical_graph_pgql;

-- Create the graph
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

-- Convert the PGQL Property Graph to a SQL Property Graph

-- Drop the SQL Property Graph
DROP PROPERTY GRAPH IF EXISTS sholmes_lexical_graph_sql;

-- Create the SQL Property Graph
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

--
-- Lab 5
--

SET SERVEROUTPUT ON;

-- Procedure for basic queries on the SQL property graph that pivots the results and sends them as prompt to the LLM
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

  --send prompt to llm with information from property graph
  SELECT
    DBMS_CLOUD_AI.GENERATE (
      prompt       => promptBegin || '  with the following INFORMATION  ' || propertyGraphRag ,
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

-- Create evidence report querying the SQL Property Graph for the "Blue Carbuncle".
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

-- Who stole the "Blue Carbuncle"?
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

-- Write a prosecution argument outline against James Ryder.
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

-- Write a defense argument outline for James Ryder.
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

-- Write poem using property graph query on the hat entity.
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
