import { Controller } from "@hotwired/stimulus"

// Coach panel: scroll to the latest answer, send with Enter (Shift+Enter = new line)
export default class extends Controller {
  static targets = ["messages"]

  connect() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (event.target.value.trim() !== "") this.element.requestSubmit()
    }
  }
}
