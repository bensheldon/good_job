function showToasts() {
  const toasts = document.querySelectorAll('.toast');

  for (let i = 0; i < toasts.length; i++) {
    var toast = new bootstrap.Toast(toasts[i])
    toast.show()
  }
}

function setupPopovers() {
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
    new bootstrap.Popover(el, {
      template: '<div class="popover" role="tooltip"><div class="popover-arrow"></div><h3 class="popover-header"></h3><pre class="popover-body text-wrap text-break"></pre></div>'
    })
  })
}

window.document.addEventListener("turbo:load", function() {
  showToasts();
  setupPopovers();
});
