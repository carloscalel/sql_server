
SELECT db_name(database_id) as base,
 MID.[statement] AS ObjectName
,MIGS.last_user_seek AS LastUserSeek
,MIGS.avg_user_impact
,(MIGS.user_seeks + MIGS.user_scans) as uso
,ROUND(MIGS.avg_total_user_cost 
 * MIGS.avg_user_impact 
       * (MIGS.user_seeks + MIGS.user_scans),0) AS Impact
      ,N'CREATE NONCLUSTERED INDEX TRIGGERDB_IDX1_ ' + MID.[statement] +
       N'ON ' + MID.[statement] + 
       N' (' + MID.equality_columns 
             + ISNULL(', ' + MID.inequality_columns, N'') +
       N') ' + ISNULL(N'INCLUDE (' + MID.included_columns + N');', ';')
       AS CreateStatement
FROM sys.dm_db_missing_index_group_stats AS MIGS
     INNER JOIN sys.dm_db_missing_index_groups AS MIG
         ON MIGS.group_handle = MIG.index_group_handle
     INNER JOIN sys.dm_db_missing_index_details AS MID
         ON MIG.index_handle = MID.index_handle
ORDER BY Impact DESC
