from django.urls import path
from django.contrib.auth import views as auth_views
from . import views
urlpatterns = [
    path('login/', views.user_login, name='login'),
    path('register/', views.user_register, name='register'),
    path('logout/', views.user_logout, name='logout'),
    path('update/', views.update_user_details, name='update_user_details'),
    path('user/<str:username>/', views.user_dashboard, name='user_dashboard'),


    path('password-reset/', views.CustomPasswordResetView.as_view(),
         name='password_reset'),

    path('password-reset/done/', auth_views.PasswordResetDoneView.as_view(template_name="accounts/password/password_reset_done.html"),
         name='password_reset_done'),
    path('reset/<uidb64>/<token>/', auth_views.PasswordResetConfirmView.as_view(
        template_name="accounts/password/password_reset_confirm.html"), name='password_reset_confirm'),
    path('reset/done/', auth_views.PasswordResetCompleteView.as_view(template_name="accounts/password/password_reset_complete.html"),
         name='password_reset_complete'),
]
