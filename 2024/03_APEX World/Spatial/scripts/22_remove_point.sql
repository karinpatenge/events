--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function remove_point (line sdo_geometry, point_number number)
return sdo_geometry
is
  g sdo_geometry;  -- Updated geometry
  p number;        -- Index into ordinates array
  d number;        -- Number of dimensions in geometry
  i number;
begin
  -- Get the number of dimensions of input geometry
  d :=line.get_dims();
  -- Get index into ordinates array. If negative, count backwards from the end of the array
  p := (point_number-1) * d + 1;
  -- Initialize output line with input line
  g := line;
  -- Shift the ordinates down
  for i in p..g.sdo_ordinates.count()-d loop
    g.sdo_ordinates(i) := g.sdo_ordinates(i+d);
  end loop;
  -- Trim the ordinates array
  g.sdo_ordinates.trim (d);
  -- Return new line string
  return g;
end;
/


-----------------
-- Remove a point
-----------------
update us_interstates
set geom = remove_point (geom, 5)
where interstate = 'I29B';

select geom from us_interstates where interstate = 'I29B';



