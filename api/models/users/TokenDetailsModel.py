from django.db import models


class TokenDetails(models.Model):
    id = models.AutoField(primary_key=True)
    type = models.CharField(max_length=200, blank=True)
    description = models.CharField(max_length=255)
    validity_duration = models.DurationField()
    # Timestamp when the token was created
    created_at = models.DateTimeField(auto_now_add=True)
    # Timestamp when the token was last updated
    updated_at = models.DateTimeField(auto_now=True)
    # Whether the token is still active
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f'{self.type} - {self.description}'

    class Meta:
        db_table = 'ac_token_details'  # Defines the table name in the database
        verbose_name = 'Token Detail'
        verbose_name_plural = 'Token Details'
