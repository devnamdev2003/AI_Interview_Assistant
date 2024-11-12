from django.contrib import admin
from api.models import Country

class CountryAdmin(admin.ModelAdmin):
    # Fields to display in the list view
    list_display = ('country_name', 'country_code', 'is_active', 'created_at', 'updated_at')
    # Fields to search by
    search_fields = ('country_name', 'country_code')
    # Fields to filter by in the admin panel
    list_filter = ('is_active', 'created_at')
    # Fieldsets to organize fields on the edit page
    fieldsets = (
        (None, {
            'fields': ('country_name', 'country_code')
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
    ordering = ('country_name',)  # Orders by country name in ascending order

    # Define custom actions for bulk operations
    actions = ['activate_countries', 'deactivate_countries']

    # Custom action to activate selected countries
    def activate_countries(self, request, queryset):
        queryset.update(is_active=True)
        self.message_user(request, "Selected countries have been activated.")
    activate_countries.short_description = "Activate selected countries"

    # Custom action to deactivate selected countries
    def deactivate_countries(self, request, queryset):
        queryset.update(is_active=False)
        self.message_user(request, "Selected countries have been deactivated.")
    deactivate_countries.short_description = "Deactivate selected countries"

# Register the Country model and custom admin
admin.site.register(Country, CountryAdmin)

