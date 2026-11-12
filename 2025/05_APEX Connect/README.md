# APEX Connect 2025

## General information

[APEX Connect 2025](https://apex.doag.org/en/apex-connect-2025/) in Europa-Park Rust/DE from May 13-15, 2025.

The conference program can be found [here](https://my.doag.org/events/apex-connect/2025/agenda/#eventDay.all).

## Demos

## Environment

* Oracle Autonomous Database (ADW) 23ai (Always Free)
* Oracle Spatial Studio deployed from OCI Marketplace to OCI Compute VM (Always Free)
* SQL Developer / Visual Code with SQL Developer extension
* APEX as integrated tool in ADB

### Simplify spatial data creation

For vector data representing points, lines, polygons, or combinations of those; aka geometries or simple features.

#### Scripts

* [Create point geometries based on lon/lat values](./scripts/01_create_point_geometries_from_lon_lat.sql) using an open [data set containing information about street lamps in Nuremberg](./data/01_DE-BY-Nurnberg-202503200800.lit.csv), and published via the [GovData Portal Germany](https://www.govdata.de/suche/daten/strassenlampen-nurnberg-de-by).
* [A few queries for point geometries](./scripts/02_query_point_geometries.sql)

### Load spatial data

Spatial and Graph supports the use of GeoJSON objects to store, index, and manage geographic data that is in JSON (JavaScript Object Notation) format.
You can convert Oracle Spatial and Graph `SDO_GEOMETRY` objects to GeoJSON objects, and GeoJSON objects to `SDO_GEOMETRY` objects. You can use spatial operators, functions, and a special `SDO_GEOMETRY` method to work with GeoJSON data.

GeoJSON support in Spatial and Graph includes the following:
* `SDO_UTIL.TO_GEOJSON` function to convert an `SDO_GEOMETRY` object to a GeoJSON object.
* `SDO_UTIL.FROM_GEOJSON` function to convert a GeoJSON object to an
SDO_GEOMETRY object.
* `Get_GeoJson` method (member function) of the `SDO_GEOMETRY` type.

In Oracle Database 19c, [JSON support was introduced in addition to GeoJSON](https://docs.oracle.com/en/database/oracle/oracle-database/19/spatl/spatial-concepts.html#GUID-0D253291-6FB9-4DBF-BD84-925E7E9C93D0), the latter being available since version 12.2.0.1.

#### Data Sources

* [World cities in GeoJSON format](https://github.com/drei01/geojson-world-cities/)
* [World Administrative Boundaries - Countries and Territories as JSON](https://public.opendatasoft.com/explore/dataset/world-administrative-boundaries/export/)
* [Administrative boundaries Germany Levels 0-1 as GeoJSON](https://gadm.org/download_country.html)
* [Geoportal B-W: PEGELONLINE WFS Aktuell](https://metadaten.geoportal-bw.de/geonetwork/srv/ger/catalog.search#/metadata/e2932050-d8f4-4258-8464-33587d42bd33)
* [Unfallatlas Statistikportal DE](https://unfallatlas.statistikportal.de/) > [Unfallatlas und OpenData (Shapefiles)](https://www.opengeodata.nrw.de/produkte/transport_verkehr/unfallatlas/Unfallorte2023_EPSG25832_Shape.zip)
* [Opendata Straßenlampen in Nürnberg als CSV im European Data Portal](https://osm.download.movisda.io/admin/DE-BY/DE-BY-Nurnberg-202503200800.lit.csv)

#### Scripts

* [Load GeoJSON and convert it to SDO_GEOMETRY](./scripts/10_load_and_convert_geojson.sql)
* [Load JSON and convert it to SDO_GEOMETRY](./scripts/11_load_and_convert_json.sql)
* [Load data from Web Feature Service](./scripts/12_load_data_from_wfs.md)
* [Load maps from Web Map Service](./scripts/13_load_maps_from_wms.md)

### Embed a published Spatial Studio project

* [Prerequisites for embedding a published project](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/spstu/prerequisites-embedding-public-published-project.html)
* [Embedding in an APEX application](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/spstu/embedding-published-project-apex-application.html)
* [Embedding in a third-party web application](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/spstu/embedding-published-project-third-party-web-applications.html)

### Vector Tiles for large spatial data sets

Here is [a brief intro to the Vector Tiles support and how to use it is used](https://medium.com/@kpatenge/how-to-create-vector-tiles-from-spatial-data-managed-in-the-oracle-database-db662f2b5544).

A tile cache is defined as a set of vector tiles that share a table_name/geom_col_name pair. For example table_a/geom_col and table_b/geom_col are two different tile caches. Each of these caches are maintained in the following two tables:

* `SDO_VECTOR_TILE_CACHE$INFO`: This table contains one row of the cache metadata.
* `SDO_VECTOR_TILE_CACHE$TABLE`: This table contains many rows, each of which is an individual vector tile.

#### DML and DDL Operations on Vector Tile Cache Source Table

In order to ensure that the cache remains consistent during DML and DDL operations, triggers are placed appropriately on the database table that provides the source data for the vector tiles in the cache. If a DML operation is performed on the source table, then those tiles in the cache that contain data generated from the modified, inserted, or deleted rows are removed from the cache. The next time `SDO_UTIL.GET_VECTORTILE` is called, these tiles are rebuilt using the new data, and are stored back in the cache.

It is strongly recommended that the vector tile caches are disabled before any large scale DML operations. It is because each DML operation performs a spatial operation to check if the row being modified interacts with any of the tiles in the cache. This has the potential to slow the DML operation substantially. Therefore, disabling the cache before the DML operations removes this slow down. You can reenable the cache after the DML operations are completed. In case of small DML operations, you may leave the cache enabled. Although the DML operations may be comparatively slower, it is still preferable than having to rebuild the cache.

#### Scripts

* [Create vector tiles and a REST interface](./scripts/20_create_vector_tiles.sql)
* [Cache vector tiles](./scripts/21_cache_vector_tiles.sql)
* [Single-page web app showing the vector tiles](./scripts/22_vector_tiles_single_page_app.html)
* [Create H3 index and a REST interface](./scripts/22_vector_tiles_single_page_app.html)

### In-database routing and drive-time/iso polygons

The following subprograms support Oracle Spatial routing capabilities and are available on Oracle Autonomous Database 23ai:

* SDO_GCDR.ELOC_ROUTE
* SDO_GCDR.ELOC_ROUTE_DISTANCE
* SDO_GCDR.ELOC_ROUTE_GEOM
* SDO_GCDR.ELOC_ROUTE_TIME
* SDO_GCDR.ELOC_DRIVE_TIME_POLYGON
* SDO_GCDR.ELOC_DRIVE_DISTANCE_POLYGON
* SDO_GCDR.ELOC_ISO_POLYGON

The documentation for 23ai is available [here](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/sdo_gcdr-package-geocoding.html).

#### Scripts

* [Simple route requests](./scripts/31_simple_route_request.sql)
* [Calculate drive-time polygons](./scripts/32_calculate_drive_time_polygons.sql)
* [Calculate iso polygons](./scripts/33_calculate_iso_polygons.sql)

## More links

* [Oracle Spatial and Graph LinkedIn group](https://www.linkedin.com/groups/1848520/)
* [AskTOM Spatial Office Hours on Youtube](https://www.youtube.com/playlist?list=PL3ZqpALcm8HP5glGHJfYLvOzQmjn9QEkn)
* [AskTOM Spatial Office Hours scripts and data](https://github.com/karinpatenge/asktom-spatial)
* [AskTOM Spatial Office Hours landing page](https://asktom.oracle.com/ords/r/tech/catalog/series-landing-page?p5_oh_id=7761)
