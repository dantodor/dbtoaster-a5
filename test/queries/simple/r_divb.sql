CREATE STREAM R(A int, B int) 
  FROM FILE '../../experiments/data/simple/tiny/r.dat' LINE DELIMITED
  CSV (fields := ',');

SELECT (100000*SUM(1))/B FROM R GROUP BY B;

