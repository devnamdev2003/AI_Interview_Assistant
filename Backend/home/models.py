from django.contrib.auth.models import AbstractUser
from django.db import models

class CustomUser(AbstractUser):
    phone_number = models.CharField(max_length=15, unique=True)
    date_of_birth = models.DateField(null=True, blank=True)
    is_registered = models.BooleanField(default=False)
    otp = models.CharField(max_length=6, blank=True, null=True) 


