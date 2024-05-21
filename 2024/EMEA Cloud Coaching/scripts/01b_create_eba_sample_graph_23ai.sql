/******************************************************************************************
 * Operational Property Graphs in Oracle Database 23ai: EBA_SAMPLE_GRAPH
 * Author: Karin Patenge
 * Date: May 2025
 *
 * Source: https://docs.oracle.com/en/database/oracle/property-graph/23.3/spgdg/graph-developers-guide-property-graph.pdf
 ******************************************************************************************/

DROP PROPERTY GRAPH EBA_SAMPLE_GRAPH;

CREATE PROPERTY GRAPH eba_sample_graph
    VERTEX TABLES (
        eba_graphviz_countries
            KEY ( country_id )
            LABEL country
            PROPERTIES ( country_id, country_name, region_id ),
        eba_graphviz_departments
            KEY ( department_id )
            LABEL department
            PROPERTIES ( department_id, department_name, location_id, manager_id ),
        eba_graphviz_locations
            KEY ( location_id )
            LABEL location
            PROPERTIES ( city, country_id, location_id, postal_code, state_province, street_address ),
        eba_graphviz_job_history
            KEY ( employee_id, end_date, job_id, start_date )
            PROPERTIES ( department_id, employee_id, end_date, job_id, start_date ),
        eba_graphviz_jobs
            KEY ( job_id )
            LABEL job
            PROPERTIES ( job_id, job_title, max_salary, min_salary ),
        eba_graphviz_regions
            KEY ( region_id )
            LABEL region
            PROPERTIES ( region_id, region_name ),
        eba_graphviz_employees
            KEY ( employee_id )
            LABEL employee
            PROPERTIES ( commission_pct, department_id, email, employee_id, first_name, hire_date, job_id, last_name, manager_id, phone_number, salary )
    )
    EDGE TABLES (
        eba_graphviz_countries AS country_located_in
            SOURCE KEY ( country_id ) REFERENCES eba_graphviz_countries ( country_id )
            DESTINATION KEY ( region_id ) REFERENCES eba_graphviz_regions ( region_id )
            NO PROPERTIES,
        eba_graphviz_departments AS department_located_in
            SOURCE KEY ( department_id ) REFERENCES eba_graphviz_departments ( department_id )
            DESTINATION KEY ( location_id ) REFERENCES eba_graphviz_locations ( location_id )
            NO PROPERTIES,
        eba_graphviz_locations AS location_located_in
            SOURCE KEY ( location_id ) REFERENCES eba_graphviz_locations ( location_id )
            DESTINATION KEY ( country_id ) REFERENCES eba_graphviz_countries ( country_id )
            NO PROPERTIES,
        eba_graphviz_employees AS works_as
            SOURCE KEY ( employee_id ) REFERENCES eba_graphviz_employees ( employee_id )
            DESTINATION KEY ( job_id ) REFERENCES eba_graphviz_jobs ( job_id )
            NO PROPERTIES,
        eba_graphviz_employees AS works_at
            SOURCE KEY ( employee_id ) REFERENCES eba_graphviz_employees ( employee_id )
            DESTINATION KEY ( department_id ) REFERENCES eba_graphviz_departments ( department_id )
            NO PROPERTIES,
        eba_graphviz_employees AS works_for
            SOURCE KEY ( employee_id ) REFERENCES eba_graphviz_employees ( employee_id )
            DESTINATION KEY ( manager_id ) REFERENCES eba_graphviz_employees ( employee_id )
            NO PROPERTIES,
        eba_graphviz_job_history AS for_job
            KEY ( employee_id, start_date )
            SOURCE KEY ( employee_id, start_date ) REFERENCES eba_graphviz_job_history ( employee_id, start_date )
            DESTINATION KEY ( job_id ) REFERENCES eba_graphviz_jobs ( job_id )
            NO PROPERTIES,
        eba_graphviz_job_history AS for_department
            KEY ( employee_id, start_date )
            SOURCE KEY ( employee_id, start_date ) REFERENCES eba_graphviz_job_history ( employee_id, start_date )
            DESTINATION KEY ( department_id ) REFERENCES eba_graphviz_departments ( department_id )
            NO PROPERTIES,
        eba_graphviz_job_history AS for_employee
            KEY ( employee_id, start_date )
            SOURCE KEY ( employee_id, start_date ) REFERENCES eba_graphviz_job_history ( employee_id, start_date )
            DESTINATION KEY ( employee_id ) REFERENCES eba_graphviz_employees ( employee_id )
            NO PROPERTIES
    )