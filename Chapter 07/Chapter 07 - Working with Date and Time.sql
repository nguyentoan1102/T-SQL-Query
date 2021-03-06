---------------------------------------------------------------------
-- T-SQL Querying (Microsoft Press, 2015)
-- Chapter 07 - Working with Date and Time
-- © Itzik Ben-Gan
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Date and Time Datatypes
---------------------------------------------------------------------

-- Get current datetimeoffset value
SELECT SYSDATETIMEOFFSET();

---------------------------------------------------------------------
-- Date and Time Functions
---------------------------------------------------------------------

-- Current date and time
SELECT
  GETDATE()           AS [GETDATE],
  CURRENT_TIMESTAMP   AS [CURRENT_TIMESTAMP],
  GETUTCDATE()        AS [GETUTCDATE],
  SYSDATETIME()       AS [SYSDATETIME],
  SYSUTCDATETIME()    AS [SYSUTCDATETIME],
  SYSDATETIMEOFFSET() AS [SYSDATETIMEOFFSET];

-- Current date and current time
SELECT
  CAST(SYSDATETIME() AS DATE) AS [current_date],
  CAST(SYSDATETIME() AS TIME) AS [current_time];

-- DATEPART
SELECT
  DATEPART(month, '20150212')   AS monthnum,
  DATEPART(weekday, '20150212') AS weekdaynum; -- language dependent

-- Getting the current tz offset and daylight saving state

-- From the registry
DECLARE @bias AS INT;

EXEC master.dbo.xp_regread
  'HKEY_LOCAL_MACHINE',
  'SYSTEM\CurrentControlSet\Control\TimeZoneInformation',
  'Bias',
  @bias OUTPUT;

SELECT
  SYSDATETIMEOFFSET() currentdatetimeoffset,
  DATEPART(TZoffset, SYSDATETIMEOFFSET()) AS currenttzoffset,
  SIGN(DATEPART(TZoffset, SYSDATETIMEOFFSET()) + @bias) AS currentdst;
GO

-- Using a CLR function

-- In VS
/*
using System;
using System.Data.SqlTypes;
using Microsoft.SqlServer.Server;

public partial class TimeZone
{
    [SqlFunction(IsDeterministic = false, DataAccess = DataAccessKind.None)]
    public static SqlBoolean IsDST()
    {
       return DateTime.Now.IsDaylightSavingTime();
    }
}
*/

-- In SQL Server
USE TSQLV3;

EXEC sys.sp_configure 'CLR Enabled', 1;
RECONFIGURE WITH OVERRIDE;

IF OBJECT_ID(N'dbo.IsDST', N'FS') IS NOT NULL DROP FUNCTION dbo.IsDST;
IF EXISTS(SELECT * FROM sys.assemblies WHERE name = N'TimeZone') DROP ASSEMBLY TimeZone;

CREATE ASSEMBLY TimeZone FROM 'C:\Temp\TimeZone\TimeZone\bin\Debug\TimeZone.dll';
GO
CREATE FUNCTION dbo.IsDST() RETURNS BIT EXTERNAL NAME TimeZone.TimeZone.IsDST;
GO

-- Test function
SELECT
  SYSDATETIMEOFFSET() currentdatetimeoffset,
  DATEPART(TZoffset, SYSDATETIMEOFFSET()) AS currenttzoffset,
  dbo.IsDST() AS currentdst;
GO

-- Cleanup
IF OBJECT_ID(N'dbo.IsDST', N'FS') IS NOT NULL DROP FUNCTION dbo.IsDST;
IF EXISTS(SELECT * FROM sys.assemblies WHERE name = N'TimeZone') DROP ASSEMBLY TimeZone;
GO

-- DAY, MONTH, YEAR
SELECT
  DAY('20150212') AS theday,
  MONTH('20150212') AS themonth,
  YEAR('20150212') AS theyear;

-- DATENAME
SELECT DATENAME(month, '20150212');

-- ISDATE
SELECT
  ISDATE('20150212') AS isdate20150212,
  ISDATE('20150230') AS isdate20150230;

-- SWITCHOFFSET
SELECT
  SWITCHOFFSET(SYSDATETIMEOFFSET(), '-05:00') AS [now as -05:00],
  SWITCHOFFSET(SYSDATETIMEOFFSET(), '-08:00') AS [now as -08:00];

-- TODATETIMEOFFSET
SELECT TODATETIMEOFFSET('20150212 00:00:00.0000000', '-08:00');
GO

-- Add computed column
ALTER TABLE dbo.T1 ADD dto AS TODATETIMEOFFSET(dt, offset);
GO

-- DATEADD
SELECT DATEADD(year, 1, '20150212');

-- DATEDIFF
SELECT DATEDIFF(day, '20150212', '20150213');

SELECT DATEDIFF(year, '20151231 23:59:59.9999999', '20160101 00:00:00.0000000');
GO

-- With DATETIMEOFFSET, DATEDIFF computes offset in UTC terms
DECLARE
  @dto1 AS DATETIMEOFFSET = '20150212 10:30:00.0000000 -08:00',
  @dto2 AS DATETIMEOFFSET = '20150213 22:30:00.0000000 -08:00';

SELECT DATEDIFF(day, @dto1, @dto2);
GO

-- To compute diff in local terms, need to convert to DATETIME2
DECLARE
  @dto1 AS DATETIMEOFFSET = '20150212 10:30:00.0000000 -08:00',
  @dto2 AS DATETIMEOFFSET = '20150213 22:30:00.0000000 -08:00';

SELECT
  CASE
    WHEN DATEPART(TZoffset, @dto1) = DATEPART(TZoffset, @dto2)
      THEN DATEDIFF(day, CAST(@dto1 AS DATETIME2), CAST(@dto2 AS DATETIME2))
  END;
GO

-- Using target offset:
DECLARE
  @dto1 AS DATETIMEOFFSET = '20150301 23:30:00.0000000 -08:00',
  @dto2 AS DATETIMEOFFSET = '20150401 11:30:00.0000000 -07:00'; -- try also with -08:00

SELECT
  DATEDIFF(day,
    CAST(SWITCHOFFSET(@dto1, DATEPART(TZoffset, @dto2)) AS DATETIME2),
    CAST(@dto2 AS DATETIME2));
GO

-- Diff in terms of multiples of 100 nanoseconds
USE TSQLV3;

IF OBJECT_ID(N'dbo.DATEDIFF_NS100', N'IF') IS NOT NULL
  DROP FUNCTION dbo.DATEDIFF_NS100;
GO
CREATE FUNCTION dbo.DATEDIFF_NS100(@dt1 AS DATETIME2, @dt2 AS DATETIME2) RETURNS TABLE
AS
RETURN
  SELECT
    CAST(864000000000 AS BIGINT) * (dddiff - subdd) + ns100diff as ns100
  FROM ( VALUES( CAST(@dt1 AS TIME), CAST(@dt2 AS TIME),
                 DATEDIFF(dd, @dt1, @dt2)
               ) )
         AS D(t1, t2, dddiff)
    CROSS APPLY ( VALUES( CASE WHEN t1 > t2 THEN 1 ELSE 0 END ) )
      AS A1(subdd)
    CROSS APPLY ( VALUES( CAST(864000000000 AS BIGINT) * subdd
        + (CAST(10000000 AS BIGINT) * DATEDIFF(ss, '00:00', t2) + DATEPART(ns, t2)/100)
        - (CAST(10000000 AS BIGINT) * DATEDIFF(ss, '00:00', t1) + DATEPART(ns, t1)/100) ) )
      AS A2(ns100diff);
GO

-- Test function
SELECT ns100
FROM dbo.DATEDIFF_NS100('20150212 00:00:00.0000001', '20160212 00:00:00.0000000');

-- Diff broken to date and time parts
IF OBJECT_ID(N'dbo.DATEDIFFPARTS', N'IF') IS NOT NULL DROP FUNCTION dbo.DATEDIFFPARTS;
GO
CREATE FUNCTION dbo.DATEDIFFPARTS(@dt1 AS DATETIME2, @dt2 AS DATETIME2) RETURNS TABLE
/* The function works correctly provided that @dt2 >= @dt1 */
AS
RETURN
  SELECT
    yydiff - subyy AS yy,
    (mmdiff - submm) % 12 AS mm,
    DATEDIFF(day, DATEADD(mm, mmdiff - submm, dt1), dt2) - subdd AS dd,
    nsdiff / CAST(3600000000000 AS BIGINT) % 60 AS hh,
    nsdiff / CAST(60000000000 AS BIGINT) % 60 AS mi,
    nsdiff / 1000000000 % 60 AS ss,
    nsdiff % 1000000000 AS ns
  FROM ( VALUES( @dt1, @dt2,
                 CAST(@dt1 AS TIME), CAST(@dt2 AS TIME),
                 DATEDIFF(yy, @dt1, @dt2),
                 DATEDIFF(mm, @dt1, @dt2),
                 DATEDIFF(dd, @dt1, @dt2)
               ) )
         AS D(dt1, dt2, t1, t2, yydiff, mmdiff, dddiff)
    CROSS APPLY ( VALUES( CASE WHEN DATEADD(yy, yydiff, dt1) > dt2 THEN 1 ELSE 0 END,
                          CASE WHEN DATEADD(mm, mmdiff, dt1) > dt2 THEN 1 ELSE 0 END,
                          CASE WHEN DATEADD(dd, dddiff, dt1) > dt2 THEN 1 ELSE 0 END ) )
      AS A1(subyy, submm, subdd)
    CROSS APPLY ( VALUES( CAST(86400000000000 AS BIGINT) * subdd
        + (CAST(1000000000 AS BIGINT) * DATEDIFF(ss, '00:00', t2) + DATEPART(ns, t2))
        - (CAST(1000000000 AS BIGINT) * DATEDIFF(ss, '00:00', t1) + DATEPART(ns, t1)) ) )
      AS A2(nsdiff);
GO

-- Test function
SELECT yy, mm, dd, hh, mi, ss, ns
FROM dbo.DATEDIFFPARTS('20150212 00:00:00.0000001', '20160212 00:00:00.0000000');

SELECT yy, mm, dd, hh, mi, ss, ns
FROM dbo.DATEDIFFPARTS('20151231 23:59:59.9999999', '20160101 00:00:00.0000000');

-- To also correctly support inputs where @dt1 > @dt2
IF OBJECT_ID(N'dbo.DATEDIFFPARTS', N'IF') IS NOT NULL DROP FUNCTION dbo.DATEDIFFPARTS;
GO
CREATE FUNCTION dbo.DATEDIFFPARTS(@dt1 AS DATETIME2, @dt2 AS DATETIME2) RETURNS TABLE
AS
RETURN
  SELECT
    sgn,
    yydiff - subyy AS yy,
    (mmdiff - submm) % 12 AS mm,
    DATEDIFF(day, DATEADD(mm, mmdiff - submm, dt1), dt2) - subdd AS dd,
    nsdiff / CAST(3600000000000 AS BIGINT) % 60 AS hh,
    nsdiff / CAST(60000000000 AS BIGINT) % 60 AS mi,
    nsdiff / 1000000000 % 60 AS ss,
    nsdiff % 1000000000 AS ns
  FROM ( VALUES( CASE WHEN @dt1 > @dt2 THEN @dt2 ELSE @dt1 END,
                 CASE WHEN @dt1 > @dt2 THEN @dt1 ELSE @dt2 END,
                 CASE WHEN @dt1 < @dt2 THEN 1
                      WHEN @dt1 = @dt2 THEN 0
                      WHEN @dt1 > @dt2 THEN -1 END ) ) AS D(dt1, dt2, sgn)
	  CROSS APPLY ( VALUES( CAST(dt1 AS TIME), CAST(dt2 AS TIME),
                          DATEDIFF(yy, dt1, dt2),
                          DATEDIFF(mm, dt1, dt2),
                          DATEDIFF(dd, dt1, dt2) ) )
      AS A1(t1, t2, yydiff, mmdiff, dddiff)
    CROSS APPLY ( VALUES( CASE WHEN DATEADD(yy, yydiff, dt1) > dt2 THEN 1 ELSE 0 END,
                          CASE WHEN DATEADD(mm, mmdiff, dt1) > dt2 THEN 1 ELSE 0 END,
                          CASE WHEN DATEADD(dd, dddiff, dt1) > dt2 THEN 1 ELSE 0 END ) )
      AS A2(subyy, submm, subdd)
    CROSS APPLY ( VALUES( CAST(86400000000000 AS BIGINT) * subdd
        + (CAST(1000000000 AS BIGINT) * DATEDIFF(ss, '00:00', t2) + DATEPART(ns, t2))
        - (CAST(1000000000 AS BIGINT) * DATEDIFF(ss, '00:00', t1) + DATEPART(ns, t1)) ) )
      AS A3(nsdiff);
GO

-- Test function
SELECT sgn, yy, mm, dd, hh, mi, ss, ns
FROM dbo.DATEDIFFPARTS('20160212 00:00:00.0000000', '20150212 00:00:00.0000001');

-- SQL Server 2012+

-- Fromparts
SELECT
  DATEFROMPARTS(2015, 02, 12),
  DATETIME2FROMPARTS(2015, 02, 12, 13, 30, 5, 1, 7),
  DATETIMEFROMPARTS(2015, 02, 12, 13, 30, 5, 997),
  DATETIMEOFFSETFROMPARTS(2015, 02, 12, 13, 30, 5, 1, -8, 0, 7),
  SMALLDATETIMEFROMPARTS(2015, 02, 12, 13, 30),
  TIMEFROMPARTS(13, 30, 5, 1, 7);

-- EOMONTH
SELECT EOMONTH(SYSDATETIME());
SELECT EOMONTH(SYSDATETIME(), -1);

-- PARSE
SELECT
  PARSE('01/02/15' AS DATE USING 'en-US') AS [US English],
  PARSE('01/02/15' AS DATE USING 'en-GB') AS [British];

-- TRY_CONVERT, TRY_CAST, TRY_PARSE
SELECT TRY_CONVERT(DATE, '20150212', 112) AS try1, TRY_CONVERT(DATE, '20150230', 112) AS try2;

-- FORMAT
SELECT
  FORMAT(SYSDATETIME(), 'd', 'en-US') AS [US English],
  FORMAT(SYSDATETIME(), 'd', 'en-GB') AS [British];

-- Using format string
SELECT FORMAT(SYSDATETIME(), 'MM/dd/yyyy') AS dt;

-- Performance of PARSE and FORMAT

-- Sample data with 1,000,000 rows
SELECT orderdate AS dt, CONVERT(CHAR(10), orderdate, 101) AS strdt
INTO #T
FROM PerformanceV3.dbo.Orders;

-- For performance test enable Discard results after execution from Query Options dialog

-- Slow
SELECT PARSE(strdt AS DATE USING 'en-US') AS mydt
FROM #T;

-- Fast
SELECT CONVERT(DATE, strdt, 101) AS mydt
FROM #T;

-- Slow
SELECT FORMAT(dt, 'MM/dd/yyyy') AS mystrdt
FROM #T;

-- Fast
SELECT CONVERT(CHAR(10), dt, 101) AS mystrdt
FROM #T;

-- Cleanup
DROP TABLE #T;

---------------------------------------------------------------------
-- Challenges Working with Date and Time
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Literals
---------------------------------------------------------------------

USE TSQLV3;

SELECT orderid, custid, empid, orderdate
FROM Sales.Orders
WHERE orderdate = '02/12/2015';

-- Under British
SET LANGUAGE British;

SELECT orderid, custid, empid, orderdate
FROM Sales.Orders
WHERE orderdate = '02/12/2015';

-- Under US English
SET LANGUAGE us_english;

SELECT orderid, custid, empid, orderdate
FROM Sales.Orders
WHERE orderdate = '02/12/2015';

-- With language-neutral format
SET LANGUAGE British;

SELECT orderid, custid, empid, orderdate
FROM Sales.Orders
WHERE orderdate = '20150212';

SET LANGUAGE us_english;

SELECT orderid, custid, empid, orderdate
FROM Sales.Orders
WHERE orderdate = '20150212';

-- Explicit conversion/parsing
SELECT CONVERT(DATE, '02/12/2015', 101);
SELECT PARSE('02/12/2015' AS DATE USING 'en-US');

SELECT CONVERT(DATE, '12/02/2015', 103);
SELECT PARSE('12/02/2015' AS DATE USING 'en-GB');

---------------------------------------------------------------------
-- Identifying Weekday
---------------------------------------------------------------------

-- Language-neutral weekday
-- Following calclations assume Monday as the first day of week

-- Diff and modulo method
SELECT DATEDIFF(day, '19000101', SYSDATETIME()) % 7 + 1;

-- Compensation method
SELECT DATEPART(weekday, DATEADD(day, @@DATEFIRST - 1, SYSDATETIME()));

---------------------------------------------------------------------
-- Handling Date-only or Time-only Data with DATETIME and SMALLDATETIME
---------------------------------------------------------------------

-- Date

-- Method 1
SELECT CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME);

-- Method 2
SELECT DATEADD(day, DATEDIFF(day, '19000101', SYSDATETIME()), '19000101');

-- Time
SELECT CAST(CAST(SYSDATETIME() AS TIME) AS DATETIME);

---------------------------------------------------------------------
-- First, Last, Previous, Next Date Calculations
---------------------------------------------------------------------

---------------------------------------------------------------------
-- First or Last Day of a Period
---------------------------------------------------------------------

-- Reminder: date only
SELECT DATEADD(day, DATEDIFF(day, '19000101', SYSDATETIME()), '19000101');

-- First day of the month
SELECT DATEADD(month, DATEDIFF(month, '19000101', SYSDATETIME()), '19000101');
SELECT DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1);

-- Last day of the month
SELECT DATEADD(month, DATEDIFF(month, '18991231', SYSDATETIME()), '18991231');
SELECT EOMONTH(SYSDATETIME());

-- First day of the year
SELECT DATEADD(year, DATEDIFF(year, '19000101', SYSDATETIME()), '19000101');
SELECT DATEFROMPARTS(YEAR(SYSDATETIME()), 1, 1);

-- Last day of the year
SELECT DATEADD(year, DATEDIFF(year, '18991231', SYSDATETIME()), '18991231');
SELECT DATEFROMPARTS(YEAR(SYSDATETIME()), 12, 31);

---------------------------------------------------------------------
-- Previous or Next Weekday
---------------------------------------------------------------------

-- Last Monday (Inclusive)
SELECT DATEADD(
         day,
         DATEDIFF(
           day,
           '19000101', -- Base Monday date
           SYSDATETIME()) /7*7,
         '19000101'); -- Base Monday date

-- Formatted in one line
SELECT DATEADD(day, DATEDIFF(day, '19000101', SYSDATETIME()) /7*7, '19000101');

-- Last Tuesday
SELECT DATEADD(day, DATEDIFF(day, '19000102', SYSDATETIME()) /7*7, '19000102');

-- Last Sunday
SELECT DATEADD(day, DATEDIFF(day, '19000107', SYSDATETIME()) /7*7, '19000107');

-- Last Monday (Exclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000101', DATEADD(day, -1, SYSDATETIME())) /7*7, '19000101');

-- Next Monday (Inclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000101', DATEADD(day, -1, SYSDATETIME())) /7*7 + 7, '19000101');

-- Next Tuesday (Inclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000102', DATEADD(day, -1, SYSDATETIME())) /7*7 + 7, '19000102');

-- Next Sunday (Inclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000107', DATEADD(day, -1, SYSDATETIME())) /7*7 + 7, '19000107');

-- Next Monday (Exclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000101', SYSDATETIME()) /7*7 + 7, '19000101');

-- Next Tuesday (Exclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000102', SYSDATETIME()) /7*7 + 7, '19000102');

-- Next Sunday (Exclusive)
SELECT DATEADD(day, DATEDIFF(day, '19000107', SYSDATETIME()) /7*7 + 7, '19000107');

-- Reminder: date of the first day of the current month
SELECT DATEADD(month, DATEDIFF(month, '19000101', SYSDATETIME()), '19000101');

-- Reminder: next occurrence of a weekday, inclusive (next Monday in this example)
SELECT DATEADD(day, DATEDIFF(day, '19000101', DATEADD(day, -1, SYSDATETIME())) /7*7 + 7, '19000101');

-- Date of the first occurrence of a Monday in this month
SELECT DATEADD(day, DATEDIFF(day, '19000101', 
  -- first day of month
  DATEADD(month, DATEDIFF(month, '19000101', SYSDATETIME()), '19000101')
    -1) /7*7 + 7, '19000101');

-- Date of the first occurrence of a Tuesday in this month
SELECT DATEADD(day, DATEDIFF(day, '19000102', 
  -- first day of month
  DATEADD(month, DATEDIFF(month, '19000101', SYSDATETIME()), '19000101')
    -1) /7*7 + 7, '19000102');

-- Reminder: date of the last day of the current month
SELECT DATEADD(month, DATEDIFF(month, '18991231', SYSDATETIME()), '18991231');

-- Reminder: date of the last occurrence of a weekday (Monday in this example)
SELECT DATEADD(day, DATEDIFF(day, '19000101', SYSDATETIME()) /7*7, '19000101');

-- Last occurrence of a Monday of the current month
SELECT DATEADD(day, DATEDIFF(day, '19000101',
  -- last day of month
  DATEADD(month, DATEDIFF(month, '18991231', SYSDATETIME()), '18991231')
  ) /7*7, '19000101');

-- Last occurrence of a Tuesday of the current month
SELECT DATEADD(day, DATEDIFF(day, '19000102',
  -- last day of month
  DATEADD(month, DATEDIFF(month, '18991231', SYSDATETIME()), '18991231')
  ) /7*7, '19000102');

-- First occurrence of a Monday in the current year
SELECT DATEADD(day, DATEDIFF(day, '19000101', 
  -- first day of year
  DATEADD(year, DATEDIFF(year, '19000101', SYSDATETIME()), '19000101')
    -1) /7*7 + 7, '19000101');

-- First occurrence of a Tuesday in the current year
SELECT DATEADD(day, DATEDIFF(day, '19000102', 
  -- first day of year
  DATEADD(year, DATEDIFF(year, '19000101', SYSDATETIME()), '19000101')
    -1) /7*7 + 7, '19000102');

-- Fast occurrence of a Monday in the current year
SELECT DATEADD(day, DATEDIFF(day, '19000101',
  -- last day of year
  DATEADD(year, DATEDIFF(year, '18991231', SYSDATETIME()), '18991231')
  ) /7*7, '19000101');

-- Fast occurrence of a Tuesday in the current year
SELECT DATEADD(day, DATEDIFF(day, '19000102',
  -- last day of year
  DATEADD(year, DATEDIFF(year, '18991231', SYSDATETIME()), '18991231')
  ) /7*7, '19000102');

---------------------------------------------------------------------
-- Search Argument
---------------------------------------------------------------------

USE PerformanceV3;

-- Not a search argument
SELECT orderid, orderdate, filler
FROM dbo.Orders
WHERE YEAR(orderdate) = 2014;

-- Search argument
SELECT orderid, orderdate, filler
FROM dbo.Orders
WHERE orderdate >= '20140101'
  AND orderdate < '20150101';

-- Exception where SQL Server does perform an index seek
SELECT orderid, orderdate, filler
FROM dbo.Orders
WHERE CAST(orderdate AS DATE) = '20140212';

-- Recommended form
SELECT orderid, orderdate, filler
FROM dbo.Orders
WHERE orderdate >= '20140212'
  AND orderdate < '20140213';

---------------------------------------------------------------------
-- Rounding Problems
---------------------------------------------------------------------

-- Sample data
USE TSQLV3;
IF OBJECT_ID(N'Sales.MyOrders', N'U') IS NOT NULL DROP TABLE Sales.MyOrders;
GO

SELECT * INTO Sales.MyOrders FROM Sales.Orders;
ALTER TABLE Sales.MyOrders ALTER COLUMN orderdate DATETIME NOT NULL;
CREATE CLUSTERED INDEX idx_cl_od ON Sales.MyOrders(orderdate);
GO

-- Return orders from January 1st, 2015

-- Here .999 rounds to the next second
SELECT orderid, orderdate, custid, empid
FROM Sales.MyOrders
WHERE orderdate BETWEEN '20150101' AND '20150101 23:59:59.999';

-- Best practice
SELECT orderid, orderdate, custid, empid
FROM Sales.MyOrders
WHERE orderdate >= '20150101'
  AND orderdate < '20150102';

-- Return orders from today
SELECT orderid, orderdate, custid, empid
FROM Sales.MyOrders
WHERE orderdate >= CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME)
  AND orderdate < DATEADD(day, 1, CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME));

-- cleanup
IF OBJECT_ID(N'Sales.MyOrders', N'U') IS NOT NULL DROP TABLE Sales.MyOrders;
GO

-- Rounding and flooring of SMALLDATETIME to the closest minute
SELECT
  SYSDATETIME() AS currentdatetime,
  CAST(SYSDATETIME() AS SMALLDATETIME) AS roundedtominute,
  CAST(DATEADD(ss, -30, SYSDATETIME()) AS SMALLDATETIME) AS flooredtominute;

-- Rounding and flooring of DATETIME2 to the closest second
SELECT
  SYSDATETIME() AS currentdatetime,
  CAST(SYSDATETIME() AS DATETIME2(0)) AS roundedtosecond,
  CAST(DATEADD(ms, -500, SYSDATETIME()) AS DATETIME2(0)) AS flooredtosecond;

---------------------------------------------------------------------
-- Querying Date and Time Data
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Grouping by the Week
---------------------------------------------------------------------

USE TSQLV3;

SELECT
  startofweek,
  DATEADD(day, 6, startofweek) AS endofweek,
  SUM(val) AS totalval,
  COUNT(*) AS numorders
FROM Sales.OrderValues
  CROSS APPLY ( VALUES( DATEPART(weekday, DATEADD(day, @@DATEFIRST -1, orderdate)) ) ) AS A1(wd)
  CROSS APPLY ( VALUES( wd - 1 ) ) AS A2(dist)
  CROSS APPLY ( VALUES( DATEADD(day, -dist, orderdate) ) ) AS A3(startofweek)
GROUP BY startofweek;

---------------------------------------------------------------------
-- Intervals
---------------------------------------------------------------------

-- Run the following code to create and populate 
-- the Users and Sessions tables in tempdb:

SET NOCOUNT ON;
USE tempdb;

IF OBJECT_ID('dbo.Sessions') IS NOT NULL DROP TABLE dbo.Sessions;
IF OBJECT_ID('dbo.Accounts') IS NOT NULL DROP TABLE dbo.Accounts;

CREATE TABLE dbo.Accounts
(
  actid INT NOT NULL,
  CONSTRAINT PK_Accounts PRIMARY KEY(actid)
);
GO

INSERT INTO dbo.Accounts(actid) VALUES(1), (2), (3);

CREATE TABLE dbo.Sessions
(
  sessionid INT          NOT NULL IDENTITY(1, 1),
  actid     INT          NOT NULL,
  starttime DATETIME2(0) NOT NULL,
  endtime   DATETIME2(0) NOT NULL,
  CONSTRAINT PK_Sessions PRIMARY KEY(sessionid),
  CONSTRAINT CHK_endtime_gteq_starttime
    CHECK (endtime >= starttime)
);
GO

INSERT INTO dbo.Sessions(actid, starttime, endtime) VALUES
  (1, '20151231 08:00:00', '20151231 08:30:00'),
  (1, '20151231 08:30:00', '20151231 09:00:00'),
  (1, '20151231 09:00:00', '20151231 09:30:00'),
  (1, '20151231 10:00:00', '20151231 11:00:00'),
  (1, '20151231 10:30:00', '20151231 12:00:00'),
  (1, '20151231 11:30:00', '20151231 12:30:00'),
  (2, '20151231 08:00:00', '20151231 10:30:00'),
  (2, '20151231 08:30:00', '20151231 10:00:00'),
  (2, '20151231 09:00:00', '20151231 09:30:00'),
  (2, '20151231 11:00:00', '20151231 11:30:00'),
  (2, '20151231 11:32:00', '20151231 12:00:00'),
  (2, '20151231 12:04:00', '20151231 12:30:00'),
  (3, '20151231 08:00:00', '20151231 09:00:00'),
  (3, '20151231 08:00:00', '20151231 08:30:00'),
  (3, '20151231 08:30:00', '20151231 09:00:00'),
  (3, '20151231 09:30:00', '20151231 09:30:00');
GO

-- For performance testing you can use the following code,
-- which creates a large set of sample data:

-- 10,000,000 intervals
DECLARE 
  @num_accounts            AS INT          = 50,
  @sessions_per_account    AS INT          = 200000,
  @start_period            AS DATETIME2(3) = '20120101',
  @end_period              AS DATETIME2(3) = '20160101',
  @max_duration_in_seconds AS INT          = 3600; -- 1 hour
  
TRUNCATE TABLE dbo.Sessions;
TRUNCATE TABLE dbo.Accounts;

INSERT INTO dbo.Accounts(actid)
  SELECT A.n AS actid
  FROM TSQLV3.dbo.GetNums(1, @num_accounts) AS A;

WITH C AS
(
  SELECT A.n AS actid,
    DATEADD(second,
      ABS(CHECKSUM(NEWID())) %
        (DATEDIFF(s, @start_period, @end_period) - @max_duration_in_seconds),
      @start_period) AS starttime
  FROM TSQLV3.dbo.GetNums(1, @num_accounts) AS A
    CROSS JOIN TSQLV3.dbo.GetNums(1, @sessions_per_account) AS I
)
INSERT INTO dbo.Sessions WITH (TABLOCK) (actid, starttime, endtime)
  SELECT actid, starttime,
    DATEADD(second,
      ABS(CHECKSUM(NEWID())) % (@max_duration_in_seconds + 1),
      starttime) AS endtime
  FROM C;
GO

---------------------------------------------------------------------
-- Intersection
---------------------------------------------------------------------

-- Index on start, end
CREATE UNIQUE INDEX idx_start_end ON dbo.Sessions(actid, starttime, endtime, sessionid);
GO

-- Query
DECLARE 
  @actid AS INT = 1,
  @s     AS DATETIME2(0) = '20151231 11:00:00',
  @e     AS DATETIME2(0) = '20151231 12:00:00';

SELECT sessionid, actid, starttime, endtime
FROM dbo.Sessions
WHERE actid = @actid
  AND starttime <= @e
  AND endtime >= @s
OPTION(RECOMPILE);
GO

-- Create index on endtime, starttime
CREATE UNIQUE INDEX idx_end_start ON dbo.Sessions(actid, endtime, starttime, sessionid);

-- Rerun query
DECLARE 
  @actid AS INT = 1,
  @s     AS DATETIME2(0) = '20151231 11:00:00',
  @e     AS DATETIME2(0) = '20151231 12:00:00';

SELECT sessionid, actid, starttime, endtime
FROM dbo.Sessions
WHERE actid = @actid
  AND starttime <= @e
  AND endtime >= @s
OPTION(RECOMPILE);
GO

-- Cleanup (keep index idx_start_end)
DROP INDEX idx_end_start ON dbo.Sessions;

----------------------------------------------------------------------
-- Max Concurrent Intervals
----------------------------------------------------------------------

-- Make sure you have the index idx_start_end
CREATE UNIQUE INDEX idx_start_end ON dbo.Sessions(actid, starttime, endtime, sessionid);

-- Traditional set-based solution

-- Step 1: Return start event time stamps
WITH P AS -- time points
(
  SELECT actid, starttime AS ts FROM dbo.Sessions
)
SELECT actid, ts FROM P;

-- Step 2: Compute counts at start events
WITH P AS -- time points
(
  SELECT actid, starttime AS ts FROM dbo.Sessions
),
C AS -- counts
(
  SELECT actid, ts,
    (SELECT COUNT(*)
     FROM dbo.Sessions AS S
     WHERE P.actid = S.actid
       AND P.ts >= S.starttime
       AND P.ts < S.endtime) AS cnt
  FROM P
)      
SELECT actid, ts, cnt FROM C;

-- Complete solution query
WITH P AS -- time points
(
  SELECT actid, starttime AS ts FROM dbo.Sessions
),
C AS -- counts
(
  SELECT actid, ts,
    (SELECT COUNT(*)
     FROM dbo.Sessions AS S
     WHERE P.actid = S.actid
       AND P.ts >= S.starttime
       AND P.ts < S.endtime) AS cnt
  FROM P
)      
SELECT actid, MAX(cnt) AS mx
FROM C
GROUP BY actid;

-- Cleanup
DROP INDEX idx_start_end ON dbo.Sessions;

-- Solution using window aggregate function

-- Indexes
CREATE UNIQUE INDEX idx_start ON dbo.Sessions(actid, starttime, sessionid);
CREATE UNIQUE INDEX idx_end ON dbo.Sessions(actid, endtime, sessionid);

-- Step 1: Chronological sequence of events
WITH C1 AS
(
  SELECT actid, starttime AS ts, +1 AS type
  FROM dbo.Sessions

  UNION ALL

  SELECT actid, endtime AS ts, -1 AS type
  FROM dbo.Sessions
)
SELECT actid, ts, type
FROM C1
ORDER BY actid, ts, type;

-- Step 2: Compute counts
WITH C1 AS
(
  SELECT actid, starttime AS ts, +1 AS type
  FROM dbo.Sessions

  UNION ALL

  SELECT actid, endtime AS ts, -1 AS type
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    SUM(type) OVER(PARTITION BY actid
                   ORDER BY ts, type
                   ROWS UNBOUNDED PRECEDING) AS cnt
  FROM C1
)
SELECT actid, ts, type, cnt FROM C2;

-- Complete solution
WITH C1 AS
(
  SELECT actid, starttime AS ts, +1 AS type
  FROM dbo.Sessions

  UNION ALL

  SELECT actid, endtime AS ts, -1 AS type
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    SUM(type) OVER(PARTITION BY actid
                   ORDER BY ts, type
                   ROWS UNBOUNDED PRECEDING) AS cnt
  FROM C1
)
SELECT actid, MAX(cnt) AS mx
FROM C2
GROUP BY actid;

-- Solution using ROW_NUMBER

-- Step 1: Compute ordinals s and se
WITH C1 AS
(
  SELECT actid, starttime AS ts, +1 AS type, sessionid,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY starttime, sessionid) AS s
  FROM dbo.Sessions

  UNION ALL

  SELECT actid, endtime AS ts, -1 AS type, sessionid, NULL AS s
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY ts, type, sessionid) AS se
  FROM C1
)
SELECT sessionid, actid, ts, type, s, se FROM C2;

-- Complete solution
WITH C1 AS
(
  SELECT actid, starttime AS ts, +1 AS type, sessionid,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY starttime, sessionid) AS s
  FROM dbo.Sessions

  UNION ALL

  SELECT actid, endtime AS ts, -1 AS type, sessionid, NULL AS s
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY ts, type, sessionid) AS se
  FROM C1
)
SELECT actid, MAX(cnt) AS mx
FROM C2
  CROSS APPLY ( VALUES( s - (se - s) ) ) AS A(cnt)
GROUP BY actid;
GO

-- Encapsulate logic for single account in inline TVF
IF OBJECT_ID(N'dbo.MaxConcurrent', N'IF') IS NOT NULL
  DROP FUNCTION dbo.MaxConcurrent;
GO
CREATE FUNCTION dbo.MaxConcurrent( @actid AS INT ) RETURNS TABLE
AS
RETURN
WITH C1 AS
(
  SELECT starttime AS ts, +1 AS type, sessionid,
    ROW_NUMBER() OVER(ORDER BY starttime, sessionid) AS s
  FROM dbo.Sessions
  WHERE actid = @actid

  UNION ALL

  SELECT endtime AS ts, -1 AS type, sessionid, NULL AS s
  FROM dbo.Sessions
  WHERE actid = @actid
),
C2 AS
(
  SELECT *,
    ROW_NUMBER() OVER(ORDER BY ts, type, sessionid) AS se
  FROM C1
)
SELECT MAX(cnt) AS mx
FROM C2
  CROSS APPLY ( VALUES( s - (se - s) ) ) AS A(cnt);
GO

-- Query
SELECT A.actid, C.mx
FROM dbo.Accounts AS A
  CROSS APPLY dbo.MaxConcurrent(A.actid) AS C
OPTION(QUERYTRACEON 8649);

----------------------------------------------------------------------
-- Packing Intervals
----------------------------------------------------------------------

-- Indexes
CREATE UNIQUE INDEX idx_start ON dbo.Sessions(actid, starttime, sessionid);
CREATE UNIQUE INDEX idx_end ON dbo.Sessions(actid, endtime, sessionid);

-- Solution Using Window Aggregate

-- Steps 1 and 2
WITH C1 AS
(
  SELECT sessionid, actid, starttime AS ts, +1 AS type
  FROM dbo.Sessions

  UNION ALL

  SELECT sessionid, actid, endtime AS ts, -1 AS type
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    SUM(type) OVER(PARTITION BY actid
                   ORDER BY ts, type DESC
                   ROWS UNBOUNDED PRECEDING)
      - CASE WHEN type = 1 THEN 1 ELSE 0 END AS cnt
  FROM C1
)
SELECT sessionid, actid, ts, type, cnt FROM C2;

-- Complete solution
WITH C1 AS
(
  SELECT sessionid, actid, starttime AS ts, +1 AS type
  FROM dbo.Sessions

  UNION ALL

  SELECT sessionid, actid, endtime AS ts, -1 AS type
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    SUM(type) OVER(PARTITION BY actid
                   ORDER BY ts, type DESC
                   ROWS UNBOUNDED PRECEDING)
      - CASE WHEN type = 1 THEN 1 ELSE 0 END AS cnt
  FROM C1
),
C3 AS
(
  SELECT *, 
    FLOOR((ROW_NUMBER() OVER(PARTITION BY actid ORDER BY ts) + 1) / 2) AS p
  FROM C2
  WHERE cnt = 0
)
SELECT actid, MIN(ts) AS starttime, max(ts) AS endtime
FROM C3
GROUP BY actid, p;

-- Solution using row numbers
WITH C1 AS
(
  SELECT sessionid, actid, starttime AS ts, +1 AS type,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY starttime, sessionid) AS s,
    NULL AS e
  FROM dbo.Sessions

  UNION ALL

  SELECT sessionid, actid, endtime AS ts, -1 AS type, 
    NULL AS s,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY endtime, sessionid) AS e
  FROM dbo.Sessions
),
C2 AS
(
  SELECT *,
    ROW_NUMBER() OVER(PARTITION BY actid ORDER BY ts, type DESC, sessionid) AS se
  FROM C1
),
C3 AS
(
  SELECT *, 
    FLOOR((ROW_NUMBER() OVER(PARTITION BY actid ORDER BY ts) + 1) / 2) AS p
  FROM C2
    CROSS APPLY ( VALUES(s - (se - s) - 1, (se - e) - e) ) AS A(cs, ce)
  WHERE cs = 0 OR ce = 0
)
SELECT actid, MIN(ts) AS starttime, MAX(ts) AS endtime
FROM C3
GROUP BY actid, p;
GO

-- Encapsulate logic for single account in inline UDF
IF OBJECT_ID(N'dbo.PackedIntervals', N'IF') IS NOT NULL DROP FUNCTION dbo.PackedIntervals;
GO
CREATE FUNCTION dbo.PackedIntervals( @actid AS INT ) RETURNS TABLE
AS
RETURN
WITH C1 AS
(
  SELECT sessionid, starttime AS ts, +1 AS type,
    ROW_NUMBER() OVER(ORDER BY starttime, sessionid) AS s,
    NULL AS e
  FROM dbo.Sessions
  WHERE actid = @actid

  UNION ALL

  SELECT sessionid, endtime AS ts, -1 AS type, 
    NULL AS s,
    ROW_NUMBER() OVER(ORDER BY endtime, sessionid) AS e
  FROM dbo.Sessions
  WHERE actid = @actid
),
C2 AS
(
  SELECT *,
    ROW_NUMBER() OVER(ORDER BY ts, type DESC, sessionid) AS se
  FROM C1
),
C3 AS
(
  SELECT *, 
    FLOOR((ROW_NUMBER() OVER(ORDER BY ts) + 1) / 2) AS p
  FROM C2
    CROSS APPLY ( VALUES(s - (se - s) - 1, (se - e) - e) ) AS A(cs, ce)
  WHERE cs = 0 OR ce = 0
)
SELECT MIN(ts) AS starttime, MAX(ts) AS endtime
FROM C3
GROUP BY p;
GO

-- Query
SELECT A.actid, P.starttime, P.endtime
FROM dbo.Accounts AS A
  CROSS APPLY dbo.PackedIntervals(A.actid) AS P
OPTION(QUERYTRACEON 8649);
