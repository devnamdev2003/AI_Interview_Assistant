from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from api.models import Users, Role, TokenDetails, UserAuthTokens
from django.utils.html import format_html
from django.utils import timezone


class CustomUserAdmin(UserAdmin):
    # Fields to be displayed in the list view
    list_display = (
        'username', 'email', 'first_name', 'last_name', 'status', 'is_verified', 'created_at', 'updated_at'
    )
    # Fields to make searchable in the admin panel
    search_fields = ('username', 'email', 'first_name', 'last_name',)
    # Fields to filter by in the admin panel
    list_filter = ('status', 'is_verified',)
    # Fieldsets to organize fields on the edit page
    fieldsets = (
        (None, {'fields': ('username', 'password')}),  # Core fields
        ('Personal Info', {'fields': ('first_name', 'last_name', 'email',
         'date_of_birth', 'phone_number', 'gender', 'address')}),
        ('Account Info', {'fields': ('status', 'is_verified',
         'profile_picture_url', 'time_zone', 'login_attempt_count', 'password_last_changed_at')}),
        ('Permissions', {'fields': ('is_staff', 'is_active',
         'is_superuser', 'groups', 'user_permissions')}),
        ('Role & Country', {'fields': ('role', 'country')}),
        ('Important Dates', {
         'fields': ('last_login', 'created_at', 'updated_at')}),
    )
    # Fields to display in the add form
    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': ('username', 'password1', 'password2', 'email', 'first_name', 'last_name', 'status', 'is_verified', 'role', 'country'),
        }),
    )
    # Set readonly fields
    readonly_fields = ('created_at', 'updated_at',
                       'password_last_changed_at', 'login_attempt_count', 'last_login')


class RoleAdmin(admin.ModelAdmin):
    # Fields to display in the list view
    list_display = ('name', 'id', 'description', 'is_active',
                    'created_at', 'updated_at')
    # Fields to search by
    search_fields = ('name', 'description')
    # Fields to filter by
    list_filter = ('is_active', 'created_at')
    # Fieldsets to organize fields on the edit page
    fieldsets = (
        (None, {
            'fields': ('name', 'description')
        }),
        ('Status', {
            'fields': ('is_active',)
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at')
        }),
    )
    # Set readonly fields
    readonly_fields = ('created_at', 'updated_at')
    # Default ordering
    ordering = ('-created_at',)  # Order by created_at in descending order

    # Define custom actions for bulk operations
    actions = ['activate_roles', 'deactivate_roles']

    # Custom action to activate selected roles
    def activate_roles(self, request, queryset):
        queryset.update(is_active=True)
        self.message_user(request, "Selected roles have been activated.")
    activate_roles.short_description = "Activate selected roles"

    # Custom action to deactivate selected roles
    def deactivate_roles(self, request, queryset):
        queryset.update(is_active=False)
        self.message_user(request, "Selected roles have been deactivated.")
    deactivate_roles.short_description = "Deactivate selected roles"


class TokenDetailsAdmin(admin.ModelAdmin):
    # Display fields in the list view
    list_display = ('type', 'description', 'validity_duration', 'is_active')

    # Add filter options to filter records by 'is_active' field
    list_filter = ('is_active',)

    # Add search functionality for 'type' and 'description'
    search_fields = ('type', 'description')

    # Allow editing of some fields directly in the list view (optional)
    list_editable = ('is_active',)

    # Define ordering of records in the list view
    ordering = ('-created_at',)

    # Define fieldsets to organize the fields in the admin form view
    fieldsets = (
        (None, {
            'fields': ('type', 'description', 'validity_duration', 'is_active')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
        }),
    )
    readonly_fields = ('created_at', 'updated_at')


class UserAuthTokensAdmin(admin.ModelAdmin):
    # Display the fields you want in the list view
    list_display = ('id', 'user', 'auth_token', 'created_at', 'expiry_time',
                    'is_expired', 'last_accessed_at', 'revoked_date', 'revoked_reason')

    # Add filters for easier admin management
    list_filter = ('is_expired', 'revoked_date', 'token_details', 'created_at')

    # Add search functionality
    search_fields = ('auth_token', 'user__username', 'user__email')

    # Allow actions like marking tokens as expired or revoked
    actions = ['mark_as_expired', 'mark_as_revoked']

    # Action to mark tokens as expired
    def mark_as_expired(self, request, queryset):
        rows_updated = queryset.update(is_expired=True)
        if rows_updated == 1:
            message_bit = "1 token was"
        else:
            message_bit = f"{rows_updated} tokens were"
        self.message_user(
            request, f"{message_bit} successfully marked as expired.")
    mark_as_expired.short_description = "Mark selected tokens as expired"

    # Action to mark tokens as revoked
    def mark_as_revoked(self, request, queryset):
        rows_updated = queryset.update(
            is_expired=True, revoked_date=timezone.now(), revoked_reason="Admin revoked")
        if rows_updated == 1:
            message_bit = "1 token was"
        else:
            message_bit = f"{rows_updated} tokens were"
        self.message_user(
            request, f"{message_bit} successfully marked as revoked.")
    mark_as_revoked.short_description = "Mark selected tokens as revoked"

    # Make fields clickable (e.g., user and token details)
    def user_link(self, obj):
        return format_html('<a href="/admin/auth/user/{}/change/">{}</a>', obj.user.id, obj.user.username)
    user_link.short_description = 'User'

    # Custom ordering
    ordering = ['-created_at']

    # Fieldsets for detailed view customization
    fieldsets = (
        (None, {
            'fields': ('user', 'auth_token', 'token_details', 'created_at', 'expiry_time', 'is_expired')
        }),
        ('Revocation Info', {
            'fields': ('revoked_date', 'revoked_reason'),
            'classes': ('collapse',),
        }),
        ('Last Accessed', {
            'fields': ('last_accessed_at',),
            'classes': ('collapse',),
        }),
    )

    # Read-only fields
    readonly_fields = ('created_at', 'expiry_time')


admin.site.register(UserAuthTokens, UserAuthTokensAdmin)
admin.site.register(TokenDetails, TokenDetailsAdmin)
admin.site.register(Users, CustomUserAdmin)
admin.site.register(Role, RoleAdmin)
