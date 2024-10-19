from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth import authenticate, login, logout, views as auth_views
from .models import UsersModel
from django.urls import reverse


class CustomPasswordResetView(auth_views.PasswordResetView):
    template_name = 'accounts/password/password_reset_form.html'
    email_template_name = 'accounts/password/password_reset_email.html'
    subject_template_name = 'accounts/password/dev.txt'
    def form_valid(self, form):
        email = form.cleaned_data['email']
        if not UsersModel.Users.objects.filter(email=email).exists():
            form.add_error(
                'email', 'This email is not associated with any user in our system.')
            return self.form_invalid(form)
        return super().form_valid(form)


def index(request):
    return render(request, 'accounts/index.html')


def user_login(request):
    if request.user.is_authenticated:
        return redirect('home')
    if request.method == 'POST':
        username_email = request.POST.get('username_email')
        password = request.POST.get('password')
        username = ""
        if UsersModel.Users.objects.filter(username=username_email).exists():
            user = UsersModel.Users.objects.filter(username=username_email).first()
            username = user.username
        if UsersModel.Users.objects.filter(email=username_email).exists():
            user = UsersModel.Users.objects.filter(email=username_email).first()
            username = user.username
        user = authenticate(request, username=username, password=password)
        if user is not None:
            login(request, user)
            return redirect('home')
        else:
            if not UsersModel.Users.objects.filter(username=username_email).exists() and not UsersModel.Users.objects.filter(email=username_email).exists():
                messages = "User does not exist"
            else:
                messages = "Invalid password"
            return render(request, 'accounts/login.html', {'message': messages})
    return render(request, 'accounts/login.html')


def user_register(request):
    if request.user.is_authenticated:
        return redirect('home')
    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')
        email = request.POST.get('email')
        phone_number = request.POST.get('phone_number')
        first_name = request.POST.get('first_name')
        last_name = request.POST.get('last_name')
        user_type = request.POST.get('userType')
        data = {
            "username": username,
            "password": password,
            "email": email,
            "phone_number": phone_number,
            "first_name": first_name,
            "last_name": last_name,
            "user_type": user_type,
        }
        if UsersModel.Users.objects.filter(username=username).exists():
            messages.error(request, 'Username already exists.')
            return render(request, 'accounts/register.html', {'message': 'Username already exists.', 'data': data})

        if UsersModel.Users.objects.filter(email=email).exists():
            messages.error(request, 'Email already exists.')
            return render(request, 'accounts/register.html', {'message': 'Email already exists.', 'data': data})
        if UsersModel.Users.objects.filter(phone_number=phone_number).exists():
            messages.error(request, 'Phone Number already exists.')
            return render(request, 'accounts/register.html', {'message': 'Phone Number already exists.', 'data': data})

        user = UsersModel.Users.objects.create_user(username=username, password=password, email=email, phone_number=phone_number, first_name=first_name,
                                              last_name=last_name,
                                              is_registered=True, user_type=user_type)
        login(request, user)
        return redirect('home')
    else:
        message = request.GET.get('message')
        return render(request, 'accounts/register.html', {'message': message})


def user_logout(request):
    logout(request)
    return redirect('home')


@login_required
def user_dashboard(request, username):
    user = get_object_or_404(UsersModel.Users, username=username)
    return render(request, 'accounts/user_dashboard.html', {'user': user})


@login_required
def update_user_details(request):
    if request.method == 'POST':
        user = request.user
        username = request.POST.get('username')
        email = request.POST.get('email')
        phone_number = request.POST.get('phone_number')
        first_name = request.POST.get('first_name')
        last_name = request.POST.get('last_name')
        data = {
            'username': username,
            'email': email,
            'phone_number': phone_number,
            'first_name': first_name,
            'last_name': last_name,
        }
        if phone_number != user.phone_number and UsersModel.Users.objects.filter(phone_number=phone_number).exclude(username=user.username).exists():
            messages.error(request, 'Phone number already exists.')
            return render(request, 'accounts/update.html', {'message': 'Phone number already exists.', 'data': data})

        if username != user.username and UsersModel.Users.objects.filter(username=username).exists():
            return render(request, 'accounts/update.html', {'message': 'Username already exists.', 'data': data})

        if email != user.email and UsersModel.Users.objects.filter(email=email).exists():
            return render(request, 'accounts/update.html', {'message': 'Email already exists.', 'data': data})

        user.username = username
        user.email = email
        user.phone_number = phone_number
        user.first_name = first_name
        user.last_name = last_name
        user.save()

        messages.success(
            request, 'Your details have been updated successfully.')
        return redirect(reverse('user_dashboard', kwargs={'username': user.username},))
    else:
        return render(request, 'accounts/update.html', {'data': request.user})
