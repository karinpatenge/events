CREATE OR REPLACE PROCEDURE add_random_bank_transfers_1000
AS
  TYPE t_acct_ids IS TABLE OF bank_accounts.id%TYPE INDEX BY PLS_INTEGER;
  TYPE t_seen     IS TABLE OF PLS_INTEGER       INDEX BY VARCHAR2(200);

  v_acct_ids      t_acct_ids;
  v_seen_pairs    t_seen;

  v_acct_count    PLS_INTEGER;
  v_max_pairs     PLS_INTEGER;
  v_pairs_done    PLS_INTEGER := 0;

  v_src_idx       PLS_INTEGER;
  v_dst_idx       PLS_INTEGER;
  v_src_acct_id   bank_accounts.id%TYPE;
  v_dst_acct_id   bank_accounts.id%TYPE;

  v_pair_key      VARCHAR2(200);
  v_txn_count     PLS_INTEGER;
  v_next_txn_id   NUMBER;
BEGIN
  SELECT id
  BULK COLLECT INTO v_acct_ids
  FROM bank_accounts
  ORDER BY id;

  v_acct_count := v_acct_ids.COUNT;

  IF v_acct_count < 2 THEN
    RAISE_APPLICATION_ERROR(-20001, 'At least two bank accounts are required.');
  END IF;

  -- Ordered pairs: (A,B) and (B,A) are treated as different combinations
  v_max_pairs := v_acct_count * (v_acct_count - 1);

  IF v_max_pairs < 1000 THEN
    RAISE_APPLICATION_ERROR(
      -20002,
      'Not enough distinct src/dst account pairs to create 1000 combinations.'
    );
  END IF;

  SELECT GREATEST(NVL(MAX(txn_id), 9999) + 1, 10000)
  INTO v_next_txn_id
  FROM bank_transfers;

  WHILE v_pairs_done < 1000 LOOP
    v_src_idx := TRUNC(DBMS_RANDOM.VALUE(1, v_acct_count + 1));
    v_dst_idx := TRUNC(DBMS_RANDOM.VALUE(1, v_acct_count + 1));

    IF v_src_idx = v_dst_idx THEN
      CONTINUE;
    END IF;

    v_src_acct_id := v_acct_ids(v_src_idx);
    v_dst_acct_id := v_acct_ids(v_dst_idx);

    v_pair_key := v_src_acct_id || ':' || v_dst_acct_id;

    IF v_seen_pairs.EXISTS(v_pair_key) THEN
      CONTINUE;
    END IF;

    v_seen_pairs(v_pair_key) := 1;
    v_pairs_done := v_pairs_done + 1;

    -- Random number of transactions for this pair: 1..15
    v_txn_count := TRUNC(DBMS_RANDOM.VALUE(1, 16));

    FOR i IN 1 .. v_txn_count LOOP
      INSERT INTO bank_transfers (
        txn_id,
        src_acct_id,
        dst_acct_id,
        description,
        amount
      )
      VALUES (
        v_next_txn_id,
        v_src_acct_id,
        v_dst_acct_id,
        'Randomly created',
        9999
      );

      v_next_txn_id := v_next_txn_id + 1;
    END LOOP;
  END LOOP;

  COMMIT;
END;
/

BEGIN
  add_random_bank_transfers_1000;
END;
/

SELECT COUNT(*) FROM bank_transfers;

SELECT
  src_acct_id,
  dst_acct_id,
  COUNT(*)
FROM
  bank_transfers
GROUP BY
  src_acct_id,
  dst_acct_id
HAVING
  COUNT(*) > 3;