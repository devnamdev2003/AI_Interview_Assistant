# admin.py

from django.contrib import admin
from .models import ScheduleInterview, InterviewModel


@admin.register(ScheduleInterview)
class ScheduleInterviewAdmin(admin.ModelAdmin):
    list_display = ('name', 'email', 'unique_id', 'created_at')


@admin.register(InterviewModel)
class InterviewModelAdmin(admin.ModelAdmin):
    list_display = ('email','userdata')
