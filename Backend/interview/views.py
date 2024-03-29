from django.utils import timezone
from django.shortcuts import render, redirect, get_object_or_404
import uuid
from django.conf import settings
from django.core.mail import send_mail
from django.contrib.auth.decorators import login_required
from .models import ScheduleInterview
from datetime import datetime
import json


@login_required
def index(request):
    if request.method == 'POST':
        name = request.POST.get('name')
        jobRole = request.POST.get('jobRole')
        interviewType = request.POST.get('interviewType')
        experience = request.POST.get('experience')
        request.session['data'] = {
            'name': name,
            'jobRole': jobRole,
            'interviewType': interviewType,
            'experience': experience
        }

        return redirect('interview_practice')
    else:
        return render(request, 'interview/index.html')


@login_required
def interview_practice(request):
    interviewData = request.session.get('data', {})
    if request.method == 'POST':
        QA = request.POST.get('data')
        QA = json.loads(QA)
        if 'QA' in request.session:
            del request.session['QA']
        request.session['QA'] = QA
        return redirect('interview_result')

    return render(request, 'interview/interview_practice.html', {'data': interviewData})


@login_required
def interview_result(request):
    interviewData = request.session.get('data', {})
    QA = request.session.get('QA', {})
    return render(request, 'interview/result.html', {'interviewData': interviewData, 'QA': QA})


def schedule_interview(request):
    protocol = 'https' if request.is_secure() else 'http'
    domain = request.get_host()
    if request.method == 'POST':
        name = request.POST.get('name')
        email = request.POST.get('email')
        start_time = request.POST.get('start_time')
        end_time = request.POST.get('end_time')
        unique_id = uuid.uuid4()
        ScheduleInterview.objects.create(name=name,
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
    instance = get_object_or_404(ScheduleInterview, unique_id=unique_id)

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
    instance = get_object_or_404(ScheduleInterview, unique_id=unique_id)

    return render(request, 'interview/schedule_interview/interview_page.html', {'instance': instance, 'key': unique_id})
