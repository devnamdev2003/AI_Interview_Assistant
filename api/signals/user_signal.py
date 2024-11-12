from api.models import Users, TokenDetails, UserAuthTokens
from django.db.models.signals import post_save
from django.dispatch import receiver
import uuid
from django.utils import timezone
from django.contrib.auth.signals import user_logged_in, user_logged_out
from django.utils.timezone import now
from django.db.models.signals import pre_save, post_save


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


@receiver(post_save, sender=Users)
def send_verification_email(sender, instance, created, **kwargs):
    """Send a verification email when a new user is created."""
    if created and not instance.is_verified:
        # Generate a unique token
        token = uuid.uuid4().hex

        # Get or create the verification TokenDetails (for example, type="verification")
        token_details, _ = TokenDetails.objects.get_or_create(
            type="verification",
            defaults={"description": "Email verification token",
                      "validity_duration": timezone.timedelta(days=1)}
        )

        # Create a UserAuthTokens entry for the user
        user_auth_token = UserAuthTokens.objects.create(
            auth_token=token,
            user=instance,
            token_details=token_details,
            created_at=timezone.now(),
            expiry_time=timezone.now() + token_details.validity_duration
        )

        # Send the email with the token
        # account_verification_mail(instance, token)
