
from django.urls import path
from .views import login, ai, interview
from django.urls import path

urlpatterns = [
    path('', ai.user_input, name='api'),
    path('login/', login.LoginView.as_view(), name='api_login'),

    # interviews/urls.py
    path('interviews/', interview.InterviewListCreateView.as_view(),
         name='interview-list-create'),
    path('interviews/<int:pk>/', interview.InterviewDetailView.as_view(),
         name='interview-detail'),
]