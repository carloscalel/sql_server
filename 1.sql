CREATE OR ALTER PROCEDURE dbo.usp_Queue_TakeNext
    @WorkerName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @runDate DATE;

    -- Tomar la fecha más antigua pendiente
    SELECT TOP (1) @runDate = RunDate
    FROM dbo.ExecutionQueue
    WHERE Status IN ('PENDING','ERROR')
    ORDER BY RunDate ASC;

    IF @runDate IS NULL
        RETURN;

    ;WITH nextItem AS
    (
        SELECT TOP (1)
               q.QueueId
        FROM dbo.ExecutionQueue q
        INNER JOIN dbo.ScriptsCatalog c ON c.ScriptId = q.ScriptId
        WHERE q.RunDate = @runDate
          AND q.Status IN ('PENDING','ERROR')
          AND q.Attempts < q.MaxAttempts
          AND c.IsActive = 1
        ORDER BY c.Priority ASC, q.QueueId ASC
    )
    UPDATE q
        SET q.Status   = 'RUNNING',
            q.LockedBy = @WorkerName,
            q.LockedAt = SYSDATETIME(),
            q.Attempts = q.Attempts + 1
    OUTPUT
        inserted.QueueId,
        inserted.ScriptId,
        c.ScriptName,
        c.TargetDatabase,
        c.CommandText,
        c.CommandTimeoutSec,
        inserted.RunDate
    FROM dbo.ExecutionQueue q
    INNER JOIN nextItem n ON n.QueueId = q.QueueId
    INNER JOIN dbo.ScriptsCatalog c ON c.ScriptId = q.ScriptId;
END