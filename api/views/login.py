from rest_framework.views import APIView
from django.contrib.auth import authenticate, login
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework.response import Response
from rest_framework import status
from accounts import models
from .utils import custom_response
from rest_framework.status import HTTP_200_OK, HTTP_401_UNAUTHORIZED, HTTP_400_BAD_REQUEST, HTTP_500_INTERNAL_SERVER_ERROR
from django.core.exceptions import ValidationError

class LoginView(APIView):
    def post(self, request, *args, **kwargs):
        try:
            username_email = request.data.get('username_email')
            password = request.data.get('password')

            # Check if username_email is missing or empty
            if not username_email:
                return custom_response(
                    data={},
                    message="Username/email is required",
                    status_code=HTTP_400_BAD_REQUEST,
                    error=True,
                    details={"username_email": username_email, "password": password}
                )

            # Check if password is missing or empty
            if not password:
                return custom_response(
                    data={},
                    message="Password is required",
                    status_code=HTTP_400_BAD_REQUEST,
                    error=True,
                    details={"username_email": username_email, "password": password}
                )

            # Find user by username or email
            user = models.UsersModel.Users.objects.filter(username=username_email).first() or \
                   models.UsersModel.Users.objects.filter(email=username_email).first()

            if user is None:
                # Invalid username/email case
                return custom_response(
                    data={},
                    message="User not found with the provided username/email",
                    status_code=HTTP_401_UNAUTHORIZED,
                    error=True,
                    details={"username_email": username_email}
                )

            # Check if user is active
            if not user.is_active:
                return custom_response(
                    data={},
                    message="User account is inactive. Please contact support.",
                    status_code=HTTP_401_UNAUTHORIZED,
                    error=True,
                    details={"username_email": username_email}
                )

            # Authenticate user with username and password
            user = authenticate(request, username=user.username, password=password)
            if user is not None:
                login(request, user)  # Django's login function to set session
                refresh = RefreshToken.for_user(user)
                token = {
                    'refresh': str(refresh),
                    'access': str(refresh.access_token),
                }
                return custom_response(
                    data=token,
                    message="Login successful",
                    status_code=HTTP_200_OK,
                    error=False
                )
            else:
                # Invalid password case
                return custom_response(
                    data={},
                    message="Invalid password",
                    status_code=HTTP_401_UNAUTHORIZED,
                    error=True,
                    details={"username_email": username_email}
                )

        except ValidationError as e:
            # Handle any Django validation errors explicitly
            return custom_response(
                data={},
                message="Validation error occurred",
                status_code=HTTP_400_BAD_REQUEST,
                error=True,
                details=str(e)
            )

        except Exception as e:
            # Catch-all for any other unexpected exceptions
            return custom_response(
                data={},
                message="An unexpected error occurred. Please try again later.",
                status_code=HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )
