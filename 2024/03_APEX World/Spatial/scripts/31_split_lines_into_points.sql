--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

drop table points purge;

create table points as
select r.id as road_id, p.id as point_id, p.x, p.y
from us_interstates r,
   table(sdo_util.getvertices(r.geom)) p
order by r.id,p.id;
