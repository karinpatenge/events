# OGC Web Map Service

This standard provides a simple HTTP interface for requesting geo-registered map images from one or more distributed geospatial databases. A WMS request defines the geographic layer(s) and area of interest to be processed. The response to the request is one or more geo-registered map images (returned as JPEG, PNG, etc) that can be displayed in a browser application.

Use Spatial Studio to load the maps. Make sure to register [https://metadaten.geoportal-bw.de](https://metadaten.geoportal-bw.de)
as **Safe Domain**.

## Requests

* [OSM Terrestris getCapabilities Request](https://ows.terrestris.de/osm/service?service=WMS&version=1.1.1&request=getCapabilities)
* [WMS Topplusopen getCapabilities Request](https://sgx.geodatenzentrum.de/wms_topplus_open?request=GetCapabilities&service=wms)

## Next steps

1. Create connections in Spatial Studio
2. Create data sets using WMS connections
3. Display data sets on a map
4. Embed a published project in an APEX application

## Documentation

* [OGC Web Map Service](https://www.ogc.org/standards/wms/)
* [Oracle Spatial Studio](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/index.html)
* [Embedding a Published Project in an APEX Application ](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/spstu/embedding-published-project-apex-application.html)

## Abbreviations

* GML: [Geography Markup Language](https://www.ogc.org/standards/gml/)
* OSM: [OpenStreetMap](https://www.openstreetmap.org)
