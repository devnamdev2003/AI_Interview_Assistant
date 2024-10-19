# interviews/serializers.py

from rest_framework import serializers
from ..models.interview import Interview 

class InterviewSerializer(serializers.ModelSerializer):
    class Meta:
        model = Interview
        fields = '__all__'  # You can specify individual fields if you don't want to include all
