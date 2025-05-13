# In-database routing

The `MDSYS.SDO_GCDR` package contains subprograms for performing in-database geocoding and routing. It is available as of Oracle Database 19c and an additional feature for Autonomous Database.  
`SDO_GCDR.ELOC_ROUTE` computes the route between two locations and returns a JSON CLOB object that includes the route distance, route time, and geometry of the route in GeoJSON format.  
The input locations can either be single-line addresses or be specified by geographic coordinates.

## Documentation

* [Oracle Database 23ai](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/sdo_gcdr-package-geocoding.html)
* [Oracle Database 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/spatl/SDO_GCDR-reference.html)

## Abbreviations

* GCDR: Geocoder
* SDO: Spatial Data Objects
