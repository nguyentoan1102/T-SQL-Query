---------------------------------------------------------------------
-- T-SQL Querying (Microsoft Press, 2015)
-- Chapter 06 - Data Modification
-- © Itzik Ben-Gan
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Inserting Data
---------------------------------------------------------------------

---------------------------------------------------------------------
-- SELECT INTO
---------------------------------------------------------------------

-- Make sure MyOrders doesn't exist
SET NOCOUNT ON;
USE PerformanceV3;
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;
GO

-- Create MyOrders as a copy of Orders
SELECT orderid, custid, empid, shipperid, orderdate, filler
INTO dbo.MyOrders
FROM dbo.Orders;
GO

-- Blocking related to metadata

-- Make sure MyOrders doesn't exist
USE PerformanceV3;
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

-- From connection 1
USE PerformanceV3;

BEGIN TRAN;

SELECT orderid, custid, empid, shipperid, orderdate, filler
INTO dbo.MyOrders
FROM dbo.Orders;

-- From connection 2 (blocked)
USE PerformanceV3;
SELECT SCHEMA_NAME(schema_id) AS schemaname, name AS tablename FROM sys.tables;

-- From connection 1
COMMIT TRAN;

-- In connection 2, query completes

---------------------------------------------------------------------
-- Bulk Import
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Measuring Amount of Logging
---------------------------------------------------------------------

-- Query to check amount of logging
USE PerformanceV3;

SELECT COUNT(*) AS numrecords, SUM(CAST([Log Record Length] AS BIGINT)) / 1048576. AS sizemb
FROM sys.fn_dblog(null, null);

-- Test full logging

-- Set recovery to FULL and backup database to get out of log truncate mode
ALTER DATABASE PerformanceV3 SET RECOVERY FULL;
BACKUP DATABASE PerformanceV3 TO DISK = 'C:\temp\PerfV3Data.BAK' WITH INIT;
BACKUP LOG PerformanceV3 TO DISK = 'C:\temp\PerfV3Log.BAK' WITH INIT;
GO

-- Import operation
CHECKPOINT;

BEGIN TRAN;

DECLARE
  @numrecords AS INT, @sizemb AS NUMERIC(12, 2), @starttime AS DATETIME2, @endtime AS DATETIME2;

-- Drop table if exists
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

-- Stats before import
SELECT
  @numrecords = COUNT(*),
  @sizemb = SUM(CAST([Log Record Length] AS BIGINT)) / 1048576.
FROM sys.fn_dblog(null, null);

SET @starttime = SYSDATETIME();

-- Import data
SELECT orderid, custid, empid, shipperid, orderdate, filler
INTO dbo.MyOrders
FROM dbo.Orders;

-- Stats after import
SET @endtime = SYSDATETIME();

SELECT
  COUNT(*) - @numrecords AS numrecords,
  SUM(CAST([Log Record Length] AS BIGINT)) / 1048576. - @sizemb AS sizemb,
  DATEDIFF(ms, @starttime, @endtime) AS durationms
FROM sys.fn_dblog(null, null);

COMMIT TRAN;

-- Cleanup
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

CHECKPOINT;
GO

-- Test optimized logging

-- Set recovery to SIMPLE
ALTER DATABASE PerformanceV3 SET RECOVERY SIMPLE;
GO

-- Import operation
CHECKPOINT;

BEGIN TRAN;

DECLARE @numrecords AS INT, @sizemb AS NUMERIC(12, 2), @starttime AS DATETIME2, @endtime AS DATETIME2;

-- Drop table if exists
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

-- Stats before import
SELECT
  @numrecords = COUNT(*),
  @sizemb = SUM(CAST([Log Record Length] AS BIGINT)) / 1048576.
FROM sys.fn_dblog(null, null);

SET @starttime = SYSDATETIME();

-- Import data
SELECT orderid, custid, empid, shipperid, orderdate, filler
INTO dbo.MyOrders
FROM dbo.Orders;

-- Stats after import
SET @endtime = SYSDATETIME();

SELECT
  COUNT(*) - @numrecords AS numrecords,
  SUM(CAST([Log Record Length] AS BIGINT)) / 1048576. - @sizemb AS sizemb,
  DATEDIFF(ms, @starttime, @endtime) AS durationms
FROM sys.fn_dblog(null, null);

COMMIT TRAN;

-- Cleanup
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

CHECKPOINT;
GO

---------------------------------------------------------------------
-- BULK Rowset Provider
---------------------------------------------------------------------

-- To create the format file run the following from a command prompt
-- bcp TSQLV3.Sales.Shippers format nul -c -f Shippers.fmt -T -S <server_name\instance_name>

-- Query as a set
SELECT shipperid, companyname, phone
FROM OPENROWSET(BULK 'C:\temp\Shippers.txt',
                FORMATFILE = 'C:\temp\Shippers.fmt') AS F;

-- Insert
INSERT INTO TargetTable WITH (TABLOCK) (shipperid, companyname, phone)
  SELECT shipperid, companyname, phone
  FROM OPENROWSET(BULK 'C:\temp\Shippers.txt',
         FORMATFILE = 'C:\temp\Shippers.fmt') AS F
  WHERE phone LIKE '(503) 555-9%';
GO

-- Query as a single value

-- Target table T1
USE tempdb;

IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;

CREATE TABLE dbo.T1
(
  id       INT          NOT NULL PRIMARY KEY,
  xmlval   XML          NULL,
  textval  VARCHAR(MAX) NULL,
  ntextval NVARCHAR(MAX) NULL,
  binval   VARBINARY(MAX) NULL  
);
GO

-- Example with INSERT
INSERT INTO dbo.T1(id, xmlval)
  VALUES( 1,
    (SELECT xmlval FROM OPENROWSET(
       BULK 'C:\temp\xmlfile.xml', SINGLE_NCLOB) AS F(xmlval)) );

-- Example with UPDATE
UPDATE dbo.T1
  SET textval  = (SELECT textval FROM OPENROWSET(
    BULK 'C:\temp\textfile.txt', SINGLE_CLOB) AS F(textval)),
      ntextval = (SELECT ntextval FROM OPENROWSET(
    BULK 'C:\temp\ntextfile.txt', SINGLE_NCLOB) AS F(ntextval)),
      binval   = (SELECT binval FROM OPENROWSET(
    BULK 'C:\temp\binfile.jpg', SINGLE_BLOB) AS F(binval))
WHERE id = 1;

SELECT id, xmlval, textval, ntextval, binval
FROM dbo.T1
WHERE id = 1;

---------------------------------------------------------------------
-- Sequences
---------------------------------------------------------------------

---------------------------------------------------------------------
-- The Sequence Object
---------------------------------------------------------------------

-- Create sequence for order IDs
USE PerformanceV3;

IF OBJECT_ID(N'dbo.Seqorderids', N'SO') IS NOT NULL DROP SEQUENCE dbo.Seqorderids;

CREATE SEQUENCE dbo.Seqorderids AS INT
  MINVALUE 1
  CYCLE
  CACHE 1000;

-- Request new value
SELECT NEXT VALUE FOR dbo.Seqorderids;

-- Query Information about Sequences
SELECT current_value, start_value, increment, minimum_value, maximum_value, is_cycling,
  is_cached, cache_size
FROM sys.Sequences
WHERE object_id = OBJECT_ID(N'dbo.Seqorderids', N'SO');

-- Can be used in DEFAULT constraint
ALTER TABLE dbo.Orders
  ADD CONSTRAINT DFT_Orders_orderid
    DEFAULT(NEXT VALUE FOR dbo.Seqorderids) FOR orderid;

-- Can drop constraint at any point
ALTER TABLE dbo.Orders DROP CONSTRAINT DFT_Orders_orderid;

-- Request value before use
DECLARE @newkey AS INT = NEXT VALUE FOR dbo.Seqorderids;
SELECT @newkey;

-- Create MyOrders table
IF OBJECT_ID(N'dbo.MyOrders', N'U') IS NOT NULL DROP TABLE dbo.MyOrders;

SELECT orderid, custid, empid, shipperid, orderdate, filler
INTO dbo.MyOrders
FROM dbo.Orders
WHERE empid = 1;

ALTER TABLE dbo.MyOrders ADD CONSTRAINT PK_MyOrders PRIMARY KEY(orderid);

-- Used in UPDATE
UPDATE dbo.MyOrders
  SET orderid = NEXT VALUE FOR dbo.Seqorderids;

-- Supports defining order in multi-row inserts
INSERT INTO dbo.MyOrders(orderid, custid, empid, shipperid, orderdate, filler)
  SELECT NEXT VALUE FOR dbo.Seqorderids OVER(ORDER BY orderid) AS orderid,
    custid, empid, shipperid, orderdate, filler
  FROM dbo.Orders
  WHERE empid = 2;
GO

-- Range
DECLARE @first AS SQL_VARIANT;

EXEC sys.sp_sequence_get_range
  @sequence_name     = N'dbo.Seqorderids',
  @range_size        = 1000000,
  @range_first_value = @first OUTPUT ;

SELECT @first;
GO

-- Can have gaps
SELECT NEXT VALUE FOR dbo.Seqorderids;
BEGIN TRAN;
  SELECT NEXT VALUE FOR dbo.Seqorderids;
ROLLBACK TRAN
SELECT NEXT VALUE FOR dbo.Seqorderids;

---------------------------------------------------------------------
-- Performance Considerations
---------------------------------------------------------------------

-- Default cache

-- Preparation
IF DB_ID(N'testdb') IS NULL CREATE DATABASE testdb;
USE testdb;

IF OBJECT_ID(N'dbo.SeqTINYINT'  , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqTINYINT;
IF OBJECT_ID(N'dbo.SeqSMALLINT' , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqSMALLINT;
IF OBJECT_ID(N'dbo.SeqINT'      , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqINT;
IF OBJECT_ID(N'dbo.SeqBIGINT'   , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqBIGINT;
IF OBJECT_ID(N'dbo.SeqNUMERIC9' , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqNUMERIC9;
IF OBJECT_ID(N'dbo.SeqNUMERIC38', N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqNUMERIC38;

IF OBJECT_ID(N'dbo.TTINYINT'  , N'U') IS NOT NULL DROP TABLE dbo.TTINYINT;
IF OBJECT_ID(N'dbo.TSMALLINT' , N'U') IS NOT NULL DROP TABLE dbo.TSMALLINT;
IF OBJECT_ID(N'dbo.TINT'      , N'U') IS NOT NULL DROP TABLE dbo.TINT;
IF OBJECT_ID(N'dbo.TBIGINT'   , N'U') IS NOT NULL DROP TABLE dbo.TBIGINT;
IF OBJECT_ID(N'dbo.TNUMERIC9' , N'U') IS NOT NULL DROP TABLE dbo.TNUMERIC9;
IF OBJECT_ID(N'dbo.TNUMERIC38', N'U') IS NOT NULL DROP TABLE dbo.TNUMERIC38;

CREATE SEQUENCE dbo.SeqTINYINT   AS TINYINT        MINVALUE 1;
CREATE SEQUENCE dbo.SeqSMALLINT  AS SMALLINT       MINVALUE 1;
CREATE SEQUENCE dbo.SeqINT       AS INT            MINVALUE 1;
CREATE SEQUENCE dbo.SeqBIGINT    AS BIGINT         MINVALUE 1;
CREATE SEQUENCE dbo.SeqNUMERIC9  AS NUMERIC( 9, 0) MINVALUE 1;
CREATE SEQUENCE dbo.SeqNUMERIC38 AS NUMERIC(38, 0) MINVALUE 1;

CREATE TABLE dbo.TTINYINT  (keycol TINYINT        IDENTITY);
CREATE TABLE dbo.TSMALLINT (keycol SMALLINT       IDENTITY);
CREATE TABLE dbo.TINT      (keycol INT            IDENTITY);
CREATE TABLE dbo.TBIGINT   (keycol BIGINT         IDENTITY);
CREATE TABLE dbo.TNUMERIC9 (keycol NUMERIC( 9, 0) IDENTITY);
CREATE TABLE dbo.TNUMERIC38(keycol NUMERIC(38, 0) IDENTITY);
GO

SELECT
  NEXT VALUE FOR dbo.SeqTINYINT  ,
  NEXT VALUE FOR dbo.SeqSMALLINT ,
  NEXT VALUE FOR dbo.SeqINT      ,
  NEXT VALUE FOR dbo.SeqBIGINT   ,
  NEXT VALUE FOR dbo.SeqNUMERIC9 ,
  NEXT VALUE FOR dbo.SeqNUMERIC38;
GO 5

INSERT INTO dbo.TTINYINT   DEFAULT VALUES;
INSERT INTO dbo.TSMALLINT  DEFAULT VALUES;
INSERT INTO dbo.TINT       DEFAULT VALUES;
INSERT INTO dbo.TBIGINT    DEFAULT VALUES;
INSERT INTO dbo.TNUMERIC9  DEFAULT VALUES;
INSERT INTO dbo.TNUMERIC38 DEFAULT VALUES;
GO 5

SELECT name, current_value FROM sys.Sequences
WHERE object_id IN
  ( OBJECT_ID(N'dbo.SeqTINYINT  '),
    OBJECT_ID(N'dbo.SeqSMALLINT '),
    OBJECT_ID(N'dbo.SeqINT      '),
    OBJECT_ID(N'dbo.SeqBIGINT   '),
    OBJECT_ID(N'dbo.SeqNUMERIC9 '),
    OBJECT_ID(N'dbo.SeqNUMERIC38') );

SELECT
  IDENT_CURRENT(N'dbo.TTINYINT  ') AS TTINYINT  ,
  IDENT_CURRENT(N'dbo.TSMALLINT ') AS TSMALLINT ,
  IDENT_CURRENT(N'dbo.TINT      ') AS TINT      ,
  IDENT_CURRENT(N'dbo.TBIGINT   ') AS TBIGINT   ,
  IDENT_CURRENT(N'dbo.TNUMERIC9 ') AS TNUMERIC9 ,
  IDENT_CURRENT(N'dbo.TNUMERIC38') AS TNUMERIC38;

-- Kill the SQL Server service from Task Manager and start the service (not sufficient to restart service)
USE testdb;

SELECT name, current_value FROM sys.Sequences
WHERE object_id IN
  ( OBJECT_ID(N'dbo.SeqTINYINT  '),
    OBJECT_ID(N'dbo.SeqSMALLINT '),
    OBJECT_ID(N'dbo.SeqINT      '),
    OBJECT_ID(N'dbo.SeqBIGINT   '),
    OBJECT_ID(N'dbo.SeqNUMERIC9 '),
    OBJECT_ID(N'dbo.SeqNUMERIC38') );

SELECT
  IDENT_CURRENT(N'dbo.TTINYINT  ') AS TTINYINT  ,
  IDENT_CURRENT(N'dbo.TSMALLINT ') AS TSMALLINT ,
  IDENT_CURRENT(N'dbo.TINT      ') AS TINT      ,
  IDENT_CURRENT(N'dbo.TBIGINT   ') AS TBIGINT   ,
  IDENT_CURRENT(N'dbo.TNUMERIC9 ') AS TNUMERIC9 ,
  IDENT_CURRENT(N'dbo.TNUMERIC38') AS TNUMERIC38;
GO

-- Generate new value
SELECT NEXT VALUE FOR dbo.SeqINT;

INSERT INTO dbo.TINT OUTPUT inserted.$identity DEFAULT VALUES;

-- Cleanup
IF OBJECT_ID(N'dbo.SeqTINYINT'  , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqTINYINT;
IF OBJECT_ID(N'dbo.SeqSMALLINT' , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqSMALLINT;
IF OBJECT_ID(N'dbo.SeqINT'      , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqINT;
IF OBJECT_ID(N'dbo.SeqBIGINT'   , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqBIGINT;
IF OBJECT_ID(N'dbo.SeqNUMERIC9' , N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqNUMERIC9;
IF OBJECT_ID(N'dbo.SeqNUMERIC38', N'SO') IS NOT NULL DROP SEQUENCE dbo.SeqNUMERIC38;

IF OBJECT_ID(N'dbo.TTINYINT'  , N'U') IS NOT NULL DROP TABLE dbo.TTINYINT;
IF OBJECT_ID(N'dbo.TSMALLINT' , N'U') IS NOT NULL DROP TABLE dbo.TSMALLINT;
IF OBJECT_ID(N'dbo.TINT'      , N'U') IS NOT NULL DROP TABLE dbo.TINT;
IF OBJECT_ID(N'dbo.TBIGINT'   , N'U') IS NOT NULL DROP TABLE dbo.TBIGINT;
IF OBJECT_ID(N'dbo.TNUMERIC9' , N'U') IS NOT NULL DROP TABLE dbo.TNUMERIC9;
IF OBJECT_ID(N'dbo.TNUMERIC38', N'U') IS NOT NULL DROP TABLE dbo.TNUMERIC38;

-- Performance test of sequences with different cache values and identity in tempdb and in a user database

-- First create the user db and a sequence in both the user db and tempdb
IF DB_ID(N'testdb') IS NULL CREATE DATABASE testdb;
ALTER DATABASE testdb SET RECOVERY SIMPLE;

USE testdb;
IF OBJECT_ID(N'dbo.Seq1', N'SO') IS NOT NULL DROP SEQUENCE dbo.Seq1;
CREATE SEQUENCE dbo.Seq1 AS INT MINVALUE 1;

USE tempdb;
IF OBJECT_ID(N'dbo.Seq1', N'SO') IS NOT NULL DROP SEQUENCE dbo.Seq1;
CREATE SEQUENCE dbo.Seq1 AS INT MINVALUE 1;
GO

-- Performance test
-- To enable TF 272: DBCC TRACEON(272, -1), to disable: DBCC TRACEOFF(272, -1)
SET NOCOUNT ON;
--USE tempdb; -- to test in tempdb
USE testdb; -- to test in user database testdb

DECLARE @numrecords AS INT, @sizemb AS NUMERIC(12, 2), @logflushes AS INT,
  @starttime AS DATETIME2, @endtime AS DATETIME2;

CHECKPOINT;

BEGIN TRAN;

  ALTER SEQUENCE dbo.Seq1 CACHE 50; -- try with CACHE 10, 50, 10000, NO CACHE
  IF OBJECT_ID(N'dbo.T', N'U') IS NOT NULL DROP TABLE dbo.T;
  
  -- Stats before
  SELECT @numrecords = COUNT(*), @sizemb = SUM(CAST([Log Record Length] AS BIGINT)) / 1048576.,
    @logflushes = (SELECT cntr_value FROM sys.dm_os_performance_counters
                   WHERE counter_name = 'Log Flushes/sec'
                         AND instance_name = 'testdb' -- to test in testdb
--                         AND instance_name = 'tempdb' -- to test in tempdb
                  )
  FROM sys.fn_dblog(null, null);
 
  SET @starttime = SYSDATETIME();

  -- Actual work
  SELECT
--    n -- to test without seq or identity
    NEXT VALUE FOR dbo.Seq1 AS n -- to test sequence
--    IDENTITY(INT, 1, 1) AS n -- to test identity
  INTO dbo.T
  FROM TSQLV3.dbo.GetNums(1, 10000000) AS N
  OPTION(MAXDOP 1);

  -- Stats after
  SET @endtime = SYSDATETIME();
 
  SELECT
    COUNT(*) - @numrecords AS numrecords,
    SUM(CAST([Log Record Length] AS BIGINT)) / 1048576. - @sizemb AS sizemb,
    (SELECT cntr_value FROM sys.dm_os_performance_counters
     WHERE counter_name = 'Log Flushes/sec'
       AND instance_name = 'testdb' -- to test in testdb
--       AND instance_name = 'tempdb' -- to test in tempdb
       ) - @logflushes AS logflushes,
    DATEDIFF(ms, @starttime, @endtime) AS durationms 
  FROM sys.fn_dblog(null, null);
 
COMMIT TRAN;
 
CHECKPOINT;

---------------------------------------------------------------------
-- Deleting Data
---------------------------------------------------------------------

---------------------------------------------------------------------
-- TRUNCATE
---------------------------------------------------------------------

-- TRUNCATE example
TRUNCATE TABLE dbo.T1;

-- Truncate but keep current identity value
-- Sample data
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;
GO

CREATE TABLE dbo.T1
(
  keycol  INT NOT NULL IDENTITY,
  datacol VARCHAR(10) NOT NULL
);

INSERT INTO dbo.T1(datacol) VALUES('A'),('B'),('C');

SELECT keycol, datacol FROM dbo.T1;

keycol      datacol
----------- ----------
1           A
2           B
3           C

-- Truncate and reseed
IF EXISTS(SELECT * FROM dbo.T1)
BEGIN
  BEGIN TRAN;
    DECLARE @tmp AS INT = (SELECT TOP (1) keycol FROM dbo.T1 WITH (TABLOCKX)); -- lock
    DECLARE @reseedval AS INT = IDENT_CURRENT(N'dbo.T1') + 1;                  -- save
    TRUNCATE TABLE dbo.T1;                                                     -- truncate
    DBCC CHECKIDENT(N'dbo.T1', RESEED, @reseedval);                            -- reseed
    PRINT 'Identity reseeded to ' + CAST(@reseedval AS VARCHAR(10)) + '.';
  COMMIT TRAN;
END
ELSE
  PRINT 'Table is empty, no need to truncate.' ;

Output:
Identity reseeded to 4.

-- Add data and query
INSERT INTO dbo.T1(datacol) VALUES('X'),('Y'),('Z');
SELECT keycol, datacol FROM dbo.T1;

-- When indexed view exists can use partition switching

-- Sample data
SET NOCOUNT ON;
USE tempdb;

IF OBJECT_ID(N'dbo.V1', N'V') IS NOT NULL DROP VIEW dbo.V1;
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;
GO

CREATE TABLE dbo.T1
(
  col1 INT NOT NULL PRIMARY KEY,
  col2 INT NOT NULL,
  col3 NUMERIC(12, 2) NOT NULL
);

INSERT INTO dbo.T1(col1, col2, col3) VALUES
  ( 2, 10,  200.00),
  ( 3, 10,  800.00),
  ( 5, 10,  100.00),
  ( 7, 20,  300.00),
  (11, 20,  500.00),
  (13, 20, 1300.00);
GO

CREATE VIEW dbo.V1 WITH SCHEMABINDING
AS

SELECT col2, SUM(col3) AS total , COUNT_BIG(*) AS cnt
FROM dbo.T1
GROUP BY col2;
GO

CREATE UNIQUE CLUSTERED INDEX idx_col2 ON dbo.V1(col2);
GO

SELECT col2, total, cnt FROM dbo.V1;
GO

-- Attempt to truncate the table fails
TRUNCATE TABLE dbo.T1;
GO

-- Solution
CREATE TABLE dbo.T1_STAGE
(
  col1 INT NOT NULL PRIMARY KEY,
  col2 INT NOT NULL,
  col3 NUMERIC(12, 2) NOT NULL
);

ALTER TABLE dbo.T1 SWITCH TO dbo.T1_STAGE;

DROP TABLE dbo.T1_STAGE;
GO

-- Cleanup
IF OBJECT_ID(N'dbo.V1', N'V') IS NOT NULL DROP VIEW dbo.V1;
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;

---------------------------------------------------------------------
-- Deleting Duplicates
---------------------------------------------------------------------

-- Sample data
USE tempdb;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;
GO

SELECT
  orderid, custid, empid, orderdate, requireddate, shippeddate, 
  shipperid, freight, shipname, shipaddress, shipcity, shipregion, 
  shippostalcode, shipcountry
INTO dbo.Orders
FROM TSQLV3.Sales.Orders
  CROSS JOIN TSQLV3.dbo.Nums
WHERE n <= 3;
GO

-- Small number of rows to delete
WITH C AS
(
  SELECT *,
    ROW_NUMBER()
      OVER(PARTITION BY orderid ORDER BY (SELECT NULL)) AS n
  FROM dbo.Orders
)
DELETE FROM C
WHERE n > 1;
GO

-- Small percent, but still large number of rows to delete
WHILE 1 = 1
BEGIN
  WITH C AS
  (
    SELECT *,
      ROW_NUMBER()
        OVER(PARTITION BY orderid ORDER BY (SELECT NULL)) AS n
    FROM dbo.Orders
  )
  DELETE TOP (3000) FROM C
  WHERE n > 1;

  IF @@ROWCOUNT < 3000 BREAK;
END;

-- Large percent and large number of rows to delete

-- Copy distinct rows to staging table
WITH C AS
(
  SELECT *,
    ROW_NUMBER()
      OVER(PARTITION BY orderid ORDER BY (SELECT NULL)) AS n
  FROM dbo.Orders
)
SELECT orderid, custid, empid, orderdate, requireddate, shippeddate, shipperid,
  freight, shipname, shipaddress, shipcity, shipregion, shippostalcode, shipcountry
INTO dbo.Orders_Stage
FROM C
WHERE n = 1;

-- Drop original table
DROP TABLE dbo.Orders;

-- Rename staging table to original table name
EXEC sp_rename N'dbo.Orders_Stage', N'Orders';

-- Create constraints, indexes, triggers and permissions on Orders
ALTER TABLE dbo.Orders ADD CONSTRAINT PK_Orders PRIMARY KEY(orderid);
GO

---------------------------------------------------------------------
-- Updating Data
---------------------------------------------------------------------

-- Sample data for UPDATE and MERGE examples
USE tempdb;

IF OBJECT_ID(N'dbo.Customers', N'U') IS NOT NULL DROP TABLE dbo.Customers;

CREATE TABLE dbo.Customers
(
  custid      INT         NOT NULL,
  companyname VARCHAR(25) NOT NULL,
  phone       VARCHAR(20) NULL,
  address     VARCHAR(50) NOT NULL,
  CONSTRAINT PK_Customers PRIMARY KEY(custid)
);
GO

INSERT INTO dbo.Customers(custid, companyname, phone, address)
  VALUES(1, 'cust 1', '(111) 111-1111', 'address 1'),
        (2, 'cust 2', '(222) 222-2222', 'address 2'),
        (3, 'cust 3', '(333) 333-3333', 'address 3'),
        (4, 'cust 4', '(444) 444-4444', 'address 4'),
        (5, 'cust 5', '(555) 555-5555', 'address 5');
GO

IF OBJECT_ID(N'dbo.CustomersStage', N'U') IS NOT NULL DROP TABLE dbo.CustomersStage;

CREATE TABLE dbo.CustomersStage
(
  custid      INT         NOT NULL,
  companyname VARCHAR(25) NOT NULL,
  phone       VARCHAR(20) NULL,
  address     VARCHAR(50) NOT NULL,
  CONSTRAINT PK_CustomersStage PRIMARY KEY(custid)
);
GO

INSERT INTO dbo.CustomersStage(custid, companyname, phone, address)
  VALUES(2, 'AAAAA', '(222) 222-2222', 'address 2'),
        (3, 'cust 3', '(333) 333-3333', 'address 3'),
        (5, 'BBBBB', 'CCCCC', 'DDDDD'),
        (6, 'cust 6 (new)', '(666) 666-6666', 'address 6'),
        (7, 'cust 7 (new)', '(777) 777-7777', 'address 7');

-- Update Using Table Expressions
WITH C AS
(
  SELECT 
    TGT.custid,
    SRC.companyname AS src_companyname,
    TGT.companyname AS tgt_companyname,
    SRC.phone       AS src_phone,
    TGT.phone       AS tgt_phone,
    SRC.address     AS src_address,
    TGT.address     AS tgt_address 
  FROM dbo.Customers AS TGT
    INNER JOIN dbo.CustomersStage AS SRC
      ON TGT.custid = SRC.custid
)
UPDATE C
  SET tgt_companyname = src_companyname,
      tgt_phone       = src_phone, 
      tgt_address     = src_address;
GO

-- Update Using Variables

-- Create and init sequence
USE tempdb;
IF OBJECT_ID(N'dbo.MySequence', N'U') IS NOT NULL DROP TABLE dbo.MySequence;
CREATE TABLE dbo.MySequence(val INT NOT NULL);
INSERT INTO dbo.MySequence(val) VALUES(0);

-- Use sequence
DECLARE @newval AS INT;
UPDATE dbo.MySequence SET @newval = val += 1;
SELECT @newval;
GO

-- Demonstrate blocking

-- Connection 1 (gets 4)
BEGIN TRAN;

  DECLARE @newval AS INT;
  UPDATE dbo.MySequence SET @newval = val += 1;
  SELECT @newval;

-- Connection 2 (is blocked)
BEGIN TRAN;

  DECLARE @newval AS INT;
  UPDATE dbo.MySequence SET @newval = val += 1;
  SELECT @newval;

-- Connection 1
ROLLBACK TRAN

-- Connection 2 (gets 4)
COMMIT TRAN;

---------------------------------------------------------------------
-- Merging Statement
---------------------------------------------------------------------

-- MERGE Examples
USE tempdb;

-- Simple MERGE example
MERGE INTO dbo.Customers AS TGT
USING dbo.CustomersStage AS SRC
  ON TGT.custid = SRC.custid
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address)
WHEN NOT MATCHED BY SOURCE THEN
  DELETE;

-- Two WHEN MATCHED clauses
WHEN MATCHED AND actiontype = 'UPDATE' THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN MATCHED AND actiontype = 'DELETE' THEN
  DELETE

-- Two WHEN NOT MATCHED BY SOURCE clauses
WHEN NOT MATCHED BY SOURCE AND CAST(SYSDATETIME() AS DATE) = EOMONTH(SYSDATETIME()) THEN
  UPDATE SET
    TGT.isdeleted = 1
WHEN NOT MATCHED BY SOURCE THEN
  DELETE

-- Update only if the row changed
MERGE INTO dbo.Customers AS TGT
USING dbo.CustomersStage AS SRC
  ON TGT.custid = SRC.custid
WHEN MATCHED AND 
       (   TGT.companyname <> SRC.companyname
        OR TGT.phone <> SRC.phone
           OR TGT.phone IS NULL AND SRC.phone IS NOT NULL
           OR TGT.phone IS NOT NULL AND SRC.phone IS NULL
        OR TGT.address <> SRC.address) THEN
-- Alternative:
-- WHEN MATCHED AND EXISTS ( SELECT TGT.* EXCEPT SELECT SRC.* ) THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address)
WHEN NOT MATCHED BY SOURCE THEN
  DELETE;

-- Preventing MERGE Conflicts
IF OBJECT_ID(N'dbo.AddCustomer', N'P') IS NOT NULL DROP PROC dbo.AddCustomer;
GO
CREATE PROC dbo.AddCustomer
  @custid INT, @companyname VARCHAR(25), @phone VARCHAR(20), @address VARCHAR(50)
AS

MERGE INTO dbo.Customers /* WITH (SERIALIZABLE) */ AS TGT
USING (VALUES(@custid, @companyname, @phone, @address))
      AS SRC(custid, companyname, phone, address)
  ON TGT.custid = SRC.custid
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address);
GO

-- Test
SET NOCOUNT ON;
USE tempdb;

WHILE 1 = 1
BEGIN
  DECLARE @curcustid AS INT = CHECKSUM(CAST(SYSDATETIME() AS DATETIME2(2)));
  EXEC dbo.AddCustomer @custid = @curcustid, @companyname = 'A', @phone = 'B', @address = 'C';
END;

-- ON Isn't a Filter
-- Following fails
MERGE INTO dbo.Customers AS TGT
USING dbo.CustomersStage AS SRC
  ON TGT.custid = SRC.custid
  AND SRC.custid = 2
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address);

-- Should filter source in a table expression
MERGE INTO dbo.Customers AS TGT
USING (SELECT * FROM dbo.CustomersStage WHERE custid = 2) AS SRC
  ON TGT.custid = SRC.custid
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address);

-- USING is Similar to FROM

-- Create a format file and a text file for the demo (run from command prompt)
-- bcp tempdb.dbo.Customers format nul -c -x -f C:\temp\CustomersFmt.xml -T -S <server\instance>
-- bcp tempdb.dbo.Customers out C:\temp\Customers.txt -c -T -S <server\instance>

MERGE INTO dbo.Customers AS TGT
USING OPENROWSET(BULK 'C:\temp\Customers.txt',
                 FORMATFILE = 'C:\temp\CustomersFmt.xml') AS SRC
  ON TGT.custid = SRC.custid
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address);

---------------------------------------------------------------------
-- The OUTPUT Clause
---------------------------------------------------------------------

-- Example with INSERT and Identity
USE tempdb;
IF OBJECT_ID(N'dbo.T1', N'U') IS NOT NULL DROP TABLE dbo.T1;
GO

CREATE TABLE dbo.T1
(
  keycol  INT          NOT NULL IDENTITY(1, 1) CONSTRAINT PK_T1 PRIMARY KEY,
  datacol NVARCHAR(40) NOT NULL
);

INSERT INTO dbo.T1(datacol)
  OUTPUT inserted.$identity, inserted.datacol
    SELECT lastname
    FROM TSQLV3.HR.Employees
    WHERE country = N'USA';
GO

-- OUTPUT INTO

-- Cleanup
TRUNCATE TABLE dbo.T1;

-- Example
DECLARE @NewRows TABLE(keycol INT, datacol NVARCHAR(40));

INSERT INTO dbo.T1(datacol)
  OUTPUT inserted.$identity, inserted.datacol
  INTO @NewRows(keycol, datacol)
    SELECT lastname
    FROM TSQLV3.HR.Employees
    WHERE country = N'USA';

SELECT keycol, datacol FROM @NewRows;
GO

-- Example for Archiving Deleted Data
IF DB_ID(N'Archive') IS NULL CREATE DATABASE Archive;
GO

USE Archive;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;

SELECT ISNULL(orderid, 0) AS orderid, orderdate, empid, custid 
INTO dbo.Orders
FROM TSQLV3.Sales.Orders WHERE 1 = 2;

ALTER TABLE dbo.Orders ADD CONSTRAINT PK_Orders PRIMARY KEY(orderid);

USE tempdb;
IF OBJECT_ID(N'dbo.Orders', N'U') IS NOT NULL DROP TABLE dbo.Orders;

SELECT orderid, orderdate, empid, custid INTO dbo.Orders FROM TSQLV3.Sales.Orders;

ALTER TABLE dbo.Orders ADD CONSTRAINT PK_Orders PRIMARY KEY(orderid);

-- Before delete
SELECT orderid, orderdate, empid, custid FROM dbo.Orders;
SELECT orderid, orderdate, empid, custid FROM Archive.dbo.Orders;

-- Delete with OUTPUT
DELETE FROM dbo.Orders
  OUTPUT
    deleted.orderid,
    deleted.orderdate,
    deleted.empid,
    deleted.custid
  INTO Archive.dbo.Orders
WHERE orderdate < '20140101';

-- Delete in chunks with OUTPUT
WHILE 1 = 1
BEGIN
  DELETE TOP (3000) FROM dbo.Orders
    OUTPUT
      deleted.orderid,
      deleted.orderdate,
      deleted.empid,
      deleted.custid
    INTO Archive.dbo.Orders
  WHERE orderdate < '20140101';

  IF @@ROWCOUNT < 3000 BREAK;
END;

-- After delete
SELECT orderid, orderdate, empid, custid FROM dbo.Orders;
SELECT orderid, orderdate, empid, custid FROM Archive.dbo.Orders;

-- Example with MERGE

-- Sample data
TRUNCATE TABLE dbo.Customers;
TRUNCATE TABLE dbo.CustomersStage;

INSERT INTO dbo.Customers(custid, companyname, phone, address)
  VALUES(1, 'cust 1', '(111) 111-1111', 'address 1'),
        (2, 'cust 2', '(222) 222-2222', 'address 2'),
        (3, 'cust 3', '(333) 333-3333', 'address 3'),
        (4, 'cust 4', '(444) 444-4444', 'address 4'),
        (5, 'cust 5', '(555) 555-5555', 'address 5');

INSERT INTO dbo.CustomersStage(custid, companyname, phone, address)
  VALUES(2, 'AAAAA', '(222) 222-2222', 'address 2'),
        (3, 'cust 3', '(333) 333-3333', 'address 3'),
        (5, 'BBBBB', 'CCCCC', 'DDDDD'),
        (6, 'cust 6 (new)', '(666) 666-6666', 'address 6'),
        (7, 'cust 7 (new)', '(777) 777-7777', 'address 7');

-- Example
MERGE INTO dbo.Customers AS TGT
USING dbo.CustomersStage AS SRC
  ON TGT.custid = SRC.custid
WHEN MATCHED THEN
  UPDATE SET
    TGT.companyname = SRC.companyname,
    TGT.phone = SRC.phone,
    TGT.address = SRC.address
WHEN NOT MATCHED THEN 
  INSERT (custid, companyname, phone, address)
  VALUES (SRC.custid, SRC.companyname, SRC.phone, SRC.address)
WHEN NOT MATCHED BY SOURCE THEN
  DELETE
OUTPUT 
  $action AS the_action, deleted.custid AS del_custid, inserted.custid AS ins_custid;

-- Cleanup
TRUNCATE TABLE dbo.T1;

-- With INSERT cannot refer to source elements
-- Following fails
INSERT INTO dbo.T1(datacol)
  OUTPUT SRC.empid AS sourcekey, inserted.keycol AS targetkey, inserted.datacol AS targetdatacol
    SELECT lastname
    FROM TSQLV3.HR.Employees AS SRC
    WHERE country = N'USA';

-- Using MERGE
MERGE INTO dbo.T1 AS TGT
USING (SELECT * FROM TSQLV3.HR.Employees WHERE country = N'USA') AS SRC
  ON 1 = 2
WHEN NOT MATCHED THEN
  INSERT (datacol) VALUES(SRC.lastname)
OUTPUT SRC.empid AS sourcekey, inserted.keycol AS targetkey, inserted.datacol AS targetdatacol;

-- Composable DML
INSERT INTO Archive.dbo.Orders (orderid, orderdate, empid, custid)
  SELECT orderid, orderdate, empid, custid
  FROM ( DELETE FROM dbo.Orders
           OUTPUT
             deleted.orderid,
             deleted.orderdate,
             deleted.empid,
             deleted.custid
         WHERE orderdate < '20140101' ) AS D
  WHERE custid IN (11, 42);
