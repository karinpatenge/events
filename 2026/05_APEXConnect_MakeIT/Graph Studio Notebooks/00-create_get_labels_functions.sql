/*
 * Create functions to retrieve labels for graph elements.
 *
 * Author: Karin Patenge
 * Last updated: 2026-04-20
 *
 */

-- Unsorted labels
CREATE OR REPLACE FUNCTION get_labels(element_id JSON)
RETURN JSON
IS
  l_labels JSON;
BEGIN
  SELECT JSON_ARRAYAGG(label_name) INTO l_labels
  FROM SYS.ALL_PG_ELEMENT_LABELS
  WHERE owner = JSON_VALUE(element_id, '$.GRAPH_OWNER')
    AND graph_name = JSON_VALUE(element_id, '$.GRAPH_NAME')
    AND element_name = JSON_VALUE(element_id, '$.ELEM_TABLE');

  RETURN l_labels;
END;
/

-- ToDo: Add custom labels to the function

-- Sorted labels
CREATE OR REPLACE FUNCTION get_labels_sorted (element_id JSON)
RETURN JSON
IS
  l_labels JSON;
BEGIN
  SELECT JSON_ARRAYAGG(label_name ORDER BY label_name) INTO l_labels
  FROM SYS.ALL_PG_ELEMENT_LABELS
  WHERE owner = JSON_VALUE(element_id, '$.GRAPH_OWNER')
    AND graph_name = JSON_VALUE(element_id, '$.GRAPH_NAME')
    AND element_name = JSON_VALUE(element_id, '$.ELEM_TABLE');

  RETURN l_labels;
END;
/