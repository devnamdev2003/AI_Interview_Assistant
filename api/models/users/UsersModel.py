from django.utils.timezone import now
from django.utils import timezone
import uuid
from django.db.models.signals import post_save
from django.contrib.auth.signals import user_logged_in, user_logged_out
from django.db import models
from django.utils.timezone import now, get_current_timezone
from django.db.models.signals import pre_save, post_save
from django.dispatch import receiver
from django.contrib.auth.models import AbstractUser
from .RolesModel import Role
from ..utility.CountriesModel import Country
from django.core.validators import EmailValidator
# from api.services.mail.sv_account_verification_mail import account_verification_mail

class Users(AbstractUser):
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('inactive', 'Inactive'),
        ('online', 'Online'),
    ]
    GENDER_CHOICES = [
        ('male', 'Male'),
        ('female', 'Female'),
        ('other', 'Other')
    ]
    email = models.EmailField(
        max_length=255, unique=True, validators=[EmailValidator()])
    status = models.CharField(
        max_length=8, choices=STATUS_CHOICES, default='inactive')
    date_of_birth = models.DateField(null=True, blank=True)
    phone_number = models.CharField(max_length=15, blank=True)
    gender = models.CharField(
        max_length=10, choices=GENDER_CHOICES, blank=True)
    address = models.TextField(blank=True)
    is_verified = models.BooleanField(default=False)
    profile_picture_url = models.URLField(max_length=255, blank=True)
    time_zone = models.CharField(max_length=50, blank=True)
    password_last_changed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    login_attempt_count = models.PositiveIntegerField(default=0)
    role = models.ForeignKey(Role, on_delete=models.SET_NULL, null=True)
    country = models.ForeignKey(Country, on_delete=models.SET_NULL, null=True)

    class Meta:
        db_table = 'ac_users'  # Defines the table name in the database
        verbose_name = 'User'
        verbose_name_plural = 'Users'

    def __str__(self):
        return self.username  # String representation for easy identification

    def save(self, *args, **kwargs):
        # Automatically set time_zone if not set
        if not self.time_zone:
            try:
                self.time_zone = get_current_timezone().key
            except Exception as e:
                print(f"Error setting time_zone: {e}")
                # Optionally, set a fallback value
                self.time_zone = 'UTC'  # or any default timezone you prefer

        # Automatically set password_last_changed_at if not set
        if not self.password_last_changed_at and self.password:
            self.password_last_changed_at = now()

        # Save the user after setting the fields
        super().save(*args, **kwargs)


@receiver(user_logged_in)
def update_login_attempt_count(sender, request, user, **kwargs):
    # Increment login attempt count each time a user logs in
    user.login_attempt_count += 1
    user.status = 'active'
    user.save()

# Signal to update password_last_changed_at whenever password is changed


@receiver(pre_save, sender=Users)
def update_password_last_changed_at(sender, instance, **kwargs):
    if instance.pk:  # Only if the user exists (not during creation)
        original_user = Users.objects.get(pk=instance.pk)
        if original_user.password != instance.password:
            instance.password_last_changed_at = now()


@receiver(user_logged_out)
def update_logout_status(sender, request, user, **kwargs):
    # Update the status to 'inactive' when the user logs out
    user.status = 'inactive'
    user.save()


# @receiver(post_save, sender=Users)
# def send_verification_email(sender, instance, created, **kwargs):
#     """Send a verification email when a new user is created."""
#     if created and not instance.is_verified:
#         # Generate a unique token
#         token = uuid.uuid4().hex
#         account_verification_mail(instance, token)
