using System;
using System.Data.SqlClient;
using System.IO;

class ExportadorInteractivoSSRS
{
    static void Main()
    {
        Console.WriteLine("🔐 Ingreso de datos de conexión SQL Server Reporting Services:");

        Console.Write("Servidor SQL (ej. localhost): ");
        string servidor = Console.ReadLine()?.Trim() ?? "localhost";

        Console.Write("Base de datos (por defecto: ReportServer): ");
        string baseDatos = Console.ReadLine();
        if (string.IsNullOrWhiteSpace(baseDatos)) baseDatos = "ReportServer";

        Console.Write("Ruta de carpeta de salida (ej. C:\\ExportSSRS): ");
        string carpetaSalida = Console.ReadLine()?.Trim() ?? @"C:\ExportSSRS";
        Directory.CreateDirectory(carpetaSalida);

        Console.Write("¿Deseas filtrar por carpeta SSRS? (ej. /Ventas o presiona Enter para todo): ");
        string filtroCarpeta = Console.ReadLine()?.Trim();

        string connectionString = $"Server={servidor};Database={baseDatos};Integrated Security=true;";

        string query = @"
            SELECT [Name], [Path], [Content], [Type]
            FROM [dbo].[Catalog]
            WHERE [Type] IN (2, 5, 8)";

        if (!string.IsNullOrWhiteSpace(filtroCarpeta))
        {
            query += " AND [Path] LIKE @FiltroPath + '%'";
        }

        int contador = 0;

        using (SqlConnection conexion = new SqlConnection(connectionString))
        {
            conexion.Open();
            using (SqlCommand comando = new SqlCommand(query, conexion))
            {
                if (!string.IsNullOrWhiteSpace(filtroCarpeta))
                {
                    comando.Parameters.AddWithValue("@FiltroPath", filtroCarpeta);
                }

                using (SqlDataReader lector = comando.ExecuteReader())
                {
                    while (lector.Read())
                    {
                        string nombre = lector.GetString(0);
                        string path = lector.GetString(1);
                        byte[] contenido = (byte[])lector["Content"];
                        int tipo = (int)lector["Type"];

                        string extension = tipo switch
                        {
                            2 => ".rdl",
                            5 => ".rds",
                            8 => ".rsd",
                            _ => ".bin"
                        };

                        string rutaRelativa = path.TrimStart('/').Replace("/", "\\");
                        string carpetaCompleta = Path.Combine(carpetaSalida, rutaRelativa);
                        Directory.CreateDirectory(carpetaCompleta);

                        string nombreSeguro = string.Join("_", nombre.Split(Path.GetInvalidFileNameChars()));
                        string rutaFinal = Path.Combine(carpetaCompleta, nombreSeguro + extension);

                        File.WriteAllBytes(rutaFinal, contenido);
                        contador++;
                        Console.WriteLine($"✅ Guardado: {rutaFinal}");
                    }
                }
            }
        }

        Console.WriteLine($"\n🎉 Exportación completada. Total archivos: {contador}");
        Console.WriteLine("Presiona cualquier tecla para salir...");
        Console.ReadKey();
    }
}