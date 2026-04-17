# Demo the Graph Visualization capabilities of Oracle Application Express

Go to the [official Oracle APEX repository on GitHub](https://github.com/oracle/apex).

## Documentation

- [Oracle Property Graph Release 26.1 - Books](https://docs.oracle.com/en/database/oracle/property-graph/26.1/index.html)
- [SQL Graph Queries](https://docs.oracle.com/en/database/oracle/property-graph/26.1/spgdg/sql-graph-queries.html)
- [Getting Started with the APEX Graph Visualization Plug-in](https://docs.oracle.com/en/database/oracle/property-graph/26.1/spgdg/getting-started-apex-graph-visualization-plug.html)
- [Property Graph Visualization Developer's Guide and Reference](https://docs.oracle.com/en/database/oracle/property-graph/26.1/pgvtr/)
- [Embedding the Graph Visualization Library in a Web Application](https://docs.oracle.com/en/database/oracle/property-graph/26.1/spgdg/embedding-graph-visualization-library-web-application.html)
- [Visualizing SQL Graph Queries Using the APEX Graph Visualization Plug-in](https://docs.oracle.com/en/database/oracle/property-graph/26.1/spgdg/visualizing-sql-graph-queries-using-apex-graph-visualization-plug.html)

## APEX Graph Visualization Plug-ins & Sample App

- [Sample Graph Visualization App](https://github.com/oracle/apex/tree/24.2/sample-apps/sample-graph-visualizations)
- [Graph Visualization Plugin 26ai](https://github.com/oracle/apex/tree/24.2/plugins/region/graph-visualization/required-for-26ai)

## Prerequisites

Download from [apex / plugins / region / graph-visualization / required-for-26ai](https://github.com/oracle/apex/tree/24.2/plugins/region/graph-visualization/required-for-26ai) the following two scripts:

```txt
gvt_sqlgraph_to_json.sql
required_helper_functions.sql
```

These scripts are required to convert the output of SQL/PGQ queries to JSON by setting up the DBMS_GVT PL/SQL Package and to provide some helper functions for APEX.

Execute the scripts in the database schema which you want to use with APEX and Property Graphs.

## The Sample Graph Visualization app

Documentation: [Chapter 9.2.1: Importing the Sample Graph Visualizations Application in APEX](https://docs.oracle.com/en/database/oracle/property-graph/26.1/spgdg/getting-started-apex-graph-visualization-plug.html#GUID-5F7A52C8-1239-4D11-BB8B-83452F9E5762)

### Download the app

1. Select the [current branch -> 24.2](https://github.com/oracle/apex/tree/24.2).
2. Click on [sample-apps](https://github.com/oracle/apex/tree/24.2/sample-apps).
3. Click on [sample-graph-visualizations](https://github.com/oracle/apex/tree/24.2/sample-apps) to download the **Sample Graph Visualization** app for 26ai.

### Install the app

1. Connect to your APEX Workspace or create a new one.
2. Go to the `App Builder` and click on `Import`.
3. Drag & drop the file for **Sample Graph Visualization** app into the `Drag and Drop` field and click on `Next`.
4. Confirm installing the application.
5. Confirm also the installation of the supporting objects.
6. Check the installation summary.

### The app behind the scenes

1. Go to `Plugins` in the `Shared Components` of the app.
2. Review the `Graph Visualization` plugin. It is the heart of the Property Graph support in APEX.
3. Open `Page 11: Basic Graph - 26ai` and review region `Graph from Tables` to see how the plug-in is used.

### Explore the app

1. Run the **Sample Graph Visualization** app.

#### New Features

##### Page 11 "Basic Graph"

- Attributes -> Controls
- Attributes -> Size Mode, Edge Marker
- Attributes -> Live Search, Search by ...
- Attributes -> Group Edges (just explain - same source and target node)
- Help function

##### Page 19 "Schema Visualization"

- Attributes -> Schema
- Right click on schema: Vertex and Edge types

##### Page 20 "Legend Features"

Visibility and Styling toggles

Show:

- Attributes -> Enable Default Legend vs. Rule-Based Styles
- Attributes -> Rule-Based Styling
- Move legend entries up/down
- hideWhenAnyUnchecked
- hideWhenAllUnchecked

##### Page 18 "Geographical Layout"

Visibility and Styling toggles

Show:

- Attributes -> Enable Default Legend vs. Rule-Based Styles
- Attributes -> Rule-Based Styling
- Move legend entries up/down
- hideWhenAnyUnchecked
- hideWhenAllUnchecked



