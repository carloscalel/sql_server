using System;
using System.IO;
using System.Net.Mail;
using Microsoft.Data.SqlClient;

namespace SqlHealthReporter
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("=== Iniciando Ejecución de Reportes SQL ===");

            // 1. Configuración de Rutas y Servidores
            string rutaScript = @"C:\Scripts\EstadoSalud.sql"; // Ruta local en el Servidor A
            
            // Aquí puedes agregar todos los servidores a los que el Servidor A se conectará
            string[] servidoresDestino = { "InstanciaSQL_01", "InstanciaSQL_02" };

            // Configuración del Servidor B (Correo)
            string smtpHost = "IP_O_NOMBRE_SERVIDOR_B"; 
            int smtpPort = 25; 
            string correoRemitente = "alertas_sql@tuempresa.com";
            string correoDestino = "dba@tuempresa.com";

            // 2. Validar que el archivo .sql exista
            if (!File.Exists(rutaScript))
            {
                Console.WriteLine($"[CRÍTICO] No se encontró el archivo de script en: {rutaScript}");
                return;
            }

            string sqlScript = File.ReadAllText(rutaScript);

            // 3. Iterar por cada servidor de la lista
            foreach (var servidor in servidoresDestino)
            {
                Console.WriteLine($"\n-> Conectando a {servidor}...");
                
                string connectionString = $"Server={servidor};Database=master;Trusted_Connection=True;TrustServerCertificate=True;";
                string htmlGenerado = string.Empty;

                try
                {
                    // Ejecutar el script y recuperar el HTML
                    using (SqlConnection conexion = new SqlConnection(connectionString))
                    {
                        conexion.Open();
                        using (SqlCommand comando = new SqlCommand(sqlScript, conexion))
                        {
                            comando.CommandTimeout = 600; // 10 minutos de timeout
                            
                            using (SqlDataReader reader = comando.ExecuteReader())
                            {
                                if (reader.Read())
                                {
                                    // Lee la columna generada en la línea 239 de tu script
                                    htmlGenerado = reader["Executive_HTML"].ToString(); 
                                }
                            }
                        }
                    }

                    // Enviar el correo usando el Servidor B
                    if (!string.IsNullOrEmpty(htmlGenerado))
                    {
                        string asunto = $"Estado de Salud SQL Server - {servidor} - {DateTime.Now:dd/MM/yyyy}";
                        EnviarCorreo(smtpHost, smtpPort, correoRemitente, correoDestino, asunto, htmlGenerado);
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

        static void EnviarCorreo(string host, int port, string de, string para, string asunto, string cuerpoHtml)
        {
            using (MailMessage mail = new MailMessage(de, para))
            {
                mail.Subject = asunto;
                mail.Body = cuerpoHtml;
                mail.IsBodyHtml = true;

                using (SmtpClient smtp = new SmtpClient(host, port))
                {
                    // Configuración básica para un servidor de correo interno (Relay)
                    smtp.UseDefaultCredentials = true; 
                    smtp.Send(mail);
                }
            }
        }
    }
}
