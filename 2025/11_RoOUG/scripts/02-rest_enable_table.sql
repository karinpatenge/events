-- REST ENABLE
BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled => TRUE,
    p_schema => 'ROOUGUSER',
    p_object => 'GADM41_LEVEL0_ROU',
    p_object_type => 'TABLE',
    p_object_alias => 'gadm41_level0_rou',
    p_auto_rest_auth => FALSE
  );
  COMMIT;
END;
/

BEGIN
  ORDS.ENABLE_OBJECT(
    p_enabled => TRUE,
    p_schema => 'ROOUGUSER',
    p_object => 'GADM41_LEVEL0_ROU',
    p_object_type => 'TABLE',
    p_object_alias => 'gadm41_level0_rou',
    p_auto_rest_auth => TRUE
  );
  COMMIT;
END;
/