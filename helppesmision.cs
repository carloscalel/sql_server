@using BitacoraMvc.Helpers

<nav class="navbar navbar-expand-lg navbar-dark bg-dark">
    <div class="container-fluid">
        <a class="navbar-brand" href="@Url.Action("Index","Home")">Mi App</a>
        <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" 
                aria-controls="navbarNav" aria-expanded="false" aria-label="Toggle navigation">
            <span class="navbar-toggler-icon"></span>
        </button>

        <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav me-auto">
                <!-- Dropdown único para todos los módulos -->
                <li class="nav-item dropdown">
                    <a class="nav-link dropdown-toggle" href="#" id="dropdownModules" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                        Módulos
                    </a>
                    <ul class="dropdown-menu" aria-labelledby="dropdownModules">
                        @foreach (var module in PermissionHelper.GetAccessibleModules())
                        {
                            <li>
                                <a class="dropdown-item" href="@Url.Action("Index", module)">
                                    @module
                                </a>
                            </li>
                        }
                    </ul>
                </li>

                <!-- Otros enlaces fijos si los hay -->
                <li class="nav-item">
                    <a class="nav-link" href="@Url.Action("About","Home")">About</a>
                </li>
            </ul>

            <ul class="navbar-nav ms-auto">
                <li class="nav-item">
                    <span class="navbar-text">@User.Identity.Name</span>
                </li>
            </ul>
        </div>
    </div>
</nav>

<!-- Bootstrap JS bundle -->
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js"></script>