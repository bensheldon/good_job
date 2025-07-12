export default function documentReady(callback) {
  window.document.addEventListener("turbo:load", callback);
}
