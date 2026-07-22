import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary"]

  close() {
    this.element.open = false
    this.syncExpanded()
  }

  closeWhenFocusLeaves(event) {
    if (this.element.contains(event.relatedTarget)) return

    this.close()
  }

  syncExpanded() {
    this.summaryTarget.setAttribute("aria-expanded", this.element.open ? "true" : "false")
  }
}
