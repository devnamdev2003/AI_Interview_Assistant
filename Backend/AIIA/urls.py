from django.contrib import admin
from django.views.generic import RedirectView
from django.urls import path, re_path, include

admin.site.site_title = "AIIA site admin (DEV)"
admin.site.site_header = "AIIA administration"
admin.site.index_title = "Site administration"

urlpatterns = [
    path('dev/', admin.site.urls),
    path('', include('home.urls')),
    path('api/', include('api.urls')),
    path('interview/', include('interview.urls')),
    re_path(r"^.*/$", RedirectView.as_view(pattern_name="home_index", permanent=False)),
]
