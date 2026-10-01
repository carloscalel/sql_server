using System;
using System.IO;
using System.Net.Mail;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace SqlHealthReporter
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("=== Iniciando Ejecución de Reportes SQL ===");

            // 1. Cargar la configuración desde appsettings.json
            var builder = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
            
            IConfiguration config = builder.Build();

            // Extraer variables de configuración
            string rutaScript = config["Configuracion:RutaScript"];
            var servidoresDestino = config.GetSection("Configuracion:ServidoresDestino").Get<string[]>();
            
            string smtpHost = config["Correo:SmtpHost"];
            int smtpPort = int.Parse(config["Correo:SmtpPort"]);
            string correoRemitente = config["Correo:Remitente"];
            var destinatarios = config.GetSection("Correo:Destinatarios").Get<string[]>();

            // 2. Validar que el archivo .sql exista
            if (!File.Exists(rutaScript))
            {
                Console.WriteLine($"[CRÍTICO] No se encontró el archivo de script en: {rutaScript}");
                return;
            }

            string sqlScript = File.ReadAllText(rutaScript);

            // 3. Iterar por cada servidor de la lista dinámica
            foreach (var servidor in servidoresDestino)
            {
                Console.WriteLine($"\n-> Conectando a {servidor}...");
                
                string connectionString = $"Server={servidor};Database=master;Trusted_Connection=True;TrustServerCertificate=True;";
                string htmlGenerado = string.Empty;

                try
                {
                    using (SqlConnection conexion = new SqlConnection(connectionString))
                    {
                        conexion.Open();
                        using (SqlCommand comando = new SqlCommand(sqlScript, conexion))
                        {
                            comando.CommandTimeout = 600; 
                            
                            using (SqlDataReader reader = comando.ExecuteReader())
                            {
                                if (reader.Read())
                                {
                                    // Lee la columna generada en el SELECT de tu script[span_0](start_span)[span_0](end_span)
                                    htmlGenerado = reader["Executive_HTML"].ToString(); 
                                }
                            }
                        }
                    }

                    if (!string.IsNullOrEmpty(htmlGenerado))
                    {
                        string asunto = $"Estado de Salud SQL Server - {servidor} - {DateTime.Now:dd/MM/yyyy}";
                        EnviarCorreo(smtpHost, smtpPort, correoRemitente, destinatarios, asunto, htmlGenerado);
                        Console.WriteLine($"[ÉXITO] Reporte generado y enviado correctamente para {servidor}.");
                    }
                    else
                    {
                        Console.WriteLine($"[ADVERTENCIA] El script se ejecutó en {servidor} pero no devolvió HTML.");
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[ERROR] Fallo procesando el servidor {servidor}: {ex.Message}");
                }
            }

            Console.WriteLine("\n=== Proceso finalizado ===");
        }

        static void EnviarCorreo(string host, int port, string de, string[] para, string asunto, string cuerpoHtml)
        {
            using (MailMessage mail = new MailMessage())
            {
                mail.From = new MailAddress(de);
                
                // Agrega todos los destinatarios del arreglo dinámicamente
                foreach (string destinatario in para)
                {
                    mail.To.Add(destinatario);
                }

                mail.Subject = asunto;
                mail.Body = cuerpoHtml;
                mail.IsBodyHtml = true;

                using (SmtpClient smtp = new SmtpClient(host, port))
                {
                    smtp.UseDefaultCredentials = true; 
                    smtp.Send(mail);
                }
            }
        }
    }
}





{
  "Configuracion": {
    "RutaScript": "C:\\Scripts\\EstadoSalud.sql",
    "ServidoresDestino": [
      "InstanciaSQL_01",
      "InstanciaSQL_02",
      "InstanciaSQL_03"
    ]
  },
  "Correo": {
    "SmtpHost": "192.168.1.50",
    "SmtpPort": 25,
    "Remitente": "alertas_sql@tuempresa.com",
    "Destinatarios": [
      "dba_principal@tuempresa.com",
      "soporte_bd@tuempresa.com",
      "gerencia_ti@tuempresa.com"
    ]
  }
}
