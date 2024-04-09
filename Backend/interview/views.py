from django.utils import timezone
from django.shortcuts import render, redirect, get_object_or_404
import uuid
from django.conf import settings
from django.core.mail import send_mail
from django.contrib.auth.decorators import login_required
from .models import ScheduleInterview, InterviewModel
from datetime import datetime
import json
from django.urls import reverse


def send_email(email_body, subject, email):
    send_mail(
        subject,
        email_body,
        settings.EMAIL_HOST_USER,
        [email],
        fail_silently=False,
    )


@login_required
def index(request):
    if request.method == 'POST':
        name = request.user.username
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

@login_required
def schedule_interview_list(request):
    Interviews = InterviewModel.objects.all()
    return render(request, 'interview/schedule_interview/schedule_interview_list.html', {'Interviews': Interviews})
    

def schedule_interview(request):
    protocol = 'https' if request.is_secure() else 'http'
    domain = request.get_host()
    if request.method == 'POST':
        name = request.POST.get('name')
        email = request.POST.get('email')
        start_time_str = request.POST.get('start_time')
        end_time_str = request.POST.get('end_time')
        start_time = timezone.make_aware(datetime.strptime(start_time_str, '%Y-%m-%dT%H:%M'))
        end_time = timezone.make_aware(datetime.strptime(end_time_str, '%Y-%m-%dT%H:%M'))
        unique_id = uuid.uuid4()
        job_role = request.POST.get('jobRole')
        interview_type = request.POST.get('interviewType')
        experience = request.POST.get('experience')
        scheduled_by = request.user.username
        interview_link = f"{protocol}://{domain}{settings.BASE_URL}{unique_id}/"

        ScheduleInterview.objects.create(name=name,
                                         email=email, unique_id=unique_id, start_time=start_time, end_time=end_time, job_role=job_role, interview_type=interview_type, experience=experience, scheduled_by=scheduled_by, interview_link=interview_link)

        unique_link = f"{settings.BASE_URL}{unique_id}/"

        subject = f'Invitation to Interview: {job_role}'
        from_email = 'carrer@aiia.com'
        start_time_str = start_time.strftime('%Y-%m-%dT%H:%M')
        end_time_str = end_time.strftime('%Y-%m-%dT%H:%M')

        email_body = f"\nDear {name},\n\nWe are pleased to inform you that your application for the {job_role} position at AIIA has been considered, and we would like to invite you for an interview. Your qualifications and experiences are impressive, and we believe you could be a valuable addition to our team.\n\nPlease find below the details for your interview:\n\nInterview Link: {protocol}://{domain}{unique_link}\n\nInterview Date: {start_time.strftime('%Y-%m-%d %H:%M')} to {end_time.strftime('%Y-%m-%d %H:%M')}\n\nWe appreciate your interest in joining AIIA, and we eagerly anticipate the opportunity to discuss your application further. Should you have any questions or require additional information before the interview, please feel free to contact us.\n\nThank you for considering a career with AIIA, and we look forward to meeting with you soon.\n\nBest regards,\nAIIA\n{protocol}://{domain}"

        send_email(email_body, subject, email)
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
    elif instance.interview_completed:
        message = {
            'done': "You are already given the interview"
        }
    else:
        message = None
    return render(request, 'interview/schedule_interview/unique_link_page.html', {'instance': instance, 'message': message})


def interview_page(request, unique_id):
    instance = get_object_or_404(ScheduleInterview, unique_id=unique_id)
    data = {
        'name': instance.name,
        'jobRole': instance.job_role,
        'interviewType': instance.interview_type,
        'experience': instance.experience
    }
    if instance.interview_completed:
        return redirect(reverse('unique_link_handler', kwargs={'unique_id': instance.unique_id},))

    if request.method == 'POST':
        instance.interview_completed = True
        instance.save()
        qa = request.POST.get('data')
        job_role = instance.job_role
        email = instance.email
        interview = InterviewModel.objects.create(
            job_role=job_role,
            email=email,
            qa=qa,
            ScheduleID=unique_id,
            is_scheduled=True
        )
        return render(request, 'interview/schedule_interview/result.html')
    return render(request, 'interview/schedule_interview/interview_page.html', {'instance': instance, 'key': unique_id, 'data': data})


def sinterview_result(request):
    return render(request, 'interview/schedule_interview/result.html')
