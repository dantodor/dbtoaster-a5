--  List all location details

CREATE STREAM LOCATION(
    location_id      INT,
    regional_group   VARCHAR(20)
    ) 
  FROM FILE '../../experiments/data/employee/location.dat' LINE DELIMITED
  csv (fields := ',', schema := 'int,string', eventtype := 'insert');

SELECT location_id, regional_group 
FROM location;