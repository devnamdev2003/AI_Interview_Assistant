from django.utils import timezone
from django.shortcuts import render, redirect, get_object_or_404
import uuid
from django.conf import settings
from django.core.mail import send_mail
from django.contrib.auth.decorators import login_required
from .models import ExampleModel
from datetime import datetime


@login_required
def index(request):
    if request.method == 'POST':
        name = request.POST.get('name')
        job_role = request.POST.get('jobRole')
        interview_type = request.POST.get('interviewType')
        experience = request.POST.get('experience')
        request.session['data'] = {
            'name': name,
            'job_role': job_role,
            'interview_type': interview_type,
            'experience': experience
        }

        return redirect('interview_practice')
    else:
        return render(request, 'interview/index.html')


@login_required
def interview_practice(request):
    data = request.session.get('data', {})
    print(data)
    return render(request, 'interview/interview_practice.html', {'data': data})


def schedule_interview(request):
    protocol = 'https' if request.is_secure() else 'http'
    domain = request.get_host()
    print("Protocol:", protocol)
    print("Domain:", domain)
    if request.method == 'POST':
        name = request.POST.get('name')
        email = request.POST.get('email')
        start_time = request.POST.get('start_time')
        end_time = request.POST.get('end_time')
        unique_id = uuid.uuid4()
        ExampleModel.objects.create(name=name,
                                    email=email, unique_id=unique_id, start_time=start_time, end_time=end_time)

        unique_link = f"{settings.BASE_URL}{unique_id}/"

        subject = 'Invitation to Interview'
        from_email = 'carrer@aiia.com'
        start_time = datetime.strptime(start_time, '%Y-%m-%dT%H:%M')
        end_time = datetime.strptime(end_time, '%Y-%m-%dT%H:%M')

        email_body = f"Dear {name},\n\n" \
            f"We are pleased to invite you to an interview for the position you applied for. " \
            f"Please find below the details:\n\n" \
            f"Interview Link: {protocol}://{domain}{unique_link}\n" \
            f"Interview Date: {start_time.strftime('%Y-%m-%d %H:%M')} to {end_time.strftime('%Y-%m-%d %H:%M')}\n\n" \
            f"Thank you for your interest. We look forward to meeting you!\n\n" \
            f"Best regards,\n AIIA"

        send_mail(
            subject,
            email_body,
            settings.EMAIL_HOST_USER,
            [email],
            fail_silently=False,
        )
        return redirect('success_page')
    return render(request, 'interview/schedule_interview/schedule_interview.html')


def success_page(request):
    return render(request, 'interview/schedule_interview/success_page.html')


def unique_link_handler(request, unique_id):
    instance = get_object_or_404(ExampleModel, unique_id=unique_id)

    current_time = timezone.now()
    if current_time < instance.start_time:
        message = {
            "before": "The link is not yet accessible. Please try again later."
        }
    elif current_time > instance.end_time:
        message = {
            "after": "The link has expired."
        }
    else:
        message = None
    return render(request, 'interview/schedule_interview/unique_link_page.html', {'instance': instance, 'message': message})


def interview_page(request, unique_id):
    instance = get_object_or_404(ExampleModel, unique_id=unique_id)

    return render(request, 'interview/schedule_interview/interview_page.html', {'instance': instance, 'key': unique_id})
