-------------------------------------------------
-- Create RDF View on relational data using R2RML
-------------------------------------------------

-- Drop the schema-private RDF View model
BEGIN
  sem_apis.drop_rdfview_model(
    model_name => 'EMPDB_R2RML_MODEL',
    network_owner => 'RDFUSER',
    network_name => 'RDF_NETWORK'
  );
END;
/

-- Show table definitions for relational data source
DESC emp;
DESC dept;

-- Show table contents for relational data source
SELECT * FROM emp;
SELECT * FROM dept;

-- Create a schema-private model using R2RML mapping
-- Note:
--   RDF Views can now be created directly from R2RML mappings 
--   specified in Turtle or N-Triple format.
DECLARE
  r2rmlStr CLOB;

BEGIN

  r2rmlStr :=
   '@prefix rr: <http://www.w3.org/ns/r2rml#>. '||
   '@prefix xsd: <http://www.w3.org/2001/XMLSchema#>. '||
   '@prefix ex: <http://example.com/ns#>. '||'

    ex:TriplesMap_Dept
        rr:logicalTable [ rr:tableName "DEPT" ];
        rr:subjectMap [
            rr:template "http://empdb/department#{DEPTNO}";
            rr:class ex:Department;
        ];
        rr:predicateObjectMap [
            rr:predicate ex:deptNum;
            rr:objectMap [ rr:column "DEPTNO" ; rr:datatype xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:deptName;
            rr:objectMap [ rr:column "DNAME" ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:deptLocation;
            rr:objectMap [ rr:column "LOC" ];
        ].'||'

    ex:TriplesMap_Emp
        rr:logicalTable [ rr:tableName "EMP" ];
        rr:subjectMap [
            rr:template "http://empdb/employee#{EMPNO}";
            rr:class ex:Employee;
        ];
        rr:predicateObjectMap [
            rr:predicate ex:empNum;
            rr:objectMap [ rr:column "EMPNO" ; rr:datatype xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:empName;
            rr:objectMap [ rr:column "ENAME" ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:jobType;
            rr:objectMap [ rr:column "JOB" ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:hireDate;
            rr:objectMap [ rr:column "HIREDATE" ; rr:dataType xsd:date ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:salary;
            rr:objectMap [ rr:column "SAL" ; rr:dataType xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:commission;
            rr:objectMap [ rr:column "COMM" ; rr:dataType xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:managedByEmpNum;
            rr:objectMap [ rr:column "MGR" ; rr:dataType xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:worksForDeptNum;
            rr:objectMap [ rr:column "DEPTNO" ; rr:dataType xsd:integer ];
        ];
        rr:predicateObjectMap [
            rr:predicate ex:managedByEmp;
            rr:objectMap [
              rr:parentTriplesMap ex:TriplesMap_Emp ;
              rr:joinCondition [ rr:child "MGR"; rr:parent "EMPNO" ]]
        ];
        rr:predicateObjectMap [
            rr:predicate ex:worksForDept;
            rr:objectMap [
              rr:parentTriplesMap ex:TriplesMap_Dept ;
              rr:joinCondition [ rr:child "DEPTNO"; rr:parent "DEPTNO" ]]].';

  sem_apis.create_rdfview_model(
    model_name => 'EMPDB_R2RML_MODEL',
    tables => NULL,
    r2rml_string => r2rmlStr,
    r2rml_string_fmt => 'TURTLE',
    network_owner => 'RDFUSER',
    network_name => 'RDF_NETWORK'
  );

END;
/

SELECT DISTINCT s, p, o
  FROM TABLE(SEM_MATCH(
    '{?s ?p ?o}',                -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                        -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));

-- Employees and their locations
SELECT emp, dept, loc
  FROM TABLE(SEM_MATCH(
    '{?emp ex:worksForDept ?dept . ?dept ex:deptLocation ?loc}',              -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));

-- Employees in Chicago
SELECT emp, dept
  FROM TABLE(SEM_MATCH(
    '{?emp ex:worksForDept ?dept . ?dept ex:deptLocation "CHICAGO" }',              -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));

-- Employees and their salaries
SELECT emp as ename, o AS salary
  FROM TABLE(SEM_MATCH(
    '{?emp ex:salary ?o}',              -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));

-- Show predicates and objects for employee 7782 
SELECT DISTINCT p, o
  FROM TABLE(SEM_MATCH(
    '{emp:7782 ?p ?o}',              -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));


-- Employees and their managers
SELECT ename, mname
  FROM TABLE(SEM_MATCH(
    '{?emp ex:managedByEmp ?mgr . ?emp ex:empName ?ename . ?mgro ex:empName ?mname }',              -- query
    SEM_Models('empdb_r2rml_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ))
ORDER BY ename, mname;

-- Show manager of employee 7782
SELECT mname
  FROM TABLE(SEM_MATCH(
    '{emp:7782 ex:managedByEmp ?mgr . ?mgr ex:empName ?mname }',  -- query
    SEM_Models('empdb_r2rml_model'),                              -- models
    NULL,                                                         -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('ex','http://example.com/ns#'),
      SEM_ALIAS('dept','http://empdb/department#'),
      SEM_ALIAS('emp','http://empdb/employee#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));
