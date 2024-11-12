from django.db import models

class Role(models.Model):
    name = models.CharField(max_length=50, unique=True)  # Role name, e.g., "admin", "user"
    description = models.TextField(blank=True)  # Description of role and permissions
    is_active = models.BooleanField(default=True)  # Role's active status
    created_at = models.DateTimeField(auto_now_add=True)  # Timestamp when the role was created
    updated_at = models.DateTimeField(auto_now=True)  # Timestamp when the role was last updated

    class Meta:
        db_table = 'ac_roles'  # Defines the table name in the database
        verbose_name = 'Role'
        verbose_name_plural = 'Roles'

    def __str__(self):
        return self.name  # String representation for easy identification


