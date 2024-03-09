from django.shortcuts import render


def index(request):
    return render(request, 'user_view/index.html',  {"heading": "user_view"})
