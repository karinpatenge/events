# From IoT Data to Intelligent Action – demo code

Demo for the session *From IoT Data to Intelligent Action with Agentic AI and Graph Analytics* (AOUG Vienna, RoOUG Bucharest, 2026).

A synthetic district heating network (2 plants, 10 pump stations, 40 substations, 200 buildings) runs inside **Oracle Autonomous AI Database 26ai**: a scheduler job plays the 50 field devices, sends their readings to the **OCI IoT Platform** like real devices, and stores them in the database. **SQL property graphs** and **DBMS_OGA** graph algorithms find root causes, critical assets and what-if effects. An **APEX** app visualizes the graph. An agent in the **Oracle AI Database Private Agent Factory** explains and acts through governed PL/SQL tools, and a coding agent with **Oracle Skills** and the **SQLcl MCP Server** writes new tools.

Everything runs in OCI. You need SQLcl (or SQL Developer for VS Code), a browser and OCI Cloud Shell; no Python and no process on your laptop.

| Folder | Content |
|---|---|
| `sql/` | `00_admin_setup.sql` (ADMIN), `00_check_prereqs.sql`, `00_install.sql` (runs all others), schema, generated network (`02_network_vie.sql`, `02_network_buc.sql`), 7-day history, property graphs, analytics, optional IoT pull, **device simulation** (`06b_device_sim.sql`), agent API, job, APEX views, demo queries for acts 2 and 3, `test_agent_tools.sql` (calls every agent tool once), `test_all.sql` (retests the whole demo with PASS/FAIL, see below), `stop_tick_job.sql` (stops the job, waits for a running tick), `demo_state.sql` (sets the demo state `base`, `incident` or `bypass`), teardown |
| `iot/` | DTDL models, adapters, `setup_iot.sh` (OCI CLI in Cloud Shell: models, adapters, 50 twins, relationships) |
| `agent/` | Private Agent Factory flows and prompts; coding agent with Oracle Skills |
| `apex/` | APEX app build guide (Graph Visualization plug-in, map, incident page) |
| `python/` | Optional: `generate_network.py` (only to regenerate the two network scripts) and `simulator.py` (devices outside the database, not used by the demo) |
| `logs/` | Your SQLcl spool files (not in Git) |

## How the data flows

```text
Autonomous AI Database, scheduler job DH_TICK_JOB, every 30 s
  1. DH_DEVICE_SIM.tick   one reading per twin (50), from the network state:
                          PS-04 tripped? bypass BYP-1 open? which substations get heat?
       ├─ INSERT into DH_TELEMETRY                       (INGEST_MODE = DIRECT, default)
       └─ HTTPS POST to the IoT Platform device endpoint (IOT_PUBLISH = Y)
            → adapter → digital twin content and history, visible in the OCI Console
              (time with 6 decimal places; rejected posts land in REJECTED_DATA, step 7)
  2. DH_ANALYTICS.run     anomalies and health status
  graphs, APEX app and agent tools read the tables
```

The database writes its readings itself; it does not read them back from the IoT Platform. Reading them back through the IoT Data API is possible (optional chapter below), but it needs an OAuth application and a user in an identity domain.

## Quick start

From the `scripts` folder in SQLcl (see `login.sql` for the session settings):

```sql
-- as ADMIN
@sql/00_admin_setup.sql
-- as OGBEMEA2026
@sql/00_check_prereqs.sql
SPOOL logs/install_vie.log
@sql/00_install.sql vie
SPOOL OFF
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
```

The install asks for the IoT domain short ID, the device password and whether to publish; press Enter at all of them if the IoT Platform is not set up yet. The demo then runs without it (`IOT_PUBLISH = N`). Trip the pump station with `EXEC dh_device_sim.trip('PS-04')`, wait two minutes and run the queries below. To add the IoT Platform, follow the next chapter.

How many buildings are cold, and where:

```sql
SELECT district, COUNT(*) AS cold_buildings, SUM(apartments) AS apartments
FROM   dh_assets
WHERE  asset_type = 'BUILDING' AND health_status = 'ALARM'
GROUP  BY district
ORDER  BY cold_buildings DESC;
```

Which open anomalies sit upstream of the cold buildings (SQL/PGQ: anomaly → asset → 1 to 4 open pipes → cold building):

```sql
SELECT suspect, suspect_name,
       COUNT(DISTINCT cold_building)                           AS cold_buildings_explained,
       LISTAGG(DISTINCT anomaly_type || ' ' || severity, ', ') AS evidence
FROM   GRAPH_TABLE (dh_network
         MATCH (an IS anomaly WHERE an.status <> 'CLOSED')
               -[IS detected_on]-> (s IS asset)
               -[p IS supplies WHERE p.valve_state = 'OPEN']->{1,4}
               (b IS asset WHERE b.asset_type = 'BUILDING' AND b.health_status = 'ALARM')
         COLUMNS (s.asset_id AS suspect, s.name AS suspect_name, b.asset_id AS cold_building,
                  an.anomaly_type, an.severity))
GROUP  BY suspect, suspect_name
ORDER  BY cold_buildings_explained DESC;
```

The same analysis as the AI agent gets it, grouped into incidents with root cause, evidence and classification:

```sql
SET LONG 100000
SELECT JSON_SERIALIZE(agent_find_root_cause() RETURNING CLOB PRETTY) AS root_cause FROM dual;
```

After the trip, PS-04 explains 40 cold buildings, and SS-09.3 (a stuck sensor) explains another 5. None of these queries needs `DBMS_OGA`.

## Retesting everything

`sql/test_all.sql` reinstalls the demo for one city and checks tracker steps A5 to C6 automatically: schema, network, history, graphs, analytics, all packages, Acts 2 and 3, all agent tools and the simulation (trip, bypass, repair, reset, with waits for the job). It ends with a PASS/FAIL list, in German (as used in Austria) for `vie` and in Romanian for `buc`, and keeps the results in table `DH_TEST_RESULTS`. It takes about 12 minutes.

```sql
SPOOL logs/test_all_vie.log
@sql/test_all.sql vie            -- or: buc
SPOOL OFF
```

With `clean` as second argument (`@sql/test_all.sql buc clean`) it first removes all demo objects (`99_teardown.sql`) and installs from scratch; the IoT settings, including the encrypted device password, are saved and restored. At the install's IoT questions, press Enter to keep the current values.

## Operating the simulation

| Action | SQL |
|---|---|
| State in one line | `SELECT dh_device_sim.status FROM dual;` |
| Trip PS-04 (spike at the next tick, stopped at the one after) | `EXEC dh_device_sim.trip('PS-04')` |
| Repair PS-04 | `EXEC dh_device_sim.repair('PS-04')` |
| Open / close bypass BYP-1 (also the APEX button) | `EXEC dh_set_valve('BYP-1', 'OPEN')` / `'CLOSED'` |
| One step by hand (job disabled) | `EXEC dh_job_tick` |
| Start / stop | `EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')` / `DISABLE` |
| Reset everything before a rehearsal | `@sql/demo_state.sql base` (or `incident` / `bypass` to rehearse a later act) |
| Messages of the job | `SELECT logged_at, step, message FROM dh_job_log ORDER BY log_id DESC FETCH FIRST 20 ROWS ONLY;` |
| Result of the last POST per twin | `SELECT asset_id, last_http_status, last_error FROM dh_sim_state ORDER BY asset_id;` |

## Setting up the OCI IoT Platform

This chapter connects the simulated devices to the OCI IoT Platform, so that Act 1 can show the twins updating live in the OCI Console. You need permissions for IoT resources, a Vault secret and one policy; no identity domain.

Everything is done in the **OCI Console**, apart from creating the 50 twins, which `iot/setup_iot.sh` does with the OCI CLI in Cloud Shell. Use **one region** for all IoT resources (the demo uses Frankfurt, `eu-frankfurt-1`). Keep a text file open for the values you collect: they are marked **→ note**.

Docs: [IoT Platform](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/home.htm) · [Creating an IoT domain group](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/create-domain-group.htm) · [Creating an IoT domain](https://docs.oracle.com/iaas/Content/internet-of-things/create-domain.htm). The Oracle Skill `oci/iot-platform` ([github.com/oracle/skills](https://github.com/oracle/skills)) helps a coding agent with the CLI side.

### 1. Permissions

If you are not a tenancy administrator, ask for a policy like this (Identity & Security → Policies):

```text
Allow group <your-group> to manage iot-family in compartment <compartment>
```

### 2. IoT domain group

1. Console → Developer Services → **Internet of Things** → **Domain groups** → **Create domain group**.
2. Name `dh-demo-iot-domain-group`, your compartment, type **Development** (cheaper; the type can't be changed later).
3. **Create** and wait until the work request shows *Succeeded* and the group is *Active*.
4. Tab **Data access** → *Data host*, e.g. `abc123xyz.data.iot.eu-frankfurt-1.oci.oraclecloud.com`.
   **→ note** the host and its first part, before the first dot: that is the **domain group short ID** (`abc123xyz`).
   The Console has no separate field for it; it appears only in the data host. In Cloud Shell: `oci iot domain-group get --iot-domain-group-id <group-ocid> --query 'data."data-host"' --raw-output`.

### 3. IoT domain

1. Internet of Things → **Domains** → select the compartment → **Create domain**.
2. Name `dh-demo-iot-domain`, select the domain group from step 2 → **Create**.
3. Open the domain:
   - **→ note** the **OCID** (tab *Details*), needed by `setup_iot.sh`.
   - *Endpoint* (device host), e.g. `def456uvw.device.iot.eu-frankfurt-1.oci.oraclecloud.com`. **→ note** the host (the database posts the readings there) and its first part, the **domain short ID** (`def456uvw`).
   - *Data retention time*: historized data is kept 30 days by default. That is enough for the demo.

### 4. Device password in OCI Vault

The twins authenticate with a password stored in Vault (one secret shared by all 50 demo twins).

1. Identity & Security → **Vault** → create a vault (or use one) and a **master encryption key** in it.
2. In the vault: **Secrets** → **Create secret**, name `dh-demo-device-pwd`, plain-text content = the device password. **→ note** the secret **OCID** and the password (it goes into `DH_CONFIG` as `IOT_DEVICE_PASSWORD`, step 6).
3. Policy, so the IoT domain may read the secret:
   ```text
   Allow any-user to {SECRET_BUNDLE_READ, SECRET_READ} in compartment <compartment>
     where ALL {request.principal.type = 'iotdomain', target.vault.id = '<vault-ocid>'}
   ```

### 5. Digital twins (Cloud Shell)

Creating 2 models, 2 adapters, 50 twins and their `feeds` relationships by hand would take hours, so a script does it. It is idempotent: it only creates what is missing.

1. Console → **Cloud Shell** (icon at the top right; it has `oci` and `jq`, no setup needed).
2. Upload or clone this repository (at least `scripts/iot/` and `data/network_<city>.json`).
3. Run, with the OCIDs from steps 3 and 4:
   ```bash
   export IOT_DOMAIN_ID=<iot-domain-ocid> DEVICE_SECRET_ID=<secret-ocid>
   WITH_RELATIONSHIPS=1 bash scripts/iot/setup_iot.sh vie     # or: buc
   ```
   `bash` in front is needed after an upload from Windows: the upload drops the execute permission, and `./scripts/iot/setup_iot.sh` then ends with *Permission denied* (alternative: `chmod +x scripts/iot/setup_iot.sh` once).
   **Switching cities** (talk in Bucharest after Vienna, or after `@sql/test_all.sql buc`): run `bash scripts/iot/setup_iot.sh buc` (or `vie`) again. The 50 twins stay (same asset ids, same topology); the script renames them to the names of that city, for example *PS-04 Pump station Rahova* instead of *PS-04 Pump station Favoriten*. The data flow does not change: the simulation authenticates with the external key = asset id.
4. Check in the Console: Domains → `dh-demo-iot-domain` → *Digital twin instances* shows 50 instances.

The script also writes `data/twins_<city>.sql` (`twins_vie.sql` or `twins_buc.sql`): one `UPDATE dh_assets SET twin_ocid = …` per twin. The demo does not need it; only the chapter [Optional: reading the data back through the IoT Data API](#optional-reading-the-data-back-through-the-iot-data-api) does, because the IoT Data API returns readings by twin OCID, not by asset id.

### 6. Values for the database

| `DH_CONFIG` name | Value | From |
|---|---|---|
| `IOT_DEVICE_HOST` | device host, e.g. `def456uvw.device.iot.eu-frankfurt-1.oci.oraclecloud.com` | step 3 |
| `IOT_DEVICE_PASSWORD` | the device password (content of the Vault secret) | step 4 |
| `IOT_PUBLISH` | `Y` | — |

`IOT_DEVICE_ENDPOINT` stays `/dh/telemetry` (the endpoint of the adapters in `iot/`). Each twin authenticates with its external key, which is the asset id (`PS-04`), and the device password.

`sql/01_schema.sql` (also run by `00_install.sql`) asks for all three: the domain short ID (it builds `IOT_DEVICE_HOST` from it), the device password (typed hidden, never written to a spool file) and whether to publish. Press Enter to keep a value. To set them later, run only that script again:

```
@sql/01_schema.sql
```

The password must not contain a single quote (`'`).

The password is stored encrypted: `SELECT name, value FROM dh_config` shows `********`. This keeps it out of query results and screen shares; it is masking, not real protection, because the schema owner can decrypt it. In production, keep it in OCI Vault.

### 7. Test

```sql
SET SERVEROUTPUT ON
EXEC dh_device_sim.publish_test('PS-04')
```

- `HTTP 200` (or another 2xx status): open Internet of Things → Domains → `dh-demo-iot-domain` → *Digital twin instances* → `PS-04 …` → tab *Data* (latest snapshot). It shows the test values (vibration 2.1, bearing temperature 52.4).
  The same in Cloud Shell:
  ```bash
  TWIN=$(oci iot digital-twin-instance list --iot-domain-id "$IOT_DOMAIN_ID" --all --output json |
         jq -r '(.data.items // .data)[] | select(."external-key" == "PS-04") | .id')
  oci iot digital-twin-instance get-content --digital-twin-instance-id "$TWIN"
  ```
  HTTP 2xx (usually `202 Accepted`) only means the post was accepted; the values are processed afterwards. If the *Data* tab stays `{}`, the IoT domain wrote the reason to its table `REJECTED_DATA`. To read it (no identity domain needed):
  1. Cloud Shell, once (password typed hidden, at least 12 characters):
     ```bash
     read -s -p "APEX password for the IoT data: " APW; echo
     oci iot domain configure-apex-data-access --iot-domain-id "$IOT_DOMAIN_ID" --db-workspace-admin-initial-password "$APW"
     unset APW
     ```
  2. Log in to `https://<domain-group-short-id>.data.iot.eu-frankfurt-1.oci.oraclecloud.com/ords/r/apex/workspace`, workspace and user `<domain-short-id>__WKSP` (domain short ID, two underscores).
  3. SQL Workshop → SQL Commands, Schema `<domain-short-id>__IOT`:
     ```sql
     SELECT * FROM rejected_data FETCH FIRST 10 ROWS ONLY;
     ```
     Example: `Text '2026-10-28T14:35:26.175Z' could not be parsed at index 20` means the time needs 6 fractional digits (`.175000Z`); `06b_device_sim.sql` sends them since 2026-10-28.
- `HTTP 401`: device password or external key wrong, or the policy from step 4 is missing.
- `HTTP 404`: device host or endpoint wrong (step 3, `IOT_DEVICE_ENDPOINT`).
- `HTTP -1` with an error text: the database could not reach the host (check the host name).

Then enable the job and check after a minute:

```sql
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
SELECT dh_device_sim.status FROM dual;          -- "publish: 50 ok, 0 failed"
```

The *Data* tab of the twins now changes every 30 seconds (refresh the page).

## Optional: reading the data back through the IoT Data API

The demo does not need this. Use it if you want the database to read the historized data from the IoT Platform instead of writing it directly (`INGEST_MODE = IOT`). It needs an identity domain in which you may create an OAuth application, a user and a group (not the *Default* domain). Docs: [Connecting IoT data to ORDS](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-iot-ords.htm).

### A. Identity domain and OAuth application

The database gets an OAuth token from an identity domain and calls the IoT Data API (ORDS) with it.

1. Identity & Security → **Domains**. Use an identity domain that is **not** the *Default* domain, in the same region, or create one (type *Free*; when creating, turn off *use the email address as user name* for the domain administrator).
2. In the domain: **Settings** → *Domain settings* → *Access signing certificate* → enable **Configure client access** → Save.
3. **Integrated applications** → **Add application** → **Confidential Application**, name `dh-demo-iot-reader-app` → Submit → **Activate**.
4. Tab **OAuth configuration** → **Edit OAuth configuration**:
   - **Resource server configuration** → *Configure this application as a resource server now*: primary audience `/<domain-group-short-id>` (lower case; the first part of the data host from step 2), add scope `/iot/<domain-short-id>` (from step 3). Example: audience `/abc123xyz`, scope `/iot/def456uvw`.
   - **Client configuration** → *Configure this application as a client now*: grant types **Resource owner**, **Client credentials**, **JWT assertion**, **Refresh token**; allowed operations **Introspect**; token issuance policy **All** → Submit.
5. Tab **OAuth configuration** → *General information*: **→ note** the **Client ID** and the **Client secret** (*Show secret*).
6. Back on the identity domain's page (Identity & Security → Domains → your domain), tab **User management**:
   - *Users* → **Create** user `dh-demo-iot-reader` with an e-mail address you can read. Activate it from the e-mail and set its password. **→ note** user name and password.
   - *Groups* → **Create** group `dh-demo-iot-readers` and add the user.

   **Or use an existing user and group** of this identity domain. Skip the two *Create* actions and pick them in item 7 instead. The user must meet these conditions:
   - It is a local user of this identity domain with its own password. A user who signs in through federation (SSO with another identity provider) has no password the token request can use.
   - It can sign in with user name and password only. The token request (grant type *Resource owner*) has no step for multi-factor authentication, so it can fail if a sign-on policy requires MFA for this user.
   - It is a member of the group you assign.

   The password is stored in the demo schema (`IOT_PASSWORD`, step C). So use a technical user rather than your personal account. In step C, enter this user's name for `IOT_USER`.
7. In the application: tab **Users** → *Assign users* → `dh-demo-iot-reader` (or your existing user); tab **Groups** → *Assign groups* → `dh-demo-iot-readers` (or your existing group).
8. Domain **Details** → *Domain URL*, e.g. `https://idcs-0123abcd.identity.oraclecloud.com:443`. **→ note** the host part without `https://` and the port, the **identity domain host** (`idcs-0123abcd.identity.oraclecloud.com`).

### B. Allow ORDS access for the IoT domain

1. Internet of Things → Domains → `dh-demo-iot-domain` → **Actions** → **Change data access**.
2. Choose **Oracle REST Data Services (ORDS) access**, enter the identity domain host from step A → **Update**.
3. Wait for the work request to succeed (domain tab *Work requests*).

### C. Values for the database

| `DH_CONFIG` name | Value | From |
|---|---|---|
| `IOT_DATA_API_BASE` | `https://<data-host>/ords/<domain-short-id>/20250531` | steps 2 and 3 |
| `IOT_TOKEN_URL` | `https://<identity-domain-host>/oauth2/v1/token` | step A |
| `IOT_SCOPE` | `/<domain-group-short-id>/iot/<domain-short-id>` | steps 2 and 3 |
| `IOT_CLIENT_ID`, `IOT_CLIENT_SECRET` | client ID and secret | step A |
| `IOT_USER`, `IOT_PASSWORD` | `dh-demo-iot-reader` (or your existing user) and its password | step A |

These settings exist only on this path: the statement below creates them (or updates them on a re-run). Run it in SQLcl as `OGBEMEA2026`, without `SPOOL`, so that no secret ends up in a log file:

```sql
SET VERIFY OFF
ACCEPT dg   CHAR PROMPT 'Domain group short ID: '
ACCEPT ds   CHAR PROMPT 'Domain short ID: '
ACCEPT idcs CHAR PROMPT 'Identity domain host (idcs-...identity.oraclecloud.com): '
ACCEPT cid  CHAR PROMPT 'Client ID: '
ACCEPT csec CHAR PROMPT 'Client secret: ' HIDE
ACCEPT usr  CHAR PROMPT 'User: '
ACCEPT pwd  CHAR PROMPT 'Password: ' HIDE
MERGE INTO dh_config t
USING (VALUES
  ('IOT_DATA_API_BASE', LOWER('https://&dg..data.iot.eu-frankfurt-1.oci.oraclecloud.com/ords/&ds./20250531')),
  ('IOT_TOKEN_URL',     LOWER('https://&idcs./oauth2/v1/token')),
  ('IOT_SCOPE',         LOWER('/&dg./iot/&ds.')),
  ('IOT_CLIENT_ID',     '&cid.'),
  ('IOT_USER',          '&usr.')
) s (name, value)
ON (t.name = s.name)
WHEN MATCHED THEN UPDATE SET t.value = s.value
WHEN NOT MATCHED THEN INSERT (name, value) VALUES (s.name, s.value);
-- the two secrets are stored encrypted (DH_CONFIG shows '********')
EXEC dh_secret.set_secret('IOT_CLIENT_SECRET', '&csec.')
EXEC dh_secret.set_secret('IOT_PASSWORD', '&pwd.')
COMMIT;
```

The client secret and the password are stored encrypted (masked as `********`); the schema owner can still decrypt them. In production, keep them in OCI Vault.

### D. Test and switch

```sql
SELECT name, value FROM dh_config WHERE name LIKE 'IOT%' ORDER BY name;   -- secrets show ********

SET SERVEROUTPUT ON
EXEC dh_iot_sync.pull(p_verbose => TRUE)
```

- The pull ends with `page n: … items` and `… rows merged` (0 items if nothing was published yet): the token and the Data API work.
- An error shows the HTTP status: `Token request failed` points to step A (client, user, scope), `historizedData failed: HTTP 401` to step B.
- The pull maps readings to assets by twin OCID: run `data/twins_<city>.sql` (written by `setup_iot.sh`, step 5) as `OGBEMEA2026` once.
- Switch: `UPDATE dh_config SET value = 'IOT' WHERE name = 'INGEST_MODE'; COMMIT;` The job then publishes and pulls; the simulation no longer writes directly. Back: `'DIRECT'`.

All data is synthetic. District names are real, everything else (assets, topology, measurements, incidents) is invented.

License: UPL 1.0 (suggested).
