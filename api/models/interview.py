from django.db import models
from accounts.models.UsersModel import Users


class Interview(models.Model):
    INTERVIEW_TYPES = [
        ('mock', 'Mock Interview'),
        ('real', 'Real Interview'),
    ]

    INTERVIEW_STATUSES = [
        ('scheduled', 'Scheduled'),
        ('completed', 'Completed'),
        ('canceled', 'Canceled'),
    ]

    interview_id = models.AutoField(primary_key=True)

    user = models.ForeignKey(
        Users, on_delete=models.CASCADE, related_name='candidate_interviews')

    company = models.ForeignKey(
        Users, on_delete=models.CASCADE, related_name='company_interviews')

    interview_type = models.CharField(max_length=50, choices=INTERVIEW_TYPES)

    scheduled_at = models.DateTimeField()

    duration = models.IntegerField(null=True, blank=True)

    interview_status = models.CharField(
        max_length=50, choices=INTERVIEW_STATUSES, default='scheduled')

    ai_assessment_generated = models.BooleanField(default=False)

    class Meta:
        db_table = 'interviews'

    def __str__(self):
        return f"Interview {self.interview_id} - {self.interview_type}"
