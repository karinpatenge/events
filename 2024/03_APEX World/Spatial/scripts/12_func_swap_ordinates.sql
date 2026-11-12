--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function swap_ordinates (g_in sdo_geometry)
return sdo_geometry
is
  g_out sdo_geometry;
  i integer;
begin
  -- Check input geometry: we only work on 2D shapes
  if substr(g_in.sdo_gtype,1,1) <> 2 then
    raise_application_error (-20001,'Geometry must be 2D');
  end if;
  -- Initialize output geometry
  g_out := g_in;
  -- Swap ordinates in sdo_point
  if g_in.sdo_point is not null then
    g_out.sdo_point.x := g_in.sdo_point.y;
    g_out.sdo_point.y := g_in.sdo_point.x;
  end if;
  -- Copy ordinates, swapping X and Y
  if g_in.sdo_ordinates is not null then
    for i in 1..g_in.sdo_ordinates.count/2 loop
      g_out.sdo_ordinates ((i-1)*2+1) := g_in.sdo_ordinates ((i-1)*2+2); -- Y -> X
      g_out.sdo_ordinates ((i-1)*2+2) := g_in.sdo_ordinates ((i-1)*2+1); -- X -> Y
    end loop;
  end if;
  -- Return fixed geometry
  return g_out;
end;
/
show errors