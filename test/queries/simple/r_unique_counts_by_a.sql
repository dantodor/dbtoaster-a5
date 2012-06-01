CREATE STREAM R(A int, B int)
FROM FILE '../../experiments/data/tiny_r.dat' LINE DELIMITED
csv (fields := ',', eventtype := 'insert');

SELECT r3.C FROM (
  SELECT r2.C, COUNT(*) FROM (
    SELECT r1.A, COUNT(*) AS C FROM R r1 GROUP BY r1.A
  ) r2 GROUP BY C
) r3;