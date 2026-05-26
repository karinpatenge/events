--==============================================================================
--  02_02c_create_component_json_helpers.sql
--  Component naming, costing, weight, and JSON payload generator routines.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Creating BOM_DEMO_COMPONENT_JSON_PKG ===

CREATE OR REPLACE PACKAGE bom_demo_component_json_pkg AS
    FUNCTION component_name_for(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER
    ) RETURN VARCHAR2;

    FUNCTION base_cost(p_cat_code VARCHAR2, p_seq PLS_INTEGER) RETURN NUMBER;
    FUNCTION base_weight(p_cat_code VARCHAR2, p_seq PLS_INTEGER) RETURN NUMBER;

    FUNCTION make_component_specs(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_weight   NUMBER,
        p_cost     NUMBER
    ) RETURN VARCHAR2;

    FUNCTION make_compliance(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_weight   NUMBER
    ) RETURN VARCHAR2;

    FUNCTION make_revision_specs(
        p_cat_code VARCHAR2,
        p_rev_code VARCHAR2,
        p_seq      PLS_INTEGER,
        p_rev_no   PLS_INTEGER
    ) RETURN VARCHAR2;

    FUNCTION make_variant_attrs(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_variant  PLS_INTEGER,
        p_region   VARCHAR2,
        p_market   VARCHAR2
    ) RETURN VARCHAR2;
END bom_demo_component_json_pkg;
/

CREATE OR REPLACE PACKAGE BODY bom_demo_component_json_pkg AS
    FUNCTION component_name_for(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER
    ) RETURN VARCHAR2 IS
        v_base VARCHAR2(200);
    BEGIN
        CASE p_cat_code
            WHEN 'VEH' THEN
                v_base := bom_demo_pick_pkg.pick_model(p_seq) || ' ' || p_ptype || ' Complete Vehicle Assembly';
            WHEN 'ENGINE' THEN
                CASE MOD(p_seq, 8)
                    WHEN 0 THEN v_base := 'Turbocharged Inline-4 Engine Assembly';
                    WHEN 1 THEN v_base := 'Cylinder Head Assembly';
                    WHEN 2 THEN v_base := 'Crankshaft and Bearing Set';
                    WHEN 3 THEN v_base := 'Variable Valve Timing Module';
                    WHEN 4 THEN v_base := 'Oil Pump Assembly';
                    WHEN 5 THEN v_base := 'Engine Control Sensor Pack';
                    WHEN 6 THEN v_base := 'Intake Manifold Assembly';
                    ELSE v_base := 'Engine Mount Bracket Set';
                END CASE;
            WHEN 'FUEL' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'High Pressure Fuel Pump';
                    WHEN 1 THEN v_base := 'Fuel Rail Assembly';
                    WHEN 2 THEN v_base := 'Evaporative Emissions Canister';
                    WHEN 3 THEN v_base := 'Fuel Tank Module';
                    WHEN 4 THEN v_base := 'Fuel Injector Set';
                    ELSE v_base := 'Fuel Line Quick Connector';
                END CASE;
            WHEN 'EXHAUST' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Close-Coupled Catalyst Assembly';
                    WHEN 1 THEN v_base := 'Exhaust Gas Temperature Sensor';
                    WHEN 2 THEN v_base := 'Particulate Filter Assembly';
                    WHEN 3 THEN v_base := 'Muffler and Tailpipe Assembly';
                    WHEN 4 THEN v_base := 'Lambda Sensor';
                    ELSE v_base := 'Exhaust Hanger Bracket';
                END CASE;
            WHEN 'TRANS' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Eight-Speed Automatic Transmission';
                    WHEN 1 THEN v_base := 'Dual Clutch Module';
                    WHEN 2 THEN v_base := 'Transmission Oil Cooler';
                    WHEN 3 THEN v_base := 'Shift-by-Wire Actuator';
                    WHEN 4 THEN v_base := 'Differential Gear Set';
                    ELSE v_base := 'Torque Converter Assembly';
                END CASE;
            WHEN 'BATTERY' THEN
                CASE MOD(p_seq, 8)
                    WHEN 0 THEN v_base := 'High Voltage Battery Pack';
                    WHEN 1 THEN v_base := 'Battery Module Assembly';
                    WHEN 2 THEN v_base := 'Cell Monitoring Unit';
                    WHEN 3 THEN v_base := 'Battery Cooling Plate';
                    WHEN 4 THEN v_base := 'Pyro Fuse Safety Disconnect';
                    WHEN 5 THEN v_base := 'Battery Management Controller';
                    WHEN 6 THEN v_base := 'Busbar Interconnect Set';
                    ELSE v_base := 'Battery Pack Enclosure';
                END CASE;
            WHEN 'EDRIVE' THEN
                CASE MOD(p_seq, 7)
                    WHEN 0 THEN v_base := 'Permanent Magnet Drive Motor';
                    WHEN 1 THEN v_base := 'E-Axle Gearbox Assembly';
                    WHEN 2 THEN v_base := 'Rotor and Stator Set';
                    WHEN 3 THEN v_base := 'Resolver Sensor Assembly';
                    WHEN 4 THEN v_base := 'Motor Cooling Jacket';
                    WHEN 5 THEN v_base := 'Traction Motor Mount';
                    ELSE v_base := 'Reduction Gear Carrier';
                END CASE;
            WHEN 'PE' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Silicon Carbide Inverter';
                    WHEN 1 THEN v_base := 'DC-DC Converter';
                    WHEN 2 THEN v_base := 'Onboard Charger Power Stage';
                    WHEN 3 THEN v_base := 'High Voltage Junction Box';
                    WHEN 4 THEN v_base := 'Power Electronics Cooling Manifold';
                    ELSE v_base := 'Gate Driver Board';
                END CASE;
            WHEN 'CHARGING' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'CCS Charge Port Assembly';
                    WHEN 1 THEN v_base := 'AC Charging Harness';
                    WHEN 2 THEN v_base := 'DC Fast Charge Contactor';
                    WHEN 3 THEN v_base := 'Charge Status Light Pipe';
                    WHEN 4 THEN v_base := 'Inlet Lock Actuator';
                    ELSE v_base := 'Charge Port Weather Seal';
                END CASE;
            WHEN 'HYBRIDCTRL' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Hybrid Supervisory Control Unit';
                    WHEN 1 THEN v_base := 'Power Split Device';
                    WHEN 2 THEN v_base := 'Regenerative Brake Blending Module';
                    WHEN 3 THEN v_base := 'Hybrid Battery Relay Unit';
                    WHEN 4 THEN v_base := 'Engine Stop-Start Controller';
                    ELSE v_base := 'Hybrid Mode Selector Switch';
                END CASE;
            WHEN 'BODY' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Body-in-White Side Aperture';
                    WHEN 1 THEN v_base := 'Roof Crossmember Assembly';
                    WHEN 2 THEN v_base := 'Front Crash Structure';
                    WHEN 3 THEN v_base := 'Door Ring Reinforcement';
                    WHEN 4 THEN v_base := 'Tailgate Hinge Reinforcement';
                    ELSE v_base := 'Battery Tray Crossmember';
                END CASE;
            WHEN 'CHASSIS' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Front Subframe Assembly';
                    WHEN 1 THEN v_base := 'Rear Axle Carrier';
                    WHEN 2 THEN v_base := 'Underbody Shield';
                    WHEN 3 THEN v_base := 'Tow Hook Bracket';
                    WHEN 4 THEN v_base := 'Cross Car Beam';
                    ELSE v_base := 'Crash Load Path Bracket';
                END CASE;
            WHEN 'BRAKE' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Brake Caliper Assembly';
                    WHEN 1 THEN v_base := 'Ventilated Brake Disc';
                    WHEN 2 THEN v_base := 'Electronic Brake Booster';
                    WHEN 3 THEN v_base := 'ABS Hydraulic Control Unit';
                    WHEN 4 THEN v_base := 'Brake Pad Set';
                    ELSE v_base := 'Parking Brake Actuator';
                END CASE;
            WHEN 'SUSP' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'MacPherson Strut Assembly';
                    WHEN 1 THEN v_base := 'Multi-Link Control Arm';
                    WHEN 2 THEN v_base := 'Adaptive Damper';
                    WHEN 3 THEN v_base := 'Coil Spring';
                    WHEN 4 THEN v_base := 'Stabilizer Bar';
                    ELSE v_base := 'Suspension Knuckle';
                END CASE;
            WHEN 'STEER' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Electric Power Steering Rack';
                    WHEN 1 THEN v_base := 'Steering Column Module';
                    WHEN 2 THEN v_base := 'Torque Sensor';
                    WHEN 3 THEN v_base := 'Steering Wheel Switch Pack';
                    WHEN 4 THEN v_base := 'Tie Rod Assembly';
                    ELSE v_base := 'Steering Intermediate Shaft';
                END CASE;
            WHEN 'HVAC' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Cabin HVAC Module';
                    WHEN 1 THEN v_base := 'Heat Pump Compressor';
                    WHEN 2 THEN v_base := 'PTC Heater';
                    WHEN 3 THEN v_base := 'Cabin Air Filter';
                    WHEN 4 THEN v_base := 'Blower Motor';
                    ELSE v_base := 'HVAC Door Actuator';
                END CASE;
            WHEN 'THERMAL' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Low Temperature Radiator';
                    WHEN 1 THEN v_base := 'Electric Coolant Pump';
                    WHEN 2 THEN v_base := 'Thermal Expansion Valve';
                    WHEN 3 THEN v_base := 'Battery Chiller';
                    WHEN 4 THEN v_base := 'Coolant Manifold';
                    ELSE v_base := 'Thermal Isolation Valve';
                END CASE;
            WHEN 'INFOTAIN' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Central Display Unit';
                    WHEN 1 THEN v_base := 'Telematics Control Unit';
                    WHEN 2 THEN v_base := 'Audio Amplifier';
                    WHEN 3 THEN v_base := 'Rear Seat Entertainment Screen';
                    WHEN 4 THEN v_base := 'GNSS Antenna';
                    ELSE v_base := 'Wireless Charging Pad';
                END CASE;
            WHEN 'INTERIOR' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Instrument Panel Assembly';
                    WHEN 1 THEN v_base := 'Front Seat Frame';
                    WHEN 2 THEN v_base := 'Door Trim Panel';
                    WHEN 3 THEN v_base := 'Center Console Assembly';
                    WHEN 4 THEN v_base := 'Headliner Assembly';
                    ELSE v_base := 'Cargo Floor Trim';
                END CASE;
            WHEN 'EXTERIOR' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Front Fascia Assembly';
                    WHEN 1 THEN v_base := 'LED Headlamp Assembly';
                    WHEN 2 THEN v_base := 'Side Mirror Assembly';
                    WHEN 3 THEN v_base := 'Rear Spoiler';
                    WHEN 4 THEN v_base := 'Wheel Arch Molding';
                    ELSE v_base := 'Active Grille Shutter';
                END CASE;
            WHEN 'ADAS' THEN
                CASE MOD(p_seq, 7)
                    WHEN 0 THEN v_base := 'Forward Camera Module';
                    WHEN 1 THEN v_base := 'Long Range Radar Sensor';
                    WHEN 2 THEN v_base := 'Ultrasonic Park Sensor';
                    WHEN 3 THEN v_base := 'Driver Monitoring Camera';
                    WHEN 4 THEN v_base := 'Surround View ECU';
                    WHEN 5 THEN v_base := 'Lidar Sensor Bracket';
                    ELSE v_base := 'ADAS Domain Controller';
                END CASE;
            WHEN 'ELECTRICAL' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Body Control Module';
                    WHEN 1 THEN v_base := 'Smart Junction Box';
                    WHEN 2 THEN v_base := '12V Battery Sensor';
                    WHEN 3 THEN v_base := 'Power Distribution Unit';
                    WHEN 4 THEN v_base := 'Gateway ECU';
                    ELSE v_base := 'Lighting Control Module';
                END CASE;
            WHEN 'HARNESS' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Main Body Wiring Harness';
                    WHEN 1 THEN v_base := 'High Voltage Cable Set';
                    WHEN 2 THEN v_base := 'Door Wiring Harness';
                    WHEN 3 THEN v_base := 'Battery Sense Harness';
                    WHEN 4 THEN v_base := 'ADAS Sensor Harness';
                    ELSE v_base := 'Instrument Panel Harness';
                END CASE;
            WHEN 'FASTENER' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'M8 Flange Bolt Class 10.9';
                    WHEN 1 THEN v_base := 'Self-Piercing Rivet';
                    WHEN 2 THEN v_base := 'Clip Nut Retainer';
                    WHEN 3 THEN v_base := 'High Voltage Orange Cable Clip';
                    WHEN 4 THEN v_base := 'Thread Forming Screw';
                    ELSE v_base := 'Structural Adhesive Bead';
                END CASE;
            WHEN 'FLUID' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Long Life Coolant';
                    WHEN 1 THEN v_base := 'Low Conductivity Battery Coolant';
                    WHEN 2 THEN v_base := 'Brake Fluid DOT 4 LV';
                    WHEN 3 THEN v_base := 'Transmission Fluid';
                    WHEN 4 THEN v_base := 'A/C Refrigerant Charge';
                    ELSE v_base := 'Assembly Grease';
                END CASE;
            WHEN 'SAFETY' THEN
                CASE MOD(p_seq, 6)
                    WHEN 0 THEN v_base := 'Driver Airbag Module';
                    WHEN 1 THEN v_base := 'Seat Belt Pretensioner';
                    WHEN 2 THEN v_base := 'Pedestrian Protection Sensor';
                    WHEN 3 THEN v_base := 'Crash Sensor Satellite';
                    WHEN 4 THEN v_base := 'Side Curtain Airbag';
                    ELSE v_base := 'Battery Venting Safety Valve';
                END CASE;
            WHEN 'SENSOR' THEN
                CASE MOD(p_seq, 7)
                    WHEN 0 THEN v_base := 'Temperature Sensor';
                    WHEN 1 THEN v_base := 'Pressure Sensor';
                    WHEN 2 THEN v_base := 'Wheel Speed Sensor';
                    WHEN 3 THEN v_base := 'Current Sensor';
                    WHEN 4 THEN v_base := 'Position Sensor';
                    WHEN 5 THEN v_base := 'Humidity Sensor';
                    ELSE v_base := 'Acceleration Sensor';
                END CASE;
            ELSE
                v_base := 'Automotive Component';
        END CASE;

        RETURN v_base || ' Gen ' || TO_CHAR(1 + MOD(p_seq, 5)) || ' ' || LPAD(p_seq, 4, '0');
    END;

    FUNCTION base_cost(p_cat_code VARCHAR2, p_seq PLS_INTEGER) RETURN NUMBER IS
        v_base NUMBER;
    BEGIN
        CASE p_cat_code
            WHEN 'VEH'        THEN v_base := 11000 + DBMS_RANDOM.VALUE(3000, 9000);
            WHEN 'ENGINE'     THEN v_base := 600  + DBMS_RANDOM.VALUE(200, 4500);
            WHEN 'FUEL'       THEN v_base := 25   + DBMS_RANDOM.VALUE(10, 650);
            WHEN 'EXHAUST'    THEN v_base := 45   + DBMS_RANDOM.VALUE(15, 900);
            WHEN 'TRANS'      THEN v_base := 450  + DBMS_RANDOM.VALUE(200, 3500);
            WHEN 'BATTERY'    THEN v_base := 400  + DBMS_RANDOM.VALUE(100, 9500);
            WHEN 'EDRIVE'     THEN v_base := 300  + DBMS_RANDOM.VALUE(100, 4500);
            WHEN 'PE'         THEN v_base := 120  + DBMS_RANDOM.VALUE(50, 2800);
            WHEN 'CHARGING'   THEN v_base := 35   + DBMS_RANDOM.VALUE(10, 850);
            WHEN 'HYBRIDCTRL' THEN v_base := 90   + DBMS_RANDOM.VALUE(30, 1600);
            WHEN 'BODY'       THEN v_base := 80   + DBMS_RANDOM.VALUE(20, 2600);
            WHEN 'CHASSIS'    THEN v_base := 90   + DBMS_RANDOM.VALUE(20, 2200);
            WHEN 'BRAKE'      THEN v_base := 35   + DBMS_RANDOM.VALUE(10, 1200);
            WHEN 'SUSP'       THEN v_base := 25   + DBMS_RANDOM.VALUE(10, 950);
            WHEN 'STEER'      THEN v_base := 45   + DBMS_RANDOM.VALUE(15, 1300);
            WHEN 'HVAC'       THEN v_base := 30   + DBMS_RANDOM.VALUE(10, 1200);
            WHEN 'THERMAL'    THEN v_base := 20   + DBMS_RANDOM.VALUE(8, 900);
            WHEN 'INFOTAIN'   THEN v_base := 60   + DBMS_RANDOM.VALUE(20, 1700);
            WHEN 'INTERIOR'   THEN v_base := 20   + DBMS_RANDOM.VALUE(5, 1000);
            WHEN 'EXTERIOR'   THEN v_base := 25   + DBMS_RANDOM.VALUE(5, 1200);
            WHEN 'ADAS'       THEN v_base := 50   + DBMS_RANDOM.VALUE(20, 2200);
            WHEN 'ELECTRICAL' THEN v_base := 20   + DBMS_RANDOM.VALUE(5, 850);
            WHEN 'HARNESS'    THEN v_base := 15   + DBMS_RANDOM.VALUE(5, 650);
            WHEN 'FASTENER'   THEN v_base := 0.05 + DBMS_RANDOM.VALUE(0.01, 15);
            WHEN 'FLUID'      THEN v_base := 3    + DBMS_RANDOM.VALUE(1, 80);
            WHEN 'SAFETY'     THEN v_base := 45   + DBMS_RANDOM.VALUE(15, 1200);
            WHEN 'SENSOR'     THEN v_base := 8    + DBMS_RANDOM.VALUE(3, 300);
            ELSE v_base := 10 + DBMS_RANDOM.VALUE(1, 500);
        END CASE;

        RETURN ROUND(v_base * (1 + MOD(p_seq, 17) / 100), 4);
    END;

    FUNCTION base_weight(p_cat_code VARCHAR2, p_seq PLS_INTEGER) RETURN NUMBER IS
        v_base NUMBER;
    BEGIN
        CASE p_cat_code
            WHEN 'VEH'        THEN v_base := 900 + DBMS_RANDOM.VALUE(150, 1100);
            WHEN 'ENGINE'     THEN v_base := 35  + DBMS_RANDOM.VALUE(5, 190);
            WHEN 'FUEL'       THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 18);
            WHEN 'EXHAUST'    THEN v_base := 0.4 + DBMS_RANDOM.VALUE(0.1, 35);
            WHEN 'TRANS'      THEN v_base := 30  + DBMS_RANDOM.VALUE(5, 95);
            WHEN 'BATTERY'    THEN v_base := 2   + DBMS_RANDOM.VALUE(0.5, 620);
            WHEN 'EDRIVE'     THEN v_base := 8   + DBMS_RANDOM.VALUE(2, 120);
            WHEN 'PE'         THEN v_base := 0.4 + DBMS_RANDOM.VALUE(0.1, 45);
            WHEN 'CHARGING'   THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 12);
            WHEN 'HYBRIDCTRL' THEN v_base := 0.5 + DBMS_RANDOM.VALUE(0.1, 75);
            WHEN 'BODY'       THEN v_base := 2   + DBMS_RANDOM.VALUE(0.5, 110);
            WHEN 'CHASSIS'    THEN v_base := 3   + DBMS_RANDOM.VALUE(0.5, 95);
            WHEN 'BRAKE'      THEN v_base := 0.5 + DBMS_RANDOM.VALUE(0.1, 20);
            WHEN 'SUSP'       THEN v_base := 0.5 + DBMS_RANDOM.VALUE(0.1, 28);
            WHEN 'STEER'      THEN v_base := 0.3 + DBMS_RANDOM.VALUE(0.05, 25);
            WHEN 'HVAC'       THEN v_base := 0.3 + DBMS_RANDOM.VALUE(0.05, 38);
            WHEN 'THERMAL'    THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 22);
            WHEN 'INFOTAIN'   THEN v_base := 0.1 + DBMS_RANDOM.VALUE(0.05, 8);
            WHEN 'INTERIOR'   THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 35);
            WHEN 'EXTERIOR'   THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 25);
            WHEN 'ADAS'       THEN v_base := 0.1 + DBMS_RANDOM.VALUE(0.05, 6);
            WHEN 'ELECTRICAL' THEN v_base := 0.1 + DBMS_RANDOM.VALUE(0.05, 10);
            WHEN 'HARNESS'    THEN v_base := 0.2 + DBMS_RANDOM.VALUE(0.05, 25);
            WHEN 'FASTENER'   THEN v_base := 0.001 + DBMS_RANDOM.VALUE(0.001, 0.25);
            WHEN 'FLUID'      THEN v_base := 0.05 + DBMS_RANDOM.VALUE(0.01, 8);
            WHEN 'SAFETY'     THEN v_base := 0.1 + DBMS_RANDOM.VALUE(0.05, 15);
            WHEN 'SENSOR'     THEN v_base := 0.02 + DBMS_RANDOM.VALUE(0.01, 2.5);
            ELSE v_base := 0.1 + DBMS_RANDOM.VALUE(0.01, 10);
        END CASE;

        RETURN ROUND(v_base * (1 + MOD(p_seq, 11) / 100), 3);
    END;

    FUNCTION make_component_specs(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_weight   NUMBER,
        p_cost     NUMBER
    ) RETURN VARCHAR2 IS
        v_attr VARCHAR2(12000);
        v_voltage NUMBER;
    BEGIN
        v_voltage := CASE WHEN p_ptype IN ('EV', 'HYBRID') THEN 400 + 400 * MOD(p_seq, 2) ELSE 12 END;

        CASE p_cat_code
            WHEN 'VEH' THEN
                v_attr := '"platform":' || bom_demo_json_pkg.q('GLOBAL-' || TO_CHAR(100 + MOD(p_seq, 8))) ||
                          ',"wheelbaseMm":' || bom_demo_json_pkg.n(2600 + MOD(p_seq, 9) * 55, 0) ||
                          ',"grossVehicleWeightKg":' || bom_demo_json_pkg.n(1600 + MOD(p_seq, 14) * 85, 0) ||
                          ',"driveLayout":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'FWD' WHEN 1 THEN 'RWD' WHEN 2 THEN 'AWD' ELSE '4MOTION' END);
            WHEN 'ENGINE' THEN
                v_attr := '"engineFamily":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'EA4' WHEN 1 THEN 'Gamma-T' WHEN 2 THEN 'Skyline-I4' ELSE 'Phoenix-PHEV' END) ||
                          ',"displacementLiters":' || bom_demo_json_pkg.n(1.2 + MOD(p_seq, 6) * 0.4, 1) ||
                          ',"cylinders":' || bom_demo_json_pkg.n(CASE WHEN MOD(p_seq, 5) = 0 THEN 6 ELSE 4 END, 0) ||
                          ',"maxPowerKw":' || bom_demo_json_pkg.n(85 + MOD(p_seq, 12) * 18, 0) ||
                          ',"peakTorqueNm":' || bom_demo_json_pkg.n(180 + MOD(p_seq, 10) * 35, 0) ||
                          ',"emissionsTarget":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'Euro 7' WHEN 1 THEN 'LEV III' ELSE 'China 6b' END);
            WHEN 'FUEL' THEN
                v_attr := '"fuelType":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'Gasoline' WHEN 1 THEN 'Diesel' WHEN 2 THEN 'E10' ELSE 'Flex Fuel' END) ||
                          ',"workingPressureBar":' || bom_demo_json_pkg.n(3 + MOD(p_seq, 14) * 25, 1) ||
                          ',"evapRequirement":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 2) WHEN 0 THEN 'CARB LEV III' ELSE 'EU Type Approval' END);
            WHEN 'EXHAUST' THEN
                v_attr := '"substrate":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'Ceramic' WHEN 1 THEN 'Metallic' ELSE 'Cordierite' END) ||
                          ',"aftertreatment":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'TWC' WHEN 1 THEN 'GPF' WHEN 2 THEN 'SCR' ELSE 'DOC' END) ||
                          ',"temperatureRatingC":' || bom_demo_json_pkg.n(650 + MOD(p_seq, 8) * 50, 0);
            WHEN 'TRANS' THEN
                v_attr := '"transmissionType":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'Automatic' WHEN 1 THEN 'DCT' WHEN 2 THEN 'eCVT' ELSE 'Reduction Gear' END) ||
                          ',"gearCount":' || bom_demo_json_pkg.n(CASE MOD(p_seq, 4) WHEN 0 THEN 8 WHEN 1 THEN 7 WHEN 2 THEN 1 ELSE 6 END, 0) ||
                          ',"maxInputTorqueNm":' || bom_demo_json_pkg.n(250 + MOD(p_seq, 9) * 75, 0);
            WHEN 'BATTERY' THEN
                v_attr := '"chemistry":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'NMC811' WHEN 1 THEN 'LFP' WHEN 2 THEN 'NCA' ELSE 'LMFP' END) ||
                          ',"nominalVoltageV":' || bom_demo_json_pkg.n(v_voltage, 0) ||
                          ',"capacityKwh":' || bom_demo_json_pkg.n(12 + MOD(p_seq, 15) * 6.2, 1) ||
                          ',"moduleCount":' || bom_demo_json_pkg.n(4 + MOD(p_seq, 12), 0) ||
                          ',"cellFormat":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'Prismatic' WHEN 1 THEN 'Pouch' ELSE 'Cylindrical 4680' END) ||
                          ',"thermalInterface":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 2) WHEN 0 THEN 'Liquid cold plate' ELSE 'Dielectric immersion ready' END);
            WHEN 'EDRIVE' THEN
                v_attr := '"motorType":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'PMSM' WHEN 1 THEN 'ASM' ELSE 'EESM' END) ||
                          ',"peakPowerKw":' || bom_demo_json_pkg.n(80 + MOD(p_seq, 12) * 25, 0) ||
                          ',"peakTorqueNm":' || bom_demo_json_pkg.n(220 + MOD(p_seq, 10) * 55, 0) ||
                          ',"reductionRatio":' || bom_demo_json_pkg.n(7.5 + MOD(p_seq, 7) * 0.4, 2);
            WHEN 'PE' THEN
                v_attr := '"switchingTechnology":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'SiC MOSFET' WHEN 1 THEN 'IGBT' ELSE 'GaN auxiliary' END) ||
                          ',"voltageClassV":' || bom_demo_json_pkg.n(v_voltage, 0) ||
                          ',"continuousCurrentA":' || bom_demo_json_pkg.n(120 + MOD(p_seq, 12) * 35, 0) ||
                          ',"cooling":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 2) WHEN 0 THEN 'Liquid' ELSE 'Cold plate' END);
            WHEN 'CHARGING' THEN
                v_attr := '"connectorStandard":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'CCS2' WHEN 1 THEN 'CCS1' WHEN 2 THEN 'GB/T' ELSE 'CHAdeMO service' END) ||
                          ',"acPowerKw":' || bom_demo_json_pkg.n(CASE MOD(p_seq, 3) WHEN 0 THEN 7.4 WHEN 1 THEN 11 ELSE 22 END, 1) ||
                          ',"dcPowerKw":' || bom_demo_json_pkg.n(50 + MOD(p_seq, 8) * 50, 0) ||
                          ',"plugLock":' || bom_demo_json_pkg.b(MOD(p_seq, 2) = 0);
            WHEN 'HYBRIDCTRL' THEN
                v_attr := '"hybridArchitecture":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'P0' WHEN 1 THEN 'P2' WHEN 2 THEN 'P3' ELSE 'Power split' END) ||
                          ',"regenBlendStrategy":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 2) WHEN 0 THEN 'Brake-by-wire blended' ELSE 'Cooperative hydraulic' END) ||
                          ',"functionalSafetyLevel":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'ASIL-C' WHEN 1 THEN 'ASIL-D' ELSE 'ASIL-B' END);
            WHEN 'ADAS' THEN
                v_attr := '"sensorSuite":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'Camera' WHEN 1 THEN 'Radar' WHEN 2 THEN 'Ultrasonic' ELSE 'Lidar' END) ||
                          ',"rangeMeters":' || bom_demo_json_pkg.n(20 + MOD(p_seq, 12) * 25, 0) ||
                          ',"fieldOfViewDeg":' || bom_demo_json_pkg.n(45 + MOD(p_seq, 9) * 15, 0) ||
                          ',"adasFeature":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 5) WHEN 0 THEN 'AEB' WHEN 1 THEN 'ACC' WHEN 2 THEN 'LKA' WHEN 3 THEN 'Parking Assist' ELSE 'Driver Monitoring' END);
            WHEN 'ELECTRICAL' THEN
                v_attr := '"network":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'CAN FD' WHEN 1 THEN 'Automotive Ethernet' WHEN 2 THEN 'LIN' ELSE 'FlexRay service' END) ||
                          ',"nominalVoltageV":' || bom_demo_json_pkg.n(CASE WHEN MOD(p_seq, 5) = 0 THEN 48 ELSE 12 END, 0) ||
                          ',"diagnosticProtocol":' || bom_demo_json_pkg.q('UDS') ||
                          ',"softwareUpdateable":' || bom_demo_json_pkg.b(MOD(p_seq, 2) = 0);
            WHEN 'HARNESS' THEN
                v_attr := '"wireClass":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'LV 0.35mm2' WHEN 1 THEN 'LV 1.5mm2' WHEN 2 THEN 'HV shielded' ELSE 'Coax / Ethernet' END) ||
                          ',"connectorFamily":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'MQS' WHEN 1 THEN 'H-MTD' WHEN 2 THEN 'HVIL' ELSE 'USCAR' END) ||
                          ',"lengthMm":' || bom_demo_json_pkg.n(250 + MOD(p_seq, 30) * 125, 0);
            WHEN 'FASTENER' THEN
                v_attr := '"thread":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 5) WHEN 0 THEN 'M6x1' WHEN 1 THEN 'M8x1.25' WHEN 2 THEN 'M10x1.5' WHEN 3 THEN 'Rivet 5.3mm' ELSE 'Clip' END) ||
                          ',"coating":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'ZnNi' WHEN 1 THEN 'Delta-Protekt' WHEN 2 THEN 'Phosphate oil' ELSE 'E-coat compatible' END) ||
                          ',"torqueNm":' || bom_demo_json_pkg.n(4 + MOD(p_seq, 12) * 6, 1);
            WHEN 'FLUID' THEN
                v_attr := '"fluidType":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 5) WHEN 0 THEN 'Coolant' WHEN 1 THEN 'Brake fluid' WHEN 2 THEN 'ATF' WHEN 3 THEN 'Refrigerant' ELSE 'Grease' END) ||
                          ',"fillVolumeLiters":' || bom_demo_json_pkg.n(0.2 + MOD(p_seq, 20) * 0.35, 2) ||
                          ',"serviceIntervalKm":' || bom_demo_json_pkg.n(30000 + MOD(p_seq, 6) * 15000, 0);
            WHEN 'SAFETY' THEN
                v_attr := '"safetyFunction":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 5) WHEN 0 THEN 'Occupant restraint' WHEN 1 THEN 'Crash sensing' WHEN 2 THEN 'Battery venting' WHEN 3 THEN 'Pedestrian protection' ELSE 'Seat belt reminder' END) ||
                          ',"functionalSafetyLevel":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'ASIL-B' WHEN 1 THEN 'ASIL-C' WHEN 2 THEN 'ASIL-D' ELSE 'QM' END) ||
                          ',"deploymentValidated":' || bom_demo_json_pkg.b(MOD(p_seq, 3) <> 0);
            WHEN 'SENSOR' THEN
                v_attr := '"measurement":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 6) WHEN 0 THEN 'Temperature' WHEN 1 THEN 'Pressure' WHEN 2 THEN 'Speed' WHEN 3 THEN 'Current' WHEN 4 THEN 'Position' ELSE 'Acceleration' END) ||
                          ',"accuracyPct":' || bom_demo_json_pkg.n(0.5 + MOD(p_seq, 6) * 0.25, 2) ||
                          ',"operatingTempCMin":' || bom_demo_json_pkg.n(-40, 0) ||
                          ',"operatingTempCMax":' || bom_demo_json_pkg.n(85 + MOD(p_seq, 4) * 15, 0);
            ELSE
                v_attr := '"material":' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_material(p_seq)) ||
                          ',"surfaceTreatment":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 5) WHEN 0 THEN 'E-coat' WHEN 1 THEN 'Anodized' WHEN 2 THEN 'Powder coat' WHEN 3 THEN 'Passivated' ELSE 'Mold-in-color' END) ||
                          ',"durabilityCycles":' || bom_demo_json_pkg.n(100000 + MOD(p_seq, 20) * 25000, 0) ||
                          ',"nvhClass":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'A' WHEN 1 THEN 'B' WHEN 2 THEN 'C' ELSE 'D' END);
        END CASE;

        RETURN '{' ||
               '"schema":"bom.component.specification.v1",' ||
               '"categoryCode":' || bom_demo_json_pkg.q(p_cat_code) || ',' ||
               '"powertrainType":' || bom_demo_json_pkg.q(p_ptype) || ',' ||
               '"engineering":{' || v_attr || '},' ||
               '"manufacturing":{' ||
                   '"supplier":' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_supplier(p_seq)) || ',' ||
                   '"material":' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_material(p_seq)) || ',' ||
                   '"process":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 6) WHEN 0 THEN 'Casting' WHEN 1 THEN 'Stamping' WHEN 2 THEN 'Injection molding' WHEN 3 THEN 'Electronics SMT' WHEN 4 THEN 'Assembly' ELSE 'Machining' END) || ',' ||
                   '"ppapLevel":' || bom_demo_json_pkg.n(1 + MOD(p_seq, 5), 0) ||
               '},' ||
               '"targets":{' ||
                   '"massKg":' || bom_demo_json_pkg.n(p_weight, 3) || ',' ||
                   '"targetCostUsd":' || bom_demo_json_pkg.n(p_cost, 2) || ',' ||
                   '"warrantyMonths":' || bom_demo_json_pkg.n(CASE WHEN MOD(p_seq, 4) = 0 THEN 96 ELSE 60 END, 0) ||
               '},' ||
               '"digitalThread":{' ||
                   '"cadSystem":"NX",' ||
                   '"simulationModel":' || bom_demo_json_pkg.q('CAE-' || p_cat_code || '-' || LPAD(p_seq, 5, '0')) || ',' ||
                   '"traceabilityClass":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 4) WHEN 0 THEN 'Serial' WHEN 1 THEN 'Lot' WHEN 2 THEN 'Batch' ELSE 'None' END) ||
               '}' ||
               '}';
    END;

    FUNCTION make_compliance(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_weight   NUMBER
    ) RETURN VARCHAR2 IS
        v_asil VARCHAR2(20);
    BEGIN
        IF p_cat_code IN ('ADAS', 'BRAKE', 'STEER', 'SAFETY', 'BATTERY', 'PE', 'EDRIVE', 'HYBRIDCTRL') THEN
            v_asil := CASE MOD(p_seq, 4) WHEN 0 THEN 'ASIL-B' WHEN 1 THEN 'ASIL-C' WHEN 2 THEN 'ASIL-D' ELSE 'QM' END;
        ELSE
            v_asil := 'QM';
        END IF;

        RETURN '{' ||
               '"schema":"bom.component.compliance.v1",' ||
               '"regulatory":{' ||
                   '"rohs":"COMPLIANT",' ||
                   '"reach":"SVHC_SCREENED",' ||
                   '"elv":"COMPLIANT",' ||
                   '"conflictMinerals":' || bom_demo_json_pkg.q(CASE WHEN p_cat_code IN ('BATTERY', 'PE', 'EDRIVE', 'ELECTRICAL') THEN 'CMRT_REQUIRED' ELSE 'NOT_APPLICABLE' END) || ',' ||
                   '"functionalSafetyLevel":' || bom_demo_json_pkg.q(v_asil) ||
               '},' ||
               '"homologation":{' ||
                   '"targetMarkets":[' || bom_demo_json_pkg.q('EU') || ',' || bom_demo_json_pkg.q('NA') || ',' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'CN' WHEN 1 THEN 'JP' ELSE 'IN' END) || '],' ||
                   '"countryOfOrigin":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 6) WHEN 0 THEN 'DE' WHEN 1 THEN 'US' WHEN 2 THEN 'CN' WHEN 3 THEN 'JP' WHEN 4 THEN 'KR' ELSE 'MX' END) || ',' ||
                   '"typeApprovalRequired":' || bom_demo_json_pkg.b(p_cat_code IN ('EXTERIOR', 'SAFETY', 'ADAS', 'EXHAUST', 'BRAKE', 'STEER')) ||
               '},' ||
               '"sustainability":{' ||
                   '"recycledContentPct":' || bom_demo_json_pkg.n(MOD(p_seq, 9) * 5, 0) || ',' ||
                   '"estimatedCarbonKgCo2e":' || bom_demo_json_pkg.n(GREATEST(0.02, p_weight * (1.7 + MOD(p_seq, 8) * 0.35)), 2) || ',' ||
                   '"batteryPassportRequired":' || bom_demo_json_pkg.b(p_cat_code = 'BATTERY') ||
               '}' ||
               '}';
    END;

    FUNCTION make_revision_specs(
        p_cat_code VARCHAR2,
        p_rev_code VARCHAR2,
        p_seq      PLS_INTEGER,
        p_rev_no   PLS_INTEGER
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN '{' ||
               '"schema":"bom.revision.specification.v1",' ||
               '"revision":' || bom_demo_json_pkg.q(p_rev_code) || ',' ||
               '"changeType":' || bom_demo_json_pkg.q(CASE MOD(p_seq + p_rev_no, 6) WHEN 0 THEN 'Cost reduction' WHEN 1 THEN 'Mass optimization' WHEN 2 THEN 'Supplier change' WHEN 3 THEN 'Durability improvement' WHEN 4 THEN 'Software calibration' ELSE 'Manufacturing process update' END) || ',' ||
               '"delta":{' ||
                   '"massChangePct":' || bom_demo_json_pkg.n((MOD(p_seq + p_rev_no, 9) - 4) * 0.35, 2) || ',' ||
                   '"costChangePct":' || bom_demo_json_pkg.n((MOD(p_seq * p_rev_no, 11) - 5) * 0.45, 2) || ',' ||
                   '"drawingSheetsTouched":' || bom_demo_json_pkg.n(1 + MOD(p_seq + p_rev_no, 7), 0) ||
               '},' ||
               '"validation":{' ||
                   '"dvStatus":' || bom_demo_json_pkg.q(CASE WHEN p_rev_no = 1 THEN 'Baseline' WHEN MOD(p_seq, 5) = 0 THEN 'Waiver Approved' ELSE 'Passed' END) || ',' ||
                   '"pvStatus":' || bom_demo_json_pkg.q(CASE WHEN MOD(p_seq + p_rev_no, 4) = 0 THEN 'In Progress' ELSE 'Passed' END) || ',' ||
                   '"testReport":' || bom_demo_json_pkg.q('TR-' || p_cat_code || '-' || LPAD(p_seq, 5, '0') || '-' || p_rev_code) ||
               '}' ||
               '}';
    END;

    FUNCTION make_variant_attrs(
        p_cat_code VARCHAR2,
        p_ptype    VARCHAR2,
        p_seq      PLS_INTEGER,
        p_variant  PLS_INTEGER,
        p_region   VARCHAR2,
        p_market   VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        RETURN '{' ||
               '"schema":"bom.component.variant.v1",' ||
               '"region":' || bom_demo_json_pkg.q(p_region) || ',' ||
               '"marketSegment":' || bom_demo_json_pkg.q(p_market) || ',' ||
               '"trimApplicability":[' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_trim(p_seq + p_variant)) || ',' || bom_demo_json_pkg.q(bom_demo_pick_pkg.pick_trim(p_seq + p_variant + 2)) || '],' ||
               '"attributes":{' ||
                   '"colorOrFinish":' || bom_demo_json_pkg.q(CASE MOD(p_seq + p_variant, 8) WHEN 0 THEN 'Satin Black' WHEN 1 THEN 'Warm Grey' WHEN 2 THEN 'Piano Black' WHEN 3 THEN 'Brushed Aluminum' WHEN 4 THEN 'Body Color' WHEN 5 THEN 'Orange HV' WHEN 6 THEN 'Natural' ELSE 'Matte Graphite' END) || ',' ||
                   '"languagePack":' || bom_demo_json_pkg.q(CASE p_region WHEN 'EU' THEN 'EU-27' WHEN 'NA' THEN 'EN-FR-ES' WHEN 'CN' THEN 'ZH-CN' WHEN 'JP' THEN 'JA-JP' WHEN 'KR' THEN 'KO-KR' WHEN 'IN' THEN 'EN-HI' ELSE 'EN-ES-PT' END) || ',' ||
                   '"driveSide":' || bom_demo_json_pkg.q(CASE WHEN p_region IN ('JP', 'IN', 'UK') THEN 'RHD' ELSE 'LHD' END) || ',' ||
                   '"softwareCalibration":' || bom_demo_json_pkg.q('SW-' || p_cat_code || '-' || p_region || '-' || LPAD(MOD(p_seq, 500), 3, '0')) || ',' ||
                   '"coldWeatherPack":' || bom_demo_json_pkg.b(p_market = 'Cold Weather' OR p_region IN ('EU', 'NA', 'KR')) || ',' ||
                   '"hotClimatePack":' || bom_demo_json_pkg.b(p_market = 'Warm Climate' OR p_region IN ('MEA', 'IN', 'LATAM')) ||
               '},' ||
               '"logistics":{' ||
                   '"packagingType":' || bom_demo_json_pkg.q(CASE MOD(p_seq + p_variant, 4) WHEN 0 THEN 'Returnable rack' WHEN 1 THEN 'KLT tote' WHEN 2 THEN 'ESD tray' ELSE 'Bulk bin' END) || ',' ||
                   '"leadTimeDays":' || bom_demo_json_pkg.n(7 + MOD(p_seq + p_variant, 8) * 3, 0) || ',' ||
                   '"incoterm":' || bom_demo_json_pkg.q(CASE MOD(p_seq, 3) WHEN 0 THEN 'DAP' WHEN 1 THEN 'FCA' ELSE 'DDP' END) ||
               '}' ||
               '}';
    END;

END bom_demo_component_json_pkg;
/

SHOW ERRORS PACKAGE bom_demo_component_json_pkg
SHOW ERRORS PACKAGE BODY bom_demo_component_json_pkg

DECLARE
    v_error_count PLS_INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO   v_error_count
    FROM   user_errors
    WHERE  name = 'BOM_DEMO_COMPONENT_JSON_PKG'
    AND    type IN ('PACKAGE', 'PACKAGE BODY');

    IF v_error_count > 0 THEN
        RAISE_APPLICATION_ERROR(-20000, 'BOM_DEMO_COMPONENT_JSON_PKG compiled with errors. Run SHOW ERRORS PACKAGE BODY BOM_DEMO_COMPONENT_JSON_PKG.');
    END IF;
END;
/

PROMPT === BOM_DEMO_COMPONENT_JSON_PKG created ===
