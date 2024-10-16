import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    # for local
    # DATABASE = os.getenv("DATABASE_LOCAL")

    # # for testing
    # DATABASE = os.getenv("DATABASE_TEST")

    # # for live
    DATABASE = os.getenv("DATABASE_LIVE")

    GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
    SECRET_KEY = os.getenv("SECRET_KEY")
    EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER")
    EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD")
    XATA_API_KEY = os.getenv("XATA_API_KEY")
