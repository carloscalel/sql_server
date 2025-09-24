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