from django.core.mail import EmailMultiAlternatives
from django.template.loader import render_to_string
from django.conf import settings
from api.models.users.TokenDetailsModel import TokenDetails
from api.models.users.UserAuthTokensModel import UserAuthTokens
from django.utils import timezone

def account_verification_mail(user, token):
    """Send account verification email."""
    verification_url = f"{settings.SITE_URL}/verify-email/{token}/"
    subject = "Please verify your account"
    # Get or create the verification TokenDetails (for example, type="verification")
    token_details, _ = TokenDetails.objects.get_or_create(
        type="verification",
        defaults={"description": "Email verification token",
                  "validity_duration": timezone.timedelta(days=1)}
    )

    # Create a UserAuthTokens entry for the user
    user_auth_token = UserAuthTokens.objects.create(
        auth_token=token,
        user=user,
        token_details=token_details,
        created_at=timezone.now(),
        expiry_time=timezone.now() + token_details.validity_duration
    )
    # Render the HTML email template with context
    html_content = render_to_string('api/emails/verification_email.html', {
        'user': user,
        'verification_link': verification_url
    })

    # Render a plain text version (optional but recommended for email clients that don't support HTML)
    text_content = f"Hello {user.username},\n\nPlease verify your email address by clicking the link below:\n\n{
        verification_url}\n\nThank you!"

    # Create the email
    email = EmailMultiAlternatives(
        subject,
        text_content,
        settings.DEFAULT_FROM_EMAIL,
        [user.email],
    )

    # Attach the HTML version
    email.attach_alternative(html_content, "text/html")

    # Send the email
    email.send(fail_silently=False)
