# APEX Connect 2025

## General information

[APEX Connect 2025](https://apex.doag.org/en/apex-connect-2025/) in Europa-Park Rust/DE from May 13-15, 2025.

The conference program can be found [here](https://my.doag.org/events/apex-connect/2025/agenda/#eventDay.all).

## Demos

### Simplified creation of spatial data (vector data representing points, lines, polygons, or combinations of those; aka geometries or simple features)

#### Scripts

* [Create point geometries based on lon/lat values](./scripts/01_create_point_geometries_from_lon_lat.sql) using an open [data set containing information about street lamps in Nuremberg](./data/01_DE-BY-Nurnberg-202503200800.lit.csv), and published via the [GovData Portal Germany](https://www.govdata.de/suche/daten/strassenlampen-nurnberg-de-by).
* [Typical queries queries for point geometries](./scripts/02_query_point_geometries.sql)

### Load spatial data using Spatial Studio

#### Scripts

* [Load GeoJSON](./)
* [Load from Web Feature Service](./)
* [Load raster data](./)

### Vector Tiles for large spatial data sets

#### Scripts

* [Create vector tiles](./20_create_vector_tiles_from_point_geometries.sql)
* [Vector tiles caching](./21_cache_vector_tiles.sql)
* [](./22_create_h3_for_hierarchical_aggregates_as_vector_tiles.sql)
