# Durchlauf <Vektor oder Frage>

**Datum:** YYYY-MM-DD
**Image:** postgres:17.10
**Ordner:** vektoren/<ordner>/
**Bezug im Text:** subsec:<label> gegen sec:schicht<N>

## Frage

Was soll der Lauf zeigen. Ein Satz je Testnummer.

| Nr | Rolle | Angriff | Erwartung vorher | Erwartung nachher |
|----|-------|---------|------------------|-------------------|
| A1 | ... | ... | gelingt | scheitert (42501) |
| N1 | ... | Nutzfall | gelingt | gelingt |

## Grundzustand

Rollen, Objekte, Voreinstellungen, die absichtlich unsicher sind
(Verweis auf setup.sql, hier nur das Wesentliche).

## Maßnahme

Was schichtN.sql ändert, in der Reihenfolge der Befehle.

## Befehle

```bash
V=vektoren/<ordner>

docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/rahmen.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
$V/lauf.sh vorher
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schichtN.sql
$V/lauf.sh nachher
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT nr, rolle, zustand, zeilen, sqlstate FROM ergebnis ORDER BY nr, rolle, zustand;"
```

## Ergebnis

Ausgabe der Abfrage, unverändert eingefügt.

```
 nr | rolle | zustand | zeilen | sqlstate
----+-------+---------+--------+----------
```

## Befund

Je Testnummer ein Satz: Erwartung getroffen oder nicht, und wenn nicht,
woran es lag.

## Abweichungen

Alles, was vom Plan abwich (Reihenfolge, Neustart, manueller Eingriff).
Leer, wenn nichts.

## Folge für den Text

Welche Aussage in Kap. 3 oder 4 der Befund stützt oder ändert.