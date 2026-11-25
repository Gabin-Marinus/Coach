import { Controller } from "@hotwired/stimulus"

// Flips a card to show its back side (used by the Today's workout widget)
export default class extends Controller {
  flip() {
    this.element.classList.toggle("is-flipped")
  }
}
