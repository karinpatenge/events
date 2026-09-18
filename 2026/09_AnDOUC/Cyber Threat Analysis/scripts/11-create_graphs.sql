/******************************************************************************
 *
 * Create SQL Property Graphs from the dataset
 * - One graph for REDTEAM edge type
 * - One graph combing all other edge types
 *
 * File name: 11-create_graphs.sql
 * Author: Karin Patenge
 * Last updated: 2026-09-07
 *
 *****************************************************************************/

-------------------
-- Session settings
-------------------

ALTER SESSION FORCE PARALLEL QUERY;
ALTER SESSION ENABLE PARALLEL DDL;
ALTER SESSION ENABLE PARALLEL DML;

--------------------------------------------
-- Clean up any existing SQL Property Graphs
--------------------------------------------

DROP PROPERTY GRAPH IF EXISTS lanl_ground_truth_graph;
DROP PROPERTY GRAPH IF EXISTS lanl_cyber_graph;

-----------------------------
-- Create SQL Property Graphs
-----------------------------

-- Ground-truth graph based on REDTEAM
CREATE PROPERTY GRAPH IF NOT EXISTS lanl_ground_truth_graph
  VERTEX TABLES (
    user_domain
      KEY ( user_domain )
      LABEL user_domain PROPERTIES ARE ALL COLUMNS,
    computer
      KEY ( computer )
      LABEL computer PROPERTIES ARE ALL COLUMNS,
    process AS process
      KEY ( process )
      LABEL process PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    redteam AS redteam_user_authenticated_computer
      KEY ( id )
      SOURCE KEY ( user_domain ) REFERENCES user_domain ( user_domain )
      DESTINATION KEY ( src_computer ) REFERENCES computer ( computer )
      LABEL authenticated PROPERTIES ( id, time, user_domain, src_computer ),
    redteam AS redteam_computer_compromised_computer
      KEY ( id )
      SOURCE KEY ( src_computer ) REFERENCES computer ( computer )
      DESTINATION KEY ( dst_computer ) REFERENCES computer ( computer )
      LABEL compromised PROPERTIES ( id, time, user_domain, src_computer, dst_computer )
  );

-- Cyber graph combining AUTH, DNS, FLOWS, and PROC
CREATE PROPERTY GRAPH IF NOT EXISTS lanl_cyber_graph
  VERTEX TABLES (
    user_domain
      KEY ( user_domain )
      LABEL user_domain PROPERTIES ARE ALL COLUMNS,
    computer
      KEY ( computer )
      LABEL computer PROPERTIES ARE ALL COLUMNS,
    process AS process
      KEY ( process )
      LABEL process PROPERTIES ARE ALL COLUMNS
  )
  EDGE TABLES (
    dns AS dns_computer_resolved_computer
      KEY ( id )
      SOURCE KEY ( src_computer ) REFERENCES computer ( computer )
      DESTINATION KEY ( computer_resolved ) REFERENCES computer ( computer )
      LABEL resolved PROPERTIES ( id, time, src_computer, computer_resolved ),
    flows AS flows_computer_connected_computer
      KEY ( id )
      SOURCE KEY ( src_computer ) REFERENCES computer ( computer )
      DESTINATION KEY ( dst_computer ) REFERENCES computer ( computer )
      LABEL flows_connected PROPERTIES ( id, time, duration, src_computer, src_port, dst_port, dst_computer, protocol, packet_cnt, byte_cnt ),
    proc AS proc_user_authenticated_computer
      KEY ( id )
      SOURCE KEY ( user_domain ) REFERENCES user_domain ( user_domain )
      DESTINATION KEY ( computer ) REFERENCES computer ( computer )
      LABEL proc_connected PROPERTIES ( id, time, user_domain, computer ),
    proc AS proc_computer_runs_process
      KEY ( id )
      SOURCE KEY ( computer ) REFERENCES computer ( computer )
      DESTINATION KEY ( process_name ) REFERENCES process ( process )
      LABEL ran PROPERTIES ( id, time, computer, process_name, start_end ),
    auth AS auth_src_user_authenticated_src_computer
      KEY ( id )
      SOURCE KEY ( src_user_domain ) REFERENCES user_domain ( user_domain )
      DESTINATION KEY ( src_computer ) REFERENCES computer ( computer )
      LABEL auth_src_authenticated PROPERTIES (id, time, src_user_domain, src_computer, auth_type, logon_type, auth_orientation, success_failure, redteam ),
    auth AS auth_dst_user_authenticated_dst_computer
      KEY ( id )
      SOURCE KEY ( dst_user_domain ) REFERENCES user_domain ( user_domain )
      DESTINATION KEY ( dst_computer ) REFERENCES computer ( computer )
      LABEL auth_dst_authenticated PROPERTIES (id, time, dst_user_domain, dst_computer, auth_type, logon_type, auth_orientation, success_failure, redteam ),
    auth AS auth_src_computer_connected_dst_computer
      KEY ( id )
      SOURCE KEY ( src_computer ) REFERENCES computer ( computer )
      DESTINATION KEY ( dst_computer ) REFERENCES computer ( computer )
      LABEL auth_connected PROPERTIES (id, time, src_computer, dst_computer, redteam )
  );