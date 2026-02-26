Console.WriteLine("7. Exportar + Analizar + Generar Reporte CSV");


Bloque opción 7
else if (opcion == "7")
{
    string reportePath = Path.Combine(baseOutputDir, "Reporte_Conexiones_SSIS.csv");

    var reporte = new List<string>();
    reporte.Add("Folder,Project,Package,ConnectionName,ConnectionType,Provider");

    foreach (CatalogFolder folder in catalog.Folders)
    {
        foreach (ProjectInfo project in folder.Projects)
        {
            Console.WriteLine($"Procesando {folder.Name} - {project.Name}");

            AnalizarProyecto(project, baseOutputDir, folder.Name, reporte);
        }
    }

    File.WriteAllLines(reportePath, reporte, Encoding.UTF8);

    Console.WriteLine($"Reporte generado en: {reportePath}");
}



Método AnalizarProyecto
static void AnalizarProyecto(ProjectInfo project, string baseOutputDir, string folderName, List<string> reporte)
{
    string tempPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
    Directory.CreateDirectory(tempPath);

    try
    {
        string tempIspac = Path.Combine(tempPath, $"{project.Name}.ispac");
        File.WriteAllBytes(tempIspac, project.GetProjectBytes());

        string extractPath = Path.Combine(tempPath, "Extract");
        ZipFile.ExtractToDirectory(tempIspac, extractPath);

        var paquetes = Directory.GetFiles(extractPath, "*.dtsx", SearchOption.AllDirectories);

        foreach (var paquete in paquetes)
        {
            AnalizarDtsx(paquete, folderName, project.Name, reporte);
        }
    }
    finally
    {
        if (Directory.Exists(tempPath))
            Directory.Delete(tempPath, true);
    }
}



Método AnalizarDtsx
static void AnalizarDtsx(string rutaDtsx, string folder, string project, List<string> reporte)
{
    XDocument doc = XDocument.Load(rutaDtsx);
    XNamespace dts = "www.microsoft.com/SqlServer/Dts";

    var conexiones = doc.Descendants(dts + "ConnectionManager");

    foreach (var conn in conexiones)
    {
        string nombre = conn.Attribute(dts + "ObjectName")?.Value ?? "";
        string tipoRaw = conn.Attribute(dts + "CreationName")?.Value ?? "";
        string connectionString = conn.Attribute(dts + "ConnectionString")?.Value ?? "";

        string tipo = DetectarTipo(tipoRaw, connectionString);
        string provider = ExtraerProvider(connectionString);

        string linea = $"{folder},{project},{Path.GetFileName(rutaDtsx)},{nombre},{tipo},{provider}";
        reporte.Add(linea);
    }
}


Detectar Tipo de Conexión
static string DetectarTipo(string creationName, string connectionString)
{
    creationName = creationName.ToUpper();

    if (creationName.Contains("OLEDB"))
        return "OLE DB";

    if (creationName.Contains("ODBC"))
        return "ODBC";

    if (creationName.Contains("ADO.NET"))
        return "ADO.NET";

    if (creationName.Contains("FLATFILE"))
        return "Flat File";

    if (creationName.Contains("EXCEL"))
        return "Excel";

    if (connectionString.ToUpper().Contains("PROVIDER="))
        return "OLE DB";

    return "Otro";
}



Extraer Provider
static string ExtraerProvider(string connectionString)
{
    if (string.IsNullOrEmpty(connectionString))
        return "";

    var partes = connectionString.Split(';');

    foreach (var parte in partes)
    {
        if (parte.Trim().ToUpper().StartsWith("PROVIDER="))
        {
            return parte.Split('=')[1];
        }
    }

    return "";
}



