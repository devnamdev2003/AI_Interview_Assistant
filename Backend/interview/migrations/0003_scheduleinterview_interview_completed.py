# Generated by Django 5.0.3 on 2024-03-30 16:18

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('interview', '0002_scheduleinterview_experience_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='scheduleinterview',
            name='interview_completed',
            field=models.BooleanField(default=False),
        ),
    ]
