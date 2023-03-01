/*jshint esversion: 6, strict: false */

// How to use:
//<form data-checkbox-toggle="{key}">
//  <input type="checkbox" data-checkbox-toggle-all="{key}" />
//
//  <input type="checkbox" data-checkbox-toggle-each="{key}" />
//  <input type="checkbox" data-checkbox-toggle-each="{key}" />
//  ...

export default function checkboxToggle() {
  document.querySelectorAll("form[data-checkbox-toggle]").forEach(function (form) {
    const keyName = form.dataset.checkboxToggle;
    const checkboxToggle = form.querySelector(`input[type=checkbox][data-checkbox-toggle-all=${keyName}]`);
    const checkboxes = form.querySelectorAll(`input[type=checkbox][data-checkbox-toggle-each=${keyName}]`);
    const showables = form.querySelectorAll(`[data-checkbox-toggle-show=${keyName}]`);

    // Check or uncheck all checkboxes
    checkboxToggle.addEventListener("change", function (event) {
      checkboxes.forEach(function (checkbox) {
        checkbox.checked = checkboxToggle.checked;
      });

      showables.forEach(function (showable) {
        showable.classList.toggle("d-none", !checkboxToggle.checked);
        showable.disabled = ! checkboxToggle.checked;
      });
    });

    // check or uncheck the "all" checkbox when all checkboxes are checked or unchecked
    form.addEventListener("change", function (event) {
      if (!event.target.matches(`input[type=checkbox][data-checkbox-toggle-each=${keyName}]`)) {
        return;
      }
      const checkedCount = Array.from(checkboxes).filter(function (checkbox) {
        return checkbox.checked;
      }).length;

      const allChecked = checkedCount === checkboxes.length;
      const indeterminateChecked = !allChecked && checkedCount > 0;

      checkboxToggle.checked = allChecked;
      checkboxToggle.indeterminate = indeterminateChecked;

      showables.forEach(function (showable) {
        showable.classList.toggle("d-none", !allChecked);
        showable.disabled = !allChecked;
      });
    });
  });
}
