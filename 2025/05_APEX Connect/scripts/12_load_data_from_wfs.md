# OGC Web Feature Service

This standard defines direct fine-grained access to geographic information at the feature and feature property level by specifying discovery, query, locking and transaction operations and operations to manage stored, parameterized query expressions.

Use Spatial Studio to load the data. Make sure to register [https://metadaten.geoportal-bw.de](https://metadaten.geoportal-bw.de)
as **Safe Domain**.

## Requests

OGC Service Provider:[Metainformationssystem GDI-BW](https://metadaten.geoportal-bw.de/)

* [getCapabilities Request](https://pegelonline.wsv.de/webservices/gis/aktuell/wfs?service=wfs&request=getcapabilities&version=1.1.0)

* [getFeature Request - Response (Default format: GML)](https://pegelonline.wsv.de/webservices/gis/aktuell/wfs?service=wfs&request=getfeature&version=1.1.0&typename=gk:waterlevels)
* [getFeature Request - Response als GeoJSON](https://pegelonline.wsv.de/webservices/gis/aktuell/wfs?service=wfs&request=getfeature&version=1.1.0&typename=gk:waterlevels&outputFormat=application/json)
* [getFeature Request - Response als JSON](https://pegelonline.wsv.de/webservices/gis/aktuell/wfs?service=wfs&request=getfeature&version=1.1.0&typename=gk:waterlevels&outputFormat=json)
* [getFeature Request - Response als CSV](https://pegelonline.wsv.de/webservices/gis/aktuell/wfs?service=wfs&request=getfeature&version=1.1.0&typename=gk:waterlevels&outputFormat=csv)

## Documentation

* [OGC Web Feature Service](https://www.ogc.org/standards/wfs/)
* [Oracle Spatial Studio](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/index.html)
* [Embedding a Published Project in an APEX Application ](https://docs.oracle.com/en/database/oracle/spatial-studio/24.2/spstu/embedding-published-project-apex-application.html)

## Abbreviations

* GML: [Geography Markup Language](https://www.ogc.org/standards/gml/)
* OGC: [Open Geospatial Consortium](https://www.ogc.org/)
