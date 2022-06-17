export default function showToasts() {
  const toasts = document.querySelectorAll('.toast');

  for (let i = 0; i < toasts.length; i++) {
    var toast = new bootstrap.Toast(toasts[i])
    toast.show()
  }
}
