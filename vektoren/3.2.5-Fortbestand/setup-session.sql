-- ============================================================
-- Vektor 3.2.5  Fortbestand  Grundzustand fuer T1 und T2
-- Laeuft als ba_admin in ba_test.
-- ============================================================
CREATE ROLE victim LOGIN PASSWORD 'victim';
CREATE TABLE daten (id int, wert text);
INSERT INTO daten VALUES (1,'a'), (2,'b'), (3,'c');
GRANT SELECT ON daten TO victim;