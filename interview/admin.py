from django.contrib import admin
from .models import interviewModel, scheduleInterviewModel

@admin.register(scheduleInterviewModel.ScheduleInterview)
class ScheduleInterviewAdmin(admin.ModelAdmin):
    list_display = ('name', 'email', 'interview_completed', 'scheduled_by')


@admin.register(interviewModel.InterviewModel)
class InterviewModelAdmin(admin.ModelAdmin):
    list_display = ('email', 'job_role')
