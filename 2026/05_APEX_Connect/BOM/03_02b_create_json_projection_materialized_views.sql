--==============================================================================
--  03_02b_create_json_projection_materialized_views.sql
--  First-level JSON projection materialized views for the BOM demo schema
--  Target: Oracle AI Database 26ai
--
--  JSON handling:
--    * Tables with JSON columns are exposed through materialized views named:
--        <original_table_name>_mv
--    * Each materialized view is generated from Oracle JSON Data Guide metadata.
--    * Only first-level JSON document keys are projected into new columns.
--    * First-level scalar values use JSON_VALUE with a typed RETURNING clause.
--    * First-level nested objects and arrays remain JSON values through
--      JSON_QUERY(... RETURNING JSON).
--    * Generated JSON column names use singular terms and concatenate the JSON
--      document name plus the first-level JSON key with underscores.
--
--  Run this after the base BOM tables are created and populated. JSON_DATAGUIDE
--  scans the current data set, so rerun this script after materially changing
--  the JSON payload shape.
--
--  The materialized views are created as:
--      BUILD IMMEDIATE REFRESH COMPLETE ON DEMAND
--
--  Refresh example:
--      EXEC DBMS_MVIEW.REFRESH('BOM_COMPONENTS_MV', 'C');
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT
PROMPT === Creating first-level JSON projection materialized views from Data Guide output ===

DECLARE
    TYPE t_seen_column IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(128);
    TYPE t_seen_path   IS TABLE OF PLS_INTEGER INDEX BY VARCHAR2(4000);
    TYPE t_path_list   IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    TYPE t_type_map    IS TABLE OF VARCHAR2(30) INDEX BY VARCHAR2(4000);
    TYPE t_flag_map    IS TABLE OF VARCHAR2(1) INDEX BY VARCHAR2(4000);
    TYPE t_num_map     IS TABLE OF NUMBER INDEX BY VARCHAR2(4000);

    FUNCTION singular_token(p_token IN VARCHAR2) RETURN VARCHAR2 IS
        l_token VARCHAR2(4000);
    BEGIN
        l_token := LOWER(REGEXP_REPLACE(p_token, '[^[:alnum:]]+', '_'));
        l_token := REGEXP_REPLACE(l_token, '^_+|_+$', '');

        IF REGEXP_LIKE(l_token, 'ies$') THEN
            l_token := REGEXP_REPLACE(l_token, 'ies$', 'y');
        ELSIF LENGTH(l_token) > 4
              AND REGEXP_LIKE(l_token, 's$')
              AND NOT REGEXP_LIKE(l_token, '(ss|us|is)$') THEN
            l_token := REGEXP_REPLACE(l_token, 's$', '');
        END IF;

        RETURN l_token;
    END singular_token;

    FUNCTION first_level_path(p_path IN VARCHAR2) RETURN VARCHAR2 IS
        l_path  VARCHAR2(4000) := TRIM(p_path);
        l_pos   PLS_INTEGER;
        l_end   PLS_INTEGER;
        l_char  VARCHAR2(1);
    BEGIN
        IF l_path IS NULL OR l_path = '$' OR SUBSTR(l_path, 1, 1) != '$' THEN
            RETURN NULL;
        END IF;

        l_pos := 2;

        IF SUBSTR(l_path, l_pos, 1) = '.' THEN
            l_pos := l_pos + 1;
        END IF;

        IF l_pos > LENGTH(l_path) THEN
            RETURN NULL;
        END IF;

        IF SUBSTR(l_path, l_pos, 1) = '"' THEN
            l_end := INSTR(l_path, '"', l_pos + 1);

            IF l_end = 0 THEN
                RETURN NULL;
            END IF;

            RETURN '$.' || SUBSTR(l_path, l_pos, l_end - l_pos + 1);
        END IF;

        l_end := LENGTH(l_path) + 1;

        FOR i IN l_pos .. LENGTH(l_path) LOOP
            l_char := SUBSTR(l_path, i, 1);

            IF l_char IN ('.', '[') THEN
                l_end := i;
                EXIT;
            END IF;
        END LOOP;

        IF l_end <= l_pos THEN
            RETURN NULL;
        END IF;

        RETURN '$.' || SUBSTR(l_path, l_pos, l_end - l_pos);
    END first_level_path;

    FUNCTION path_to_column_name(
        p_prefix IN VARCHAR2,
        p_path   IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_key  VARCHAR2(4000) := p_path;
        l_name VARCHAR2(4000);
    BEGIN
        l_key := REGEXP_REPLACE(l_key, '^\$\.?', '');
        l_key := REGEXP_REPLACE(l_key, '\[.*$', '');
        l_key := REPLACE(l_key, '"', '');

        l_name := singular_token(p_prefix) || '_' || singular_token(l_key);
        RETURN UPPER(SUBSTR(l_name, 1, 128));
    END path_to_column_name;

    FUNCTION unique_column_name(
        p_name IN VARCHAR2,
        p_seen IN OUT NOCOPY t_seen_column
    ) RETURN VARCHAR2 IS
        l_base VARCHAR2(128) := SUBSTR(p_name, 1, 128);
        l_name VARCHAR2(128) := SUBSTR(p_name, 1, 128);
        l_seq  PLS_INTEGER := 2;
    BEGIN
        WHILE p_seen.EXISTS(l_name) LOOP
            l_name := SUBSTR(l_base, 1, 128 - LENGTH('_' || l_seq)) || '_' || l_seq;
            l_seq := l_seq + 1;
        END LOOP;

        p_seen(l_name) := 1;
        RETURN l_name;
    END unique_column_name;

    FUNCTION merge_scalar_type(
        p_current IN VARCHAR2,
        p_new     IN VARCHAR2
    ) RETURN VARCHAR2 IS
        l_new VARCHAR2(30) := LOWER(p_new);
    BEGIN
        IF l_new IN ('null') THEN
            RETURN NVL(p_current, 'string');
        END IF;

        IF p_current IS NULL THEN
            RETURN l_new;
        END IF;

        IF p_current = l_new THEN
            RETURN p_current;
        END IF;

        RETURN 'string';
    END merge_scalar_type;

    PROCEDURE parse_base_columns(
        p_base_columns IN VARCHAR2,
        p_seen         IN OUT NOCOPY t_seen_column
    ) IS
        l_count PLS_INTEGER;
        l_col   VARCHAR2(128);
    BEGIN
        l_count := REGEXP_COUNT(p_base_columns, '[^,]+');

        FOR i IN 1 .. l_count LOOP
            l_col := UPPER(TRIM(REGEXP_SUBSTR(p_base_columns, '[^,]+', 1, i)));
            p_seen(l_col) := 1;
        END LOOP;
    END parse_base_columns;

    PROCEDURE append_text(
        p_clob IN OUT NOCOPY CLOB,
        p_text IN VARCHAR2
    ) IS
    BEGIN
        DBMS_LOB.APPEND(p_clob, TO_CLOB(p_text));
    END append_text;

    PROCEDURE run_ddl(p_sql IN CLOB) IS
        l_cursor INTEGER;
    BEGIN
        l_cursor := DBMS_SQL.OPEN_CURSOR;
        DBMS_SQL.PARSE(l_cursor, p_sql, DBMS_SQL.NATIVE);
        DBMS_SQL.CLOSE_CURSOR(l_cursor);
    EXCEPTION
        WHEN OTHERS THEN
            IF DBMS_SQL.IS_OPEN(l_cursor) THEN
                DBMS_SQL.CLOSE_CURSOR(l_cursor);
            END IF;
            RAISE;
    END run_ddl;

    PROCEDURE drop_materialized_view_if_exists(p_mv_name IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || p_mv_name;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-12003, -942) THEN
                RAISE;
            END IF;
    END drop_materialized_view_if_exists;

    PROCEDURE append_json_projection(
        p_select_list IN OUT NOCOPY CLOB,
        p_json_column IN VARCHAR2,
        p_prefix      IN VARCHAR2,
        p_path        IN VARCHAR2,
        p_type        IN VARCHAR2,
        p_is_nested   IN VARCHAR2,
        p_length      IN NUMBER,
        p_seen        IN OUT NOCOPY t_seen_column
    ) IS
        l_column  VARCHAR2(128);
        l_type    VARCHAR2(30) := LOWER(p_type);
        l_varchar NUMBER;
    BEGIN
        l_column := unique_column_name(
                        path_to_column_name(p_prefix, p_path),
                        p_seen
                    );

        IF p_is_nested = 'Y' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_QUERY(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING JSON NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'number' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING NUMBER NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'double' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING BINARY_DOUBLE NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'float' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING BINARY_FLOAT NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'boolean' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING BOOLEAN NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'date' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING DATE NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSIF l_type = 'timestamp' THEN
            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING TIMESTAMP NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        ELSE
            l_varchar := LEAST(GREATEST(NVL(p_length, 4000), 1), 4000);

            append_text(
                p_select_list,
                ',' || CHR(10) ||
                '    JSON_VALUE(' || p_json_column || ', ''' ||
                REPLACE(p_path, '''', '''''') ||
                ''' RETURNING VARCHAR2(' || l_varchar ||
                ') NULL ON EMPTY NULL ON ERROR) AS ' || l_column
            );
        END IF;
    END append_json_projection;

    PROCEDURE add_json_data_guide_columns(
        p_select_list IN OUT NOCOPY CLOB,
        p_table_name  IN VARCHAR2,
        p_json_column IN VARCHAR2,
        p_prefix      IN VARCHAR2,
        p_seen        IN OUT NOCOPY t_seen_column
    ) IS
        l_data_guide CLOB;
        l_sql        VARCHAR2(1000);
        l_top_path   VARCHAR2(4000);
        l_type       VARCHAR2(30);
        l_count      PLS_INTEGER := 0;
        l_seen_path  t_seen_path;
        l_paths      t_path_list;
        l_type_map   t_type_map;
        l_nested_map t_flag_map;
        l_length_map t_num_map;
    BEGIN
        l_sql :=
            'SELECT JSON_DATAGUIDE(' || p_json_column || ', DBMS_JSON.FORMAT_FLAT) ' ||
            'FROM ' || p_table_name || ' WHERE ' || p_json_column || ' IS NOT NULL';

        EXECUTE IMMEDIATE l_sql INTO l_data_guide;

        IF l_data_guide IS NULL THEN
            RETURN;
        END IF;

        FOR r IN (
            SELECT path_value, type_value, length_value
            FROM JSON_TABLE(
                l_data_guide,
                '$[*]'
                COLUMNS (
                    path_value   VARCHAR2(4000) PATH '$."o:path"',
                    type_value   VARCHAR2(30)   PATH '$.type',
                    length_value NUMBER         PATH '$."o:length"'
                )
            )
            WHERE path_value IS NOT NULL
            ORDER BY path_value, type_value
        ) LOOP
            l_top_path := first_level_path(r.path_value);

            IF l_top_path IS NULL THEN
                CONTINUE;
            END IF;

            IF NOT l_seen_path.EXISTS(l_top_path) THEN
                l_count := l_count + 1;
                l_seen_path(l_top_path) := l_count;
                l_paths(l_count) := l_top_path;
                l_nested_map(l_top_path) := 'N';
                l_type_map(l_top_path) := NULL;
                l_length_map(l_top_path) := 0;
            END IF;

            l_type := LOWER(r.type_value);

            IF r.path_value != l_top_path
               OR l_type IN ('array', 'object', 'geojson') THEN
                l_nested_map(l_top_path) := 'Y';
            ELSIF l_type IN (
                    'number',
                    'double',
                    'float',
                    'boolean',
                    'date',
                    'timestamp',
                    'string',
                    'null'
                  ) THEN
                l_type_map(l_top_path) := merge_scalar_type(
                                             l_type_map(l_top_path),
                                             l_type
                                          );
                l_length_map(l_top_path) := GREATEST(
                                               NVL(l_length_map(l_top_path), 0),
                                               NVL(r.length_value, 0)
                                            );
            END IF;
        END LOOP;

        FOR i IN 1 .. l_count LOOP
            append_json_projection(
                p_select_list => p_select_list,
                p_json_column => p_json_column,
                p_prefix      => p_prefix,
                p_path        => l_paths(i),
                p_type        => NVL(l_type_map(l_paths(i)), 'string'),
                p_is_nested   => NVL(l_nested_map(l_paths(i)), 'N'),
                p_length      => NULLIF(l_length_map(l_paths(i)), 0),
                p_seen        => p_seen
            );
        END LOOP;
    END add_json_data_guide_columns;

    PROCEDURE create_json_projection_mv(
        p_mv_name      IN VARCHAR2,
        p_table_name   IN VARCHAR2,
        p_base_columns IN VARCHAR2,
        p_json_columns IN SYS.ODCIVARCHAR2LIST,
        p_prefixes     IN SYS.ODCIVARCHAR2LIST
    ) IS
        l_select_list CLOB;
        l_sql         CLOB;
        l_seen        t_seen_column;
    BEGIN
        DBMS_LOB.CREATETEMPORARY(l_select_list, TRUE);
        DBMS_LOB.CREATETEMPORARY(l_sql, TRUE);

        parse_base_columns(p_base_columns, l_seen);
        append_text(l_select_list, '    ' || REPLACE(p_base_columns, ',', ',' || CHR(10) || '    '));

        FOR i IN 1 .. p_json_columns.COUNT LOOP
            add_json_data_guide_columns(
                p_select_list => l_select_list,
                p_table_name  => p_table_name,
                p_json_column => p_json_columns(i),
                p_prefix      => p_prefixes(i),
                p_seen        => l_seen
            );
        END LOOP;

        drop_materialized_view_if_exists(p_mv_name);

        append_text(l_sql, 'CREATE MATERIALIZED VIEW ' || p_mv_name || CHR(10));
        append_text(l_sql, 'BUILD IMMEDIATE' || CHR(10));
        append_text(l_sql, 'REFRESH COMPLETE ON DEMAND' || CHR(10));
        append_text(l_sql, 'AS' || CHR(10));
        append_text(l_sql, 'SELECT' || CHR(10));
        DBMS_LOB.APPEND(l_sql, l_select_list);
        append_text(l_sql, CHR(10) || 'FROM ' || p_table_name);

        run_ddl(l_sql);

        DBMS_OUTPUT.PUT_LINE('Created ' || p_mv_name || ' with first-level JSON projections.');
        DBMS_LOB.FREETEMPORARY(l_select_list);
        DBMS_LOB.FREETEMPORARY(l_sql);
    END create_json_projection_mv;
BEGIN
    create_json_projection_mv(
        p_mv_name      => 'bom_components_mv',
        p_table_name   => 'bom_components',
        p_base_columns => 'component_id, part_number, component_name, category_id, powertrain_type, unit_of_measure, standard_cost, weight_kg, lifecycle_status, created_date',
        p_json_columns => SYS.ODCIVARCHAR2LIST('specifications', 'compliance'),
        p_prefixes     => SYS.ODCIVARCHAR2LIST('specification', 'compliance')
    );

    create_json_projection_mv(
        p_mv_name      => 'bom_component_revisions_mv',
        p_table_name   => 'bom_component_revisions',
        p_base_columns => 'revision_id, component_id, revision_code, revision_date, eco_number, engineer_name, change_summary, revision_status',
        p_json_columns => SYS.ODCIVARCHAR2LIST('specifications'),
        p_prefixes     => SYS.ODCIVARCHAR2LIST('specification')
    );

    create_json_projection_mv(
        p_mv_name      => 'bom_component_variants_mv',
        p_table_name   => 'bom_component_variants',
        p_base_columns => 'variant_id, component_id, variant_code, variant_name, region_code, market_segment, cost_adjustment, variant_status',
        p_json_columns => SYS.ODCIVARCHAR2LIST('variant_attributes'),
        p_prefixes     => SYS.ODCIVARCHAR2LIST('variant_attribute')
    );

    create_json_projection_mv(
        p_mv_name      => 'bom_headers_mv',
        p_table_name   => 'bom_headers',
        p_base_columns => 'bom_id, bom_code, bom_name, vehicle_model, model_year, trim_level, powertrain_type, plant_code, top_component_id, effective_date, expiration_date, bom_status',
        p_json_columns => SYS.ODCIVARCHAR2LIST('bom_metadata'),
        p_prefixes     => SYS.ODCIVARCHAR2LIST('bom_metadata')
    );

    create_json_projection_mv(
        p_mv_name      => 'bom_items_mv',
        p_table_name   => 'bom_items',
        p_base_columns => 'bom_item_id, bom_id, parent_item_id, component_id, revision_id, variant_id, level_num, sequence_num, find_number, quantity, reference_designator',
        p_json_columns => SYS.ODCIVARCHAR2LIST('item_attributes'),
        p_prefixes     => SYS.ODCIVARCHAR2LIST('item_attribute')
    );
END;
/

PROMPT
PROMPT === JSON projection materialized views created ===

SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN (
           'BOM_COMPONENTS_MV',
           'BOM_COMPONENT_REVISIONS_MV',
           'BOM_COMPONENT_VARIANTS_MV',
           'BOM_HEADERS_MV',
           'BOM_ITEMS_MV'
       )
ORDER  BY object_type, object_name;

PROMPT
PROMPT === Generated first-level JSON projection materialized view columns ===

SELECT table_name, column_name, data_type
FROM   user_tab_columns
WHERE  table_name IN (
           'BOM_COMPONENTS_MV',
           'BOM_COMPONENT_REVISIONS_MV',
           'BOM_COMPONENT_VARIANTS_MV',
           'BOM_HEADERS_MV',
           'BOM_ITEMS_MV'
       )
ORDER  BY table_name, column_id;

