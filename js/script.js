let jobRole = ""
let interviewType = ""
let experience = ""
let role = "You are the interviewer, and you will ask a one questions based on the proposed job role, experience level, and type of interview.";
let user_message = "";
let ai_question = ""

function get_ai_response(mess, role = "you are a helpful assistant") {
    const endpoint = "https://chatgptapi-2pc2.onrender.com/";
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
    startCameraButton.click();
    jobRole = document.getElementById("jobRole").value;
    interviewType = document.getElementById('interviewType').value;
    experience = document.getElementById('experience').value;
    user_message = `Job role: ${jobRole}\nInterview type: ${interviewType}\nExperience: ${experience}`
    console.log(user_message);
    const aiResponsePromise = get_ai_response(user_message, role);
    console.log(aiResponsePromise);
    aiResponsePromise
        .then((answer) => {
            ai_question = answer
            document.getElementById("displayQuestion").textContent = answer;
            document.getElementById("displayInterviewQuestion").style.display =
                "block";
            console.log(ai_question);
            const speechSynthesis = window.speechSynthesis;
            const utterance = new SpeechSynthesisUtterance(answer);
            speechSynthesis.speak(utterance);
        })
        .catch((error) => {
            console.error("Error:", error);
        });
}

const startCameraButton = document.getElementById("startCamera");
const stopCameraButton = document.getElementById("stopCamera");
const startRecordingButton = document.getElementById("startRecording");
const stopRecordingButton = document.getElementById("stopRecording");
const outputDiv = document.getElementById("output");
const outputDiv_v = document.getElementById("output_v");
const videoElement = document.getElementById("videoElement");
const delbtn = document.getElementById("delbtn");
const nextbtn = document.getElementById("nextquestion");
window.SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const recognition = new SpeechRecognition();
recognition.interimResults = true;
recognition.continuous = true;
let result = "";
let mediaStream;
let mediaRecorder;
let chunks = [];

startCameraButton.addEventListener("click", async () => {
    outputDiv.innerHTML = "";
    outputDiv_v.innerHTML = "";
    outputDiv_v.style.display = "none";

    delbtn.style.display = "none";
    nextbtn.style.display = "none";
    try {
        mediaStream = await navigator.mediaDevices.getUserMedia({
            video: true,
            audio: false,
        });
        videoElement.srcObject = mediaStream;
        videoElement.style.display = "block";
        startRecordingButton.disabled = false;
        stopCameraButton.disabled = false;
        startCameraButton.disabled = true;
    } catch (error) {
        console.error("Error accessing camera:", error);
    }
});

stopCameraButton.addEventListener("click", () => {
    if (mediaStream) {
        mediaStream.getTracks().forEach((track) => track.stop());
        videoElement.srcObject = null;
        videoElement.style.display = "none";
        startRecordingButton.disabled = true;
        stopRecordingButton.disabled = true;
        stopCameraButton.disabled = true;
        startCameraButton.disabled = false;
    }
});

startRecordingButton.addEventListener("click", () => {
    outputDiv_v.style.display = "none";
    result = "";
    navigator.mediaDevices
        .getUserMedia({ video: true, audio: true })
        .then((stream) => {
            recognition.start();
            mediaStream = stream;
            mediaRecorder = new MediaRecorder(mediaStream);
            mediaRecorder.ondataavailable = (event) => {
                chunks.push(event.data);
            };
            mediaRecorder.onstop = () => {
                const blob_v = new Blob(chunks, { type: "video/webm" });
                const videoURL = URL.createObjectURL(blob_v);
                const videoElement = document.createElement("video");
                videoElement.src = videoURL;
                videoElement.controls = true;
                outputDiv_v.innerHTML = "";
                outputDiv_v.appendChild(videoElement);
                chunks = [];
            };
            mediaRecorder.start();
            startRecordingButton.disabled = true;
            stopCameraButton.disabled = true;
            stopRecordingButton.disabled = false;
        })
        .catch((error) => {
            console.error("Error accessing microphone:", error);
        });
});
recognition.addEventListener("result", (e) => {
    const text = Array.from(e.results)
        .map((result) => result[0])
        .map((result) => result.transcript)
        .join("");
    outputDiv.innerText = text;
});

recognition.onerror = (event) => {
    console.log("Error occurred in recognition: " + event.error);
};

stopRecordingButton.addEventListener("click", () => {
    recognition.stop();
    result = outputDiv.innerText;
    if (mediaRecorder && mediaRecorder.state !== "inactive") {
        mediaRecorder.stop();
    }
    delbtn.style.display = "block";
    outputDiv_v.style.display = "block";
    nextbtn.style.display = "block";
    if (mediaStream) {
        mediaStream.getTracks().forEach((track) => track.stop());
        videoElement.srcObject = null;
        videoElement.style.display = "none";
    }
    mediaStream = null;
    startRecordingButton.disabled = true;
    stopCameraButton.disabled = true;
    stopRecordingButton.disabled = true;
    startCameraButton.disabled = false;
});

function try_again() {
    startCameraButton.click();
    outputDiv.innerHTML = "";
    outputDiv_v.innerHTML = "";
    delbtn.style.display = "none";
    nextbtn.style.display = "none";
}


function next_question() {
    outputDiv.innerHTML = "";
    outputDiv_v.innerHTML = "";
    delbtn.style.display = "none";
    nextbtn.style.display = "none";
    startCameraButton.click();
    ai_question = ai_question.includes(":") ? ai_question.split(':')[1] : ai_question
    user_message = `Job role: ${jobRole}\nInterview type: ${interviewType}\nExperience: ${experience}\nPrevious Question: ${ai_question}\nInterviewer's answer to previous question: ${result}\n\nNow ask the next question as per your choice and continue the conversation. `;
    console.log(user_message);
    const aiResponsePromise = get_ai_response(user_message, role);
    console.log(aiResponsePromise);
    aiResponsePromise
        .then((answer) => {
            ai_question = answer
            document.getElementById("displayQuestion").textContent = answer;
            document.getElementById("displayInterviewQuestion").style.display =
                "block";
            console.log(ai_question);
            const speechSynthesis = window.speechSynthesis;
            const utterance = new SpeechSynthesisUtterance(answer);
            speechSynthesis.speak(utterance);
        })
        .catch((error) => {
            console.error("Error:", error);
        });
}