# Heat Network Ops – APEX application

*EMEA Community Tour 2026 – From IoT Data to Intelligent Action*

An operator app for a synthetic district heating network: two heat plants, ten pump stations, forty substations and two hundred buildings, with the district names of Vienna or Bucharest. Pump stations and substations are digital twins that report every thirty seconds. The app shows the state of the network live, explains why buildings are cold, shows what an action would change, and lets an operator ask an AI assistant for advice.

The app reads the same data and calls the same database functions as the AI agent in the demo, so app and agent always give the same answers. The network page refreshes by itself every minute, the asset page every thirty seconds.

The export of the application is in the folder `emea-community-tour-2026-from-iot-data-to-intelligent-action`. How to build it step by step is described in [BUILD.md](BUILD.md).

## Pages

### 1 Home

The start page. Four tiles lead to the other pages, each with a live count: how many buildings are cold, how many anomalies are open, how many work orders are open.

### 2 Network

The whole network at a glance, in two views that can be expanded or collapsed:

- **Network graph:** every plant, pump station, substation and building as a node, every pipe as a line. The colour shows the type of asset and its health: red for an alarm (flashing), orange for a warning, magenta for a predicted problem. Hovering over a node shows its details.
- **Map:** the same network on a map of the city, with pipes, bypasses and assets in the colours of the graph.

A switch shows or hides the two hundred buildings in both views. Below, **Open anomalies** lists every current problem as a card, coloured by its type (limit exceeded, unusual value, trend towards the limit, frozen value, no data). A click on a card or on a pump station or substation on the map opens page 4 for that asset.

### 3 Incident

One incident in detail, for the asset selected at the top; it opens on the asset that the root cause analysis names first.

- **Root cause and impact:** a graph from the selected asset down to the buildings it supplies, with its open anomalies and work orders attached.
- **Impact:** how many buildings and apartments the asset supplies, how many would be cold if it fails, and which critical buildings (hospital, nursing home, school) are affected.
- **Mitigation options:** which bypass valve could supply part of the area instead, and how many buildings would still be cold.

If a bypass leads into the area of the asset, a button opens or closes it (*Open bypass BYP-1*). For an asset in alarm or warning, *Create work order for …* opens page 6.

### 4 Asset

Everything about one pump station or substation:

- **Details:** name, type, district, equipment, rated power, year of installation, criticality, and the current health with its reason.
- Two selections at the top choose the asset and the measurement (for example vibration, bearing temperature, flow or pressure); a button opens page 3 for the same asset.
- **Charts:** one measurement of the asset over the last six hours and as hourly averages over the last seven days, with its warning and alarm limits.
- **Open anomalies**, **maintenance history** and **work orders** of the asset; a work order opens page 6.

### 5 Assistant

A chat with the **Heat Network Ops Agent**, an AI assistant built into the app. It answers questions about the situation, the causes, the impact, and which pump station will fail next, using only approved database functions. Quick actions offer typical questions. It can create a work order, but only after the operator confirms it.

### 6 Work order

One work order for a pump station or a substation: the asset and its type, priority, title and what must be done (the work plan comes from the open anomalies, for example "restart or repair the pump" or "replace the temperature sensor"). *Place work order* creates it and starts the workflow; for a work order of the AI agent, *Start workflow* does the same. A progress list shows the steps.

The workflow **Work order** takes it through three steps with a person in the loop, each a task in page 7:

1. **Approve** (NEW → PLANNED), or reject (CANCELLED).
2. **Start work** (PLANNED → IN PROGRESS).
3. **Confirm work done** (IN PROGRESS → Closed): the asset is repaired and the repair goes into the maintenance history. The task links to page 3 for the asset, where the subgraph shows the effect.

There are no roles: the signed-in user does every step.

### 7 My tasks

The task list of the signed-in user: the open workflow steps, with *Approve*, *Reject* or *Complete*.

### 8 Task details

One task with its work order: asset, type, priority, what must be done, and in the last step the link to page 3.

### Login

The sign-in page of the application.
