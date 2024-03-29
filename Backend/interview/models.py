from django.db import models


class ScheduleInterview(models.Model):
    email = models.EmailField()
    name = models.CharField(max_length=255, default=None, null=True)
    unique_id = models.UUIDField(unique=True)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.email


class InterviewModel(models.Model):
    userdata = models.CharField(max_length=500)
    email = models.EmailField()
    qa = models.TextField(default='{"QA": []}')

    def __str__(self):
        return self.email
