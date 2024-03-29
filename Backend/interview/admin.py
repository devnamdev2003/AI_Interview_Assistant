# admin.py

from django.contrib import admin
from .models import ScheduleInterview


@admin.register(ScheduleInterview)
class ScheduleInterviewAdmin(admin.ModelAdmin):
    list_display = ('name', 'email', 'unique_id', 'created_at')
