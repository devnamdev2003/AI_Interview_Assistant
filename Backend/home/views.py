
from django.contrib.auth import authenticate
from django.contrib.auth.decorators import login_required
from django.contrib.auth import authenticate, login
from django.contrib import messages
from django.shortcuts import render, redirect
from django.contrib.auth import authenticate, login, logout
from .models import CustomUser
from django.shortcuts import render, get_object_or_404

from django.contrib.auth import views as auth_views



class CustomPasswordResetView(auth_views.PasswordResetView):
    template_name = 'home/password/password_reset_form.html'
    email_template_name = 'home/password/password_reset_email.html'
    def form_valid(self, form):
        email = form.cleaned_data['email']
        if not CustomUser.objects.filter(email=email).exists():
            form.add_error(
                'email', 'This email is not associated with any user in our system.')
            return self.form_invalid(form)
        return super().form_valid(form)


@login_required
def user_dashboard(request, username):
    user = get_object_or_404(CustomUser, username=username)
    return render(request, 'home/user_dashboard.html', {'user': user})


def index(request):
    return render(request, 'home/base.html')


def user_login(request):
    if request.user.is_authenticated:
        return redirect('home_index')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        user = authenticate(request, username=username, password=password)
        if user is not None:
            login(request, user)
            return redirect('home_index')
        else:
            messages = "Wrong credentials"
            if not CustomUser.objects.filter(username=username).exists():
                messages = "User does not exist"
            else:
                messages = "Invalid password"
            return render(request, 'home/login.html', {'message': messages})
    return render(request, 'home/login.html')


def user_register(request):
    if request.user.is_authenticated:
        return redirect('home_index')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        email = request.POST.get('email')
        phone_number = request.POST.get('phone_number')
        first_name = request.POST.get('first_name')
        last_name = request.POST.get('last_name')
        if CustomUser.objects.filter(username=username).exists():
            messages.error(request, 'Username already exists.')
            return render(request, 'home/register.html', {'message': 'Username already exists.'})

        if CustomUser.objects.filter(email=email).exists():
            messages.error(request, 'Email already exists.')
            return render(request, 'home/register.html', {'message': 'Email already exists.'})

        user = CustomUser.objects.create_user(username=username, password=password, email=email,
                                              phone_number=phone_number, first_name=first_name,
                                              last_name=last_name,
                                              is_registered=True)
        login(request, user)
        return redirect('home_index')
    else:
        message = request.GET.get('message')
        return render(request, 'home/register.html', {'message': message})


def user_logout(request):
    logout(request)
    return redirect('home_index')
