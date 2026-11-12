CREATE PROPERTY GRAPH bank_graph
  VERTEX TABLES (
    BANK_ACCOUNTS
      KEY ( id )
      LABEL accounts PROPERTIES ( id, name )
  )
  EDGE TABLES (
    BANK_TRANSFERS
      SOURCE KEY ( src_acct_id ) REFERENCES BANK_ACCOUNTS(id)
      DESTINATION KEY ( dst_acct_id ) REFERENCES BANK_ACCOUNTS(id)
      LABEL transfers PROPERTIES ( amount, description, src_acct_id, dst_acct_id, txn_id )
  );

