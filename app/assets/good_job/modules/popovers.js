export default function() {
  document.querySelectorAll('[data-bs-toggle="popover"]').forEach((el) => {
    new bootstrap.Popover(el, { html: true })
  })
}
