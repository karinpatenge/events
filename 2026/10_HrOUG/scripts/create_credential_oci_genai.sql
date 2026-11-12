/*********************************************
 * Create the credential OCI_GENAI_CRED
 * (OCI API key) for Select AI in HROUG2026
 *
 * Author: Karin Patenge
 * Date: October 2026
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-subprograms.html
-- Used by: spatial_using_select_ai.sql (AI profile OCI_GENAI_PROFILE)
--
-- Connect as the demo schema HROUG2026 (the schema that owns the AI profile).
--
-- The key values are SQLcl substitution variables, defined from ../.env (git-ignored):
--   OCI_USER_OCID     OCID of the OCI user that owns the API key
--   OCI_TENANCY_OCID  OCID of the tenancy
--   OCI_FINGERPRINT   fingerprint of the API key
--   OCI_PRIVATE_KEY   the private key (.pem) as one line, without the BEGIN/END lines
-- Run with SQLcl from the scripts folder, passing the connection at run time:
--   python run_sqlcl_with_env.py create_credential_oci_genai.sql --connect "<SQLcl connect arguments>"
--   Check the variables first: add --check (shows names and lengths only).
-- Other clients prompt for the four values.
--
-- Re-runnable: an existing credential is kept. To replace the key, drop the credential first:
--   EXEC DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'OCI_GENAI_CRED');
--

SET SERVEROUTPUT ON
SET VERIFY OFF

DECLARE
  l_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM user_credentials WHERE credential_name = 'OCI_GENAI_CRED';
  IF l_count > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Credential OCI_GENAI_CRED exists: kept.');
    RETURN;
  END IF;

  IF '&OCI_FINGERPRINT' IS NULL OR '&OCI_PRIVATE_KEY' IS NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'Set OCI_USER_OCID, OCI_TENANCY_OCID, OCI_FINGERPRINT and OCI_PRIVATE_KEY in .env first.');
  END IF;

  DBMS_CLOUD.CREATE_CREDENTIAL(
    credential_name => 'OCI_GENAI_CRED',
    user_ocid       => '&OCI_USER_OCID',
    tenancy_ocid    => '&OCI_TENANCY_OCID',
    private_key     => REGEXP_REPLACE('&OCI_PRIVATE_KEY', '-----[A-Z ]+-----|\s', ''),
    fingerprint     => '&OCI_FINGERPRINT'
  );
  DBMS_OUTPUT.PUT_LINE('Credential OCI_GENAI_CRED created.');
END;
/

-- Expected: 1 row, enabled
SELECT credential_name, enabled
FROM user_credentials
WHERE credential_name = 'OCI_GENAI_CRED';
