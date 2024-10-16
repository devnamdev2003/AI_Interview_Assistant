from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from models import CustomUser


def create_user(request):
    try:
        username = 'username'
        password = 'password'
        phone_number = 'phone_number'
        date_of_birth = 'date_of_birth'
        is_registered = 'is_registered'
        otp = 'otp'
        interview_limit = 'interview_limit'
        profile_picture = 'profile_picture'
        bio = 'bio'
        city = 'city'
        country = 'country'
        user_type = 'normal'

        # Create the user instance
        user = CustomUser.objects.create_user(
            username=username,
            password=password,
            phone_number=phone_number,
            date_of_birth=date_of_birth,
            is_registered=is_registered,
            otp=otp,
            interview_limit=interview_limit,
            profile_picture=profile_picture,
            bio=bio,
            city=city,
            country=country,
            user_type=user_type
        )

        # Return success response
        return 'User created successfully'

    except Exception as e:
        # Return error response if there's an exception
        return str(e)



def index(request):
    # Retrieve all CustomUser instances
    all_users = CustomUser.objects.all()

    # Iterate through each user and print their details
    for user in all_users:
        user_details = (
            f"Username: {user.username}\n"
            f"Phone Number: {user.phone_number}\n"
            f"Date of Birth: {user.date_of_birth}\n"
            f"Is Registered: {user.is_registered}\n"
            f"OTP: {user.otp}\n"
            f"Interview Limit: {user.interview_limit}\n"
            f"Bio: {user.bio}\n"
            f"City: {user.city}\n"
            f"Country: {user.country}\n"
            f"User Type: {user.get_user_type_display()}\n"
        )
        print(user_details)

    # Return a response indicating that the details are printed
    return "User details printed on terminal."
