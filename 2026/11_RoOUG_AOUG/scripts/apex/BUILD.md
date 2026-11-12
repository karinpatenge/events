# Building the APEX application

*EMEA Community Tour 2026 – From IoT Data to Intelligent Action · Oracle APEX 26.1 · Universal Theme*

This guide describes every component of the application, so that it can be rebuilt by hand or checked after an import. An overview of the pages without technical details is in [README.md](README.md). All paths are relative to this folder (`scripts/apex`).

The application was exported in APEXlang format to the folder `emea-community-tour-2026-from-iot-data-to-intelligent-action/`.

> **Excluded from the repository.** The export folder `emea-community-tour-2026-from-iot-data-to-intelligent-action/workspace-components/` contains two components with tenancy-specific data: the Web Credential `workspace-components/credentials/credentials-for-oci-genai.apx` and the Generative AI Service in `workspace-components/generative-ai-services/`. Both are listed in `.gitignore` and were not uploaded to the GitHub repository. Create them in your own workspace as described in [section 2](#2-workspace-components).

## Placeholders

| Placeholder | Meaning |
|---|---|
| `<APEX_WORKSPACE>` | Your APEX workspace |
| `<PARSING_SCHEMA>` | Database schema that owns the demo objects and is the parsing schema of the app |
| `<APP_ID>` | Application ID in your workspace |
| `<WEB_CREDENTIAL_NAME>`, `<WEB_CREDENTIAL_STATIC_ID>` | Name and static ID of the Web Credential for OCI |
| `<OCI_USER_OCID>` | OCID of the OCI user that owns the API key |
| `<OCI_TENANCY_OCID>` | OCID of your tenancy |
| `<OCI_PRIVATE_KEY>` | Private key (PEM) of the API key of that user |
| `<OCI_API_KEY_FINGERPRINT>` | Fingerprint of that API key |
| `<OCI_COMPARTMENT_OCID>` | Compartment in which OCI Generative AI is used |
| `<OCI_REGION>` | OCI region with Generative AI, for example the region of your tenancy |
| `<GENAI_SERVICE_NAME>`, `<GENAI_SERVICE_STATIC_ID>` | Name and static ID of the Generative AI Service in APEX |
| `<GENAI_MODEL_ID>` | Chat model of OCI Generative AI that supports tool calling |
| `<LOGO_URL>` | URL of the logo image in the application header |

Never write real values for these into files of the repository.

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Workspace components](#2-workspace-components)
3. [Graph Visualization plug-in](#3-graph-visualization-plug-in)
4. [Application and shared components](#4-application-and-shared-components)
5. [Page 1 "Home"](#5-page-1-home)
6. [Page 2 "Network"](#6-page-2-network)
7. [Page 3 "Incident"](#7-page-3-incident)
8. [Page 4 "Asset"](#8-page-4-asset)
9. [AI Agent "Heat Network Ops Agent"](#9-ai-agent-heat-network-ops-agent)
10. [Page 5 "Assistant"](#10-page-5-assistant)
11. [Work orders: workflow and pages 6 to 9](#11-work-orders-workflow-and-pages-6-to-9)
12. [Login page](#12-login-page)
13. [Test](#13-test)

---

## 1. Prerequisites

- **Oracle APEX 26.1** on Oracle AI Database 26ai (for example an Autonomous AI Database). Check with `SELECT version_no FROM apex_release;`.
- **Demo schema** `<PARSING_SCHEMA>` with all objects of the demo, installed with `../sql/00_install.sql` (see `../README.md`). The app uses:

  | Object | Created by | Used on |
  |---|---|---|
  | Tables `DH_ASSETS`, `DH_PIPES`, `DH_TELEMETRY`, `DH_ANOMALIES`, `DH_WORK_ORDERS`, `DH_MAINTENANCE`, `DH_METRICS` | `../sql/01_schema.sql` | pages 1–4 |
  | Property graph `DH_NETWORK` | `../sql/04_property_graphs.sql` | pages 2 and 3 |
  | Functions `AGENT_*`, package `DH_GRAPH_API` | `../sql/07_agent_api.sql` | page 3, AI Agent |
  | Views `DH_ASSET_STATUS_V`, `DH_PIPE_LINES_V`, `DH_OPEN_ANOMALIES_V`, `DH_TELEMETRY_RECENT_V`, procedure `DH_SET_VALVE` | `../sql/09_apex_support.sql` | pages 2–4 |
  | View `DH_WORK_ORDERS_V`, function `DH_WORK_PLAN`, package `DH_WO_FLOW` (work order workflow), function `DH_BYPASS_FOR_ASSET` | `../sql/10_work_orders.sql` | pages 3, 6 and 8, workflow |

- **The workspace** `<APEX_WORKSPACE>` has `<PARSING_SCHEMA>` as a workspace schema.
- **For page 5 only:** an OCI user with an API key, and an IAM policy that lets this user use OCI Generative AI in `<OCI_COMPARTMENT_OCID>`, for example:
  ```text
  Allow group <GROUP_OF_THE_USER> to use generative-ai-family in compartment <COMPARTMENT_NAME>
  ```

Two ways to get the app:

- **Import** the APEXlang export from `emea-community-tour-2026-from-iot-data-to-intelligent-action/` into APEX 26.1. Create the workspace components of [section 2](#2-workspace-components) first: they are not in the repository, and the AI Agent refers to the Generative AI Service by its static ID. After the import, check sections 3 and 4 (plug-in helper scripts, parsing schema).
- **Build it by hand** with sections 2–11.

## 2. Workspace components

### 2.1 Web Credential for OCI

Workspace Utilities → *All Workspace Utilities* → **Web Credentials** → *Create*:

| Field | Value |
|---|---|
| Name | `<WEB_CREDENTIAL_NAME>` |
| Static ID | `<WEB_CREDENTIAL_STATIC_ID>` |
| Authentication Type | *Oracle Cloud Infrastructure (OCI)* |
| OCI User ID | `<OCI_USER_OCID>` |
| OCI Private Key | `<OCI_PRIVATE_KEY>` (the whole PEM text, including the BEGIN and END lines) |
| OCI Tenancy ID | `<OCI_TENANCY_OCID>` |
| OCI Public Key Fingerprint | `<OCI_API_KEY_FINGERPRINT>` |

The private key must belong to exactly this user and fingerprint. A wrong key gives errors that look like network or ACL problems (for example ORA-24247 or ORA-20951), not like an authentication error.

### 2.2 Generative AI Service

Workspace Utilities → *All Workspace Utilities* → **Generative AI** → *Create*:

| Field | Value |
|---|---|
| AI Provider | *OCI Generative AI Service* |
| Name | `<GENAI_SERVICE_NAME>` |
| Static ID | `<GENAI_SERVICE_STATIC_ID>` (the export uses `oci_genai`; the AI Agent of section 9 references this static ID) |
| Base URL | `https://inference.generativeai.<OCI_REGION>.oci.oraclecloud.com` |
| Credential | `<WEB_CREDENTIAL_NAME>` |
| Compartment ID | `<OCI_COMPARTMENT_OCID>` |
| Model ID | `<GENAI_MODEL_ID>` (serving type *On Demand*) |
| Used by App Builder | as you like (the export: on, and default for new apps) |

Choose a chat model that supports tool calling and accepts the request parameters APEX sends. Models of the gpt-oss family reject APEX 26.1 AI Agent calls with HTTP 400 ("Harmony does not support reasoning_effort='none'").

Test: *Test Connection*, then in SQL Workshop → SQL Commands:

```sql
SELECT APEX_AI.GENERATE(p_prompt            => 'Reply with the single word OK.',
                        p_service_static_id => '<GENAI_SERVICE_STATIC_ID>') AS answer
FROM   dual;
```

## 3. Graph Visualization plug-in

Pages 2 and 3 use the region plug-in **Graph Visualization** (internal name in the export: `graphVisualization`). It is part of the export (`emea-community-tour-2026-from-iot-data-to-intelligent-action/shared-components/plugins/region/graphVisualization/`) and is imported with the app. The database helper objects it needs are not part of an APEX export; install them once per schema:

1. Open the folder `plugins/region/graph-visualization` of the branch `26.1` of the GitHub repository `oracle/apex` (the branch that matches your APEX version).
2. SQL Workshop → SQL Scripts: upload and run, as `<PARSING_SCHEMA>`:
   - `required-for-26ai/gvt_sqlgraph_to_json.sql`
   - `required-for-26ai/required_helper_functions.sql`
3. Building by hand: App Builder → *Import* → `region_type_plugin_graphviz.sql` from the same folder, file type *Plug-in*.

Repeat steps 1–3 after an APEX upgrade with the branch of the new version. The plug-in does not support DATE or TIMESTAMP vertex or edge keys; the demo graphs use VARCHAR2 and NUMBER keys.

## 4. Application and shared components

### 4.1 Application

| Attribute | Value |
|---|---|
| Name | `EMEA Community Tour 2026 - From IoT Data to Intelligent Action` |
| Application ID | `<APP_ID>` |
| Parsing schema | `<PARSING_SCHEMA>` |
| Theme | Universal Theme (42), theme style **Vita** |
| Logo | Image, URL `<LOGO_URL>` |
| Home page | 1, login page *LOGIN* (9999), global page 0 (empty) |
| Authentication | *Oracle APEX Accounts* |
| Navigation menu | list *Navigation Menu*, template *Side Navigation Menu*, template options *Collapsed by default*, *Hidden* when collapsed, style A |
| Navigation bar | list *Navigation Bar*, template *Navigation Bar* |
| Footer | *Add "Built with APEX" to Footer* off |
| Format masks | Date, Timestamp, Timestamp with Time Zone: `DS` |
| Feedback | allowed |
| Globalization | *Automatic Time Zone* = **Yes** (the views convert UTC to the session time zone) |
| Substitution string | `APP_NAME` = the application name |

Every page has *Page Access Protection* = *Arguments Must Have Checksum*, *Form Auto Complete* off and *Cursor Focus* = *Do not focus cursor*.

### 4.2 Lists

**Navigation Menu** (Font APEX icons):

| Seq | Label | Icon | Target | Parent | Current for page |
|---|---|---|---|---|---|
| 10 | Home | `fa-home` | page 1 | – | – |
| 20 | Network | `fa-network-hub` | page 2 | Home | 2 |
| 30 | Incident | `fa-alert` | page 3 | Home | 3 |
| 40 | Asset | `fa-gear` | page 4 | Home | 4 |
| 50 | Assistant | `fa-chatbot` | page 5 | Home | 5 |
| 60 | Work orders | `fa-wrench` | page 9 | Home | 9 |
| 70 | Tasks | `fa-tasks` | page 7 | Home | 7 |

**Navigation Bar**: `&APP_USER.` (icon `fa-user`, user-defined attribute 2 = `has-username`) with the children `---` (URL `separator`) and *Sign Out* (icon `fa-sign-out`, URL `&LOGOUT_URL.`), both with the condition *User is Authenticated*.

`fa-network-hub` and `fa-chatbot` are newer Font APEX icons: after an upgrade from an older APEX version, refresh the theme (Shared Components → Themes → *Refresh Theme*), or they show as empty squares.

### 4.3 Breadcrumb "Breadcrumb"

Entries *Home* (page 1), *Network* (page 2, parent *Home*), *Incident* (page 3), *Asset* (page 4), *Assistant* (page 5), *Work orders* (page 9), *Work order* (page 6, parent *Work orders*), *Tasks* (page 7), each linking to its page. Pages 2–5 show it in a region *Breadcrumb* (slot *Breadcrumb Bar*, template *Title Bar*, option *Use Current Breadcrumb Entry as Title*).

### 4.4 Other shared components

- **Static application files**: `icons/app-icon-32.png`, `-144-rounded.png`, `-192.png`, `-256-rounded.png`, `-512.png` (application icons; page 1 shows `#APP_FILES#icons/app-icon-512.png`).
- **Authorization scheme** *Administration Rights* (PL/SQL function body `return true;`) and **page group** *Administration*: created by the wizard, not used by the pages.
- **Build option** *Commented Out*: created by the wizard.
- **Component settings**: Switch *On Value* `Y`; Checkbox *Unchecked Value* `N`; Date Picker with month picker, year picker and *Today* button. The other settings are defaults.

---

## 5. Page 1 "Home"

Page alias `HOME`, title = application name, template *Standard*.

### 5.1 Region "EMEA Community Tour 2026 - From IoT Data to Intelligent Action"

Static Content, slot *Breadcrumb Bar*, template **Hero**, Image → File URL `#APP_FILES#icons/app-icon-512.png`.

### 5.2 Region "Pages" (tiles)

Type **Cards**, slot *Body*, template *Cards Container* with *Hide Header*, Static ID **`tiles`** (used by the CSS), Grid Columns **5**. Source SQL Query:

```sql
SELECT page_no, title, subtitle, body, icon,
       apex_page.get_url(p_page => page_no) AS link
FROM  (SELECT 2 AS page_no, 'Network' AS title, 'Network graph and map, coloured by health' AS body,
              'fa fa-network-hub dh-tile-network' AS icon,
              (SELECT COUNT(*) FROM dh_assets WHERE asset_type = 'BUILDING' AND health_status = 'ALARM')
              || ' cold buildings' AS subtitle
       FROM dual
       UNION ALL
       SELECT 3, 'Incident', 'Root cause and impact path, bypass, work order', 'fa fa-alert dh-tile-incident',
              (SELECT COUNT(*) FROM dh_anomalies WHERE status <> 'CLOSED') || ' open anomalies'
       FROM dual
       UNION ALL
       SELECT 4, 'Asset', 'Telemetry with limits, anomalies, maintenance', 'fa fa-gear dh-tile-asset',
              (SELECT COUNT(*) FROM dh_assets
               WHERE  asset_type IN ('PUMP_STATION', 'SUBSTATION') AND health_status IN ('ALARM', 'WARNING'))
              || ' assets in alarm or warning'
       FROM dual
       UNION ALL
       SELECT 5, 'Assistant', 'Ask the operations agent', 'fa fa-chatbot dh-tile-assistant', NULL
       FROM dual
       UNION ALL
       SELECT 9, 'Work orders', 'All work orders, open and closed, with their status', 'fa fa-wrench dh-tile-tasks',
              (SELECT COUNT(*) FROM dh_work_orders WHERE status IN ('NEW', 'PLANNED', 'IN_PROGRESS')) || ' open work orders'
       FROM dual)
ORDER  BY page_no
```

Card attributes: Primary Key Column 1 `PAGE_NO`; Title Column `TITLE`; Subtitle Column `SUBTITLE`; Body Column `BODY`; Icon Source *Icon Class Column*, Icon Column `ICON`; no Badge Column. The count is the subtitle, on its own line below the page name: as a badge it sat next to the name and squeezed it into one letter per line. Action: Type *Full Card*, Link *Redirect to URL* `&LINK.`.

The tile *Work orders* opens page 9, the list of all work orders; the open steps of the workflow are in *Tasks* (page 7) of the navigation menu. The count of open work orders moved from the tile *Asset* to this tile.

The column `ICON` holds three classes: `fa`, the icon, and a class of our own (`dh-tile-…`) that selects the colour of the circle.

### 5.3 Page CSS (Inline)

```css
/* tile icons: one circle colour per page */
#tiles .a-CardView-item:has(.dh-tile-network)   { --dh-tile: #2C3E50; }  /* dark slate */
#tiles .a-CardView-item:has(.dh-tile-incident)  { --dh-tile: #C74634; }  /* alarm red  */
#tiles .a-CardView-item:has(.dh-tile-asset)     { --dh-tile: #8D6E63; }  /* brown      */
#tiles .a-CardView-item:has(.dh-tile-assistant) { --dh-tile: #16A085; }  /* teal       */
#tiles .a-CardView-item:has(.dh-tile-tasks)     { --dh-tile: #5F96AE; }  /* steel blue */
#tiles .a-CardView-item:has([class*="dh-tile-"]) .a-CardView-iconWrap,
#tiles .a-CardView-item:has([class*="dh-tile-"]) .a-CardView-icon {   /* the circle; its wrapper is a square */
  --a-cv-icon-background-color: var(--dh-tile);
  background-color: var(--dh-tile) !important;
  color: #FFFFFF !important; border-radius: 50%;
}
```

### 5.4 Page JavaScript (Execute when Page Loads)

The same refresh as on page 2 (section 6.6), every 30 seconds. Page 1 has no regions with these Static IDs, so it does nothing here; the badges are updated when the page is opened again.

---

## 6. Page 2 "Network"

Page alias `NETWORK`, template *Standard*. Regions in the slot *Body*, from top to bottom:

| Seq | Region | Type | Template | Static ID |
|---|---|---|---|---|
| 10 | Graph filter | Static Content | *Blank with Attributes* | – |
| 30 | Network graph | Graph Visualization (plug-in) | *Collapsible*, expanded, *Scroll – Body* | `network` |
| 40 | Map | Map | *Collapsible*, expanded, *Scroll – Body* | `map` |
| 50 | Open anomalies | Cards | *Cards Container*, *Hide Header* | `anomalies` |

Plus the region *Breadcrumb* (section 4.3).

### 6.1 Item `P2_SHOW_BUILDINGS` and the filter

- Item **`P2_SHOW_BUILDINGS`** in region *Graph filter*: Type **Switch**, label `Show buildings` (left aligned), template *Optional – Floating*, *Use Defaults* off, On Value `Y`, On Label `Yes`, Off Value `N`, Off Label `No`, Default *Static* `N`.
- Dynamic Action **Apply building filter**: Event *Change*, Selection Type *Item(s)* `P2_SHOW_BUILDINGS`; True action **Submit Page**, Request / Button Name `APPLY_FILTER`, *Fire on Initialization* off.
- Branch **Back to Network**: after processing, to page 2.

The submit reloads the page, so graph, map layers and map legend are all built again from the new value.

### 6.2 Region "Network graph"

Source SQL Query, Page Items to Submit `P2_SHOW_BUILDINGS`:

```sql
SELECT *
FROM   GRAPH_TABLE (
    dh_network
    MATCH (a IS asset) -[e IS supplies]-> (b IS asset)
    WHERE (:P2_SHOW_BUILDINGS = 'Y' OR b.asset_type <> 'BUILDING')
    COLUMNS (VERTEX_ID(a) AS id_a, EDGE_ID(e) AS id_e, VERTEX_ID(b) AS id_b))
```

Columns `ID_A`, `ID_E`, `ID_B` with data type CLOB. One row per pipe; the plug-in loads the properties of the vertices and edges itself, so the styles can use `ASSET_TYPE`, `HEALTH_STATUS` and `VALVE_STATE`.

Attributes:

| Group | Setting |
|---|---|
| Settings | Display Size **500**, Live Search on |
| Appearance | Height **640**, Size Mode *Compact*, Edge Marker *Arrow*; Display: *Modes* and *Exploration*; mode options *Interaction*, *Fit to Screen*, *Sticky*, *Evolution* (defaults: Fit to Screen, Evolution); exploration options *Expand*, *Focus*, *Group*, *Ungroup*, *Drop*, *Undo*, *Redo*, *Reset* |
| Layout | **Radial** |
| Captions | Vertex Caption `ASSET_ID` |
| Expand | Enable Expand on |

**Advanced → Base Styles:**

```json
{
    "vertex": { "size": 14, "color": "#7FA65F",
                "label": { "text": "${properties.ASSET_ID}", "angle": 270, "d": 4, "font": { "size": 20 }, "color": "#7FA65F" },
                "border": { "color": "#FFFFFF", "width": 1 } },
    "edge":   { "width": 2, "color": "#9B9B9B",
                "label": { "text": "${properties.PIPE_ID}", "font": { "size": 20 }, "color": "#6B6B6B" } }
}
```

The vertex label sits below the vertex (`angle` 270) and 4 pixels outside it (`d`), in the colour of the vertex; font size 20 for the projector.

**Advanced → Rule-Based Styles** (one rule per line without spaces: the attribute takes at most 4,000 characters). Asset types first, health states last: when several rules match, the later one wins, so a pump station in WARNING is orange. Each rule repeats the whole label with its own colour.

```json
[
{"legendTitle":"Heat plant","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"ASSET_TYPE","operator":"=","value":"PLANT"}]},"style":{"color":"#8E44AD","size":30,"icon":{"class":"fa-fire","color":"#FFFFFF"},"label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#8E44AD"}}},
{"legendTitle":"Pump station","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"ASSET_TYPE","operator":"=","value":"PUMP_STATION"}]},"style":{"color":"#2C3E50","size":24,"icon":{"class":"fa-cog","color":"#FFFFFF"},"label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#2C3E50"}}},
{"legendTitle":"Substation","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"ASSET_TYPE","operator":"=","value":"SUBSTATION"}]},"style":{"color":"#8D6E63","size":18,"label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#8D6E63"}}},
{"legendTitle":"Building","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"ASSET_TYPE","operator":"=","value":"BUILDING"}]},"style":{"color":"#7FA65F","size":12,"label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#7FA65F"}}},
{"legendTitle":"Alarm (flashing)","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"HEALTH_STATUS","operator":"=","value":"ALARM"}]},"animations":[[{"duration":1.2,"timingFunction":"ease-in-out","keyFrames":[{"percentage":0,"style":{"opacity":1}},{"percentage":50,"style":{"opacity":0.25}},{"percentage":100,"style":{"opacity":1}}]}]],"style":{"color":"#C74634","label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#C74634"}}},
{"legendTitle":"Warning","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"HEALTH_STATUS","operator":"=","value":"WARNING"}]},"style":{"color":"#F0AB00","label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#F0AB00"}}},
{"legendTitle":"Watch (predicted)","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"HEALTH_STATUS","operator":"=","value":"WATCH"}]},"style":{"color":"#D63384","label":{"text":"${properties.ASSET_ID}","angle":270,"d":4,"font":{"size":20},"color":"#D63384"}}},
{"legendTitle":"Bypass (closed)","component":"edge","target":"edge","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"VALVE_STATE","operator":"=","value":"CLOSED"}]},"style":{"color":"#5F96AE"}}
]
```

| Rule | Colour | Size |
|---|---|---|
| Heat plant | purple `#8E44AD`, icon `fa-fire` | 30 |
| Pump station | dark slate `#2C3E50`, icon `fa-cog` | 24 |
| Substation | brown `#8D6E63` | 18 |
| Building | green `#7FA65F` | 12 |
| Alarm | red `#C74634`, flashing (opacity 1 → 0.25 → 1 every 1.2 s) | of the type |
| Warning | orange `#F0AB00` | of the type |
| Watch (predicted) | magenta `#D63384` | of the type |
| Bypass (closed), edge | light blue `#5F96AE` | – |

### 6.3 Region "Map"

Type **Map**, Background *Built-in*, *Oracle World Map*; Controls *Rectangle Zoom*, *Scale Bar*, *Infinite Map*, *Distance Tool*; Messages *Below*. Footer Text:

```html
<p>Circles: red alarm, orange warning, magenta predicted problem; otherwise the colour of the type.</p>
```

Six layers; all use Geometry Column `GEOM`. The colours come from the columns `HEALTH_COLOR` and `LINE_COLOR` of the views.

| Seq | Layer | Type | Source (Table / Where) | Primary key | Appearance |
|---|---|---|---|---|---|
| 10 | Pipes | Lines | `DH_PIPE_LINES_V`, `pipe_kind <> 'BYPASS' AND (:P2_SHOW_BUILDINGS = 'Y' OR to_asset_type <> 'BUILDING')`, submit `P2_SHOW_BUILDINGS` | `PIPE_ID` | Stroke `&LINE_COLOR.`, width 2 |
| 20 | Bypasses | Lines | `DH_PIPE_LINES_V`, `pipe_kind = 'BYPASS'` | `PIPE_ID` | Stroke `&LINE_COLOR.`, width 3, *Dashed* |
| 30 | Buildings | Points | `DH_ASSET_STATUS_V`, `asset_type = 'BUILDING' AND :P2_SHOW_BUILDINGS = 'Y'`, submit `P2_SHOW_BUILDINGS` | `ASSET_ID` | Circle, scale 0.8 |
| 40 | Substations | Points | `DH_ASSET_STATUS_V`, `asset_type = 'SUBSTATION'` | `ASSET_ID` | Circle, scale 1.1 |
| 50 | Pump stations | Points | `DH_ASSET_STATUS_V`, `asset_type = 'PUMP_STATION'` | `ASSET_ID` | Circle, scale 1.5 |
| 60 | Heat plants | Points | `DH_ASSET_STATUS_V`, `asset_type = 'PLANT'` | `ASSET_ID` | Circle, scale 2 |

Point layers: Point Objects Style *SVG*, Shape *Circle*; Fill Color `&HEALTH_COLOR.`, Fill Opacity `.9`, Stroke Color `#ffffff`, Stroke Width 1. Layer *Buildings* also has the Server-side Condition *Item = Value*, `P2_SHOW_BUILDINGS` = `Y`, so it (and its legend entry) only exists while the switch is on.

**Tooltips** (Advanced Formatting on). Point layers:

```html
<strong>&ASSET_ID.</strong> &NAME.<br>
&TYPE_NAME. · &DISTRICT.<br>
<span style="color:&HEALTH_COLOR.; font-weight:bold">&HEALTH_STATUS.</span> &HEALTH_REASON.
```

Pipes: `<strong>&PIPE_ID.</strong> &PIPE_KIND.<br>&FROM_ASSET. → &TO_ASSET. · DN &DIAMETER_MM. · &LENGTH_M. m` · Bypasses: `· valve &VALVE_STATE.`

**Links**: layers *Pump stations*, *Substations* (and *Buildings*) → *Redirect to Page in this Application*, page 4, Set Items `P4_ASSET_ID` = `&ASSET_ID.`; *Pump stations* and *Substations* also Clear Cache `4`.

**Legend** (each layer: Legend → Show on, Advanced Formatting on). The entry is plain HTML, so it has no show/hide box and shows the colour of its type:

| Layer | HTML Expression |
|---|---|
| Pipes | `<span class="dh-leg dh-leg-pipe">Pipes</span>` |
| Bypasses | `<span class="dh-leg dh-leg-bypass">Bypasses (green when open)</span>` |
| Buildings | `<span class="dh-leg dh-leg-building">Buildings</span>` |
| Substations | `<span class="dh-leg dh-leg-substation">Substations</span>` |
| Pump stations | `<span class="dh-leg dh-leg-pump">Pump stations</span>` |
| Heat plants | `<span class="dh-leg dh-leg-plant">Heat plants</span>` |

**Zoom to the network**: Map attributes → **Initial Position and Zoom**, Type *SQL Query*, Geometry Column Data Type *Longitude/Latitude*, Longitude Column `LON`, Latitude Column `LAT`, Zoom Level Column `ZOOM`:

```sql
SELECT (MIN(longitude) + MAX(longitude)) / 2 AS lon,
       (MIN(latitude)  + MAX(latitude))  / 2 AS lat,
       FLOOR(LOG(2, 700 / GREATEST(MAX(longitude) - MIN(longitude),
                                   (MAX(latitude) - MIN(latitude)) * 1.5))) AS zoom
FROM   dh_assets
```

The centre of the network and a zoom level at which its extent (about 700 pixels wide; latitude counts 1.5 times at this latitude) fits into the map. The map opens there directly; no JavaScript moves it afterwards. A zoom with `fitBounds` in the event *Map Initialized* changed the zoom while the map was still loading its first data: the map cancelled that request and failed with *TypeError: l.mapData is null*.

### 6.4 Region "Open anomalies"

Type **Cards**, Source Table `DH_OPEN_ANOMALIES_V`, Order By *Static Value* `DECODE(severity, 'ALARM', 1, 'WARNING', 2, 3), asset_id`, Grid Columns **3**.

- Card: Primary Key Column 1 `ANOMALY_ID`
- Title: Column `ASSET_ID`, **CSS Classes `&ANOMALY_CLASS.`** (one class per anomaly type, for example `dh-anom-threshold`)
- Subtitle: Advanced Formatting, `&ASSET_NAME. · &ANOMALY_TYPE_NAME. · &SEVERITY.`
- Body: Advanced Formatting, `&DETAILS.`
- Action: *Full Card* → page 4, Set Items `P4_ASSET_ID` = `&ASSET_ID.`, `P4_METRIC` = `&METRIC.`, Clear Cache `4`

Header Text:

```html
<p>Anomalies found by the detection job, which checks every reading of the last
two minutes. A card stays here until its condition has been gone for one minute.
Click a card to open the asset.</p>
<p>
  <span class="dh-anom-tag dh-anom-threshold">Limit exceeded</span> above the warning or alarm limit
  <span class="dh-anom-tag dh-anom-zscore">Unusual value</span> far from the asset's normal values (z-score)
  <span class="dh-anom-tag dh-anom-trend">Trend towards the limit</span> rising, with the hours left until the alarm limit
  <span class="dh-anom-tag dh-anom-flatline">Value frozen</span> the value does not change, sensor probably stuck
  <span class="dh-anom-tag dh-anom-no-data">No data</span> the twin has stopped sending
</p>
```

### 6.5 Page CSS (Inline)

```css
/* map legend: one swatch per layer, in the colour of its type */
.dh-leg { display: inline-flex; align-items: center; gap: 8px;
          margin-inline-end: 24px; margin-block: 4px; }     /* space between the entries */
.dh-leg::before { content: ""; display: inline-block; flex: none; }
.dh-leg-pipe::before   { width: 20px; border-top: 2px solid #9B9B9B; }
.dh-leg-bypass::before { width: 20px; border-top: 3px dashed #5F96AE; }
.dh-leg-building::before, .dh-leg-substation::before,
.dh-leg-pump::before,     .dh-leg-plant::before {
  width: 12px; height: 12px; border-radius: 50%; border: 1px solid #FFFFFF; box-shadow: 0 0 0 1px #9B9B9B; }
.dh-leg-building::before   { background: #7FA65F; width: 9px;  height: 9px; }
.dh-leg-substation::before { background: #8D6E63; }
.dh-leg-pump::before       { background: #2C3E50; width: 15px; height: 15px; }
.dh-leg-plant::before      { background: #8E44AD; width: 18px; height: 18px; }

/* colour per anomaly type (class from DH_OPEN_ANOMALIES_V.ANOMALY_CLASS);
   the card and its inner .a-CardView both get it, so the theme cannot paint over it */
.dh-anom-threshold, .dh-anom-threshold .a-CardView { --a-cv-background-color: #F8D7D3; background-color: #F8D7D3 !important; }  /* light red     */
.dh-anom-zscore,    .dh-anom-zscore .a-CardView    { --a-cv-background-color: #FCE8C3; background-color: #FCE8C3 !important; }  /* light orange  */
.dh-anom-trend,     .dh-anom-trend .a-CardView     { --a-cv-background-color: #F6D5E5; background-color: #F6D5E5 !important; }  /* light magenta */
.dh-anom-flatline,  .dh-anom-flatline .a-CardView  { --a-cv-background-color: #E8DFDA; background-color: #E8DFDA !important; }  /* light brown   */
.dh-anom-no-data,   .dh-anom-no-data .a-CardView   { --a-cv-background-color: #E3E3E3; background-color: #E3E3E3 !important; }  /* light grey    */
.dh-anom-tag { display: inline-block; padding: 2px 8px; margin: 2px 4px 2px 0; border-radius: 10px; font-size: 12px; }
```

The swatches and colours use CSS classes rather than `style` attributes in HTML expressions, so they also work with a strict Content Security Policy.

### 6.6 Refresh every 60 seconds

Page JavaScript → *Execute when Page Loads*:

```js
setInterval(function () {
  if (document.hidden) { return; }                       // tab in the background
  ["network", "map", "anomalies"].forEach(function (id) {
    var r = apex.region(id);                             // null if no region has this Static ID
    if (!r || !r.element.is(":visible")) { return; }     // missing or collapsed region
    if (id === "map" && !r.getMapObject()) { return; }   // map not initialized yet
    try { r.refresh(); } catch (e) { apex.debug.warn("refresh " + id + ": " + e.message); }
  });
}, 60000);
```

A refresh rebuilds the graph from scratch, so expanded, moved or grouped vertices go back to the layout; every 60 seconds leaves time to explore it between two refreshes. Collapsed regions are skipped; a region that was collapsed when the page opened is drawn at the next refresh after it is expanded.

---

## 7. Page 3 "Incident"

Page alias `INCIDENT`, template *Standard*. Layout (12-column grid):

| Seq | Region | Type | Layout |
|---|---|---|---|
| 10 | Incident | Static Content, template *Standard* | full width |
| 30 | Root cause and impact | Graph Visualization (plug-in), *Collapsible*, expanded, Static ID `incident_graph` | new row, full width |
| 40 | Analysis | Static Content, template *Blank with Attributes* | new row, full width |
| ↳ 10 | Impact | Classic Report, sub-region of *Analysis* | new row, half width |
| ↳ 20 | Mitigation options | Classic Report, sub-region of *Analysis* | Start New Row **off**, Column Span **6** |

Plus the region *Breadcrumb*. A sub-region is never wider than its parent, so *Analysis* keeps Column Span *Automatic*.

### 7.1 Region "Incident": asset selection and buttons

Item **`P3_ASSET_ID`**: Type *Select List*, label `Asset`, template *Optional – Floating*, *Page Action on Selection* = **Submit Page**. List of Values, SQL Query (assets with a problem first):

```sql
SELECT asset_id || ' ' || name || ' (' || health_status || ')' AS d, asset_id AS r
FROM   dh_assets
WHERE  asset_type IN ('PUMP_STATION', 'SUBSTATION')
ORDER  BY DECODE(health_status, 'ALARM', 1, 'WARNING', 2, 'WATCH', 3, 4), asset_id
```

No *Default* on the item. The page opens on the asset that the root cause analysis names first, and the buttons below need that asset before the page renders, so it is set by a computation.

Item **`P3_BYPASS`**: Hidden, in region *Incident*. The bypass that matters for the selected asset, or empty.

Item **`P3_OPEN_WO`**: Hidden, in region *Incident*. The open work order of the selected asset (status `NEW`, `PLANNED` or `IN_PROGRESS`), or empty.

Three computations under **Pre-Rendering → Before Header** (Page Designer, *Rendering* tab: right-click *Before Header* → *Create Computation*). They are separate components that set an item; the items stay in region *Incident*.

| Seq | Item | Type | Function Body (PL/SQL) | Server-side Condition |
|---|---|---|---|---|
| 10 | `P3_ASSET_ID` | Function Body | `RETURN NVL(JSON_VALUE(agent_find_root_cause(), '$.incidents[0].root_cause_asset'), 'PS-04');` | *Item is NULL* `P3_ASSET_ID` |
| 20 | `P3_BYPASS` | Function Body | `RETURN dh_bypass_for_asset(:P3_ASSET_ID);` | – |
| 30 | `P3_OPEN_WO` | SQL Query (single value) | `SELECT MAX(wo_id) FROM dh_work_orders WHERE asset_id = :P3_ASSET_ID AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS')` | – |

The first only runs when no asset is selected yet (first call of the page, or a link without `P3_ASSET_ID`); the others run on every page view, so bypass and work order follow the selection.

`DH_BYPASS_FOR_ASSET` (`../sql/10_work_orders.sql`) returns a bypass when the asset is one of its ends, when the bypass leads into the area the asset supplies, or when the asset lies behind its end. For PS-04, PS-05, PS-06 and the substations behind PS-05 it is `BYP-1`; for the substations of PS-04 it is empty.

Buttons in slot *Next*, template *Text with Icon*, *Icon Left*, *Warn on Unsaved Changes* = *Do Not Check*:

| Seq | Button name | Label | Icon | Action | Server-side Condition (Rows returned) |
|---|---|---|---|---|---|
| 30 | `OPEN_BYPASS` | `Open bypass &P3_BYPASS.` (Hot) | `fa-unlock` | Submit Page | `SELECT 1 FROM dh_pipes WHERE pipe_id = :P3_BYPASS AND valve_state = 'CLOSED'` |
| 40 | `CLOSE_BYPASS` | `Close bypass &P3_BYPASS.` | `fa-lock` | Submit Page | `SELECT 1 FROM dh_pipes WHERE pipe_id = :P3_BYPASS AND valve_state = 'OPEN'` |
| 50 | `CREATE_WO` | `Create work order for &P3_ASSET_ID.` | `fa-wrench` | Redirect to Page in this Application: page **6**, Set Items `P6_ASSET_ID` = `&P3_ASSET_ID.`, Clear Cache `6` | `SELECT 1 FROM dh_assets WHERE asset_id = :P3_ASSET_ID AND health_status IN ('ALARM', 'WARNING') AND :P3_OPEN_WO IS NULL` |
| 60 | `OPEN_WO` | `Open work order &P3_OPEN_WO.` | `fa-wrench` | Redirect to Page in this Application: page **6**, Set Items `P6_WO_ID` = `&P3_OPEN_WO.`, Clear Cache `6` | *Item is NOT NULL* `P3_OPEN_WO` (instead of *Rows returned*) |

- The valve buttons appear only when a bypass leads into the area of the selected asset, and only one of the two at a time.
- *Create work order* appears only for an asset in alarm or warning that has no open work order yet, and its label names the asset. If the asset already has an open work order, *Open work order …* takes its place and opens that work order with its progress, so no second one is created by mistake. It opens page 6, where the work order is described and placed ([section 11](#11-work-orders-workflow-and-pages-6-to-9)).

**Coming from an earlier version of the app?** Delete the hidden item `P3_WO`, the process *Create work order* (it set `P3_WO`), the buttons `OPEN_BYP1` and `CLOSE_BYP1` with their processes, and the *Default* of `P3_ASSET_ID`. Change the action of `CREATE_WO` from *Submit Page* to the redirect above once page 6 exists.

Processes (Processing, *Execute Code*), each with *When Button Pressed*:

| Seq | Process | Button | PL/SQL | Success message | Error message |
|---|---|---|---|---|---|
| 10 | Open bypass | `OPEN_BYPASS` | `dh_set_valve(:P3_BYPASS, 'OPEN');` | `&P3_BYPASS. is open. The supply returns within about 1.5 minutes.` | `Opening &P3_BYPASS. failed.` |
| 20 | Close bypass | `CLOSE_BYPASS` | `dh_set_valve(:P3_BYPASS, 'CLOSED');` | `&P3_BYPASS. is closed.` | `Closing &P3_BYPASS. failed.` |

Branch **Back to page 3**: after processing, to page 3. The simulation reads the valve state at its next tick, so the supply changes by itself.

**Opening the bypass in the incident** (state `incident`): page 3 opens on PS-04 → *Mitigation options* shows "Open bypass valve BYP-1 (PS-06 -> PS-05)" → **Open bypass BYP-1** → after about 1.5 minutes the buildings behind PS-05 have heat again; *Mitigation options* then says "No closed bypass valve leads into the affected area", and the button changes to **Close bypass BYP-1**.

### 7.2 Region "Root cause and impact" (graph)

Source SQL Query, Page Items to Submit `P3_ASSET_ID`:

```sql
SELECT *
FROM   GRAPH_TABLE (
        dh_network
        MATCH (s IS asset WHERE s.asset_id = :P3_ASSET_ID)
           -[e IS supplies WHERE e.valve_state = 'OPEN']->{1,4}
           (b IS asset WHERE b.asset_type = 'BUILDING')
        ONE ROW PER STEP (v1, st, v2)
        COLUMNS (VERTEX_ID(v1) AS id_a, EDGE_ID(st) AS id_e, VERTEX_ID(v2) AS id_b))
UNION
SELECT *
FROM   GRAPH_TABLE (
        dh_network
        MATCH (an IS anomaly WHERE an.status <> 'CLOSED') -[d IS detected_on]-> (s IS asset WHERE s.asset_id = :P3_ASSET_ID)
        COLUMNS (VERTEX_ID(an) AS id_a, EDGE_ID(d) AS id_e, VERTEX_ID(s) AS id_b))
UNION
SELECT *
FROM   GRAPH_TABLE (
        dh_network
        MATCH (w IS work_order WHERE w.status IN ('NEW', 'PLANNED', 'IN_PROGRESS')) -[t IS targets]-> (s IS asset WHERE s.asset_id = :P3_ASSET_ID)
        COLUMNS (VERTEX_ID(w) AS id_a, EDGE_ID(t) AS id_e, VERTEX_ID(s) AS id_b))
```

`ONE ROW PER STEP` turns each path into its single pipes; `UNION` removes the pipes that several paths share. The second part attaches the open anomalies of the asset, the third its open work orders (status `NEW`, `PLANNED` or `IN_PROGRESS`), each styled by its own rule below.

Columns `ID_A`, `ID_E`, `ID_B` as CLOB. Attributes as on page 2, with these differences: Display Size **100**, Height **500**, mode default *Fit to Screen* only, Layout **Hierarchical**, Rank Direction *Top to Bottom*, Ranker *Longest Path*, no vertex caption, no Expand. **Tooltip Max Length 1000** (Appearance): the tooltip of a vertex lists its properties, and each value is cut after 100 characters by default; with 1000 the `DETAILS` of an anomaly (what was measured, against which limit) are shown in full when hovering over it.

Base Styles:

```json
{
  "vertex": { "size": 10, "color": "#7FA65F",
              "label": { "text": "${properties.ASSET_ID}", "angle": 270, "d": 4, "font": { "size": 20 }, "color": "#7FA65F" },
              "border": { "color": "#FFFFFF", "width": 1 } },
  "edge":   { "width": 2, "color": "#9B9B9B" }
}
```

Rule-Based Styles: the eight rules of page 2 (section 6.2), followed by these two, ten rules in total and about 3,600 characters (the limit is 4,000; if APEX reports it as too long, a rule is in the list twice):

```json
{"legendTitle":"Anomaly","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"ANOMALY_ID","operator":">","value":0}]},"style":{"color":"#C74634","size":16,"icon":{"class":"fa-exclamation-triangle","color":"#FFFFFF"},"label":{"text":"${properties.ANOMALY_TYPE}","angle":270,"d":4,"font":{"size":20},"color":"#C74634"}}},
{"legendTitle":"Work order","component":"vertex","target":"vertex","stylingEnabled":true,"conditions":{"operator":"and","conditions":[{"property":"WO_ID","operator":">","value":0}]},"style":{"color":"#16A085","size":16,"icon":{"class":"fa-wrench","color":"#FFFFFF"},"label":{"text":"WO ${properties.WO_ID} ${properties.PRIORITY}","angle":270,"d":4,"font":{"size":20},"color":"#16A085"}}}
```

Separate the eighth rule of page 2 from these with a comma.

### 7.3 Region "Impact"

Classic Report, Page Items to Submit `P3_ASSET_ID`, region template *Standard* with *Scroll – Body*, report template **Value Attribute Pairs – Column**, template options **Label Width: Fixed – Large** and *Left Aligned*:

```sql
SELECT jt.asset_name                                          AS "Asset",
       jt.downstream_buildings                                AS "Buildings supplied",
       jt.apartments                                          AS "Apartments supplied",
       jt.cut_off                                             AS "Cold if it fails",
       REPLACE(REPLACE(REPLACE(jt.critical, '["'), '"]'), '","', ', ') AS "Critical buildings affected"
FROM   JSON_TABLE(agent_impact_analysis(:P3_ASSET_ID), '$'
         COLUMNS (asset_name           VARCHAR2(100)  PATH '$.asset_name',
                  downstream_buildings NUMBER         PATH '$.downstream_buildings',
                  apartments           NUMBER         PATH '$.apartments',
                  cut_off              NUMBER         PATH '$.if_asset_out_of_service.buildings_without_supply',
                  critical             VARCHAR2(4000) FORMAT JSON PATH '$.if_asset_out_of_service.critical_buildings')) jt
```

The page calls the same function as the AI agent (`AGENT_IMPACT_ANALYSIS`), so app and agent always agree.

### 7.4 Region "Mitigation options"

Classic Report, Page Items to Submit `P3_ASSET_ID`, report template *Value Attribute Pairs – Column*, *Left Aligned*; When No Data Found: `No closed bypass valve leads into the affected area.`

```sql
SELECT jt.action                                              AS "Option",
       jt.still_cold                                          AS "Still cold",
       REPLACE(REPLACE(REPLACE(jt.critical, '["'), '"]'), '","', ', ') AS "Critical still cold"
FROM   JSON_TABLE(agent_impact_analysis(:P3_ASSET_ID), '$.mitigation_options[*]'
         COLUMNS (action     VARCHAR2(200)  PATH '$.action',
                  still_cold NUMBER         PATH '$.result_if_out_of_service.buildings_without_supply',
                  critical   VARCHAR2(4000) FORMAT JSON PATH '$.result_if_out_of_service.critical_buildings')) jt
```

With BYP-1 open there is no closed bypass into the area any more, so the region shows the No Data Found message.

---

## 8. Page 4 "Asset"

Page alias `ASSET`, template *Standard*.

| Seq | Region | Type | Layout | Static ID |
|---|---|---|---|---|
| 10 | Asset | Static Content, *Standard* | Column Span 4 | – |
| 20 | Details | Classic Report | Start New Row off, Column Span 8 | – |
| 30 | Last 6 hours | Chart (Line), *Collapsible* | Column Span 12 | `chart6h` |
| 40 | Last 7 days | Chart (Line), *Collapsible* | Column Span 12 | `chart7d` |
| 50 | Open anomalies | Classic Report, *Collapsible* | Column Span 6 | `anomalies4` |
| 60 | Work orders | Classic Report, *Collapsible* | Start New Row off, Column Span 6 | – |
| 70 | Maintenance | Classic Report, *Collapsible* | Column Span 12 | – |

Plus the region *Breadcrumb*. The three reports use report template *Standard* with *Alternating Rows* and *Row Highlighting*, pagination *Next and Previous Links*, columns not sortable.

### 8.1 Items and button

In region *Asset*:

- **`P4_ASSET_ID`**: Select List, label `Asset`, *Page Action on Selection* = Submit Page, Display Extra Values off, Display Null Value off; LOV:
  ```sql
  SELECT asset_id || ' ' || name || ' (' || health_status || ')' AS d, asset_id AS r
  FROM   dh_assets
  WHERE  asset_type IN ('PUMP_STATION', 'SUBSTATION')
  ORDER  BY asset_id
  ```
- **`P4_METRIC`**: Select List, label `Metric`, *Page Action on Selection* = Submit Page; LOV (only the metrics of the asset's type):
  ```sql
  SELECT m.display_name || ' (' || m.unit || ')' AS d, m.metric AS r
  FROM   dh_metrics m
  JOIN   dh_assets a ON a.asset_type = m.asset_type
  WHERE  a.asset_id = :P4_ASSET_ID
  ORDER  BY m.display_name
  ```
- Hidden: **`P4_METRIC_NAME`**, **`P4_UNIT`**, **`P4_WARN`**, **`P4_ALARM`**, and **`P4_LIMIT_KIND`** (in the body).
- Button **`INCIDENT`**: label `Incident view`, slot *Next*, icon `fa-alert`, action *Redirect to Page in this Application*, page 3, Set Items `P3_ASSET_ID` = `&P4_ASSET_ID.`.

### 8.2 Process "Set asset and metric"

Pre-Rendering, *Before Header*, Execute Code:

```sql
DECLARE
  l_type dh_assets.asset_type%TYPE;
  l_n    PLS_INTEGER;
BEGIN
  :P4_ASSET_ID := NVL(:P4_ASSET_ID, 'PS-04');
  SELECT asset_type INTO l_type FROM dh_assets WHERE asset_id = :P4_ASSET_ID;

  -- keep the metric if the asset type has it, else the default metric of the type
  SELECT COUNT(*) INTO l_n FROM dh_metrics WHERE asset_type = l_type AND metric = :P4_METRIC;
  IF l_n = 0 THEN
    :P4_METRIC := CASE l_type WHEN 'PUMP_STATION' THEN 'vibration' ELSE 't_sec' END;
  END IF;

  -- name, unit and limits for chart titles and limit lines (high limits, else low limits)
  SELECT display_name, unit, COALESCE(warn_high, warn_low), COALESCE(alarm_high, alarm_low),
         CASE WHEN COALESCE(warn_high, alarm_high) IS NOT NULL THEN 'max'
              WHEN COALESCE(warn_low,  alarm_low)  IS NOT NULL THEN 'min' END
  INTO   :P4_METRIC_NAME, :P4_UNIT, :P4_WARN, :P4_ALARM, :P4_LIMIT_KIND
  FROM   dh_metrics
  WHERE  asset_type = l_type AND metric = :P4_METRIC;
END;
```

Links from page 2 that clear the cache of page 4 and set only `P4_ASSET_ID` get the default metric of the type here.

### 8.3 Region "Details"

Classic Report, report template *Value Attribute Pairs – Column*, *Left Aligned*, Page Items to Submit `P4_ASSET_ID`:

```sql
SELECT s.name                         AS "Name",
       s.type_name                    AS "Type",
       s.district                     AS "District",
       a.equipment                    AS "Equipment",
       a.rated_kw                     AS "Rated power (kW)",
       a.install_year                 AS "Installed",
       s.criticality                  AS "Criticality (1-5)",
       s.health_status                AS "Health",
       s.health_reason                AS "Reason",
       s.health_color                 AS health_color
FROM   dh_asset_status_v s
JOIN   dh_assets a ON a.asset_id = s.asset_id
WHERE  s.asset_id = :P4_ASSET_ID
```

Column `HEALTH_COLOR`: Type *Hidden Column*. Column `Health` → Column Formatting → HTML Expression:

```html
<span style="color:#HEALTH_COLOR#; font-weight:bold">#Health#</span>
```

### 8.4 Charts "Last 6 hours" and "Last 7 days"

Both: Chart Type *Line*, height 400, legend at the bottom, x axis without minor ticks, y axis *Decimal* with 0 decimal places and no scaling. Three series each; all submit `P4_ASSET_ID`, `P4_METRIC`, `P4_WARN`, `P4_ALARM`; markers off.

| Seq | Series name | Colour | Line |
|---|---|---|---|
| 10 | `&P4_METRIC_NAME.` | `#2c3e50` | solid |
| 20 | `Warning limit (&P4_LIMIT_KIND.)` | `#f0ab00` | dashed |
| 30 | `Alarm limit (&P4_LIMIT_KIND.)` | `#c74634` | dashed |

**Last 6 hours**, title `&P4_METRIC_NAME. (&P4_UNIT.) – last 6 hours`, Label column `TS_LOCAL`, Value column `VALUE`:

```sql
-- series 10
SELECT ts_local, value FROM dh_telemetry_recent_v WHERE asset_id = :P4_ASSET_ID AND metric = :P4_METRIC ORDER BY ts_local
-- series 20
SELECT ts_local, TO_NUMBER(:P4_WARN) AS value FROM dh_telemetry_recent_v WHERE asset_id = :P4_ASSET_ID AND metric = :P4_METRIC ORDER BY ts_local
-- series 30
SELECT ts_local, TO_NUMBER(:P4_ALARM) AS value FROM dh_telemetry_recent_v WHERE asset_id = :P4_ASSET_ID AND metric = :P4_METRIC ORDER BY ts_local
```

**Last 7 days**, title `&P4_METRIC_NAME. (&P4_UNIT.) – last 7 days, hourly average`, Label column `HOUR`, Value column `VALUE`. Series 10:

```sql
SELECT TRUNC(CAST(FROM_TZ(ts, 'UTC') AT LOCAL AS DATE), 'HH24') AS hour, ROUND(AVG(value), 2) AS value
FROM   dh_telemetry
WHERE  asset_id = :P4_ASSET_ID AND metric = :P4_METRIC
AND    ts > SYS_EXTRACT_UTC(SYSTIMESTAMP) - INTERVAL '7' DAY
GROUP  BY TRUNC(CAST(FROM_TZ(ts, 'UTC') AT LOCAL AS DATE), 'HH24')
ORDER  BY 1
```

Series 20 and 30: the same query with `TO_NUMBER(:P4_WARN) AS value` and `TO_NUMBER(:P4_ALARM) AS value` instead of `ROUND(AVG(value), 2) AS value`. The limit series draw a flat dashed line at the limit over the same time axis.

### 8.5 Reports "Open anomalies", "Work orders", "Maintenance"

All with Page Items to Submit `P4_ASSET_ID`.

**Open anomalies** (When No Data Found: `No open anomalies.`):

```sql
SELECT detected_local    AS "Detected",
       anomaly_type_name AS "Type",
       severity          AS "Severity",
       metric            AS "Metric",
       details           AS "Details",
       hours_to_alarm    AS "Hours to alarm"
FROM   dh_open_anomalies_v
WHERE  asset_id = :P4_ASSET_ID
ORDER  BY detected_local DESC
```

**Work orders** (`No work orders.`):

```sql
SELECT wo_id      AS "No.",
       created_at AS "Created",
       priority   AS "Priority",
       title      AS "Title",
       status     AS "Status",
       created_by AS "Created by"
FROM   dh_work_orders
WHERE  asset_id = :P4_ASSET_ID
ORDER  BY wo_id DESC
```

**Maintenance** (`No maintenance recorded.`):

```sql
SELECT performed_on   AS "Date",
       maint_type     AS "Type",
       description    AS "Description",
       downtime_hours AS "Downtime (h)"
FROM   dh_maintenance
WHERE  asset_id = :P4_ASSET_ID
ORDER  BY performed_on DESC
```

### 8.6 Refresh every 30 seconds

Page JavaScript → *Execute when Page Loads*:

```js
setInterval(function () {
  if (document.hidden) { return; }                       // tab in the background
  ["chart6h", "anomalies4"].forEach(function (id) {
    var r = apex.region(id);
    if (!r || !r.element.is(":visible")) { return; }     // missing or collapsed region
    try { r.refresh(); } catch (e) { apex.debug.warn("refresh " + id + ": " + e.message); }
  });
}, 30000);
```

---

## 9. AI Agent "Heat Network Ops Agent"

Shared Components → Generative AI → **AI Agents** → *Create*.

| Attribute | Value |
|---|---|
| Name | `Heat Network Ops Agent` |
| Static ID | `heat_network_ops` |
| Generative AI Service | `<GENAI_SERVICE_NAME>` (static ID `<GENAI_SERVICE_STATIC_ID>`) |
| Temperature | `0.1` |
| Welcome Message | `Good morning. Ask me about the network: situation, causes, impact, what will fail next, or a work order.` |

### 9.1 System Prompt

The answer format comes last and as a template: models follow the end of the prompt and a concrete shape more reliably than a rule in the middle of a list. Replace the example names (`Rahova`, `Militari`) with the districts of your city if you like.

```text
You are the operations assistant for a district heating network. Operators ask
you about cold buildings, alarms, pump stations and what to do next.

Tools
- Use the tools. Never guess numbers, asset ids or causes.
- Current situation: call AGENT_NETWORK_STATUS, then AGENT_ACTIVE_ANOMALIES with
  MIN_SEVERITY = WARNING to name the assets behind alarms and warnings.
- "Why" questions: call AGENT_FIND_ROOT_CAUSE. It groups cold buildings into
  incidents with a root-cause asset, evidence and a classification
  (EQUIPMENT_PROBLEM or SUSPECTED_SENSOR_FAULT). For every equipment incident
  also call AGENT_IMPACT_ANALYSIS with the root-cause asset.
- "What will fail next": call AGENT_PREDICT_FAILURES.
- Call AGENT_CREATE_WORK_ORDER only when the operator asks for a work order.
  Priorities: P1 = people without heat now, P2 = failure expected within 48 h,
  P3 = within 10 days, P4 = check.

Content
- Write the asset id with the name, for example "PS-04 (Pump station Rahova)".
  Put all anomalies of one asset in one line.
- Report life-critical buildings (hospital, nursing home, school) first.
- Never say that actions are underway, planned or done unless a tool result says
  so (for example a work order returned by AGENT_CREATE_WORK_ORDER).
- Times in tool results are UTC (2026-10-29T17:17Z): write 2026-10-29 17:17 UTC.

Answer format (always, at most 200 words)
Answer only the question asked. Never announce your own next steps such as
"Next, I will ...": you cannot act on your own; write them as suggestions under
Recommended actions. Use exactly these Markdown headings. Leave out Root cause
or Impact when no tool result supports them. The text in angle brackets
describes the content; replace it with facts from the tools.

### Situation
<cold buildings, apartments, districts; the assets in alarm or warning>
### Root cause
<root-cause asset with id and name, evidence, classification>
### Impact
<life-critical buildings first, then buildings and apartments; mitigation options>
### Recommended actions
- <a check, decision or question for the operator, for example "Ask me for the
  root cause of the cold buildings in Militari">
```

### 9.2 Tools

Common settings of the read tools: Type **Retrieve Data**, Execution Point **On Demand**, Settings Type *Function Body*, Language PL/SQL. Leave *Allowed Values* of the parameters empty: APEX validates them strictly (ORA-20960) and the model does not always send the exact case; the function bodies normalise the values instead (`UPPER`, `TRIM`, `NVL`).

| Name | Description | Function body | Parameters |
|---|---|---|---|
| `agent_network_status` | Current state of the network: assets by health, buildings and apartments without heat, critical buildings, districts, open anomalies. | `RETURN agent_network_status;` | – |
| `agent_active_anomalies` | Open anomalies with asset, metric, severity, details and time, at or above a minimum severity. | `RETURN agent_active_anomalies(NVL(UPPER(TRIM(:MIN_SEVERITY)), 'WATCH'));` | `MIN_SEVERITY` (optional) |
| `agent_find_root_cause` | Groups cold buildings into incidents with root-cause asset, evidence and classification. Optional: one district. | `RETURN agent_find_root_cause(:DISTRICT);` | `DISTRICT` (optional) |
| `agent_impact_analysis` | Buildings and apartments that depend on an asset, critical buildings, and bypass options with their effect. | `RETURN agent_impact_analysis(UPPER(TRIM(:ASSET_ID)));` | `ASSET_ID`: "Asset id, for example PS-04" |
| `agent_asset_details` | Details of one asset: type, district, equipment, health, latest readings, supplier, open work orders. | `RETURN agent_asset_details(UPPER(TRIM(:ASSET_ID)));` | `ASSET_ID`: "Asset id, for example PS-04" |
| `agent_maintenance_history` | Maintenance history of one asset. | `RETURN agent_maintenance_history(UPPER(TRIM(:ASSET_ID)));` | `ASSET_ID`: "Asset id, for example PS-04" |
| `agent_predict_failures` | Assets whose trend reaches the alarm limit within a horizon, with the hours left. | `RETURN agent_predict_failures(NVL(TO_NUMBER(:HORIZON_HOURS DEFAULT NULL ON CONVERSION ERROR), 240));` | `HORIZON_HOURS` (optional): "Hours ahead, default 240" |
| `agent_critical_assets` | Assets that most buildings depend on (graph analysis, PageRank). | `RETURN agent_critical_assets(NVL(TO_NUMBER(:TOP_N DEFAULT NULL ON CONVERSION ERROR), 5));` | `TOP_N` (optional): "Number of assets, default 5" |
| `agent_what_if` | Simulates assets out of service and bypass valves opened; returns buildings without supply. Lists are comma-separated. | `RETURN agent_what_if(UPPER(TRIM(:OUT_OF_SERVICE)), UPPER(TRIM(:OPEN_VALVES)));` | `OUT_OF_SERVICE`: "Asset ids, comma-separated, for example PS-04"; `OPEN_VALVES` (optional): "Bypass ids, comma-separated, for example BYP-1" |

**`agent_create_work_order`**: Type **Execute Server-side Code**, Execution Point *On Demand*, description `Creates a work order for an asset. Use only when the operator asks for it.` Parameters `ASSET_ID`, `PRIORITY`, `TITLE`, `DETAILS` (optional). PL/SQL Code:

```sql
DECLARE
  l_json CLOB;
BEGIN
  IF :PRIORITY NOT IN ('P1', 'P2', 'P3', 'P4') THEN
    apex_ai.set_tool_result(p_result => '{"error":"PRIORITY must be P1, P2, P3 or P4"}');
    RETURN;
  END IF;
  l_json := agent_create_work_order(p_asset_id => :ASSET_ID,
                                    p_priority => :PRIORITY,
                                    p_title    => :TITLE,
                                    p_details  => :DETAILS);
  apex_ai.set_tool_result(p_result => l_json);
END;
```

| Group | Setting |
|---|---|
| User Approval | **Requires Confirmation** on · Title `Create work order?` · Message `The agent wants to create a work order. Approve only if this is what you asked for.` · Approve Label `Create` · Cancel Label `Cancel` |
| Notification | Message `Calling AGENT_CREATE_WORK_ORDER` · Type *Info* |

The agent can only write through this one tool, and only after the operator approves it in the chat.

---

## 10. Page 5 "Assistant"

Page alias `ASSISTANT`, template *Standard*. Page CSS (Inline):

```css
.dh-chat { min-height: 70vh; }   /* room for the conversation */
```

- Region **Operations assistant**: Static Content, template *Standard* with *Scroll – Body*, Source HTML Code `<div id="ops-chat" class="dh-chat"></div>`.
- Region *Breadcrumb* (section 4.3).
- Dynamic Action **Start assistant**: Event *Page Load*; True action **Show AI Assistant**:
  - AI Agent: `Heat Network Ops Agent`
  - Display As **Inline**, Container Selector `#ops-chat`
  - Quick Actions: `What is the situation in the network?`, `Why are the buildings cold?`, `What can we do right now for the hospital?`, `Which pump station will fail next if we do nothing?`

## 11. Work orders: workflow and pages 6 to 9

A work order goes through four states. Every step forward is a task that a person completes in the app (human in the loop); the workflow then changes the status in the database:

```text
NEW ──(1) approve──► PLANNED ──(2) start work──► IN_PROGRESS ──(3) confirm done──► CLOSED
  └──(1) reject──► CANCELLED                                   └─ the asset is repaired
```

| Step | Task (task definition) | Type | Status after the step |
|---|---|---|---|
| 1 | *Approve work order* (`approve-work-order`) | Approval task: Approve or Reject | `PLANNED`, or `CANCELLED` |
| 2 | *Start work* (`start-work`) | Action task: Complete | `IN_PROGRESS` |
| 3 | *Confirm work done* (`confirm-work-done`) | Action task: Complete | `DONE` in the table, shown as *Closed*; the asset is repaired |

Closing step 3 repairs the asset in the simulation: a pump station runs again without bearing wear, a substation gets a working temperature sensor again, and the maintenance history gets an entry. The buildings behind it have heat again within about 1.5 minutes.

Built from:

- **Database** (`../sql/10_work_orders.sql`): view `DH_WORK_ORDERS_V` (work order with asset type, asset label and readable status), function `DH_WORK_PLAN` (what has to be done, from the asset type and its anomalies), package `DH_WO_FLOW` (create, status changes, close and repair).
- **APEX**: three task definitions, one workflow, page 6 *Work order*, page 7 *Tasks* (unified task list), page 8 *Task details*, page 9 *Work orders* (list of all work orders).

Prerequisites: `../sql/10_work_orders.sql` installed; the parsing schema needs the privilege `CREATE JOB` (granted by `../sql/00_admin_setup.sql`).

There are no roles in this demo: every task goes to the user who started the workflow, that is the user signed in to the app who places the work order (or starts the workflow of an AI agent work order). No user name is stored in the app. `:APP_USER` cannot be used for this: workflows run in the background, where it returns `nobody`.

### 11.1 Task definitions

Shared Components → *Workflows and Automations* → **Task Definitions** → *Create*. Create the first one, then the other two the same way.

| Field | Step 1 | Step 2 | Step 3 |
|---|---|---|---|
| Name | `Approve work order` | `Start work` | `Confirm work done` |
| Type | **Approval Task** | **Action Task** | **Action Task** |
| Subject | `Approve work order` | `Start work` | `Confirm work done` |
| Static ID (default from the name) | `approve-work-order` | `start-work` | `confirm-work-done` |
| Priority | 2 - High | 2 - High | 2 - High |
| Potential Owner | Expression `:APEX$TASK_INITIATOR` | same | same |
| Business Admin | Expression `:APEX$TASK_INITIATOR` | same | same |

The workflow sets the subject of each task with the work order number and the asset (11.2), so these subjects are only fallbacks. Keep the default Static IDs: nothing in the app or the SQL refers to them; the workflow selects the task definitions by name.

Then, on the page of each of the three task definitions (every point applies to all three, except *Initiator Can Complete*):

- **Settings → Task Details Page Number**: for `approve-work-order` click **Create Task Details Page** and note the number of the new page (here **8**; rename it *Task details*). Do not enter the number of page 6 *Work order*: the details page is a page of its own that APEX generates for the task. For `start-work` and `confirm-work-done` enter the same page number: one details page for all three steps.
- **Settings → Initiator Can Complete** (`approve-work-order` only): **On**. The person who places the work order also approves it in this demo; without this setting the approval task cannot be completed by its own initiator.
- **Settings → Actions Source**: SQL Query
  ```sql
  SELECT * FROM dh_work_orders_v WHERE wo_id = :APEX$TASK_PK
  ```
- **Participants**: the Potential Owner and the Business Administrator from the dialog, Identity Type *User*, Value Type **Expression**, PL/SQL `:APEX$TASK_INITIATOR` (the workflow sets the initiator of each task to the initiator of the workflow, see 11.2).
- No parameters and no actions: the status changes are done by the workflow.

### 11.2 Workflow "Work Order"

Shared Components → *Workflows and Automations* → **Workflows** → *Create*.

**Workflow**: Name `Work Order`, Title `Work order &WO_ID. for &ASSET_TYPE_NAME. &ASSET_ID.`, Static ID `work-order` (the default).

**Version** (the node below the workflow, version `1.0`): under **Additional Data**, the source of the workflow's detail row: Table `DH_WORK_ORDERS_V`, primary key column `WO_ID`. The columns of this row (`WO_ID`, `ASSET_ID`, `ASSET_TYPE_NAME`, `TITLE`, …) can then be used as substitution strings in the activities, and `:APEX$WORKFLOW_DETAIL_PK` is the number of the work order.

**Variables**: in the tree of the Workflow Designer, right-click the **version** node `1.0 [Dev]` (one level below the workflow `Work Order`) → *Create Variable*. The workflow node itself only offers *Create Parameter*, which is not needed here. *Create Variable* is only offered while the version is *In Development*; for an active version, right-click it → *Create New Version* first.

| Static ID | Label | Data Type | Value |
|---|---|---|---|
| `WO_PK` | Work order | Number | Type *Expression*, PL/SQL `:APEX$WORKFLOW_DETAIL_PK` |
| `TASK_ID` | Task | Number | Null |
| `INITIATOR` | Initiator | Varchar2 | Type *Expression*, PL/SQL `:APEX$WORKFLOW_INITIATOR` |

`WO_PK` has a name of its own because `WO_ID` is already a column of the Additional Data; the subjects use that column (`&WO_ID.`).

`TASK_OUTCOME` and `APPROVER` are created by APEX with the first *Human Task - Create* activity.

**Participants** (right-click the version → *Create Participant*): *Workflow Owner* and *Workflow Administrator*, both Value Type **Expression**, PL/SQL `:APEX$WORKFLOW_INITIATOR`. An active workflow version needs both.

**Activities** (right-click the version → *Create Activity*; connect them in this order with *Create Connection*). In every *Human Task - Create* activity set **Task ID Item** `TASK_ID`, **Details Primary Key Item** `WO_PK` and **Initiator Item** `INITIATOR`: the task then has the workflow's initiator as its initiator, and its participants (`:APEX$TASK_INITIATOR`) are that user.

| # | Name | Type | Settings | Next |
|---|---|---|---|---|
| 1 | Start | Workflow Start | – | 2 |
| 2 | Approve work order | Human Task - Create | Definition `Approve work order`; Subject `Approve work order &WO_ID. for &ASSET_TYPE_NAME. &ASSET_ID.: &TITLE.`; Outcome `TASK_OUTCOME`; Owner `APPROVER` | 3 |
| 3 | Approved? | Workflow Switch | Type *True False Check*, Condition *Expression*, PL/SQL `:TASK_OUTCOME = 'APPROVED'` | True → 4, False → 10 |
| 4 | Status PLANNED | Execute Code | `dh_wo_flow.set_status(:APEX$WORKFLOW_DETAIL_PK, 'PLANNED');` | 5 |
| 5 | Start work | Human Task - Create | Definition `Start work`; Subject `Start work on work order &WO_ID. for &ASSET_TYPE_NAME. &ASSET_ID.: &TITLE.` | 6 |
| 6 | Status IN_PROGRESS | Execute Code | `dh_wo_flow.set_status(:APEX$WORKFLOW_DETAIL_PK, 'IN_PROGRESS');` | 7 |
| 7 | Confirm work done | Human Task - Create | Definition `Confirm work done`; Subject `Confirm work done for work order &WO_ID. for &ASSET_TYPE_NAME. &ASSET_ID.: &TITLE.` | 8 |
| 8 | Close and repair | Execute Code | `dh_wo_flow.close_work_order(:APEX$WORKFLOW_DETAIL_PK);` | 9 |
| 9 | Closed | Workflow End | – | – |
| 10 | Status CANCELLED | Execute Code | `dh_wo_flow.set_status(:APEX$WORKFLOW_DETAIL_PK, 'CANCELLED');` | 11 |
| 11 | Cancelled | Workflow End | – | – |

*Show Messages* must list no errors; then **Save**, and right-click the version → **Activate**.

The task subjects name the work order, what it is about and whether it is a pump station or a substation, for example *Approve work order 202 for Pump station PS-04: Repair pump station PS-04*, or for a work order of the AI agent *Approve work order 182 for Pump station PS-08: Pre-emptive maintenance for PS-08*.

### 11.3 Page 7 "Tasks" (unified task list)

*Create Page* → **Unified Task List** → Report Context **My Tasks**, page number **7**, name `Tasks`, alias `TASKS`, navigation: new entry in the *Navigation Menu* (label `Tasks`, icon `fa-tasks`, parent *Home*, after *Assistant*). The page lists the open tasks of the current user; a click on a task opens page 8.

Remove the checkbox **`P7_SHOW_EXPIRED`** (*Show expired tasks*), the dynamic action that refreshes the report when it changes, the item from *Page Items to Submit* of the report, and the parameter `p_show_expired_tasks => :P7_SHOW_EXPIRED` from its query (`apex_human_task.get_tasks` then hides expired tasks by default). A task only expires when its definition has a deadline, and these have none, so the checkbox would never change anything.

### 11.4 Page 6 "Work order"

Blank page, number **6**, name `Work order`, template *Standard*, breadcrumb entry *Work order* (parent *Work orders*). It is opened from page 3, page 9 (*Create work order for …*, with `P6_ASSET_ID`) or from page 4 (a work order of the list, with `P6_WO_ID`).

**Items**

| Item | Type | Settings |
|---|---|---|
| `P6_WO_ID` | Hidden | – |
| `P6_ASSET_ID` | Hidden | – |
| `P6_WORKFLOW_ID` | Hidden | – |
| `P6_STATUS` | Hidden | – |
| `P6_PRIORITY` | Select List | Label `Priority`; static values `P1 – people without heat now;P1,P2 – failure within 48 h;P2,P3 – failure within 10 days;P3,P4 – check;P4`; Default *Function Body* `RETURN dh_wo_flow.default_priority(:P6_ASSET_ID);` |
| `P6_TITLE` | Text Field | Label `Title`, width 80; Default *Function Body* `RETURN dh_wo_flow.default_title(:P6_ASSET_ID);` |
| `P6_DETAILS` | Textarea | Label `What has to be done`, 4 rows; Default *Function Body* `RETURN dh_work_plan(:P6_ASSET_ID);` |

`P6_PRIORITY`, `P6_TITLE` and `P6_DETAILS`: *Read Only* when `P6_WO_ID` is not null (the work order is placed).

**Pre-rendering** process **Load work order** (Before Header, Execute Code, Server-side Condition *Item is NOT NULL* `P6_WO_ID`):

```sql
SELECT asset_id, priority, title, details, status, workflow_id
INTO   :P6_ASSET_ID, :P6_PRIORITY, :P6_TITLE, :P6_DETAILS, :P6_STATUS, :P6_WORKFLOW_ID
FROM   dh_work_orders_v
WHERE  wo_id = :P6_WO_ID;
```

**Region "Asset"** (Classic Report, template *Value Attribute Pairs – Column*, *Left Aligned*, Page Items to Submit `P6_ASSET_ID`). It makes clear whether the work order is for a pump station or a substation:

```sql
SELECT CASE asset_type WHEN 'PUMP_STATION' THEN 'Pump station' WHEN 'SUBSTATION' THEN 'Substation' END AS "Asset type",
       asset_id || ' (' || name || ')' AS "Asset",
       district                        AS "District",
       health_status                   AS "Health",
       health_reason                   AS "Reason"
FROM   dh_asset_status_v
WHERE  asset_id = :P6_ASSET_ID
```

**Region "Work order"** (Static Content, template *Standard*) with the items `P6_PRIORITY`, `P6_TITLE`, `P6_DETAILS`, and the buttons:

| Button | Label | Action | Server-side Condition |
|---|---|---|---|
| `PLACE` (Hot) | `Place work order` | Submit Page | Item is NULL `P6_WO_ID` |
| `START_WF` | `Start workflow` | Submit Page | Rows returned `SELECT 1 FROM dh_work_orders WHERE wo_id = :P6_WO_ID AND status = 'NEW' AND workflow_id IS NULL` (work orders of the AI agent) |
| `TASKS` | `Open tasks` | Redirect to page 7 | Item is NOT NULL `P6_WO_ID` |
| `INCIDENT` | `Incident view for &P6_ASSET_ID.` | Redirect to page 3, Set Items `P3_ASSET_ID` = `&P6_ASSET_ID.` | – |

**Region "Progress"** (Classic Report, template **Badge List**, Static ID `wo_progress`, Server-side Condition Item is NOT NULL `P6_WO_ID`, Page Items to Submit `P6_WO_ID`): one badge per step, ✓ done, ● current, – still open.

```sql
SELECT CASE WHEN n >= 1 THEN '✓' END                                              AS "New",
       CASE WHEN n >= 2 THEN '✓' WHEN n = 1 THEN '●' ELSE '–' END                   AS "Planned",
       CASE WHEN n >= 3 THEN '✓' WHEN n = 2 THEN '●' ELSE '–' END                   AS "In progress",
       CASE WHEN n = 4 THEN '✓' WHEN n = 3 THEN '●' ELSE '–' END                    AS "Closed",
       status_label                                                                 AS "Status"
FROM  (SELECT status_label,
              DECODE(status, 'NEW', 1, 'PLANNED', 2, 'IN_PROGRESS', 3, 'DONE', 4, 0) AS n
       FROM   dh_work_orders_v
       WHERE  wo_id = :P6_WO_ID)
```

Page JavaScript → *Execute when Page Loads*, so the progress follows the tasks completed on pages 7 and 8:

```js
setInterval(function () {
  if (document.hidden) { return; }
  var r = apex.region("wo_progress");
  if (r) { r.refresh(); }
}, 10000);
```

**Validation** *No open work order for the asset* (When Button Pressed `PLACE`, type *No Rows returned*, display *Inline in Notification*), in case page 6 is opened twice for the same asset:

```sql
SELECT 1 FROM dh_work_orders WHERE asset_id = :P6_ASSET_ID AND status IN ('NEW', 'PLANNED', 'IN_PROGRESS')
```

Error message: `&P6_ASSET_ID. already has an open work order. Open it from page 3 or page 4 instead of placing a new one.`

**Processing** (in this order):

| Seq | Process | Type | Settings | Server-side Condition |
|---|---|---|---|---|
| 10 | Create work order | Execute Code | `:P6_WO_ID := dh_wo_flow.create_work_order(:P6_ASSET_ID, :P6_PRIORITY, :P6_TITLE, :P6_DETAILS);` | When Button Pressed `PLACE` |
| 20 | Start workflow | Execute Code | see below | Request is contained in Value `PLACE,START_WF` |

```sql
:P6_WORKFLOW_ID := apex_workflow.start_workflow(
                     p_static_id => 'work-order',
                     p_detail_pk => :P6_WO_ID);
dh_wo_flow.set_workflow(:P6_WO_ID, :P6_WORKFLOW_ID);
```

The workflow is started with `APEX_WORKFLOW.START_WORKFLOW` and the static ID of the workflow (`work-order`); the work order number is its detail primary key. Success message of process 20: `Work order &P6_WO_ID. placed. The first step is waiting in Tasks.` Branch after processing: page 6, Set Items `P6_WO_ID` = `&P6_WO_ID.`.

### 11.5 Page 8 "Task details"

Generated in 11.1. It shows the task (subject, state, history) with the buttons of the task type: *Approve* and *Reject* for step 1, *Complete* for steps 2 and 3 (labelled *Set to In progress* and *Set to Closed*, see point 4). Add the work order and the link to the incident view:

1. Hidden item **`P8_WO_ID`**, computation Before Header, SQL Query:
   ```sql
   SELECT TO_NUMBER(detail_pk) FROM apex_tasks WHERE task_id = :P8_TASK_ID
   ```
   Hidden item **`P8_ASSET_ID`**, computation after it: `SELECT asset_id FROM dh_work_orders WHERE wo_id = :P8_WO_ID`.
2. Region **Work order** (Classic Report, slot *Content Body*, sequence 35, between the generated regions *Subject* and *Details*; report template *Value Attribute Pairs – Column*, *Left Aligned*; Server-side Condition *Item is NOT NULL* `P8_WO_ID`):
   ```sql
   SELECT wo_id           AS "Work order",
          asset_type_name AS "Asset type",
          asset_label     AS "Asset",
          district        AS "District",
          priority        AS "Priority",
          title           AS "Title",
          details         AS "What has to be done",
          status_label    AS "Status"
   FROM   dh_work_orders_v
   WHERE  wo_id = :P8_WO_ID
   ```
   Page Items to Submit `P8_WO_ID`.
3. Button **`INCIDENT`** in that region (slot *Next*): label `Open incident view for &P8_ASSET_ID.`, icon `fa-alert`, action **Submit Page**. Server-side Condition *Rows returned*:
   ```sql
   SELECT 1 FROM apex_tasks WHERE task_id = :P8_TASK_ID AND subject LIKE 'Confirm work done%'
   ```
   Branch **To the incident view** (sequence 5, before the generated *Reload Dialog*, When Button Pressed `INCIDENT`): page 3, Set Items `P3_ASSET_ID` = `&P8_ASSET_ID.`. Page 8 is a drawer (modal dialog): a branch to a normal page closes the drawer and opens page 3 in the browser, a plain redirect would open page 3 inside the drawer. Add `INCIDENT` to the list of requests in the Server-side Condition of the generated process *Close Dialog*, so that the drawer is not closed before the branch.

   The button belongs to the last step: there it opens page 3 with the subgraph of the asset being repaired. After *Set to Closed*, the graph turns from red to green within about 1.5 minutes.
4. Button label of the generated button **`COMPLETE`**: `&P8_COMPLETE_LABEL.`, so it names the status the work order gets next. Hidden item **`P8_COMPLETE_LABEL`**, computation Before Header, SQL Query:
   ```sql
   SELECT CASE
            WHEN subject LIKE 'Start work%'        THEN 'Set to In progress'
            WHEN subject LIKE 'Confirm work done%' THEN 'Set to Closed'
            ELSE 'Complete'
          END
   FROM   apex_tasks
   WHERE  task_id = :P8_TASK_ID
   ```
5. If the page has no *Approve* and *Reject* buttons (it was generated from an action task): buttons `APPROVE` (Hot, `t-Button--success`, icon `fa-check`) and `REJECT` (`t-Button--danger`, icon `fa-times`) in region *Buttons*, slot *Create*, each with the Server-side Condition *Expression* `apex_human_task.is_allowed(p_task_id => :P8_TASK_ID, p_operation => apex_human_task.c_task_op_approve)` (or `c_task_op_reject`), and processes *Approve* and *Reject* of type **Human Task - Manage**, Action *Approve* or *Reject*, Task ID Item `P8_TASK_ID`, When Button Pressed `APPROVE` or `REJECT`. The task list of page 7 offers *Approve* and *Reject* as well.

If the generated page names its task item differently, use that name instead of `P8_TASK_ID`.

### 11.6 Links from page 4

In the report *Work orders* of page 4, add the column `WO_ID AS wo_id` (hidden) and give the column *No.* a link: page 6, Set Items `P6_WO_ID` = `#WO_ID#`, Clear Cache `6`. A click opens the work order with its progress; work orders of the AI agent show *Start workflow* there.

### 11.7 Page 9 "Work orders"

Blank page, number **9**, name `Work orders`, alias `WORK-ORDERS`, template *Standard*, breadcrumb entry *Work orders* (page 9, no parent), navigation entry *Work orders* (see 4.2). All work orders, open and closed, with their status; the tile *Work orders* on page 1 opens it.

Region **Work orders**: **Interactive Report**, slot *Body*, template *Standard*, SQL Query:

```sql
SELECT wo_id,
       CAST(created_at AS DATE)                       AS created_at,
       asset_type_name,
       asset_label,
       district,
       priority,
       title,
       status_label,
       CASE
         WHEN status = 'NEW' AND workflow_id IS NULL      THEN 'Not started'
         WHEN status IN ('NEW', 'PLANNED', 'IN_PROGRESS') THEN 'Running'
         ELSE 'Finished'
       END                                            AS workflow,
       CASE created_by WHEN 'AI_AGENT' THEN 'AI agent'
                       WHEN 'APEX'     THEN 'App'
                       ELSE created_by END            AS created_by,
       CASE WHEN status IN ('NEW', 'PLANNED', 'IN_PROGRESS') THEN 0 ELSE 1 END AS open_first
FROM   dh_work_orders_v
```

| Column | Heading | Settings |
|---|---|---|
| `WO_ID` | No. | Type *Link*: page 6, Set Items `P6_WO_ID` = `#WO_ID#`, Clear Cache `6`, Link Text `#WO_ID#` |
| `CREATED_AT` | Created | Format mask `YYYY-MM-DD HH24:MI` |
| `ASSET_TYPE_NAME` | Asset type | Pump station or Substation |
| `ASSET_LABEL` | Asset | |
| `DISTRICT` | District | |
| `PRIORITY` | Priority | |
| `TITLE` | Title | |
| `STATUS_LABEL` | Status | New, Planned, In progress, Closed, Cancelled |
| `WORKFLOW` | Workflow | *Not started* marks a work order of the AI agent whose workflow still has to be started on page 6 |
| `CREATED_BY` | Created by | App or AI agent |
| `OPEN_FIRST` | – | Hidden, only for sorting |

Primary default report: 50 rows, sorted by `OPEN_FIRST` ascending, then `WO_ID` descending, so open work orders come first, newest first. The report's search and filters show the closed and cancelled ones on their own.

### 11.8 The sequence in the demo

State `incident`, page 3 on PS-04:

1. **Create work order for PS-04** → page 6: asset type *Pump station*, what has to be done (bearing, alignment, restart), priority P1 → **Place work order**.
2. **Open tasks** → page 7: *Approve work order …* → page 8 → **Approve**. Status *Planned*.
3. Page 7: *Start work on work order …* → page 8 → **Set to In progress**. Status *In progress*.
4. Page 7: *Confirm work done for work order …* → page 8 → **Open incident view for PS-04** to show the red subgraph, back, **Set to Closed**. Status *Closed*, PS-04 is repaired.
5. Page 3 on PS-04: within about 1.5 minutes the subgraph turns green; the anomalies close one minute after their condition is gone.

For the stuck sensor the same with SS-09.3: *Substation*, "Replace the temperature sensor of the secondary supply", P4.

---

## 12. Login page

Page 9999, created by the application wizard and unchanged: region with template *Login* and the application name, items Username, Password, Remember username, button *Sign In*, processes *Set Username Cookie*, *Login*, *Clear Page(s) Cache*, *Get Username Cookie*.

---

## 13. Test

| Page | Check |
|---|---|
| 1 | Five tiles in five colours, each with its name and below it the number of cold buildings, open anomalies, assets in alarm or warning, open work orders; *Work orders* opens page 9 |
| 2 | Graph in radial layout, labels readable; switch *Show buildings* on: 252 vertices in the graph, building layer and legend entry on the map; off: 52 vertices, no building layer. Map zoomed to the network. Anomaly cards coloured by type; a click opens page 4 for the asset and metric. Regions refresh every 60 seconds |
| 3 | Opens on the root-cause asset; graph from the asset down to its buildings, anomalies and open work orders attached; *Impact* and *Mitigation options* side by side below the graph; *Open bypass BYP-1* for PS-04 while the valve is closed, *Close bypass BYP-1* while it is open, no bypass button for SS-04.1; *Create work order for PS-04* only for assets in alarm or warning |
| 4 | Asset and metric selection; both charts with dashed warning and alarm limits; reports for anomalies, work orders, maintenance; *Incident view* opens page 3 for the asset |
| 5 | Welcome message and quick actions; "What is the situation in the network?" answers with the headings Situation / Root cause / Impact / Recommended actions; asking for a work order shows the approval dialog before anything is written |
| 6–8 | From page 3: *Create work order for PS-04* → page 6 shows *Pump station*, what has to be done and P1 → *Place work order* → page 7 lists *Approve work order …* → *Approve* (Planned) → *Start work …* → *Set to In progress* → *Confirm work done …* with *Open incident view for PS-04* → *Set to Closed*; page 6 shows the progress; PS-04 runs again and its buildings have heat within about 1.5 minutes |
| 9 | All work orders, open ones first; a work order of the AI agent shows *Not started* under *Workflow*; a click on the number opens page 6 with that work order |

Test the Generative AI Service first (section 2.2) if page 5 shows an error.
