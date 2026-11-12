--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

-- Find the closest points in counties Passaic and Hudson in New Jersey
select sdo_geom.sdo_closest_points (c1.geom, c2.geom, 0.5, 'unit=km') cp
from us_counties c1, us_counties c2
where c1.state_abrv='NJ' and c1.county='Passaic'
and  c2.state_abrv='NJ' and c2.county='Hudson';

-- Extract the information in a simple way:
select d.cp.dist, d.cp.geoma, d.cp.geomb
from (
  select sdo_geom.sdo_closest_points (c1.geom, c2.geom, 0.5, 'unit=km') cp
  from us_counties c1, us_counties c2
  where c1.state_abrv='NJ' and c1.county='Passaic'
  and  c2.state_abrv='NJ' and c2.county='Hudson'
) d;

with distance_result as (
  select sdo_geom.sdo_closest_points (c1.geom, c2.geom, 0.5, 'unit=km') cp
  from us_counties c1, us_counties c2
  where c1.state_abrv='NJ' and c1.county='Passaic'
  and  c2.state_abrv='NJ' and c2.county='Hudson'
)
select d.cp.dist, d.cp.geoma, d.cp.geomb
from distance_result d;
