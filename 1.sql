using Microsoft.Data.SqlClient;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using System.Text.Json;
using ClosedXML.Excel;
using System.Data;

class Program
{
    static void Main()
    {
        Console.WriteLine("Ingreso de datos de conexión SQL Server Reporting Services:");

        Console.Write("Servidor SQL (ej. localhost): ");
        string servidor = Console.ReadLine()?.Trim() ?? "localhost";

        Console.Write("Base de datos (por defecto: ReportServer): ");
        string? baseDatos = Console.ReadLine();
        if (string.IsNullOrWhiteSpace(baseDatos)) baseDatos = "ReportServer";

        Console.Write("Ruta de carpeta de salida (ej. C:\\ExportSSRS): ");
        string carpetaSalida = Console.ReadLine()?.Trim() ?? @"C:\ExportSSRS";

        if (!Directory.Exists(carpetaSalida))
            Directory.CreateDirectory(carpetaSalida);

        string rutaExcel = Path.Combine(carpetaSalida, "Auditoria_RDL_SQLServer2022.xlsx");

        var motorReglas = new MotorReglas("reglas.json");

        var listaHallazgos = new List<HallazgoExcel>();

        string connectionString =
            $"Server={servidor};Database={baseDatos};Integrated Security=true;Encrypt=True;TrustServerCertificate=True;";

        string query = @"
            SELECT [Name], [Path], [Content]
            FROM [dbo].[Catalog]
            WHERE [Type] = 2";

        using SqlConnection conn = new SqlConnection(connectionString);
        conn.Open();

        using SqlCommand cmd = new SqlCommand(query, conn);
        using SqlDataReader reader = cmd.ExecuteReader();

        var reportes = new List<(string Nombre, string Path, byte[] Content)>();

        while (reader.Read())
        {
            reportes.Add((
                reader["Name"].ToString() ?? "",
                reader["Path"].ToString() ?? "",
                (byte[])reader["Content"]
            ));
        }

        reader.Close();

        using SqlConnection connMaster = new SqlConnection(connectionString);
        connMaster.Open();

        foreach (var r in reportes)
        {
            try
            {
                string xmlString = Encoding.UTF8.GetString(r.Content);

                if (!xmlString.TrimStart().StartsWith("<"))
                    continue;

                XDocument doc = XDocument.Parse(xmlString);

                bool usaImagenEmbedded = doc
                    .Descendants()
                    .Any(x => x.Name.LocalName == "EmbeddedImage");

                var dataSets = doc.Descendants()
                    .Where(x => x.Name.LocalName == "DataSet");

                foreach (var ds in dataSets)
                {
                    string dsName = ds.Attribute("Name")?.Value ?? "SinNombre";

                    var commandTexts = ds.Descendants()
                        .Where(x => x.Name.LocalName == "CommandText")
                        .ToList();

                    foreach (var commandTextNode in commandTexts)
                    {
                        string querySql = commandTextNode.Value;

                        string sqlSeguro = LimpiarSqlParaAnalisis(querySql);

                        int score = 0;
                        List<string> hallazgos = new List<string>();

                        foreach (var regla in motorReglas.Reglas.Values)
                        {
                            if (string.IsNullOrWhiteSpace(regla.Patron))
                                continue;

                            bool matchSql = Regex.IsMatch(querySql ?? "", regla.Patron, RegexOptions.IgnoreCase);
                            bool matchXml = Regex.IsMatch(xmlString ?? "", regla.Patron, RegexOptions.IgnoreCase);

                            if (matchSql || matchXml)
                            {
                                score += regla.Puntaje;
                                hallazgos.Add(regla.Codigo ?? "REGLA");
                            }
                        }

                        try
                        {
                            if (Regex.IsMatch(sqlSeguro, @"\bSELECT\b", RegexOptions.IgnoreCase))
                            {
                                using SqlCommand cmdMeta = new SqlCommand("sp_describe_first_result_set", connMaster);
                                cmdMeta.CommandType = CommandType.StoredProcedure;

                                cmdMeta.Parameters.Add("@tsql", SqlDbType.NVarChar).Value = sqlSeguro;

                                using SqlDataReader metaReader = cmdMeta.ExecuteReader();

                                while (metaReader.Read())
                                {
                                    string tipo = metaReader["system_type_name"]?.ToString() ?? "";

                                    foreach (var regla in motorReglas.Reglas.Values)
                                    {
                                        if (string.IsNullOrWhiteSpace(regla.Patron))
                                            continue;

                                        if (Regex.IsMatch(tipo, regla.Patron, RegexOptions.IgnoreCase))
                                        {
                                            score += regla.Puntaje;
                                            hallazgos.Add(regla.Codigo ?? "TIPO");
                                        }
                                    }
                                }
                            }
                        }
                        catch
                        {
                            hallazgos.Add("ERROR_ANALISIS_DINAMICO");
                        }

                        string severidad = "Bajo";

                        if (score >= 60) severidad = "Alto";
                        else if (score >= 30) severidad = "Medio";

                        listaHallazgos.Add(new HallazgoExcel
                        {
                            Reporte = r.Nombre,
                            Path = r.Path,
                            DataSet = dsName,
                            Score = score,
                            Severidad = severidad,
                            Detalle = string.Join(",", hallazgos)
                        });
                    }
                }

                if (usaImagenEmbedded)
                {
                    listaHallazgos.Add(new HallazgoExcel
                    {
                        Reporte = r.Nombre,
                        Path = r.Path,
                        DataSet = "GLOBAL",
                        Score = 5,
                        Severidad = "Bajo",
                        Detalle = "USA_IMAGEN_EMBEDDED"
                    });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error procesando {r.Nombre}: {ex.Message}");
            }
        }

        using var workbook = new XLWorkbook();

        var ws1 = workbook.Worksheets.Add("Hallazgos");

        ws1.Cell(1, 1).Value = "Reporte";
        ws1.Cell(1, 2).Value = "Path";
        ws1.Cell(1, 3).Value = "DataSet";
        ws1.Cell(1, 4).Value = "Score";
        ws1.Cell(1, 5).Value = "Severidad";
        ws1.Cell(1, 6).Value = "Detalle";

        int row = 2;

        foreach (var h in listaHallazgos)
        {
            ws1.Cell(row, 1).Value = h.Reporte;
            ws1.Cell(row, 2).Value = h.Path;
            ws1.Cell(row, 3).Value = h.DataSet;
            ws1.Cell(row, 4).Value = h.Score;
            ws1.Cell(row, 5).Value = h.Severidad;
            ws1.Cell(row, 6).Value = h.Detalle;
            row++;
        }

        var ws2 = workbook.Worksheets.Add("Matriz_Criterios");

        ws2.Cell(1, 1).Value = "Codigo";
        ws2.Cell(1, 2).Value = "Descripcion";
        ws2.Cell(1, 3).Value = "Puntaje";
        ws2.Cell(1, 4).Value = "Severidad";
        ws2.Cell(1, 5).Value = "Patron";

        row = 2;

        foreach (var regla in motorReglas.Reglas.Values)
        {
            ws2.Cell(row, 1).Value = regla.Codigo;
            ws2.Cell(row, 2).Value = regla.Descripcion;
            ws2.Cell(row, 3).Value = regla.Puntaje;
            ws2.Cell(row, 4).Value = regla.Severidad;
            ws2.Cell(row, 5).Value = regla.Patron;
            row++;
        }

        workbook.SaveAs(rutaExcel);

        Console.WriteLine("Proceso finalizado.");
    }

    static string LimpiarSqlParaAnalisis(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
            return "";

        string limpio = sql;

        limpio = limpio.Replace("\0", "");

        limpio = Regex.Replace(limpio, @"\bUSE\s+\[?\w+\]?\s*;?", "", RegexOptions.IgnoreCase);

        limpio = Regex.Replace(limpio, @"\bGO\b", "", RegexOptions.IgnoreCase);

        limpio = Regex.Replace(limpio, @"DECLARE\s+@\w+[^;]*;", "", RegexOptions.IgnoreCase);

        limpio = Regex.Replace(limpio, @"SET\s+@\w+[^;]*;", "", RegexOptions.IgnoreCase);

        limpio = Regex.Replace(limpio, @"/\*.*?\*/", "", RegexOptions.Singleline);

        limpio = Regex.Replace(limpio, @"--.*?$", "", RegexOptions.Multiline);

        limpio = Regex.Replace(
            limpio,
            @"SELECT\s+(.*?)\s+INTO\s+#\w+",
            "SELECT $1",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);

        limpio = Regex.Replace(limpio, @"EXEC\s*\(@.*?\)", "", RegexOptions.IgnoreCase);

        return limpio.Trim();
    }
}

class HallazgoExcel
{
    public string Reporte { get; set; } = "";
    public string Path { get; set; } = "";
    public string DataSet { get; set; } = "";
    public int Score { get; set; }
    public string Severidad { get; set; } = "";
    public string Detalle { get; set; } = "";
}

class MotorReglas
{
    public Dictionary<string, Regla> Reglas { get; set; } = new();

    public MotorReglas(string rutaJson)
    {
        if (!File.Exists(rutaJson))
            return;

        var json = File.ReadAllText(rutaJson);

        var lista = JsonSerializer.Deserialize<List<Regla>>(json);

        if (lista == null) return;

        foreach (var r in lista)
            Reglas[r.Codigo] = r;
    }
}

class Regla
{
    public string Codigo { get; set; } = "";
    public string Descripcion { get; set; } = "";
    public int Puntaje { get; set; }
    public string Severidad { get; set; } = "";
    public string Patron { get; set; } = "";
}