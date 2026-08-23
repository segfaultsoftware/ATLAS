import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "age",
    "budget",
    "firstName",
    "healthInput",
    "healthOutput",
    "hire",
    "lastName",
    "nickname",
    "staminaInput",
    "staminaOutput",
    "startingBudgetInput",
    "vigorInput",
    "vigorOutput"
  ]

  static values = {
    persistedBudget: Number,
    startingBudget: Number
  }

  connect() {
    this.updateNicknamePlaceholder()
    this.refresh()
  }

  increase(event) {
    const stat = event.currentTarget.dataset.stat
    const input = this.statInput(stat)
    input.value = this.integerValue(input.value, 100) + 10
    this.refresh()
  }

  pass() {
    this.firstNameTarget.value = ""
    this.nicknameTarget.value = ""
    this.lastNameTarget.value = ""
    this.healthInputTarget.value = 100
    this.staminaInputTarget.value = 100
    this.vigorInputTarget.value = 100
    this.startingBudgetValue = this.persistedBudgetValue
    this.startingBudgetInputTarget.value = this.persistedBudgetValue
    this.updateNicknamePlaceholder()
    this.refresh()
    this.firstNameTarget.focus()
  }

  updateNicknamePlaceholder() {
    this.nicknameTarget.placeholder = this.firstNameTarget.value.trim()
  }

  refresh() {
    const stats = {
      health: this.integerValue(this.healthInputTarget.value, 100),
      stamina: this.integerValue(this.staminaInputTarget.value, 100),
      vigor: this.integerValue(this.vigorInputTarget.value, 100)
    }
    const increments = Object.values(stats).reduce((total, stat) => total + ((stat - 100) / 10), 0)
    const displayedBudget = this.startingBudgetValue - (increments * 100)

    this.healthOutputTarget.value = stats.health
    this.staminaOutputTarget.value = stats.stamina
    this.vigorOutputTarget.value = stats.vigor
    this.ageTarget.value = (16 + (increments * 0.25)).toFixed(2)
    this.budgetTarget.textContent = displayedBudget
    this.hireTarget.disabled = displayedBudget < 0
  }

  statInput(stat) {
    return {
      health: this.healthInputTarget,
      stamina: this.staminaInputTarget,
      vigor: this.vigorInputTarget
    }[stat]
  }

  integerValue(value, fallback) {
    const parsed = Number.parseInt(value, 10)
    return Number.isNaN(parsed) ? fallback : parsed
  }
}
