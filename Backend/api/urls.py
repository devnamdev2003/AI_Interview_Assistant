from django.contrib import admin
from django.urls import path
from api import views

urlpatterns = [
    path('', views.user_input, name='user_input'),
]
