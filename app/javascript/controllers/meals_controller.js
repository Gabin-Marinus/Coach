import { Controller } from "@hotwired/stimulus"

// Today's meals: toggles "undo mode", which shows an "Undo this meal" button on eaten meals.
// Marking a meal as eaten or undoing it is a real form submit (saved on the meal).
export default class extends Controller {
  toggleUndo() {
    this.element.classList.toggle("is-undoing")
  }
}
