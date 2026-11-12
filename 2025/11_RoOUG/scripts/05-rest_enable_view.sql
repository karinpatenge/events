-- REST ENABLE
BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled => TRUE,
    p_schema => 'ROOUGUSER',
    p_object => 'METEO_STATIONS_ROU_FC',
    p_object_type => 'VIEW',
    p_object_alias => 'meteo_stations_rou_fc',
    p_auto_rest_auth => FALSE);
  COMMIT;
END;
/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled => TRUE,
    p_schema => 'ROOUGUSER',
    p_object => 'METEO_STATIONS_ROU_FC',
    p_object_type => 'VIEW',
    p_object_alias => 'meteo_stations_rou_fc',
    p_auto_rest_auth => TRUE);
  COMMIT;
END;
/
