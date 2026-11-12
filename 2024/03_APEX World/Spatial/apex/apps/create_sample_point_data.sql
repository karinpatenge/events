-----------------------------------------
-- Create a random point data.
-- sdo_sample_points are located in the Netherlands.
-----------------------------------------

-- Create table
create table sdo_sample_points (
    id number,
    geom sdo_geometry,
    name varchar2(200),
    constraint pk_sdo_sample_points primary key (id) enable
);

-- APEX specific registration of
--   SDO_GEOMETRY column GEOM
--   in table SDO_SAMPLE_POINTS
-- using APEX_SPATIAL.INSERT_GEOM_METADATA

-- Clean up before inserting the metadata
begin
  apex_spatial.delete_geom_metadata (
    p_table_name  => 'SDO_SAMPLE_POINTS',
    p_column_name => 'GEOM');
end;
/

begin
  apex_spatial.insert_geom_metadata (
    p_table_name  => 'SDO_SAMPLE_POINTS',
    p_column_name => 'GEOM',
    p_diminfo     => sdo_dim_array(
      sdo_dim_element('X',-180,180,1),
      sdo_dim_element('Y',-90,90,1)
    ),
    p_srid        => apex_spatial.c_wgs_84 );
end;
/

-- Create the spatial index optimized for points
create index sdo_sample_points_geom_sidx on sdo_sample_points(geom)
indextype is mdsys.spatial_index_v2
parameters ('LAYER_GTYPE=POINT');

-- Procedure to insert random point geometries located in the Netherlands
declare
  type t_points is table of sdo_sample_points%ROWTYPE;
  l_tab t_points := t_points();

  -- Sample size
  l_size number    := 200;

  l_curr_id number;
  l_curr_lon number;
  l_curr_lat number;
  l_curr_geom sdo_geometry;
  l_curr_name varchar2(200);

begin

  -- Fetch last id from gps_positions table
  select nvl(max(id),1) + 1 into l_curr_id from sdo_sample_points;

  -- Populate sample as collection
  for i in 1 .. l_size loop

    l_curr_lon := round(dbms_random.value(51.6,52.3),10);
    l_curr_lat := round(dbms_random.value(4.7,5.7),10);

    l_curr_geom := mdsys.sdo_geometry (
      2001,
      4326,
      sdo_point_type (l_curr_lat, l_curr_lon, null),
      null,
      null
    );

    l_curr_name := dbms_random.string('x',10);

    l_tab.extend;
    l_tab(l_tab.last).id   := l_curr_id;
    l_tab(l_tab.last).geom := l_curr_geom;
    l_tab(l_tab.last).name := l_curr_name;

    l_curr_id := l_curr_id + 1;

  end loop;

  -- Ingest table with point geometries
  forall i in l_tab.first .. l_tab.last
    insert /*+ APPEND */ into sdo_sample_points values l_tab(i);

  commit;

end;
/