# In-database routing

The `MDSYS.SDO_GCDR` package contains subprograms for performing in-database geocoding and routing. It is available as of Oracle Database 19c and an additional feature for Autonomous Database.  
`SDO_GCDR.ELOC_ROUTE` computes the route between two locations and returns a JSON CLOB object that includes the route distance, route time, and geometry of the route in GeoJSON format.  
The input locations can either be single-line addresses or be specified by geographic coordinates.

## Documentation

* [Oracle Database 23ai](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/sdo_gcdr-package-geocoding.html)
* [Oracle Database 19c](https://docs.oracle.com/en/database/oracle/oracle-database/19/spatl/SDO_GCDR-reference.html)

## Prerequisites

* Autonomous Database 19c or 23ai
* Database permission granted to the application user via `SDO_GCDR.ELOC_GRANT_ACCESS`

## Functions

### SDO_GCDR.ELOC_ROUTE

Computes the route between two locations and returns a JSON CLOB object that includes the route distance, route time, and geometry of the route in GeoJSON format.

The input locations can either be single-line addresses or be specified by geographic coordinates.

```sql
SDO_GCDR.ELOC_ROUTE(
  route_preference        IN  VARCHAR2,
  distance_unit           IN  VARCHAR2,
  time_unit               IN  VARCHAR2,
  start_address           IN  VARCHAR2,
  end_address             IN  VARCHAR2,
  country                 IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN CLOB;
```

```sql
SDO_GCDR.ELOC_ROUTE(
  route_preference        IN  VARCHAR2,
  distance_unit           IN  VARCHAR2,
  time_unit               IN  VARCHAR2,
  start_longitude         IN  NUMBER,
  start_latitude          IN  NUMBER,
  end_longitude           IN  NUMBER,
  end_latitude            IN  NUMBER,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN CLOB;
```

### SDO_GCDR.ELOC_ROUTE_DISTANCE

Computes the route distance between two locations.

The input locations can either be single-line addresses or be specified by geographic coordinates.

```sql
SDO_GCDR.ELOC_ROUTE_DISTANCE(
  route_preference        IN  VARCHAR2,
  distance_unit           IN  VARCHAR2,
  start_address           IN  VARCHAR2,
  end_address             IN  VARCHAR2,
  country                 IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN NUMBER;
```

```sql
SDO_GCDR.ELOC_ROUTE_DISTANCE(
  route_preference        IN  VARCHAR2,
  distance_unit           IN  VARCHAR2,
  start_longitude         IN  NUMBER,
  start_latitude          IN  NUMBER,
  end_longitude           IN  NUMBER,
  end_latitude            IN  NUMBER,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN NUMBER;
```

## SDO_GCDR.ELOC_ROUTE_GEOM

Computes the route between two locations and returns the geometry of the route in SDO_GEOMETRY format.

The input locations can either be single-line addresses or be specified by geographic coordinates.

```sql
SDO_GCDR.ELOC_ROUTE_GEOM(
  route_preference        IN  VARCHAR2,
  start_address           IN  VARCHAR2,
  end_address             IN  VARCHAR2,
  country                 IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

```sql
SDO_GCDR.ELOC_ROUTE_GEOM(
  route_preference        IN  VARCHAR2,
  start_longitude         IN  NUMBER,
  start_latitude          IN  NUMBER,
  end_longitude           IN  NUMBER,
  end_latitude            IN  NUMBER,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

### SDO_GCDR.ELOC_ROUTE_TIME

Computes the travel time between two locations.

The input locations can either be single-line addresses or be specified by geographic coordinates.

```sql
SDO_GCDR.ELOC_ROUTE_TIME(
  route_preference        IN  VARCHAR2,
  time_unit               IN  VARCHAR2,
  start_address           IN  VARCHAR2,
  end_address             IN  VARCHAR2,
  country                 IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN NUMBER;
```

```sql
SDO_GCDR.ELOC_ROUTE_TIME(
  route_preference        IN  VARCHAR2,
  time_unit               IN  VARCHAR2,
  start_longitude         IN  NUMBER,
  start_latitude          IN  NUMBER,
  end_longitude           IN  NUMBER,
  end_latitude            IN  NUMBER,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN NUMBER;
```

### SDO_GCDR.ELOC_DRIVE_TIME_POLYGON

Computes the drive time polygon around an input location for the specified cost, and returns the geometry of the polygon in SDO_GEOMETRY format.

The input location can either be a single-line address or be specified as longitude and latitude.

```sql
SDO_GCDR.ELOC_DRIVE_TIME_POLYGON(
  start_address           IN  VARCHAR2,
  country                 IN  VARCHAR2,
  cost                    IN  NUMBER,
  cost_unit               IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

```sql
SDO_GCDR.ELOC_DRIVE_TIME_POLYGON(
  longitude               IN  NUMBER,
  latitude                IN  NUMBER,
  cost                    IN  NUMBER,
  cost_unit               IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

### SDO_GCDR.ELOC_DRIVE_DISTANCE_POLYGON

Computes the drive distance polygon around an input location for the specified distance cost, and returns the geometry of the polygon in SDO_GEOMETRY format.

The input location can either be a single-line address or be specified as longitude and latitude.

```sql
SDO_GCDR.ELOC_DRIVE_DISTANCE_POLYGON(
  start_address           IN  VARCHAR2,
  country                 IN  VARCHAR2,
  cost                    IN  NUMBER,
  cost_unit               IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

```sql
SDO_GCDR.ELOC_DRIVE_DISTANCE_POLYGON(
  longitude               IN  NUMBER,
  latitude                IN  NUMBER,
  cost                    IN  NUMBER,
  cost_unit               IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN SDO_GEOMETRY;
```

### SDO_GCDR.ELOC_ISO_POLYGON (19c)

Computes the drive time polygon around an input location for the specified cost, and returns a JSON CLOB object that includes the cost, cost unit, and geometry of the polygon in GeoJSON format.

The input location can either be a single-line address or be specified as longitude and latitude.

```sql
SDO_GCDR.ELOC_ISO_POLYGON(
  iso                     IN  VARCHAR2,
  start_address           IN  VARCHAR2,
  country                 IN  VARCHAR2,
  cost                    IN  NUMBER,
  cost_unit               IN  VARCHAR2,
  vehicle_type            IN  VARCHAR2,
  print_request_response  IN  VARCHAR2 DEFAULT 'FALSE'
) RETURN CLOB;
```

```sql

```

## Abbreviations

* GCDR: Geocoder
* SDO: Spatial Data Objects
