CREATE STREAM LINEITEM (
        orderkey       INT,
        partkey        INT,
        suppkey        INT,
        linenumber     INT,
        quantity       DECIMAL,
        extendedprice  DECIMAL,
        discount       DECIMAL,
        tax            DECIMAL,
        returnflag     CHAR(1),
        linestatus     CHAR(1),
        shipdate       DATE,
        commitdate     DATE,
        receiptdate    DATE,
        shipinstruct   CHAR(25),
        shipmode       CHAR(10),
        comment        VARCHAR(44)
    )
  FROM FILE '../../experiments/data/tpch/lineitem.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,int,int,int,float,float,float,float,string,string,date,date,date,string,string,string', eventtype := 'insert');


CREATE STREAM ORDERS (
        orderkey       INT,
        custkey        INT,
        orderstatus    CHAR(1),
        totalprice     DECIMAL,
        orderdate      DATE,
        orderpriority  CHAR(15),
        clerk          CHAR(15),
        shippriority   INT,
        comment        VARCHAR(79)
    )
  FROM FILE '../../experiments/data/tpch/orders.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,int,string,float,date,string,string,int,string', eventtype := 'insert');

CREATE STREAM PART (
        partkey      INT,
        name         VARCHAR(55),
        mfgr         CHAR(25),
        brand        CHAR(10),
        type         VARCHAR(25),
        size         INT,
        container    CHAR(10),
        retailprice  DECIMAL,
        comment      VARCHAR(23)
    )
  FROM FILE '../../experiments/data/tpch/part.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,string,string,string,string,int,string,float,string', eventtype := 'insert');


CREATE STREAM CUSTOMER (
        custkey      INT,
        name         VARCHAR(25),
        address      VARCHAR(40),
        nationkey    INT,
        phone        CHAR(15),
        acctbal      DECIMAL,
        mktsegment   CHAR(10),
        comment      VARCHAR(117)
    )
  FROM FILE '../../experiments/data/tpch/customer.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,string,string,int,string,float,string,string', eventtype := 'insert');

CREATE STREAM SUPPLIER (
        suppkey      INT,
        name         CHAR(25),
        address      VARCHAR(40),
        nationkey    INT,
        phone        CHAR(15),
        acctbal      DECIMAL,
        comment      VARCHAR(101)
    )
  FROM FILE '../../experiments/data/tpch/supplier.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,string,string,int,string,float,string', eventtype := 'insert');
  
CREATE STREAM NATION (
        nationkey    INT,
        name         CHAR(25),
        regionkey    INT,
        comment      VARCHAR(152)
    )
  FROM FILE '../../experiments/data/tpch/nation.csv'
  LINE DELIMITED CSV (fields := '|', schema := 'int,string,int,string', eventtype := 'insert');


 SELECT sn.regionkey, 
        cn.regionkey,
        PART.type,
        SUM(LINEITEM.quantity) AS ssb4
 FROM   CUSTOMER, ORDERS, LINEITEM, PART, SUPPLIER, NATION cn, NATION sn
 WHERE  CUSTOMER.custkey = ORDERS.custkey
   AND  ORDERS.orderkey = LINEITEM.orderkey
   AND  PART.partkey = LINEITEM.partkey
   AND  SUPPLIER.suppkey = LINEITEM.suppkey
   AND  ORDERS.orderdate >= DATE('1997-01-01')
   AND  ORDERS.orderdate <  DATE('1998-01-01')
   AND  cn.nationkey = CUSTOMER.nationkey
   AND  sn.nationkey = SUPPLIER.nationkey
 GROUP BY sn.regionkey, cn.regionkey, PART.type
