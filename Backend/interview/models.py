from django.db import models


from django.db import models


class ScheduleInterview(models.Model):
    name = models.CharField(max_length=255, default=None, null=True)
    email = models.EmailField()
    unique_id = models.UUIDField(unique=True)
    start_time = models.DateTimeField()
    end_time = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    job_role = models.CharField(max_length=255, null=True)
    experience = models.CharField(max_length=100, null=True)
    interview_type = models.CharField(max_length=100, null=True)
    interview_completed = models.BooleanField(default=False)

    def __str__(self):
        return self.email


class InterviewModel(models.Model):
    userdata = models.CharField(max_length=500)
    email = models.EmailField()
    qa = models.TextField(default='{"QA": []}')

    def __str__(self):
        return self.email
