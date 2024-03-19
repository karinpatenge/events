--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

-- Extract coordinates
select d.cp.dist as distance, d.cp.geoma.sdo_point.x as xa, d.cp.geoma.sdo_point.y as ya,  d.cp.geomb.sdo_point.x as xb, d.cp.geomb.sdo_point.y as yb
from (
  select sdo_geom.sdo_closest_points (c1.geom, c2.geom, 0.5, 'unit=km') cp
  from us_counties c1, us_counties c2
  where c1.state_abrv='NJ' and c1.county='Passaic'
  and  c2.state_abrv='NJ' and c2.county='Hudson'
) d;


