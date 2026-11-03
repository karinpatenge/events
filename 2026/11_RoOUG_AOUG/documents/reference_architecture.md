# Reference architecture

*Graphic: `media/16_reference_architecture.svg` (2560 × 1100, transparent) · generator `internal/graphics/gen_reference_architecture.py` · slide 15*

Related: [structure.md](structure.md) · [setup.md](setup.md)

## Components

| Area | Component | Role in the demo | Oracle technology |
|---|---|---|---|
| OCI IoT Platform | Device endpoint | HTTPS POST, basic auth (external key + Vault secret) | IoT domain |
| | Twin models, adapters | `PumpStation`, `Substation` (DTDL v3, historized), payload mapping | `scripts/iot/*.json` |
| | Digital twins, relationships | 10 pump stations + 40 substations, `feeds` | `scripts/iot/setup_iot.sh` |
| | IoT database, Data API | raw, historized, snapshot, rejected; Data API (ORDS with OAuth) optional, not used in the demo | managed by the platform |
| | APEX workspace of the IoT domain | SQL on raw, historized and rejected data (checks during setup, optional in Act 1) | `configure-apex-data-access` |
| Autonomous AI Database 26ai | Device simulation job | `DH_TICK_JOB` every 30 s: 50 readings from the network state, `INSERT` into `DH_TELEMETRY` and HTTPS POST to the device endpoint; `trip`, `repair` and the valve state as demo actions | `DBMS_SCHEDULER`, PL/SQL (`06b_device_sim.sql`), `APEX_WEB_SERVICE` |
| | Tables | assets, pipes, metrics, telemetry, anomalies, work orders, maintenance | `01_schema.sql` |
| | SQL property graphs | `DH_NETWORK` (tables), `DH_LIVE_NETWORK` and `DH_DEPENDENCY` (views + context for what-if) | `CREATE PROPERTY GRAPH`, `GRAPH_TABLE` |
| | Graph algorithms | PageRank, Personalized PageRank, WCC, Bellman-Ford | `DBMS_OGA` |
| | Anomaly detection | threshold, z-score, trend (time to alarm), flatline, no data | SQL (`05_analytics.sql`); production option OML MSET-SPRT |
| | Agent tools | 10 `AGENT_*` functions returning JSON | PL/SQL (`07_agent_api.sql`) |
| | APEX app | network graph, map, incident page, buttons | APEX + Graph Visualization plug-in |
| Compute VM | Private Agent Factory | ops agent (chat), morning briefing (workflow) | Agent Factory 26.10 from the OCI Marketplace (free listing, VM billed) |
| OCI | Generative AI | LLM with tool calling | OCI Generative AI |
| Laptop | Coding agent + Oracle Skills + SQLcl MCP | writes and tests new agent tools | `oracle/skills`, SQLcl |

## Design decisions to mention

- **Graph on the operational tables.** No copy, no second store. The graph sees the latest health status and anomalies the moment the job commits.
- **Graphs on views for what-if.** The live graphs read a session context (`DH_CTX`), so "what if PS-04 is out and BYP-1 is open" changes nothing in the data.
- **Agents call functions, not SQL.** The PL/SQL Executor only runs approved routines, as user `OGBEMEA2026` with its own privileges. Writes (work orders) need a confirmed request.
- **Devices simulated where the data lives.** The job that plays the devices runs in the database, posts to the IoT Platform like real devices and writes the same readings into `DH_TELEMETRY`. Nothing runs on the presenter's laptop, and the data flow does not depend on the venue network. In production the database would read the historized data through the IoT Data API (`06_iot_sync.sql`, `INGEST_MODE = IOT`), which needs an OAuth application in an identity domain.
- **IoT Platform for device data, ADB for assets.** Twins are linked to assets by external key (= asset id) and twin OCID. The IoT Platform keeps its own twin graph (`DIGITAL_TWINS`), which can be queried in the IoT domain's APEX workspace (set up for the demo checks).
- **Fallbacks are part of the design.** `IOT_PUBLISH = N` keeps the demo running without the IoT Platform, SQL/PGQ variants for every algorithm, and recorded videos.

## Talk track (75 s)

> Left: the field. Fifty digital twins send JSON every thirty seconds; in this demo a job in the database plays the devices. The OCI IoT Platform authenticates them, maps the payload onto a model and keeps raw, historized and latest values in its own Oracle database. The same readings land in our Autonomous AI Database. Inside one database we have the asset register and telemetry, three property graphs on top of them, graph algorithms, anomaly detection in SQL, and the PL/SQL tools for agents. APEX is the operator UI. On the right the Private Agent Factory runs the agents with a model from OCI Generative AI. On top, operators use the app and the chat, and developers use a coding agent that knows Oracle through Oracle Skills and works through the SQLcl MCP Server.
