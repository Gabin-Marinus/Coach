import { Controller } from "@hotwired/stimulus"

// Gym users get all equipment, so only ask everyone else
export default class extends Controller {
  static targets = ["equipment"]

  connect() {
    this.toggle()
  }

  toggle() {
    const location = this.element.querySelector("select[name='user[training_location]']").value
    this.equipmentTarget.hidden = location === "" || location === "gym"
  }
}
