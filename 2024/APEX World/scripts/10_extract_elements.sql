--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

drop function get_elements;
drop type sdo_geometry_table;
drop type sdo_geometry_row;

create or replace type sdo_geometry_row as object (
  element_id    number,
  element_geom  sdo_geometry
);
/

create or replace type sdo_geometry_table as table of sdo_geometry_row;
/

create or replace function get_elements (g sdo_geometry) return sdo_geometry_table
pipelined
as
begin
  for i in 1..sdo_util.getnumelem(g) loop
    pipe row (
      sdo_geometry_row (
        i,
        sdo_util.extract(g,i)
      )
    );
  end loop;
  return;
end;
/
show errors

select * from table(get_elements((select geom from us_states where state_abrv='CA')));

select element_id, element_geom
from us_states, table(get_elements(geom))
where state_abrv = 'CA'
order by element_id;

select id, state_abrv, element_id, element_geom
from us_states, table(get_elements(geom))
order by id, element_id;

create table us_states_elements as
select id, state_abrv, element_id, element_geom
from   us_states, table(get_elements(geom));

select id, county, state_abrv, element_id, element_geom
from   us_counties, table(get_elements(geom))
where state_abrv = 'CO'
and county in ('Denver', 'Arapahoe')
order by id, element_id;

