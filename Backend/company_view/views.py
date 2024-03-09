from django.shortcuts import render


def index(request):
    return render(request, 'company_view/index.html', {"heading": "company_view"})
