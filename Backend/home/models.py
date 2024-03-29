from django.contrib.auth.models import AbstractUser
from django.db import models


class CustomUser(AbstractUser):
    USER_TYPE_CHOICES = (
        ('company', 'Company User'),
        ('normal', 'Normal User'),
    )
    phone_number = models.CharField(max_length=15, unique=True)
    date_of_birth = models.DateField(null=True, blank=True)
    is_registered = models.BooleanField(default=False)
    otp = models.CharField(max_length=6, blank=True, null=True)
    interview_limit = models.IntegerField(blank=True, null=True)
    bio = models.TextField(max_length=500, blank=True)
    city = models.CharField(max_length=100, blank=True)
    country = models.CharField(max_length=100, blank=True)
    user_type = models.CharField(
        max_length=100, choices=USER_TYPE_CHOICES, default='normal')
