package classeurtool

// shop: the six pages of classeur's shop (pricing, thanks, terms, refunds, privacy, imprint) written into site/ from
// shop(), the toolkit's template pages filled (gt:site licence_pages). They are files of the site's sources, published as
// they are by `site build`; run it again when shop() changes. Until it has Paddle's client token, the price ids and the
// licence Worker's address, the buy button says "Coming soon" (docs/licence.md of gui_toolkit, "What the maintainer does
// at the end").

import "core:fmt"
import "core:os"
import "core:strings"
import tk_site "gt:site"
import classeur_licence "../../src/licence"

// The prices of the buttons: the price ids are what `classeurtool paddle -apply` prints ("": not made yet).
@(rodata)
SHOP_PRICES := [?]tk_site.Shop_Price{
	{edition = "supporter", price_id = "", label = "Buy the licence"},
}

shop :: proc() -> tk_site.Shop {
	return {
		name           = "classeur",
		product_title  = "Classeur Licence",
		price          = "29&nbsp;&euro;",
		price_note     = "Once. Taxes included.",
		environment    = "sandbox",
		client_token   = "",   // Paddle's client-side token: "" keeps the shop shut ("Coming soon")
		prices         = SHOP_PRICES[:],
		worker         = "",   // the licence Worker's address (licence-worker/README.md of gui_toolkit)
		thanks         = "https://classeur.froment.software/thanks/",
		help           = "mailto:contact@froment.software",
		register       = "Open the file with classeur, or paste the key in <strong>Settings &gt; General &gt; Licence</strong>.",
		extension      = classeur_licence.PRODUCT.file_extension,
		seller         = "Froment Software",
		seller_url     = "https://froment.software",
		seller_address = "the trade name of Sacha Froment, sole proprietor (<em>entrepreneur individuel</em>)<br>7 Lieu-dit les Renardi&egrave;res, 72220 Marign&eacute;-Laill&eacute;, France",
		seller_email   = "contact@froment.software",
		code_licence   = "MIT",
		stylesheet     = "../style.css",
		home           = "../",
		updated        = "2026-11-13",
	}
}

run_shop :: proc(args: []string) -> int {
	for p in tk_site.licence_pages(shop()) {
		path := fmt.tprintf("site/%s", p.path)
		_ = os.make_directory_all(path[:strings.last_index_byte(path, '/')])   // (there already, or the write says it)
		if err := os.write_entire_file(path, transmute([]u8)p.text); err != nil {
			fmt.eprintfln("classeurtool shop: %s cannot be written", path)
			return 1
		}
		fmt.printfln("wrote %s", path)
	}
	return 0
}
