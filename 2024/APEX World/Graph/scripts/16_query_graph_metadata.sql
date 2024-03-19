------------------------------------------
-- Query the Property Graph metadata views
------------------------------------------

select * from user_property_graphs;
select * from user_pg_elements where graph_name='FLIGHT_GRAPH';
select * from user_pg_label_properties where graph_name='FLIGHT_GRAPH';
select * from user_pg_labels where graph_name='FLIGHT_GRAPH';