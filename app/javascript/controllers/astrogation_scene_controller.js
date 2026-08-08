import { Controller } from "@hotwired/stimulus"

const VIEWBOX_CENTER = 50
const INITIAL_SCALE = 0.05
const MIN_SCALE = 0.008
const MAX_SCALE = 0.5
const ZOOM_FACTOR = 1.2
const LABEL_GAP_PX = 4
const SVG_NAMESPACE = "http://www.w3.org/2000/svg"

export default class extends Controller {
  static targets = ["viewport", "world", "labels", "status"]

  connect() {
    this.entities = JSON.parse(this.element.dataset.astrogationEntities)
    this.transits = this.parseTransits(this.element.dataset.astrogationTransits)
    this.ship = this.entities.find((entity) => entity.kind === "ship")
    this.scale = INITIAL_SCALE
    this.center = { x: this.ship.x, y: this.ship.y }
    this.drag = null

    this.onPointerDown = this.pointerDown.bind(this)
    this.onPointerMove = this.pointerMove.bind(this)
    this.onPointerUp = this.pointerUp.bind(this)
    this.onWheel = this.wheel.bind(this)
    this.onResize = this.render.bind(this)

    this.viewportTarget.addEventListener("pointerdown", this.onPointerDown)
    this.viewportTarget.addEventListener("pointermove", this.onPointerMove)
    this.viewportTarget.addEventListener("pointerup", this.onPointerUp)
    this.viewportTarget.addEventListener("pointercancel", this.onPointerUp)
    this.viewportTarget.addEventListener("wheel", this.onWheel, { passive: false })
    window.addEventListener("resize", this.onResize)

    if (window.ResizeObserver) {
      this.resizeObserver = new ResizeObserver(this.onResize)
      this.resizeObserver.observe(this.viewportTarget)
    }

    this.render()
  }

  disconnect() {
    this.viewportTarget.removeEventListener("pointerdown", this.onPointerDown)
    this.viewportTarget.removeEventListener("pointermove", this.onPointerMove)
    this.viewportTarget.removeEventListener("pointerup", this.onPointerUp)
    this.viewportTarget.removeEventListener("pointercancel", this.onPointerUp)
    this.viewportTarget.removeEventListener("wheel", this.onWheel)
    window.removeEventListener("resize", this.onResize)
    this.resizeObserver?.disconnect()
  }

  zoomIn() {
    this.setScale(this.scale * ZOOM_FACTOR)
  }

  zoomOut() {
    this.setScale(this.scale / ZOOM_FACTOR)
  }

  recenter() {
    this.center = { x: this.ship.x, y: this.ship.y }
    this.render()
  }

  pointerDown(event) {
    if (event.button !== 0) return

    this.drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
    this.viewportTarget.setPointerCapture(event.pointerId)
    this.viewportTarget.dataset.dragging = "true"
  }

  pointerMove(event) {
    if (!this.drag || event.pointerId !== this.drag.pointerId) return

    const last = this.drag
    this.drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY }
    const unitsPerPixel = 100 / (Math.min(this.viewportTarget.clientWidth, this.viewportTarget.clientHeight) * this.scale)
    this.center.x = this.clampCenter(this.center.x - (event.clientX - last.x) * unitsPerPixel, "x")
    this.center.y = this.clampCenter(this.center.y - (event.clientY - last.y) * unitsPerPixel, "y")
    this.render()
  }

  pointerUp(event) {
    if (!this.drag || event.pointerId !== this.drag.pointerId) return

    if (this.viewportTarget.hasPointerCapture(event.pointerId)) {
      this.viewportTarget.releasePointerCapture(event.pointerId)
    }
    this.drag = null
    delete this.viewportTarget.dataset.dragging
  }

  wheel(event) {
    event.preventDefault()
    this.setScale(this.scale * (event.deltaY < 0 ? ZOOM_FACTOR : 1 / ZOOM_FACTOR))
  }

  setScale(scale) {
    this.scale = Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale))
    this.center.x = this.clampCenter(this.center.x, "x")
    this.center.y = this.clampCenter(this.center.y, "y")
    this.render()
  }

  clampCenter(value, axis) {
    const coordinates = this.entities.map((entity) => entity[axis])
    const viewportHalf = VIEWBOX_CENTER / this.scale
    const minimum = Math.min(...coordinates) - viewportHalf
    const maximum = Math.max(...coordinates) + viewportHalf
    return Math.min(maximum, Math.max(minimum, value))
  }

  render() {
    if (!this.worldTarget) return

    this.worldTarget.setAttribute(
      "transform",
      `translate(${VIEWBOX_CENTER} ${VIEWBOX_CENTER}) scale(${this.scale}) translate(${-this.center.x} ${-this.center.y})`
    )
    this.renderTransits()

    const markers = new Map(
      [...this.worldTarget.querySelectorAll("[data-astrogation-marker]")].map((marker) => [
        marker.dataset.astrogationMarker,
        marker
      ])
    )

    this.labelsTarget.querySelectorAll("[data-astrogation-label]").forEach((label) => {
      const entity = this.entities.find((candidate) => candidate.name === label.dataset.astrogationLabel)
      const marker = markers.get(label.dataset.astrogationLabel)
      if (!entity || !marker) return

      const x = VIEWBOX_CENTER + (entity.x - this.center.x) * this.scale
      const y = VIEWBOX_CENTER + (entity.y - this.center.y) * this.scale
      label.setAttribute("transform", `translate(${x} ${y})`)

      const labelText = label.querySelector("text")
      const labelBottom = labelText.getBoundingClientRect().bottom
      const markerTop = marker.getBoundingClientRect().top
      const pixelsPerSvgUnit = Math.abs(label.getScreenCTM().d)
      const yOffset = (markerTop - LABEL_GAP_PX - labelBottom) / pixelsPerSvgUnit

      label.setAttribute("transform", `translate(${x} ${y + yOffset})`)
    })

    this.element.dataset.astrogationScale = this.scale
    this.element.dataset.astrogationCenterX = this.center.x
    this.element.dataset.astrogationCenterY = this.center.y
    this.statusTarget.textContent = `Zoom ${this.scale.toFixed(3)}. Center ${this.center.x.toFixed(1)}, ${this.center.y.toFixed(1)}.`
  }

  parseTransits(value) {
    try {
      const transits = JSON.parse(value)
      if (!Array.isArray(transits)) throw new Error("transits must be an array")

      return transits
    } catch (error) {
      console.log("Unable to parse astrogation transits", error)
      return []
    }
  }

  renderTransits() {
    const layer = this.worldTarget.querySelector("[data-astrogation-transit-layer]")
    if (!layer) return

    layer.replaceChildren()
    this.transits.forEach((transit, index) => {
      const coordinates = this.usableTransitCoordinates(transit)
      if (!coordinates) {
        console.log("Skipping invalid astrogation transit", transit)
        return
      }

      const line = document.createElementNS(SVG_NAMESPACE, "line")
      line.classList.add("astrogation-transit")
      line.dataset.astrogationTransit = index
      line.setAttribute("x1", coordinates.start.x)
      line.setAttribute("y1", coordinates.start.y)
      line.setAttribute("x2", coordinates.target.x)
      line.setAttribute("y2", coordinates.target.y)
      line.setAttribute("marker-end", "url(#astrogation-transit-arrowhead)")
      layer.appendChild(line)
    })
  }

  usableTransitCoordinates(transit) {
    const start = transit?.celestial_coordinates_start
    const target = transit?.celestial_coordinates_target
    if (!this.usableCoordinate(start) || !this.usableCoordinate(target)) return null
    if (start.x === target.x && start.y === target.y) return null

    return { start, target }
  }

  usableCoordinate(coordinate) {
    return coordinate && typeof coordinate === "object" && !Array.isArray(coordinate) &&
      Number.isFinite(coordinate.x) && Number.isFinite(coordinate.y)
  }
}
