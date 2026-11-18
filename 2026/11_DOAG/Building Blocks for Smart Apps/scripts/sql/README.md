# SQL-Skripte für die Demo „Nur verstaucht?“

Die Skripte richten die Demo-Umgebung in einer **Oracle Autonomous AI Database 26ai** ein und laden den Datensatz aus `../../data`. Sie folgen den [Oracle Database Skills](https://github.com/oracle/skills/tree/main/db), vor allem `appdev` (JSON, Spatial, Property Graph, Oracle Text), `sqlcl` (Laden) sowie `agent` (wiederholbare und abgesicherte Skripte).

## Überblick

| Nr. | Datei | Ausführen als | Zweck |
| --- | --- | --- | --- |
| 00 | `00_create_user.sql` | ADMIN | Demo-Benutzer `DOAG2026` anlegen, alle Rechte vergeben |
| 01 | `01_run_all.sql` | DOAG2026 | Ruft 02 bis 10 nacheinander auf und schreibt das Protokoll `01_run_all.log` (Start, Ende, Laufzeiten) |
| 02 | `02_create_tables.sql` | DOAG2026 | Tabellen und Staging-Tabellen anlegen |
| 03 | `03_load_data.sql` | DOAG2026 | Datensatz (ohne RDF) mit SQLcl laden, Statistiken sammeln |
| 04 | `04_create_annotations.sql` | DOAG2026 | Schema-Annotationen für alle Tabellen und Spalten setzen (nach 02, vor oder nach 03) |
| 05 | `05_create_embeddings.sql` | DOAG2026 | Embedding-Modell all-MiniLM-L12-v2 laden, `symptom_reports.report_embedding` füllen (nach 03) |
| 06 | `06_create_text_index.sql` | DOAG2026 | Volltextindex (Oracle Text) auf `symptom_reports.report_text` mit deutschen Einstellungen (nach 03) |
| 07 | `07_create_spatial_indexes.sql` | DOAG2026 | Spatial-Metadaten, Geometrieprüfung, Spatial-Indexe, Statistiken (nach 03) |
| 08 | `08_create_rdf_network.sql` | DOAG2026 | RDF-Netzwerk `RDF_NETWORK`, Staging-Tabelle, Graphen `KNEE_KG` und `FMA`, Regelbasis `KNEE_RB` (nur die Regeln; die Inferenz `KNEE_KG_RIX` erzeugt 09a nach dem Laden) |
| 09a | `09a_load_knee_kg.sql` | DOAG2026 | Knie-Wissensgraph `KNEE_KG` laden, Inferenz, Probeabfragen (nach 08) |
| 09b | `09b_load_fma.sql` | DOAG2026 | FMA laden (einige Minuten), Graph-Sammlung, RDF-Textindex, Probeabfragen (nach 08, meist nach 09a) |
| 10 | `10_create_property_graph.sql` | DOAG2026 | SQL Property Graph `CARE_NETWORK` über dem Versorgungsnetz (nach 03) |
| 11 | `11_demo_live_de.sqlnb`, `11_demo_live_en.sqlnb` | DOAG2026 | Demo-Notebook für den Vortrag, deutsch und englisch (gleiches SQL, nur die Beschreibungen sind übersetzt): nur die 12 Abfragen, die live laufen (eine in Schritt 1, je zwei in den Schritten 2–6, eine im Finale); unverändert aus 11a–11h übernommen (Ablauf: `documents/demo-guide.md`) |
| 11a–11i | `11*.sqlnb` | DOAG2026 | SQL Notebooks mit den Analysen je Demo-Schritt und der Auswertung aller Bausteine (11i), in SQL Developer for VS Code (nach 01 bzw. 10) |
| 12 | `12_query_ontologies.sparql` | DOAG2026 | 35 SPARQL-Beispielabfragen (SELECT, DESCRIBE, CONSTRUCT) für einen SPARQL-Endpunkt (z. B. Oracle RDF Graph Server): Teil A FMA, Teil B Knie-Ontologie `KNEE_KG`, Teil C beide über `skos:exactMatch` (Graph-Sammlung `KNEE_FMA_VM`); reines SPARQL 1.1, auch in `SEM_MATCH` verwendbar (nach 09a und 09b) |
| 98 | `98_cleanup.sql` | DOAG2026 | Alle Objekte des Demo-Benutzers entfernen, der Benutzer bleibt |
| 99 | `99_drop_user.sql` | ADMIN | Demo-Benutzer entfernen (nach 98) |

**Nummerierung:** 00–10 für Einrichten und Laden, 11a–11i für die Analyse-Notebooks, 98 und 99 für das Aufräumen. Jedes neue Skript bekommt eine Nummer aus diesem Schema.

**Konvention für alle Abfragen:** keine `CROSS JOIN`s. Ein einzelner Vergleichswert (z. B. Jonas' Vektor) kommt als skalare Unterabfrage oder Bindevariable in die Abfrage, alles andere über Joins mit Bedingung. Das gilt auch für die Analyse-Skripte der Demo-Schritte.

Alle Skripte sind **wiederholbar**. Sie brechen beim ersten Fehler ab (`WHENEVER SQLERROR EXIT`), prüfen, ob der richtige Benutzer angemeldet ist, und fragen vor dem Löschen nach.

## Voraussetzungen

1. **Autonomous AI Database 26ai** (Serverless) mit Zugang als ADMIN.
2. **SQLcl** in einer aktuellen Version. `LOAD` ist ein SQLcl-Befehl; die Skripte laufen deshalb nicht in SQL*Plus und nicht im SQL Worksheet von Database Actions.
3. **Verbindung** über das Wallet, z. B.:
   ```powershell
   sql -cloudconfig C:\Pfad\Wallet_DOAG.zip admin@doag_high
   ```
4. **UTF-8 für SQLcl:** Die Skripte und Daten sind UTF-8-kodiert (Umlaute in Annotationen und Daten). Vor dem Start in PowerShell:
   ```powershell
   $env:JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8"
   ```
5. **Oracle Java einschalten** (nur für RDF): `SEM_MATCH` braucht auf Autonomous AI Database Oracle Java. `00_create_user.sql` schaltet es ein, wenn es noch fehlt (`DEFINE enable_java = Y`), nach der [Oracle-Dokumentation](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-oracle-java.html):
   1. `DBMS_CLOUD_ADMIN.ENABLE_FEATURE(feature_name => 'JAVAVM')` als ADMIN (macht das Skript).
   2. Datenbank neu starten: OCI-Konsole, Seite der Datenbank, **More actions › Restart**, oder `oci db autonomous-database restart --autonomous-database-id <OCID>`.
   3. Warten, bis die Installation fertig ist: `SELECT status, version FROM dba_registry WHERE comp_id = 'JAVAVM';` zeigt `VALID` (`LOADING` = läuft noch). Zusätzlich liefert `SELECT dbms_java.get_jdk_version FROM dual;` die JDK-Version.

   Oracle Java lässt sich danach **nicht wieder ausschalten**. Im Wartungsfenster patcht Oracle Java; Java-Aufrufe können dann kurz mit `ORA-29548` scheitern. Laden und Anlegen der Graphen funktionieren auch ohne Java.
6. **Ladekopien in `data/_load`.** SQLcl `LOAD` liest nur Textdateien mit Trennzeichen (`SET LOADFORMAT JSON` gilt nur für `UNLOAD`) und prüft die Dateiendung: `.ndjson` und `.nt` nimmt es mit `LOADFORMAT DELIMITED` nicht an. 03 und 09 laden deshalb inhaltsgleiche Kopien mit der Endung `.csv`:

   | Ladekopie | Original |
   | --- | --- |
   | `data/_load/knee_kg_nt.csv` | `data/rdf/knee_kg.nt` |
   | `data/_load/fma_nt.csv` | `data/rdf/fma.nt.gz`, entpackt (92 MB, per `.gitignore` nicht im Repository) |
   | `data/_load/json_chunks.csv` | alle `data/spatial/*.geojson`, `data/json/symptom_report_jonas.json` und `data/json/fhir_bundles_all_patients.ndjson` (je Zeile ein Dokument), als kompaktes JSON in Stücken von höchstens 1000 Zeichen (23.641 Zeilen, 16.550 Dokumente). Trennzeichen ist der Backtick. SQLcl `soda insert` scheitert mit „Index 4 out of bounds“, `LOAD` liest kein JSON und hat die NDJSON-Zeilen der FHIR-Bundles (bis 11.865 Byte) zeilenweise nicht geladen |

   Alle Kopien außer `fma_nt.csv` liegen im Repository. Ändert sich ein Original, alle Kopien neu erzeugen mit `python _generator/make_load_copies.py` im Ordner `data` (legt auch `fma_nt.csv` an). `fma_nt.csv` einmal anlegen, unter Windows in PowerShell:
   ```powershell
   cd "<Projekt>\data"
   $src = [IO.File]::OpenRead("$PWD\rdf\fma.nt.gz")
   $gz  = New-Object IO.Compression.GZipStream($src, [IO.Compression.CompressionMode]::Decompress)
   $dst = [IO.File]::Create("$PWD\_load\fma_nt.csv")
   $gz.CopyTo($dst); $dst.Close(); $gz.Close(); $src.Close()
   ```
   Unter Linux/macOS: `gunzip -c data/rdf/fma.nt.gz > data/_load/fma_nt.csv`.

## Ablauf

```powershell
cd "<Projekt>\scripts\sql"

# 1. Als ADMIN: Benutzer und Rechte (fragt nach dem Passwort)
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip admin@doag_high @00_create_user.sql

# 2. Als Demo-Benutzer: alles Weitere in einem Lauf (02 bis 10)
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @01_run_all.sql

# oder einzeln
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @02_create_tables.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @03_load_data.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @04_create_annotations.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @05_create_embeddings.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @06_create_text_index.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @07_create_spatial_indexes.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @08_create_rdf_network.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @09a_load_knee_kg.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @09b_load_fma.sql
sql -cloudconfig C:\Pfad\Wallet_DOAG.zip doag2026@doag_high @10_create_property_graph.sql
```

`01_run_all.sql` bricht beim ersten Fehler ab. Jedes Skript schreibt per `SPOOL` ein eigenes Protokoll `<Skriptname>.log` nach `../../logs/sql` (relativ zu `scripts/sql`, also der Ordner `logs/sql` im Projektordner); es wird bei jedem Lauf überschrieben. Der Ordner muss vorhanden sein, und SQLcl muss im Ordner `scripts\sql` gestartet werden. `01_run_all.sql` schreibt dort zusätzlich `01_run_all.log` mit Start, Ende und Laufzeiten.

`03_load_data.sql`, `09a_load_knee_kg.sql` und `09b_load_fma.sql` müssen **im Ordner `scripts\sql`** starten, weil die Dateipfade relativ sind (`../../data/...`). Ein anderer Ort lässt sich oben in diesen Skripten mit `DEFINE data_dir` einstellen. Am längsten brauchen das OSM-Straßennetz (03) und die FMA mit 612.982 Triples (09).

Der Benutzername steht als `DEFINE demo_user = DOAG2026` in 00, 98 und 99. Wer ihn ändert, ändert ihn in allen drei Dateien.

## 00 – Benutzer und Rechte

| Recht | Wofür |
| --- | --- |
| `DB_DEVELOPER_ROLE` | Tabellen, Views, Sequenzen, Prozeduren, Typen, Trigger, Property Graphs, Modelle (`CREATE MINING MODEL`), Jobs (`CREATE JOB`), Domains, MLE; enthält die Rollen `RESOURCE`, `CTXAPP` (Oracle Text) und `SODA_APP` |
| `CONNECT`, `RESOURCE`, `CREATE VIEW` | RDF-Netzwerk (08, 09a, 09b): die Rechte, die die Oracle-Dokumentation für den Eigentümer eines schema-privaten RDF-Netzwerks nennt |
| `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE TRIGGER`, `CREATE PROCEDURE`, `CREATE TYPE` (direkt) | `SEM_APIS` legt Netzwerk, Graphen, Inferenz und Regelbasis als Tabellen, Views, Sequenzen, Trigger und Pakete im eigenen Schema an. Direkt vergeben gelten die Rechte auch in gespeichertem PL/SQL und in Scheduler-Jobs, wo Rollen nicht wirken |
| `QUOTA UNLIMITED ON DATA` | Speicherplatz; das RDF-Netzwerk muss im Tablespace `DATA` liegen |
| `CTXAPP`, `EXECUTE ON CTXSYS.CTX_DDL`, `CTX_QUERY`, `CTX_DOC`, `CTX_REPORT`, `CTX_OUTPUT` | Volltextindex (06) und Textindex auf den RDF-Literalen (09b, `SEM_APIS.ADD_DATATYPE_INDEX` braucht `CTX_DDL`): `CTXAPP` (schon in `DB_DEVELOPER_ROLE`) erlaubt Präferenzen, Stoplists und den CONTEXT-Index. Die direkten `EXECUTE`-Rechte braucht es, sobald `CTX_DDL` & Co. in gespeichertem PL/SQL oder Scheduler-Jobs laufen, weil dort Rollen nicht gelten. Die Index-Tabellen (`DR$…`) brauchen `CREATE TABLE` und Quota, beides vorhanden |
| `EXECUTE ON DBMS_VECTOR`, `DBMS_VECTOR_CHAIN` | Embeddings und ONNX-Modelle für die Vektorsuche |
| `EXECUTE ON DBMS_CLOUD` | Credentials und Objektspeicher, z. B. zum Laden des ONNX-Modells |
| `READ, WRITE ON DIRECTORY DATA_PUMP_DIR` | ONNX-Datei zwischenlagern und mit `DBMS_VECTOR.LOAD_ONNX_MODEL` importieren |
| `EXECUTE ON DBMS_CLOUD_AI` | Select AI (optional im Finale) |
| `GRAPH_DEVELOPER` | Graph Studio |
| `SDO_GCDR.ELOC_GRANT_ACCESS` | Routing mit `SDO_GCDR.ELOC_ROUTE` (nur Autonomous AI Database, nur durch ADMIN) |
| `ORDS_ADMIN.ENABLE_SCHEMA` | Anmeldung in Database Actions (SQL Worksheet, Kartenansicht, Graph-Werkzeuge) |
| `DBMS_CLOUD_ADMIN.ENABLE_FEATURE('JAVAVM')` | Oracle Java für `SEM_MATCH` (RDF-Abfragen); nur wenn noch nicht installiert, abschaltbar mit `DEFINE enable_java = N`; danach Neustart der Datenbank |

Fehlt eines der Zusatzrechte in der Instanz, gibt das Skript eine **WARNUNG** aus und macht weiter.

## 02 – Tabellen

| Daten | Tabelle(n) | Wichtige Datentypen |
| --- | --- | --- |
| `graph/*.csv` | `providers`, `devices`, `patients`, `appointment_slots`, `provider_relations`, `patient_provider_relations` | Schlüssel `VARCHAR2(10)`, Primär- und Fremdschlüssel (Grundlage für den Property Graph in 10), Fremdschlüssel indexiert; `accepts_acute BOOLEAN`; `slot_start TIMESTAMP WITH TIME ZONE`; `providers.geom SDO_GEOMETRY` aus `lon`, `lat` |
| `spatial/road_*.csv` | `road_nodes`, `road_links` | Punktgeometrie, Fahrzeit `cost_s` in Sekunden |
| `casebase/case_notes.csv` | `case_notes` | `note_text VARCHAR2(4000)`; Text- und Vektorindex legt die Demo an |
| `stream/*.csv` | `watch_stream`, `car_stream` | `event_ts` (Messzeit) und `ingest_ts` (Ankunftszeit) als `TIMESTAMP WITH TIME ZONE`, `buffered BOOLEAN`, Punktgeometrie |
| `spatial/trails.geojson` usw. | `trail_segments`, `parking_lots`, `pois`, `zones` | `SDO_GEOMETRY` (Linie, Punkt, Polygon); `grade_pct NUMBER(5,1)`; `car_access BOOLEAN` |
| `spatial/osm_*.geojson` | `osm_trails`, `osm_parking`, `osm_pois`, `osm_roads`, `osm_hospitals`, `osm_boundaries`, `osm_layers` | `feature_id` (z. B. `way/123`) als Schlüssel, `osm_id NUMBER(19)`, OSM-Tags als JSON-Text in `VARCHAR2(4000)` mit `IS JSON`-Prüfung (nicht als Datentyp `JSON`, den Oracle Spatial Studio nicht anzeigt), `geom SDO_GEOMETRY`; `osm_layers` hält Namensnennung, Lizenz und Datenstand. Die 38 Wanderrouten (Relationen) in `osm_trails` schneidet 03 mit `SDO_GEOM.SDO_INTERSECTION` auf das Demo-Gebiet zu (Länge 11,370–11,460, Breite 49,755–49,795, wie in der Overpass-Abfrage); Overpass liefert sie sonst vollständig, bis 109 km lang |
| `json/fhir_bundles_all_patients.ndjson`, `json/symptom_report_jonas.json` | `symptom_reports`, `diagnoses`, `medication_recommendations`, Sicht `symptom_diagnosis_medication_v` | relational zerlegt. **`symptom_reports`**: 1.458 Symptommeldungen anderer Personen und Jonas' App-Meldung, von der Person nur `age` und `gender`; Freitext in `report_text`, dazu **`report_embedding VECTOR(*, FLOAT32)`**; Position (`geom`) bei 229 Knie-Meldungen aus der App (FHIR-Erweiterung `geolocation`) und bei Jonas, strukturierte Antworten nur bei Jonas. **`diagnoses`**: 1.326 Diagnosen, je Meldung höchstens eine (Knie-Codes wie in `case_notes`). **`medication_recommendations`**: 1.331 empfohlene oder verordnete Medikamente je Diagnose. Name, Adresse, Geburtsdatum, Vorerkrankungen und Messwerte werden nicht übernommen |
| `rdf/knee_kg.nt`, `rdf/fma.nt` | keine Tabelle in 02; siehe 08, 09a und 09b | |

Allgemein gilt:
- **Koordinaten:** WGS 84 (SRID 4326), Länge vor Breite.
- **Spatial-Metadaten und -Indexe:** trägt erst 07 nach dem Laden ein (siehe unten).
- **Zeiten:** Die CSV-Zeiten sind Ortszeit Europe/Berlin. Sie werden als `TIMESTAMP WITH TIME ZONE` gespeichert, damit Ereignis- und Ankunftszeit eindeutig vergleichbar sind.
- **Staging-Tabellen** (`stg_*`) haben nur Textspalten mit denselben Namen wie die CSV-Spalten. Dazu kommen `stg_text_lines` für zeilenweise Dateien, `stg_json_chunks` für die JSON-Stücke und `stg_json_docs` für die daraus zusammengesetzten Dokumente (`doc_no` 0 = Kopf der Datei, 1..n = Features). `stg_rdf_triples` legt 08 an.

### Abfrage: ähnliche Symptome, ihre Diagnosen und Medikamente

So beantwortet die Demo die Frage „Was hatten andere mit ähnlichen Symptomen, und was wurde ihnen empfohlen?“, sobald `report_embedding` gefüllt ist:

```sql
WITH similar AS (
  SELECT s.report_id, s.age, s.gender, s.report_text,
         VECTOR_DISTANCE(s.report_embedding,
                         (SELECT j.report_embedding
                          FROM   symptom_reports j
                          WHERE  j.report_id = 'SR-2026-11-16-0001'),   -- Jonas' Meldung
                         COSINE) AS distance
  FROM   symptom_reports s
  WHERE  s.source = 'fhir'
  ORDER  BY distance
  FETCH  FIRST 10 ROWS ONLY
)
SELECT sm.report_id, sm.age, sm.gender, ROUND(sm.distance, 3) AS distance,
       d.diagnosis_label, d.confirmed_by,
       LISTAGG(m.medication_text, '; ') WITHIN GROUP (ORDER BY m.medication_text) AS medications
FROM   similar sm
LEFT   JOIN diagnoses d                  ON d.report_id    = sm.report_id
LEFT   JOIN medication_recommendations m ON m.diagnosis_id = d.diagnosis_id
GROUP  BY sm.report_id, sm.age, sm.gender, sm.distance, d.diagnosis_label, d.confirmed_by
ORDER  BY sm.distance;
```

Die Sicht `symptom_diagnosis_medication_v` liefert dieselbe Verknüpfung ohne Vektorsuche, eine Zeile je Meldung, Diagnose und Medikament.

## 03 – Laden mit SQLcl

`LOAD` liest in SQLcl nur CSV- und andere Textdateien mit Trennzeichen. Die übrigen Formate lädt das Skript auf diesen Wegen:

| Format | Dateien | Weg |
| --- | --- | --- |
| CSV | `graph`, `casebase`, `stream`, `spatial/road_*` | `LOAD` in die Staging-Tabelle (`ERRORS 0`, `TRUNCATE ON`, UTF-8), dann `INSERT … SELECT` mit expliziten Umwandlungen: Dezimalpunkt, Zeitformat `YYYY-MM-DD HH24:MI:SS`, `true`/`false` und `J`/`N` nach `BOOLEAN`, Punktgeometrie aus `lon`, `lat` |
| NDJSON | `fhir_bundles_all_patients.ndjson` | Mit den JSON-Dateien in `data/_load/json_chunks.csv` (Layer `fhir_bundles_all_patients`, je Zeile ein Dokument); 03 setzt die Bundles in `stg_json_docs` zusammen. Dann zerlegt `JSON_TABLE` jedes Bundle: Symptommeldungen (Condition `problem-list-item`) mit Alter und Geschlecht aus dem Patient-Eintrag, Diagnosen (Condition `encounter-diagnosis`, `evidence` → Meldung) und Medikamentenempfehlungen (MedicationRequest, `reason` → Diagnose und Meldung). Alles andere bleibt in der Datei |
| JSON, GeoJSON | `symptom_report_jonas.json`, alle `.geojson` | `LOAD` der Ladekopie `data/_load/json_chunks.csv` in `stg_json_chunks`; ein PL/SQL-Block setzt die Stücke je Dokument wieder zusammen (`DBMS_LOB.WRITEAPPEND`) und speichert sie als `JSON` in `stg_json_docs`. Die Symptommeldung und die Features zerlegt `JSON_TABLE`, die Geometrien wandelt `SDO_UTIL.FROM_GEOJSON` um. Die Datei erkennt das Skript an `layer` (`trails`, `osm_roads` …) |

Die Spalte `symptom_reports.report_embedding` bleibt beim Laden leer; sie füllt `05_create_embeddings.sql`. Die Spalte ist als `VECTOR(*, FLOAT32)` angelegt, damit sich das Modell später tauschen lässt.

Vor dem Laden entfernt 03 vorhandene Spatial-Indexe, damit `DELETE` und `INSERT` ohne Indexpflege laufen; 07 legt sie danach neu an. Am Ende sammelt 03 Statistiken.

**Kontrolle:** `LOAD` bricht bei einem Fehler nicht das ganze Skript ab. Darum vergleicht 03 nach jedem Schritt die Zeilenzahlen mit den erwarteten Werten oben im Skript (`DEFINE exp_…`) und bricht bei einer Abweichung ab. Wer den Datensatz ändert, passt dort die Zahlen an.

## 04 – Annotationen

Schema-Annotationen (ab 23ai) sind Name-Wert-Paare an Tabellen und Spalten. Anders als Kommentare sind sie strukturiert und lassen sich gezielt abfragen, etwa von Werkzeugen, von Select AI oder in der Demo selbst.

| Ebene | Annotation | Beispiel |
| --- | --- | --- |
| Tabelle | `Display` | Uhren-Stream |
| Tabelle | `Description` | Fitnessuhr von Jonas, alle 5 s ein Messpunkt … |
| Tabelle | `Source` | `data/stream/watch_stream_jonas.csv` |
| Tabelle | `License` | CC0 (synthetisch) bzw. ODbL 1.0, © OpenStreetMap-Mitwirkende |
| Tabelle | `Feature` | Spatial, Streaming |
| Tabelle | `Demo_Step` | 2 |
| Spalte | `Display` | Messzeit |
| Spalte | `Description` | Ereigniszeit der Messung, Europe/Berlin; danach wird ausgewertet |
| Spalte | `Unit` | m, km/h, %, 1/min, g, Grad (nur bei Spalten mit Einheit) |

Annotiert werden alle 25 Ziel-Tabellen mit allen Spalten sowie die Staging-Tabellen auf Tabellenebene; `stg_text_lines`, `stg_json_chunks` und `stg_json_docs` auch mit ihren Spalten. Das Skript entfernt in Schritt 1 zuerst **alle** vorhandenen Annotationen im Schema (Tabellen, Spalten, Views, Materialized Views, Indexe; laut `USER_ANNOTATIONS_USAGE`) und setzt sie in Schritt 2 neu, ist also wiederholbar. Ausgenommen sind über Domains geerbte Annotationen, die Objekte des RDF-Netzwerks und `STG_RDF_TRIPLES` (Annotationen aus 08). Spalten-Annotationen von Views lassen sich nur mit `CREATE OR REPLACE VIEW` ändern und erscheinen als WARNUNG. Eine Abfrage zum Nachsehen:

```sql
SELECT object_name, column_name,
       JSON_OBJECTAGG(annotation_name VALUE annotation_value) AS annotations
FROM   user_annotations_usage
WHERE  object_name = 'WATCH_STREAM'
GROUP  BY object_name, column_name;
```

## 05 – Embeddings

Grundlage ist der Blogpost [Getting started with vectors in 23ai](https://blogs.oracle.com/coretec/getting-started-with-vectors-in-23ai).

| Schritt | Umsetzung |
| --- | --- |
| Modell | all-MiniLM-L12-v2 als ONNX-Datei mit Tokenizer und Nachverarbeitung, von Oracle Machine Learning im Objektspeicher bereitgestellt; 384 Dimensionen, FLOAT32 |
| Laden | `DBMS_CLOUD.GET_OBJECT` kopiert die Datei nach `DATA_PUMP_DIR` (auf Autonomous AI Database gibt es kein eigenes Server-Verzeichnis wie `DM_DUMP` im Blog), dann `DBMS_VECTOR.LOAD_ONNX_MODEL` als Modell `ALL_MINILM_L12_V2`; danach wird die Datei gelöscht |
| Prüfen | `USER_MINING_MODELS` (EMBEDDING, ONNX) und `ORA$ONNXTARGET` in `USER_MINING_MODEL_ATTRIBUTES` (`VECTOR(384,FLOAT32)`) |
| Füllen | `UPDATE symptom_reports SET report_embedding = VECTOR_EMBEDDING(ALL_MINILM_L12_V2 USING report_text AS data)` für alle Zeilen ohne Embedding; danach Kontrolle, dass keine Zeile fehlt |
| Probe | Die fünf Meldungen mit der kleinsten `VECTOR_DISTANCE(…, COSINE)` zu Jonas' Meldung, mit Diagnose |

- **Wiederholen:** Ein zweiter Lauf berechnet nur fehlende Embeddings. Mit `DEFINE rebuild = Y` lädt das Skript das Modell neu und berechnet alles neu.
- **Modelldatei:** Der Link (`DEFINE model_uri`) ist ein Pre-Authenticated Request von Oracle. Läuft er ab, den aktuellen Link aus dem OML-Blog nehmen oder die Datei in einen eigenen Bucket legen.
- **Sprache:** all-MiniLM-L12-v2 ist vor allem auf Englisch trainiert, die Meldungen sind deutsch. Die Rangfolge vor dem Vortrag prüfen (offener Punkt der Storyline). Für ein mehrsprachiges Modell nur `model_name`, `onnx_file` und `model_uri` ändern und mit `rebuild = Y` laufen lassen.
- **Kein Vektorindex:** Bei 1.459 Zeilen ist die exakte Suche schnell genug. Der Blog nennt IVF und HNSW für größere Datenmengen.

## 06 – Volltextindex

`SYMPTOM_REPORTS_TXT_IDX` ist ein CONTEXT-Index (Oracle Text) auf `symptom_reports.report_text` mit eigenen Einstellungen für deutsche Texte:

| Teil | Einstellung | Wirkung |
| --- | --- | --- |
| Lexer `SYMPTOM_LEXER` | `BASIC_LEXER`, `COMPOSITE GERMAN`, `ALTERNATE_SPELLING GERMAN`, `MIXED_CASE NO` | Komposita werden zerlegt („Knie“ findet „Kniekehle“), „ae“ gilt wie „ä“, Groß-/Kleinschreibung egal. Der Bindestrich ist kein `PRINTJOINS`, „Plopp-Geräusch“ wird also zu „Plopp“ und „Geräusch“ |
| Wordlist `SYMPTOM_WORDLIST` | `STEMMER GERMAN`, `FUZZY_MATCH GERMAN`, Präfixindex 3–8 Zeichen | `$verdrehen` findet „verdreht“, `?Plop` findet „Plopp“, `Schwell%` ist schnell |
| Stoplist `SYMPTOM_STOPLIST` | häufige deutsche Füllwörter | „kein“ und „nicht“ bleiben suchbar |
| Synchronisierung | `SYNC (ON COMMIT)` | neue Meldungen sind nach dem Commit suchbar |

Das Skript prüft danach Status und Fehler des Index und zeigt Probeabfragen mit `CONTAINS` und `SCORE`. Das deckt den offenen Punkt der Storyline „deutschen Lexer mit Plopp-Geräusch testen“ ab. Ein erneuter Lauf entfernt Index und Präferenzen und legt sie neu an.

## 07 – Spatial-Metadaten und Spatial-Indexe

Das Skript folgt den Empfehlungen für Spatial-Indexe:

| Schritt | Umsetzung |
| --- | --- |
| Erst laden, dann indexieren | 03 entfernt vorhandene Spatial-Indexe vor dem Laden, 07 legt sie danach an |
| Metadaten vor dem Index | `DELETE` und `INSERT` in `USER_SDO_GEOM_METADATA` (die View erlaubt kein `MERGE`, ORA-38106) für alle 15 Geometriespalten: Länge –180 bis 180, Breite –90 bis 90, SRID 4326, Toleranz 0,05 m (bei geodätischen Daten in Metern) |
| Geometrien prüfen | je Tabelle Zeilen, leere Geometrien, ungültige Geometrien (`SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT`), falscher Geometrietyp und falsche SRID. Eine falsche SRID stoppt das Skript, ein falscher Typ nur bei Punkttabellen, weil dort `CREATE INDEX` mit `layer_gtype=POINT` sonst scheitert; bei anderen Tabellen erscheint er als WARNING |
| Ungültige Geometrien protokollieren | Schritt 5: jede ungültige Geometrie aller Tabellen mit Fehlercode, Meldung und Kontext in `GEOMETRY_ERRORS` (bei jedem Lauf neu angelegt) |
| Ungültige Geometrien reparieren | Schritt 5a: `SDO_UTIL.RECTIFY_GEOMETRY`, Rückschreiben nur, wenn die reparierte Geometrie gültig ist; danach verschwindet sie aus `GEOMETRY_ERRORS`. Nicht reparierbare Geometrien (ORA-13199) bleiben als WARNING stehen |
| Indextyp | `MDSYS.SPATIAL_INDEX_V2`, Name `<TABELLE>_SIDX` |
| Erwarteter Geometrietyp je Tabelle | `POINT` für alle Punkttabellen (auch die Streams), `LINE` für `trail_segments`, `MULTILINE` für `osm_roads` und `osm_trails`, `POLYGON` für `zones`, `MULTIPOLYGON` für `osm_boundaries`; `osm_parking` und `osm_pois` sind gemischt. Der Typ wird für alle Tabellen geprüft, als Indexparameter aber nur bei Punkttabellen gesetzt. Linien, Flächen und gemischte Tabellen bekommen einen Spatial-Index ohne Parameter |
| Punkttabellen | als einzige mit Indexparametern: `layer_gtype=POINT cbtree_index=true` (Composite-B-Tree statt R-Tree, kleiner und schneller für Punkte) |
| Parallel | `PARALLEL 4` ab 100.000 Zeilen (`DEFINE parallel_min_rows`, `parallel_degree`); im Datensatz erreicht das keine Tabelle |
| Status und Statistik | alle Indexe müssen `VALID` sein; danach `DBMS_STATS.GATHER_TABLE_STATS` mit `cascade => TRUE` |

Mit `DEFINE rebuild = Y` legt das Skript alle Spatial-Indexe neu an. Die Liste der Tabellen und Geometrietypen steht an einer Stelle im Skript.

## 08 – RDF-Netzwerk und RDF-Modell

Aufbau wie in der Vorlage [optional_example_family_rdf_knowledge_graph.sql](https://github.com/karinpatenge/events/blob/main/2025/06_AOUG/scripts/optional_example_family_rdf_knowledge_graph.sql): Netzwerk, Graphen, Regelbasis. Verwendet werden die Namen ab 23ai (`CREATE_RDF_NETWORK` statt `CREATE_SEM_NETWORK`, `CREATE_RDF_GRAPH` statt `CREATE_SEM_MODEL`).

| Objekt | Inhalt |
| --- | --- |
| Netzwerk `RDF_NETWORK` | auf Autonomous AI Database das einzige mögliche Netzwerk; schema-privat, Eigentümer `DOAG2026`, Tablespace `DATA` |
| `stg_rdf_triples` | Staging-Tabelle für `SEM_APIS.BULK_LOAD_RDF_GRAPH`, mit Annotationen |
| Graph `KNEE_KG` | Knie-Wissensgraph (Anatomie, Befunde, Verletzungsmuster, Jonas' Meldung) |
| Graph `FMA` | Foundational Model of Anatomy als gemeinsames Vokabular |
| Regelbasis `KNEE_RB` | drei Regeln: Befund ist starker Indikator eines Musters (`kg:showsIndicatorOf`), Befund spricht dagegen (`kg:showsCounterIndicatorOf`), Mechanismus passt (`kg:matchesMechanismOf`) |

Graphen, Inferenz und Regelbasis werden bei jedem Lauf entfernt und leer neu angelegt; das Netzwerk bleibt. `DEFINE rebuild = Y` legt auch das Netzwerk neu an.

Name und Eigentümer des Netzwerks stehen in 08, 09a, 09b und 98 als `DEFINE network_name = RDF_NETWORK` und `DEFINE network_owner = DOAG2026` (in 98: `&demo_user`), in 99 als `DEFINE network_name`. 08 und 09 laufen nur, wenn der angemeldete Benutzer der Netzwerk-Eigentümer ist.

**Nativer Datentyp `SDO_RDF_TRIPLE_S`.** Die Vorlage bindet eine eigene Tabelle (`FAMILY_TPL` mit Spalte `triple SDO_RDF_TRIPLE_S`) an das Modell. Auf Autonomous AI Database gibt es nur das Netzwerk `RDF_NETWORK`, und es ist schema-privat. In einem schema-privaten Netzwerk müssen `table_name` und `column_name` in `SEM_APIS.CREATE_RDF_GRAPH` aber `NULL` sein. Deshalb steht in 02 keine solche Tabelle. Stattdessen legt `CREATE_RDF_GRAPH` je Graph die änderbare View `RDF_NETWORK#RDFT_<GRAPH>` an. Ihre Spalte `TRIPLE` hat den Typ `SDO_RDF_TRIPLE_S`, und 09 lädt `KNEE_KG` mit dem Konstruktor `SDO_RDF_TRIPLE_S(…)` über diese View.

## 09a und 09b – RDF-Daten laden

Das Laden ist zweigeteilt, damit der kleine Knie-Wissensgraph schnell neu geladen werden kann, ohne die FMA (mehrere Minuten) erneut zu laden.

| Skript | Schritt | Umsetzung |
| --- | --- | --- |
| 09a | Neu anlegen | Graph-Sammlung `KNEE_FMA_VM`, Inferenz `KNEE_KG_RIX` und Graph `KNEE_KG` entfernen, `KNEE_KG` leer neu anlegen |
| 09a | `KNEE_KG` | `LOAD` der Ladekopie `data/_load/knee_kg_nt.csv` zeilenweise in `stg_text_lines`, Aufteilung in Subjekt, Prädikat, Objekt per regulärem Ausdruck, Umlaute mit `SEM_APIS.ESCAPE_RDF_TERM` escaped, dann `INSERT INTO rdf_network#rdft_knee_kg VALUES (SDO_RDF_TRIPLE_S('KNEE_KG', s, p, o, 'DOAG2026', 'RDF_NETWORK'))` je Triple (353) |
| 09a | Inferenz `KNEE_KG_RIX` | `SEM_APIS.CREATE_ENTAILMENT` über `KNEE_KG` mit `OWLPRIME` (Unterklassen, transitives `kg:partOf`) und `KNEE_RB`. Die FMA bleibt außen vor; ihre Klassenhierarchie würde die Inferenz stark vergrößern |
| 09a | Probeabfragen | starke Indikatoren je Muster in Jonas' Meldung (ACL 3, Verstauchung 1), abgeleitete Aussagen aus `KNEE_RB` |
| 09a | Prüfung der Inferenz (5c–5e) | Status `VALID` und Eingaben von `KNEE_KG_RIX`; Tripel je Prädikat ohne und mit Inferenz (9 abgeleitet: 2 × `rdfs:subClassOf` aus `OWLPRIME`, 7 aus `KNEE_RB`); Beispiel: Bänder des Kniegelenks ohne Inferenz 4, mit Inferenz 6 (vorderes und hinteres Kreuzband über die Unterklasse Kreuzband) |
| 09b | Neu anlegen | Graph-Sammlung `KNEE_FMA_VM` und Graph `FMA` entfernen, `FMA` leer neu anlegen |
| 09b | `FMA` | `LOAD` der Ladekopie `data/_load/fma_nt.csv`, gleiche Aufteilung, dann `SEM_APIS.BULK_LOAD_RDF_GRAPH` mit `PARSE MBV_METHOD=SHADOW` (612.982 Triples; Bulk Load ist für große Mengen der schnellste Weg) |
| 09b | Textindex | `SEM_APIS.ADD_DATATYPE_INDEX('http://xmlns.oracle.com/rdf/text')` für `orardf:textContains` (abschaltbar mit `DEFINE text_index = N`); der Index liegt auf der Wertetabelle des Netzwerks und deckt beide Graphen ab |
| 09b | Probeabfragen | Triples je Graph, vom ACL-Muster über das Kreuzband zur FMA-ID, Befund mit dem Synonym „Plopp“ |
| beide | Graph-Sammlung `KNEE_FMA_VM` | `KNEE_KG`, `FMA` und `KNEE_KG_RIX` in einer Sicht für Abfragen über beide Graphen. Sie braucht beide Graphen: Das Skript, das als zweites läuft, legt sie an |
| beide | Statistik | `SEM_PERF.GATHER_STATS` |

Beide Skripte prüfen vorher, dass das Netzwerk aus 08 existiert (09a zusätzlich die Regelbasis `KNEE_RB`), und sind unabhängig voneinander wiederholbar: Jedes legt seinen Graphen leer neu an, der andere bleibt. Nur 08 setzt alles zurück. Die Probeabfragen mit `SEM_MATCH` brauchen Oracle Java; ohne Java melden sie einen Fehler, ohne das Skript abzubrechen.

## 10 – Property Graph

`10_create_property_graph.sql` legt den SQL Property Graph `CARE_NETWORK` an (`CREATE OR REPLACE`, wiederholbar). Er kopiert keine Daten, sondern beschreibt nur, welche Tabellen Knoten und Kanten sind.

| Art | Label | Tabelle | Richtung |
| --- | --- | --- | --- |
| Knoten | `patient` | `patients` | |
| Knoten | `provider` | `providers` (ohne `geom`: `SDO_GEOMETRY` ist als Eigenschaft nicht erlaubt) | |
| Knoten | `device` | `devices` | |
| Knoten | `slot` | `appointment_slots` | |
| Kante | `care_relation` | `patient_provider_relations` | Patient → Praxis |
| Kante | `provider_relation` | `provider_relations` | Praxis → Praxis (`ueberweist_an`, `kooperiert_mit`) |
| Kante | `operates` | `devices` (zweiter Alias) | Praxis → Gerät |
| Kante | `offers` | `appointment_slots` (zweiter Alias) | Praxis → Termin |

Der Graph läuft im `TRUSTED MODE` (Standard): `devices` und `appointment_slots` sind zugleich Knoten- und Kantentabelle, und ihr Zielschlüssel ist der eigene Primärschlüssel, kein Fremdschlüssel. `ENFORCED MODE` verlangt dagegen für jeden Kantenschlüssel einen Fremdschlüssel. Die Schlüssel sind trotzdem eindeutig, weil es die Primärschlüssel sind. Nach Änderungen an den Tabellen: `ALTER PROPERTY GRAPH care_network COMPILE`. Die Probeabfrage am Ende zeigt Jonas' Überweisungswege bis zum MRT.

## 11a–11i – Analyse-Notebooks

Die Analysen der Demo liegen als SQL Notebooks (`.sqlnb`) vor und laufen in SQL Developer for VS Code als Demo-Benutzer. Jede Abfrage hat davor einen Markdown-Absatz mit Frage, Erklärung und dem Ergebnis des Laufs vom 10.11.2026 (**Result**). Die Notebooks folgen der Storyline:

| Notebook | Demo-Schritt | Inhalt |
| --- | --- | --- |
| `11_demo_live_de.sqlnb`, `11_demo_live_en.sqlnb` | Demo | Die Live-Abfragen aus 11a–11h in Vortragsreihenfolge: 11a §4 · 11b §5, §6 · 11c §3, §8 · 11e §3, §5 · 11f §4, §8 · 11g §2, §3 · 11h. Legt nichts an; Duality View, Hybrid-Index und Routen-Cache müssen vorher existieren |
| `11a_json_patient_record.sqlnb` | 1 JSON | FHIR-Bundle mit Punktnotation, `JSON_TABLE`, Pfadfilter, `JSON_EXISTS`, App-Meldung mit GeoJSON → `SDO_GEOMETRY`, JSON Schema, Duality View `patient_care_dv` (wird angelegt) |
| `11b_stream_watch_events.sqlnb` | 2 Streaming | Mess- und Ankunftszeit, Funkloch, Geschwindigkeit und Steigung, `MATCH_RECOGNIZE` (Wandern → Sturz → Stillstand → Humpeln), Zuordnung zum Wegsegment mit `SDO_NN` |
| `11c_text_vector_search.sqlnb` | 3 Volltext → Vektor | `CONTAINS`, `SCORE`, `CTX_DOC.SNIPPET`, Fuzzy/Stamm/`NEAR`, Ausführungsplan; `VECTOR_DISTANCE`, `VECTOR_EMBEDDING` zur Abfragezeit, beide Listen nebeneinander |
| `11d_hybrid_search.sqlnb` | 3 Theorie | Hybrid Vector Index auf `case_notes` und `DBMS_HYBRID_VECTOR.SEARCH`, Chunking mit `DBMS_VECTOR_CHAIN`, `DBMS_SEARCH`; legt zwei zusätzliche Indexe an (Aufräumen am Ende des Notebooks) |
| `11e_rdf_knowledge_graph.sqlnb` | 4 RDF | `SEM_MATCH`: Muster prüfen, Regeln aus `KNEE_RB`, Erklärung bis FMA 44614, Synonyme aus dem Graphen für `CONTAINS`, Join mit `diagnoses` |
| `11f_property_graph_location.sqlnb` | 5 Property Graph und Ort | `GRAPH_TABLE` vom Hausarzt bis zum MRT-Termin, Pfade variabler Länge, Filter auf die OSM-Stadtgrenzen, Fahrzeit mit `ELOC_ROUTE` |
| `11g_spatial_pickup_route.sqlnb` | 6 Spatial | nächster befahrbarer Parkplatz, Geofence-Ereignis aus zwei Streams, Route als GeoJSON, Tabelle `route_cache` als Rückfallebene, Plan B: Notaufnahmen aus OSM mit JSON-Filter |
| `11h_finale_all_in_one.sqlnb` | 7 Finale | eine `SELECT`-Anweisung mit allen Datenarten: JSON, Stream, Spatial, Volltext, Vektor, RDF, Property Graph, Routing |
| `11i_feature_impact_evaluation.sqlnb` | Muster und Ausblick | Auswertung: Wie genau ist die Diagnose mit Vektor, Volltext, Ontologie, GraphRAG und Spatial, allein und kombiniert? Testmenge sind die rund 360 FHIR-Knie-Meldungen mit Diagnose; neun Methoden (M0–M8), Genauigkeit, Abdeckung, Trefferquote für Kreuzbandrupturen; Spatial auch für die Umsetzbarkeit der Empfehlung; optional GraphRAG mit LLM (`DBMS_VECTOR_CHAIN.UTL_TO_GENERATE_TEXT`, Credential `OCI_GENAI_CRED` als Platzhalter). Legt Arbeitstabellen `EVAL_*` an. Ergebnis des Laufs: Vektor allein 50,6 %, alle Bausteine kombiniert 70,8 %; Kreuzbandrupturen erkannt 30,0 % bzw. 72,5 % |

Voraussetzungen: `01_run_all.sql` (inklusive 10), Oracle Java für `SEM_MATCH`, `SDO_GCDR.ELOC_GRANT_ACCESS` für das Routing. 11i braucht die mit `data/_generator/knee_cases.py` erzeugten Daten; die Daten sind synthetisch, die Auswertung zeigt also, wie sich die Bausteine ergänzen, und ist kein Beleg für echte medizinische Daten. Für den optionalen LLM-Teil in 11i: OCI-Generative-AI-Credential und Netzwerkzugriff (ACL) für den Demo-Benutzer. Zeitbezug der Geschichte: Suche ab Montag, 16.11.2026, 12:00 Uhr; das MRT muss vor Dienstag, 12:00 Uhr liegen. Netzwerkeigentümer `DOAG2026` und Netzwerk `RDF_NETWORK` stehen in den `SEM_MATCH`-Aufrufen fest.

## 98 und 99 – Aufräumen

`98_cleanup.sql` entfernt im Demo-Schema der Reihe nach:
- Scheduler-Jobs
- das RDF-Netzwerk mit Graphen, Inferenz, Graph-Sammlung, Regelbasis und Textindex (`SEM_APIS.DROP_RDF_NETWORK`, vor den Views, weil die Graph-Views zum Netzwerk gehören)
- Property Graphs
- Views und Duality Views
- Materialized Views
- SODA-Collections (`DBMS_SODA.DROP_COLLECTION`)
- Oracle-Text-Präferenzen
- ONNX-Modelle
- alle Tabellen
- Code-Objekte
- die Spatial-Metadaten

Es erfasst auch Objekte, die spätere Demo-Skripte anlegen. Vorher fragt es nach einer Bestätigung mit `JA`.

`99_drop_user.sql` löscht danach als ADMIN den Benutzer. Es verweigert den Lauf, solange das RDF-Netzwerk noch existiert oder der Benutzer angemeldet ist.

## Noch nicht gegen eine Datenbank getestet

Die Skripte sind bisher nicht gegen eine echte Instanz gelaufen. Beim ersten Lauf besonders auf diese Punkte achten:
- **JSON-Stücke:** `LOAD` mit dem Backtick als Trennzeichen und das Zusammensetzen von 15.550 Dokumenten; das größte (ein Wanderweg in `osm_trails`) hat 640.296 Zeichen.
- **Lange Zeilen:** `LOAD` in `VARCHAR2(32767)`. Die längste FHIR-Zeile hat 5.751 Zeichen.
- **RDF-Option `PARSE`:** sie ist in `SEM_APIS.BULK_LOAD_RDF_GRAPH` gesetzt, weil die Triples nicht über `SEM_APIS.LOAD_INTO_STAGING_TABLE` geprüft wurden.
- **`SDO_RDF_TRIPLE_S` über die Graph-View:** `INSERT INTO rdf_network#rdft_knee_kg VALUES (SDO_RDF_TRIPLE_S(…))` folgt dem Beispiel der Dokumentation, ist hier aber noch nicht gelaufen.
- **Abgekündigte Namen:** `SEM_APIS.CREATE_ENTAILMENT` und `DROP_ENTAILMENT` (wie in der Vorlage) sollen später durch `CREATE_INFERRED_GRAPH` und `DROP_INFERRED_GRAPH` ersetzt werden; in 26ai funktionieren beide.
- **Eigene Regeln:** die drei Regeln in `KNEE_RB` und die Probeabfrage 7c prüfen, sobald Oracle Java eingeschaltet ist.
- **`SEM_PERF.GATHER_STATS`** mit `network_owner`/`network_name`: schlägt der Aufruf fehl, gibt 09a bzw. 09b nur eine WARNUNG aus.
- **Spatial-Indexe:** `layer_gtype=POINT cbtree_index=true` auf den geodätischen Punkttabellen beim ersten Lauf prüfen.
- **Zusatzrechte in 00:** Je nach Instanz kann eines davon eine WARNUNG liefern.
