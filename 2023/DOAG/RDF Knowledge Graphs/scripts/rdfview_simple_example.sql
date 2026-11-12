-- Clean up

-- Drop the schema-private RDF View model
BEGIN
  sem_apis.drop_rdfview_model(
    model_name => 'EMPDB_RDFVIEW_MODEL',
    network_owner => 'RDFUSER',
    network_name => 'RDF_NETWORK'
  );
END;
/

-- Drop the tables
DROP TABLE emp PURGE;
DROP TABLE dept PURGE;

-- Create tables
create table dept(
  deptno     number(2,0),
  dname      varchar2(14),
  loc        varchar2(13),
  constraint pk_dept primary key (deptno)
);

create table emp(
  empno    number(4,0),
  ename    varchar2(10),
  job      varchar2(50),
  mgr      number(4,0),
  hiredate date,
  sal      number(7,2),
  comm     number(7,2),
  deptno   number(2,0),
  constraint pk_emp primary key (empno),
  constraint fk_deptno foreign key (deptno) references dept (deptno)
);

-- Populate with data
insert into dept (DEPTNO, DNAME, LOC) values (10, 'ACCOUNTING', 'NEW YORK');
insert into dept (DEPTNO, DNAME, LOC) values (20, 'RESEARCH', 'DALLAS');
insert into dept (DEPTNO, DNAME, LOC) values (30, 'SALES', 'CHICAGO');
insert into dept (DEPTNO, DNAME, LOC) values (40, 'OPERATIONS', 'BOSTON');

insert into emp
values (
 7839, 'KING', 'PRESIDENT', null,
 to_date('17-11-1981','dd-mm-yyyy'),
 5000, null, 10
);

insert into emp
values (
 7698, 'BLAKE', 'MANAGER', 7839,
 to_date('1-5-1981','dd-mm-yyyy'),
 2850, null, 30
);

insert into emp
values (
 7782, 'CLARK', 'MANAGER', 7839,
 to_date('9-6-1981','dd-mm-yyyy'),
 2450, null, 10
);

insert into emp
values (
 7566, 'JONES', 'MANAGER', 7839,
 to_date('2-4-1981','dd-mm-yyyy'),
 2975, null, 20
);

insert into emp
values (
 7788, 'SCOTT', 'ANALYST', 7566,
 to_date('13-JUL-87','dd-mm-rr') - 85,
 3000, null, 20
);

insert into emp
values (
 7902, 'FORD', 'ANALYST', 7566,
 to_date('3-12-1981','dd-mm-yyyy'),
 3000, null, 20
);

insert into emp
values (
 7369, 'SMITH', 'CLERK', 7902,
 to_date('17-12-1980','dd-mm-yyyy'),
 800, null, 20
);

insert into emp
values (
 7499, 'ALLEN', 'SALESMAN', 7698,
 to_date('20-2-1981','dd-mm-yyyy'),
 1600, 300, 30
);

insert into emp
values (
 7521, 'WARD', 'SALESMAN', 7698,
 to_date('22-2-1981','dd-mm-yyyy'),
 1250, 500, 30
);

insert into emp
values (
 7654, 'MARTIN', 'SALESMAN', 7698,
 to_date('28-9-1981','dd-mm-yyyy'),
 1250, 1400, 30
);

insert into emp
values (
 7844, 'TURNER', 'SALESMAN', 7698,
 to_date('8-9-1981','dd-mm-yyyy'),
 1500, 0, 30
);

insert into emp
values (
 7876, 'ADAMS', 'CLERK', 7788,
 to_date('13-JUL-87', 'dd-mm-rr') - 51,
 1100, null, 20
);

insert into emp
values (
 7900, 'JAMES', 'CLERK', 7698,
 to_date('3-12-1981','dd-mm-yyyy'),
 950, null, 30
);

insert into emp
values (
 7934, 'MILLER', 'CLERK', 7782,
 to_date('23-1-1982','dd-mm-yyyy'),
 1300, null, 10
);

insert into emp
values (
 7950, 'STONE', 'SALESWOMAN', 7782,
 to_date('1-1-1989','dd-mm-yyyy'),
 1500, null, 40
);

commit;


-- Verify data
  select ename, dname, job, empno, hiredate, loc
    from emp, dept
   where emp.deptno = dept.deptno
order by ename;


-- Create the RDF View model
BEGIN
  sem_apis.create_rdfview_model(
    model_name => 'EMPDB_RDFVIEW_MODEL',
    tables => SYS.ODCIVarchar2List('EMP', 'DEPT'),
    prefix => 'http://empdb/',
    -- options => 'KEY_BASED_REF_PROPERTY=T',
    options => 'KEY_BASED_REF_PROPERTY=T CONFORMANCE=T',
    network_owner => 'RDFUSER',
    network_name => 'RDF_NETWORK'
  );
END;
/

-- Show the list of predicates used
SELECT DISTINCT p
  FROM TABLE(SEM_MATCH(
    '{?s ?p ?o}',              -- query
    SEM_Models('empdb_rdfview_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('dept','http://empdb/DEPT#'),
      SEM_ALIAS('emp','http://empdb/EMP#')),            -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ))
ORDER BY p;

-- List all employees that work for departments located in Chicago
SELECT emp
  FROM TABLE(SEM_MATCH(
    '{?emp emp:ref-DEPTNO ?dept . ?dept dept:LOC "CHICAGO"}',     -- query
    SEM_Models('empdb_rdfview_model'), -- models
    NULL,                      -- rulebases
    SEM_ALIASES(
      SEM_ALIAS('dept','http://empdb/DEPT#'),
      SEM_ALIAS('emp','http://empdb/EMP#')),                      -- aliases
    -- NULL,                      -- aliases
    NULL,                      -- filter
    null,                      -- index status
    null,                      -- options
    null,                      -- graphs
    null,                      -- named graphs
    'RDFUSER',                 -- network owner
    'RDF_NETWORK'              -- network name
    ));


-- The preceding query is functionally comparable to this:
SELECT e.empno
  FROM emp e, dept d
 WHERE e.deptno = d.deptno
   AND d.loc = 'CHICAGO';