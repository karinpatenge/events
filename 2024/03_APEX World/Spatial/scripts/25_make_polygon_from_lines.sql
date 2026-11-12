--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

create or replace function line_to_polygon (line sdo_geometry)
return sdo_geometry deterministic
is 
  polygon sdo_geometry;
  k number;
begin
  -- Check that the input is a simple 2D line
  if line.sdo_gtype <> 2002 then
    raise_application_error (-20001, 'Geometry is not a simple 2D line (gtype 2002)');
  end if;
  -- Make it into a simple 2D polygon
  polygon := line;
  polygon.sdo_gtype := 2003;
  polygon.sdo_elem_info := sdo_elem_info_array (1, 1003, 1);
  -- Close the polygon if not already closed
  k := polygon.sdo_ordinates.count;
  if polygon.sdo_ordinates(k-1) <> polygon.sdo_ordinates(1)
  or polygon.sdo_ordinates(k) <> polygon.sdo_ordinates(2) then
    polygon.sdo_ordinates.extend(2);
    polygon.sdo_ordinates(k+1) := polygon.sdo_ordinates(1);
    polygon.sdo_ordinates(k+2) := polygon.sdo_ordinates(2);
  end if;
  
  -- Return result
  return polygon;
end;
/
show errors
