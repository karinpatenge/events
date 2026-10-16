# Datasets

*Last updated 2026-10-16*

All data is open data. Status: **Loaded** (in the database), **Generated** (file prepared in `data/`), **Live** (feed checked), **Planned**, **Optional**.

## Overview

| Dataset | Provider | Licence | Source | Role in the demo | Status |
|---|---|---|---|---|---|
| OSM tram 6: route relations 147093 and 2183640, stop positions | OpenStreetMap contributors (Overpass API) | ODbL | [overpass-api.de](https://overpass-api.de) | Tram 6 track (`TRAM_LINES`) and stops A–D (`TRAM_STATIONS`) for the hook map | **Loaded** (SQL scripts) |
| ZET GTFS static, feed version 000396 (valid from 2026-09-28) | ZET (Zagrebački električni tramvaj) | Attribution required ([Transitland](https://www.transit.land/feeds/f-u25k-zagreba%C4%8Dkielektri%C4%8Dnitramvaj)); open licence via data.gov.hr to confirm | [zet.hr/gtfs-scheduled/latest](https://zet.hr/gtfs-scheduled/latest) | `ZET_STOPS`: 1,275 stations (124 tram, 1,151 bus; about 1,113 in the city) with transport mode, platforms and weekday departures; source for the July positions | **Loaded** (downloaded by the database in the dependence notebook) |
| ZET GTFS-Realtime | ZET | To confirm | [zet.hr/gtfs-rt-protobuf](https://zet.hr/gtfs-rt-protobuf) | Moving trams (Act 0), spatio-temporal queries (Act 1) | **Live**; loader job drafted in demo 1 |
| ZET tram positions 29–31 July 2026, reconstructed | Derived from ZET GTFS by `scripts/gen_zet_july_positions.py` | As ZET GTFS | `data/zet_tram_positions_202607*.csv.gz` | Three hot days for the queries and the map (demo 1, section 7.2) | **Generated**: 1,098,128 positions, 187 trams, 19 lines |
| Landsat 8 Collection 2 Level-2 surface temperature, scene `LC08_L2SP_189028_20260802_02_T1` | USGS, via the [Microsoft Planetary Computer](https://planetarycomputer.microsoft.com/dataset/landsat-c2-l2) | Public domain | [Landsat Collection 2 Level-2](https://www.usgs.gov/landsat-missions/landsat-collection-2-level-2-science-products) | Surface temperature on 2 August 2026: hook reveal, `ZG_HEAT_RASTERS` (GeoRaster), `ZG_H3_CELLS.LST_C` | **Loaded**: `data/zg_lst_20260802.tif` by `scripts/gen_zg_lst_geotiff.py`, loaded with `gdal_translate` |
| City of Zagreb boundary (OSM relation 226224) | OpenStreetMap contributors | ODbL | [openstreetmap.org/relation/226224](https://www.openstreetmap.org/relation/226224) | Clip for the surface temperature raster | **Generated**: `data/zg_city_boundary.geojson` |
| City districts (*Gradske četvrti*), version of 3 February 2025 | City of Zagreb | Otvorena dozvola (open licence) | [data.gov.hr – Gradske četvrti](https://data.gov.hr/ckan/en/dataset/gradske-cetvrti-prostorna-jedinica-mjesne-samouprave-za-podrucje-grada-zagreba) | `ZG_DISTRICTS`: 17 districts, 641 km²; Novi Zagreb – istok and – zapad (79 km²) are the held-out area of the leakage demo; district names for maps and Select AI | **Loaded** (downloaded by the database in the leakage notebook) |
| ESA WorldCover 2021 v200, tile `N45E015` | ESA WorldCover consortium, via the [Microsoft Planetary Computer](https://planetarycomputer.microsoft.com/dataset/esa-worldcover) | CC BY 4.0 | [esa-worldcover.org](https://esa-worldcover.org) | `ZG_H3_FEATURES`: land cover shares per H3 cell for OLS and GWR. City-wide: about 53 % tree canopy, 29 % other green, 1 % water, 16 % built-up | **Loaded** (downloaded by the database in the heterogeneity notebook) |
| ZG3D buildings, LoD2.2, per city district (2022 data) | City of Zagreb | Otvorena dozvola | [data.zagreb.hr – ZG3D](https://data.zagreb.hr/en/dataset/zg3d-gradska-cetvrt-donji-grad-2022) | Building heights and volumes, 3 pm shadows, population weights | Planned |
| Digital orthophoto (DOF) 2021–2024, WMS | DGU (State Geodetic Administration) | Otvorena dozvola | [DOF 2024 WMS](https://geoportal.dgu.hr/services/inspire/orthophoto_2024/wms?service=WMS&request=GetCapabilities) | Spatial Studio imagery, AI Labeling, detection, CLIP embeddings | Planned |
| LiDAR-derived terrain (DMR) and surface heights (nDMP), 2021–2023 | DGU | Otvorena dozvola | [dgu.gov.hr](https://dgu.gov.hr) (ATOM INSPIRE download) | Tree and building heights | Planned |
| Census 2021, 1 km grid | DZS (Croatian Bureau of Statistics) | To confirm | [dzs.gov.hr](https://dzs.gov.hr) (service URL to confirm) | Residents aged 65+ for colocation and Select AI | Planned |
| Sentinel-2 L2A | Copernicus (ESA) | Copernicus free and open | [dataspace.copernicus.eu](https://dataspace.copernicus.eu) | NDVI and NDBI | Planned |
| Urban Atlas Zagreb, Street Tree Layer, imperviousness | Copernicus Land Monitoring Service (EEA) | Copernicus free and open | [land.copernicus.eu](https://land.copernicus.eu) | Checks for canopy and impervious surfaces | Planned |
| Overture Maps (buildings, places) | Overture Maps Foundation | ODbL (buildings), CDLA-Permissive-2.0 (places) | [overturemaps.org](https://overturemaps.org) | GeoParquet ingest via `DBMS_CLOUD` (Act 1) | Planned |
| OSM Croatia extract | Geofabrik, OSM contributors | ODbL | [download.geofabrik.de](https://download.geofabrik.de/europe/croatia.html) | Drinking water, parks, health facilities | Optional |

## Notes on the data

**Tram 6** (`TRAM_STATIONS`, `TRAM_LINES`): stops A–D are Trg bana Josipa Jelačića, Zrinjevac, Glavni kolodvor and Autobusni kolodvor (GTFS stations 106, 107, 109, 113, set by the dependence notebook). Both track directions are continuous (about 10 km each), and every stop position lies on the track. `GTFS_SHAPE_ID` is still empty.

**Surface temperature.** The heat wave ran from 28 July to 16 August 2026 (DHMZ). The 2 August scene is the clear-sky scene closest to the demo days: 09:39 UTC, which is 11:39 in Zagreb (say "late morning" on the slide), 27.8 to 58.1 °C over the city, mean 38.2 °C. About 1 km² in the east has no value in the product.

**Land cover** is from 2021, the surface temperature from 2026: new buildings or felled trees in between are not captured.

**Reconstructed July positions.** No GTFS-RT recordings of ZET exist for July 2026 (public recordings start on 2026-09-17), so the positions for 29–31 July (Wednesday to Friday, orange heat warning on 30 July) are reconstructed from the weekday timetable: 3,838 tram trips moved along their shapes, about one position per 30 s, with small delays and 2.5 m of noise. ZET's summer timetable ran fewer trips, so frequencies are approximate. Check: tram 6 positions lie a median 1.5 m from the OSM track; 95 trams pass stop A between 14:00 and 16:00 on 29 July. Daily maximum air temperatures were not found: check DHMZ station data before quoting a number. Sources: [DHMZ analysis (morski.hr)](https://www.morski.hr/dhmz-analizirao-toplinske-valove-u-2026-cak-6-od-8-gradova-srusilo-povijesne-rekorde-evo-gdje-je-bilo-najgore/), [Wikipedia](https://hr.wikipedia.org/wiki/Toplinski_val_u_Hrvatskoj_2026.), [tportal](https://www.tportal.hr/vijesti/clanak/cijela-hrvatska-pod-meteoalarmom-neki-gradovi-gore-od-sest-ujutro-20260730).

## Open questions

1. **ZET GTFS and GTFS-RT:** confirm licence and terms of use. A third-party app describes the real-time feed as test-only, so record a replay for the live demo. The feed fills vehicle id, trip, route, position and timestamp, but not bearing, speed or stop.
2. **DZS 1 km grid:** confirm the service URL and licence; cells with fewer than 4 units are suppressed.
3. **DGU orthophoto WMS:** check the terms for bulk `GetMap` requests, and the capture dates if the 2023 storm teaser is used.
4. **DGU LiDAR:** is the raw point cloud (LAZ) openly downloadable? The derived DMR/nDMP rasters are.
5. **ZG3D:** confirm the coordinate system (probably EPSG:3765) and attributes; the files per district need to be merged.
6. **Overture:** pin a release, pre-cut the Zagreb bounding box and record the licence per theme.

## Attribution (for slides and maps)

- © OpenStreetMap contributors, ODbL
- ZET GTFS / GTFS-RT
- Grad Zagreb – ZG3D, Gradske četvrti
- DGU – digitalni ortofoto, LiDAR DMR/nDMP
- DZS – Popis 2021
- Landsat data courtesy of the U.S. Geological Survey
- © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium, CC BY 4.0
- Contains modified Copernicus Sentinel data [year]; © European Union, Copernicus Land Monitoring Service [year], EEA (if Sentinel-2 or Urban Atlas are used)

## Other assets

- `media/01_hook_*.png`: hook frames, 1920 × 1080, Redwood FY26 dark style (`scripts/gen_hook_frames.py`); frame 3 uses `ZET_STOPS_LISA.LST_C` of stops A–D (Landsat 8, 2 August 2026).
- `media/02_spatial_ml_1_dependence.svg`, `…_2_heterogeneity.svg`, `…_3_leakage.svg`: graphics for the "Spatial ML in 5 Minutes" slide; schematic, illustrative values.
- `media/03_reference_architecture.svg` and `.png`: reference architecture slide, generated by `scripts/gen_reference_architecture.py`.
- `media/oci-icons-white/`: OCI icons as white line art for dark slides.
- `media/small/tram-station.png`, `media/large/tram-station.png`: tram-station icon in Font APEX style.
