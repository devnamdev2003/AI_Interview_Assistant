from django.contrib import admin
from django.urls import path
from company_view import views

urlpatterns = [
    path('', views.index, name='company_index'),
]
