--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

drop table lines_1 purge;
create table lines_1 as
select r.road_id, r.geom
from (
  select  c.road_id,
          sdo_geometry (
            2002, 4326, null,
            sdo_elem_info_array(1,2,1),
            cast (
              multiset (
                select b.column_value
                from points p,
                     table (
                       sdo_ordinate_array(p.x, p.y)
                     ) b
                where p.road_id = c.road_id
                order by p.point_id
              )
              as sdo_ordinate_array
            )
          ) as geom
  from points c
  group by c.road_id
  order by c.road_id
) r;

drop table lines_2 purge;
create table lines_2 as
select r.road_id, r.geom
from (
  select  c.road_id,
          sdo_geometry (
            2002, 4326, null,
            sdo_elem_info_array(1,2,1),
            cast (
              multiset (
                select v
                from points
                     unpivot (v for (col) in (x,y))
                where road_id = c.road_id
                order by point_id
              )
              as sdo_ordinate_array
            )
          ) as geom
  from points c
  group by c.road_id
  order by c.road_id
) r;
