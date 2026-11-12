# BOM demo

## Script to create tables

```sql
@01_01_create_schema.sql
```

[Visual of the created schema](01_02_bom_schema.svg).

## Scripts to populate data

```sql
@02_run_all_populate_bom_demo.sql
```

The runner executes the scripts in this order:

1. `02_01_reset_data.sql` - deletes existing rows in dependency order.
2. `02_02a_create_json_helpers.sql` - compiles small JSON formatting helpers.
3. `02_02b_create_picklist_helpers.sql` - compiles deterministic picklist/value-selection helpers.
4. `02_02c_create_component_json_helpers.sql` - compiles component naming, cost, weight, and JSON payload helpers.
5. `02_02d_create_bom_hierarchy_helpers.sql` - compiles BOM hierarchy lookup and item-insert helpers.
6. `02_03_load_categories.sql` - loads automotive component categories.
7. `02_04_load_components.sql` - loads approximately 7,000 components with JSON specifications and compliance payloads.
8. `02_05_load_component_revisions.sql` - loads several engineering revisions per component.
9. `02_06_load_component_variants.sql` - loads approximately 15,000 component variants.
10. `02_07_load_bom_headers_items.sql` - loads approximately 1,000 BOM headers and 44,000 hierarchical BOM items up to level 7.
11. `02_08_validate_bom_data.sql` - prints row counts, hierarchy checks, JSON samples, and a sample BOM tree.

All scripts set `DEFINE OFF` and avoid literal ampersands, so they are safe for SQL*Plus, SQLcl, or SQL Developer substitution-variable handling.

## Scripts to demo SQL Property Graphs using the Bill of Materials dataset

1. `BOM/03_01_create_bom_property_graph_using_tables.sql`
2. `BOM/03_02a_create_json_projection_views.sql`
3. `BOM/03_02b_create_json_projection_materialized_views.sql`
4. `BOM/03_03a_create_bom_property_graph_using_views.sql`
5. `BOM/03_03b_create_bom_property_graph_using_materialized_views.sql`

## Graph Studio notebooks to demo SQL Property Graphs

Import the notebooks into Graph Studio.

1. `Graph Studio Notebooks/01-Simple Graph.dsnb`
2. `Graph Studio Notebooks/02-Students Graph.dsnb`
3. `Graph Studio Notebooks/03-Openflights Plus Graph.dsnb`
4. `Graph Studio Notebooks/04a-BOM Graph.dsnb`
5. `BGraph Studio Notebooks/04b-BOM Graph Expanded.dsnb`
