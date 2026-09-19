# Vektor 3.2.2 Rechteausweitung gegen Schicht 2 und Schicht 3

## Zweck

Abschnitt 3.2.2 beschreibt zwei Wege, auf denen eine Rolle zu Rechten
gelangt, die ihr nicht zugedacht waren. Auf dem ersten besitzt der
Angreifer die Rechte nicht, sondern lenkt die Ausführung einer
privilegierten Funktion auf ein eigenes Objekt um, sodass fremde
Rechte in fremder Sitzung für ihn arbeiten. Auf dem zweiten erzeugt
oder verwaltet er Rechte selbst, weil seiner Rolle die Befugnis dazu
eingeräumt wurde.

Die beiden Wege werden von verschiedenen Schichten geschlossen. Weg 1
beantwortet Schicht 3 mit dem festen Suchpfad der Funktion, während
Schicht 2 nur flankiert. Weg 2 beantwortet allein Schicht 2, indem sie
`CREATEROLE` und die `ADMIN`-Option zurücknimmt, und Schicht 3 hat
gegen ihn ausdrücklich kein Mittel.

Dieser Test zeigt beides an einem einzigen Grundzustand. Er misst
jeden Angriff dreimal, gegen den Grundzustand, nach Schicht 2 und nach
Schicht 3. Die Differenz zeigt, welche Schicht welchen Weg schließt,
und wo eine Schicht einen Weg offenlässt, den die andere schließt.

## Vorgehen

Anders als in 3.2.1 gibt es keine Messfunktion und keine
Ergebnistabelle. Jeder Angriff ist eine kleine Datei, die als ihre
Rolle läuft und ihr Ergebnis unmittelbar in die psql-Ausgabe schreibt,
entweder die zurückgegebene Zeile oder den Fehler `42501`. Das genügt,
weil es nur vier Angriffe gibt, jeder an genau eine Rolle gebunden,
und kein Kreuzprodukt aus Rollen und Befehlen entsteht.

Der Test läuft in drei Durchläufen von Hand (`ablauf.md`). Jeder beginnt
mit einem frischen Volume, spielt `setup.sql` ein, wendet im zweiten und
dritten Durchlauf die zugehörige Schichtdatei an und lässt danach alle
Angriffe laufen. Weil jeder Angriff je Volume genau einmal läuft,
hinterlässt keiner einen Zustand, der einen späteren verfälscht. Der
Rollback, den 3.2.1 über die Messfunktion erzwingt, wird deshalb hier
nicht gebraucht.

Der entscheidende Aufbau steckt im Grundzustand. Es gibt ein
gemeinsames Schema `shared`, in das jede Rolle schreiben darf und das
im Suchpfad der Datenbank vor `public` steht. Der Angreifer schreibt
sein untergeschobenes Objekt dorthin. Ein eigenes Schema je Rolle über
`"$user"` genügt hier nicht, weil `"$user"` in einer
`SECURITY DEFINER`-Sitzung zur Identität des Eigentümers aufgelöst
wird, nicht zu der des Angreifers. Schicht 2 zieht `CREATE` auf
`public` zurück, trifft `shared` aber nicht, sodass der Hijack sie
überlebt. Erst der feste Suchpfad der Funktion in Schicht 3, der
`shared` nicht enthält, schließt den Weg. Genau daran ist abzulesen,
dass Schicht 3 dort
greift, wo Schicht 2 versagt.

Die Verbindung läuft im Container über den Unix-Socket. Die Passwörter
in `setup.sql` sind Testwerte ohne Bedeutung, weil die Anmeldung über
den Socket auf `trust` steht und nicht geprüft wird.

## Umgebung

- PostgreSQL 17.10, Image `postgres:17.10`, Container `ba-test-pg`,
  Dienst `pg-service`
- Datenbank `ba_test`, Superuser `ba_admin`
- Alle Verbindungen über `docker compose exec` innerhalb des Containers
- Jeder Zustand beginnt mit einem frischen Volume

## Dateien

| Datei | Läuft als | Inhalt |
|---|---|---|
| `setup.sql` | `ba_admin` | Grundzustand: Rollen, Schema `shared`, geheime Tabelle, umgelenkte Funktion |
| `e1-hijack.sql` | `attacker` | Weg 1, untergeschobenes Objekt in `shared`, Funktion selbst ausgelöst |
| `e2-createrole.sql` | `creator` | Weg 2a, Rolle anlegen und selbst gewähren, Grenze aus T3 |
| `e3-adminoption.sql` | `attacker` | Weg 2b, ein `GRANT` über die `ADMIN`-Option |
| `n1-nutzfall.sql` | `app` | regulärer Aufruf der Funktion |
| `schicht2.sql` | `ba_admin` | Maßnahmen gegen Weg 2 |
| `schicht3.sql` | `ba_admin` | Maßnahmen gegen Weg 1 |
| `ablauf.md` | — | händisches Ablaufdokument mit Ergebnisfeldern |

## Rollen und Objekte

| Rolle | LOGIN | Zustand vorher | Aufgabe im Test |
|---|---|---|---|
| `victim_owner` | nein | Eigentümer von `geheim`, `protokoll()`, `pruef_zugriff()` | privilegierte Rolle, deren Ausführung umgelenkt wird |
| `attacker` | ja | `CREATE` auf `shared`, `grp_priv` mit `ADMIN`, ohne `INHERIT`/`SET` | Weg 1 und Weg 2b |
| `creator` | ja | `CREATEROLE`, keine `ADMIN`-Option auf Serverrollen | Weg 2a |
| `grp_priv` | nein | `SELECT` auf `geheim` | privilegierte Gruppe, Ziel von Weg 2b |
| `app` | ja | `EXECUTE` auf `pruef_zugriff()` | regulärer Aufrufer, Nutzfall |

`pruef_zugriff()` läuft mit `SECURITY DEFINER`, also mit den Rechten
von `victim_owner`, und ruft `protokoll()` unqualifiziert auf. Ohne
festen Suchpfad entscheidet der Pfad der Sitzung, welche `protokoll()`
sie erreicht. Die legitime liegt in `public`, damit der Nutzfall sie
findet. Die untergeschobene legt `attacker` in `shared` an, das im
Suchpfad der Datenbank vor `public` steht und für jede Rolle
beschreibbar ist.

## Szenarien

| Nr | Rolle | Befehl | Weg |
|---|---|---|---|
| E1 | `attacker` | Objekt in `shared` anlegen, das den unqualifizierten Aufruf verdeckt, dann `pruef_zugriff()` auslösen | 1 |
| E2 | `creator` | `CREATE ROLE neu`, `GRANT neu TO creator`, dann Serverrolle vergeben | 2a |
| E3 | `attacker` | `GRANT grp_priv TO attacker WITH INHERIT TRUE`, dann `geheim` lesen | 2b |
| N1 | `app` | `pruef_zugriff()` regulär aufrufen | — |

**E1.** Erreicht der Angreifer über eine umgelenkte Funktion Daten, die
ihm niemand gegeben hat? Die untergeschobene `protokoll()` läuft mit den
Rechten von `victim_owner` und liest `geheim`. Vorher ja. Nach Schicht 2
weiter ja, weil `shared` unangetastet bleibt. Nach Schicht 3 nein,
weil der feste Suchpfad `shared` nicht enthält.

**E2.** Kann eine Rolle mit `CREATEROLE` eigene Rollen erzeugen und sich
selbst gewähren? Vorher ja. Nach Schicht 2 nein, weil `CREATEROLE`
entzogen ist. Der Weg endet in allen Zuständen bei selbst erzeugten
Rollen, die Serverrolle bleibt ohne `ADMIN`-Option unerreichbar, wie in
T3 belegt.

**E3.** Verschafft die `ADMIN`-Option auf einer Gruppe mit einem einzigen
`GRANT` deren Rechte? Vorher ja. Nach Schicht 2 nein, weil die
Mitgliedschaft samt `ADMIN`-Option zurückgenommen ist. Nach Schicht 3
weiter ja, weil Schicht 3 am Rechtemodell nichts ändert.

**N1.** Arbeitet der reguläre Aufruf in allen Zuständen weiter? Muss
durchgehend `ok` liefern, sonst hätte eine Schicht gesperrt statt
begrenzt.

## Maßnahmen

`schicht2.sql`, gegen Weg 2:

1. `ALTER ROLE creator NOCREATEROLE` — kein Erzeugen von Rollen mehr
2. `REVOKE grp_priv FROM attacker` — Mitgliedschaft samt `ADMIN`-Option
3. `REVOKE CREATE ON SCHEMA public FROM PUBLIC` — flankierend gegen Weg 1

`schicht3.sql`, gegen Weg 1:

1. `ALTER FUNCTION pruef_zugriff() SET search_path = pg_catalog, public, pg_temp`
   — fester Suchpfad, `shared` steht nicht darin
2. `REVOKE CREATE ON SCHEMA public FROM PUBLIC` — Teil des sicheren
   Schemamusters

## Ablauf

Händisch, drei Durchläufe nacheinander, jeder mit frischem Volume.
Die vollständige Schritt-für-Schritt-Anleitung mit Feldern zum Eintragen
der Ergebnisse steht in `ablauf.md`. Grundmuster eines Aufrufs:

```bash
V=vektoren/3.2.2-Rechteausweitung
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
```

## Erwartung

Der Durchlauf steht noch aus. Erwartet wird:

| Angriff | vorher | nach Schicht 2 | nach Schicht 3 |
|---|---|---|---|
| E1 Hijack (`attacker`) | `HIJACK: streng geheim` | `HIJACK: streng geheim` | `ok` |
| E2 CREATEROLE (`creator`) | gelingt, Grenze `42501` | `42501` | gelingt, Grenze `42501` |
| E3 ADMIN-Option (`attacker`) | gelingt (1 Zeile) | `42501` | gelingt (1 Zeile) |
| N1 Nutzfall (`app`) | `ok` | `ok` | `ok` |

## Lesart

- E1 gegen Schicht 2 und Schicht 3: Nach Schicht 2 gelingt der Hijack
  weiter, weil `attacker` in `shared` schreibt, das die Rücknahme von
  `CREATE` auf `public` nicht trifft. Erst der feste
  Suchpfad in Schicht 3 schließt den Weg. Das ist die Stelle, an der
  Schicht 3 greift, wo Schicht 2 versagt.
- E2 und E3 gegen Schicht 2 und Schicht 3: spiegelbildlich. Schicht 2
  nimmt `CREATEROLE` und die `ADMIN`-Option und schließt beide Wege.
  Schicht 3 lässt sie offen, weil sie am Rechtemodell nichts ändert.
  Das ist die Stelle, an der Schicht 2 greift, wo Schicht 3 versagt.
- E2-Grenze: Die Serverrolle bleibt in allen Zuständen unerreichbar
  (`42501`), das bestätigt T3. Der `CREATEROLE`-Weg endet bei selbst
  erzeugten Rollen.
- N1: Der reguläre Aufruf liefert durchgehend `ok`. Keine Schicht
  sperrt ihn, beide begrenzen nur.
- Zu E3: Der `GRANT` wirkt in der laufenden Sitzung. Sollte der
  Lesezugriff unmittelbar danach dennoch `42501` zeigen, bestätigt eine
  neue Anmeldung die geerbte Berechtigung.

## Folge für den Text

Die beiden Wege aus 3.2.2 werden von je einer Schicht geschlossen und
von der anderen offengelassen. Das stützt den Grenzabsatz in
`sec:schicht3`, wonach gegen erzeugte Rechte kein eigenes Mittel der
feingranularen Kontrolle besteht, und die flankierende Rolle von
Schicht 2 bei Weg 1.

## Nicht getestet

- CVE-2020-14349 (logische Replikation) und der Fall, dass eine nicht
  vertrauenswürdige Rolle Datenbankeigentümer ist: nur im Text
- `security_invoker` als Alternative zum festen Suchpfad: nur beschrieben
- das vollständige sichere Schemamuster mit Datenbankeigentum bei einer
  NOLOGIN-Rolle: im Grundzustand ist `ba_admin` Eigentümer, `attacker`
  nie; gemessen wird allein der Suchpfad der Funktion

## Hinweise

- `docker compose down -v` löscht das Volume `ba-test-data`. Nur aus
  `/home/nikita/docker/ba-test` aufrufen
- Die Passwörter der Testrollen entsprechen den Namen. Sie sind ohne
  Bedeutung, weil die Verbindung im Container über den Socket auf
  `trust` läuft
- `attacker`, `creator` und `app` haben `LOGIN`, `victim_owner` und
  `grp_priv` sind `NOLOGIN` und verbinden nie
- `e1-hijack.sql` löscht die untergeschobene `shared.protokoll()` am Ende
  wieder. Sie ist global in der Datenbank, und ohne das Löschen würde der
  Nutzfall N1, der dieselbe Funktion aufruft, die vergiftete Version
  treffen statt der echten in `public`
- Die drei Durchläufe machen je einen Down-Up-Zyklus, das Ganze dauert
  entsprechend länger als ein einzelner Angriff