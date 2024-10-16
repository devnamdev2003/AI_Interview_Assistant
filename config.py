import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    # for local
    development = False

    if development:
        DATABASE_URL = os.getenv("DATABASE_LOCAL")
        DEBUG = True
        STATIC_URL = '/static/'
    else:
        # for testing
        DATABASE_URL = os.getenv("DATABASE_TEST")
        DEBUG = False
        STATIC_URL = '/staticfiles/'
        # for live
        # DATABASE_URL = os.getenv("DATABASE_LIVE")
        # DEBUG = False
        # STATIC_URL = '/staticfiles/'
    
    DATABASE_LIVE = os.getenv("DATABASE_LIVE")
    DATABASE_LOCAL = os.getenv("DATABASE_LOCAL")
    DATABASE_TEST = os.getenv("DATABASE_TEST")
    GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
    SECRET_KEY = os.getenv("SECRET_KEY")
    EMAIL_HOST_USER = os.getenv("EMAIL_HOST_USER")
    EMAIL_HOST_PASSWORD = os.getenv("EMAIL_HOST_PASSWORD")
    XATA_API_KEY = os.getenv("XATA_API_KEY")
