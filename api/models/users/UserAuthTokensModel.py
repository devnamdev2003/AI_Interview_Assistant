from django.db import models
from django.utils import timezone
from datetime import timedelta
from .UsersModel import Users
from .TokenDetailsModel import TokenDetails
class UserAuthTokens(models.Model):
    id = models.AutoField(primary_key=True)
    auth_token = models.CharField(max_length=500)  # Store the token securely (hash or encryption)
    created_at = models.DateTimeField(auto_now_add=True)  # Date and time the token was created
    is_expired = models.BooleanField(default=False)  # Whether the token is expired
    last_accessed_at = models.DateTimeField(null=True, blank=True)  # Track when the token was last used
    revoked_date = models.DateTimeField(null=True, blank=True)  # Date when the token was revoked (optional)
    revoked_reason = models.CharField(max_length=255, null=True, blank=True)  # Reason for token revocation (optional)
    
    # Foreign Key to TokenDetails, will not delete token details if a token is deleted
    token_details = models.ForeignKey(TokenDetails, on_delete=models.SET_NULL, null=True, blank=True, related_name='user_tokens') 
    
    # Foreign Key to User model, token will be deleted if the user is deleted
    user = models.ForeignKey(Users, on_delete=models.CASCADE)  

    # Automatically calculate expiry_time based on created_at and token's validity_duration
    expiry_time = models.DateTimeField(null=True, blank=True)

    def __init__(self, *args, **kwargs):
        # Ensure expiry_time is set when the object is created
        super().__init__(*args, **kwargs)
        if self.token_details and self.created_at and not self.expiry_time:
            # Calculate expiry time based on created_at and validity_duration from TokenDetails
            self.expiry_time = self.created_at + self.token_details.validity_duration

    def save(self, *args, **kwargs):
        # Save method to persist the object
        super().save(*args, **kwargs)

    def __str__(self):
        return f'Token {self.auth_token} for User {self.user.id}'

    class Meta:
        db_table = 'ac_user_auth_tokens'  # Table name in the database
        verbose_name = 'User Auth Token'
        verbose_name_plural = 'User Auth Tokens'
