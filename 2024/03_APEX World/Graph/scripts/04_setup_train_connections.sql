--------------------------------------------------------
--  DDL for Table TRAIN_CONNECTIONS
--------------------------------------------------------
CREATE TABLE TRAIN_CONNECTIONS (
  ID NUMBER,
	ORIG_AIRPORT_ID NUMBER,
	DEST_AIRPORT_ID NUMBER,
	DISTANCE NUMBER,
	DETAILS JSON
);

--------------------------------------------------------
--  DDL for Index TRAIN_CONNECTIONS_PK
--------------------------------------------------------
CREATE UNIQUE INDEX TRAIN_CONNECTIONS_PK ON TRAIN_CONNECTIONS (ID) ;

--------------------------------------------------------
--  Constraints for Table TRAIN_CONNECTIONS
--------------------------------------------------------
ALTER TABLE TRAIN_CONNECTIONS MODIFY (ID NOT NULL ENABLE);
ALTER TABLE TRAIN_CONNECTIONS ADD CONSTRAINT TRAIN_CONNECTIONS_PK PRIMARY KEY (ID) ENABLE;

--------------------------------------------------------
--  Ref Constraints for Table TRAIN_CONNECTIONS
--------------------------------------------------------
ALTER TABLE TRAIN_CONNECTIONS ADD CONSTRAINT TC_DEST_AIRPORT_FK FOREIGN KEY (DEST_AIRPORT_ID)
	REFERENCES AIRPORTS (ID) ENABLE;
ALTER TABLE TRAIN_CONNECTIONS ADD CONSTRAINT TC_ORIG_AIRPORT_FK FOREIGN KEY (ORIG_AIRPORT_ID)
	REFERENCES AIRPORTS (ID) ENABLE;

--------------------------------------------------------
--  Insert data into Table TRAIN_CONNECTIONS
--------------------------------------------------------
Insert into TRAIN_CONNECTIONS (ID,ORIG_AIRPORT_ID,DEST_AIRPORT_ID,DISTANCE,DETAILS) values (987,8588,8590,219,'{Operator:Eurostar,Stops:0,Load:Passengers}');
Insert into TRAIN_CONNECTIONS (ID,ORIG_AIRPORT_ID,DEST_AIRPORT_ID,DISTANCE,DETAILS) values (988,8590,8588,219,'{Operator:Eurostar,Stops:0,Load:Passengers}');
Insert into TRAIN_CONNECTIONS (ID,ORIG_AIRPORT_ID,DEST_AIRPORT_ID,DISTANCE,DETAILS) values (1247,8588,8590,219,'{Operator:LeShuttle,Stops:0,Load:[Passengers,Vehicles]}');
Insert into TRAIN_CONNECTIONS (ID,ORIG_AIRPORT_ID,DEST_AIRPORT_ID,DISTANCE,DETAILS) values (1248,8590,8588,219,'{Operator:LeShuttle,Stops:0,Load:[Passengers,Vehicles]}');
commit;