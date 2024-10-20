
from django.urls import path
from .views import login, ai, interview, token
from django.urls import path

urlpatterns = [
    path('', ai.user_input, name='api'),
    path('auth/login/', login.LoginView.as_view(), name='api_login'),

    path('interviews/', interview.InterviewListCreateView.as_view(),
         name='interview-list-create'),
    path('interviews/<int:pk>/', interview.InterviewDetailView.as_view(),
         name='interview-detail'),
    path('auth/token/verify/', token.VerifyTokenView.as_view(), name='check_token'),
]