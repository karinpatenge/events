-- REST ENABLE
BEGIN
    ORDS_ADMIN.ENABLE_SCHEMA(
        p_enabled => TRUE,
        p_schema => 'ROOUGUSER',
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => 'roouguser',
        p_auto_rest_auth=> TRUE
    );
END;
/

-- Alternative (as user ROOUGUSER)
EXEC ORDS.ENABLE_SCHEMA();