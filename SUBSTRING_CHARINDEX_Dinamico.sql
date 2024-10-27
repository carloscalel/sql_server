
DECLARE @TABLE AS TABLE (dato VARCHAR(MAX))
INSERT INTO @TABLE
VALUES ('T_0203'), ('T_0204'), ('T_0205')

with
ArchivosOK as (
select *
  from (values ('T_0203')
             , ('T_0204')
             , ('T_0205')
        ) q1 (archivo)
)
,
ArchivoConSeparador as (
select   archivo 
       --, charindex('_', archivo) Separador1
       --, charindex('_', archivo, charindex('_', archivo) + 1) Separador2
  from ArchivosOK
)
select  archivo
      --, substring(archivo, Separador1, Separador1) Folio
      --, substring(archivo, Separador1 + 1, Separador2) Fecha
		, REPLACE(RTRIM(SUBSTRING(archivo,1,CHARINDEX('_', archivo))),'_', '') Separador1
		, RTRIM(SUBSTRING(archivo,CHARINDEX('_', archivo)+1,len(archivo))) Separador2
  from ArchivoConSeparador;



DECLARE @CODIGO VARCHAR(MAX) = '1,4|1,6|1,3|'
DECLARE @TABLE AS TABLE (dato VARCHAR(MAX))

INSERT INTO @TABLE(DATO)
SELECT dbo.ReplaceASCII(items) 
FROM dbo.Split(REPLACE(@CODIGO,',','_'), '|')

--DECLARE @TABLE AS TABLE (dato VARCHAR(MAX))
--INSERT INTO @TABLE
--VALUES ('T_0203'), ('T_0204'), ('T_0205')

SELECT 
	 REPLACE(RTRIM(SUBSTRING(dato,1,CHARINDEX('_', dato))),'_', '') id_propuesta
	, RTRIM(SUBSTRING(dato,CHARINDEX('_', dato)+1,len(dato))) id_sede
FROM @TABLE
