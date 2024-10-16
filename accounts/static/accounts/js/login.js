function validateForm() {
    var username_email = document.getElementById('username_email').value
    var password = document.getElementById('password').value
  
    if (username_email.trim() === '') {
      alert('Please enter your username_email.')
      return false
    }
  
    if (password.trim() === '') {
      alert('Please enter your password.')
      return false
    }
    return true
  }
  if (window.history.replaceState) {
    window.history.replaceState(null, null, window.location.href)
  }