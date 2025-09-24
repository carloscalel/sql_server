public static class PermissionHelper
{
    public static List<string> GetAccessibleModules()
    {
        var username = HttpContext.Current.User.Identity.Name;

        using (var db = new BitacoraMvcDbEntities())
        {
            var user = db.Users.FirstOrDefault(u => u.UserName == username);
            if (user == null) return new List<string>();

            var userRoleIds = db.UserRoles
                                .Where(ur => ur.UserId == user.UserId)
                                .Select(ur => ur.RoleId)
                                .ToList();

            if (!userRoleIds.Any()) return new List<string>();

            // Traer módulos únicos a los que tenga algún permiso
            var modules = (from rp in db.RolePermissions
                           join p in db.Permissions on rp.PermissionId equals p.PermissionId
                           join m in db.Modules on p.ModuleId equals m.ModuleId
                           where userRoleIds.Contains(rp.RoleId)
                           select m.Name)
                           .Distinct()
                           .ToList();

            return modules;
        }
    }
}





<ul class="nav navbar-nav">
    @foreach (var module in BitacoraMvc.Helpers.PermissionHelper.GetAccessibleModules())
    {
        if (module == "Productos")
        {
            <li>@Html.ActionLink("Productos", "Index", "Productos")</li>
        }
        else if (module == "Ventas")
        {
            <li>@Html.ActionLink("Ventas", "Index", "Ventas")</li>
        }
        else if (module == "Solicitudes")
        {
            <li>@Html.ActionLink("Solicitudes", "Index", "SolicitudPermisos")</li>
        }
    }
</ul>





-- 1. Crear un nuevo módulo
INSERT INTO Modules (Name, Description)
VALUES ('Reportes', 'Módulo de generación de reportes');

DECLARE @NewModuleId INT = SCOPE_IDENTITY();

-- 2. Crear un permiso para el módulo (ejemplo: acceso completo)
INSERT INTO Permissions (ModuleId, Action)
VALUES (@NewModuleId, 'View');

DECLARE @NewPermissionId INT = SCOPE_IDENTITY();

-- 3. Identificar el usuario al que queremos darle acceso
DECLARE @UserName NVARCHAR(50) = 'carlos';  -- Cambia por el usuario real
DECLARE @UserId INT;

SELECT @UserId = UserId
FROM Users
WHERE UserName = @UserName;

-- 4. Ver el rol principal del usuario
DECLARE @RoleId INT;

SELECT TOP 1 @RoleId = RoleId
FROM UserRoles
WHERE UserId = @UserId;

-- Si no tiene rol, podrías asignarle uno
IF @RoleId IS NULL
BEGIN
    -- Crear rol básico si no existe
    INSERT INTO Roles (Name) VALUES ('DefaultRole');
    SET @RoleId = SCOPE_IDENTITY();

    INSERT INTO UserRoles (UserId, RoleId)
    VALUES (@UserId, @RoleId);
END

-- 5. Darle el permiso al rol del usuario
IF NOT EXISTS (
    SELECT 1 FROM RolePermissions 
    WHERE RoleId = @RoleId AND PermissionId = @NewPermissionId
)
BEGIN
    INSERT INTO RolePermissions (RoleId, PermissionId)
    VALUES (@RoleId, @NewPermissionId);
END