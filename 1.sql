@model IEnumerable<dynamic> 
@{
    ViewBag.Title = ViewBag.Title ?? "Listado";
}

<h2>@ViewBag.Title</h2>

<!-- Tabla genérica con Bootstrap 5 -->
<table id="dataTable" class="table table-striped table-bordered">
    <thead class="table-dark">
        <tr>
            <!-- Encabezados dinámicos -->
            @if (Model != null && Model.Any())
            {
                var props = Model.First().GetType().GetProperties();
                foreach (var prop in props)
                {
                    <th>@prop.Name</th>
                }
                <th>Acciones</th>
            }
            else
            {
                <th>Sin datos disponibles</th>
            }
        </tr>
    </thead>
    <tbody>
        @if (Model != null && Model.Any())
        {
            foreach (var item in Model)
            {
                <tr>
                    @foreach (var prop in item.GetType().GetProperties())
                    {
                        <td>@prop.GetValue(item, null)</td>
                    }
                    <td>
                        <!-- Botones de acción genéricos -->
                        @Html.ActionLink("Editar", "Edit", new { id = item.GetType().GetProperty("Id")?.GetValue(item) }, new { @class = "btn btn-sm btn-warning" }) 
                        @Html.ActionLink("Detalles", "Details", new { id = item.GetType().GetProperty("Id")?.GetValue(item) }, new { @class = "btn btn-sm btn-info" }) 
                        @Html.ActionLink("Eliminar", "Delete", new { id = item.GetType().GetProperty("Id")?.GetValue(item) }, new { @class = "btn btn-sm btn-danger" })
                    </td>
                </tr>
            }
        }
    </tbody>
</table>

@section Scripts {
    <!-- DataTables + Bootstrap 5 configuración -->
    <script>
        $(document).ready(function () {
            $('#dataTable').DataTable({
                "language": {
                    "url": "//cdn.datatables.net/plug-ins/1.13.5/i18n/es-ES.json"
                },
                "pageLength": 10,
                "lengthMenu": [5, 10, 25, 50],
                "ordering": true,
                "searching": true,
                "responsive": true
            });
        });
    </script>
}