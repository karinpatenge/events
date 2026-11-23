# DOAG Conference 2026 in Nuremberg/DE

Material for the five sessions at the DOAG 2026 Konferenz + Ausstellung, 17–19 November 2026 in Nuremberg. Each session has its own folder. All demos use Oracle Autonomous AI Database 26ai and synthetic or open data.

| Date | Session | Folder |
| --- | --- | --- |
| 17 November | From IoT Data to Intelligent Action with Agentic AI and Graph Analytics | [From IoT to Intelligent Action](./From%20IoT%20to%20Intelligent%20Action) |
| 18 November | Spatial AI in Python: Unlocking Machine Learning for Geospatial Intelligence (workshop) | [Spatial AI Workshop](./Spatial%20AI%20Workshop) || 19 November | Building Blocks for Smart Data Applications | [Building Blocks for Smart Apps](./Building%20Blocks%20for%20Smart%20Apps) |
| 19 November | Hänsel und Gretel im Geodatenwald | [Geodatenwald](./Geodatenwald) |
| 19 November | Temporal Data Lineage and Impact Analysis in Oracle Database | [Temporal Data Lineage and Impact Analysis](./Temporal%20Data%20Lineage%20and%20Impact%20Analysis) |

## From IoT Data to Intelligent Action with Agentic AI and Graph Analytics

**What the session is about.** A cold Monday morning in Nuremberg: 45 buildings in a district heating network lose their heat, among them a hospital, a nursing home and a school. Are these 45 problems, or fewer? The session follows the data from the sensors to an action that a person approves:

- Pump stations and substations are digital twins on the **OCI IoT Platform** and send readings every 30 seconds into the database.
- **SQL property graphs** and graph algorithms reduce the 45 symptoms to two causes and simulate what a bypass would change.
- An **Oracle APEX** app shows the network as a graph and on a map.
- An agent in the **Oracle AI Database Private Agent Factory** explains the situation and proposes work orders through approved PL/SQL tools. A coding agent with **Oracle Skills** and the **SQLcl MCP Server** writes a new tool.

**What the folder contains.**

| Path | Content |
| --- | --- |
| `presentation/` | The slides as PDF |
| `media/` | German teaser video, two recordings of the Agent Factory agents (*Heat Network Ops* and *Morning Briefing*), DOAG 2026 logo and icons |
| `documents/setup.md` | Setup of the demo environment and checklist before the session |
| `data/network.json` | The synthetic heating network: plants, pump stations, substations and buildings |
| `scripts/` | All demo code. Start with [`scripts/README.md`](./From%20IoT%20to%20Intelligent%20Action/scripts/README.md) |
| `scripts/sql/` | Install, simulation, property graphs, analytics, agent tools, work orders, demo states, tests and teardown |
| `scripts/apex/` | The APEX application as APEXlang export, with a build guide |
| `scripts/iot/` | Digital twin models and adapters, and shell scripts to set up and remove the IoT resources |

## Building Blocks for Smart Data Applications

*Just a sprain? Spatial, Graph, Text, Vector and Hybrid Search* · with Ulrike Schwinn

**What the session is about.** Jonas, a fictional developer from Nuremberg, twists his knee on a steep hiking trail the day before his first DOAG talk. Seven questions decide how to help him, and each question uses a different building block of the database:

- JSON, FHIR and JSON-relational duality views for his health record
- Streaming data from his watch with `MATCH_RECOGNIZE` and Spatial
- Oracle Text, AI Vector Search and hybrid search across symptom reports
- An RDF knowledge graph of the knee with the FMA anatomy ontology
- A SQL property graph of the care network and a spatial route to the pick-up point

The finale combines all building blocks in one query. The data is synthetic; the geography comes from OpenStreetMap.

**What the folder contains.**

| Path | Content |
| --- | --- |
| `presentation/` | The slides in German and English as PDF |
| `scripts/sql/` | Numbered scripts: `00`–`10` create the user, tables, embeddings, text and spatial indexes, the RDF network and the property graph; `11a`–`11i` are SQL notebooks for each demo step; `11_demo_live_de/en` are the notebooks used live; `12` holds SPARQL sample queries; `98` and `99` clean up. Details in [`scripts/sql/README.md`](./Building%20Blocks%20for%20Smart%20Apps/scripts/sql/README.md) (German) |
| `logs/sql/` | Target folder for the logs of the scripts (empty) |

## Hänsel und Gretel im Geodatenwald

*Oracle Spatial basics* · session in German, with Knut Göttling (Enignum AI GmbH)

**What the session is about.** The Brothers Grimm fairy tale as an introduction to Oracle Spatial. Each chapter of the story asks a spatial question and answers it with SQL, live in Oracle AI Database 26ai: the data type `SDO_GEOMETRY`, loading and exporting with WKT and GeoJSON, coordinate reference systems and EPSG codes, map projections and their distortions, spatial metadata and indexes, and operators such as `SDO_WITHIN_DISTANCE`, `SDO_NN` and `SDO_FILTER`.

**What the folder contains.**

| Path | Content |
| --- | --- |
| `presentation/` | The slides in German as HTML and PDF |

More material for this session is in Knut Göttling's repository [knutman/doag-2026-spatial](https://github.com/knutman/doag-2026-spatial).

## Temporal Data Lineage and Impact Analysis in Oracle Database

*Evolution to Oracle Graph Architecture* · with Tomislav Zarkovic (Koios)

**What the session is about.** Part 1 introduces Oracle AI Database as a graph database: how to define and query SQL property graphs on existing tables. Part 2 applies graphs to data lineage: tracing how data flows between systems over time and analysing the impact of a change with interactive visual analysis.

**What the folder contains.**

| Path | Content |
| --- | --- |
| `20261119_DOAG_GettingStartedWithOracleGraph_KPatenge.pdf` | The slides as PDF |

## Spatial AI in Python: Unlocking Machine Learning for Geospatial Intelligence

*Workshop: Safe Cycling in Nuremberg*

**What the session is about.** A hands-on workshop for participants without data science or GIS background. Lena, a fictional mobility planner, needs to know where Nuremberg should invest first in safer cycling. With open data (accident atlas 2020–2025, Zensus 2022, OpenStreetMap) and Python in OML Notebooks next to the data, participants:

1. find accident clusters with DBSCAN,
2. test for hotspots with Moran's I and LISA,
3. check the distance to cycling infrastructure,
4. find schools and kindergartens in hotspots,
5. find places with more bicycle accidents than expected, using OLS and GWR regression.

The results are written back as tables and can be shown on a map in Spatial Studio (optional).

**What the folder contains.**

| Path | Content |
| --- | --- |
| `documents/` | Participants guide in German and English: task, timetable, environment options (LiveLabs or your own Autonomous AI Database) and an explanation of each method |
| `scripts/oml4py/` | The workshop notebooks for OML Notebooks in German and English (`.dsnb`) |
| `scripts/sql/` | Scripts to create and drop the workshop user and to load the accident data |
| `logs/sql/` | Target folder for the logs of the scripts (empty) |

The PAR URL for the data files in Object Storage is handed out by the instructors during the workshop.
