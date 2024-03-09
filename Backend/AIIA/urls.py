from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('home.urls')),
    path('user/', include('user_view.urls')),
    path('company/', include('company_view.urls')),
    path('api/', include('api.urls')),
]
