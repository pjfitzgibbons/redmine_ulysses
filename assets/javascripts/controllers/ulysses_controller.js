import { Controller } from "@hotwired/stimulus"

// The plugin's root on the issue page. It does nothing yet but say it has connected.
export default class extends Controller {
  connect() {
    this.element.dataset.ulyssesConnected = "true"
  }
}
