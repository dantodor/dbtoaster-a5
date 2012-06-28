SET search_path = '@@DATASET@@';

SELECT SUM(l.l_extendedprice * l.l_discount) AS revenue
FROM   lineitem l
WHERE  l.l_shipdate >= DATE('1994-01-01')
  AND  l.l_shipdate < DATE('1995-01-01')
  AND  (l.l_discount BETWEEN (0.06 - 0.01) AND (0.06 + 0.01)) 
  AND  l.l_quantity < 24;