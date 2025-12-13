DECLARE 
    @LinkedServer sysname = N'CALEL',
    @DB          sysname = N'AdventureWorks2022',
    @Schema      sysname = N'Person',
    @Table       sysname = N'Person';

DECLARE @RemoteProc nvarchar(300) = QUOTENAME(@DB) + N'.sys.sp_spaceused';
DECLARE @Obj        nvarchar(300) = @Schema + N'.' + @Table;

DECLARE @SQL nvarchar(max) =
N'SELECT *
  FROM OPENQUERY(' + QUOTENAME(@LinkedServer) + N',
''SET NOCOUNT ON;
  EXEC ' + REPLACE(@RemoteProc, '''', '''''') + N' N'''''+ REPLACE(@Obj, '''', '''''') + N'''''
  WITH RESULT SETS
  (
    (
      [name] sysname,
      [rows] char(11),
      reserved varchar(18),
      data varchar(18),
      index_size varchar(18),
      unused varchar(18)
    )
  );'');';

EXEC sys.sp_executesql @SQL;



--sp sp_spaceused 
DECLARE @Table1 SYSNAME = 'Person.Person';
EXEC sp_spaceused @Table1;
