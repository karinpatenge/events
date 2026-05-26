--==============================================================================
--  01_create_schema.sql
--  Bill of Materials (BOM) demo schema for Oracle AI Database 26ai
--  Industry: Automotive  -  Mix of ICE + EV passenger vehicles
--
--  Targets:
--    * 7,000  components (with several revisions each)
--    * 15,000 component variants
--    * 1,000  BOM headers
--    * Hierarchical BOM items up to 7 levels deep
--
--  Conventions:
--    * Surrogate keys: NUMBER GENERATED ALWAYS AS IDENTITY
--    * Native JSON data type (Oracle 23ai+) for semi-structured payloads
--    * DROP TABLE IF EXISTS (Oracle 23ai+) for idempotent re-runs
--    * Run as a schema-owning user (e.g. BOM_DEMO) with CREATE TABLE privilege
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

PROMPT
PROMPT === Dropping existing BOM demo tables (if any) ===

-- Drop in reverse dependency order. CASCADE CONSTRAINTS releases any
-- inbound FKs so the order is forgiving on re-runs.
DROP TABLE IF EXISTS bom_items                 CASCADE CONSTRAINTS PURGE;
DROP TABLE IF EXISTS bom_headers               CASCADE CONSTRAINTS PURGE;
DROP TABLE IF EXISTS bom_component_variants    CASCADE CONSTRAINTS PURGE;
DROP TABLE IF EXISTS bom_component_revisions   CASCADE CONSTRAINTS PURGE;
DROP TABLE IF EXISTS bom_components            CASCADE CONSTRAINTS PURGE;
DROP TABLE IF EXISTS bom_categories            CASCADE CONSTRAINTS PURGE;

PROMPT
PROMPT === Creating BOM_CATEGORIES ===
--==============================================================================
-- BOM_CATEGORIES
--   Lookup table of component categories spanning ICE, EV, HYBRID and common
--   automotive subsystems.
--==============================================================================
CREATE TABLE bom_categories (
    category_id       NUMBER GENERATED ALWAYS AS IDENTITY,
    category_code     VARCHAR2(20)  NOT NULL,
    category_name     VARCHAR2(100) NOT NULL,
    powertrain_type   VARCHAR2(20)  NOT NULL,
    description       VARCHAR2(500),
    CONSTRAINT pk_bom_categories       PRIMARY KEY (category_id),
    CONSTRAINT uk_bom_categories_code  UNIQUE      (category_code),
    CONSTRAINT ck_bom_categories_ptype CHECK (powertrain_type IN ('ICE','EV','HYBRID','COMMON'))
);

PROMPT
PROMPT === Creating BOM_COMPONENTS ===
--==============================================================================
-- BOM_COMPONENTS
--   Master catalog of automotive components (~7,000 rows).
--   Combines relational attributes with two JSON payloads:
--      specifications - engineering attributes that vary by category
--      compliance     - regulatory / homologation metadata
--==============================================================================
CREATE TABLE bom_components (
    component_id      NUMBER GENERATED ALWAYS AS IDENTITY,
    part_number       VARCHAR2(50)  NOT NULL,
    component_name    VARCHAR2(200) NOT NULL,
    category_id       NUMBER        NOT NULL,
    powertrain_type   VARCHAR2(20)  NOT NULL,
    unit_of_measure   VARCHAR2(20)  DEFAULT 'EA',
    standard_cost     NUMBER(12,4),
    weight_kg         NUMBER(10,3),
    lifecycle_status  VARCHAR2(20)  DEFAULT 'ACTIVE',
    created_date      DATE          DEFAULT SYSDATE,
    specifications    JSON,
    compliance        JSON,
    CONSTRAINT pk_bom_components        PRIMARY KEY (component_id),
    CONSTRAINT uk_bom_components_pn     UNIQUE      (part_number),
    CONSTRAINT fk_bom_components_cat    FOREIGN KEY (category_id)
        REFERENCES bom_categories (category_id),
    CONSTRAINT ck_bom_components_ptype  CHECK (powertrain_type IN ('ICE','EV','HYBRID','COMMON')),
    CONSTRAINT ck_bom_components_status CHECK (lifecycle_status IN ('ACTIVE','PROTOTYPE','PHASE_OUT','OBSOLETE'))
);

CREATE INDEX ix_bom_components_cat   ON bom_components (category_id);
CREATE INDEX ix_bom_components_ptype ON bom_components (powertrain_type);

PROMPT
PROMPT === Creating BOM_COMPONENT_REVISIONS ===
--==============================================================================
-- BOM_COMPONENT_REVISIONS
--   Engineering change revisions per component. Each component typically has
--   1-4 revisions (A,B,C,D...). The latest is RELEASED, older ones SUPERSEDED.
--==============================================================================
CREATE TABLE bom_component_revisions (
    revision_id       NUMBER GENERATED ALWAYS AS IDENTITY,
    component_id      NUMBER        NOT NULL,
    revision_code     VARCHAR2(10)  NOT NULL,
    revision_date     DATE          NOT NULL,
    eco_number        VARCHAR2(30),
    engineer_name     VARCHAR2(100),
    change_summary    VARCHAR2(1000),
    revision_status   VARCHAR2(20)  DEFAULT 'RELEASED',
    specifications    JSON,
    CONSTRAINT pk_bom_revisions        PRIMARY KEY (revision_id),
    CONSTRAINT uk_bom_revisions        UNIQUE      (component_id, revision_code),
    CONSTRAINT fk_bom_revisions_comp   FOREIGN KEY (component_id)
        REFERENCES bom_components (component_id),
    CONSTRAINT ck_bom_revisions_status CHECK (revision_status IN ('DRAFT','IN_REVIEW','RELEASED','SUPERSEDED','OBSOLETE'))
);

CREATE INDEX ix_bom_revisions_comp ON bom_component_revisions (component_id);

PROMPT
PROMPT === Creating BOM_COMPONENT_VARIANTS ===
--==============================================================================
-- BOM_COMPONENT_VARIANTS
--   Region / trim-level variants of a component (~15,000 rows).
--   variant_attributes JSON holds the differentiating attributes
--   (color, language pack, voltage, software build, etc.)
--==============================================================================
CREATE TABLE bom_component_variants (
    variant_id        NUMBER GENERATED ALWAYS AS IDENTITY,
    component_id      NUMBER        NOT NULL,
    variant_code      VARCHAR2(50)  NOT NULL,
    variant_name      VARCHAR2(200) NOT NULL,
    region_code       VARCHAR2(10),
    market_segment    VARCHAR2(50),
    cost_adjustment   NUMBER(10,4)  DEFAULT 0,
    variant_status    VARCHAR2(20)  DEFAULT 'ACTIVE',
    variant_attributes JSON,
    CONSTRAINT pk_bom_variants        PRIMARY KEY (variant_id),
    CONSTRAINT uk_bom_variants        UNIQUE      (component_id, variant_code),
    CONSTRAINT fk_bom_variants_comp   FOREIGN KEY (component_id)
        REFERENCES bom_components (component_id),
    CONSTRAINT ck_bom_variants_status CHECK (variant_status IN ('ACTIVE','PILOT','OBSOLETE'))
);

CREATE INDEX ix_bom_variants_comp ON bom_component_variants (component_id);

PROMPT
PROMPT === Creating BOM_HEADERS ===
--==============================================================================
-- BOM_HEADERS
--   ~1,000 vehicle BOM headers. Each header points at a top-level assembly
--   (top_component_id) and carries vehicle / plant / market metadata as JSON.
--==============================================================================
CREATE TABLE bom_headers (
    bom_id            NUMBER GENERATED ALWAYS AS IDENTITY,
    bom_code          VARCHAR2(50)  NOT NULL,
    bom_name          VARCHAR2(200) NOT NULL,
    vehicle_model     VARCHAR2(100),
    model_year        NUMBER(4),
    trim_level        VARCHAR2(50),
    powertrain_type   VARCHAR2(20)  NOT NULL,
    plant_code        VARCHAR2(20),
    top_component_id  NUMBER,
    effective_date    DATE,
    expiration_date   DATE,
    bom_status        VARCHAR2(20)  DEFAULT 'RELEASED',
    bom_metadata      JSON,
    CONSTRAINT pk_bom_headers        PRIMARY KEY (bom_id),
    CONSTRAINT uk_bom_headers_code   UNIQUE      (bom_code),
    CONSTRAINT fk_bom_headers_top    FOREIGN KEY (top_component_id)
        REFERENCES bom_components (component_id),
    CONSTRAINT ck_bom_headers_ptype  CHECK (powertrain_type IN ('ICE','EV','HYBRID')),
    CONSTRAINT ck_bom_headers_status CHECK (bom_status IN ('DRAFT','RELEASED','SUPERSEDED','OBSOLETE'))
);

CREATE INDEX ix_bom_headers_model ON bom_headers (vehicle_model, model_year);
CREATE INDEX ix_bom_headers_ptype ON bom_headers (powertrain_type);

PROMPT
PROMPT === Creating BOM_ITEMS ===
--==============================================================================
-- BOM_ITEMS
--   The hierarchical BOM line items, up to 7 levels deep.
--   Self-referencing FK (parent_item_id) builds the indented BOM tree.
--   References the chosen revision and (optionally) variant of the component.
--==============================================================================
CREATE TABLE bom_items (
    bom_item_id          NUMBER GENERATED ALWAYS AS IDENTITY,
    bom_id               NUMBER        NOT NULL,
    parent_item_id       NUMBER,
    component_id         NUMBER        NOT NULL,
    revision_id          NUMBER,
    variant_id           NUMBER,
    level_num            NUMBER(2)     NOT NULL,
    sequence_num         NUMBER(6)     NOT NULL,
    find_number          VARCHAR2(20),
    quantity             NUMBER(12,4)  DEFAULT 1,
    reference_designator VARCHAR2(200),
    item_attributes      JSON,
    CONSTRAINT pk_bom_items         PRIMARY KEY (bom_item_id),
    CONSTRAINT fk_bom_items_bom     FOREIGN KEY (bom_id)
        REFERENCES bom_headers (bom_id),
    CONSTRAINT fk_bom_items_parent  FOREIGN KEY (parent_item_id)
        REFERENCES bom_items (bom_item_id),
    CONSTRAINT fk_bom_items_comp    FOREIGN KEY (component_id)
        REFERENCES bom_components (component_id),
    CONSTRAINT fk_bom_items_rev     FOREIGN KEY (revision_id)
        REFERENCES bom_component_revisions (revision_id),
    CONSTRAINT fk_bom_items_var     FOREIGN KEY (variant_id)
        REFERENCES bom_component_variants (variant_id),
    CONSTRAINT ck_bom_items_level   CHECK (level_num BETWEEN 1 AND 7)
);

CREATE INDEX ix_bom_items_bom    ON bom_items (bom_id);
CREATE INDEX ix_bom_items_parent ON bom_items (parent_item_id);
CREATE INDEX ix_bom_items_comp   ON bom_items (component_id);
CREATE INDEX ix_bom_items_level  ON bom_items (bom_id, level_num);

PROMPT
PROMPT === Table comments ===
COMMENT ON TABLE bom_categories             IS 'Component category lookup (engine, battery, chassis, ...).';
COMMENT ON TABLE bom_components             IS 'Master automotive component catalog (~7k rows). Specs and compliance stored as JSON.';
COMMENT ON TABLE bom_component_revisions    IS 'Engineering change revisions per component.';
COMMENT ON TABLE bom_component_variants     IS 'Region / market variants of a component (~15k rows).';
COMMENT ON TABLE bom_headers                IS 'Vehicle Bill-of-Materials headers (~1k rows).';
COMMENT ON TABLE bom_items                  IS 'Hierarchical BOM line items, up to 7 levels deep.';

COMMENT ON COLUMN bom_components.specifications IS 'JSON: engineering specifications (varies by category).';
COMMENT ON COLUMN bom_components.compliance     IS 'JSON: regulatory / homologation metadata (RoHS, REACH, ASIL, country of origin, ...).';
COMMENT ON COLUMN bom_headers.bom_metadata      IS 'JSON: vehicle program metadata (markets, target volume, emissions target, ...).';
COMMENT ON COLUMN bom_items.item_attributes     IS 'JSON: BOM-line specific data (installation method, torque, criticality, ...).';
COMMENT ON COLUMN bom_component_variants.variant_attributes IS 'JSON: differentiating attributes for this variant.';
COMMENT ON COLUMN bom_component_revisions.specifications    IS 'JSON: spec delta captured with this revision.';

COMMIT;

PROMPT
PROMPT === Schema objects created ===
SELECT object_name, object_type
FROM   user_objects
WHERE  object_name LIKE 'BOM_%'
ORDER  BY object_type, object_name;
