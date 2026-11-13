// What classeur's licence is to the toolkit's licence package (gt:licence, docs/licence.md): its name in the
// licences, what their signatures cover, their file, the editions, and the public halves of its keys. The program
// checks with it (src/licence.odin), classeurtool issues and checks with it (its licence command), and the shop's
// Worker is set from the same values.
package classeur_licence

import licence "gt:licence"

// The public key is empty until the maintainer makes the pair (`classeurtool licence keygen`): no licence of the shop
// is accepted before. The development pair is public on purpose: its private half is classeurtool's DEV_SEED, for the
// tests and the shop's sandbox, and only a debug build accepts it.
PRODUCT :: licence.Product{
	name           = "classeur",
	title          = "classeur",
	version_tag    = "CLASSEUR1",
	sign_context   = "classeur-licence-v1\n",
	file_extension = ".classeurlicence",
	public_key     = "",
	dev_public_key = "E2W_yH5ujOtduTE-7wHGjNJbbf7XVqi5MGi20IJA5nQ",
	editions       = {0 = {id = "supporter", title = "Supporter"}},
}
