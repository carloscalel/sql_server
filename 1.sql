@section Scripts {
    <script>
        $(function () {
            $('#dataTable').DataTable({
                "deferRender": true,   // Renderiza solo lo que se necesita
                "processing": true,    // Muestra indicador de carga
                "pageLength": 10,
                "lengthMenu": [5, 10, 25, 50],
                "language": {
                    "url": "//cdn.datatables.net/plug-ins/1.13.5/i18n/es-ES.json"
                }
            });
        });
    </script>
}