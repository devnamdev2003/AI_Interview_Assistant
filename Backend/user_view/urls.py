from django.contrib import admin
from django.urls import path
from user_view import views

urlpatterns = [
    path('', views.index, name='index'),
]
