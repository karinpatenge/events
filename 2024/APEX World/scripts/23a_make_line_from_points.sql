--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function make_line (
  point_cursor sys_refcursor,
  srid number default 4326
)
return sdo_geometry
as
  line_geom sdo_geometry;
  longitude number;
  latitude number;
  i number;
begin
  -- Initialize line geometry object
  line_geom := sdo_geometry (
    2002, srid, null, 
    sdo_elem_info_array (1,2,1),
    sdo_ordinate_array()
  );
  -- Fetch points and load into ordinate array
  i := 0;
  loop
    fetch point_cursor into longitude, latitude;
      exit when point_cursor%NOTFOUND;
    line_geom.sdo_ordinates.extend(2);
    line_geom.sdo_ordinates(i+1) := longitude;
    line_geom.sdo_ordinates(i+2) := latitude;
    i := i + 2;
  end loop;
  close point_cursor;
  -- If the line has no points, then return NULL
  if i = 0 then
    line_geom := NULL;
  end if;
  -- Return the line
  return line_geom; 
end;
/
show errors


------------------------------------------------------------
-- Constructing a line from a set of points
------------------------------------------------------------
drop table points purge;
create table points as
select i.id oid, p.id pid, p.x, p.y
from us_interstates i,
	   table(sdo_util.getvertices (geom)) p
where interstate like '%91%';

drop table lines purge;
create table lines as
select oid, make_line (
  cursor (
    select x, y
    from   points
    where  oid = p.oid
    ORDER BY pid
  ),
  4326
) geom
from (
  select distinct oid
  from points
) p;

