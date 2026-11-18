# Leitfaden für Teilnehmende: Sicher Radfahren in Nürnberg

**Spatial AI in Python: Unlocking Machine Learning for Geospatial Intelligence**
DOAG 2026, Nürnberg · Hands-on-Teil · 45 Minuten (plus 5 Minuten für den optionalen Teil in Spatial Studio)

Willkommen zum Hands-on-Teil. Sie müssen weder Data Scientist noch GIS-Fachleute sein: Das Notebook erklärt jeden Schritt, und Sie führen vor allem Code aus, der schon geschrieben ist. Dieser Leitfaden sagt Ihnen, was zu tun ist, worauf Sie achten sollten und was die einzelnen Methoden bedeuten.

> **Sprache:** Im deutschen Notebook sind Titel, Kommentare und Erklärungen auf Deutsch. Der Code und seine Ausgaben sind auf Englisch und werden hier im Original zitiert.

---

## 1. Ihre Aufgabe

**Lena** ist Mobilitätsplanerin der Stadt Nürnberg (eine erfundene Persona). Die Stadt möchte, dass mehr Menschen Rad fahren, aber das Budget für sicherere Kreuzungen und Radwege ist begrenzt. Ihre Abteilungsleitung fragt: *„Wo fangen wir an?“*

Sie helfen Lena mit offenen Daten und Spatial AI in der Datenbank. Die Antworten erarbeiten Sie in fünf Schritten:

1. **Wo häufen sich Radunfälle?** → dichtebasiertes Clustering mit DBSCAN
2. **Ist das mehr als Zufall?** → Hotspot-Test mit Moran's I und LISA
3. **Gibt es Radinfrastruktur in der Nähe?** → Nachbarschaftsanalyse
4. **Welche Schulen und Kindergärten liegen in Unfall-Hotspots?** → räumlicher Join und Puffer
5. **Wo gibt es mehr Radunfälle, als Verkehr und Umgebung erklären?** → räumliche Regression mit OLS und GWR

Am Ende hat Lena eine Rangliste mit fünf Orten und Karten, die sie dem Stadtrat zeigen kann.

![Ablauf von Szenario 1](../media/s1_workshop_story_de.png)

### Die Daten

Alle Daten sind offene Daten:

- **Unfälle mit Personenschaden, 2020–2025** – Unfallatlas der Statistischen Ämter des Bundes und der Länder. Etwa 11.000 Unfälle in Nürnberg, davon etwa 4.400 mit Radbeteiligung.
- **Einwohner nach Altersklassen, 100-m-Gitter** – Zensus 2022 der Statistischen Ämter des Bundes und der Länder, zugeschnitten auf Bayern.
- **Radinfrastruktur, Schulen, Kindergärten, Universitäten und Studentenwohnheime** – OpenStreetMap.

Die Daten bleiben in der Oracle Autonomous AI Database. Python läuft neben den Daten, und die Ergebnisse werden als Tabellen zurückgeschrieben.

![Die Daten bleiben in der Datenbank – Python kommt zu den Daten](../media/s1_workshop_architecture_de.png)

---

## 2. Was Sie brauchen

- **Eine Workshop-Umgebung:** eine Autonomous AI Database mit OML Notebooks. Abschnitt 5 nennt die Möglichkeiten; die Workshop-Leitenden sagen Ihnen, welche Sie verwenden.
- **Einen Workshop-Benutzer:** aus Ihrer LiveLabs-Umgebung oder von Ihnen selbst in Ihrer eigenen Datenbank angelegt.

Diese Angaben erhalten Sie von den Workshop-Leitenden:

- **Die Notebook-Datei** `Sicher_Radfahren_in_Nürnberg_de.dsnb`.
- **Die PAR-URL:** ein Link, über den das Notebook die Datendateien aus Object Storage liest. Er endet mit `/o/`.

Sie brauchen auf Ihrem Laptop nur einen Webbrowser.

---

## 3. Zeitplan

| Zeit | Was Sie tun | Wo |
|---|---|---|
| 0–3 | Anmelden, Notebook importieren, Parameter setzen | OML Notebooks, Teil 1 |
| 3–10 | Offene Daten in die Datenbank laden | Teil 2 |
| 10–16 | Unfälle erkunden: Unfalltypen, Zeit und Ort | Teil 3 |
| 16–21 | Unfall-Cluster mit DBSCAN finden | Teil 4 |
| 21–27 | Auf Hotspots testen mit Moran's I und LISA | Teil 5 |
| 27–31 | Entfernung zur Radinfrastruktur prüfen | Teil 6 |
| 31–35 | Schulen und Kindergärten in Hotspots | Teil 7 |
| 35–42 | Mehr Radunfälle als erwartet? | Teil 8 |
| 42–43 | Ergebnisse speichern | Teil 9 |
| 43–48 | Optional: Ergebnisse auf eine Karte bringen | Spatial Studio |

Der Zeitplan ist knapp:
- **Try it**-Absätze sind optional. Überspringen Sie sie, wenn Sie im Verzug sind.
- **Spatial Studio ist optional:** Es steht nur in Ihrer eigenen Autonomous AI Database zur Verfügung (Option 2 in Abschnitt 5), nicht in LiveLabs.
- **Die Zeit reicht nicht?** Ihre Tabellen bleiben in Ihrem Schema. Den Teil in Spatial Studio können Sie also nach dem Workshop machen.

---

## 4. Arbeiten mit dem Notebook

- **Von oben nach unten:** Führen Sie die Absätze einzeln aus. Die Absätze bauen aufeinander auf: Wenn Sie einen überspringen, fehlen dem nächsten seine Variablen.
- **Den Text lesen:** Die Textabsätze erklären, was passiert und warum.
- **Vergleichen:** Nach jedem Code-Absatz zeigt ein Absatz **Erwartetes Ergebnis**, was Sie sehen sollten und was es bedeutet.
- **Erneut ausführen:** Jeder Absatz kann erneut ausgeführt werden. Tabellen werden ersetzt, nicht ergänzt.
- **Zufallszahlen:** Einige Tests verwenden zufällige Permutationen. Einzelne Werte können daher leicht von den erwarteten Ergebnissen abweichen.

---

## 5. Schritt für Schritt

### Bevor Sie beginnen – Ihre Workshop-Umgebung

Sie brauchen eine Oracle Autonomous AI Database mit OML Notebooks. Es gibt zwei Möglichkeiten:

1. **Oracle LiveLabs (empfohlen für den Präsenz-Workshop auf der DOAG Konferenz 2026):** Starten Sie mit Ihrem Oracle-Konto den LiveLabs-Workshop [Get started with Oracle Machine Learning Fundamentals on Oracle Autonomous AI Database](https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?clear=RR,180&wid=922). LiveLabs stellt eine Autonomous AI Database mit OML Notebooks einschließlich Python bereit, aber ohne Spatial Studio. Die ersten Labs dieses Workshops erklären, wie Sie sich anmelden.
2. **Oracle Autonomous AI Database 26ai Free im eigenen OCI-Tenant:** eine Always-Free-Datenbank in Ihrem eigenen Oracle-Cloud-Konto, mit Spatial Studio für den optionalen Kartenteil. Legen Sie den Workshop-Benutzer als ADMIN mit `scripts/sql/00_create_user.sql` an.

Die Workshop-Leitenden sagen Ihnen vorab, welche Option Sie verwenden. Wenn Sie Ihre eigene Autonomous AI Database verwenden (Option 2), legen Sie Ihren Workshop-Benutzer vor dem Workshop mit `scripts/sql/00_create_user.sql` an, damit Sie gleich loslegen können.

### Teil 1 – Anmelden und Notebook importieren (3 Min.)

1. Öffnen Sie **Oracle Machine Learning** und melden Sie sich mit Ihrem Workshop-Benutzer an.
2. Öffnen Sie **Notebooks**, wählen Sie **Import** und wählen Sie die Datei `Sicher_Radfahren_in_Nürnberg_de.dsnb`.
3. Öffnen Sie das Notebook. Ersetzen Sie im Absatz **Workshop-Parameter setzen** den Platzhalter in `PAR_URL` durch die PAR-URL der Workshop-Leitenden.
4. Führen Sie **Bibliotheken importieren** und **Workshop-Parameter setzen** aus.

✅ **Kontrollpunkt:** `Connected to the database: True` und `Parameters set.`

### Teil 2 – Offene Daten laden (7 Min.)

Sie lesen die Originaldateien aus Object Storage, behalten, was in oder um Nürnberg liegt, und schreiben vier Tabellen in Ihr Schema. Die größten Dateien sind die Unfalldateien mit etwa 40 MB pro Jahr.

✅ **Kontrollpunkt:** 11.002 Unfälle, 3.638 Radwege, 11.780 Zensus-Zellen, 516 Schulen, Kindergärten und andere Bildungseinrichtungen.

**Achten Sie darauf:** Der Code verwendet ganz normales `pandas` und `geopandas`, läuft aber in der Datenbankumgebung. Die Daten gehen nie über Ihren Laptop.

### Teil 3 – Unfälle erkunden (6 Min.)

Sie verschaffen sich ein erstes Bild der Radunfälle: auf einer Karte, nach Unfalltyp und nach Zeit und Ort.

✅ **Kontrollpunkt:** 4.387 Radunfälle.

**Achten Sie darauf:**
- **Häufigster Unfalltyp:** Fahrunfälle, bei denen Radfahrende ohne Zutun anderer die Kontrolle verlieren, sind die größte und schwerste Gruppe.
- **Über die Jahre:** Die Radunfälle gingen von 801 im Jahr 2022 auf 675 im Jahr 2025 zurück.
- **Über Woche und Tag:** Die meisten Unfälle passieren im Sommer, an Werktagen und im Berufsverkehr.

**Frage:** Ist Radfahren sicherer geworden, oder sind weniger Menschen Rad gefahren? Welche Daten bräuchten Sie, um das zu entscheiden?

### Teil 4 – Unfall-Cluster finden (5 Min.)

DBSCAN sucht Orte, an denen sich mindestens 12 Unfälle innerhalb von 50 m ereignet haben.

✅ **Kontrollpunkt:** 18 Cluster mit 277 Radunfällen.

**Achten Sie darauf:** Die meisten Unfälle liegen in keinem Cluster. **Try it:** Vergleichen Sie verschiedene Werte für `min_samples`. Welchen würden Sie dem Stadtrat erklären?

### Teil 5 – Ist das mehr als Zufall? (6 Min.)

Sie zählen die Radunfälle in Hexagonen und testen, ob stark belastete Hexagone häufiger nebeneinander liegen, als es der Zufall erwarten lässt.

✅ **Kontrollpunkt:** Moran's I etwa 0,44 und etwa 219 Hotspot-Hexagone.

**Achten Sie darauf:** Der große Hotspot umfasst die Altstadt und den Ring, wo die meisten Menschen Rad fahren. Ein Hotspot zeigt, wo sich Unfälle häufen, nicht, dass Radfahren dort gefährlicher ist.

### Teil 6 – Gibt es Radinfrastruktur in der Nähe? (4 Min.)

Für jeden Radunfall messen Sie die Entfernung zum nächsten Radweg und bringen die Cluster in eine Rangfolge.

✅ **Kontrollpunkt:** Rang 1 ist die Schnieglinger Straße mit 29 Unfällen.

**Achten Sie auf die Überraschung:** Die meisten Cluster liegen nahe an vorhandenen Radwegen, und Abbiegeunfälle sind dort häufiger. Ein fehlender Radweg ist also meist nicht die Erklärung; Kreuzungen, an denen Radwege auf abbiegenden Verkehr treffen, sind ein wichtiger Faktor. Welcher Cluster ist die Ausnahme?

### Teil 7 – Schulen und Kindergärten in Hotspots (4 Min.)

Sie verknüpfen die Bildungseinrichtungen mit den Hotspots und zählen die Radunfälle im Umkreis von 150 m um jede Einrichtung.

✅ **Kontrollpunkt:** Etwa ein Viertel der Schulen und Kindergärten liegt in einem Hotspot-Hexagon.

**Achten Sie darauf:** Der Unfallatlas erfasst nicht das Alter der Beteiligten. Die Ergebnisse zeigen Unfälle *in der Nähe* von Schulen, nicht Unfälle *von* Kindern.

### Teil 8 – Mehr Radunfälle als erwartet? (7 Min.)

Ein Regressionsmodell schätzt, wie viele Radunfälle ein Hexagon angesichts seines Verkehrs (Unfälle ohne Radbeteiligung als Ersatzgröße), seiner Radwege und seiner jungen Einwohner hätte. Dann suchen Sie Hexagone mit deutlich mehr Unfällen als erwartet.

✅ **Kontrollpunkt:** OLS erklärt etwa 58 % der Unterschiede zwischen den Hexagonen (R² ≈ 0,58). Die Schnieglinger Straße hat 31 Radunfälle, wo etwa 8 erwartet werden.

**Achten Sie darauf:**
- **OLS und GWR:** GWR findet für jeden Ort eine eigene Regel und erklärt mehr.
- **Ein neuer Ort:** ein Hexagon im Osten, das LISA nicht markiert hat.

Das Training von GWR kann bis zu einer Minute dauern.

### Teil 9 – Ergebnisse speichern (1 Min.)

Das Notebook schreibt vier Ergebnistabellen, bereit für Spatial Studio:

| Tabelle | Inhalt |
|---|---|
| `NUE_HOTSPOT_GRID` | Hexagone mit Unfallzahlen, Hotspot-Kennzeichnung und den Ergebnissen der Regression |
| `NUE_CLUSTER_SUMMARY` | ein Punkt je Cluster mit seinem Rang |
| `NUE_BIKE_ACCIDENT_CLUSTERS` | jeder Radunfall mit seinem Cluster und der Entfernung zum nächsten Radweg |
| `NUE_EDUCATION_SURROUNDINGS` | Schulen, Kindergärten und andere Bildungseinrichtungen mit den Unfällen in ihrer Umgebung |

### Zusammenfassung – Lenas Erkenntnisse und Empfehlungen

Das Notebook hat Lenas fünf Fragen beantwortet. Für jede Frage sagt diese Zusammenfassung, was herausgekommen ist, was Lena daraus ableiten kann und was nicht. Der zweite Teil ist so wichtig wie der erste: Der Stadtrat wird fragen, wie sicher sie sich ist.

#### 1. Wo häufen sich Radunfälle? (DBSCAN, Teil 4)

**Ergebnis:** 18 Orte mit jeweils mindestens 12 Radunfällen innerhalb von 50 m in sechs Jahren. Zusammen sind das 277 der 4.387 Radunfälle (6 %). Die Top 5:

| Rang | Ort | Radunfälle | Getötete oder Schwerverletzte | Häufigste Unfalltypen |
|---|---|---|---|---|
| 1 | Schnieglinger Straße | 29 | 6 | Fahrunfall (26) |
| 2 | Am Plärrer | 26 | 4 | Abbiegeunfall (8), Einbiegen/Kreuzen-Unfall (7) |
| 3 | Neutorgraben | 21 | 5 | Fahrunfall (9) |
| 4 | Äußere Bayreuther Straße | 20 | 1 | Einbiegen/Kreuzen-Unfall (10), Abbiegeunfall (8) |
| 5 | Von-der-Tann-Straße | 17 | 3 | Fahr-, Abbiege- und Einbiegen/Kreuzen-Unfall (je 5) |

**Was das bedeutet:** Die meisten Radunfälle verteilen sich über die ganze Stadt. Wenige Orte stechen heraus, und das ist nützlich: Es sind konkrete Orte, an denen sich 12 bis 29 Unfälle gemeinsam untersuchen lassen.

**Was das nicht bedeutet:** Ein Cluster beweist nicht, dass ein Ort gefährlicher ist. Dort kann einfach viel Radverkehr sein. Die Zahl der Cluster hängt außerdem von den beiden Parametern ab, 50 m und 12 Unfälle: Andere Werte ergeben mehr oder weniger Cluster.

#### 2. Ist das mehr als Zufall? (Moran's I und LISA, Teil 5)

**Ergebnis:** Moran's I beträgt 0,44 mit einem p-Wert von etwa 0,001. LISA findet etwa 219 Hotspot-Hexagone in etwa 19 zusammenhängenden Gebieten. Diese Hotspots umfassen 8 % der Hexagone, enthalten aber etwa 42 % der Radunfälle. Das größte Hotspot-Gebiet umfasst die Altstadt und den Ring.

**Was das bedeutet:** Das Muster ist echt. Hexagone mit vielen Radunfällen liegen weit häufiger nebeneinander, als zufällige Schwankungen erklären würden. Lena kann mit Sicherheit sagen, dass sich Radunfälle in bestimmten Teilen der Stadt häufen.

**Was das nicht bedeutet:** Ein Hotspot zeigt, *wo* sich Unfälle häufen, nicht *warum*. In der Altstadt fahren auch die meisten Menschen Rad. Und bei mehr als 2.600 Tests sind einige einzelne Hexagone zufällig „signifikant“; eine Gruppe zusammenhängender Hotspot-Hexagone ist verlässlicher als ein einzelnes.

#### 3. Gibt es Radinfrastruktur in der Nähe? (Teil 6)

**Ergebnis:** 88 % der Unfälle in Clustern ereigneten sich innerhalb von 25 m zu einem Radweg, gegenüber 58 % der übrigen Radunfälle. Abbiegeunfälle sind in Clustern häufiger: 22 % gegenüber 13 %. Die Ausnahme ist Rang 1, die Schnieglinger Straße: Nur 31 % ihrer Unfälle ereigneten sich nahe einem Radweg, und der nächste Radfahrstreifen ist etwa 60 m entfernt.

**Was das bedeutet:** In den meisten Clustern gibt es Radwege, ein fehlender Radweg ist also meist nicht die Erklärung. Kreuzungen, an denen Radwege auf abbiegenden Verkehr treffen, sind ein wichtiger Faktor, weil Abbiegeunfälle in Clustern häufiger sind. Sie sind aber nicht der einzige: An der Schnieglinger Straße und am Neutorgraben sind Fahrunfälle der häufigste Typ. Die Schnieglinger Straße ist außerdem der einzige Ort der Top 5, an dem sich die meisten Unfälle abseits von Radwegen ereignet haben.

**Was das nicht bedeutet:** Die Daten sagen nichts über die Qualität der Radwege aus, etwa ihre Breite, die Trennung vom Autoverkehr oder den Belag. „Innerhalb von 25 m“ heißt nicht, dass die Radfahrenden den Radweg benutzt haben. Und OpenStreetMap ist nur so vollständig, wie die Mitwirkenden es gemacht haben.

#### 4. Welche Schulen und Kindergärten liegen in Unfall-Hotspots? (Teil 7)

**Ergebnis:** 112 von 469 Schulen und Kindergärten (24 %) liegen in einem Hotspot-Hexagon. Zum Vergleich: 28 % der Einwohner unter 18 Jahren und 31 % aller Einwohner leben in Hotspot-Hexagonen. Der Kindergarten St. Michael liegt etwa 130 m vom Cluster auf Rang 1 entfernt.

**Was das bedeutet:** Schulen und Kindergärten liegen nicht häufiger in Hotspots als erwartet. Hotspots, Schulen und Kinder konzentrieren sich alle in der dichten Innenstadt; dass etwa ein Viertel in einem Hotspot liegt, entspricht ungefähr der Verteilung der Kinder. (Die 8 % der Hexagone sind kein fairer Vergleich, weil viele Hexagone dünn besiedelte Gebiete abdecken.) Trotzdem liegt etwa jede vierte Schule und jeder vierte Kindergarten in einem Gebiet mit nachgewiesener Häufung von Radunfällen. Das ist eine nützliche Prioritätenliste, um Schulwege zu prüfen.

**Was das nicht bedeutet:** Der Unfallatlas erfasst nicht das Alter der Beteiligten. Die Ergebnisse zeigen Unfälle *in der Nähe* von Schulen und Kindergärten, nicht Unfälle *von* Kindern. Sie zeigen auch nicht, dass Schulen oder Kindergärten Unfälle verursachen.

#### 5. Wo gibt es mehr Radunfälle, als Verkehr und Umgebung erklären? (OLS und GWR, Teil 8)

**Ergebnis:** Die Regression schätzt, wie viele Radunfälle ein Hexagon angesichts seines Verkehrs, seiner Radwege und seiner jungen Einwohner hätte. Die Schnieglinger Straße hat 31 Radunfälle, wo etwa 8 erwartet werden. Die Schmausenbuckstraße im Osten hat 21, wo etwa 1 erwartet wird, obwohl LISA sie nicht als Hotspot markiert. OLS, mit einer Regel für die ganze Stadt, erklärt 58 % der Unterschiede zwischen den Hexagonen. GWR, mit einer eigenen Regel für jede Nachbarschaft, erklärt etwa 71 %.

**Was das bedeutet:** Das ist der fairste Vergleich im Workshop, weil er berücksichtigt, wie belebt ein Ort ist. Wo es viel mehr Unfälle gibt als erwartet, macht etwas Besonderes an diesem Ort Radfahren gefährlicher. Dass GWR mehr erklärt als OLS, zeigt: Der Zusammenhang zwischen Verkehr und Radunfällen ist nicht überall in der Stadt gleich.

**Was das nicht bedeutet:** Das Modell verwendet Ersatzgrößen, weil es keine offenen Verkehrszählungen gibt: Unfälle ohne Radbeteiligung stehen für den Straßenverkehr, Einwohner zwischen 18 und 29 Jahren für Radfahrende. Ein Überschuss an Unfällen ist deshalb ein Grund, sich den Ort anzusehen, keine Diagnose der Ursache.

#### Empfehlungen, die Lena der Stadtplanung geben kann

Jede Empfehlung nennt die Daten dahinter und sagt, wo die Daten enden.

1. **Zuerst die Schnieglinger Straße untersuchen.** Der Cluster auf Rang 1 hat 29 Radunfälle, 6 davon mit Getöteten oder Schwerverletzten. 26 der 29 sind Fahrunfälle, bei denen Radfahrende ohne Zutun anderer die Kontrolle verloren haben. Nur 31 % ereigneten sich innerhalb von 25 m zu einem Radweg; der nächste Radfahrstreifen ist etwa 60 m entfernt. Das Hexagon dort hat 31 Radunfälle, wo etwa 8 erwartet werden, und der Kindergarten St. Michael liegt etwa 130 m entfernt. *Wo die Daten enden:* Sie zeigen nicht, warum Radfahrende dort die Kontrolle verlieren. Das muss vor Ort geklärt werden, und ob ein Radweg hilft, hängt von der Ursache ab.
2. **Die Konflikte mit abbiegendem und kreuzendem Verkehr in der Äußeren Bayreuther Straße und am Plärrer untersuchen.** In der Äußeren Bayreuther Straße waren 18 von 20 Radunfällen Abbiege- oder Einbiegen/Kreuzen-Unfälle, alle innerhalb von 25 m zu einem Radweg. Am Plärrer sind es 15 von 26, und 88 % ereigneten sich nahe einem Radweg. Hier gibt es die Radwege; die Unfälle passieren dort, wo sie auf abbiegenden und kreuzenden Verkehr treffen. *Wo die Daten enden:* Sie sagen nicht, welche Änderung an der Kreuzung die Unfälle verhindern würde.
3. **Neutorgraben und Von-der-Tann-Straße einzeln betrachten.** Beide haben Radwege in der Nähe (86 % und 100 % der Unfälle innerhalb von 25 m), aber kein Unfalltyp überwiegt. Neutorgraben: 9 von 21 sind Fahrunfälle, der Rest Abbiege-, Längsverkehrs- und sonstige Unfälle; das benachbarte Hexagon an der Johannisstraße hat 27 Radunfälle, wo etwa 5 erwartet werden. Von-der-Tann-Straße: je 5 Fahr-, Abbiege- und Einbiegen/Kreuzen-Unfälle von 17. *Wo die Daten enden:* Gemischte Unfalltypen bedeuten, dass es keine einzelne offensichtliche Ursache gibt.
4. **Die Schmausenbuckstraße vor Ort prüfen.** Ihr Hexagon hat 21 Radunfälle in sechs Jahren, 15 davon Fahrunfälle, aber nur 1 Unfall ohne Radbeteiligung; erwartet würde etwa 1 Radunfall. LISA markiert sie nicht, durch Zählen allein wäre sie also übersehen worden. *Wo die Daten enden:* Das Muster deutet auf die Radstrecke selbst hin und nicht auf Konflikte mit Autos, die Ursache muss aber vor Ort geklärt werden.
5. **Die Wege zu den Schulen und Kindergärten mit den meisten Radunfällen im Umkreis von 150 m prüfen:** Nürnberger Fremdsprachenschule (32, davon 8 mit Getöteten oder Schwerverletzten), Gan Schalom (32, 1), St. Michael (29, 4), Evangelische Kindertagesstätte an der Peterskirche (26, 4) und Kindergarten der Frauenkirche (25, 7). *Wo die Daten enden:* Sie zeigen nicht, ob Kinder beteiligt waren, und Schulen und Kindergärten sind in Hotspots nicht überrepräsentiert.
6. **Kampagnen und Kontrollen für die Zeiten mit den meisten Radunfällen planen:** 58 % ereigneten sich von Mai bis September; es gibt etwa 700 an jedem Werktag der Woche, aber etwa 370 an Sonntagen (2020–2025); an Werktagen liegen die Spitzen um 7–8 und 16–17 Uhr. *Wo die Daten enden:* Sie zeigen nicht, ob Kampagnen oder Kontrollen Unfälle verringern.
7. **Radverkehr zählen und die Analyse jedes Jahr wiederholen.** Die Radunfälle gingen von 801 im Jahr 2022 auf 675 im Jahr 2025 zurück, aber ohne Zählungen der Radfahrenden kann niemand sagen, ob Radfahren sicherer geworden ist oder weniger Menschen Rad gefahren sind. Zählungen je Straße würden aus Unfallzahlen ein Risiko machen, und ein jährlicher Lauf mit den neuen Unfallatlas-Daten zeigt, ob Maßnahmen wirken.

#### Grenzen der Analyse

- **Keine Verkehrszählungen:** Ohne die Zahl der Radfahrenden je Straße zeigt die Analyse, wo Unfälle passieren, nicht, wo Radfahren pro gefahrenem Kilometer am gefährlichsten ist.
- **Kein Alter:** Die Unfalldaten sagen nicht, wer beteiligt war.
- **Entscheidungen:** Der Radius und die Mindestzahl von Unfällen für DBSCAN, die Hexagongröße und das Signifikanzniveau beeinflussen alle das Ergebnis. Andere vernünftige Werte würden die Zahl der Cluster ändern und einige Orte in der Liste nach oben oder unten verschieben.
- **Kleine Zahlen:** Bei etwa 700 Radunfällen pro Jahr können Unterschiede von wenigen Unfällen zwischen Orten oder Jahren Zufall sein.
- **Ihre Werte:** LISA verwendet zufällige Permutationen, und GWR hängt davon ab, wie die Nachbarn gewichtet werden. Ihre Zahlen können daher leicht von den obigen abweichen.

---

## 6. Optional: Spatial Studio (5 Min.)

Dieser Teil braucht Ihre eigene Autonomous AI Database mit Spatial Studio (Option 2 in Abschnitt 5). Die LiveLabs-Umgebung stellt Spatial Studio nicht bereit: Dort endet der Workshop mit Teil 9 des Notebooks.

Die Menünamen können sich je nach Version und Spracheinstellung von Spatial Studio leicht unterscheiden.

1. **Spatial Studio öffnen** und mit Ihrem Workshop-Benutzer anmelden.
2. **Datasets anlegen** aus den Tabellen `NUE_HOTSPOT_GRID`, `NUE_CLUSTER_SUMMARY` und `NUE_BIKE_INFRA`. Wenn Spatial Studio nach einer Schlüsselspalte fragt, verwenden Sie `CELL_ID`, `CLUSTER_ID`, `OSM_ID` oder `ID`.
3. **Ein Projekt anlegen** mit dem Namen „Safe Cycling Nuremberg“ und die Datasets zur Karte hinzufügen.
4. **Die Layer gestalten:**
   - **Hotspot-Gitter:** `LABEL` auf `HOTSPOT` und `HIGH-LOW` filtern und nach `LABEL` einfärben.
   - **Radinfrastruktur:** die Linien nach `CATEGORY` einfärben.
   - **Cluster-Zusammenfassung:** die Größe der Punkte nach `ACCIDENTS` richten und sie mit `RANK` beschriften.
5. **Optional:**
   - **Mehr als erwartet:** das Hotspot-Gitter ein zweites Mal hinzufügen und nach `EXCESS` einfärben, mit einer Rot-Blau-Farbskala.
   - **Schulen und Kindergärten:** ein Dataset aus `NUE_EDUCATION_SURROUNDINGS` anlegen und seine Punkte zeigen, gefiltert auf `LABEL` = `HOTSPOT`.
6. **Entscheiden:** Zoomen Sie auf die Top 5. Welchen Ort würden Sie zuerst entschärfen, und wie: mit einem neuen Radweg oder einer sichereren Kreuzung?

---

## 7. Wenn etwas nicht klappt

| Was Sie sehen | Was zu tun ist |
|---|---|
| `Replace PAR_URL ...` | Die PAR-URL der Workshop-Leitenden in **Workshop-Parameter setzen** einfügen und den Absatz erneut ausführen. |
| HTTP 401, 403 oder 404 beim Lesen einer Datei | Die PAR-URL auf Tippfehler prüfen. Wenn sie stimmt, die Workshop-Leitenden fragen. |
| `NameError: name '...' is not defined` | Sie haben einen Absatz übersprungen, oder die Python-Sitzung wurde neu gestartet. Führen Sie den Absatz davor aus. Nach einem Neustart das Notebook ab Teil 1 erneut ausführen; Teil 2 können Sie überspringen, wenn Ihre Tabellen schon geladen sind. |
| Das Laden in Teil 2 dauert lange | Die Dateien sind groß. Warten Sie, oder fragen Sie die Workshop-Leitenden, ob Sie weniger Jahre laden sollen. |
| Eine Karte hat keinen Hintergrund | Der Basiskartendienst ist nicht erreichbar. Die Analyse ist nicht betroffen. |
| Ihre Werte weichen leicht ab | Erwartet bei Moran's I, LISA und allem, was darauf aufbaut. Cluster, Anzahlen und die Top 5 sollten übereinstimmen. |

---

## 8. Begriffe einfach erklärt

| Begriff | Bedeutung |
|---|---|
| **Koordinatensystem (CRS)** | Die Art, wie Positionen angegeben werden. Längen-/Breitengrad (EPSG:4326) eignet sich zum Speichern, Entfernungen brauchen aber Meter: hier UTM-Zone 32N (EPSG:25832). |
| **SpatialDataFrame** | Ein Tabellenobjekt von Spatial AI in Python. Es verweist auf eine Datenbanktabelle, statt sie zu kopieren. Filter und räumliche Operationen laufen deshalb in der Datenbank. |
| **DBSCAN** | Findet dichte Gruppen von Punkten. Ein Punkt mit genügend Nachbarn innerhalb eines Radius bildet den Kern eines Clusters; vereinzelte Punkte sind „Rauschen“. |
| **Hexagon-Gitter** | Eine Wabenstruktur aus gleich großen Flächen. Damit werden aus Punkten Flächen, die sich mit ihren Nachbarn vergleichen lassen. |
| **Räumliche Gewichte** | Die Liste, wer wessen Nachbar ist, zum Beispiel die 6 nächsten Hexagone. Alle räumlichen Statistiken bauen darauf auf. |
| **Moran's I** | Eine Zahl für die ganze Karte: Liegen hohe Werte häufiger neben hohen Werten, als es der Zufall erwarten lässt? 0 bedeutet zufällig, positive Werte bedeuten Häufung. |
| **LISA** | Lokales Moran's I: derselbe Test für jedes einzelne Hexagon. Er findet Hotspots (belastet unter belasteten) und Ausreißer (belastet unter ruhigen). |
| **p-Wert** | Wie wahrscheinlich ein so starkes Muster zufällig entstünde. Kleine Werte (hier ≤ 0,05) bedeuten „wahrscheinlich kein Zufall“. |
| **Puffer** | Eine Fläche um ein Objekt, zum Beispiel 150 m um eine Schule. |
| **Räumlicher Join** | Zwei Tabellen über ihre Lage statt über einen Schlüssel verknüpfen, zum Beispiel „In welchem Hexagon liegt diese Schule?“ |
| **OLS** | Regression nach der Methode der kleinsten Quadrate (Ordinary Least Squares): eine Regel für die ganze Stadt, die Unfallzahlen aus anderen Variablen erklärt. |
| **GWR** | Geographisch gewichtete Regression: für jeden Ort eine eigene Regel, auf Basis seiner Nachbarn. |
| **R²** | Anteil der Unterschiede, den ein Modell erklärt: 0 = nichts, 1 = alles. |

---

## 9. Nach dem Workshop

- **Ihre Ergebnisse:** Ihre Tabellen bleiben in Ihrem Workshop-Schema, bis die Workshop-Leitenden die Workshop-Benutzer entfernen.
- **Weitere Beispiele:** OML Notebooks enthält weitere Spatial-AI-Beispiele unter Templates → Examples (Filter „Spatial AI“).
- **Dokumentation:** [Using Oracle Spatial AI on Autonomous AI Database Serverless](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/cspai/oracle-spatial-ai1.html)

**Datenlizenzen:**
- Unfallatlas und Zensus 2022: © Statistische Ämter des Bundes und der Länder, [Datenlizenz Deutschland – Namensnennung – Version 2.0](https://www.govdata.de/dl-de/by-2-0).
- Radinfrastruktur, Schulen und Kindergärten: © [OpenStreetMap-Mitwirkende](https://www.openstreetmap.org/copyright), ODbL.

---

## Anhang: Funktionen und Features von Spatial AI und Oracle Spatial

Alle im Workshop verwendeten Funktionen und Features von Spatial AI (`oraclesai`) und Oracle Spatial, nach Namen geordnet.

| Name | Produkt | Was es tut | Verwendet in |
|---|---|---|---|
| `DBScanClustering` | Spatial AI (`oraclesai.clustering`) | Dichtebasiertes Clustering: fasst Punkte zusammen, die mindestens `min_samples` Nachbarn innerhalb des Radius `eps` haben, und kennzeichnet alle anderen Punkte als Rauschen (-1). | Teil 4 |
| `DBSpatialDataset` | Spatial AI | Verweist auf eine Datenbanktabelle mit einer Geometriespalte. Damit wird ein `SpatialDataFrame` aus einer Tabelle erzeugt; außerdem ist es das Ziel von `write()`. | Teile 2–9 |
| `enable_geodataframes()` | Spatial AI | Sorgt dafür, dass `z.show()` in OML Notebooks GeoDataFrames und SpatialDataFrames als Tabellen anzeigt. | Teil 1 |
| `GeoDataFrameDataset` | Spatial AI | Umschließt einen GeoPandas-GeoDataFrame, der nur in Python existiert, zum Beispiel das Hexagon-Gitter, sodass Spatial-AI-Algorithmen ihn verwenden können. | Teile 4, 5, 8 |
| `GWRRegressor` | Spatial AI (`oraclesai.regression`) | Geographisch gewichtete Regression: berechnet für jeden Ort eine eigene Regression, auf Basis seiner Nachbarn gemäß den räumlichen Gewichten. | Teil 8 |
| `KNNWeightsDefinition` | Spatial AI (`oraclesai.weights`) | Legt die Nachbarn jeder Geometrie als ihre k nächsten Nachbarn fest, zum Beispiel `k=6` für die sechs Hexagone um ein Hexagon. | Teile 5, 8 |
| `LISAHotspotClustering` | Spatial AI (`oraclesai.clustering`) | Lokales Moran's I (LISA): testet jede Geometrie gegen ihre Nachbarn und kennzeichnet signifikante Hotspots (HIGH-HIGH), Coldspots und Ausreißer. `labels_` enthält den Quadranten, `regions_` die zusammenhängenden Hotspot-Regionen. | Teil 5 |
| `MoranITest` | Spatial AI (`oraclesai.analysis`) | Globales Moran's I: ein Wert und ein p-Wert für die ganze Karte, die zeigen, ob sich ähnliche Werte räumlich häufen. Dient auch zur Prüfung, ob die Fehler eines Modells räumlich gehäuft sind. | Teile 5, 8 |
| `OLSRegressor` | Spatial AI (`oraclesai.regression`) | Regression nach der Methode der kleinsten Quadrate mit räumlichen Diagnosen: eine Regel für das ganze Gebiet. `summary` zeigt die Koeffizienten und Tests. | Teil 8 |
| `PARObjStoreSpatialDataset` | Spatial AI | Liest eine räumliche Datei, zum Beispiel GeoJSON, über einen Pre-Authenticated Request (PAR) aus OCI Object Storage. | Teil 2 |
| `plot_clusters()` | Spatial AI (`oraclesai.vis`) | Zeichnet Clustering-Ergebnisse auf eine Karte, eine Farbe je Cluster, wahlweise mit Rauschpunkten und Basiskarte. | Teil 4 |
| `read()` | Spatial AI | Lädt einen räumlichen Datensatz, zum Beispiel ein `PARObjStoreSpatialDataset`, in einen GeoDataFrame in Python. | Teil 2 |
| `SCoordTransformer` | Spatial AI (`oraclesai.preprocessing`) | Wandelt Geometrien in x/y-Koordinatenspalten um, die Eingabe, die Algorithmen wie DBSCAN brauchen. | Teil 4 |
| `SDO_GEOMETRY` | Oracle Spatial | Der Datentyp der Geometriespalten in allen Workshop-Tabellen. Er speichert Punkte, Linien und Polygone zusammen mit ihrem Koordinatensystem (SRID). | Alle Tabellen |
| Räumlicher Index (Spatial Index) | Oracle Spatial | Ein Index auf einer Geometriespalte, der räumliche Abfragen wie die Suche nach nächsten Nachbarn schnell macht. Wird von `write(..., create_spatial_index=True)` angelegt. Spatial Studio braucht ihn ebenfalls. | Teile 2, 9, Spatial Studio |
| Spatial Studio – Dataset | Spatial Studio | Macht eine Datenbanktabelle mit Geometrien für Karten und Analysen verfügbar. | Spatial Studio |
| Spatial Studio – Projekt und Layer | Spatial Studio | Eine Karte mit einem Layer je Dataset. Layer lassen sich filtern, nach einer Spalte einfärben, in der Größe skalieren und beschriften. | Spatial Studio |
| Spatial Studio – Analyse *Within distance* | Spatial Studio | Findet die Objekte eines Datasets, die innerhalb einer bestimmten Entfernung zu den Objekten eines anderen Datasets liegen, ohne Code zu schreiben. | Spatial Studio (Leitfaden für Workshop-Leitende) |
| `SpatialDataFrame` | Spatial AI | Die zentrale Datenstruktur von Spatial AI. Sie funktioniert wie ein GeoPandas-DataFrame, verweist aber auf eine Datenbanktabelle, sodass Filter und räumliche Operationen in Oracle Spatial laufen. Wird mit `SpatialDataFrame.create()` erzeugt. | Teile 3–9 |
| `SpatialDataFrame.as_geodataframe()` | Spatial AI | Kopiert die Daten in einen GeoPandas-GeoDataFrame in Python, für Operationen, die GeoPandas bietet, etwa räumliche Joins und Puffer. | Teile 3–8 |
| `SpatialDataFrame.nearest_neighbors()` | Spatial AI / Oracle Spatial | Findet die nächstgelegenen Geometrien zu einer gegebenen Geometrie. Bei einem tabellenbasierten SpatialDataFrame läuft die Suche in der Datenbank und nutzt den räumlichen Index. | Teil 6 |
| `SpatialDataFrame.plot()` | Spatial AI | Zeichnet die Geometrien auf eine Karte, wahlweise nach einer Spalte eingefärbt und mit Basiskarte (`with_basemap=True`). | Teile 3, 8 |
| `SpatialDataFrame.to_crs()` | Spatial AI | Rechnet die Geometrien in ein anderes Koordinatensystem um, hier von WGS84 (EPSG:4326) nach UTM-Zone 32N (EPSG:25832) für Entfernungen in Metern. | Teile 3–8 |
| `SpatialPipeline` | Spatial AI (`oraclesai.pipeline`) | Verkettet Vorverarbeitungsschritte und ein Modell, wie eine scikit-learn-Pipeline, und reicht die räumlichen Informationen weiter. Wird mit `fit()` und `predict()` verwendet. | Teil 8 |
| `SpatialWeights` | Spatial AI (`oraclesai.weights`) | Erstellt aus einer Gewichtsdefinition den Nachbarschaftsgraphen, zum Beispiel um die Nachbarn eines Hexagons anzusehen. | Teil 5 |
| SRID | Oracle Spatial | Die Kennung des Koordinatensystems einer Geometrie, zum Beispiel 4326 für WGS84-Längen-/Breitengrad. Die Workshop-Tabellen verwenden 4326. | Alle Tabellen |
| `write()` | Spatial AI | Schreibt einen GeoDataFrame in eine Datenbanktabelle, ersetzt mit `if_exists='replace'` eine vorhandene Tabelle und legt mit `create_spatial_index=True` einen räumlichen Index an. | Teile 2, 9 |
