--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function append_point (
   line sdo_geometry, point sdo_geometry) return sdo_geometry
is
  g   sdo_geometry;  -- Updated geometry
  p   number;        -- Insertion point into ordinates array
begin
  -- Initialize output line with input line
  g := line;
  -- Determine insertion point into ordinates array.
  p := g.sdo_ordinates.count() + 1;
  -- Extend the ordinates array
  g.sdo_ordinates.extend(g.get_dims());
  -- Store the new point
  g.sdo_ordinates(p) := point.sdo_point.x;
  g.sdo_ordinates(p+1) := point.sdo_point.y;
  -- Return new line string
  return g;
end;
/

---------------------------------------------
-- Extend interstate I29B: add one more point
---------------------------------------------
update us_interstates
set geom = append_point (
  geom,
  sdo_geometry(
    2001, 8307,
    sdo_point_type(-94.850621, 39.77548, null),
    null,null
  )
)
where interstate = 'I29B';
