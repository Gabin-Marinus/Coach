import { Controller } from "@hotwired/stimulus"

// Budget suggestion buttons fill in the amount and period fields
export default class extends Controller {
  static targets = ["amount", "period"]

  pick({ params: { amount, period } }) {
    this.amountTarget.value = amount
    this.periodTarget.value = period
    this.amountTarget.focus()
  }
}
