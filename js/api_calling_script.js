function get_ai_response(mess, role = "you are a helpful assistant") {
    const endpoint = "http://127.0.0.1:8000";
    const requestData = {
        model_role: role,
        user_message: mess,
    };
    const fetchOptions = {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify(requestData),
    };

    return fetch(endpoint, fetchOptions)
        .then((response) => {
            if (!response.ok) {
                throw new Error("Network response was not ok");
            }
            return response.json();
        })
        .then((data) => {
            return data.answer;
        })
        .catch((error) => {
            console.error(
                "There was a problem with the fetch operation:",
                error
            );
            throw error;
        });
}

function genrate_question() {
    jobRole = document.getElementById("jobRole").value;
    interviewType = document.getElementById('interviewType').value;
    experience = document.getElementById('experience').value;
    user_message = `Job role: ${jobRole}\nInterview type: ${interviewType}\nExperience: ${experience}`
    let role =
        "You are the interviewer, and you will ask a one questions based on the proposed job role, experience level, and type of interview.";
    console.log(user_message);
    const aiResponsePromise = get_ai_response(user_message, role);
    console.log(aiResponsePromise);
    aiResponsePromise
        .then((answer) => {
            document.getElementById("displayQuestion").textContent = answer;
            document.getElementById("displayInterviewQuestion").style.display =
                "block";
            console.log(answer);
            const speechSynthesis = window.speechSynthesis;
            const utterance = new SpeechSynthesisUtterance(answer);
            speechSynthesis.speak(utterance);
        })
        .catch((error) => {
            console.error("Error:", error);
        });
}