# Generated by Django 5.0.3 on 2024-03-28 11:28

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('interview', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='examplemodel',
            name='name',
            field=models.CharField(default=None, max_length=255, null=True),
        ),
    ]
