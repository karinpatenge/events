-----------------------------------------------------------------
-- Prerequisites:
-----------------------------------------------------------------

-- Connect as user with SYSDBA privileges

-- Re-create tablespace
drop tablespace rdf_tbs including contents and datafiles cascade constraints;

create tablespace rdf_tbs
datafile 'rdf_tbs.dat' size 1024m reuse
autoextend on next 256m maxsize unlimited
segment space management auto;

select * from dba_tablespaces order by tablespace_name;

-- Re-create user
drop user rdfuser cascade;

-- Replace the placeholder with a proper pwd
create user rdfuser identified by <pwd> default tablespace rdf_tbs temporary tablespace temp;
grant resource, connect, create view to rdfuser;
alter user rdfuser quota unlimited on rdf_tbs;

---------------------
-- Start from scratch
---------------------

-- Connect as user RDFUSER (or adapt script to your DB user)

-- Re-create schema-private semantic network
BEGIN
    SEM_APIS.DROP_SEM_NETWORK(
        cascade => true
-- TRUE drops any existing semantic technology models and rulebases, and removes structures
-- used for persistent storage of semantic data; FALSE (the default) causes the operation to fail
-- if any semantic technology models or rulebases exist.
        , network_owner => 'RDFUSER'
        , network_name => 'RDF_NETWORK');
END;
/

BEGIN
    SEM_APIS.CREATE_SEM_NETWORK(
        tablespace_name => 'RDF_TBS'
        , network_owner => 'RDFUSER'
        , network_name => 'RDF_NETWORK');
END;
/

-- Re-create triple table
DROP TABLE family_tpl PURGE;
CREATE TABLE family_tpl (triple SDO_RDF_TRIPLE_S) COMPRESS;

-- Re-create semantic model
BEGIN
    SEM_APIS.DROP_SEM_MODEL(
        model_name => 'FAMILY'
        , network_owner => 'RDFUSER'
        , network_name => 'RDF_NETWORK');
END;
/

BEGIN
    SEM_APIS.CREATE_SEM_MODEL(
        model_name => 'FAMILY'
        , table_name => 'FAMILY_TPL'
        , column_name => 'TRIPLE'
        , network_owner => 'RDFUSER'
        , network_name => 'RDF_NETWORK');
END;
/

-- Load RDF triples using SEM_APIS.UPDATE_MODEL
BEGIN
    -- Insert some TBox (schema) information.
    SEM_APIS.UPDATE_MODEL(
        'family'
        ,  'PREFIX    rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX   rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX family: <http://www.example.org/family/>
            INSERT DATA {
                # Person is a class
                family:Person rdf:type rdfs:Class .

                # Male is a subclass of Person
                family:Male rdfs:subClassOf family:Person .

                # Female is a subclass of Person
                family:Female rdfs:subClassOf family:Person .

                # siblingOf is a property
                family:siblingOf rdf:type rdf:Property .

                # parentOf is a property
                family:parentOf rdf:type rdf:Property .

                # brotherOf is a subproperty of siblingOf
                family:brotherOf rdfs:subPropertyOf family:siblingOf .

                # sisterOf is a subproperty of siblingOf
                family:sisterOf rdfs:subPropertyOf family:siblingOf .

                # A brother is male
                family:brotherOf rdfs:domain family:Male .

                # A sister is female
                family:sisterOf rdfs:domain family:Female .

                # fatherOf is a subproperty of parentOf
                family:fatherOf rdfs:subPropertyOf family:parentOf .

                # motherOf is a subproperty of parentOf
                family:motherOf rdfs:subPropertyOf family:parentOf .

                # A father is male
                family:fatherOf rdfs:domain family:Male .

                # A mother is female
                family:motherOf rdfs:domain family:Female .
            }'
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );

    -- Insert some ABox (instance) information.
    SEM_APIS.UPDATE_MODEL(
        'family'
        , 'PREFIX    rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
           PREFIX   rdfs: <http://www.w3.org/2000/01/rdf-schema#>
           PREFIX family: <http://www.example.org/family/>
           INSERT DATA {
                # John is the father of Suzie and Matt
                family:John family:fatherOf family:Suzie .
                family:John family:fatherOf family:Matt .

                # Janice is the mother of Suzie and Matt
                family:Janice family:motherOf family:Suzie .
                family:Janice family:motherOf family:Matt .

                # Sammy is the father of Cathy and Jack
                family:Sammy family:fatherOf family:Cathy .
                family:Sammy family:fatherOf family:Jack .

                # Suzie is the mother of Cathy and Jack
                family:Suzie family:motherOf family:Cathy .
                family:Suzie family:motherOf family:Jack .

                # Matt is the father of Tom and Cindy
                family:Matt family:fatherOf family:Tom .
                family:Matt family:fatherOf family:Cindy .

                # Martha is the mother of Tom and Cindy
                family:Martha family:motherOf family:Tom .
                family:Martha family:motherOf family:Cindy .

                # Cathy is the sister of Jack
                family:Cathy family:sisterOf family:Jack .

                # Jack is male
                family:Jack rdf:type family:Male .

                # Tom is male
                family:Tom rdf:type family:Male .

                # Cindy is female
                family:Cindy rdf:type family:Female .
            }'
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );
END;
/

-- Note: Use SQL Developer for the following queries

-- Show all existing family triples (S-P-O relations)
SELECT
    s$rdfterm s
    , p$rdfterm p
    , o$rdfterm o
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            SELECT ?s ?p ?o
            WHERE { ?s ?p ?o }
            ORDER BY ?p ?s ?o'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , 'PLUS_RDFT=VC'
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Count all existing S-P-O relations (triples)
SELECT
    *
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            SELECT (COUNT(*) as ?num_triples) 
            WHERE { ?s ?p ?o }'
                , SEM_Models('family')
                , null
                , null
                , null
                , null
                , ' PLUS_RDFT=VC '
                , null
                , null
                , 'RDFUSER'
                , 'RDF_NETWORK'
        )
    );

-- Count all distinct S-P-O relations
SELECT
    *
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            SELECT (COUNT(DISTINCT ?s) as ?num_subjects) (COUNT(DISTINCT ?p) as ?num_predicates)  (COUNT(DISTINCT ?o) as ?num_objects)
            WHERE { ?s ?p ?o }'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Count all distinct classes
SELECT
    *
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            SELECT (COUNT(distinct ?class) AS ?num_classes)
            WHERE { ?s a ?class }'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );


-- Show all classes
SELECT
    class$rdfterm class
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            SELECT distinct ?class
            WHERE { ?s a ?class }'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Infer new data (create entailment) for the semantic model using RDFS and OWLPRIME rulebases
BEGIN
    SEM_APIS.CREATE_ENTAILMENT(
        'family_rb_rix'
        , SEM_Models('family')
        , SEM_Rulebases('RDFS','OWLPRIME')
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );
END;
/

-- Select all males from the family model, without inferred data (entailment).
-- Result set contains only Jack and Tom.
SELECT
    m$rdfterm
FROM
    TABLE (
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX     : <http://www.example.org/family/>
            SELECT ?m
            WHERE {?m rdf:type :Male}'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Is there a father of Cindy
SELECT
    *
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX  owl: <http://www.w3.org/2002/07/owl#>
            PREFIX     : <http://www.example.org/family/>

            ASK  { ?x :fatherOf  :Cindy }'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );


-- Select all males from the family model, now using the entailment.
-- Result set contains Jack, Tom, John, Sammy, and Matt.
SELECT
    m$rdfterm
FROM
    TABLE (
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX     : <http://www.example.org/family/>
            SELECT ?m
            WHERE {?m rdf:type :Male}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME')
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Create custom rulebase for the semantic model
BEGIN
    SEM_APIS.DROP_RULEBASE('family_rb');
END;
/

BEGIN
    SEM_APIS.CREATE_RULEBASE(
        'family_rb'
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );
END;
/

-- Insert grandparent rule
INSERT INTO
    rdfuser.rdf_network#semr_family_rb
VALUES (
    'grandparent_rule'
    , '(?x :parentOf ?y) (?y :parentOf ?z)'
    , NULL
    , '(?x :grandParentOf ?z)'
    , SEM_ALIASES (
        SEM_ALIAS (
            ''
            , 'http://www.example.org/family/'
        )
    )
);
COMMIT;

-- Re-create the entailment to include the custom rulesbase
BEGIN
    SEM_APIS.DROP_ENTAILMENT (
        index_name_in => 'family_rb_rix'
        , network_owner => 'RDFUSER'
        , network_name => 'RDF_NETWORK'
    );
END;
/

BEGIN
    SEM_APIS.CREATE_ENTAILMENT (
        'family_rb_rix'
        , SEM_Models('family')
        , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );
END;
/

-- Select all grandfathers and their grandchildren from the family model, without entailment
-- No rows returned
SELECT
    x$rdfterm grandfather
    , y$rdfterm grandchild
FROM
    TABLE(
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX     : <http://www.example.org/family/>
            SELECT ?x ?y
            WHERE  {?x :grandParentOf ?y . ?x rdf:type :Male}'
            , SEM_Models('family')
            , null
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );


-- Select all grandfathers and their grandchildren from the family model, with entailment.
-- Result contains:
--   John as grandfather and Cindy, Jack, Cathy, and Tom as grandchildren
SELECT
    x$rdfterm grandfather
    , y$rdfterm grandchild
FROM
    TABLE (
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX     : <http://www.example.org/family/>
            SELECT ?x ?y
            WHERE {?x :grandParentOf ?y . ?x rdf:type :Male}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , null
            , null
            , null
            , ' PLUS_RDFT=VC '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Same query. Add HINT0 Option with SEM_MATCH Table Function.
SELECT
    x$rdfterm grandfather
    , y$rdfterm grandchild
FROM
    TABLE (
        SEM_MATCH (
            'PREFIX  rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
            PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
            PREFIX     : <http://www.example.org/family/>
            SELECT ?x ?y
            WHERE {?x :grandParentOf ?y . ?x rdf:type :Male}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , null
            , null
            , null
            , ' PLUS_RDFT=VC HINT0={LEADING(t0 t1) USE_NL(?x ?y)}'
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Use the syntax with curly braces and a period to express a graph pattern in the SEM_MATCH table function.
SELECT
    x, y
FROM
    TABLE (
        SEM_MATCH (
            '{?x :grandParentOf ?y . ?x rdf:type :Male}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , SEM_ALIASES(SEM_ALIAS('','http://www.example.org/family/'))
            , null
            , null
            , ''
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

-- Use the OPTIONAL construct to modify previous example, so that it also returns, for each grandfather, 
-- the names of the games that he plays or null if he does not play any games.
SELECT
    x, y, game
FROM
    TABLE (
        SEM_MATCH (
            '{?x :grandParentOf ?y . ?x rdf:type :Male . OPTIONAL{?x :plays ?game}}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , SEM_ALIASES(SEM_ALIAS('','http://www.example.org/family/'))
            , null
            , null
            , 'HINT0={LEADING(t0 t1) USE_NL(?x ?y)}'
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

--
-- Full-text search
--

-- Requires EXECUTE permission on CTXSYS.CTX_DDL to be granted (run as SYSTEM or SYS)
GRANT EXECUTE ON CTXSYS.CTX_DDL TO rdfuser;

-- The Oracle-specific orardf:textContains SPARQL FILTER function uses full-textindexes on the RDF_VALUE$ table.
-- Before using orardf:textContains, you must create an Oracle Text index for the RDF network.

EXECUTE SEM_APIS.ADD_DATATYPE_INDEX('http://xmlns.oracle.com/rdf/text', network_owner=>'RDFUSER', network_name=>'RDF_NETWORK');
EXECUTE SEM_APIS.ADD_DATATYPE_INDEX('http://xmlns.oracle.com/rdf/like', network_owner=>'RDFUSER', network_name=>'RDF_NETWORK');

SELECT
    x, y, n
FROM
    TABLE(
        SEM_MATCH(
           '{ ?x :grandParentOf ?y . ?x rdf:type :Male . ?x :name ?n
            FILTER (orardf:textContains(?n, " A% | B% "))}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , SEM_ALIASES(SEM_ALIAS('','http://www.example.org/family/'))
            , null
        )
    );


-- Example 1.78:
-- Use orardf:textContains to find allgrandfathers whose names start with the letter A or B.
SELECT
    x, y, n
FROM
    TABLE(
        SEM_MATCH(
            'PREFIX : <http://www.example.org/family/>
            SELECT *
            WHERE
                {?x :grandParentOf ?y . ?x rdf:type :Male . ?x :name ?n
                    FILTER (orardf:textContains(?n, " A% | B% "))}'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , null
            , null
            , null
            , ' '
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );


SELECT
    x, y, n, scr
FROM
    TABLE(
        SEM_MATCH(
           'PREFIX <http://www.example.org/family/>
            SELECT *
            WHERE {
                {
                    SELECT
                        ?x ?y ?n (orardf:textScore(123)AS ?scr)
                    WHERE {
                       ?x :grandParentOf ?y . ?x rdf:type :Male . ?x :name ?n
                       FILTER (orardf:textContains(?n, " A% | B% ", 123))
                    }
                }
                FILTER (?scr > 0.5)
            }'
            , SEM_Models('family')
            , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
            , null
            , null
            , null
            , ' REWRITE=F'
            , null
            , null
            , 'RDFUSER'
            , 'RDF_NETWORK'
        )
    );

SELECT x, y, n
FROM TABLE(
    SEM_MATCH(
        'PREFIX : <http://www.example.org/family/>
        SELECT *
        WHERE {
            ?x :grandParentOf ?y . ?y :name ?n
                FILTER (orardf:like(?x, "Ja%")) }'
        , SEM_Models('family')
        , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
        , null
        , null
        , null
        , ' '
        , null
        , null
        , 'RDFUSER'
        , 'RDF_NETWORK'
    )
);

SELECT x, y, n
FROM TABLE(
    SEM_MATCH(
        'PREFIX : <http://www.example.org/family/>
        SELECT *
        WHERE {
            ?x :grandParentOf ?y . ?y :name ?n
                FILTER (orardf:like(?n, "J__k"))}'
        , SEM_Models('family')
        , SEM_Rulebases('RDFS','OWLPRIME','family_rb')
        , null
        , null
        , null
        , ' '
        , null
        , null
        , 'RDFUSER'
        , 'RDF_NETWORK'
    )
);





-------------
-- Namespaces
-------------
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX ex: <http://www.example.org/family/>

