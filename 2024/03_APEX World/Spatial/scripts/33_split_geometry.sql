--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace package split_geometry is
  type geometry_part is record (
    part_id    number,
    part_geom  sdo_geometry
  );
  type geometry_parts is table of geometry_part;
  function get_parts (g sdo_geometry) return geometry_parts pipelined;
end split_geometry;
/
show errors

create or replace package body split_geometry is
  function get_parts (g sdo_geometry) return geometry_parts
  pipelined
  as
  begin
    for i in 1..sdo_util.getnumelem(g) loop
      pipe row (
        geometry_part (
          i,
          sdo_util.extract(g,i)
        )
      );
    end loop;
    return;
  end;
end split_geometry;
/
show errors


------------------------------------------------------------
-- Splitting a multi-geometry into its elements
------------------------------------------------------------

select * from table(split_geometry.get_parts((select geom from us_counties where county='Arapahoe')));

-- Split geometry in parts
select c.id as feature_id, p.part_id, p.part_geom
from us_counties c, table(split_geometry.get_parts((c.geom))) p
where county='Arapahoe';

-- Split geometry in vertices
select c.id as feature_id, p.part_id, v.id as vertex_num, v.x, v.y
from us_counties c, table(split_geometry.get_parts((c.geom))) p, table(sdo_util.getvertices(p.part_geom)) v
where county='Arapahoe'
order by feature_id, part_id, vertex_num;


select * from table(split_geometry.get_parts((select geom from us_states where state_abrv='CA')));

select id, state_abrv, part_id, part_geom
from   us_states, table(split_geometry.get_parts(geom))
order by id, part_id;

select part_id, part_geom
from us_states, table(split_geometry.get_parts(geom))
where state_abrv = 'CA'
order by part_id;

select id, county, state_abrv, part_id, part_geom
from   us_counties, table(split_geometry.get_parts(geom))
where state_abrv = 'CO'
and county in ('Denver', 'Arapahoe')
order by id, part_id;

select s.state_abrv, s.state, e.part_id, e.part_geom
from us_states s, table(split_geometry.get_parts(geom)) e
where s.state_abrv = 'CA'
order by e.part_id;

create table us_states_elements as
select id, state_abrv, part_id, part_geom
from   us_states, table(split_geometry.get_parts(geom));

