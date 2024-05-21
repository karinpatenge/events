/******************************************************************************************
 * Operational Property Graphs in Oracle Database 23ai: Bank Graph
 * Author: Karin Patenge
 * Date: May 2025
 ******************************************************************************************/

-- Query graph metadata
SELECT * FROM user_property_graphs;
SELECT * FROM user_pg_label_properties WHERE graph_name='BANK_GRAPH';

-- SQL/PGQ queries
SELECT acct_id, COUNT(1) AS Num_Transfers
FROM graph_table ( BANK_GRAPH
    MATCH (src) - [IS TRANSFER] -> (dst)
    COLUMNS ( dst.id AS acct_id )
) GROUP BY acct_id ORDER BY Num_Transfers DESC FETCH FIRST 10 ROWS ONLY;

SELECT acct_id, COUNT(1) AS Num_In_Middle
FROM graph_table ( BANK_GRAPH
    MATCH (src) - [IS TRANSFER] -> (via) - [IS TRANSFER] -> (dst)
    COLUMNS ( via.id AS acct_id )
) GROUP BY acct_id ORDER BY Num_In_Middle DESC FETCH FIRST 10 ROWS ONLY;

SELECT account_id1, account_id2
FROM graph_table(BANK_GRAPH
    MATCH (v1)-[IS TRANSFER]->{1,3}(v2)
    WHERE v1.id = 387
    COLUMNS (v1.id AS account_id1, v2.id AS account_id2)
);

SELECT acct_id, COUNT(1) AS Num_Triangles
FROM graph_table (BANK_GRAPH
    MATCH (src) - []->{3} (src)
    COLUMNS (src.id AS acct_id)
) GROUP BY acct_id ORDER BY Num_Triangles DESC;

SELECT acct_id, COUNT(1) AS Num_4hop_Chains
FROM graph_table (BANK_GRAPH
    MATCH (src) - []->{4} (src)
    COLUMNS (src.id AS acct_id)
) GROUP BY acct_id ORDER BY Num_4hop_Chains DESC;

SELECT acct_id, COUNT(1) AS Num_5hop_Chains
FROM graph_table (BANK_GRAPH
    MATCH (src) - []->{5} (src)
    COLUMNS (src.id AS acct_id)
) GROUP BY acct_id ORDER BY Num_5hop_Chains DESC;

SELECT DISTINCT(account_id)
FROM GRAPH_TABLE(BANK_GRAPH
   MATCH (v1)-[IS TRANSFER]->{3,5}(v1)
    COLUMNS (v1.id AS account_id)
) FETCH FIRST 10 ROWS ONLY;

SELECT DISTINCT(account_id), COUNT(1) AS Num_Cycles
FROM graph_table(BANK_GRAPH
    MATCH (v1)-[IS TRANSFER]->{3, 5}(v1)
    COLUMNS (v1.id AS account_id)
) GROUP BY account_id ORDER BY Num_Cycles DESC FETCH FIRST 10 ROWS ONLY;


INSERT INTO bank_transfers VALUES (5002, 39, 934, null, 1000);
INSERT INTO bank_transfers VALUES (5003, 39, 135, null, 1000);
INSERT INTO bank_transfers VALUES (5004, 40, 135, null, 1000);
INSERT INTO bank_transfers VALUES (5005, 41, 135, null, 1000);
INSERT INTO bank_transfers VALUES (5006, 38, 135, null, 1000);
INSERT INTO bank_transfers VALUES (5007, 37, 135, null, 1000);


SELECT acct_id, count(1) AS Num_Transfers
FROM GRAPH_TABLE ( bank_graph
MATCH (src) - [IS TRANSFER] -> (dst)
COLUMNS ( dst.id as acct_id )
) GROUP BY acct_id ORDER BY Num_Transfers DESC fetch first 10 rows only;

SELECT count(1) Num_4Hop_Cycles
FROM graph_table(bank_graph
MATCH (s)-[]->{4}(s)
WHERE s.id = 39
COLUMNS (1 as dummy) );

INSERT INTO bank_transfers VALUES (5008, 559, 39, null, 1000);
INSERT INTO bank_transfers VALUES (5009, 982, 39, null, 1000);
INSERT INTO bank_transfers VALUES (5010, 407, 39, null, 1000);

SELECT count(1) Num_4Hop_Cycles
FROM graph_table(bank_graph
MATCH (s)-[]->{4}(s)
WHERE s.id = 39
COLUMNS (1 as dummy) );

SELECT s0, a1, a2, a3
FROM graph_table(bank_graph
MATCH (s)-[]->(a)-[]->(b)-[]->(c)
WHERE s.id = 39 and c.id in (559, 982, 407)
COLUMNS (s.id as s0, a.id as a1, b.id as a2, c.id as a3) );

DELETE FROM bank_transfers
WHERE txn_id IN (5002, 5003, 5004, 5005, 5006, 5007, 5008, 5009, 5010);


SELECT *
  FROM GRAPH_TABLE (
           bank_graph
           MATCH (a IS account) -[e IS transfer]-> (b IS account)
           WHERE a.id = 816
           COLUMNS(vertex_id(a) AS id_a, edge_id(e) AS id_e, vertex_id(b) AS id_b)
       )