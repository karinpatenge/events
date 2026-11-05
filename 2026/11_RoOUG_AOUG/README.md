# From IoT Data to Intelligent Action with Agentic AI and Graph Analytics

*EMEA Community Tour 2026 · AOUG (Vienna) and RoOUG (Bucharest) · November 2026 · Karin Patenge*

Session material and complete demo code: how sensor data becomes a decision that a person can approve, with Oracle technology end to end.

## The story

A cold Monday morning, minus ten degrees. In a city's district heating network, 45 buildings lose their heat, one after another: among them a hospital, a nursing home and a school. 45 problems, or fewer?

The demo walks from the data to the action:

1. **IoT data.** Pump stations and substations are digital twins on the **OCI IoT Platform**. They report every 30 seconds, and the same readings land in **Oracle Autonomous AI Database 26ai**, where anomaly detection runs in plain SQL.
2. **Graph analytics.** **SQL property graphs** (SQL/PGQ) model the network on the existing tables, without a copy. A few lines of graph pattern turn 45 symptoms into two causes: one failing pump and one stuck sensor. Graph algorithms (PageRank, connected components) confirm the root cause and simulate what opening a bypass valve would change, before anyone touches the network.
3. **Graph apps.** An **Oracle APEX** application shows the network as an interactive graph and on a map, with live health colours, impact analysis and mitigation options.
4. **Agentic AI.** An agent built with the **Oracle AI Database Private Agent Factory** explains the situation and recommends actions. It can only call approved database functions, and a person approves what it proposes, such as a work order. A fixed *Morning Briefing* workflow writes a daily summary. A **coding agent** with **Oracle Skills** and the **SQLcl MCP Server** shows the developer side: it writes a new tool for the agent.

The answer: two problems, not 45. Open a bypass and the hospital and nursing home are warm again within minutes; a work order sends a crew to the pump.

## What is in this repository

| Path | Content |
|---|---|
| `presentation/` | The slides of the session as PDF |
| `media/01_teaser_en.mp4` | Teaser video, 50 seconds, English |
| `media/01_teaser_at.mp4`, `media/01_teaser_ro.mp4` | The same teaser in German (Vienna) and Romanian (Bucharest) |
| `media/octemea26*` | Logo and icons of the EMEA Community Tour 2026 |
| `scripts/` | All demo code, with step-by-step instructions in [`scripts/README.md`](scripts/README.md) |
| `scripts/sql/` | Install, simulation, analytics, property graphs, agent tools, demo states, tests, teardown |
| `scripts/iot/` | Digital twin models and adapters, and a script that creates the 50 twins with the OCI CLI |
| `scripts/apex/` | The APEX application: overview, build guide and APEXlang export |
| `data/` | The synthetic network of both cities, used to create the digital twins |
| `schema/` | Diagram of the demo tables |

## Try it yourself

Everything runs in Oracle Cloud Infrastructure. You need an Autonomous AI Database 26ai and SQLcl (or SQL Developer for VS Code); no Python and nothing running on your own machine. The core demo (simulation, analytics, graph queries) needs nothing else. The IoT Platform, the APEX app, the Agent Factory and the coding agent are optional building blocks that you can add one at a time.

Start with [`scripts/README.md`](scripts/README.md).

## Technologies

- Oracle Autonomous AI Database 26ai: SQL property graphs (SQL/PGQ), graph algorithms (`DBMS_OGA`), PL/SQL, scheduler jobs
- OCI IoT Platform: digital twin models, adapters and instances
- Oracle APEX 26.1: Graph Visualization plug-in, maps, AI Agents
- Oracle AI Database Private Agent Factory 26.10: agent flows with the Oracle PL/SQL Executor, Data Analysis Agent
- OCI Generative AI: chat models with tool calling
- Oracle Skills and the SQLcl MCP Server for coding agents

## Notes

All data is synthetic. The district names of Vienna and Bucharest are real; assets, topology, measurements and incidents are invented. The repository contains no credentials or tenancy-specific values: the instructions use placeholders for them.

License: UPL 1.0 (suggested).
