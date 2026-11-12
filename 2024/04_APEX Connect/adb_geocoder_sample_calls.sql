/*
 * (Forward) Geocoding
 */

-- Structured addresses
select sdo_gcdr.eloc_geocode('Hamborner Str. 51', 'Düsseldorf', null, '40472', 'DE', 'RELAX_POSTAL_CODE') as json
from dual;
select sdo_gcdr.eloc_geocode_as_geom('Hamborner Str. 51', 'Düsseldorf', null, '40472', 'DE', 'RELAX_POSTAL_CODE') as geom
from dual;
-- Unstructured addresses
select sdo_gcdr.eloc_geocode('Alexanderplatz 1, Berlin, 10117, DE') as json
from dual;
select sdo_gcdr.eloc_geocode_as_geom('Alexanderplatz 1, Berlin, 10117, DE') as geom
from dual;

/*
 * Reverse geocoding
 */
select sdo_gcdr.eloc_geocode(13.43335, 52.53107) from dual;
