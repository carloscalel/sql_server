<ul class="nav navbar-nav">
    <li class="nav-item dropdown">
        <a class="nav-link dropdown-toggle" href="#" id="dropdownModules" role="button" data-bs-toggle="dropdown" aria-expanded="false">
            Módulos
        </a>
        <ul class="dropdown-menu" aria-labelledby="dropdownModules">
            @foreach (var module in BitacoraMvc.Helpers.PermissionHelper.GetAccessibleModules())
            {
                @* Ajusta los enlaces según tu módulo *@
                <li>
                    @if (module == "Productos")
                    {
                        <a class="dropdown-item" href="@Url.Action("Index", "Productos")">Productos</a>
                    }
                    else if (module == "Ventas")
                    {
                        <a class="dropdown-item" href="@Url.Action("Index", "Ventas")">Ventas</a>
                    }
                    else if (module == "Solicitudes")
                    {
                        <a class="dropdown-item" href="@Url.Action("Index", "SolicitudPermisos")">Solicitudes</a>
                    }
                    else
                    {
                        @* Por si agregas módulos nuevos *@
                        <a class="dropdown-item" href="@Url.Action("Index", module)">@module</a>
                    }
                </li>
            }
        </ul>
    </li>
</ul>