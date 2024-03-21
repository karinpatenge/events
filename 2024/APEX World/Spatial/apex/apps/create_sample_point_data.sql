-----------------------------------------
-- Create a random point data.
-- Points are located in the Netherlands.
-----------------------------------------

-- Create table
create table points (
    id number,
    geom sdo_geometry,
    name varchar2(200),
    constraint pk_points primary key (id) enable
);

-- APEX only:
-- Register SDO_GEOMETRY column of table POINTS
-- using APEX_SPATIAL.INSERT_GEOM_METADATA
begin
  apex_spatial.insert_geom_metadata (
    p_table_name  => 'POINTS',
    p_column_name => 'GEOM',
    p_diminfo     => sdo_dim_array(
      sdo_dim_element('X',-180,180,1),
      sdo_dim_element('Y',-90,90,1)
    ),
    p_srid        => apex_spatial.c_wgs_84 );
end;
/

-- Create spatial index
create index points_geom_sidx on points(geom)
indextype is mdsys.spatial_index_v2
parameters ('LAYER_GTYPE=POINT');

-- Procedure to insert random point geometries located in the Netherlands
declare
  type t_points is table of points%ROWTYPE;
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
  select nvl(max(id),1) + 1 into l_curr_id from points;

  -- Populate sample as collection
  for i in 1 .. l_size loop

    l_curr_lon := round(dbms_random.value(51.3,52.3),10);
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
    insert /*+ APPEND */ into points values l_tab(i);

  commit;

end;
/