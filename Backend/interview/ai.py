import os
import google.generativeai as genai

genai.configure(api_key=os.environ['GOOGLE_API_KEY'])


def get_ai_response_google(query):
    try:
        model = genai.GenerativeModel('gemini-pro')
        response = model.generate_content(query)
        response_text = response.text
        return response_text
    except Exception as e:
        response_data = f'AI error: {str(e)}'
        return response_data


print(get_ai_response_google("hi"))
