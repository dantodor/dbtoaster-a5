-- Expected result: 

CREATE STREAM R(A int, B int) 
  FROM FILE '../../experiments/data/simple/tiny/r.dat' LINE DELIMITED
  CSV (fields := ',');

CREATE STREAM S(B int, C int) 
  FROM FILE '../../experiments/data/simple/tiny/s.dat' LINE DELIMITED
  CSV (fields := ',');

SELECT A FROM R r, (SELECT s2.B, COUNT(*) FROM S s2 GROUP BY s2.B) s WHERE r.B = s.B;
