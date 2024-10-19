from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.authentication import JWTAuthentication
from ..models.interview import Interview
from ..serializers.interview import InterviewSerializer
from .utils import custom_response
from rest_framework import status
from django.core.exceptions import ValidationError
from django.db import IntegrityError, DatabaseError


class InterviewListCreateView(APIView):
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        try:
            # Get query parameters
            interview_id = request.query_params.get('interview_id', None)
            status_filter = request.query_params.get('status', None)

            # Filter interviews based on parameters
            interviews = Interview.objects.all()

            if interview_id is not None:
                interviews = interviews.filter(interview_id=interview_id)

            if status_filter is not None:
                interviews = interviews.filter(interview_status=status_filter)

            serializer = InterviewSerializer(interviews, many=True)
            return custom_response(data=serializer.data, message="Interviews retrieved successfully", status_code=status.HTTP_200_OK)

        except Exception as e:
            # Catch-all for any other unexpected exceptions
            return custom_response(
                data={},
                message="An unexpected error occurred. Please try again later.",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

    def post(self, request, *args, **kwargs):
        try:
            serializer = InterviewSerializer(data=request.data)
            if serializer.is_valid():
                serializer.save()
                return custom_response(data=serializer.data, message="Interview created successfully", status_code=status.HTTP_201_CREATED)
            return custom_response(data=None, message="Interview creation failed", status_code=status.HTTP_400_BAD_REQUEST, error=True, details=serializer.errors, error_code="E_VALIDATION_ERROR")

        except IntegrityError as e:
            return custom_response(
                data=None,
                message="Data integrity error during interview creation",
                status_code=status.HTTP_400_BAD_REQUEST,
                error=True,
                details=str(e)
            )

        except DatabaseError as e:
            return custom_response(
                data=None,
                message="Database error occurred",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

        except Exception as e:
            # Catch-all for any other unexpected exceptions
            return custom_response(
                data={},
                message="An unexpected error occurred during interview creation.",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )


class InterviewDetailView(APIView):
    authentication_classes = [JWTAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        try:
            interview = Interview.objects.get(pk=kwargs['pk'])
            serializer = InterviewSerializer(interview)
            return custom_response(data=serializer.data, message="Interview retrieved successfully", status_code=status.HTTP_200_OK)

        except Interview.DoesNotExist:
            return custom_response(
                data=None,
                message="Interview not found",
                status_code=status.HTTP_404_NOT_FOUND,
                error=True
            )

        except ValidationError as e:
            return custom_response(
                data=None,
                message="Invalid interview ID",
                status_code=status.HTTP_400_BAD_REQUEST,
                error=True,
                details=str(e)
            )

        except Exception as e:
            return custom_response(
                data={},
                message="An unexpected error occurred while retrieving the interview.",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

    def put(self, request, *args, **kwargs):
        try:
            interview = Interview.objects.get(pk=kwargs['pk'])
            serializer = InterviewSerializer(
                interview, data=request.data, partial=True)
            if serializer.is_valid():
                serializer.save()
                return custom_response(data=serializer.data, message="Interview updated successfully", status_code=status.HTTP_200_OK)
            return custom_response(data=None, message="Interview update failed", status_code=status.HTTP_400_BAD_REQUEST, error=True, details=serializer.errors, error_code="E_VALIDATION_ERROR")

        except Interview.DoesNotExist:
            return custom_response(
                data=None,
                message="Interview not found",
                status_code=status.HTTP_404_NOT_FOUND,
                error=True
            )

        except IntegrityError as e:
            return custom_response(
                data=None,
                message="Data integrity error during interview update",
                status_code=status.HTTP_400_BAD_REQUEST,
                error=True,
                details=str(e)
            )

        except DatabaseError as e:
            return custom_response(
                data=None,
                message="Database error occurred",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

        except Exception as e:
            return custom_response(
                data={},
                message="An unexpected error occurred while updating the interview.",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

    def delete(self, request, *args, **kwargs):
        try:
            interview = Interview.objects.get(pk=kwargs['pk'])
            interview.delete()
            return custom_response(data=None, message="Interview deleted successfully", status_code=status.HTTP_204_NO_CONTENT)

        except Interview.DoesNotExist:
            return custom_response(
                data=None,
                message="Interview not found",
                status_code=status.HTTP_404_NOT_FOUND,
                error=True
            )

        except DatabaseError as e:
            return custom_response(
                data=None,
                message="Database error occurred",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )

        except Exception as e:
            return custom_response(
                data={},
                message="An unexpected error occurred while deleting the interview.",
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                error=True,
                details=str(e)
            )
