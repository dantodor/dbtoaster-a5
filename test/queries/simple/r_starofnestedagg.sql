
CREATE STREAM R(A int, B int) 
  FROM FILE '../../experiments/data/tiny_r.dat' LINE DELIMITED
  csv ();

SELECT * FROM (SELECT COUNT(*) FROM R) n;