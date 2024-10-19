# interviews/utils.py
from rest_framework.views import exception_handler
from rest_framework.response import Response


def custom_response(data=None, message="Operation successful", status_code=200, error=False, details=None):
    response = {
        "data": data if data else [],
        "response": {
            "status_code": status_code,
            "error": error,
            "message": message,
        }
    }

    if error:
        response["response"]["error_desc"] = details

    return Response(response, status=status_code)


def custom_exception_handler(exc, context):
    # Call the default exception handler provided by DRF
    response = exception_handler(exc, context)

    if response is not None:
        status_code = response.status_code
        # Get the main error message (usually found in 'detail')
        detail = response.data.get('detail', '')

        # Pass the entire response.data as 'details' if available
        details = response.data if response.data else None

        # Use your custom_response function
        return custom_response(
            data={},
            message=detail,
            status_code=status_code,
            error=True,
            details=details,
        )

    return response  # If there's no response, fallback to default behavior
