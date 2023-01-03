/*-----------------------------------------------------------------------------
Hands-On Lab: Data Engineering with Snowpark
Script:       06_daily_city_metrics_update.sql
Author:       Jeremiah Hansen
Last Updated: 1/2/2023
-----------------------------------------------------------------------------*/

USE ROLE HOL_ROLE;
USE WAREHOUSE HOL_WH;
USE SCHEMA HOL_DB.HARMONIZED;


-- ----------------------------------------------------------------------------
-- Step #1: Create daily_city_metrics table if needed
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ANALYTICS.FAHRENHEIT_TO_CELSIUS(TEMP_F NUMBER(35,4))
RETURNS NUMBER(35,4)
AS
$$
    (temp_f - 32) * (5/9)
$$;

CREATE OR REPLACE FUNCTION ANALYTICS.INCH_TO_MILLIMETER(INCH NUMBER(35,4))
RETURNS NUMBER(35,4)
    AS
$$
    inch * 25.4
$$;

CREATE TABLE IF NOT EXISTS DAILY_CITY_METRICS_STAGE
(
    DATE DATE,
    CITY_NAME VARCHAR,
    COUNTRY_DESC VARCHAR,
    DAILY_SALES VARCHAR,
    AVG_TEMPERATURE_FAHRENHEIT NUMBER,
    AVG_TEMPERATURE_CELSIUS NUMBER,
    AVG_PRECIPITATION_INCHES NUMBER,
    AVG_PRECIPITATION_MILLIMETERS NUMBER,
    MAX_WIND_SPEED_100M_MPH NUMBER
);

-- Debug: DROP TABLE DAILY_CITY_METRICS;
CREATE TABLE IF NOT EXISTS DAILY_CITY_METRICS
(
    DATE DATE,
    CITY_NAME VARCHAR,
    COUNTRY_DESC VARCHAR,
    DAILY_SALES VARCHAR,
    AVG_TEMPERATURE_FAHRENHEIT NUMBER,
    AVG_TEMPERATURE_CELSIUS NUMBER,
    AVG_PRECIPITATION_INCHES NUMBER,
    AVG_PRECIPITATION_MILLIMETERS NUMBER,
    MAX_WIND_SPEED_100M_MPH NUMBER,
    META_UPDATED_AT TIMESTAMP
);


-- ----------------------------------------------------------------------------
-- Step #2: Load new data into the stage table
-- ----------------------------------------------------------------------------

--ALTER WAREHOUSE HOL_WH SET WAREHOUSE_SIZE = XLARGE;

TRUNCATE TABLE DAILY_CITY_METRICS_STAGE;

INSERT INTO DAILY_CITY_METRICS_STAGE
WITH ORDERS_STREAM_DATES_CTE AS
(
  SELECT DISTINCT
    ORDER_TS_DATE AS DATE
  FROM ORDERS_STREAM
)
,ORDERS_CTE AS
(
  SELECT
    ORDER_TS_DATE AS DATE,
    PRIMARY_CITY AS CITY_NAME,
    COUNTRY AS COUNTRY_DESC,
    ZEROIFNULL(SUM(PRICE)) AS DAILY_SALES
  FROM ORDERS_STREAM OS
  GROUP BY
    ORDER_TS_DATE,
    CITY_NAME,
    COUNTRY_DESC
)
,WEATHER_CTE AS
(
  SELECT
    HD.DATE_VALID_STD AS DATE,
    HD.CITY_NAME,
    C.COUNTRY AS COUNTRY_DESC,
    ROUND(AVG(HD.AVG_TEMPERATURE_AIR_2M_F),2) AS AVG_TEMPERATURE_FAHRENHEIT,
    ROUND(AVG(ANALYTICS.FAHRENHEIT_TO_CELSIUS(HD.AVG_TEMPERATURE_AIR_2M_F)),2) AS AVG_TEMPERATURE_CELSIUS,
    ROUND(AVG(HD.TOT_PRECIPITATION_IN),2) AS AVG_PRECIPITATION_INCHES,
    ROUND(AVG(ANALYTICS.INCH_TO_MILLIMETER(HD.TOT_PRECIPITATION_IN)),2) AS AVG_PRECIPITATION_MILLIMETERS,
    MAX(HD.MAX_WIND_SPEED_100M_MPH) AS MAX_WIND_SPEED_100M_MPH
  FROM FROSTBYTE_WEATHERSOURCE.ONPOINT_ID.HISTORY_DAY HD
  JOIN FROSTBYTE_WEATHERSOURCE.ONPOINT_ID.POSTAL_CODES PC
      ON PC.POSTAL_CODE = HD.POSTAL_CODE
      AND PC.COUNTRY = HD.COUNTRY
  JOIN RAW_POS.COUNTRY C
      ON C.ISO_COUNTRY = HD.COUNTRY
      AND C.CITY = HD.CITY_NAME
    -- This join filters the results to only dates in the stream
  JOIN ORDERS_STREAM_DATES_CTE OSD ON (HD.DATE_VALID_STD = OSD.DATE)
  GROUP BY
    HD.DATE_VALID_STD,
    HD.CITY_NAME,
    COUNTRY_DESC
)
SELECT
    O.DATE,
    O.CITY_NAME,
    O.COUNTRY_DESC,
    O.DAILY_SALES,
    W.AVG_TEMPERATURE_FAHRENHEIT,
    W.AVG_TEMPERATURE_CELSIUS,
    W.AVG_PRECIPITATION_INCHES,
    W.AVG_PRECIPITATION_MILLIMETERS,
    W.MAX_WIND_SPEED_100M_MPH
FROM ORDERS_CTE O
  LEFT JOIN WEATHER_CTE W ON (O.DATE = W.DATE AND O.CITY_NAME = W.CITY_NAME AND O.COUNTRY_DESC = W.COUNTRY_DESC)
;  

-- Debug: SELECT COUNT(*) FROM ORDERS_STREAM;
-- Debug: SELECT COUNT(*) FROM DAILY_CITY_METRICS_STAGE;
-- Debug: SELECT * FROM DAILY_CITY_METRICS_STAGE LIMIT 100;


-- ----------------------------------------------------------------------------
-- Step #3: Merge any changes from the stream to the target table
-- ----------------------------------------------------------------------------

MERGE INTO DAILY_CITY_METRICS AS TARGET
USING DAILY_CITY_METRICS_STAGE AS SOURCE
ON (TARGET.DATE = SOURCE.DATE AND TARGET.CITY_NAME = SOURCE.CITY_NAME AND TARGET.COUNTRY_DESC = SOURCE.COUNTRY_DESC)
WHEN MATCHED THEN UPDATE
SET
    TARGET.DATE = SOURCE.DATE,
    TARGET.CITY_NAME = SOURCE.CITY_NAME,
    TARGET.COUNTRY_DESC = SOURCE.COUNTRY_DESC,
    TARGET.DAILY_SALES = SOURCE.DAILY_SALES,
    TARGET.AVG_TEMPERATURE_FAHRENHEIT = SOURCE.AVG_TEMPERATURE_FAHRENHEIT,
    TARGET.AVG_TEMPERATURE_CELSIUS = SOURCE.AVG_TEMPERATURE_CELSIUS,
    TARGET.AVG_PRECIPITATION_INCHES = SOURCE.AVG_PRECIPITATION_INCHES,
    TARGET.AVG_PRECIPITATION_MILLIMETERS = SOURCE.AVG_PRECIPITATION_MILLIMETERS,
    TARGET.MAX_WIND_SPEED_100M_MPH = SOURCE.MAX_WIND_SPEED_100M_MPH,
    TARGET.META_UPDATED_AT = TO_TIMESTAMP_NTZ(CURRENT_TIMESTAMP())
WHEN NOT MATCHED THEN INSERT
(
    DATE,
    CITY_NAME,
    COUNTRY_DESC,
    DAILY_SALES,
    AVG_TEMPERATURE_FAHRENHEIT,
    AVG_TEMPERATURE_CELSIUS,
    AVG_PRECIPITATION_INCHES,
    AVG_PRECIPITATION_MILLIMETERS,
    MAX_WIND_SPEED_100M_MPH,
    META_UPDATED_AT
)
VALUES
(
    SOURCE.DATE,
    SOURCE.CITY_NAME,
    SOURCE.COUNTRY_DESC,
    SOURCE.DAILY_SALES,
    SOURCE.AVG_TEMPERATURE_FAHRENHEIT,
    SOURCE.AVG_TEMPERATURE_CELSIUS,
    SOURCE.AVG_PRECIPITATION_INCHES,
    SOURCE.AVG_PRECIPITATION_MILLIMETERS,
    SOURCE.MAX_WIND_SPEED_100M_MPH,
    TO_TIMESTAMP_NTZ(CURRENT_TIMESTAMP())
);

--ALTER WAREHOUSE HOL_WH SET WAREHOUSE_SIZE = XSMALL;

-- Debug: SELECT * FROM DAILY_CITY_METRICS LIMIT 100;
