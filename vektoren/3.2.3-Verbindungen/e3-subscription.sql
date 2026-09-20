\echo '## E3  Subscription als Empfaenger  (als attacker, in ba_sub)'
-- Empfaenger einrichten, der die Publikation aus ba_test bezieht.
-- Die Verbindung laeuft als Replikationskonto repl. Ein Nicht-Superuser
-- muss fuer eine Subscription ein Passwort mitgeben und passwortbasiert
-- authentifiziert werden; deshalb ueber den Hostnamen ba-test-pg (scram)
-- statt ueber die trust-Zeile fuer 127.0.0.1.
--
-- create_slot = false, weil Publisher und Empfaenger im selben Cluster
-- liegen: ein CREATE SUBSCRIPTION, das den Slot selbst anlegt, wuerde in
-- diesem Fall haengen (dokumentierte Einschraenkung, CREATE SUBSCRIPTION
-- Notes). Der Slot 'sub' wird deshalb vorher getrennt angelegt (siehe
-- ablauf.md). In einem echten entfernten Aufbau entfaellt dieser Schritt.
CREATE SUBSCRIPTION sub
  CONNECTION 'host=ba-test-pg port=5432 dbname=ba_test user=repl password=repl'
  PUBLICATION pub
  WITH (create_slot = false, slot_name = 'sub');
-- kurz warten, bis die Erstkopie durch ist, dann die Daten ansehen
SELECT pg_sleep(1);
SELECT * FROM oeffentlich ORDER BY id;