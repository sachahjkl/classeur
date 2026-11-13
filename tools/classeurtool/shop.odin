package classeurtool

// The shop: classeur's licence, sold through Paddle by the toolkit's licence Worker. Its six pages (pricing, thanks, terms,
// refunds, privacy, imprint) are the toolkit's templates, filled at each `site build` (Meta.shop, site.odin). Until it has
// Paddle's client token, the price id and the licence Worker's address, the buy button says "Coming soon" (docs/licence.md
// of gui_toolkit, "What the maintainer does at the end").

import tk_site "gt:site"
import classeur_licence "../../src/licence"

shop :: proc() -> tk_site.Shop {
	return {
		name           = "classeur",
		icon           = "../img/logo.png",
		product_title  = "Classeur User License",
		price          = "29&nbsp;&euro;",
		price_note     = "",
		environment    = "sandbox",
		client_token   = "",   // Paddle's client-side token: "" keeps the shop shut ("Coming soon")
		edition        = "supporter",
		price_id       = "",   // what `classeurtool paddle -apply` prints ("": not made yet)
		worker         = "",   // the licence Worker's address (licence-worker/README.md of gui_toolkit)
		thanks         = "https://classeur.froment.software/thanks/",
		help           = REPOSITORY + "/issues/new",
		register       = "Open the file with classeur, or paste the key in <strong>Settings &gt; General &gt; Licence</strong>.",
		extension      = classeur_licence.PRODUCT.file_extension,
		repository     = REPOSITORY,
		seller         = SELLER,
		code_licence   = "MIT License",
		platform       = "Linux, x64, and Windows 10 or 11, x64.",
		network        = "classeur connects to the network for its updates only: the installed copy asks GitHub for the latest release a while after it starts and then once a day, and puts an update in place only if it is signed by Froment Software. Another copy asks only when you press <em>Check now</em> in the settings.",
		stylesheet     = "../style.css",
		home           = "../",
		updated        = "2026-11-13",
	}
}

// The seller, as Wren's imprint names it: the same block in every program of Froment Software.
SELLER :: tk_site.Seller{
	name       = "Froment Software",
	owner      = "Sacha Froment",
	status     = "sole proprietor (<em>entrepreneur individuel</em>)",
	address    = "7 Lieu-dit les Renardi&egrave;res, 72220 Marign&eacute;-Laill&eacute;, France",
	email      = "contact@froment.software",
	url        = "https://froment.software",
	siren      = "131 941 718",
	siret      = "131 941 718 00010",
	ape        = "6201Z, computer programming",
	registry   = "the French national register of companies (RNE)",
	registered = "23 October 2026",
	vat        = "not applicable, article 293 B of the French General Tax Code (<em>franchise en base de TVA</em>)",
}
