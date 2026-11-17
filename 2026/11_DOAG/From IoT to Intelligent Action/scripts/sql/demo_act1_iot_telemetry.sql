-- Check PS-04 telemetry data
SELECT asset_id, metric, ts, value, source
FROM   dh_telemetry
WHERE  asset_id = 'PS-04'
ORDER  BY ts DESC
FETCH FIRST 10 ROWS ONLY;

SELECT dh_device_sim.status FROM DUAL;