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
,p_default_application_id=>110
,p_default_id_offset=>14394028688543154
,p_default_owner=>'DEVUSER'
);
end;
/
 
prompt APPLICATION 110 - Sample Geocoder
--
-- Application Export:
--   Application:     110
--   Name:            Sample Geocoder
--   Date and Time:   11:18 Tuesday March 19, 2024
--   Exported By:     KPATENGE
--   Flashback:       0
--   Export Type:     Component Export
--   Manifest
--     PLUGIN: 40095327096761087
--   Manifest End
--   Version:         23.2.3
--   Instance ID:     8554775834495400
--

begin
  -- replace components
  wwv_flow_imp.g_mode := 'REPLACE';
end;
/
prompt --application/shared_components/plugins/process_type/adb_geocoder
begin
wwv_flow_imp_shared.create_plugin(
 p_id=>wwv_flow_imp.id(40095327096761087)
,p_plugin_type=>'PROCESS TYPE'
,p_name=>'ADB_GEOCODER'
,p_display_name=>'Server Side Geocoding'
,p_supported_component_types=>'APEX_APPLICATION_PAGE_PROC:APEX_APPL_AUTOMATION_ACTIONS'
,p_plsql_code=>wwv_flow_string.join(wwv_flow_t_varchar2(
'function process_geocode (',
'    p_process in apex_plugin.t_process,',
'    p_plugin  in apex_plugin.t_plugin )',
'    return apex_plugin.t_process_exec_result',
'is',
'    c_hn_first_countries   constant apex_t_varchar2 := apex_t_varchar2( ''au'', ''ca'', ''cn'', ''fr'', ''uk'', ''gb'', ''hk'', ''in'', ''jp'', ''nz'', ''us'', ''za'' );',
'',
'    c_match_mode           constant varchar2(255)   := p_plugin.attribute_01;',
'    c_country_code         constant varchar2(255)   := case p_process.attribute_01',
'                                                           when ''ITEM'' ',
'                                                           then v( p_process.attribute_03 )',
'                                                           else p_process.attribute_02',
'                                                       end;',
'    ',
'    c_structured           constant boolean         := p_process.attribute_04 = ''Y'';',
'    c_sanitize             constant boolean         := p_process.attribute_05 = ''Y'';',
'',
'    c_address_unstructured constant varchar2(32767) := v( p_process.attribute_06 );',
'',
'    c_street_item          constant varchar2(32767) := p_process.attribute_07;',
'    c_house_number_item    constant varchar2(32767) := p_process.attribute_08;',
'    c_zip_item             constant varchar2(32767) := p_process.attribute_09;',
'    c_city_item            constant varchar2(32767) := p_process.attribute_10;',
'    c_city_subarea_item    constant varchar2(32767) := p_process.attribute_11;',
'    c_region_item          constant varchar2(32767) := p_process.attribute_12;',
'    c_coordinate_item      constant varchar2(32767) := p_process.attribute_13;',
'    c_matchvector_item     constant varchar2(32767) := p_process.attribute_14;',
'',
'    c_collection_name      constant varchar2(32767) := p_process.attribute_15;',
'',
'',
'    l_street               varchar2(32767) := v( c_street_item );',
'    l_house_number         varchar2(255)   := v( c_house_number_item );',
'',
'    l_geocoding_results    clob;',
'    l_coordinate_geojson   varchar2(32767);',
'',
'    l_result               apex_plugin.t_process_exec_result;',
'begin',
'    if l_house_number is not null then',
'        if lower( c_country_code ) member of c_hn_first_countries then',
'            l_street := l_house_number || '' '' || l_street;',
'        else ',
'            l_street := l_street || '' '' || l_house_number;',
'        end if;',
'        apex_debug.trace( ''Computed Street / House Number string is: %s'', l_street );',
'    end if;',
'',
'    if c_collection_name is not null and not apex_collection.collection_exists( c_collection_name ) then',
'        apex_collection.create_collection( c_collection_name );',
'    end if;',
'',
'',
'    if c_structured then',
'        apex_debug.info( ''perform structured address geocoding using match mode: %s'', c_match_mode );',
'',
'        l_geocoding_results := mdsys.sdo_gcdr.eloc_geocode( ',
'                                  cc2          => c_country_code,',
'                                  street       => l_street,',
'                                  postal_code  => v( c_zip_item ),',
'                                  city         => v( c_city_item ),',
'                                  region       => v( c_region_item ),',
'                                  --',
'                                  match_mode   => c_match_mode );',
'    else ',
'        apex_debug.info( ''perform unstructured address geocoding.'' );',
'        ',
'        -- unstructured address does not allow passing in a match mode?',
'        l_geocoding_results := mdsys.sdo_gcdr.eloc_geocode( ',
'                                  address     => c_address_unstructured );',
'    end if;',
'',
'    apex_debug.trace( ''JSON Result received from the geocoder is: %s'', l_geocoding_results );',
'',
'    apex_debug.info( ''parsing geocoder results.'' );',
'',
'    <<parse_geocoder_results_loop>>',
'    for l_geocoding_result in (',
'        select seq,',
'               street,',
'               house_number,',
'               municipality,',
'               settlement,',
'               region,',
'               postalcode,',
'               matchvector,',
'               country,',
'               lon,',
'               lat',
'          from json_table(',
'                   l_geocoding_results,',
'                   ''$.matches[*]''',
'                   columns(',
'                       seq          for ordinality,',
'                       street       varchar2(4000) path ''$.street'',',
'                       house_number varchar2(255)  path ''$.houseNumber'',',
'                       municipality varchar2(4000) path ''$.municipality'',',
'                       settlement   varchar2(4000) path ''$.settlement'',',
'                       region       varchar2(4000) path ''$.region'',',
'                       country      varchar2(255)  path ''$.country'',',
'                       postalcode   varchar2(4000) path ''$.postalCode'',',
'                       matchvector  varchar2(255)  path ''$.matchVector'',',
'                       lon          number         path ''$.x'',',
'                       lat          number         path ''$.y'' ) ) )',
'    loop',
'        apex_debug.trace( ''parsing geocoder result #%s'', l_geocoding_result.seq );',
'',
'        if c_matchvector_item is not null then',
'            apex_session_state.set_value( c_matchvector_item, l_geocoding_result.matchvector );',
'        end if;',
'',
'        if c_coordinate_item is not null then',
'            l_coordinate_geojson := case when l_geocoding_result.lon is not null and l_geocoding_result.lat is not null ',
'                                         then     ''{"type":"Point", "coordinates": ['' ',
'                                               || apex_json.stringify( l_geocoding_result.lon ) ',
'                                               || '','' ',
'                                               || apex_json.stringify( l_geocoding_result.lat )',
'                                               || '']}''',
'                                    end;',
'            apex_session_state.set_value( c_coordinate_item, l_coordinate_geojson );',
'        end if;',
'',
'        if c_sanitize then',
'        ',
'            apex_session_state.set_value( c_street_item, l_geocoding_result.street );',
'            if c_house_number_item is not null then',
'                apex_session_state.set_value( c_house_number_item, l_geocoding_result.house_number );',
'            end if;',
'            if c_zip_item is not null then',
'                apex_session_state.set_value( c_zip_item, l_geocoding_result.postalcode );',
'            end if;',
'            if c_city_item is not null then',
'                apex_session_state.set_value( c_city_item, l_geocoding_result.municipality );',
'            end if;',
'            if c_city_subarea_item is not null then',
'                apex_session_state.set_value( c_city_subarea_item, l_geocoding_result.settlement );',
'            end if;',
'            if c_region_item is not null then',
'                apex_session_state.set_value( c_region_item, l_geocoding_result.region );',
'            end if;',
'        end if;',
'',
'        if c_collection_name is not null then',
'            apex_collection.add_member( ',
'                p_collection_name => c_collection_name,',
'                p_c001            => l_geocoding_result.street,',
'                p_c002            => l_geocoding_result.house_number,',
'                p_c003            => l_geocoding_result.postalcode,',
'                p_c004            => l_geocoding_result.municipality,',
'                p_c005            => l_geocoding_result.settlement,',
'                p_c006            => l_geocoding_result.region,',
'                p_c007            => l_geocoding_result.country,',
'                p_c011            => l_geocoding_result.matchvector,',
'                p_n001            => l_geocoding_result.lon,',
'                p_n002            => l_geocoding_result.lat,',
'                p_d001            => sysdate );',
'        end if;',
'',
'        exit when c_collection_name is null and l_geocoding_result.seq > 1;',
'',
'    end loop parse_geocoder_results_loop;',
'',
'    return l_result;',
'end process_geocode;'))
,p_default_escape_mode=>'HTML'
,p_api_version=>2
,p_execution_function=>'process_geocode'
,p_standard_attributes=>'REGION'
,p_substitute_attributes=>true
,p_subscribe_plugin_settings=>true
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<p>This process type provides Geocoding (turning a postal address to a coordinate) functionality.</p>',
'<p>Geocoding is performed by calling <strong>SDO_GCDR.ELOC_GEOCODE</strong>, which does a REST request to the <strong>Oracle Elocation</strong> Geocoding Service (elocation.oracle.com). The <strong>SDO_GCDR.ELOC_GEOCODE</strong> is defined as follows'
||':</p>',
'<pre>',
'function eloc_geocode( ',
'    street       in varchar2, ',
'    city         in varchar2,',
'    region       in varchar2, ',
'    postal_code  in varchar2,',
'    cc2          in varchar2, ',
'    match_mode   in varchar2 default ''DEFAULT'' )',
'    return varchar2;',
'',
'function eloc_geocode( ',
'    address      in varchar2 )',
'    return varchar2;',
'</pre>',
'<p>Geocoding input data comes from page items, which are mapped to address parts like Street, House Number, Postal Code or City. The process populates a coordinate and match vector page item with the results of the first matched address. In addition,'
||' all matches can be loaded into a collection for further processing.  If <strong>Sanitize Address</strong> is enabled, address part page items will be overwritten with the sanitized values of the first matched address.</p>'))
,p_version_identifier=>'1.0'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40148340485070796)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'APPLICATION'
,p_attribute_sequence=>1
,p_display_sequence=>10
,p_prompt=>'Match Mode'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'RELAX_HOUSE_NUMBER'
,p_is_translatable=>false
,p_lov_type=>'STATIC'
,p_help_text=>'<p>The <strong>Match Mode</strong> determines how closely the attributes of an input address must match the data being used for geocoding.</p>'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40149504554072571)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>10
,p_display_value=>'Exact'
,p_return_value=>'EXACT'
,p_help_text=>'<p>All provided address parts must match. However, if the house number, street name or street type do not <em>all</em> match, the first match in the following is returned: postal code, city or town, and state. For example, if the street name is incor'
||'rect but a valid postal code is specified, a location in the postal code is returned.</p>'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40149855241073724)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>20
,p_display_value=>'Relax Street Type'
,p_return_value=>'RELAX_STREET_TYPE'
,p_help_text=>'<p>The provided <em>street type</em> can be different from the data used for geocoding. For example, <strong>Main Street</strong> or <strong>Main Blvd</strong> match <strong>Main St</strong>, if there is no other <strong>Main Blvd</strong> or <strong'
||'>Main Street</strong> in the relevant area.</p>'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40150273799074790)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>30
,p_display_value=>'Relax House Number'
,p_return_value=>'RELAX_HOUSE_NUMBER'
,p_help_text=>'<p>The house number and street type can be different from the data used for geocoding. For example, <strong>123 Main St</strong> matches <strong>123 Main Lane</strong> and <strong>124 Main St</strong>, as long as there are no ambiguities or other mat'
||'ches.</p>'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40150658715076158)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>40
,p_display_value=>'Relax Street Name'
,p_return_value=>'RELAX_BASE_NAME'
,p_help_text=>'<p>The <em>base name</em> of the street, the house number, and the street type can be different from the data used for geocoding. For example, <strong>Pleasant Vale</strong> matches <strong>Pleasant Valley</strong> as long as there are no ambiguities'
||' or other matches in the data.'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40151034135077242)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>50
,p_display_value=>'Relax Postal Code'
,p_return_value=>'RELAX_POSTAL_CODE'
,p_help_text=>'<p>The postal code (if provided), street name, street type and house number can be different from the data used for geocoding.</p>'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40151515752078314)
,p_plugin_attribute_id=>wwv_flow_imp.id(40148340485070796)
,p_display_sequence=>60
,p_display_value=>'Relax All'
,p_return_value=>'RELAX_ALL'
,p_help_text=>'<p>The address can be outside the city specified as long as it is within the same county. Also includes the characteristics of <strong>Relax Postal Code</strong>.</p>'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40095922191774217)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>1
,p_display_sequence=>20
,p_prompt=>'Country Type'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'STATIC'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_lov_type=>'STATIC'
,p_help_text=>'Choose whether to use a static country for geocoding, or whether to derive the country from an item.'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40096269460775969)
,p_plugin_attribute_id=>wwv_flow_imp.id(40095922191774217)
,p_display_sequence=>10
,p_display_value=>'Static'
,p_return_value=>'STATIC'
,p_help_text=>'Use a static country from a select list.'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40096669602777124)
,p_plugin_attribute_id=>wwv_flow_imp.id(40095922191774217)
,p_display_sequence=>20
,p_display_value=>'Item'
,p_return_value=>'ITEM'
,p_help_text=>'Get the country from an application or page item. The item must contain the 2-digit ISO code for a country.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40097288877781923)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>30
,p_prompt=>'Country'
,p_attribute_type=>'SELECT LIST'
,p_is_required=>true
,p_default_value=>'US'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40095922191774217)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'STATIC'
,p_lov_type=>'STATIC'
,p_help_text=>'Pick the country to use for geocoding.'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40097567468782833)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>10
,p_display_value=>'United States'
,p_return_value=>'US'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40097937067783489)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>20
,p_display_value=>'United Kingdom'
,p_return_value=>'UK'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40098351012784092)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>30
,p_display_value=>'Germany'
,p_return_value=>'DE'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40098728931784777)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>40
,p_display_value=>'France'
,p_return_value=>'FR'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40099184255785732)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>50
,p_display_value=>'Italy'
,p_return_value=>'IT'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40099577548786117)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>60
,p_display_value=>'Canada'
,p_return_value=>'CA'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40099981758786684)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>70
,p_display_value=>'Netherlands'
,p_return_value=>'NL'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40100363855787330)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>80
,p_display_value=>'Belgium'
,p_return_value=>'BE'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40100781050788259)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>90
,p_display_value=>'Austria'
,p_return_value=>'AT'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40101172181789119)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>100
,p_display_value=>'Switzerland'
,p_return_value=>'CH'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40101600845789629)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>110
,p_display_value=>'Spain'
,p_return_value=>'ES'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40101953098790932)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>120
,p_display_value=>'Portugal'
,p_return_value=>'PT'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40102382581791530)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>130
,p_display_value=>'Estonia'
,p_return_value=>'EE'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40102721427791960)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>140
,p_display_value=>'India'
,p_return_value=>'IN'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40103179496792622)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>150
,p_display_value=>'Mexico'
,p_return_value=>'MX'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40103546263793272)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>160
,p_display_value=>'Australia'
,p_return_value=>'AU'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40103951121793789)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>170
,p_display_value=>'Brazil'
,p_return_value=>'BR'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40104391060794543)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>180
,p_display_value=>'Chile'
,p_return_value=>'CL'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40104811605795557)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>190
,p_display_value=>'Czech Republic'
,p_return_value=>'CZ'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40105188994795994)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>200
,p_display_value=>'Norway'
,p_return_value=>'NO'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40105573741796495)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>210
,p_display_value=>'Finland'
,p_return_value=>'FI'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40105949518797012)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>220
,p_display_value=>'Denmark'
,p_return_value=>'DK'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40106370979797521)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>230
,p_display_value=>'Hong Kong'
,p_return_value=>'HK'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40106736179798014)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>240
,p_display_value=>'Ireland'
,p_return_value=>'IE'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40107181303798547)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>250
,p_display_value=>'Latvia'
,p_return_value=>'LV'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40107572878799412)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>260
,p_display_value=>'Romania'
,p_return_value=>'RO'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40107921931799875)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>270
,p_display_value=>'Colombia'
,p_return_value=>'CO'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40108330233800487)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>280
,p_display_value=>'Poland'
,p_return_value=>'PL'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40108797906801820)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>290
,p_display_value=>'United Arab Emirates'
,p_return_value=>'AE'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40109147277802479)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>300
,p_display_value=>'Hungary'
,p_return_value=>'HU'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40109609135803189)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>310
,p_display_value=>'Saudi Arabia'
,p_return_value=>'SA'
);
wwv_flow_imp_shared.create_plugin_attr_value(
 p_id=>wwv_flow_imp.id(40110002964803762)
,p_plugin_attribute_id=>wwv_flow_imp.id(40097288877781923)
,p_display_sequence=>320
,p_display_value=>'South Africa'
,p_return_value=>'ZA'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40110465731810334)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>3
,p_display_sequence=>40
,p_prompt=>'Country'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40095922191774217)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'ITEM'
,p_examples=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<ul>',
'<li><strong>US</strong>: United States</li>',
'<li><strong>UK</strong>: United Kingdom</li>',
'<li><strong>DE</strong>: Germany</li>',
'<li><strong>AT</strong>: Austria</li>',
'</ul>'))
,p_help_text=>'Pick a page or application item to get the country for geocoding from. The item must contain the 2-digit ISO code for a country.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40110931985817482)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>4
,p_display_sequence=>10
,p_prompt=>'Structured Address'
,p_attribute_type=>'CHECKBOX'
,p_is_required=>false
,p_default_value=>'Y'
,p_is_translatable=>false
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<p>Whether address parts are provided to the geocoding service in a <em>structured</em> or <em>unstructured</em> manner.</p>',
'<p>Structured means that explicit page items are mapped to address parts like Street, Postal Code, City or Region. This leads to more accurate geocoding results, and also allows to feed the ',
'corrected addresses back to the page items.</p>',
'<p>Unstructured means that only one item is used for the whole address; parts are separated by comma. This mode does not allow to feed corrected addresses back to the page item.</p>'))
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40111255233821223)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>5
,p_display_sequence=>50
,p_prompt=>'Sanitize Address'
,p_attribute_type=>'CHECKBOX'
,p_is_required=>false
,p_default_value=>'Y'
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'<p>Enable this switch to feed address data from the geocoding service back to the mapped items. If the geocoder returns multiple matching addresses, the <em>first match</em> will be fed back to the configured page items.</p><p>Configure a <strong>Col'
||'lection Name</strong> to fetch all matched addresses into a collection, for further processing.</p>'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40158220968117049)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>6
,p_display_sequence=>60
,p_prompt=>'Address Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'N'
,p_help_text=>'Pick the item containing unstructured address parts, separated by comma.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40111852757828381)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>7
,p_display_sequence=>70
,p_prompt=>'Street Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the Street part of the address.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40112171953831039)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>8
,p_display_sequence=>80
,p_prompt=>'House Number Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the <em>House Number</em> part of the address.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40112496162833446)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>9
,p_display_sequence=>90
,p_prompt=>'Postal Code Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the <em>Postal Code</em> part of the address.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40112730682836656)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>10
,p_display_sequence=>100
,p_prompt=>'City Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the <em>City</em> part of the address.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40113055405839424)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>11
,p_display_sequence=>110
,p_prompt=>'City Sub Area Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the <em>Sub Area (within a City)</em> part of the address. This attribute is not passed to the geocoder, but can be received back for address enrichment.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40113336901841459)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>12
,p_display_sequence=>120
,p_prompt=>'Region Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_depending_on_attribute_id=>wwv_flow_imp.id(40110931985817482)
,p_depending_on_has_to_exist=>true
,p_depending_on_condition_type=>'EQUALS'
,p_depending_on_expression=>'Y'
,p_help_text=>'Pick the item containing the <em>Region (State)</em> part of the address.'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40113806417847880)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>13
,p_display_sequence=>130
,p_prompt=>'Coordinate Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_help_text=>'<p>Pick a page item to store the coordinate of <em>the first Geocoder match</em>, in GeoJSON format.</p>'
);
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40114103808852222)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>14
,p_display_sequence=>140
,p_prompt=>'Match Vector Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<p>Pick a page item to store the <em>Match Vector</em> of <em>the first Geocoder match</em>. The match vector is a 17-digit string with detailed information about how each address attribute has been matched against the data used for geocoding.</p>',
'<p><strong>Match Vector digits can have the following values:</strong></p>',
'<ul>',
'<li><p>0: The input attribute is not null and is matched with a non-null value.</p></li>',
'<li><p>1: The input attribute is null and is matched with a null value.</p></li>',
'<li><p>2: The input attribute is not null and is replaced by a different non-null value.</p></li>',
'<li><p>3: The input attribute is not null and is replaced by a null value.</p></li>',
'<li><p>4: The input attribute is null and is replaced by a non-null value.</p></li>',
'</ul>',
'<br>',
'<p><strong>Match Vector digits and the address attribute corresponding to each:</strong></p>',
'<ul>',
'<li><p>3: Address Point (exact address matched in data used for geocoding)</p></li>',
'<li><p>4: Point Of Interest Name</p></li>',
'<li><p>5: House Number</p></li>',
'<li><p>6: Street Prefix</p></li>',
'<li><p>7: Street Name</p></li>',
'<li><p>8: Street Suffix</p></li>',
'<li><p>9: Street Type</p></li>',
'<li><p>10: Secondary Unit</p></li>',
'<li><p>11: City</p></li>',
'<li><p>14: Region</p></li>',
'<li><p>15: Country</p></li>',
'<li><p>16: Postal Code</p></li>',
'<li><p>17: Postal Add-On Code</p></li>',
'<li><p><em>other digits are unused yet.</em></p></li>',
'</ul>'))
);
end;
/
begin
wwv_flow_imp_shared.create_plugin_attribute(
 p_id=>wwv_flow_imp.id(40126872256789230)
,p_plugin_id=>wwv_flow_imp.id(40095327096761087)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>15
,p_display_sequence=>150
,p_prompt=>'Collection Name'
,p_attribute_type=>'TEXT'
,p_is_required=>false
,p_display_length=>30
,p_max_length=>30
,p_is_translatable=>false
,p_help_text=>wwv_flow_string.join(wwv_flow_t_varchar2(
'<p>If the name of a collection is provided, then all geocoding results are fetched into this collection. The mapping of geocoding result attributes to collection member attributes is as follows:</p>',
'<ul>',
'<li><code>C001</code>: <strong>Street</strong></li>',
'<li><code>C002</code>: <strong>House Number</strong></li>',
'<li><code>C003</code>: <strong>Postal Code</strong></li>',
'<li><code>C004</code>: <strong>City</strong></li>',
'<li><code>C005</code>: <strong>City sub area</strong></li>',
'<li><code>C006</code>: <strong>Region (State)</strong></li>',
'<li><code>C007</code>: <strong>Country</strong></li>',
'<li><code>C011</code>: <strong>Match Vector</strong></li>',
'<li><code>N001</code>: <strong>Longitude</strong></li>',
'<li><code>N002</code>: <strong>Latitude</strong></li>',
'<li><code>D001</code>: <strong>Timestamp of Geocoding</strong></li>',
'</ul>',
'<p>If the collection does not exist, it will be created before the first member is added. Existing collections will <em>not</em> be cleared; this must be done using a separate page process which runs before this geocoding process.</p>'))
);
null;
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
