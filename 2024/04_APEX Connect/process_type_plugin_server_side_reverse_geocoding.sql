--------------------------------------------------------------------------------
-- Name: Sample Geocoder
-- Copyright (c) 2012, 2024 Oracle and/or its affiliates.
-- Licensed under the Universal Permissive License v 1.0 as shown
-- at https://oss.oracle.com/licenses/upl/
-- 
-- Data providers:
-- This application makes use of third-party data provided by HERE (c) available via http://elocation.oracle.com. Make sure to read and understand the end-user terms published at http://elocation.oracle.com/elocation/terms.html.
--------------------------------------------------------------------------------
prompt --application/set_environment
set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback
--------------------------------------------------------------------------------
--
-- Oracle APEX export file
--
-- You should run this script using a SQL client connected to the database as
-- the owner (parsing schema) of the application or as a database user with the
-- APEX_ADMINISTRATOR_ROLE role.
--
-- This export file has been automatically generated. Modifying this file is not
-- supported by Oracle and can lead to unexpected application and/or instance
-- behavior now or in the future.
--
-- NOTE: Calls to apex_application_install override the defaults below.
--
--------------------------------------------------------------------------------
begin
wwv_flow_imp.import_begin (
 p_version_yyyy_mm_dd=>'2023.10.31'
,p_release=>'23.2.3'
,p_default_workspace_id=>9935058041861130
,p_default_application_id=>111
,p_default_id_offset=>11797912299441821
,p_default_owner=>'DEVUSER'
);
end;
/
 
prompt APPLICATION 111 - Sample Geocoder
--
-- Application Export:
--   Application:     111
--   Name:            Sample Geocoder
--   Date and Time:   22:03 Monday April 22, 2024
--   Exported By:     KPATENGE
--   Flashback:       0
--   Export Type:     Component Export
--   Manifest
--     PLUGIN: 10151374071289
--   Manifest End
--   Version:         23.2.3
--   Instance ID:     8554775834495400
--

begin
  -- replace components
  wwv_flow_imp.g_mode := 'REPLACE';
end;
/
prompt --application/shared_components/plugins/process_type/server_side_reverse_geocoding
begin
wwv_flow_imp_shared.create_plugin(
 p_id=>wwv_flow_imp.id(10151374071289)
,p_plugin_type=>'PROCESS TYPE'
,p_name=>'SERVER_SIDE_REVERSE_GEOCODING'
,p_display_name=>'Server Side Reverse Geocoding'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_PROC:APEX_APPL_AUTOMATION_ACTIONS'
,p_plsql_code=>wwv_flow_string.join(wwv_flow_t_varchar2(
'function process_reverse_geocode (',
'   p_process in apex_plugin.t_process,',
'   p_plugin  in apex_plugin.t_plugin )',
'   return apex_plugin.t_process_exec_result',
'is',
'',
'   -- Input parameters for reverse geocoding',
'   c_lon                         constant number            := p_process.attribute_01;',
'   c_lat                         constant number            := p_process.attribute_02;',
'',
'   -- Output parameters for reverse geocoding',
'   c_street                      constant varchar2(4000)    := p_process.attribute_03;',
'   c_house_number                constant varchar2(4000)    := p_process.attribute_04;',
'   c_settlement                  constant varchar2(4000)    := p_process.attribute_05;',
'   c_municipality                constant varchar2(4000)    := p_process.attribute_06;',
'   c_postal_code                 constant varchar2(4000)    := p_process.attribute_07;',
'   c_region                      constant varchar2(4000)    := p_process.attribute_08;',
'   c_country                     constant varchar2(4000)    := p_process.attribute_09;',
'',
'   l_reverse_geocoding_result   clob;',
'',
'   l_result                      apex_plugin.t_process_exec_result;',
'',
'   l_street                      varchar2(4000);',
'   l_house_number                varchar2(4000);',
'   l_settlement                  varchar2(4000);',
'   l_municipality                varchar2(4000);',
'   l_postal_code                 varchar2(4000);',
'   l_region                      varchar2(4000);',
'   l_country                     varchar2(4000);',
'',
'begin',
'',
'   l_reverse_geocoding_result := mdsys.sdo_gcdr.eloc_geocode(',
'      longitude   => c_lon,',
'      latitude    => c_lat );',
'',
'   apex_debug.info( ''JSON result received from the reversed geocoding is: %s'', l_reverse_geocoding_result );',
'',
'   apex_debug.info( ''Parsing reverse geocoding results.'' );',
'',
'   select',
'      street,',
'      house_number,',
'      settlement,',
'      municipality,',
'      region,',
'      postal_code,',
'      country',
'   into',
'      l_street,',
'      l_house_number,',
'      l_settlement,',
'      l_municipality,',
'      l_region,',
'      l_postal_code,',
'      l_country',
'   from json_table(',
'      l_reverse_geocoding_result,',
'      ''$.matches[*]''',
'      columns(',
'         lon          number         path ''$.x'',',
'         lat          number         path ''$.y'',',
'         street       varchar2(4000) path ''$.street'',',
'         house_number varchar2(255)  path ''$.houseNumber'',',
'         settlement   varchar2(4000) path ''$.settlement'',',
'         municipality varchar2(4000) path ''$.municipality'',',
'         region       varchar2(4000) path ''$.region'',',
'         postal_code  varchar2(4000) path ''$.postalCode'',',
'         country      varchar2(255)  path ''$.country''));',
'',
'   if c_street is not null then',
'      apex_session_state.set_value(c_street, l_street);',
'   end if;',
'',
'   if c_house_number is not null then',
'      apex_session_state.set_value(c_house_number, l_house_number);',
'   end if;',
'',
'   if c_settlement is not null then',
'      apex_session_state.set_value(c_settlement, l_settlement);',
'   end if;',
'',
'   if c_municipality is not null then     ',
'      apex_session_state.set_value(c_municipality, l_municipality);',
'   end if;',
'',
'   if c_region is not null then   ',
'      apex_session_state.set_value(c_region, l_region);',
'   end if;',
'',
'   if c_postal_code is not null then   ',
'      apex_session_state.set_value(c_postal_code, l_postal_code);',
'   end if;',
'   ',
'   if c_country is not null then   ',
'      apex_session_state.set_value(c_country, l_country);',
'   end if;',
'',
'   return l_result;',
'end process_reverse_geocode;'))
,p_default_escape_mode=>'HTML'
,p_api_version=>2
,p_execution_function=>'process_reverse_geocode'
,p_standard_attributes=>'REGION'
,p_substitute_attributes=>true
,p_subscribe_plugin_settings=>true
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<p>This process type provides <strong>Reverse Geocoding</strong> (turning coordinates into a postal addresses) functionality.</p>',
'<p>Reverse geocoding is performed by calling <strong>SDO_GCDR.ELOC_GEOCODE</strong>, which makes a REST request to the <strong>Oracle Elocation</strong> Geocoding Service (elocation.oracle.com). The service uses geocoding reference data provided by H'
||'ERE&copy;.',
'<p>The <strong>SDO_GCDR.ELOC_GEOCODE</strong> is an overloaded function and is defined as follows to perform reverse geocoding:</p>',
'<pre>',
'function eloc_geocode( ',
'    Lon       in number, ',
'    lat       in number )',
'    return varchar2;',
'</pre>',
'<p>Reverse geocoding input data comes from page items mapped to a coordinate represented by its longitude and latitude values. The process populates addresses matching the coordinate, returning values like street, house number, postal code, city, or '
||'country. It also returns a match vector page item that contains information about the quality of the first matched address. In addition, all matches can be loaded into a collection for further processing.'))
,p_version_identifier=>'1.0'
);
wwv_flow_imp_shared.create_plugin_attr_group(
 p_id=>wwv_flow_imp.id(103772705333491)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_title=>'Structured Address'
,p_display_sequence=>1
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(10604335075706)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>1
,p_display_sequence=>10
,p_prompt=>'Longitude Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(10836170077199)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>20
,p_prompt=>'Latitude Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(98021272972259)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>3
,p_display_sequence=>30
,p_prompt=>'Street Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(110343882440237)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>4
,p_display_sequence=>40
,p_prompt=>'House Number Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(109670649437225)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>5
,p_display_sequence=>50
,p_prompt=>'Settlement Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(102473534317137)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>6
,p_display_sequence=>60
,p_prompt=>'Municipality Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(102778994318093)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>7
,p_display_sequence=>70
,p_prompt=>'Postal Code Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(103100931318666)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>8
,p_display_sequence=>80
,p_prompt=>'Region Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(103346438319151)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>9
,p_display_sequence=>90
,p_prompt=>'Country Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_attribute_group_id=>wwv_flow_imp.id(103772705333491)
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(106653509351271)
,p_plugin_id=>wwv_flow_imp.id(10151374071289)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>10
,p_display_sequence=>100
,p_prompt=>'Location'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
);
end;
/
prompt --application/end_environment
begin
wwv_flow_imp.import_end(p_auto_install_sup_obj => nvl(wwv_flow_application_install.get_auto_install_sup_obj, false));
commit;
end;
/
set verify on feedback on define on
prompt  ...done
