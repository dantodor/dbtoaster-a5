CREATE STREAM R(A int, B int)
FROM FILE '../../experiments/data/simple/tiny/r.dat' LINE DELIMITED
CSV (fields := ',');

SELECT A+SUM(1) FROM R GROUP BY A,B
