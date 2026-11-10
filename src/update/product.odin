// What classeur is to the toolkit's update package (gt:update, docs/update.md): its name in the manifests and the
// release's file names, what its signatures cover, and the public half of its update key (classeurtool update keygen; the
// private half is the release workflow's secret UPDATE_SIGNING_KEY). The program checks with it (updates.odin),
// classeurtool signs with it (classeurtool package).
package classeur_update

import update "gt:update"

PRODUCT :: update.Product{
	name         = "classeur",
	sign_context = "classeur-update-v1\n",
	public_key   = "vkMGa5whMb_TgTOILT9yn5cHAbqIs5rLQkeflWyu3R8",
}
