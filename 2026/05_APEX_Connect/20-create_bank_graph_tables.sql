CREATE TABLE BANK_ACCOUNTS (
  id              NUMBER,
  name            VARCHAR(400),
  balance         NUMBER(20,2)
);

CREATE TABLE BANK_TRANSFERS (
  txn_id          NUMBER,
  src_acct_id     NUMBER,
  dst_acct_id     NUMBER,
  description     VARCHAR(400),
  amount          NUMBER
);

ALTER TABLE bank_accounts ADD PRIMARY KEY (id);
ALTER TABLE bank_transfers ADD PRIMARY KEY (txn_id);
ALTER TABLE bank_transfers MODIFY src_acct_id REFERENCES bank_accounts (id);
ALTER TABLE bank_transfers MODIFY dst_acct_id REFERENCES bank_accounts (id);
