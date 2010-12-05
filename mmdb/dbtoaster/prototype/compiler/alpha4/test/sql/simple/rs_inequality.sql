CREATE TABLE R(A int, B int) 
  FROM FILE 'test/data/r.dat' LINE DELIMITED
  csv (fields := ',', schema := 'int,int', eventtype := 'insert');

CREATE TABLE S(C int, D int) 
  FROM FILE 'test/data/s.dat' LINE DELIMITED
  csv (fields := ',', schema := 'int,int', eventtype := 'insert');

--SELECT sum(A*H) FROM R,S,T,U WHERE R.B<S.C AND R.B<T.E AND T.F<U.G AND R.B<U.H;
SELECT sum(A*C) FROM R,S WHERE R.B<S.C;
