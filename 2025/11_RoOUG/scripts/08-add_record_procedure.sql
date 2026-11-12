CREATE OR REPLACE PROCEDURE add_city (
  p_city       IN VARCHAR2,
  p_lat        IN NUMBER,
  p_lon        IN NUMBER,
  p_population IN NUMBER
)
AS
  v_id NUMBER;
BEGIN

  v_id := cities_rou_seq.nextval();

  INSERT INTO cities_rou (
    id,
    city,
    lat,
    lon,
    location,
    population
  ) VALUES (
    v_id,
    p_city,
    p_lat,
    p_lon,
    sdo_util.from_geojson('{ "type":"Point","coordinates":[' || p_lon || ',' || p_lat || ']}'),
    p_population
  );

  COMMIT;

EXCEPTION

  WHEN OTHERS THEN
    DBMS_OUTPUT.put_line('Error: ' || SQLERRM);

END;
/

-- Test
BEGIN
  add_city('Test', 10, 10, 1000);
END;
/