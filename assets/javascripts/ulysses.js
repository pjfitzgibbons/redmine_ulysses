// The pages the plugin works on import this module (lib/redmine_ulysses/hooks.rb). Turbo Drive
// stays off there, so core's
// links and forms navigate as they always have; Turbo acts only on elements that opt in with
// data-turbo="true" and inside turbo-frame elements.
import { session } from "@hotwired/turbo"

session.drive = false

// Turning Drive off leaves Turbo's history running (Turbo 8.0.23): its popstate listener answers
// Back and Forward over a fragment link with a restoration visit, which replaces the body and
// loses unsaved edits, and once the page loads it sets history.scrollRestoration to "manual".
// The browser keeps both. Frames and streams don't use Turbo's history unless a frame advances
// the URL, which the plugin's frames don't.
session.history.stop()
session.history.assumeControlOfScrollRestoration = () => {}
