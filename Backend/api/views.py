import openai
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
import os
import json
import concurrent.futures
import time
import google.generativeai as genai

genai.configure(api_key=os.environ['GAPI_KEY'])
openai.api_key = os.getenv('OPENAI_KEY')


@csrf_exempt
def user_input(request):
    print("Received a user input request.")
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            if 'model_role' in data and 'user_message' in data:
                conversation = [
                        {"role": "system", "content": data['model_role']},
                        {"role": "user", "content":  data['user_message']}
                    ]
                print(data)
                if 'ai' in data:
                    if data['ai']=="google":
                        with concurrent.futures.ThreadPoolExecutor() as executor:
                            ai_output = "Timed out please try again"
                            try:
                                ai_output = executor.submit(
                                    get_ai_response_google, conversation).result(timeout=40)
                            except concurrent.futures.TimeoutError:
                                pass
                    elif data['ai']=="openai":
                        with concurrent.futures.ThreadPoolExecutor() as executor:
                            ai_output = "Timed out please try again"
                            try:
                                ai_output = executor.submit(
                                    get_ai_response_openai, conversation).result(timeout=40)
                            except concurrent.futures.TimeoutError:
                                pass
                    else:
                        response_data = {
                            'error': f"{data['ai']} ai does not exist"
                        }
                        print( f"{data['ai']} ai does not exist")
                        return JsonResponse(response_data, status=200) 
                else:
                    with concurrent.futures.ThreadPoolExecutor() as executor:
                        ai_output = "Timed out please try again"
                        try:
                            ai_output = executor.submit(
                                get_ai_response_openai, conversation).result(timeout=40)
                        except concurrent.futures.TimeoutError:
                            pass
                response_data = {
                    'answer': ai_output,
                }
                print("Response sent.", response_data)
                return JsonResponse(response_data)
            else:
                response_data = {
                    'error': '"model_role", "user_message" are required in the JSON data.'
                }
                print("Invalid JSON data: Missing required fields.")
                return JsonResponse(response_data, status=200)
        except json.JSONDecodeError:
            response_data = {
                'error': 'Invalid JSON data'
            }
            print("Invalid JSON data: JSON decoding error.")
            return JsonResponse(response_data, status=200)
        except Exception as e:
            response_data = {
                'error': f'An unexpected error occurred: {str(e)}'
            }
            print(f"Unexpected error: {str(e)}")
            return JsonResponse(response_data, status=200)
    else:
        response_data = {
            'error': 'Invalid request method'
        }
        print("Invalid request method: Must be a POST request.")
        return JsonResponse(response_data, status=200)


def get_ai_response_openai(conversation):
    print("Received a request by openai to get AI response.")
    try:
        completion = openai.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=conversation
        )
        response_text = completion.choices[0].message.content
        # response_text = "hi how can i help you.."
        # time.sleep(12)
        # response_text = "hi how can i help you.."
        print("AI response received.")
        return response_text
    except Exception as e:
        print(f"OpenAI API error: {str(e)}")
        return get_ai_response_google(conversation)


def get_ai_response_google(conversation):
    print("Received a request by google to get AI response.")
    try:
        text = f"{conversation[0]['content']}\n{conversation[1]['content']}"
        print(text)
        model = genai.GenerativeModel('gemini-pro')
        response = model.generate_content(text)
        response_text = response.text
        print("AI response received.")
        return response_text
    except Exception as e:
        response_data = {
            'error': f'OpenAI API error: {str(e)}'
        }
        print(f"OpenAI API error: {str(e)}")
        return response_data