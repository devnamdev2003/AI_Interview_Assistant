@echo off
setlocal

rem Set paths

set "project_directory=%CD%"
set "venv_directory=%project_directory%\env"


rem Check if virtual environment exists
if exist "%venv_directory%\Scripts\activate.bat" (
    echo "virtual environment present"

    rem Virtual environment exists, activate it
    call "%venv_directory%\Scripts\activate"
    echo "virtual environment activated"
) else (
    echo "virtual environment not present"

    rem Virtual environment does not exist, create it
    python -m venv "%venv_directory%"
    echo "virtual environment created successfully"

    call "%venv_directory%\Scripts\activate"
    echo "virtual environment activated"

    rem Install dependencies
    pip install -r "%project_directory%\requirements.txt"
    echo "libraries installed"
)

echo "project started..."
rem Run Django development server in background
start "Django Server" /B  python .\Backend\manage.py runserver

rem Wait for a short time to ensure the server is up and running
timeout /t 10

rem Open the application in a browser
start "" http://127.0.0.1:8000

endlocal
