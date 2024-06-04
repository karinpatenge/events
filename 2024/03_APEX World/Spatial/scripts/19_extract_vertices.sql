--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

col county for a30
col id for 99999

-- Points for a single geometry:
SELECT id,x,y 
FROM TABLE(
  sdo_util.getvertices(
    (SELECT geom FROM us_counties WHERE county='Denver')
  )
);

-- Points for multiple geometries
SELECT c.county, p.id, p.x, p.y 
FROM   us_counties c, 
       TABLE(sdo_util.getvertices(c.geom)) p  
WHERE  c.state_abrv = 'CO'
ORDER BY c.county, p.id;

-- With a spatial query
SELECT c.id, c.county, c.totpop,
       v.id, v.x, v.y
FROM   us_counties c,
       TABLE(sdo_util.getvertices (geom)) v
WHERE sdo_filter (
        geom,
        sdo_geometry (2003, 32775, null,
          sdo_elem_info_array (1,1003,3),
          sdo_ordinate_array (
            1420300,1805461, 1820000,2210000))
        ) = 'TRUE'
ORDER BY c.id, v.id;

-- Using a nested cursor
SELECT c.id, c.county, c.totpop,
       cursor (
         select id, x, y from (table (sdo_util.getvertices (geom)))
       ) ordinates
FROM   us_counties c
WHERE sdo_filter (
        geom,
        sdo_geometry (2003, 32775, null,
          sdo_elem_info_array (1,1003,3),
          sdo_ordinate_array (
            1420300,1805461, 1820000,2210000))
        ) = 'TRUE';


-- Points for one element of a geometry
SELECT id,x,y 
FROM TABLE(
  sdo_util.getvertices(
    (SELECT sdo_util.extract(geom,1,2) FROM us_counties WHERE county='Denver')
  )
);


