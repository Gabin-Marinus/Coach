import { Controller } from "@hotwired/stimulus"

// All plans page: shows checkboxes to choose which plans to delete
export default class extends Controller {
  static targets = ["checkbox", "toolbar", "actions", "deleteButton", "count"]

  // "Delete plans" button: show the checkboxes and the toolbar
  start() {
    this.element.classList.add("selecting")
    this.actionsTarget.classList.add("d-none")
    this.toolbarTarget.classList.remove("d-none")
    this.checkboxTargets.forEach((checkbox) => checkbox.classList.remove("d-none"))
  }

  // "Cancel" button: untick everything and go back to normal
  cancel() {
    this.element.classList.remove("selecting")
    this.actionsTarget.classList.remove("d-none")
    this.toolbarTarget.classList.add("d-none")
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false
      checkbox.classList.add("d-none")
    })
    this.update()
  }

  // Each time a checkbox changes: update the number of selected plans
  update() {
    const selected = this.checkboxTargets.filter((checkbox) => checkbox.checked).length

    this.countTargets.forEach((count) => (count.innerText = selected))
    this.deleteButtonTarget.disabled = selected === 0
  }
}
