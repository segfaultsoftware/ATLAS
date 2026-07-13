import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  spin() {
    this.element.classList.remove("is-spinning")
    this.element.offsetHeight
    this.element.classList.add("is-spinning")
  }

  reset() {
    this.element.classList.remove("is-spinning")
  }
}
