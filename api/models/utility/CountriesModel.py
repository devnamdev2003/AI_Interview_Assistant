from django.db import models

class Country(models.Model):
    country_name = models.CharField(max_length=100)  # Name of the country
    country_code = models.CharField(max_length=10, unique=True)  # Unique code for the country
    is_active = models.BooleanField(default=True)  # Country's active status
    created_at = models.DateTimeField(auto_now_add=True)  # Timestamp when the country was created
    updated_at = models.DateTimeField(auto_now=True)  # Timestamp when the country was last updated

    class Meta:
        db_table = 'ut_countries'  # Defines the table name in the database
        verbose_name = 'Country'
        verbose_name_plural = 'Countries'

    def __str__(self):
        return self.country_name  # String representation for easy identification
