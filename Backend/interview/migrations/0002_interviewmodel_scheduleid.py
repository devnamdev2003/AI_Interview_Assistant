# Generated by Django 5.0.3 on 2024-04-09 03:49

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('interview', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='interviewmodel',
            name='ScheduleID',
            field=models.CharField(default='', max_length=255),
        ),
    ]