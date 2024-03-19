--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function extract_vertex_as_point (
  geom sdo_geometry, vertex_number number) return sdo_geometry
is
  i  number;            -- Index into ordinates array
  px number;            -- X of extracted vertex
  py number;            -- Y of extracted vertex
begin
  -- Get index into ordinates array
  i := (point_number-1) * geom.get_dims() + 1;
  -- Extract the X and Y coordinates of the desired vertex
  px := geom.sdo_ordinates(i);
  py := geom.sdo_ordinates(i+1);
  -- Construct and return the vertex
  return
    sdo_geometry (2001, geom.sdo_srid,
      sdo_point_type (px, py, null), null, null);
end;
/

------------------------------------------------
-- Extract the second point from interstate I29B
------------------------------------------------
select get_point (geom, 2)
from us_interstates
where interstate = 'I29B';
