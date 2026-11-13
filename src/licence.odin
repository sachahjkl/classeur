package classeur

// classeur's licence (gui_toolkit's gt:licence, docs/licence.md): a key signed by the shop, checked here with no
// network. A licence changes nothing of what classeur does: it says who supports it. The settings show it on the
// toolkit's Licence page (prefs_page.Licence): its state, Buy a licence, a key to paste, a file to choose, Remove. Every
// read and write of its file is one of the page's tasks (the store blocks on the disk).

import prefs_page "gt:prefs_page"
import classeur_licence "licence"

// classeur's licence: src/licence/product.odin (the tool's too).
LICENCE :: classeur_licence.PRODUCT

// Where a licence is bought: the site's pricing page.
LICENCE_PRICING_URL :: SITE_URL + "pricing/"

licence_open :: proc(app: ^App) {
	// (the tests keep it in memory: the person's folder is never touched)
	prefs_page.licence_init(&app.licence, &app.main.state, {
		store = {product = LICENCE, program = APP_NAME, memory = app.headless, accept_dev = ODIN_DEBUG},
		name = "Classeur", pricing_url = LICENCE_PRICING_URL, owner = app.main.win,
	})
}

// After the chores have stopped: no task holds the store any more.
licence_close :: proc(app: ^App) { prefs_page.licence_end(&app.licence) }
