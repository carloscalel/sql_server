
	IF OBJECT_ID('tempdb..#batch') IS NOT NULL DROP TABLE #batch

	CREATE TABLE #bcc_jobs (sede VARCHAR(MAX), no_job INT, IdOT INT, fh_ingreso DATE, process_name VARCHAR(MAX), codigo VARCHAR(MAX))
	CREATE TABLE #batch (co_no INT, invbatch_no INT, inv_date DATE, cantidad INT, patrulla INT, sede VARCHAR(MAX))
	CREATE TABLE #tbl_pocess (cantidad INT, last_execution DATE, sede VARCHAR(MAX), process_name VARCHAR(MAX), codigo VARCHAR(MAX))

	DECLARE @iQuery VARCHAR(MAX), @BaseDatosSede AS VARCHAR(255), @server VARCHAR(20), @db VARCHAR(30), @sede VARCHAR(50), @idsede INT, @codigo VARCHAR(MAX)  
	DECLARE @err_num BIGINT, @err_sp VARCHAR(50), @fI DATETIME

	DECLARE @MSG VARCHAR(MAX) = 'BATCH PENDIENTES' + CHAR(10) + 
			'SEDE' + SPACE(5) + 'PAT' + SPACE(5) + 'RECU'  + CHAR(10)

	DECLARE cursorSedes CURSOR FOR

    --instruccion que controla el cursor
	SELECT servidor, [db_name], pais, sede, codigo FROM sedes WITH(NOLOCK) WHERE pais IN (1)

	OPEN cursorSedes

	SET @iQuery = ''

	FETCH NEXT FROM cursorSedes INTO @server, @db, @idsede, @sede, @codigo
	WHILE @@FETCH_STATUS = 0
	BEGIN

		--instrucciones a ejecutar

		FETCH NEXT FROM cursorSedes INTO @server, @db, @idsede, @sede, @codigo
	END

	CLOSE cursorSedes
	DEALLOCATE cursorSedes

	IF OBJECT_ID('tempdb..#batch') IS NOT NULL DROP TABLE #batch


