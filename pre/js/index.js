$(document).ready(function () {
    $('#interviewForm').submit(function (event) {
        event.preventDefault();

        // Validation
        if (!this.checkValidity()) {
            event.stopPropagation();
            return;
        }

        var name = $('#name').val();
        var jobRole = $('#jobRole').val();
        var interviewType = $('#interviewType').val();
        var experience = $('#experience').val();

        // Redirect to interview details page with form data as URL parameters
        window.location.href = 'main.html?name=' + encodeURIComponent(name) +
            '&jobRole=' + encodeURIComponent(jobRole) +
            '&interviewType=' + encodeURIComponent(interviewType) +
            '&experience=' + encodeURIComponent(experience);
    });
});
const payloadData = {
    model_role: "helpful assistant",
    user_message: "hi",
};
fetch('https://chatgptapi-2pc2.onrender.com', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/json'
    },
    body: JSON.stringify(payloadData)
})
    .then(response => response.json())
    .then(data => {
        console.log(data);
        if (data.answer) {
            document.querySelector('.content').style.display = 'block';
            document.getElementById('loader').style.display = 'none';
        } else {
            console.log('HTML page loading not required.');
        }
    })
    .catch(error => {
        console.error('Error:', error);
    });