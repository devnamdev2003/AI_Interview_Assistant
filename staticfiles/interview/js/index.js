$(document).ready(function () {
  $("#interviewForm").submit(function (event) {
    event.preventDefault();

    // Validation
    if (!this.checkValidity()) {
      event.stopPropagation();
      return;
    }

    var name = $("#name").val();
    var jobRole = $("#jobRole").val();
    var interviewType = $("#interviewType").val();
    var experience = $("#experience").val();

    window.location.href =
      "main.html?name=" +
      encodeURIComponent(name) +
      "&jobRole=" +
      encodeURIComponent(jobRole) +
      "&interviewType=" +
      encodeURIComponent(interviewType) +
      "&experience=" +
      encodeURIComponent(experience);
  });
});
fetch("/api", {
  method: "GET",
  headers: {
    "Content-Type": "application/json",
  },
})
  .then((response) => response.json())
  .then((data) => {
    console.log(data);
    if (data) {
      document.querySelector(".content").style.display = "block";
      document.getElementById("loader").style.display = "none";
    } else {
      console.log("HTML page loading not required.");
    }
  })
  .catch((error) => {
    console.error("Error:", error);
  });
