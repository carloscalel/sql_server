else if (opcion == "7")
{
    Console.WriteLine("¿Cómo deseas ingresar los proyectos?");
    Console.WriteLine("1. Manual (Carpeta|Proyecto)");
    Console.WriteLine("2. Desde archivo TXT");
    Console.Write("Opción (1/2): ");

    string tipoIngreso = Console.ReadLine()?.Trim();

    var listaProyectos = new List<(string folder, string project)>();

    if (tipoIngreso == "1")
    {
        Console.WriteLine("Ingresa proyectos en formato Carpeta|Proyecto");
        Console.WriteLine("Línea vacía para terminar:");

        while (true)
        {
            string linea = Console.ReadLine();

            if (string.IsNullOrWhiteSpace(linea))
                break;

            var partes = linea.Split('|');

            if (partes.Length == 2)
                listaProyectos.Add((partes[0].Trim(), partes[1].Trim()));
            else
                Console.WriteLine("Formato inválido. Usa Carpeta|Proyecto");
        }
    }
    else if (tipoIngreso == "2")
    {
        Console.Write("Ruta completa del TXT: ");
        string ruta = Console.ReadLine()?.Trim();

        if (!File.Exists(ruta))
        {
            Console.WriteLine("Archivo no existe.");
            return;
        }

        var lineas = File.ReadAllLines(ruta)
            .Where(l => !string.IsNullOrWhiteSpace(l) && !l.Trim().StartsWith("#"));

        foreach (var linea in lineas)
        {
            var partes = linea.Split('|');
            if (partes.Length == 2)
                listaProyectos.Add((partes[0].Trim(), partes[1].Trim()));
        }
    }
    else
    {
        Console.WriteLine("Opción inválida.");
        return;
    }

    if (listaProyectos.Count == 0)
    {
        Console.WriteLine("No hay proyectos para procesar.");
        return;
    }

    string reportePath = Path.Combine(baseOutputDir, "Reporte_Conexiones_SSIS.csv");
    var reporte = new List<string>();
    reporte.Add("Folder,Project,Package,ConnectionName,ConnectionType,Provider");

    foreach (var item in listaProyectos)
    {
        try
        {
            var folder = catalog.Folders[item.folder];
            if (folder == null)
            {
                Console.WriteLine($"Carpeta no encontrada: {item.folder}");
                continue;
            }

            var project = folder.Projects[item.project];
            if (project == null)
            {
                Console.WriteLine($"Proyecto no encontrado: {item.project}");
                continue;
            }

            Console.WriteLine($"Procesando {item.folder} - {item.project}");

            AnalizarProyecto(project, baseOutputDir, item.folder, reporte);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error procesando {item.project}: {ex.Message}");
        }
    }

    File.WriteAllLines(reportePath, reporte, Encoding.UTF8);

    Console.WriteLine($"Reporte generado en: {reportePath}");
}