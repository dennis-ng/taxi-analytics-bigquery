Design considerations:
======================
1. Wildcard table name with REGEXP doesn't work because the prefix matches the table names of `green_trips_2018` and `yellow_trips_2018`, which do not contain the columns "`pickup_latitude`" and "`pickup_longitude`"

```
SELECT
...
FROM
    `bigquery-public-data.new_york_taxi_trips.tlc_*`
WHERE
    REGEXP_CONTAINS(_TABLE_SUFFIX, r'((green_trips_201[4-7])|(yellow_trips_201[5-7]))')
```
2. Null Values and Invalid values<p>
There are some rows where some columns in `trip_distance`, `fare_amount`, `dropoff_datetime` or the `longitude/latitude` are NULL. I exclude any rows where any of those columns contain a `NULL` value to ensure the endpoints are returning results based on the same consistent set of taxi trips. However, if I do that, tables in 2017 will be completely empty. If approximation is acceptable, I will include the rows as long as they contain either valid set of columns in [`longitude/latitude`, `fare_amount`] or valid set of columns in [`trip_distance`, `dropoff_datetime`]. However, because the API required does not support specify if approximation is expected, I would rather not surprise the user.<br>
Some of the columns have only a certain valid range of values, thus the following filters are put in place:
```
WHERE
    (pickup_datetime < dropoff_datetime)
    AND
    (pickup_latitude BETWEEN -90 AND 90)
    AND
    (pickup_longitude BETWEEN -180 AND 180)
    AND
    (fare_amount > 0)
    AND
    (trip_distance > 0)
    AND
    (DATETIME_DIFF(dropoff_datetime, pickup_datetime, DAY) < 1)
```
On top of the usual valid range of values, I noticed that some of the pickup_datetime appears to not belong to the year indicated by the table name(i.e. tlc_green_trips_2017 containing `MIN(pickup_datetime)` of the year 2008). Hence, I also filtered out the pickup_datetime with year that doesn't match the table name.<P>
There are 518 rows out of the non-null pickup_datetime and dropoff_datetime. This is an insignificant number of rows out of all the data we have, thus I can safely determine them as outliers(This is a database for taxi trips and it doesn't make sense to travel for days on a taxi) and drop them.
There are 2190875 trips that lasted less than 2 minutes between pickup_datetime and dropoff_datetime, yet they have travelled a great distance. I left them in because there are too many rows that if I tried to determine a threshold for the distance or time travelled, the data for the average speed would become significantly biased. I would inform the data scientist or whoever is going to use these data and let them decide according to the requirements of their application. <P>
One way I can handle it however, could be using k-means clustering to remove the outliers. I know BigQuery supports this model natively but I suspect it might be out of scope for this assignment. If this is something I should have done, please let me know and I will work on it.

3. Because the ST_GEOHASH function in bigquery is not implemented using S2 geometry, I needed to use a javascript UDF to do the hashing. <br>
I found [one](https://github.com/CartoDB/bigquery-jslibs) already implemented and the source was very similar to the [npm registry's javascript port](https://www.npmjs.com/package/s2-geometry).<br>
The javascript UDF slows down the SQL operation by a lot, but since we only need to run this once, it should be fine.<p>
In this case, the requirement is to group the location by level 16 s2 id. Because BigQuery does not support unsigned 64 bit integers(cannot store the id 2^64-1), I stored and clustered the locations by using their s2 key instead of id. This will allow the cluster to be more efficient in case we want to group by a higher level of s2(< level 16). We can do that by using `SUBSTR`(e.g. `SUBSTR(level30_key, 1, 12)` to group them by level 10). One consideration is that I can also create level 30 s2 keys instead, then we can just use substrings of the level 30 s2 key. i.e. `SUBSTR(level30_key, 1, 18)` to get the level 16 keys. This will avoid expensive recomputation if we need other to group by the deeper levels.

4. Average speed in the past 24 hours API requires filtering by `dropoff_datetime`, but data is only partitioned by `pickup_datetime`<p>
If we were to run the query with a filter of only `WHERE dropoff_datetime=date`, bigquery would scan the entire 5.6GB of data available despite being a partitioned table. This would potentially be way bigger when we get more new data. This would both be slow and cost more. <br>
Because we removed the 518 rows of trips that last more than 1 day, we can confirm that every trip will span over at most 2 dates(i.e. when the trip spans over midnight). Thus I can filter by the partitioned pickup_datetime to query from a range of 1 day before to the date given.
