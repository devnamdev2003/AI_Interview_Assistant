from django.contrib import admin
from django.urls import path, include

from django.contrib import admin
from django.views.generic import RedirectView
from django.urls import path, re_path


urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('home.urls')),
    # path('user/', include('user_view.urls')),
    # path('company/', include('company_view.urls')),
    # path('api/', include('api.urls')),
    re_path(r"^.*/$", RedirectView.as_view(pattern_name="home_index", permanent=False)),
]
