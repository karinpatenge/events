-----------------------------
-- Clean up sample point data
-----------------------------

-- Unregister SDO_GEOMETRY column
begin
  apex_spatial.delete_geom_metadata (
    p_table_name  => 'SDO_SAMPLE_POINTS',
    p_column_name => 'GEOM');
end;
/

-- Drop table
drop table sdo_sample_points purge;