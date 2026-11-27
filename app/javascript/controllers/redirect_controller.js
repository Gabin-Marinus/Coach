import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Goes to another page shortly after this element appears, e.g. to the plan once it is saved
// (the "Plan #1 is ready" box is broadcast by PlanGenerationJob). The link in the box works too.
export default class extends Controller {
  static values = { url: String, delay: { type: Number, default: 1500 } }

  connect() {
    this.timer = setTimeout(() => Turbo.visit(this.urlValue), this.delayValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
