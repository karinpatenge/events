--------------------------
-- Author: Albert Godfrind
-- Update: Karin Patenge
--------------------------

!cls
set sqlformat ansiconsole
set serveroutput on
set echo on

-- Turn VPA off
alter session set spatial_vector_acceleration = false;
show parameter spatial_vector_acceleration;

set echo off
set serveroutput off
