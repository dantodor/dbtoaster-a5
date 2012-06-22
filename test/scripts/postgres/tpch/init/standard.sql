﻿DROP SCHEMA "TPCH_standard" CASCADE;

CREATE SCHEMA "TPCH_standard"
  AUTHORIZATION postgres;

CREATE TABLE IF NOT EXISTS "TPCH_standard".CUSTOMER (
  C_CUSTKEY    int NOT NULL,
  C_NAME       varchar(25) NOT NULL,
  C_ADDRESS    varchar(40) NOT NULL,
  C_NATIONKEY  int NOT NULL,
  C_PHONE      char(15) NOT NULL,
  C_ACCTBAL    decimal(10,2) NOT NULL,
  C_MKTSEGMENT char(10) NOT NULL,
  C_COMMENT    varchar(117) NOT NULL,
  PRIMARY KEY (C_CUSTKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".LINEITEM (
  L_ORDERKEY      int NOT NULL,
  L_PARTKEY       int NOT NULL,
  L_SUPPKEY       int NOT NULL,
  L_LINENUMBER    int NOT NULL,
  L_QUANTITY      decimal(20,10) NOT NULL,
  L_EXTENDEDPRICE decimal(10,2) NOT NULL,
  L_DISCOUNT      decimal(10,10) NOT NULL,
  L_TAX           decimal(10,10) NOT NULL,
  L_RETURNFLAG    char(1) NOT NULL,
  L_LINESTATUS    char(1) NOT NULL,
  L_SHIPDATE      date NOT NULL,
  L_COMMITDATE    date NOT NULL,
  L_RECEIPTDATE   date NOT NULL,
  L_SHIPINSTRUCT  char(25) NOT NULL,
  L_SHIPMODE      char(10) NOT NULL,
  L_COMMENT       varchar(44) NOT NULL,
  PRIMARY KEY (L_ORDERKEY, L_LINENUMBER)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".NATION (
  N_NATIONKEY int NOT NULL,
  N_NAME      char(25) NOT NULL,
  N_REGIONKEY int NOT NULL,
  N_COMMENT   varchar(152) NOT NULL,
  PRIMARY KEY (N_NATIONKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".ORDERS (
  O_ORDERKEY      int NOT NULL,
  O_CUSTKEY       int NOT NULL,
  O_ORDERSTATUS   char(1) NOT NULL,
  O_TOTALPRICE    decimal(10,2) NOT NULL,
  O_ORDERDATE     date NOT NULL,
  O_ORDERPRIORITY char(15) NOT NULL,
  O_CLERK         char(15) NOT NULL,
  O_SHIPPRIORITY  int NOT NULL,
  O_COMMENT       varchar(79) NOT NULL,
  PRIMARY KEY (O_ORDERKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".PART (
  P_PARTKEY     int NOT NULL,
  P_NAME        varchar(55) NOT NULL,
  P_MFGR        char(25) NOT NULL,
  P_BRAND       char(10) NOT NULL,
  P_TYPE        varchar(25) NOT NULL,
  P_SIZE        int NOT NULL,
  P_CONTAINER   char(10) NOT NULL,
  P_RETAILPRICE decimal(10,2) NOT NULL,
  P_COMMENT     varchar(23) NOT NULL,
  PRIMARY KEY (P_PARTKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".PARTSUPP (
  PS_PARTKEY    int NOT NULL,
  PS_SUPPKEY    int NOT NULL,
  PS_AVAILQTY   int NOT NULL,
  PS_SUPPLYCOST decimal(10,2) NOT NULL,
  PS_COMMENT    varchar(199) NOT NULL
--  PRIMARY KEY (PS_PARTKEY,PS_SUPPKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".REGION (
  R_REGIONKEY int NOT NULL,
  R_NAME      char(25) NOT NULL,
  R_COMMENT   varchar(152) NOT NULL,
  PRIMARY KEY (R_REGIONKEY)
);

CREATE TABLE IF NOT EXISTS "TPCH_standard".SUPPLIER (
  S_SUPPKEY   int NOT NULL,
  S_NAME      char(25) NOT NULL,
  S_ADDRESS   varchar(40) NOT NULL,
  S_NATIONKEY int NOT NULL,
  S_PHONE     char(15) NOT NULL,
  S_ACCTBAL   decimal(10,2) NOT NULL,
  S_COMMENT   varchar(101) NOT NULL,
  PRIMARY KEY (S_SUPPKEY)
);

DELETE FROM "TPCH_standard".LINEITEM;
DELETE FROM "TPCH_standard".ORDERS;
DELETE FROM "TPCH_standard".PARTSUPP;
DELETE FROM "TPCH_standard".PART;
DELETE FROM "TPCH_standard".SUPPLIER;
DELETE FROM "TPCH_standard".CUSTOMER;
DELETE FROM "TPCH_standard".NATION;
DELETE FROM "TPCH_standard".REGION;

COPY "TPCH_standard".REGION   FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/region.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".NATION   FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/nation.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".CUSTOMER FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/customer.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".SUPPLIER FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/supplier.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".PART     FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/part.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".PARTSUPP FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/partsupp.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".ORDERS   FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/orders.csv' WITH DELIMITER AS '|'; 
COPY "TPCH_standard".LINEITEM FROM '@@DBT_DIR@@/../../experiments/data/tpch/standard/lineitem.csv' WITH DELIMITER AS '|'; 

