import json
from django.db import models
import os
import google.generativeai as genai

genai.configure(api_key=os.environ['GOOGLE_API_KEY'])


def get_ai_response_google(user_message, role):
    print("Received a request by google to get AI response.")
    try:
        text = f"{user_message}\n{role}"
        print(text)
        model = genai.GenerativeModel('gemini-pro')
        response = model.generate_content(text)
        response_text = response.text
        print("AI response received.")
        print(response_text)
        return response_text
    except Exception as e:
        response_data = f'AI error: {str(e)}'
        print(f"AI error: {str(e)}")
        return response_data

class InterviewModel(models.Model):
    email = models.EmailField()
    ScheduleID = models.CharField(max_length=255, default="")
    job_role = models.CharField(max_length=500)
    qa = models.TextField(default='{"QA": []}')
    is_scheduled = models.BooleanField(default=False)
    result = models.TextField(blank=True)

    def save(self, *args, **kwargs):
        role = "As the interviewer, your role is to analyze the candidate's interview answers and generate a score out of 100 based on the quality of their responses. Additionally, you should provide feedback for each answer to help the candidate understand areas of strength and areas for improvement."
        user_message = f"Job role: {self.job_role} \ninterview questions and answers: {json.loads(self.qa)}"
        result_data = get_ai_response_google(user_message, role)
        self.result = json.dumps(result_data)
        super().save(*args, **kwargs)

    def __str__(self):
        return self.email
 