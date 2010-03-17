LOAD DATA
INFILE '/home/yanif/datasets/tpch/100m/supplier.tbl'
INTO TABLE SUPPLIER
APPEND
FIELDS TERMINATED BY '|'
OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
( s_suppkey, s_name, s_address, s_nationkey,
  s_phone, s_acctbal, s_comment        
)