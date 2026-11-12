/******************************************************************************************
 * Operational Property Graphs in Oracle Database 23ai: EBA_SAMPLE_GRAPH
 * Author: Karin Patenge
 * Date: May 2025
 ******************************************************************************************/

-- Query graph metadata
select * from user_property_graphs;
select * from user_pg_edge_relationships where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_elements where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_element_labels where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_keys where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_label_properties where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_labels where graph_name='EBA_SAMPLE_GRAPH';
select * from user_pg_prop_definitions where graph_name='EBA_SAMPLE_GRAPH';

-- Query the graph
select employee,e, manager
from graph_table ( eba_sample_graph
  match (m is employee ) -[e is works_for ]-> (n)
  columns (vertex_id(m) as employee, edge_id(e) as e, vertex_id(n) as manager )
);

select employee_name, 'works for', manager_name
from graph_table ( eba_sample_graph
  match (m is employee ) -[e is works_for]->{1,3}(n)
  columns (m.employee_id as employee_id, m.first_name || ' ' ||  m.last_name as employee_name, n.employee_id as manager_id, n.first_name || ' ' ||  n.last_name as manager_name )
)
where employee_id = 105;

select count(*)
from graph_table ( eba_sample_graph
  match (m) -[e]-> {1,5}(n)
  columns (vertex_id(m) as src, vertex_id(n) as dst)
);