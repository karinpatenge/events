drop table if exists works_for cascade constraints;
drop table if exists speaks_at cascade constraints;
drop table if exists knows cascade constraints;
drop table if exists persons cascade constraints;
drop table if exists events cascade constraints;
drop table if exists companies cascade constraints;

create table if not exists persons (
  id number generated always as identity
    constraint persons_pk primary key,
  name varchar2(100)
);

insert into persons ( name ) values
 ( 'Carsten' ),
 ( 'Martin' ),
 ( 'Julian' ),
 ( 'Chris' ),
 ( 'Sebastian' ),
 ( 'Karin' ),
 ( 'Mirela' ),
 ( 'Johannes' ),
 ( 'Peter' ),
 ( 'Stefan' );

commit;

create table if not exists companies (
  id number generated always as identity
    constraint companies_pk primary key,
  name varchar2(100)
);

insert into companies ( name ) values ( 'Oracle');

commit;

create table if not exists events (
  id number generated always as identity
    constraint events_pk primary key,
  name varchar2(100),
  location varchar2(100),
  start_date date,
  end_date date,
  duration number generated always as ( end_date - start_date + 1) virtual
);

insert into events ( name, location, start_date, end_date )
values
  ( 'TDWI 2025', 'München', to_date('24-06-2025','dd-mm-yyyy'), to_date('26-06-2025','dd-mm-yyyy')),
  ( 'AOUG 2025', 'Vienna', to_date('16-06-2025','dd-mm-yyyy'), to_date('17-06-2025','dd-mm-yyyy'));

commit;

create table if not exists knows (
  id number generated always as identity
    constraint knows_pk primary key,
  src_id number,
  dst_id number
);

alter table knows add constraint knows_src_id_to_persons_fk foreign key ( src_id ) references persons ( id );
alter table knows add constraint knows_dst_id_to_persons_fk foreign key ( dst_id ) references persons ( id );

truncate table knows drop storage;

insert into knows ( src_id, dst_id )
values
  ( 2, 4 ),
  ( 3, 1 ),
  ( 3, 10 ),
  ( 4, 3 ),
  ( 5, 2 ),
  ( 6, 7 ),
  ( 6, 4 ),
  ( 6, 2 ),
  ( 6, 5 ),
  ( 7, 4 ),
  ( 8, 6 ),
  ( 8, 7 ),
  ( 9, 3 );

commit;

create table if not exists works_for (
  id number generated always as identity
    constraint works_for_pk primary key,
  src_id number,
  dst_id number
);

alter table works_for add constraint works_for_src_id_to_persons_fk foreign key ( src_id ) references persons ( id );
alter table works_for add constraint works_for_dst_id_to_companies_fk foreign key ( dst_id ) references companies ( id );

insert into works_for ( src_id, dst_id )
values
  ( 1, 1 ),
  ( 6, 1);

commit;

create table if not exists speaks_at (
  id number generated always as identity
    constraint speaks_at_pk primary key,
  src_id number,
  dst_id number,
  presents_on date,
  start_time timestamp,
  end_time timestamp,
  room varchar2(100)
);

alter table speaks_at add constraint speaks_at_src_id_to_persons_fk foreign key ( src_id ) references persons ( id );
alter table speaks_at add constraint speaks_at_dst_id_to_events_fk foreign key ( dst_id ) references events ( id );

insert into speaks_at ( src_id, dst_id, presents_on )
values
  ( 1, 1, to_date('24-06-2025','dd-mm-yyyy')),
  ( 6, 1, to_date('24-06-2025','dd-mm-yyyy')),
  ( 6, 2, to_date('18-06-2025','dd-mm-yyyy'));

commit;


DROP PROPERTY GRAPH IF EXISTS simple_sql_graph;

CREATE PROPERTY GRAPH IF NOT EXISTS simple_sql_graph
  VERTEX TABLES (
    persons
	  KEY ( id ) LABEL person
      PROPERTIES ARE ALL COLUMNS,
    companies
      KEY ( id ) LABEL company
      PROPERTIES ARE ALL COLUMNS,
    events
      KEY ( id ) LABEL event
      PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    works_for
      KEY (id)
      SOURCE KEY ( src_id ) REFERENCES persons ( id )
      DESTINATION KEY ( dst_id ) REFERENCES companies ( id )
      LABEL works_for PROPERTIES ARE ALL COLUMNS,
    knows
      KEY (id)
      SOURCE KEY ( src_id ) REFERENCES persons ( id )
      DESTINATION KEY ( dst_id ) REFERENCES persons ( id )
      LABEL knows PROPERTIES ARE ALL COLUMNS,
    speaks_at
      KEY (id)
      SOURCE KEY ( src_id ) REFERENCES persons ( id )
      DESTINATION KEY ( dst_id ) REFERENCES events ( id )
      LABEL speaks_at PROPERTIES ARE ALL COLUMNS
  );


SELECT
	num_hops,
  'Karin -> ' || names_list AS path
FROM GRAPH_TABLE (
  simple_sql_graph
  MATCH (p1 IS Person) (-[e IS knows]-> (x)){1,6} (p2 IS Person)
  WHERE
    p1.name = 'Karin' AND p2.name = 'Carsten'
  COLUMNS (
		LISTAGG (x.name, ' -> ') AS names_list,
		BINDING_COUNT (e) AS num_hops
  )
)
ORDER BY
  num_hops;

SELECT
	num_hops,
  'Karin - ' || names_list AS path
FROM GRAPH_TABLE (
  simple_sql_graph
  MATCH (p1 IS Person) (-[e IS knows|works_for]- (x WHERE x.name <> 'Karin')){1,6} (p2 IS Person)
  WHERE
    p1.name = 'Karin' AND p2.name = 'Carsten'
  COLUMNS (
		LISTAGG (x.name, ' - ') AS names_list,
		BINDING_COUNT (e) AS num_hops
  )
)
ORDER BY
  num_hops,
  path;

SELECT
	num_hops as num_hops,
  'Karin - ' || names_list || ' - Carsten' AS path
FROM GRAPH_TABLE (
  simple_sql_graph
  MATCH
    (p1 IS Person)
    (-[e1 IS knows|works_for]-(x WHERE x.name not in ('Karin','Carsten'))){1,6}
    -[e2]- (p2 IS Person)
  WHERE
    p1.name = 'Karin' AND p2.name = 'Carsten'
  COLUMNS (
		LISTAGG (x.name, ' - ') AS names_list,
		BINDING_COUNT (e1)+1 AS num_hops
  )
)
ORDER BY
  num_hops,
  path;

SELECT
	num_hops,
  'Karin -> ' || name_list AS path
FROM GRAPH_TABLE (
  simple_sql_graph
  MATCH
    (p1 IS Person) (-[e1 IS knows]-> (x)){1,6} (p2 IS Person)
  WHERE
    p1.name = 'Karin' AND p2.name = 'Carsten'
  COLUMNS (
		LISTAGG (x.name, ' -> ') AS name_list,
		BINDING_COUNT (e1) AS num_hops
  )
)
UNION
SELECT
	num_hops,
  'Karin -> ' || name_list AS path
FROM GRAPH_TABLE (
  simple_sql_graph
  MATCH
    (p1 IS Person) (-[e2 IS works_for]-(y)){1,6} (p2 IS Person)
  WHERE
    p1.name = 'Karin' AND p2.name = 'Carsten'
  COLUMNS (
		LISTAGG (y.name, ' -> ') AS name_list,
		BINDING_COUNT (e2) AS num_hops
  )
)
ORDER BY
  num_hops;