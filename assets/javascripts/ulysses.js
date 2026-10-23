// The pages the plugin works on import this module (lib/redmine_ulysses/hooks.rb). Turbo Drive
// stays off there, so core's
// links and forms navigate as they always have; Turbo acts only on elements that opt in with
// data-turbo="true" and inside turbo-frame elements.
import { session } from "@hotwired/turbo"

session.drive = false
