--==============================================================================
--  02_03_load_categories.sql
--  Load automotive component category lookup rows.
--==============================================================================

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET DEFINE OFF

PROMPT
PROMPT === Loading BOM_CATEGORIES ===

INSERT INTO bom_categories (category_code, category_name, powertrain_type, description)
SELECT 'VEH',        'Complete Vehicle Assembly',  'COMMON', 'Top-level vehicle assemblies used as BOM roots.' FROM dual UNION ALL
SELECT 'ENGINE',     'Engine Systems',             'ICE',    'ICE engine assemblies and subcomponents.' FROM dual UNION ALL
SELECT 'FUEL',       'Fuel and Evap Systems',       'ICE',    'Fuel delivery, tank, pump, rail and evaporative emissions.' FROM dual UNION ALL
SELECT 'EXHAUST',    'Exhaust and Emissions',       'ICE',    'Exhaust aftertreatment, sensors, mufflers and brackets.' FROM dual UNION ALL
SELECT 'TRANS',      'Transmission and Driveline',  'ICE',    'Transmissions, gearsets, differentials and shift actuators.' FROM dual UNION ALL
SELECT 'BATTERY',    'High Voltage Battery',        'EV',     'Battery packs, modules, BMS, thermal plates and safety devices.' FROM dual UNION ALL
SELECT 'EDRIVE',     'Electric Drive Unit',         'EV',     'Traction motors, e-axles, resolvers, gear carriers and mounts.' FROM dual UNION ALL
SELECT 'PE',         'Power Electronics',           'EV',     'Inverters, converters, chargers and high-voltage junction boxes.' FROM dual UNION ALL
SELECT 'CHARGING',   'Charging System',             'EV',     'Charge ports, locks, contactors and charging harnesses.' FROM dual UNION ALL
SELECT 'HYBRIDCTRL', 'Hybrid Control',              'HYBRID', 'Hybrid supervisory controls, regen blending and power split devices.' FROM dual UNION ALL
SELECT 'BODY',       'Body Structure',              'COMMON', 'Body-in-white, closures, crash structures and reinforcements.' FROM dual UNION ALL
SELECT 'CHASSIS',    'Chassis and Frame',           'COMMON', 'Subframes, carriers, underbody shields and crash brackets.' FROM dual UNION ALL
SELECT 'BRAKE',      'Braking System',              'COMMON', 'Brake calipers, discs, boosters, hydraulic controls and actuators.' FROM dual UNION ALL
SELECT 'SUSP',       'Suspension System',           'COMMON', 'Struts, dampers, springs, control arms and stabilizer bars.' FROM dual UNION ALL
SELECT 'STEER',      'Steering System',             'COMMON', 'Electric steering racks, columns, sensors and shafts.' FROM dual UNION ALL
SELECT 'HVAC',       'Cabin HVAC',                  'COMMON', 'Cabin thermal comfort, heat pump, PTC and air handling modules.' FROM dual UNION ALL
SELECT 'THERMAL',    'Vehicle Thermal Management',  'COMMON', 'Coolant pumps, radiators, chillers, valves and manifolds.' FROM dual UNION ALL
SELECT 'INFOTAIN',   'Infotainment and Telematics', 'COMMON', 'Displays, telematics, audio and connected vehicle electronics.' FROM dual UNION ALL
SELECT 'INTERIOR',   'Interior Trim',               'COMMON', 'Seats, instrument panels, consoles, panels and cargo trims.' FROM dual UNION ALL
SELECT 'EXTERIOR',   'Exterior Trim and Lighting',  'COMMON', 'Fascias, lamps, mirrors, spoilers, shutters and exterior trim.' FROM dual UNION ALL
SELECT 'ADAS',       'ADAS and Autonomy',           'COMMON', 'Cameras, radars, sensors and ADAS domain controllers.' FROM dual UNION ALL
SELECT 'ELECTRICAL', 'Low Voltage Electrical',      'COMMON', 'Body control, junction boxes, gateways, PDUs and lighting modules.' FROM dual UNION ALL
SELECT 'HARNESS',    'Wiring Harnesses',            'COMMON', 'Low-voltage, high-voltage and signal harnesses and cable sets.' FROM dual UNION ALL
SELECT 'FASTENER',   'Fasteners and Adhesives',     'COMMON', 'Bolts, rivets, clips, retainers and structural adhesives.' FROM dual UNION ALL
SELECT 'FLUID',      'Fluids and Consumables',      'COMMON', 'Coolant, brake fluid, refrigerant, grease and assembly consumables.' FROM dual UNION ALL
SELECT 'SAFETY',     'Safety and Restraints',       'COMMON', 'Airbags, crash sensors, pretensioners and safety valves.' FROM dual UNION ALL
SELECT 'SENSOR',     'Sensors and Transducers',     'COMMON', 'Temperature, pressure, current, position and acceleration sensors.' FROM dual;

COMMIT;

PROMPT === BOM_CATEGORIES loaded ===
