CREATE SEQUENCE EXTERNAL_BALANCE_HISTORY_SEQ INCREMENT BY 1 MAXVALUE 9999999999999999999999999999 MINVALUE 1 CACHE 20;
CREATE TABLE EXTERNAL_BALANCE_HISTORY 
(
  ID NUMBER(18, 0) DEFAULT EXTERNAL_BALANCE_HISTORY_SEQ.nextval NOT NULL 
, AMND_DATE DATE DEFAULT SYSDATE NOT NULL
, CONTRACT VARCHAR2(32) DEFAULT '-' NOT NULL
, SEQ VARCHAR2(32) DEFAULT '-' NOT NULL  
, BALANCE_DATE DATE NOT NULL 
, BALANCE NUMBER(18, 2) NOT NULL 
, ENTRY_EXISISTS VARCHAR2(1) DEFAULT 'N' NOT NULL 
, CONSTRAINT EXTERNAL_BALANCE_HISTORY_PK PRIMARY KEY 
  (
    ID 
  )
  ENABLE 
) 