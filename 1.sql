else if (opcion == "5")
{
    Console.WriteLine("Ingresa los proyectos en formato Carpeta|Proyecto");
    Console.WriteLine("Uno por línea. Línea vacía para terminar:");

    var listaProyectos = new List<(string folder, string project)>();

    while (true)
    {
        string linea = Console.ReadLine();

        if (string.IsNullOrWhiteSpace(linea))
            break;

        var partes = linea.Split('|');

        if (partes.Length == 2)
        {
            listaProyectos.Add((partes[0].Trim(), partes[1].Trim()));
        }
        else
        {
            Console.WriteLine("Formato incorrecto. Usa Carpeta|Proyecto");
        }
    }

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

            ExportarProyecto(project, baseOutputDir, item.folder);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error exportando {item.project}: {ex.Message}");
        }
    }
}