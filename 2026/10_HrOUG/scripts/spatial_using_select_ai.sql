/*********************************************
 * Set up Select AI for the HrOUG 2026 demo:
 * privileges, OCI API key credential and the
 * AI profile OCI_GENAI_PROFILE in HROUG2026
 *
 * Author: Karin Patenge
 * Date: October 2026
 *********************************************/

--
-- Documentation: https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/select-ai.html
--                https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-ai-package.html
--                https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/select-ai-examples.html
-- Database: Autonomous AI Database kpadw26 (eu-frankfurt-1), demo schema HROUG2026
--
-- Two parts for two database users; connect as the user named in a part before running it:
--   Part 1: as ADMIN (or another user allowed to grant these privileges)   privileges, Spatial Studio proxy
--   Part 2: as the demo schema HROUG2026                                   credential, AI profile, tests
--
-- Re-runnable: grants can be repeated; the proxy is only added when missing; the credential is only created
-- when it does not exist yet; the profile is dropped and created again.
--
-- Credential: OCI API key of an OCI user who may use OCI Generative AI (an administrator, or a member of a group
-- with: allow group <group> to manage generative-ai-family in compartment <compartment>).
--   OCI Console > profile menu (top right) > My profile > API keys > Add API key > Generate API key pair:
--   download the private key (.pem), click Add, and copy the fingerprint from the configuration file preview.
-- The values live in ../.env (git-ignored), never in a script:
--   OCI_USER_OCID     OCID of that OCI user
--   OCI_TENANCY_OCID  OCID of the tenancy
--   OCI_FINGERPRINT   fingerprint of the API key
--   OCI_PRIVATE_KEY   the private key (.pem) as one line, without the BEGIN/END lines
-- The credential itself is created by create_credential_oci_genai.sql (see section 2.1).
--
-- The profile name OCI_GENAI_PROFILE is the one the agent ZG_SHADE_PLANNER uses
-- (created by create_tool_rank_stops_for_shade.sql, section 4).
--

-------------------------------------------------------------------------------
-- Part 1: run as ADMIN
-------------------------------------------------------------------------------

-- Connect as ADMIN (or another user allowed to grant these privileges) before running this part.

-- 1.1 Privileges for OML4Py (granting again is harmless)
GRANT SELECT ANY MINING MODEL TO aiuser;
GRANT CREATE ANY MINING MODEL TO spatialuser;
GRANT SELECT ANY MINING MODEL TO hroug2026;

-- 1.2 Privileges for Select AI and Select AI Agent
GRANT EXECUTE ON DBMS_CLOUD TO aiuser;
GRANT EXECUTE ON DBMS_CLOUD TO spatialuser;
GRANT EXECUTE ON DBMS_CLOUD TO hroug2026;
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO aiuser;
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO spatialuser;
GRANT EXECUTE ON DBMS_CLOUD_PIPELINE TO hroug2026;
GRANT EXECUTE ON DBMS_CLOUD_AI TO aiuser;
GRANT EXECUTE ON DBMS_CLOUD_AI TO spatialuser;
GRANT EXECUTE ON DBMS_CLOUD_AI TO hroug2026;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO aiuser;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO spatialuser;
GRANT EXECUTE ON DBMS_CLOUD_AI_AGENT TO hroug2026;

-- 1.3 Spatial Studio: connect through its proxy user (only where missing)
BEGIN
  FOR u IN (SELECT column_value AS username
            FROM   TABLE(sys.odcivarchar2list('SPATIALUSER', 'HROUG2026'))
            WHERE  column_value NOT IN (SELECT client FROM proxy_users WHERE proxy = 'SPATIAL$PROXY_USER'))
  LOOP
    EXECUTE IMMEDIATE 'ALTER USER ' || DBMS_ASSERT.ENQUOTE_NAME(u.username) || ' GRANT CONNECT THROUGH "SPATIAL$PROXY_USER"';
  END LOOP;
END;
/

-- 1.4 Check privileges
SELECT
  grantee, table_name AS package_name, privilege
FROM
  dba_tab_privs
WHERE
  grantee IN ('AIUSER', 'SPATIALUSER', 'HROUG2026')
  AND table_name IN ('DBMS_CLOUD_AI', 'DBMS_CLOUD_AI_AGENT', 'DBMS_CLOUD_PIPELINE')
ORDER BY
  grantee, package_name;

-- Expected: SPATIALUSER and HROUG2026
SELECT client FROM proxy_users WHERE proxy = 'SPATIAL$PROXY_USER' AND client IN ('SPATIALUSER', 'HROUG2026');

-------------------------------------------------------------------------------
-- Part 2: run as HROUG2026
-------------------------------------------------------------------------------

-- Connect as the demo schema HROUG2026 before running this part.

-- 2.1 Credential OCI_GENAI_CRED with an OCI API key
--     Created once by create_credential_oci_genai.sql, which reads the key values from ../.env.
--     Run it with SQLcl from the scripts folder, passing the connection for HROUG2026 at run time:
--       python run_sqlcl_with_env.py create_credential_oci_genai.sql --connect "<SQLcl connect arguments>"
--     To replace the key: drop the credential, update ../.env and run create_credential_oci_genai.sql again.
--       EXEC DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'OCI_GENAI_CRED');

-- Expected: 1 row, enabled
SELECT credential_name, enabled FROM user_credentials WHERE credential_name = 'OCI_GENAI_CRED';

-- 2.2 Create the AI profile (dropped first if it exists)
--     No "model": Select AI uses its default OCI Generative AI model in the region.
--     To pin one, add "model": "<model id offered in eu-frankfurt-1>".
--     object_list: the annotated demo tables; switch to the curated view STOP_HEAT_PROFILE_V once it exists.
DECLARE
  l_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_count FROM user_cloud_ai_profiles WHERE profile_name = 'OCI_GENAI_PROFILE';
  IF l_count > 0 THEN
    DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'OCI_GENAI_PROFILE');
  END IF;

  DBMS_CLOUD_AI.CREATE_PROFILE(
    profile_name => 'OCI_GENAI_PROFILE',
    attributes   => '{
        "provider": "oci",
        "credential_name": "OCI_GENAI_CRED",
        "region": "eu-frankfurt-1",
        "object_list": [
          {"owner": "HROUG2026", "name": "ZET_STOPS"},
          {"owner": "HROUG2026", "name": "ZET_STOPS_LISA"},
          {"owner": "HROUG2026", "name": "ZG_DISTRICTS"},
          {"owner": "HROUG2026", "name": "ZG_H3_FEATURES"},
          {"owner": "HROUG2026", "name": "ZG_H3_GWR"},
          {"owner": "HROUG2026", "name": "TRAM_STATIONS"}
        ],
        "comments": "true",
        "annotations": "true",
        "conversation": "true",
        "temperature": 0
      }',
    description  => 'HrOUG 2026: OCI Generative AI with an API key credential, for Select AI and the agent ZG_SHADE_PLANNER'
  );
END;
/

-- 2.3 Use the profile in this session
BEGIN
  DBMS_CLOUD_AI.SET_PROFILE(profile_name => 'OCI_GENAI_PROFILE');
END;
/

-- 2.4 Tests
-- Profile attributes
SELECT
  profile_name, attribute_name, attribute_value
FROM
  user_cloud_ai_profile_attributes
WHERE
  profile_name = 'OCI_GENAI_PROFILE'
ORDER BY
  attribute_name;

-- One round trip to OCI Generative AI with the API key.
-- An authorization error means a wrong key or fingerprint, or that the OCI user may not use Generative AI.
SELECT DBMS_CLOUD_AI.GENERATE(prompt => 'Reply with the single word OK.', profile_name => 'OCI_GENAI_PROFILE', action => 'chat') AS reply FROM dual;

-- NL2SQL on an annotated table
SELECT AI SHOWSQL show the 10 ZET stops with the most weekday departures;

-- The agent team ZG_SHADE_TEAM now finds its profile: run_tool_rank_stops_for_shade.sql tests and demos it.

-- If needed, remove the profile and the credential
-- EXEC DBMS_CLOUD_AI.DROP_PROFILE(profile_name => 'OCI_GENAI_PROFILE');
-- EXEC DBMS_CLOUD.DROP_CREDENTIAL(credential_name => 'OCI_GENAI_CRED');
