# yourapp/management/commands/list_urls.py
from django.core.management.base import BaseCommand
from django.urls import URLPattern, URLResolver
from django.conf import settings
from importlib import import_module

def list_urls(urlpatterns, base=""):
    """Recursively print URLs and their paths."""
    urls = []
    for pattern in urlpatterns:
        if isinstance(pattern, URLPattern):  # For simple paths
            urls.append(base + str(pattern.pattern))
        elif isinstance(pattern, URLResolver):  # For included paths
            urls += list_urls(pattern.url_patterns, base + str(pattern.pattern) + "/")
    return urls

class Command(BaseCommand):
    help = "Lists all URL patterns in the project"

    def handle(self, *args, **kwargs):
        root_urlconf = import_module(settings.ROOT_URLCONF)
        urlpatterns = root_urlconf.urlpatterns
        urls = list_urls(urlpatterns)
        for url in urls:
            self.stdout.write(url)
