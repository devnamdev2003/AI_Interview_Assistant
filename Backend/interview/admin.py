# admin.py

from django.contrib import admin
from .models import ScheduleInterview, InterviewModel


@admin.register(ScheduleInterview)
class ScheduleInterviewAdmin(admin.ModelAdmin):
    list_display = ('name', 'email', 'interview_completed', 'scheduled_by')


@admin.register(InterviewModel)
class InterviewModelAdmin(admin.ModelAdmin):
    list_display = ('email', 'job_role')
