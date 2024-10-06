
ALTER PROCEDURE [dbo].[nombre_specific]
(
	--variable
)
AS
BEGIN
	SET NOCOUNT ON;
		
		DECLARE @msg VARCHAR(255), @err_num BIGINT, @err_sp VARCHAR(50), @Query VARCHAR(MAX)
		
		BEGIN TRY

			--instructions

		END TRY  
		BEGIN CATCH
            --instructions
			SELECT @msg  = ERROR_MESSAGE(), @err_num = ERROR_NUMBER(), @err_sp  = ERROR_PROCEDURE()
		END CATCH

	SET NOCOUNT OFF
END