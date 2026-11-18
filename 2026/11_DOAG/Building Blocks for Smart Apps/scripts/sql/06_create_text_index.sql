--------------------------------------------------------------------------------
-- File       : 06_create_text_index.sql
-- Project    : DOAG 2026 - "Just a sprain?" (Ulrike & Karin)
-- Purpose    : Creates the full-text index (Oracle Text, CONTEXT) on
--              SYMPTOM_REPORTS.REPORT_TEXT, configured for German texts,
--              and checks it with a few test queries.
-- Database   : Oracle Autonomous AI Database 26ai (Serverless)
-- Run        : with SQLcl as the demo user, after 03_load_data.sql
--                sql doag2026@<tns_alias> @06_create_text_index.sql
-- Privileges : CTXAPP (in DB_DEVELOPER_ROLE, see 00_create_user.sql)
-- Re-runnable: yes. Index and preferences are dropped and created again.
-- Log        : logs/sql/06_create_text_index.log in the project folder,
--              overwritten on every run
--
-- Settings (the symptom reports are German, so the index is German too)
--   Lexer     BASIC_LEXER, German compound splitting (Kniekehle -> Knie,
--             kehle), alternate umlaut spellings (ae = ä), case-insensitive.
--             The hyphen is deliberately NOT a PRINTJOIN: this way
--             "Plopp-Geräusch" becomes "Plopp" and "Geräusch", and a search
--             for "Plopp" finds it.
--   Wordlist  German stemming ($verdrehen finds verdreht) and German fuzzy
--             search (?Plop finds Plopp), prefix index for wildcards
--             (Schwell%)
--   Stoplist  frequent German filler words; "kein" (no) and "nicht" (not)
--             remain searchable
--   Sync      ON COMMIT, new reports are searchable right after the commit
--------------------------------------------------------------------------------

SET DEFINE OFF
SET VERIFY OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON SIZE UNLIMITED
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

SPOOL ../../logs/sql/06_create_text_index.log

PROMPT
PROMPT === 06 Full-text index on SYMPTOM_REPORTS.REPORT_TEXT ===

BEGIN
  IF USER = 'ADMIN' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Run this script as the demo user, not as ADMIN.');
  END IF;
END;
/

--==============================================================================
-- 1. Drop existing index and preferences
--==============================================================================

PROMPT --- 1. Drop old index
DROP INDEX IF EXISTS symptom_reports_txt_idx;

BEGIN
  FOR p IN (SELECT pre_name FROM ctx_user_preferences
            WHERE  pre_name IN ('SYMPTOM_LEXER', 'SYMPTOM_WORDLIST')) LOOP
    CTX_DDL.DROP_PREFERENCE(p.pre_name);
  END LOOP;
  FOR s IN (SELECT spl_name FROM ctx_user_stoplists WHERE spl_name = 'SYMPTOM_STOPLIST') LOOP
    CTX_DDL.DROP_STOPLIST(s.spl_name);
  END LOOP;
END;
/

--==============================================================================
-- 2. Preferences for German texts
--==============================================================================

PROMPT --- 2. Create lexer, wordlist and stoplist
BEGIN
  -- Lexer
  CTX_DDL.CREATE_PREFERENCE('symptom_lexer', 'BASIC_LEXER');
  CTX_DDL.SET_ATTRIBUTE('symptom_lexer', 'COMPOSITE',          'GERMAN');
  CTX_DDL.SET_ATTRIBUTE('symptom_lexer', 'ALTERNATE_SPELLING', 'GERMAN');
  CTX_DDL.SET_ATTRIBUTE('symptom_lexer', 'MIXED_CASE',         'NO');

  -- Wordlist
  CTX_DDL.CREATE_PREFERENCE('symptom_wordlist', 'BASIC_WORDLIST');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'STEMMER',           'GERMAN');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'FUZZY_MATCH',       'GERMAN');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'FUZZY_SCORE',       '60');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'FUZZY_NUMRESULTS',  '100');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'PREFIX_INDEX',      'TRUE');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'PREFIX_MIN_LENGTH', '3');
  CTX_DDL.SET_ATTRIBUTE('symptom_wordlist', 'PREFIX_MAX_LENGTH', '8');

  -- Stoplist with frequent German filler words
  CTX_DDL.CREATE_STOPLIST('symptom_stoplist', 'BASIC_STOPLIST');
  FOR w IN (SELECT COLUMN_VALUE AS word
            FROM   TABLE(SYS.ODCIVARCHAR2LIST(
                     'der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einem',
                     'einer', 'eines', 'und', 'oder', 'aber', 'auch', 'als', 'am', 'an', 'auf',
                     'aus', 'bei', 'beim', 'bis', 'durch', 'für', 'im', 'in', 'ins', 'mit',
                     'nach', 'seit', 'über', 'um', 'unter', 'vom', 'von', 'vor', 'zu', 'zum',
                     'zur', 'ich', 'mir', 'mich', 'mein', 'meine', 'es', 'er', 'sie', 'wir',
                     'ist', 'sind', 'war', 'hat', 'habe', 'hatte', 'wird', 'wurde', 'sich',
                     'so', 'da', 'dann', 'noch', 'schon', 'sehr', 'etwas', 'wie', 'wenn'))) LOOP
    CTX_DDL.ADD_STOPWORD('symptom_stoplist', w.word);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('OK      SYMPTOM_LEXER, SYMPTOM_WORDLIST, SYMPTOM_STOPLIST');
END;
/

--==============================================================================
-- 3. Create the CONTEXT index
--==============================================================================

PROMPT --- 3. Create index SYMPTOM_REPORTS_TXT_IDX
CREATE INDEX symptom_reports_txt_idx
  ON symptom_reports (report_text)
  INDEXTYPE IS CTXSYS.CONTEXT
  PARAMETERS ('LEXER    symptom_lexer
               WORDLIST symptom_wordlist
               STOPLIST symptom_stoplist
               SYNC (ON COMMIT)');

-- Check the index: status and indexing errors
DECLARE
  l_status ctx_user_indexes.idx_status%TYPE;
  l_docs   ctx_user_indexes.idx_docid_count%TYPE;
  l_errors PLS_INTEGER;
BEGIN
  SELECT idx_status, idx_docid_count INTO l_status, l_docs
  FROM   ctx_user_indexes WHERE idx_name = 'SYMPTOM_REPORTS_TXT_IDX';

  SELECT COUNT(*) INTO l_errors
  FROM   ctx_user_index_errors WHERE err_index_name = 'SYMPTOM_REPORTS_TXT_IDX';

  IF l_status <> 'INDEXED' OR l_errors > 0 THEN
    RAISE_APPLICATION_ERROR(-20030, 'Index SYMPTOM_REPORTS_TXT_IDX: status ' || l_status
                                    || ', ' || l_errors || ' errors (see CTX_USER_INDEX_ERRORS).');
  END IF;
  DBMS_OUTPUT.PUT_LINE('OK      SYMPTOM_REPORTS_TXT_IDX, status ' || l_status || ', ' || l_docs || ' documents');
END;
/

--==============================================================================
-- 4. Test queries (only reports of others, without Jonas' app report)
--==============================================================================

PROMPT
PROMPT --- 4. Test queries: hits per search expression
SELECT 'Plopp'              AS search_term, 'exact word (pop), also in Plopp-Geräusch' AS meaning,
       COUNT(*) AS hits FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, 'Plopp') > 0
UNION ALL
SELECT 'Knie', 'word (knee) and word part in compounds (Kniekehle, Kniescheibe)',
       COUNT(*) FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, 'Knie') > 0
UNION ALL
SELECT '$verdrehen', 'stem form (twist): verdreht, verdrehen',
       COUNT(*) FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, '$verdrehen') > 0
UNION ALL
SELECT '?Plop', 'fuzzy: typing errors',
       COUNT(*) FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, '?Plop') > 0
UNION ALL
SELECT 'Schwell%', 'wildcard (swell...): Schwellung, but not geschwollen',
       COUNT(*) FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, 'Schwell%') > 0
UNION ALL
SELECT 'Gelenk AND instabil', 'both terms (joint, unstable)',
       COUNT(*) FROM symptom_reports WHERE source = 'fhir' AND CONTAINS(report_text, 'Gelenk AND instabil') > 0;

PROMPT
PROMPT --- Top five hits for "Plopp OR geknallt OR wackelig" (pop, banged, wobbly) with diagnosis
COLUMN report_id       FORMAT A12
COLUMN diagnosis_label FORMAT A30
COLUMN report_text     FORMAT A70 TRUNCATED

SELECT s.report_id,
       SCORE(1) AS score,
       d.diagnosis_label,
       s.report_text
FROM   symptom_reports s
LEFT   JOIN diagnoses d ON d.report_id = s.report_id
WHERE  s.source = 'fhir'
AND    CONTAINS(s.report_text, 'Plopp OR geknallt OR wackelig', 1) > 0
ORDER  BY SCORE(1) DESC
FETCH  FIRST 5 ROWS ONLY;

PROMPT
PROMPT Done.

SPOOL OFF
