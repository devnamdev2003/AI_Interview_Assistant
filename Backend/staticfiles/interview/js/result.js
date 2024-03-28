function get_ai_response(mess, role = "you are a helpful assistant") {
  const endpoint = "/api";
  const requestData = {
    model_role: role,
    user_message: mess,
    ai: "google",
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
      document.getElementById("main_content").style.display = "block";
      document.getElementById("loader").style.display = "none";
      return data.answer;
    })
    .catch((error) => {
      console.error("There was a problem with the fetch operation:", error);
      throw error;
    });
}

let role =
  "As the interviewer, your role is to analyze the candidate's interview answers and generate a score out of 100 based on the quality of their responses. Additionally, you should provide feedback for each answer to help the candidate understand areas of strength and areas for improvement.";

const urlParams = new URLSearchParams(window.location.search);
const dataParam = urlParams.get("data");
const interviewDataParam = urlParams.get("interviewData");
const QA = JSON.parse(dataParam);
const interviewData = JSON.parse(interviewDataParam);

function generate_feedback() {
  document.getElementById("main_content").style.display = "none";
  document.getElementById("loader").style.display = "block";
  let ai_answer = "";
  user_message = `${JSON.stringify(interviewData)}\n\n${JSON.stringify(
    QA
  )}\n\ngenrate your answer out of 100 and give the feedback`;
  const aiResponsePromise = get_ai_response(user_message, role);
  aiResponsePromise
    .then((answer) => {
      ai_answer = answer;
      console.log(ai_answer);
      document.getElementById("ai_response").innerHTML =
        marked.parse(ai_answer);
    })
    .catch((error) => {
      console.error("Error:", error);
    });
}

let generate_result = document.getElementById("generate_feedback");
let start_again = document.getElementById("start_again");

generate_result.addEventListener("click", () => {
  generate_feedback();
  generate_result.style.display = "none";
  start_again.style.display = "block";
});

// Function to display interview details
function displayInterviewDetails() {
  if (interviewData) {
    document.getElementById("name").innerText = interviewData.name;
    document.getElementById("jobRole").innerText = interviewData.jobRole;
    document.getElementById("interviewType").innerText =
      interviewData.interviewType;
    document.getElementById("experience").innerText = interviewData.experience;
    generate_result.style.display = "block";
  } else {
    document.getElementById("errorMessage").style.display = "block";
    start_again.style.display = "block";
  }
}

// Function to display questions and answers
function displayQA() {
  const list = document.getElementById("qaList");
  if (QA && QA.length > 0) {
    QA.forEach((item) => {
      const listItem = document.createElement("li");
      listItem.classList.add("list-group-item");
      listItem.innerHTML = `<strong>Question:</strong> ${item.question}<br><strong>Answer:</strong> ${item.answer}`;
      list.appendChild(listItem);
      generate_result.style.display = "block";
    });
  } else {
    document.getElementById("errorMessage").style.display = "block";
    start_again.style.display = "block";
  }
}

// Call the displayInterviewDetails and displayQA functions when the page loads
window.onload = function () {
  displayQA();
  displayInterviewDetails();
};
