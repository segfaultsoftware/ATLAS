import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "creationDisclosure",
    "creationClientError",
    "creationName",
    "creationPanel",
    "deleteDialog",
    "deleteDialogTitle",
    "status"
  ]

  connect() {
    this.deleteForm = null
    this.deleteTrigger = null
    this.restoreFocusAfterDialog = true
  }

  creationNameTargetConnected(input) {
    if (input.closest("[data-games-target='creationPanel']")?.hidden) return

    requestAnimationFrame(() => input.focus())
  }

  openCreation() {
    this.creationPanelTarget.hidden = false
    this.creationDisclosureTarget.setAttribute("aria-expanded", "true")
    this.creationNameTarget.focus()
  }

  showLoadingToast(event) {
    const name = event.currentTarget.dataset.gameName
    this.statusTarget.textContent = `Loading ${name}...`
  }

  validateCreation(event) {
    const name = this.creationNameTarget.value.trim()
    const characterCount = [...name].length

    if (characterCount < 1 || characterCount > 64) {
      event.preventDefault()
      this.creationClientErrorTarget.textContent = "Name must contain 1–64 characters after trimming."
      this.creationClientErrorTarget.hidden = false
      this.creationNameTarget.focus()
      return
    }

    this.creationNameTarget.value = name
    this.clearCreationError()
  }

  clearCreationError() {
    this.creationClientErrorTarget.textContent = ""
    this.creationClientErrorTarget.hidden = true
  }

  requestDelete(event) {
    event.preventDefault()
    event.stopPropagation()

    this.deleteTrigger = event.currentTarget
    this.deleteForm = event.currentTarget.form
    this.restoreFocusAfterDialog = true
    this.deleteDialogTitleTarget.textContent = `Delete ${event.currentTarget.dataset.gameName}?`
    this.deleteDialogTarget.showModal()
  }

  cancelDelete(event) {
    event.preventDefault()
    this.restoreFocusAfterDialog = true
    this.deleteDialogTarget.close()
  }

  confirmDelete(event) {
    event.preventDefault()

    const form = this.deleteForm
    this.restoreFocusAfterDialog = false
    this.deleteDialogTarget.close()
    this.deleteForm = null
    this.deleteTrigger = null
    form?.requestSubmit()
  }

  restoreDeleteFocus() {
    if (this.restoreFocusAfterDialog && this.deleteTrigger?.isConnected) {
      this.deleteTrigger.focus()
    }

    if (this.restoreFocusAfterDialog) {
      this.deleteForm = null
      this.deleteTrigger = null
    }
  }
}
