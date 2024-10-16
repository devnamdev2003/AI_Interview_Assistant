from django.urls import path
from interview import views

urlpatterns = [
    path('', views.index, name="interview_index"),
    path('practice/', views.interview_practice, name="interview_practice"),
    path('slist/', views.schedule_interview_list, name="schedule_interview_list"),
    path('schedule_interview/', views.schedule_interview,
         name='schedule_interview'),
    path('success/', views.success_page, name='success_page'),
    path('<uuid:unique_id>/', views.unique_link_handler,
         name='unique_link_handler'),
    path('<uuid:unique_id>/interview_page',
         views.interview_page, name='interview_page'),
    path('result/', views.interview_result, name='interview_result'),
    path('sresult/', views.sinterview_result, name='sinterview_result')
]
