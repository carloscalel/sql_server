@using BitacoraMvc.Helpers
@using BitacoraMvc.Models

<div class="d-flex">
    <!-- Sidebar -->
    <nav class="flex-column bg-dark text-white p-3" style="width: 220px; min-height: 100vh;">
        <h5 class="text-white">Mi App</h5>
        <hr class="text-white">
        <ul class="nav nav-pills flex-column">
            @foreach (var module in PermissionHelper.GetAccessibleModules())
            {
                <li class="nav-item mb-1">
                    <a class="nav-link text-white" href="@Url.Action("Index", module)">
                        @module
                    </a>
                </li>
            }
        </ul>
    </nav>

    <!-- Contenido principal -->
    <div class="flex-grow-1 p-3">
        @RenderBody()
    </div>
</div>

<!-- Bootstrap JS Bundle -->
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js"></script>