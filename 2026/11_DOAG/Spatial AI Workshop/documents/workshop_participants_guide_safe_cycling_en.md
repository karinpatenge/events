# Participants Guide: Safe Cycling in Nuremberg

**Spatial AI in Python: Unlocking Machine Learning for Geospatial Intelligence**
DOAG 2026, Nuremberg · Hands-on part · 45 minutes (plus 5 minutes for the optional Spatial Studio part)

Welcome to the hands-on part. You don't need to be a data scientist or a GIS expert: the notebook explains every step, and you mostly run code that is already written. This guide tells you what to do, what to look for, and what each method means.

---

## 1. Your task

**Lena** is a mobility planner for the city of Nuremberg (a fictional persona). The city wants more people to cycle, but the budget for safer crossings and cycle lanes is limited. Her manager asks: *"Where do we start?"*

You help Lena with open data and Spatial AI in the database. Your answers come in five steps:

1. **Where do bicycle accidents pile up?** → density clustering with DBSCAN
2. **Is that more than chance?** → hotspot test with Moran's I and LISA
3. **Is there cycling infrastructure nearby?** → proximity analysis
4. **Which schools and kindergartens lie in accident hotspots?** → spatial join and buffers
5. **Which places have more bicycle accidents than their traffic and surroundings would explain?** → spatial regression with OLS and GWR

At the end, Lena has a ranked list of five places and maps she can show to the city council.

![Scenario 1 storyline](../media/s1_workshop_story_en.png)

### The data

All data is open data:

- **Accidents with personal injury, 2020–2025** – Unfallatlas of the German statistical offices. About 11,000 accidents in Nuremberg, about 4,400 of them with a bicycle.
- **Residents by age group, 100 m grid** – Zensus 2022 of the German statistical offices, cut to Bavaria.
- **Cycling infrastructure, schools, kindergartens, universities and student housing** – OpenStreetMap.

The data stays in Oracle Autonomous AI Database. Python runs next to the data, and the results are written back as tables.

![Data stays in the database – Python comes to the data](../media/s1_workshop_architecture_en.png)

---

## 2. What you need

- **A workshop environment:** an Autonomous AI Database with OML Notebooks. Section 5 lists the options; the instructors tell you which one to use.
- **A workshop user:** from your LiveLabs environment, or created by yourself in your own database.

You get these from the instructors:

- **The notebook file** `Safe_Cycling_in_Nuremberg_en.dsnb`.
- **The PAR URL**: a link that lets the notebook read the data files from Object Storage. It ends with `/o/`.

A web browser is all you need on your laptop.

---

## 3. Timetable

| Time | What you do | Where |
|---|---|---|
| 0–3 | Sign in, import the notebook, set the parameters | OML Notebooks, Part 1 |
| 3–10 | Load the open data into the database | Part 2 |
| 10–16 | Explore the accidents: types, time and place | Part 3 |
| 16–21 | Find accident clusters with DBSCAN | Part 4 |
| 21–27 | Test for hotspots with Moran's I and LISA | Part 5 |
| 27–31 | Check the distance to cycling infrastructure | Part 6 |
| 31–35 | Schools and kindergartens in hotspots | Part 7 |
| 35–42 | More bicycle accidents than expected? | Part 8 |
| 42–43 | Save the results | Part 9 |
| 43–48 | Optional: put the results on a map | Spatial Studio |

The schedule is tight:
- **Try it** paragraphs are optional. Skip them if you are behind.
- **Spatial Studio is optional:** it is available only in your own Autonomous AI Database (option 2 in section 5), not in LiveLabs.
- **Run out of time?** Your tables stay in your schema, so you can do the Spatial Studio part after the workshop.

---

## 4. Working with the notebook

- **Top to bottom:** run the paragraphs one by one. The paragraphs build on each other: if you skip one, the next one is missing its variables.
- **Read the text:** the text paragraphs explain what happens and why.
- **Compare:** after every code paragraph, a paragraph **Expected result** shows what you should see and what it means.
- **Run again:** every paragraph can be run again. Tables are replaced, not appended.
- **Random numbers:** some tests use random permutations, so a few of your numbers can differ slightly from the expected results.

---

## 5. Step by step

### Before you start – Your workshop environment

You need an Oracle Autonomous AI Database with OML Notebooks. There are two options:

1. **Oracle LiveLabs (recommended for the in-person workshop at the DOAG Conference 2026):** launch the LiveLabs workshop [Get started with Oracle Machine Learning Fundamentals on Oracle Autonomous AI Database](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?clear=RR,180&wid=922) with your Oracle account. LiveLabs provides an Autonomous AI Database with OML Notebooks, including Python, but without Spatial Studio. The first labs of that workshop explain how to sign in.
2. **Oracle Autonomous AI Database 26ai Free in your own OCI tenancy:** an Always Free database in your own Oracle Cloud account, including Spatial Studio for the optional map part. Create the workshop user as ADMIN with `scripts/sql/00_create_user.sql`.

The instructors tell you in advance which option to use. If you use your own Autonomous AI Database (option 2), create your workshop user with `scripts/sql/00_create_user.sql` before the workshop, so you can start right away.

### Part 1 – Sign in and import the notebook (3 min)

1. Open **Oracle Machine Learning** and sign in with your workshop user.
2. Open **Notebooks**, choose **Import** and select the file `Safe_Cycling_in_Nuremberg_en.dsnb`.
3. Open the notebook. In the paragraph **Set workshop parameters**, replace the placeholder in `PAR_URL` with the PAR URL from the instructors.
4. Run **Import libraries** and **Set workshop parameters**.

✅ **Checkpoint:** `Connected to the database: True` and `Parameters set.`

### Part 2 – Load the open data (7 min)

You read the original files from Object Storage, keep what lies in or around Nuremberg, and write four tables to your schema. The largest files are the accident files, about 40 MB per year.

✅ **Checkpoint:** 11,002 accidents, 3,638 cycling ways, 11,780 census cells, 516 schools, kindergartens and other education places.

**Look for:** the code uses ordinary `pandas` and `geopandas`, but it runs in the database environment. The data never passes through your laptop.

### Part 3 – Explore the accidents (6 min)

You get a first picture of the bicycle accidents: on a map, by type of accident, and by time and place.

✅ **Checkpoint:** 4,387 bicycle accidents.

**Look for:**
- **Most frequent type:** driving accidents, where cyclists lose control without another road user causing it, are the largest and most severe group.
- **Over the years:** bicycle accidents fell from 801 in 2022 to 675 in 2025.
- **Over the week and day:** most accidents happen in summer, on working days and in the rush hour.

**Question:** did cycling get safer, or did fewer people cycle? What data would you need to tell?

### Part 4 – Find accident clusters (5 min)

DBSCAN looks for places where at least 12 accidents happened within 50 m of each other.

✅ **Checkpoint:** 18 clusters with 277 bicycle accidents.

**Look for:** most accidents are not in a cluster. **Try it:** compare different values of `min_samples`. Which one would you explain to the city council?

### Part 5 – Is it more than chance? (6 min)

You count the bicycle accidents in hexagons and test whether busy hexagons sit next to each other more often than by chance.

✅ **Checkpoint:** Moran's I about 0.44, and about 219 hotspot hexagons.

**Look for:** the big hotspot covers the old town and the ring road, where most people cycle. A hotspot shows where accidents concentrate, not that cycling is more dangerous there.

### Part 6 – Is there cycling infrastructure nearby? (4 min)

For every bicycle accident, you measure the distance to the nearest cycling way, and you rank the clusters.

✅ **Checkpoint:** rank 1 is Schnieglinger Straße with 29 accidents.

**Look for the surprise:** most clusters are close to existing cycling ways, and turning accidents are more frequent there. So a missing cycling way is usually not the explanation; junctions where cycling ways meet turning traffic are one important factor. Which cluster is the exception?

### Part 7 – Schools and kindergartens in hotspots (4 min)

You combine the education places with the hotspots and count the bicycle accidents within 150 m of each place.

✅ **Checkpoint:** about a quarter of the schools and kindergartens lie in a hotspot hexagon.

**Look for:** the Unfallatlas does not record the age of the people involved. The results show accidents *near* schools, not accidents *of* children.

### Part 8 – More bicycle accidents than expected? (7 min)

A regression model estimates how many bicycle accidents a hexagon would have, given its traffic (accidents without a bicycle as a stand-in), its cycling ways and its young residents. Then you look for hexagons with many more accidents than expected.

✅ **Checkpoint:** OLS explains about 58 % of the differences between hexagons (R² ≈ 0.58). Schnieglinger Straße has 31 bicycle accidents where about 8 are expected.

**Look for:**
- **OLS vs GWR:** GWR fits a separate rule for every place and explains more.
- **A new place:** a hexagon in the east that LISA did not flag.

The GWR training can take up to a minute.

### Part 9 – Save the results (1 min)

The notebook writes four result tables, ready for Spatial Studio:

| Table | Content |
|---|---|
| `NUE_HOTSPOT_GRID` | hexagons with accident counts, hotspot labels and the regression results |
| `NUE_CLUSTER_SUMMARY` | one point per cluster with its rank |
| `NUE_BIKE_ACCIDENT_CLUSTERS` | every bicycle accident with its cluster and the distance to the nearest cycling way |
| `NUE_EDUCATION_SURROUNDINGS` | schools, kindergartens and other education places with the accidents around them |

### Summary – Lena's findings and recommendations

The notebook answered Lena's five questions. For each one, this summary says what was found, what Lena can conclude from it, and what she cannot conclude. The second part matters as much as the first: the city council will ask how sure she is.

#### 1. Where do bicycle accidents pile up? (DBSCAN, Part 4)

**Finding:** 18 places, each with at least 12 bicycle accidents within 50 m over six years. Together they account for 277 of the 4,387 bicycle accidents (6 %). The top 5:

| Rank | Place | Bicycle accidents | Killed or seriously injured | Most frequent types |
|---|---|---|---|---|
| 1 | Schnieglinger Straße | 29 | 6 | driving accident (26) |
| 2 | Am Plärrer | 26 | 4 | turning (8), turning into a road or crossing (7) |
| 3 | Neutorgraben | 21 | 5 | driving accident (9) |
| 4 | Äußere Bayreuther Straße | 20 | 1 | turning into a road or crossing (10), turning (8) |
| 5 | Von-der-Tann-Straße | 17 | 3 | driving accident, turning, turning into a road or crossing (5 each) |

**What this means:** most bicycle accidents are spread across the whole city. A few places stand out, and that is useful: they are concrete places where 12 to 29 accidents can be examined together.

**What it does not mean:** a cluster is not proof that a place is more dangerous. It may simply have a lot of bicycle traffic. The number of clusters also depends on the two parameters, 50 m and 12 accidents: other values give more or fewer clusters.

#### 2. Is that more than chance? (Moran's I and LISA, Part 5)

**Finding:** Moran's I is 0.44 with a p-value of about 0.001. LISA finds about 219 hotspot hexagons in about 19 connected areas. These hotspots cover 8 % of the hexagons but contain about 42 % of the bicycle accidents. The largest hotspot area covers the old town and the ring road.

**What this means:** the pattern is real. Hexagons with many bicycle accidents lie next to each other far more often than random variation would explain. Lena can say with confidence that bicycle accidents concentrate in certain parts of the city.

**What it does not mean:** a hotspot shows *where* accidents concentrate, not *why*. The old town is also where most people cycle. And with more than 2,600 tests, a few single hexagons are "significant" by chance; a group of connected hotspot hexagons is more reliable than a single one.

#### 3. Is there cycling infrastructure nearby? (Part 6)

**Finding:** 88 % of the accidents in clusters happened within 25 m of a cycling way, compared with 58 % of the other bicycle accidents. Turning accidents are more frequent in clusters: 22 % compared with 13 %. The exception is rank 1, Schnieglinger Straße: only 31 % of its accidents happened near a cycling way, and the nearest cycling lane is about 60 m away.

**What this means:** at most clusters, cycling ways exist, so a missing cycling way is usually not the explanation. Junctions where cycling ways meet turning traffic are one important factor, because turning accidents are more frequent in clusters. But they are not the only one: at Schnieglinger Straße and Neutorgraben, driving accidents are the most frequent type. Schnieglinger Straße is also the one top-5 place where most accidents happened away from cycling ways.

**What it does not mean:** the data says nothing about the quality of the cycling ways, such as their width, separation from cars or surface. "Within 25 m" does not mean the cyclist was using the cycling way. And OpenStreetMap is only as complete as its contributors have made it.

#### 4. Which schools and kindergartens lie in accident hotspots? (Part 7)

**Finding:** 112 of 469 schools and kindergartens (24 %) lie in a hotspot hexagon. For comparison: 28 % of the residents under 18 and 31 % of all residents live in hotspot hexagons. The kindergarten St. Michael is about 130 m from the rank-1 cluster.

**What this means:** schools and kindergartens are not more often in hotspots than expected. Hotspots, schools and children all concentrate in the dense inner city, so about a quarter of them lying in a hotspot is roughly what the distribution of children predicts. (The 8 % of the hexagons is not a fair comparison, because many hexagons cover sparsely populated areas.) Still, about one in four schools and kindergartens lies in an area with a proven accumulation of bicycle accidents. That is a useful priority list for checking school routes.

**What it does not mean:** the Unfallatlas does not record the age of the people involved. The results show accidents *near* schools and kindergartens, not accidents *of* children. They also do not show that schools or kindergartens cause accidents.

#### 5. Where are there more bicycle accidents than traffic and surroundings would explain? (OLS and GWR, Part 8)

**Finding:** the regression estimates how many bicycle accidents a hexagon would have, given its traffic, its cycling ways and its young residents. Schnieglinger Straße has 31 bicycle accidents where about 8 are expected. Schmausenbuckstraße in the east has 21 where about 1 is expected, although LISA does not flag it as a hotspot. OLS, with one rule for the whole city, explains 58 % of the differences between hexagons. GWR, with a separate rule for each neighbourhood, explains about 71 %.

**What this means:** this is the fairest comparison in the workshop, because it takes into account how busy a place is. Where there are many more accidents than expected, something specific to that place makes cycling more dangerous. That GWR explains more than OLS shows that the relationship between traffic and bicycle accidents differs within the city.

**What it does not mean:** the model uses stand-ins, because there are no open traffic counts: accidents without a bicycle stand for road traffic, and residents aged 18–29 stand for cyclists. An excess of accidents is therefore a reason to look at a place on site, not a diagnosis of the cause.

#### Recommendations Lena can give to the city planners

Each recommendation names the data behind it and where the data ends.

1. **Inspect Schnieglinger Straße first.** The rank-1 cluster has 29 bicycle accidents, 6 of them with killed or seriously injured people. 26 of the 29 are driving accidents, in which cyclists lost control without another road user causing it. Only 31 % happened within 25 m of a cycling way; the nearest cycling lane is about 60 m away. The surrounding hexagon has 31 bicycle accidents where about 8 are expected, and the kindergarten St. Michael is about 130 m away. *Where the data ends:* it does not show why cyclists lose control there. That has to be found on site, and whether a cycling way would help depends on the cause.
2. **Examine the conflicts with turning and crossing traffic at Äußere Bayreuther Straße and Am Plärrer.** At Äußere Bayreuther Straße, 18 of 20 bicycle accidents were turning or turning-into-a-road/crossing accidents, all within 25 m of a cycling way. At Am Plärrer, it is 15 of 26, and 88 % happened near a cycling way. Here the cycling ways exist; the accidents happen where they meet turning and crossing traffic. *Where the data ends:* it does not say which change to the junction would prevent them.
3. **Look at Neutorgraben and Von-der-Tann-Straße one by one.** Both have cycling ways nearby (86 % and 100 % of the accidents within 25 m), but no single accident type dominates. Neutorgraben: 9 of 21 are driving accidents, the rest turning, along the road and other accidents; the neighbouring hexagon at Johannisstraße has 27 bicycle accidents where about 5 are expected. Von-der-Tann-Straße: 5 driving, 5 turning and 5 turning-into-a-road/crossing accidents of 17. *Where the data ends:* mixed types mean there is no single obvious cause.
4. **Inspect Schmausenbuckstraße on site.** Its hexagon has 21 bicycle accidents in six years, 15 of them driving accidents, but only 1 accident without a bicycle; about 1 bicycle accident would be expected. LISA does not flag it, so counting alone would have missed it. *Where the data ends:* the pattern points to the cycling route itself rather than to conflicts with cars, but the cause has to be found on site.
5. **Check the routes to the schools and kindergartens with the most bicycle accidents within 150 m:** Nürnberger Fremdsprachenschule (32, of which 8 with killed or seriously injured), Gan Schalom (32, 1), St. Michael (29, 4), Evangelische Kindertagesstätte an der Peterskirche (26, 4) and Kindergarten der Frauenkirche (25, 7). *Where the data ends:* it does not show whether children were involved, and schools and kindergartens are not over-represented in hotspots.
6. **Plan campaigns and checks for the times with the most bicycle accidents:** 58 % happened from May to September; there are about 700 on each working day of the week but about 370 on Sundays (2020–2025); on working days the peaks are at 7–8 and 16–17 o'clock. *Where the data ends:* it does not show whether campaigns or checks reduce accidents.
7. **Count cycling traffic and repeat the analysis every year.** Bicycle accidents fell from 801 in 2022 to 675 in 2025, but without counts of cyclists nobody can tell whether cycling became safer or fewer people cycled. Counts per street would turn accident numbers into risk, and a yearly run with the new Unfallatlas data shows whether measures work.

#### Limits of the analysis

- **No traffic counts:** without the number of cyclists per street, the analysis shows where accidents happen, not where cycling is most dangerous per kilometre ridden.
- **No ages:** the accident data does not say who was involved.
- **Choices:** the radius and minimum number of accidents for DBSCAN, the size of the hexagons and the significance level all influence the results. Other reasonable choices would change the number of clusters and move some places up or down the list.
- **Small numbers:** about 700 bicycle accidents per year means that differences of a few accidents between places or years can be chance.
- **Your values:** LISA uses random permutations and GWR depends on how neighbours are weighted, so your numbers can differ slightly from the ones above.

---

## 6. Optional: Spatial Studio (5 min)

This part needs your own Autonomous AI Database with Spatial Studio (option 2 in section 5). The LiveLabs environment does not provide Spatial Studio: there, the workshop ends with Part 9 of the notebook.

Menu names can differ slightly between Spatial Studio versions.

1. **Open Spatial Studio** and sign in with your workshop user.
2. **Create datasets** from the tables `NUE_HOTSPOT_GRID`, `NUE_CLUSTER_SUMMARY` and `NUE_BIKE_INFRA`. If Spatial Studio asks for a key column, use `CELL_ID`, `CLUSTER_ID`, `OSM_ID` or `ID`.
3. **Create a project** named "Safe Cycling Nuremberg" and add the datasets to the map.
4. **Style the layers:**
   - **Hotspot grid:** filter `LABEL` to `HOTSPOT` and `HIGH-LOW`, and colour by `LABEL`.
   - **Cycling infrastructure:** colour the lines by `CATEGORY`.
   - **Cluster summary:** size the points by `ACCIDENTS` and label them with `RANK`.
5. **Optional:**
   - **More than expected:** add the hotspot grid a second time and colour it by `EXCESS`, with a red-blue colour ramp.
   - **Schools and kindergartens:** create a dataset from `NUE_EDUCATION_SURROUNDINGS` and show its points, filtered to `LABEL` = `HOTSPOT`.
6. **Decide:** zoom to the top 5. Which place would you fix first, and how: a new lane, or a safer crossing?

---

## 7. If something goes wrong

| What you see | What to do |
|---|---|
| `Replace PAR_URL ...` | Paste the PAR URL from the instructors into **Set workshop parameters** and run it again. |
| HTTP 401, 403 or 404 when reading a file | Check the PAR URL for typos. If it is correct, ask the instructors. |
| `NameError: name '...' is not defined` | You skipped a paragraph, or the Python session was restarted. Run the paragraph before it. After a restart, run the notebook again from Part 1; you can skip Part 2 if your tables are already loaded. |
| Loading in Part 2 takes long | The files are large. Wait, or ask the instructors whether to load fewer years. |
| A map has no background | The basemap service is not reachable. The analysis is not affected. |
| Your numbers differ slightly | Expected for Moran's I, LISA and everything that builds on them. Clusters, counts and the top 5 should match. |

---

## 8. Terms in plain language

| Term | Meaning |
|---|---|
| **Coordinate system (CRS)** | The way positions are written down. Longitude/latitude (EPSG:4326) is good for storing, but distances need metres: here UTM zone 32N (EPSG:25832). |
| **SpatialDataFrame** | A Spatial AI table object in Python. It points to a database table instead of copying it, so filters and spatial operations run in the database. |
| **DBSCAN** | Finds dense groups of points. A point with enough neighbours within a radius starts a cluster; isolated points are "noise". |
| **Hexagon grid** | A honeycomb of equal areas. It turns points into areas that can be compared with their neighbours. |
| **Spatial weights** | The list of who is whose neighbour, for example the 6 nearest hexagons. All spatial statistics build on it. |
| **Moran's I** | One number for the whole map: are high values next to high values more often than by chance? 0 means random, positive values mean clustering. |
| **LISA** | Local Moran's I: the same test for every single hexagon. It finds hotspots (busy among busy) and outliers (busy among quiet). |
| **p-value** | How likely a pattern this strong would appear by chance. Small values (here ≤ 0.05) mean "probably not chance". |
| **Buffer** | An area around an object, for example 150 m around a school. |
| **Spatial join** | Combining two tables by location instead of by a key, for example "which hexagon is this school in?" |
| **OLS** | Ordinary least squares regression: one rule for the whole city, explaining accident counts from other variables. |
| **GWR** | Geographically weighted regression: a separate rule for every place, based on its neighbours. |
| **R²** | Share of the differences that a model explains: 0 = nothing, 1 = everything. |

---

## 9. After the workshop

- **Your results:** your tables stay in your workshop schema until the instructors remove the workshop users.
- **More examples:** OML Notebooks has more Spatial AI examples under Templates → Examples (filter "Spatial AI").
- **Documentation:** [Using Oracle Spatial AI on Autonomous AI Database Serverless](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/cspai/oracle-spatial-ai1.html)

**Data licences:**
- Unfallatlas and Zensus 2022: © Statistische Ämter des Bundes und der Länder, [Datenlizenz Deutschland – Namensnennung 2.0](https://www.govdata.de/dl-de/by-2-0).
- Cycling infrastructure, schools and kindergartens: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL.

---

## Appendix: Spatial AI and Oracle Spatial functions and features

All Spatial AI (`oraclesai`) and Oracle Spatial functions and features used in the workshop, ordered by name.

| Name | Product | What it does | Used in |
|---|---|---|---|
| `DBScanClustering` | Spatial AI (`oraclesai.clustering`) | Density-based clustering: groups points that have at least `min_samples` neighbours within the radius `eps`, and marks all other points as noise (-1). | Part 4 |
| `DBSpatialDataset` | Spatial AI | Points to a database table with a geometry column. Used to create a `SpatialDataFrame` from a table and as the target of `write()`. | Parts 2–9 |
| `enable_geodataframes()` | Spatial AI | Lets `z.show()` in OML Notebooks display GeoDataFrames and SpatialDataFrames as tables. | Part 1 |
| `GeoDataFrameDataset` | Spatial AI | Wraps a GeoPandas GeoDataFrame that exists only in Python, for example the hexagon grid, so that Spatial AI algorithms can use it. | Parts 4, 5, 8 |
| `GWRRegressor` | Spatial AI (`oraclesai.regression`) | Geographically weighted regression: fits a separate regression for every location, using its neighbours as defined by the spatial weights. | Part 8 |
| `KNNWeightsDefinition` | Spatial AI (`oraclesai.weights`) | Defines the neighbours of every geometry as its k nearest neighbours, for example `k=6` for the six hexagons around a hexagon. | Parts 5, 8 |
| `LISAHotspotClustering` | Spatial AI (`oraclesai.clustering`) | Local Moran's I (LISA): tests every geometry against its neighbours and labels significant hotspots (HIGH-HIGH), cold spots and outliers. `labels_` holds the quadrant, `regions_` the connected hotspot regions. | Part 5 |
| `MoranITest` | Spatial AI (`oraclesai.analysis`) | Global Moran's I: one value and a p-value for the whole map that show whether similar values cluster in space. Also used to check whether the errors of a model are clustered. | Parts 5, 8 |
| `OLSRegressor` | Spatial AI (`oraclesai.regression`) | Ordinary least squares regression with spatial diagnostics: one rule for the whole area. Its `summary` shows the coefficients and tests. | Part 8 |
| `PARObjStoreSpatialDataset` | Spatial AI | Reads a spatial file, for example GeoJSON, from OCI Object Storage through a pre-authenticated request (PAR). | Part 2 |
| `plot_clusters()` | Spatial AI (`oraclesai.vis`) | Draws clustering results on a map, one colour per cluster, optionally with noise points and a basemap. | Part 4 |
| `read()` | Spatial AI | Loads a spatial dataset, for example a `PARObjStoreSpatialDataset`, into a GeoDataFrame in Python. | Part 2 |
| `SCoordTransformer` | Spatial AI (`oraclesai.preprocessing`) | Turns geometries into x/y coordinate columns, the input that algorithms such as DBSCAN need. | Part 4 |
| `SDO_GEOMETRY` | Oracle Spatial | The data type of the geometry columns in all workshop tables. It stores points, lines and polygons together with their coordinate system (SRID). | All tables |
| Spatial index | Oracle Spatial | An index on a geometry column that makes spatial queries such as nearest neighbours fast. Created by `write(..., create_spatial_index=True)`. Spatial Studio needs it too. | Parts 2, 9, Spatial Studio |
| Spatial Studio – dataset | Spatial Studio | Makes a database table with geometries available for maps and analyses. | Spatial Studio |
| Spatial Studio – project and layers | Spatial Studio | A map with one layer per dataset. Layers can be filtered, coloured by a column, sized and labelled. | Spatial Studio |
| Spatial Studio – *Within distance* analysis | Spatial Studio | Finds the features of one dataset that lie within a given distance of the features of another dataset, without writing code. | Spatial Studio (instructor guide) |
| `SpatialDataFrame` | Spatial AI | The central Spatial AI data structure. It works like a GeoPandas data frame but references a database table, so filters and spatial operations run in Oracle Spatial. Created with `SpatialDataFrame.create()`. | Parts 3–9 |
| `SpatialDataFrame.as_geodataframe()` | Spatial AI | Copies the data into a GeoPandas GeoDataFrame in Python, for operations that GeoPandas offers, such as spatial joins and buffers. | Parts 3–8 |
| `SpatialDataFrame.nearest_neighbors()` | Spatial AI / Oracle Spatial | Finds the nearest geometries to a given geometry. On a table-based SpatialDataFrame, the search runs in the database and uses the spatial index. | Part 6 |
| `SpatialDataFrame.plot()` | Spatial AI | Draws the geometries on a map, optionally coloured by a column and with a basemap (`with_basemap=True`). | Parts 3, 8 |
| `SpatialDataFrame.to_crs()` | Spatial AI | Converts the geometries to another coordinate system, here from WGS84 (EPSG:4326) to UTM zone 32N (EPSG:25832) for distances in metres. | Parts 3–8 |
| `SpatialPipeline` | Spatial AI (`oraclesai.pipeline`) | Chains preprocessing steps and a model, like a scikit-learn pipeline, and passes the spatial information along. Used with `fit()` and `predict()`. | Part 8 |
| `SpatialWeights` | Spatial AI (`oraclesai.weights`) | Builds the neighbour graph from a weights definition, for example to look at the neighbours of a hexagon. | Part 5 |
| SRID | Oracle Spatial | The ID of the coordinate system of a geometry, for example 4326 for WGS84 longitude/latitude. The workshop tables use 4326. | All tables |
| `write()` | Spatial AI | Writes a GeoDataFrame to a database table, replaces an existing table with `if_exists='replace'`, and creates a spatial index with `create_spatial_index=True`. | Parts 2, 9 |
