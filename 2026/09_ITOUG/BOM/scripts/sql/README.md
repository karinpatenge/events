# BOM demo scripts

Run these scripts from this directory with SQLcl, SQL*Plus, or SQL Developer.
The manual sequence below can be run one script at a time or with the runner.

## 1. Create the application user

Run as `ADMIN` in Oracle Autonomous AI Database, or as `SYS AS SYSDBA` or
`SYSTEM` in another Oracle AI Database deployment.

```sql
@00-create_user.sql
```

## 2. Create the schema

Connect as `BOMUSER`, then run:

```sql
@01-create_schema.sql
```

## 3. Populate and validate the demo data

Remain connected as `BOMUSER` and run these scripts in the following order:

| Step | Script | Purpose |
| ---: | --- | --- |
| 1 | `02_01-reset_data.sql` | Delete existing demo rows in dependency order. |
| 2 | `02_02a-create_json_helpers.sql` | Create JSON formatting helper packages. |
| 3 | `02_02b-create_picklist_helpers.sql` | Create deterministic picklist helper packages. |
| 4 | `02_02c-create_component_json_helpers.sql` | Create component naming, cost, weight, and JSON helper packages. |
| 5 | `02_02d-create_bom_hierarchy_helpers.sql` | Create BOM hierarchy lookup and item-insert helper packages. |
| 6 | `02_02-validate_packages.sql` | Check and recompile invalid `BOM%` packages. |
| 7 | `02_03-load_categories.sql` | Load 27 automotive component categories. |
| 8 | `02_04-load_components.sql` | Load 7,000 components with JSON specifications and compliance data. |
| 9 | `02_05-load_component_revisions.sql` | Load 17,500 engineering revisions. |
| 10 | `02_06-load_component_variants.sql` | Load 15,000 component variants. |
| 11 | `02_07-load_bom_headers_items.sql` | Load 1,000 BOM headers and 44,000 hierarchical BOM items. |
| 12 | `02_08-validate_bom_data.sql` | Display row counts, hierarchy checks, JSON samples, and a BOM tree. |

All data-load scripts set `DEFINE OFF` and avoid literal ampersands, so they
are safe for SQL*Plus, SQLcl, and SQL Developer substitution-variable handling.

As an alternative to running the 02-series scripts individually, run:

```sql
@02-run_all_populate_bom_demo.sql
```

The runner executes every individual `02_0*.sql` script in the table above,
including package validation and data validation.

## 4. Optional JSON review add-ons

Run this script after the schema and demo data have been created:

```sql
@03-bom_json_demo_review_addons.sql
```

It creates optional JSON indexes and runs read-only SQL/JSON demonstrations.

## 5. Convenience runner

`02-run_all_populate_bom_demo.sql` is the alternative to manually executing the
individual `02_0*.sql` scripts. It runs all of them in the dependency order
shown above. It does not run the optional 03-series JSON review script.

## 6. Create the SQL Property Graph

Run this script as `BOMUSER` after `01-create_schema.sql`:

```sql
@10-create_bom_graph.sql
```

It creates `bom_graph` from the BOMUSER tables, primary keys, and foreign-key
relationships. The graph reads current table data and does not copy it.

## 7. Query the whole SQL Property Graph

Run this script as `BOMUSER` after creating `bom_graph`:

```sql
@11-query_bom_graph.sql
```

It returns each graph edge with the source vertex, edge, and destination vertex
identifiers for visualization.

## Script catalog

| Script | Description |
| --- | --- |
| `00-create_user.sql` | Create the `BOMUSER` application user and grant required privileges. |
| `01-create_schema.sql` | Create the BOM demo tables, constraints, indexes, and comments. |
| `02_01-reset_data.sql` | Delete existing demo data. |
| `02_02a-create_json_helpers.sql` | Create JSON formatting helpers. |
| `02_02b-create_picklist_helpers.sql` | Create picklist helpers. |
| `02_02c-create_component_json_helpers.sql` | Create component JSON helpers. |
| `02_02d-create_bom_hierarchy_helpers.sql` | Create BOM hierarchy helpers. |
| `02_02-validate_packages.sql` | Validate and recompile `BOM%` packages when necessary. |
| `02_03-load_categories.sql` | Load component categories. |
| `02_04-load_components.sql` | Load components. |
| `02_05-load_component_revisions.sql` | Load component revisions. |
| `02_06-load_component_variants.sql` | Load component variants. |
| `02_07-load_bom_headers_items.sql` | Load BOM headers and items. |
| `02_08-validate_bom_data.sql` | Validate loaded demo data. |
| `02-run_all_populate_bom_demo.sql` | Run the population scripts. |
| `03-bom_json_demo_review_addons.sql` | Create optional JSON indexes and run SQL/JSON demonstrations. |
| `10-create_bom_graph.sql` | Create the BOM SQL Property Graph. |
| `11-query_bom_graph.sql` | Query BOM graph edges, rank component use, and display a BOM hierarchy. |
