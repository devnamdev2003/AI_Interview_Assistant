import google.generativeai as genai
import time

# Configure API key
genai.configure(api_key='AIzaSyAh3I-bct06ZzZCA2_Jl0vVyR-ZZNqv5Ok')
# import typing_extensions as typing
# import google.generativeai as genai
# import json


# genai.configure(api_key='AIzaSyAh3I-bct06ZzZCA2_Jl0vVyR-ZZNqv5Ok')

# class InterviewResponse(typing.TypedDict):
#     feedback: str
#     next_question: str

# model = genai.GenerativeModel("gemini-1.5-pro-latest")
# result = model.generate_content(
#     "Provide constructive feedback on a candidate's job interview answer and ask a follow-up question.",
#     generation_config=genai.GenerationConfig(
#         response_mime_type="application/json", response_schema=InterviewResponse
#     ),
# )
# print(result.text)
# # Parse and format the JSON output
# text = json.loads(result.text)
# print(json.dumps(text, indent=4))

class AIResponse:
    def __init__(self, prompt=""):
        self.prompt = prompt.strip()
        try:
            self.model = genai.GenerativeModel("gemini-1.5-flash")
        except Exception as e:
            print(f"Error initializing model: {e}")
            self.model = None

    def generate_text(self):
        """Generates a response based on the given prompt."""
        if not self.model:
            return "Model not initialized."

        try:
            response = self.model.generate_content(self.prompt)
            return response.text
        except Exception as e:
            return f"Error generating text: {e}"

    def interactive_chat(self):
        if not self.model:
            return "Model not initialized."
        try:
            chat = self.model.start_chat(
                history=[
                    {"role": "user", "parts": "you give not answer more than 50 words"},
                    {"role": "model", "parts": "okay"},
                ]
            )
            while True:
                user_input = input(
                    "Enter your message (type 'exit' to quit): ")
                if user_input == "exit":
                    break
                response = chat.send_message(user_input)
                print(response.text)
                print("*" * 60)

        except Exception as e:
            return f"Error generating text: {e}"

    def interactive_interview(self, instuction):
        if not self.model:
            return "Model not initialized."
        try:
            chat = self.model.start_chat(
                history=[
                    {"role": "user", "parts": """You are an AI Interviewer conducting a realistic job interview. Please analyze my previous answer carefully, provide constructive feedback, and then generate a new question based on my response. I want the feedback to be insightful, covering both strengths and improvement areas as an interviewer would.
                    interview instructions: 
                    job role = software engineer
                    experiences = 1 year software development experience, 2 years web development experience, 1 year machine learning experience 
                    Provide your response in the following JSON format:
                    {
                        "feedback": "Provide detailed feedback on my previous question's answer, focusing on strengths and areas for improvement.",
                        "next_question": "Ask a follow-up question or a related question that would come naturally in a real interview."
                    }
                    """},
                    {"role": "model", "parts": "okay"},
                ]
            )
            #  for start interview
            response = chat.send_message("give me first question")
            print(response.text)
            while True:
                user_input = input(
                    "give answer  (type 'exit' to quit): ")
                if user_input == "exit":
                    break
                response = chat.send_message(user_input)
                print(response.text)
                print("*" * 60)

        except Exception as e:
            return f"Error generating text: {e}"

    def structured_output(self, prompt="", schema={}):
        try:
            model = genai.GenerativeModel("gemini-1.5-pro-latest")
            prompt = """List a few popular cookie recipes in JSON format.

            Use this JSON schema:

            Recipe = {'recipe_name': str, 'ingredients': list[str]}
            Return: list[Recipe]"""
            result = model.generate_content(prompt)
            print(result.text)
        except Exception as e:
            return f"Error generating text: {e}"


def main():
    obj = AIResponse("hi")
    print(obj.interactive_interview("hi"))


if __name__ == "__main__":
    main()
