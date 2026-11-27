import { Controller } from "@hotwired/stimulus"

// Follows the coach's answer while it streams in: keeps the newest text in view,
// unless the user scrolled up to read something (then it leaves them alone)
export default class extends Controller {
  connect() {
    this.observer = new MutationObserver(() => this.scroll())
    this.observer.observe(this.element, { childList: true, subtree: true, characterData: true })
  }

  disconnect() {
    this.observer.disconnect()
  }

  scroll() {
    const scrollsItself = this.element.scrollHeight > this.element.clientHeight + 1 &&
      getComputedStyle(this.element).overflowY !== "visible"

    if (scrollsItself) {
      // The coach panel: the message list has its own scrollbar
      if (this.nearBottom(this.element.scrollTop + this.element.clientHeight, this.element.scrollHeight)) {
        this.element.scrollTop = this.element.scrollHeight
      }
    } else if (this.nearBottom(window.scrollY + window.innerHeight, this.element.getBoundingClientRect().bottom + window.scrollY)) {
      // The plan chat page: the whole page scrolls
      window.scrollTo({ top: document.body.scrollHeight })
    }
  }

  // Within ~a screen of the bottom: the user is following along
  nearBottom(position, bottom) {
    return bottom - position < 400
  }
}
