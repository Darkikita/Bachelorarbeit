-- Einmal als ba_admin, bleibt über beide Zustände stehen.
CREATE TABLE ergebnis (
  lfd      serial PRIMARY KEY,
  nr       text,
  rolle    text,
  zustand  text,
  zeilen   bigint,
  sqlstate text,
  meldung  text
);
GRANT INSERT ON ergebnis TO PUBLIC;
GRANT USAGE ON SEQUENCE ergebnis_lfd_seq TO PUBLIC;

-- Führt einen Befehl mit den Rechten des Aufrufers aus, misst, rollt zurück.
-- sqlstate 00000 = gelungen, 42501 = insufficient_privilege.
CREATE FUNCTION pruef(p_nr text, p_zustand text, p_befehl text, p_setrole text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $$
DECLARE
  v_state text   := '00000';
  v_rows  bigint := 0;
  v_msg   text   := '';
BEGIN
  BEGIN
    IF p_setrole IS NOT NULL THEN
      EXECUTE format('SET ROLE %I', p_setrole);
    END IF;
    EXECUTE p_befehl;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RAISE EXCEPTION USING ERRCODE = 'P9999';   -- erzwingt den Rollback
  EXCEPTION
    WHEN SQLSTATE 'P9999' THEN NULL;
    WHEN OTHERS THEN
      v_state := SQLSTATE;
      v_msg   := SQLERRM;
      v_rows  := NULL;
  END;
  INSERT INTO ergebnis (nr, rolle, zustand, zeilen, sqlstate, meldung)
  VALUES (p_nr, session_user, p_zustand, v_rows, v_state, v_msg);
END $$;