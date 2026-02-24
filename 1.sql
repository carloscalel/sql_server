else if (opcion == "6")
{
    Console.Write("Ingresa la ruta completa del archivo TXT: ");
    string rutaArchivo = Console.ReadLine()?.Trim();

    if (string.IsNullOrEmpty(rutaArchivo) || !File.Exists(rutaArchivo))
    {
        Console.WriteLine("Archivo no válido o no existe.");
        return;
    }

    Console.Write("¿Deseas exportar solo .dtsx? (s/n): ");
    bool soloDtsx = Console.ReadLine()?.Trim().ToLower() == "s";

    var lineas = File.ReadAllLines(rutaArchivo)
                      .Where(l => !string.IsNullOrWhiteSpace(l))
                      .ToList();

    foreach (var linea in lineas)
    {
        try
        {
            var partes = linea.Split('|');

            if (partes.Length != 2)
            {
                Console.WriteLine($"Formato inválido: {linea}");
                continue;
            }

            string folderName = partes[0].Trim();
            string projectName = partes[1].Trim();

            var folder = catalog.Folders[folderName];

            if (folder == null)
            {
                Console.WriteLine($"Carpeta no encontrada: {folderName}");
                continue;
            }

            var project = folder.Projects[projectName];

            if (project == null)
            {
                Console.WriteLine($"Proyecto no encontrado: {projectName}");
                continue;
            }

            if (soloDtsx)
                ExportarSoloDtsx(project, baseOutputDir, folderName);
            else
                ExportarProyecto(project, baseOutputDir, folderName);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error procesando línea '{linea}': {ex.Message}");
        }
    }
}