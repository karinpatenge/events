# From IoT Data to Intelligent Action – demo code

Code for the session *From IoT Data to Intelligent Action with Agentic AI and Graph Analytics* (EMEA Community Tour 2026).

A synthetic district heating network (2 heat plants, 10 pump stations, 40 substations, 200 buildings) runs inside **Oracle Autonomous AI Database 26ai**:

- A scheduler job plays the 50 field devices. Every 30 seconds it stores one reading per device in the database and, optionally, sends it to the **OCI IoT Platform** like a real device.
- **SQL property graphs** (SQL/PGQ) and **DBMS_OGA** graph algorithms find root causes, critical assets and the effect of what-if actions.
- An **Oracle APEX** app shows the network as a graph and on a map.
- An agent in the **Oracle AI Database Private Agent Factory** explains the situation and acts through governed PL/SQL tools (`AGENT_*` functions).
- A coding agent with **Oracle Skills** and the **SQLcl MCP Server** writes a new tool.

Everything runs in OCI. You need SQLcl (or SQL Developer for VS Code), a browser and, for the IoT part, OCI Cloud Shell. No Python and no process on your own machine.

All data is synthetic. District names of Vienna and Bucharest are real; assets, topology, measurements and incidents are invented.

## Contents

1. [What is in this folder](#1-what-is-in-this-folder)
2. [Placeholders](#2-placeholders)
3. [Install the database part](#3-install-the-database-part)
4. [Operate the simulation](#4-operate-the-simulation)
5. [Test](#5-test)
6. [Optional: OCI IoT Platform](#6-optional-oci-iot-platform)
7. [Optional: APEX application](#7-optional-apex-application)
8. [Optional: Private Agent Factory](#8-optional-private-agent-factory)
9. [Optional: coding agent with Oracle Skills and the SQLcl MCP Server](#9-optional-coding-agent-with-oracle-skills-and-the-sqlcl-mcp-server)
10. [Optional: reading the data back through the IoT Data API](#10-optional-reading-the-data-back-through-the-iot-data-api)
11. [Remove everything](#11-remove-everything)

---

## 1. What is in this folder

| Path | Content |
|---|---|
| `sql/00_admin_setup.sql` | Run once as the database administrator: creates the demo user and its grants |
| `sql/00_check_prereqs.sql` | Checks the prerequisites in the demo schema (graph support, `DBMS_OGA`, privileges) |
| `sql/00_install.sql` | Installs everything below in the right order, for one city (`vie` or `buc`) |
| `sql/01_schema.sql` | Tables and configuration (`DH_CONFIG`); asks for the optional IoT Platform settings |
| `sql/02_network_vie.sql`, `sql/02_network_buc.sql` | The network with the district names of Vienna or Bucharest (same topology) |
| `sql/03_backfill.sql` | 7 days of history |
| `sql/04_property_graphs.sql` | Property graphs `DH_NETWORK`, `DH_LIVE_NETWORK`, `DH_DEPENDENCY` |
| `sql/05_analytics.sql` | Anomaly detection (limits, z-scores, frozen values, trends) and health status |
| `sql/06_iot_sync.sql` | Optional: reading the data back from the IoT Data API ([section 10](#10-optional-reading-the-data-back-through-the-iot-data-api)) |
| `sql/06b_device_sim.sql` | Device simulation: readings, trip and repair, posts to the IoT Platform |
| `sql/07_agent_api.sql` | The agent tools: `AGENT_*` functions returning JSON, package `DH_GRAPH_API` |
| `sql/08_jobs.sql` | Scheduler job `DH_TICK_JOB` (every 30 seconds) |
| `sql/09_apex_support.sql` | Views for APEX and the Data Analysis Agent, procedure `DH_SET_VALVE` |
| `sql/demo_state.sql` | Puts the demo into a defined state: `base`, `incident` or `bypass` |
| `sql/stop_tick_job.sql` | Stops the job and waits for a running tick |
| `sql/test_all.sql`, `sql/test_skip.sql` | Retests the whole demo with a PASS/FAIL list |
| `sql/test_agent_tools.sql` | Calls every `AGENT_*` tool once |
| `sql/99_teardown.sql` | Removes all demo objects |
| `iot/` | DTDL models and adapters for pump stations and substations, `setup_iot.sh` (creates models, adapters and 50 digital twins with the OCI CLI) |
| `apex/` | The APEX app: overview (`README.md`), build guide (`BUILD.md`), APEXlang export |

Outside this folder, `../data/network_vie.json` and `../data/network_buc.json` describe the network for `setup_iot.sh`, and `../schema/` contains a diagram of the tables.

### How the data flows

```text
Autonomous AI Database, scheduler job DH_TICK_JOB, every 30 s
  1. DH_DEVICE_SIM.tick   one reading per twin (50), from the network state:
                          PS-04 tripped? bypass BYP-1 open? which substations get heat?
       ├─ INSERT into DH_TELEMETRY                       (INGEST_MODE = DIRECT, default)
       └─ HTTPS POST to the IoT Platform device endpoint (IOT_PUBLISH = Y, optional)
            → adapter → digital twin content and history, visible in the OCI Console
  2. DH_ANALYTICS.run     anomalies and health status
  The graphs, the APEX app and the agent tools read the tables.
```

## 2. Placeholders

| Placeholder | Meaning |
|---|---|
| `<ADMIN_USER>` | Database administrator (`ADMIN` on Autonomous AI Database) |
| `<DEMO_USER>` | Demo schema, created by `00_admin_setup.sql` (it asks for the name and suggests a default) |
| `<CITY>` | `vie` (Vienna) or `buc` (Bucharest): district names only, the network is the same |
| `<DB_NAME>`, `<DB_SERVICE>` | Database name and service, for example `<DB_NAME>_low` |
| `<WALLET_ZIP>` | Client credentials (wallet) of the database |
| `<OCI_REGION>` | OCI region for the IoT Platform and Generative AI, for example `eu-frankfurt-1` |
| `<COMPARTMENT>` | Compartment for the OCI resources |
| `<CHAT_MODEL>` | OCI Generative AI chat model with tool calling, registered in Agent Factory |
| `<AGENT_FACTORY_HOST>` | Public IP or host name of the Agent Factory VM |

---

## 3. Install the database part

Prerequisites: Oracle Autonomous AI Database 26ai and SQLcl. Run all scripts from this folder (`scripts`).

```sql
-- as <ADMIN_USER>
@sql/00_admin_setup.sql

-- as <DEMO_USER>
@sql/00_check_prereqs.sql
@sql/00_install.sql <CITY>
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
```

- `00_admin_setup.sql` asks for the name of the demo user (Enter keeps the default) and its password (typed hidden). It is idempotent: an existing user keeps its password.
- `00_install.sql` asks for the IoT Platform settings (region, IoT domain short ID, device password, whether to publish). Press Enter at all of them if you don't use the IoT Platform: the demo then runs without it (`IOT_PUBLISH = N`). [Section 6](#6-optional-oci-iot-platform) explains the values.
- To keep a log, wrap the install in `SPOOL logs/install.log` … `SPOOL OFF`. The device password is never written to the log.

### First queries

Trip a pump station, wait two minutes, then run the queries below:

```sql
EXEC dh_device_sim.trip('PS-04')
```

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

The same analysis as the agent gets it, grouped into incidents with root cause, evidence and classification:

```sql
SET LONG 100000
SELECT JSON_SERIALIZE(agent_find_root_cause() RETURNING CLOB PRETTY) AS root_cause FROM dual;
```

After the trip, PS-04 explains 40 cold buildings, and SS-09.3 (a stuck sensor) another 5. None of these queries needs `DBMS_OGA`.

---

## 4. Operate the simulation

The simulation runs in real time: one tick every 30 seconds.

| Action | SQL |
|---|---|
| State in one line | `SELECT dh_device_sim.status FROM dual;` |
| Trip PS-04 (spike at the next tick, stopped at the one after) | `EXEC dh_device_sim.trip('PS-04')` |
| Repair PS-04 | `EXEC dh_device_sim.repair('PS-04')` |
| Open / close bypass BYP-1 (also a button in the APEX app) | `EXEC dh_set_valve('BYP-1', 'OPEN')` / `'CLOSED'` |
| One step by hand (job disabled) | `EXEC dh_job_tick` |
| Start / stop the job | `EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')` / `@sql/stop_tick_job.sql` |
| Messages of the job | `SELECT logged_at, step, message FROM dh_job_log ORDER BY log_id DESC FETCH FIRST 20 ROWS ONLY;` |
| Result of the last post per twin | `SELECT asset_id, last_http_status, last_error FROM dh_sim_state ORDER BY asset_id;` |

### Demo states

`sql/demo_state.sql` resets the demo to a defined state, from scratch, as often as needed. It stops the job, removes work orders, open bypasses, what-if scenarios, live readings and anomalies, and the function `AGENT_CRITICAL_CUSTOMERS` from [section 9](#9-optional-coding-agent-with-oracle-skills-and-the-sqlcl-mcp-server). Then it writes a new 7-day history, starts the job and waits until the network has reacted.

| State | Command | Takes | Result |
|---|---|---|---|
| `base` | `@sql/demo_state.sql base` | 1–2 min | PS-04 wearing (rising vibration), PS-08 with a slow trend, SS-09.3 with a stuck sensor: **5 cold buildings** |
| `incident` | `@sql/demo_state.sql incident` | 3–4 min | `base` + PS-04 tripped and stopped: **45 cold buildings** |
| `bypass` | `@sql/demo_state.sql bypass` | 5–6 min | `incident` + bypass BYP-1 open: **25 cold buildings**, hospital and nursing home warm again |

## 5. Test

**Everything:** `sql/test_all.sql` reinstalls the demo for one city and checks schema, network, history, graphs, analytics, all packages, the graph queries and algorithms, all agent tools and the simulation (trip, bypass, repair, reset, with waits for the job). It ends with a PASS/FAIL list (in German for `vie`, in Romanian for `buc`) and keeps the results in table `DH_TEST_RESULTS`. It takes about 12 minutes.

```sql
SPOOL logs/test_all.log
@sql/test_all.sql <CITY>
SPOOL OFF
```

With `clean` as second argument (`@sql/test_all.sql <CITY> clean`) it first removes all demo objects (`99_teardown.sql`) and installs from scratch. The IoT settings, including the encrypted device password, are saved and restored; at the install's IoT questions, press Enter to keep the current values.

**Agent tools only:** `@sql/test_agent_tools.sql` calls every `AGENT_*` function once, best after the PS-04 trip. Every call must return JSON; an `error` key or an ORA- message is a failure. It creates one test work order and deletes it again.

---

## 6. Optional: OCI IoT Platform

This connects the simulated devices to the OCI IoT Platform, so the digital twins update live in the OCI Console. You need permissions for IoT resources, a Vault secret and one policy; no identity domain. Everything is done in the OCI Console, apart from the 50 twins, which `iot/setup_iot.sh` creates in Cloud Shell. Use **one region** for all IoT resources and note the values marked **→ note**.

Docs: [IoT Platform](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/home.htm) · [Creating an IoT domain group](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/create-domain-group.htm) · [Creating an IoT domain](https://docs.oracle.com/iaas/Content/internet-of-things/create-domain.htm).

### 6.1 Permissions

If you are not a tenancy administrator, ask for a policy like this (Identity & Security → Policies):

```text
Allow group <your-group> to manage iot-family in compartment <COMPARTMENT>
```

### 6.2 IoT domain group

1. Console → Developer Services → **Internet of Things** → **Domain groups** → **Create domain group**.
2. Name `dh-demo-iot-domain-group`, your compartment, type **Development** (cheaper; the type can't be changed later).
3. **Create** and wait until the group is *Active*.
4. Tab **Data access** → *Data host*, for example `abc123xyz.data.iot.<OCI_REGION>.oci.oraclecloud.com`. **→ note** the host and its first part, the **domain group short ID** (`abc123xyz`). In Cloud Shell: `oci iot domain-group get --iot-domain-group-id <group-ocid> --query 'data."data-host"' --raw-output`.

### 6.3 IoT domain

1. Internet of Things → **Domains** → **Create domain**, name `dh-demo-iot-domain`, the domain group from 6.2.
2. Open the domain:
   - **→ note** the **OCID** (tab *Details*), needed by `setup_iot.sh`.
   - *Endpoint* (device host), for example `def456uvw.device.iot.<OCI_REGION>.oci.oraclecloud.com`. **→ note** its first part, the **domain short ID** (`def456uvw`).

### 6.4 Device password in OCI Vault

The twins authenticate with a password stored in Vault (one secret shared by all 50 twins).

1. Identity & Security → **Vault** → a vault with a **master encryption key**.
2. **Secrets** → **Create secret**, name `dh-demo-device-pwd`, plain-text content = the device password. **→ note** the secret **OCID** and the password.
3. Policy, so the IoT domain may read the secret:
   ```text
   Allow any-user to {SECRET_BUNDLE_READ, SECRET_READ} in compartment <COMPARTMENT>
     where ALL {request.principal.type = 'iotdomain', target.vault.id = '<vault-ocid>'}
   ```

### 6.5 Digital twins (Cloud Shell)

`iot/setup_iot.sh` creates 2 models, 2 adapters, 50 twins and their `feeds` relationships. It is idempotent: it only creates what is missing.

1. Console → **Cloud Shell** (it has `oci` and `jq`).
2. Clone this repository, or upload at least `scripts/iot/` and `data/network_<CITY>.json`.
3. Run, with the OCIDs from 6.3 and 6.4:
   ```bash
   export IOT_DOMAIN_ID=<iot-domain-ocid> DEVICE_SECRET_ID=<secret-ocid>
   WITH_RELATIONSHIPS=1 bash scripts/iot/setup_iot.sh <CITY>
   ```
   Use `bash` in front: an upload from Windows drops the execute permission.
4. Check: Domains → `dh-demo-iot-domain` → *Digital twin instances* shows 50 instances.

Each twin's external key is its asset ID (`PS-04`), and its display name contains the district (for example *PS-04 Pump station Favoriten*). To switch cities, run the script again with the other city: it renames the twins and keeps everything else.

The script also writes `data/twins_<CITY>.sql` and `.json` with the OCIDs of your twins. They are needed only for [section 10](#10-optional-reading-the-data-back-through-the-iot-data-api) and are excluded from the repository.

### 6.6 Values for the database

`sql/01_schema.sql` (also run by `00_install.sql`) asks for them. To set them later, run it again; Enter keeps a value:

```sql
@sql/01_schema.sql
```

| Prompt | Value |
|---|---|
| OCI region | `<OCI_REGION>` |
| IoT domain short ID | from 6.3; the script builds the device host from it |
| Device password | from 6.4, typed hidden; it must not contain a single quote (`'`) |
| Publish | `Y` |

The password is stored encrypted: `SELECT name, value FROM dh_config` shows `********`. This keeps it out of query results and screen shares; it is masking, not real protection, because the schema owner can decrypt it. In production, keep it in OCI Vault.

### 6.7 Test

```sql
SET SERVEROUTPUT ON
EXEC dh_device_sim.publish_test('PS-04')
```

- **HTTP 2xx** (usually `202 Accepted`): Internet of Things → Domains → `dh-demo-iot-domain` → *Digital twin instances* → `PS-04 …` → tab *Data* shows the test values (vibration 2.1, bearing temperature 52.4). If the tab stays `{}`, the post was accepted but rejected later; see below.
- **HTTP 401**: device password or external key wrong, or the policy from 6.4 is missing.
- **HTTP 404**: device host or endpoint wrong.
- **HTTP -1** with an error text: the database could not reach the host.

To read rejected posts (table `REJECTED_DATA` of the IoT domain):

1. Cloud Shell, once (password typed hidden, at least 12 characters):
   ```bash
   read -s -p "APEX password for the IoT data: " APW; echo
   oci iot domain configure-apex-data-access --iot-domain-id "$IOT_DOMAIN_ID" --db-workspace-admin-initial-password "$APW"
   unset APW
   ```
2. Log in to `https://<domain-group-short-id>.data.iot.<OCI_REGION>.oci.oraclecloud.com/ords/r/apex/workspace`, workspace and user `<domain-short-id>__WKSP` (two underscores).
3. SQL Workshop → SQL Commands, schema `<domain-short-id>__IOT`: `SELECT * FROM rejected_data FETCH FIRST 10 ROWS ONLY;`

Then enable the job and check after a minute:

```sql
EXEC DBMS_SCHEDULER.ENABLE('DH_TICK_JOB')
SELECT dh_device_sim.status FROM dual;          -- "publish: 50 ok, 0 failed"
```

The *Data* tab of the twins now changes every 30 seconds (reload the page).

---

## 7. Optional: APEX application

An operator app with five pages: home tiles, network graph and map, incident analysis with bypass and work order buttons, asset telemetry with limits, and a chat with an APEX AI Agent that uses the same `AGENT_*` tools.

- [`apex/README.md`](apex/README.md): what each page shows.
- [`apex/BUILD.md`](apex/BUILD.md): prerequisites (APEX 26.1, Graph Visualization plug-in, Web Credential and Generative AI Service) and every component, to import the APEXlang export from `apex/` or to build the app by hand.

The export contains no credentials: create the Web Credential and the Generative AI Service in your workspace first, as described in `BUILD.md`.

---

## 8. Optional: Private Agent Factory

*Oracle AI Database Private Agent Factory 26.10 · Agent Builder*

The agent never writes SQL against the network. It calls **approved PL/SQL functions** (`AGENT_*` in `<DEMO_USER>`, from `sql/07_agent_api.sql`). Each function runs SQL/PGQ pattern matching and, where available, `DBMS_OGA` graph algorithms, and returns JSON. The model only decides *which* tool to call and *how to explain* the result.

### 8.1 Prerequisites

- Agent Factory 26.10, for example provisioned from the OCI Marketplace (free listing, only the VM is billed), reachable at `https://<AGENT_FACTORY_HOST>:8080`.
- **Model** registered in *Model Management*: `<CHAT_MODEL>`, an OCI Generative AI chat model with tool calling.
- **Database connection** to the Autonomous AI Database as `<DEMO_USER>` (wallet `<WALLET_ZIP>`, service `<DB_SERVICE>`), named `ADB_DH` below.

### 8.2 Flow 1 – "Heat Network Ops Agent" (chat)

```text
Chat Input ──(Message → Prompt)──► Agent ──(Message → Message)──► Chat Output
                                     ▲ Tools
                                     └── Oracle PL/SQL Executor  (ADB_DH, allowed routines below)
```

Connections on the Agent Builder canvas (drag from an output point to an input point):

1. **Chat Input** output → **Agent** input *Prompt*.
2. **Oracle PL/SQL Executor** output *Tools* → **Agent** input *Tools*.
3. **Agent** output *Message* → **Chat Output** input *Message*.

| Node | Setting |
|---|---|
| Agent | Model `<CHAT_MODEL>` · Temperature **0.1**, if offered · **Custom instructions**: the system prompt below · **Prompt**: leave empty (filled by Chat Input) · **Agent description**: `Operations assistant for the district heating network: situation, root causes, impact, predicted failures and work orders, using the AGENT_* database functions.` |
| Oracle PL/SQL Executor | Database `ADB_DH` · Allowed routines: `AGENT_NETWORK_STATUS`, `AGENT_ACTIVE_ANOMALIES`, `AGENT_FIND_ROOT_CAUSE`, `AGENT_IMPACT_ANALYSIS`, `AGENT_WHAT_IF`, `AGENT_PREDICT_FAILURES`, `AGENT_CRITICAL_ASSETS`, `AGENT_ASSET_DETAILS`, `AGENT_MAINTENANCE_HISTORY`, `AGENT_CREATE_WORK_ORDER` · Auto-commit off (the work order function commits itself) |

The nodes *Current Date* and *Calculator* are not needed: the `AGENT_*` functions return their own time stamps and computed values.

System prompt (*Custom instructions* of the Agent node):

```text
You are the operations assistant for a district heating network. Operators ask
you about cold buildings, alarms, pump stations and what to do next.

Rules
- Use the tools. Never guess numbers, asset ids or causes.
- All tools are database functions behind the Oracle PL/SQL Executor. Call its
  execution tool with the exact function name (for example AGENT_NETWORK_STATUS)
  and the arguments. If you are unsure about a function's parameters, use the
  discovery tool first. Report results only when the tool returns success.
- For questions about the current situation call AGENT_NETWORK_STATUS, then
  AGENT_ACTIVE_ANOMALIES with p_min_severity = 'WARNING' to name the assets
  behind the alarms and warnings (asset id, metric, severity).
- For "why" questions call AGENT_FIND_ROOT_CAUSE. It groups cold buildings into
  incidents, each with a root-cause asset, evidence and a classification
  (EQUIPMENT_PROBLEM or SUSPECTED_SENSOR_FAULT).
- For every equipment incident call AGENT_IMPACT_ANALYSIS with the root-cause
  asset. Report life-critical buildings (hospital, nursing home, school) first
  and present the mitigation options with their effect.
- For "what will fail next" call AGENT_PREDICT_FAILURES.
- Create work orders only when the operator asks for it or confirms it.
  Priorities: P1 = people without heat now, P2 = failure expected within 48 h,
  P3 = within 10 days, P4 = check.
- Answer in short sections with these headings: Situation · Root cause · Impact ·
  Recommended actions. Leave out Root cause or Impact if no tool result supports
  it. Always end with Recommended actions: the next checks or questions that
  follow from the tool results.
- Always write the asset id with the name, for example "PS-04 (Pump station
  Favoriten)", so operators can find it. Put all anomalies of one asset in one line.
- Never say that actions are underway, planned or done unless a tool result says
  so (for example a work order returned by AGENT_CREATE_WORK_ORDER).
- Times in tool results are UTC; say "UTC" when you quote them.
- Keep answers under 200 words unless asked for details.
```

**Prompts to try**, in state `incident` (`@sql/demo_state.sql incident`). District names are for Vienna; for Bucharest use Rahova, Berceni and Militari instead of Favoriten, Simmering and Ottakring.

| # | Prompt | Tools called | Key facts in the answer |
|---|---|---|---|
| 1 | `Good morning. What is the situation in the network?` | network_status, active_anomalies('WARNING') | About 45 buildings without heat in three districts, hospital among them; PS-04 and SS-09.3 named |
| 2 | `Why are the buildings in Favoriten and Simmering cold?` | find_root_cause, impact_analysis(PS-04) | PS-04 explains 40 buildings; evidence: vibration trend over 3 days, bearing temperature, flow and pressure collapse |
| 3 | `What can we do right now for the hospital?` | impact_analysis or what_if('PS-04','BYP-1') | Opening BYP-1 restores 20 buildings incl. hospital and nursing home; 20 stay cold until PS-04 is repaired |
| 4 | `And the cold buildings in Ottakring?` | find_root_cause('Ottakring') | SS-09.3 reports exactly 41 °C for over 30 minutes, no upstream problem: suspected sensor fault, P4 check |
| 5 | `Which pump station will fail next if we do nothing?` | predict_failures | PS-08, vibration rising about 0.4 mm/s per day, alarm limit in about 6 days: P3 maintenance |
| 6 | `Create a P1 work order for PS-04 and a P3 work order for PS-08.` | create_work_order ×2 | Two work orders, visible in the APEX app |

`@sql/demo_state.sql incident` removes the work orders again.

**Which tools did the agent call?** The Playground shows only the chat. Without a tracing server (Application settings → Observability), check the database. Ask a prompt, then run as `<ADMIN_USER>`:

```sql
SET LINESIZE 250
COLUMN sql_text FORMAT a80
COLUMN module   FORMAT a30
COLUMN parsing_schema_name FORMAT a15

SELECT parsing_schema_name, module, executions,
       TO_CHAR(last_active_time,'YYYY-MM-DD HH24:MI:SS') AS last_active,
       SUBSTR(sql_text,1,80) AS sql_text
FROM   v$sql
WHERE  UPPER(sql_text) LIKE '%AGENT\_%' ESCAPE '\'
AND    UPPER(sql_text) NOT LIKE '%V$SQL%'
AND    parsing_schema_name = '<DEMO_USER>'
ORDER  BY last_active_time DESC
FETCH FIRST 20 ROWS ONLY;
```

Calls from the PL/SQL Executor have the module `python3.12` and look like `begin :return_value := <DEMO_USER>.AGENT_NETWORK_STATUS(); end;`; `last_active` is in UTC. To compare an answer with the tool result:

```sql
SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET PAGESIZE 0
SET LINESIZE 200
SELECT JSON_SERIALIZE(agent_network_status RETURNING CLOB PRETTY) FROM dual;
SELECT JSON_SERIALIZE(agent_active_anomalies('WARNING') RETURNING CLOB PRETTY) FROM dual;
```

On Windows, run `chcp 65001` before starting SQLcl, otherwise `°C` shows as `┬░C`.

### 8.3 Flow 2 – "Morning Briefing" (fixed workflow)

A fixed chain instead of a chat: a SQL query counts the open alarms and warnings, a condition decides, and only if there is something to report the agent writes a briefing for the shift lead. The agent may only read.

```text
SQL Query ──(JSON)──► Parser ──(Message → Text Input)──► Condition
                                                 │ True               │ False
                                                 ▼                    ▼
         Oracle PL/SQL Executor ──Tools──► Agent (Prompt)        Chat Output "no briefing"
         (read-only routines)                │ Message
                                             ▼
                                        Chat Output (and optional Email Output)
```

1. **Agent Builder → new flow**, name `Morning Briefing`.
2. **SQL Query**: data source `ADB_DH`, query:
   ```sql
   SELECT COUNT(*) AS alarms
   FROM   dh_anomalies
   WHERE  status <> 'CLOSED'
   AND    severity IN ('ALARM', 'WARNING')
   ```
3. **Parser**: SQL Query *JSON* → Parser *JSON or DataFrame*. *Root path* **`records`** · *Mode* `Parser` · *Template* `{ALARMS}`. The SQL Query node wraps its rows as `{"records": [{"ALARMS": 47}]}`; without the root path the template finds nothing and the condition is always false. The Parser's output is just the number.
4. **Condition**: Parser *Message* → *Text Input* · *Operator* `greater than` · *Match Text* `0` · *True Message*: `Good morning. There are open alarms and warnings. Write today's morning briefing for the shift lead.` · *False Message*: `No open alarms or warnings. No briefing sent.` The Condition passes on its True or False Message, not its input.
5. **Chat Output** on Condition *False*.
6. **Oracle PL/SQL Executor**, a new one for this flow: database `ADB_DH`, allowed routines **read-only**: `AGENT_NETWORK_STATUS`, `AGENT_ACTIVE_ANOMALIES`, `AGENT_FIND_ROOT_CAUSE`, `AGENT_IMPACT_ANALYSIS`, `AGENT_PREDICT_FAILURES`; auto-commit off. `AGENT_CREATE_WORK_ORDER` is deliberately missing: the briefing recommends, the operator decides.
7. **Agent**: model `<CHAT_MODEL>`, temperature 0.1 if offered, *Custom instructions* below, *Agent description* `Writes the morning briefing for the shift lead of the district heating network from the AGENT_* database functions.` Connections: Condition *True* → Agent *Prompt*; PL/SQL Executor *Tools* → Agent *Tools*.
8. **Chat Output** on Agent *Message*.
9. Optional: **Email Output** on Agent *Message* (needs SMTP in the Agent Factory settings; subject for example `Morning briefing – district heating`). For email, the last instruction can ask for simple HTML instead of plain text.
10. **Save**.

Briefing instructions (*Custom instructions* of the Agent node):

```text
You write the morning briefing for the shift lead of a district heating network.

Rules
- Use the tools. Never guess numbers, asset ids or causes.
- All tools are database functions behind the Oracle PL/SQL Executor. Call its
  execution tool with the exact function name and the arguments. If you are
  unsure about a function's parameters, use the discovery tool first.
- Call AGENT_NETWORK_STATUS, AGENT_ACTIVE_ANOMALIES with p_min_severity =
  'WARNING', AGENT_FIND_ROOT_CAUSE and AGENT_PREDICT_FAILURES. For every incident
  classified EQUIPMENT_PROBLEM also call AGENT_IMPACT_ANALYSIS with its
  root-cause asset.
- Sections: Situation · Root causes · Impact · Expected failures · Recommended
  actions. Report life-critical buildings (hospital, nursing home, school) first.
- Always write the asset id with the name, for example "PS-04 (Pump station
  Favoriten)".
- You cannot create work orders. Recommend them with a priority: P1 = people
  without heat now, P2 = failure expected within 48 h, P3 = within 10 days,
  P4 = check.
- Never say that actions are underway, planned or done unless a tool result says
  so. Times in tool results are UTC; say "UTC" when you quote them.
- At most 200 words. Plain text, no Markdown.
```

**Test.** The flow has no Chat Input: in the Playground, whatever you type only starts the run (a space is enough); it is not read. For questions, use Flow 1.

1. In state `base` (`@sql/demo_state.sql base`): the briefing names PS-04 with rising vibration before it fails, PS-08 with its trend, and SS-09.3 with the stuck sensor. The agent needs 30–60 seconds for its tool calls.
2. The `v$sql` check from 8.2 shows the `AGENT_*` calls, and no `AGENT_CREATE_WORK_ORDER`.
3. False branch: set *Match Text* to `1000` for one run; only the False Message appears and no `AGENT_*` function is called. Set it back to `0`.

**Publish** (optional): saving is enough for the Playground. A published flow can also be run through the integration endpoint `POST https://<AGENT_FACTORY_HOST>:8080/agentFactory/v1/integrations/agents/<agent_id>/run` with an API key (created by an administrator in the chat window under *Integration options → API Key*, bound to this agent, shown only once), for example from a database job every morning.

### 8.4 Data Analysis Agent (ad-hoc questions with charts)

A prebuilt agent of the Agent Factory: it turns a question into SQL on **one** table or view, runs it, and answers with an explanation, a table, a chart and the SQL it used. It has no tools: it is for exploring, not for decisions. The view **`DH_ANALYSIS_V`** (`sql/09_apex_support.sql`) combines asset status and open anomalies in one row per asset, with comments on every column.

1. Left sidebar → **Data analysis agents** → **Create Agent**.
2. Database `ADB_DH`, view **`DH_ANALYSIS_V`**.
3. Agent name `Heat Network Analyst`. Description (at most 200 characters):
   ```text
   District heating network: one row per asset with health (OK, WATCH, WARNING, ALARM), buildings without heat, life-critical buildings and open anomalies.
   ```
   Help descriptions (optional):
   ```text
   WITHOUT_HEAT = 'Y': building without heat. APARTMENTS_WITHOUT_HEAT: apartments
   without heat (sum it). APARTMENTS: apartments per building.
   LIFE_CRITICAL = 'Y': hospital, nursing home or school. HEALTH_STATUS: OK, WATCH,
   WARNING, ALARM (worst). HOURS_TO_ALARM: time until a rising trend reaches its
   alarm limit. Use ASSET_ID to name assets.
   Examples: How many buildings are without heat per district? Which assets reach
   an alarm limit within 48 hours? Assets per type and health as a stacked bar chart.
   ```
4. **Publish Agent**, open its chat and wait for the initial exploration of the view.

Questions that work well:

| # | Question | Check |
|---|---|---|
| 1 | How many buildings are without heat per district? Show a bar chart. | `base`: 5; `incident`: 45 |
| 2 | How many apartments are without heat in total and per district? | equals `apartments_without_heat` of `AGENT_NETWORK_STATUS` |
| 3 | Show the number of assets per asset type and health status as a stacked bar chart. | equals `assets_by_health` of `AGENT_NETWORK_STATUS` |
| 4 | Which assets have open alarms or warnings? List id, name, district and reason. | SS-09.3, PS-04 (after the trip also the cold buildings) |
| 5 | Which assets reach an alarm limit within the next 48 hours? | PS-04 before the trip; PS-08 only with a longer horizon (about 6 days) |
| 6 | List the life-critical buildings with their district and whether they are without heat. | 7 buildings; after the trip the hospital and nursing home behind PS-04 are without heat |
| 7 | Which district has the most open anomalies? Show a pie chart. | sum of `open_anomalies` per district |

The explanation is written from the result table only and does not see the SQL's filter; check the **SQL** tab before trusting a number. Start a new chat when the topic changes, and create the agent again after a change to the view. The Data Analysis Agent answers "how many, where, which"; "why, who is affected, what if" need the ops agent and its graph tools.

### 8.5 More options

- **The same agent in APEX**: page 5 of the APEX app is an APEX AI Agent with the same `AGENT_*` functions as tools ([`apex/BUILD.md`](apex/BUILD.md), section 9). Work orders need approval in the chat.
- **MCP Server node** with the OCI IoT MCP server (`oci-iot-mcp-server`, sample in [github.com/oracle/mcp](https://github.com/oracle/mcp)) for live twin context.
- **Select AI Agent**: the same `AGENT_*` functions can be registered as tools with `DBMS_CLOUD_AI_AGENT.CREATE_TOOL` and exposed through the Autonomous AI Database MCP Server.

---

## 9. Optional: coding agent with Oracle Skills and the SQLcl MCP Server

The ops agent uses tools that a developer wrote. Here a **coding agent** writes such a tool: it learns SQL/PGQ from **Oracle Skills** and runs what it writes against the database through the **SQLcl MCP Server**.

### 9.1 Setup

1. Oracle Skills for your coding agent (Claude Code shown; Codex, Cursor, GitHub Copilot and Gemini CLI work the same way):
   ```bash
   # Claude Code
   /plugin marketplace add oracle/skills
   /plugin install db@oracle-skills
   # or any agent that supports Agent Skills
   npx skills add oracle/skills/db
   ```
   Relevant skill files: `db/appdev/sql-property-graph.md` (CREATE PROPERTY GRAPH, GRAPH_TABLE, quantifiers, ONE ROW PER STEP, VERTEX_ID) and `db/sqlcl/…` (SQLcl and its MCP server).
2. A saved SQLcl connection for the demo user (password stored):
   ```bash
   sql /nolog
   SQL> conn -save dh_demo -savepwd -cloudconfig <WALLET_ZIP> <DEMO_USER>@<DB_SERVICE>
   ```
3. Register the SQLcl MCP Server with the coding agent:
   ```bash
   claude mcp add sqlcl -- sql -mcp
   ```
4. Connect as `<DEMO_USER>`, never as an administrator, and keep the approval prompts of the coding agent on. The MCP server runs SQL with the privileges of that user, so the agent can't do more than the user.

### 9.2 Prompts

1. Understand the graph:
   ```text
   Connect to dh_demo. Describe the property graph DH_NETWORK: labels, properties,
   edge directions. Keep it short.
   ```
2. Write a new graph query:
   ```text
   Write a SQL/PGQ query on DH_NETWORK that lists, for every pump station, the
   nursing homes and hospitals it supplies (open pipes only, up to 4 hops) and the
   number of hops. Run it and show the result.
   ```
3. Turn it into an agent tool:
   ```text
   Wrap that query in a function AGENT_CRITICAL_CUSTOMERS(p_asset_id VARCHAR2)
   RETURN CLOB that returns JSON, in the style of the existing AGENT_* functions.
   Create it in my schema and test it with PS-04.
   ```

Then add `AGENT_CRITICAL_CUSTOMERS` to the allowed routines of the Oracle PL/SQL Executor in Agent Factory: a new capability for the ops agent, written by an agent and reviewed by a human. Review the generated function like any other code before you keep it.

To repeat: `@sql/demo_state.sql` (any state) drops the function, or `DROP FUNCTION IF EXISTS agent_critical_customers;`. If you added it to the allowed routines, remove it there too.

---

## 10. Optional: reading the data back through the IoT Data API

Not needed for the demo. Use it if the database should read the historized data from the IoT Platform instead of writing it directly (`INGEST_MODE = IOT`). It needs [section 6](#6-optional-oci-iot-platform) and an identity domain in which you may create an OAuth application, a user and a group (not the *Default* domain). Docs: [Connecting IoT data to ORDS](https://docs.oracle.com/en-us/iaas/Content/internet-of-things/connect-iot-ords.htm).

### 10.1 Identity domain and OAuth application

1. Identity & Security → **Domains**: an identity domain that is **not** the *Default* domain, in the same region (or create one, type *Free*).
2. In the domain: **Settings** → *Domain settings* → *Access signing certificate* → enable **Configure client access**.
3. **Integrated applications** → **Add application** → **Confidential Application**, name `dh-demo-iot-reader-app` → **Activate**.
4. Tab **OAuth configuration** → **Edit OAuth configuration**:
   - **Resource server**: primary audience `/<domain-group-short-id>` (lower case), scope `/iot/<domain-short-id>`.
   - **Client**: grant types **Resource owner**, **Client credentials**, **JWT assertion**, **Refresh token**; allowed operation **Introspect**; token issuance policy **All**.
5. **→ note** the **Client ID** and the **Client secret**.
6. **User management**: a local user of this identity domain with its own password and no MFA requirement (for example `dh-demo-iot-reader`), and a group that contains it. Use a technical user: its password is stored in the demo schema.
7. In the application: assign the user (tab **Users**) and the group (tab **Groups**).
8. Domain **Details** → *Domain URL*: **→ note** the host, `idcs-<unique-id>.identity.oraclecloud.com`.

### 10.2 Allow ORDS access for the IoT domain

Internet of Things → Domains → `dh-demo-iot-domain` → **Actions** → **Change data access** → **Oracle REST Data Services (ORDS) access**, with the identity domain host from 10.1. Wait for the work request to succeed.

### 10.3 Values for the database

Run in SQLcl as `<DEMO_USER>`, without `SPOOL`, so that no secret ends up in a log file:

```sql
SET VERIFY OFF
ACCEPT rg   CHAR PROMPT 'OCI region: '
ACCEPT dg   CHAR PROMPT 'Domain group short ID: '
ACCEPT ds   CHAR PROMPT 'Domain short ID: '
ACCEPT idcs CHAR PROMPT 'Identity domain host (idcs-...identity.oraclecloud.com): '
ACCEPT cid  CHAR PROMPT 'Client ID: '
ACCEPT csec CHAR PROMPT 'Client secret: ' HIDE
ACCEPT usr  CHAR PROMPT 'User: '
ACCEPT pwd  CHAR PROMPT 'Password: ' HIDE
MERGE INTO dh_config t
USING (VALUES
  ('IOT_DATA_API_BASE', LOWER('https://&dg..data.iot.&rg..oci.oraclecloud.com/ords/&ds./20250531')),
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

The schema owner can still decrypt the secrets; in production, keep them in OCI Vault.

### 10.4 Test and switch

```sql
SELECT name, value FROM dh_config WHERE name LIKE 'IOT%' ORDER BY name;   -- secrets show ********

SET SERVEROUTPUT ON
EXEC dh_iot_sync.pull(p_verbose => TRUE)
```

- The pull ends with `page n: … items` and `… rows merged`: token and Data API work.
- `Token request failed` points to 10.1 (client, user, scope); `historizedData failed: HTTP 401` to 10.2.
- The IoT Data API returns readings by twin OCID. Run `data/twins_<CITY>.sql` (written by `setup_iot.sh`, 6.5) as `<DEMO_USER>` once, so the pull can map them to the assets.
- Switch: `UPDATE dh_config SET value = 'IOT' WHERE name = 'INGEST_MODE'; COMMIT;` The job then publishes and pulls. Back: `'DIRECT'`.

---

## 11. Remove everything

```sql
-- as <DEMO_USER>
@sql/99_teardown.sql
```

It drops the job, the property graphs and all demo tables, views, functions, procedures and packages of the demo schema. To remove the schema itself, drop `<DEMO_USER>` as `<ADMIN_USER>`. Delete the IoT domain, domain group, Vault secret, APEX app and Agent Factory flows in their consoles.

License: UPL 1.0 (suggested).
