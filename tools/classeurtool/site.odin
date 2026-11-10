package classeurtool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are the
// toolkit's (gt:site); this file says what this site is: its address, names and colours.
//   classeurtool site build <site> <out>      the changelog's pages and the classic ones from <site>, then what a page
//                                           says when it is shared; <out> is what is published
//   classeurtool site check [--site folder] [--shot file.png] [--browser program]
//                                           the pages in a real browser, served on this machine
// {{version}} in the home page is the last version: its download link names the file of that release.

import "core:fmt"
import cdp "gt:cdp"
import tk_site "gt:site"

SITE_DIR     :: "site"
REPOSITORY   :: "https://github.com/sachahjkl/classeur"
CHANGELOG    :: "CHANGELOG.md"
VERSION_MARK :: "{{version}}"

// Where the site is published, what it is: the one place that says it.
SITE_META :: tk_site.Meta{
	url         = "https://classeur.sacha.house/",
	name        = "classeur",
	repository  = REPOSITORY,
	tagline     = "A fast file manager for Linux and Windows",
	changes     = CHANGELOG,
	card        = "img/main.png",
	logo        = "img/logo.png",
	logo_file   = "site/img/logo.png",
	theme       = "#141517",
	accent      = "#4f9de8",
	author      = "Sacha Froment",
	author_url  = "https://froment.software",
	publisher   = "Froment Software",
	ld_type     = "SoftwareApplication",
	root_domain = false,   // (github.io answers for /robots.txt and /favicon.ico, not the site)
}

SITE_LD :: [?][2]string{
	{"applicationCategory", "UtilitiesApplication"},
	{"operatingSystem", "Linux, Windows"},
	{"license", "https://opensource.org/license/mit"},
}

@(private = "file")
site_meta :: proc() -> tk_site.Meta {
	m := SITE_META
	ld := SITE_LD
	m.ld_fields = make([][2]string, len(ld), context.temp_allocator)
	copy(m.ld_fields, ld[:])
	return m
}

// The systems classeur is published for: the home page's button is the reader's (Linux when it is not known).
@(private = "file", rodata)
SITE_DOWNLOADS := [?]tk_site.Download{
	{os = "linux", label = "Linux", href = "https://github.com/sachahjkl/classeur/releases/download/v{{version}}/classeur-{{version}}-linux-x64.tar.gz", detail = "v{{version}} · x64 · .tar.gz"},
	{os = "windows", label = "Windows", href = "https://github.com/sachahjkl/classeur/releases/download/v{{version}}/classeur-{{version}}-windows-x64.zip", detail = "v{{version}} · Windows 10 / 11 · x64 · .zip"},
}

@(private = "file")
site_changelog :: proc(site, out: string) -> bool {
	return tk_site.build_changelog(site, out, {changes = CHANGELOG, version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]})
}

// A browser of each system (what it says it runs on), and the download the home page offers it: the file of the
// button, and the other system's in the line under it. A phone gets the first: whoever reads it there installs it on a
// computer.
@(private = "file")
Site_System :: struct { name, agent, platform, data, button, other: string }

@(private = "file", rodata)
SITE_SYSTEMS := [?]Site_System{
	{"Windows", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Win32", "Windows", "-windows-x64.zip", "-linux-x64.tar.gz"},
	{"Linux", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Linux x86_64", "Linux", "-linux-x64.tar.gz", "-windows-x64.zip"},
	{"Android", "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36", "Linux armv8l", "Android", "-linux-x64.tar.gz", "-windows-x64.zip"},
}

@(private = "file")
site_downloads :: proc(s: ^tk_site.Check) {
	for sys in SITE_SYSTEMS {
		tk_site.check_call(s, "Emulation.setUserAgentOverride", fmt.tprintf(`{{"userAgent":%s,"platform":%s,"userAgentMetadata":{{"platform":%s,"platformVersion":"","architecture":"x86","model":"","mobile":false}}}}`,
			cdp.quote(sys.agent), cdp.quote(sys.platform), cdp.quote(sys.data)))
		if !tk_site.check_go(s, "index.html") { continue }
		// (the button shown: the one with a box)
		button :: `[...document.querySelectorAll('.hero [data-download-os]')].find((e) => e.getClientRects().length > 0)`
		other :: `[...document.querySelectorAll('.hero [data-download-others]')].find((e) => e.getClientRects().length > 0).querySelector('a')`
		tk_site.check_expect(s, tk_site.check_true(s, fmt.tprintf(`%s.href.endsWith(%s)`, button, cdp.quote(sys.button))),
			fmt.tprintf("index.html, %s: the button is %s (%s)", sys.name, sys.button, tk_site.check_text(s, button + ".href")))
		tk_site.check_expect(s, tk_site.check_true(s, fmt.tprintf(`%s.href.endsWith(%s)`, other, cdp.quote(sys.other))),
			fmt.tprintf("index.html, %s: the other is %s (%s)", sys.name, sys.other, tk_site.check_text(s, other + ".href")))
	}
	tk_site.check_call(s, "Emulation.setUserAgentOverride", `{"userAgent":""}`)   // (the browser's own again)
}

run_site :: proc(args: []string) -> int {
	what := len(args) > 0 ? args[0] : ""
	switch what {
	case "build":
		if len(args) != 3 { break }
		if !site_changelog(args[1], args[2]) { return 1 }
		return tk_site.build_meta(site_meta(), args[2], args[2]) ? 0 : 1
	case "check":
		o := tk_site.Check_Options{site = SITE_DIR, generate = site_changelog, extra = site_downloads}
		if why := tk_site.check_arguments(args[1:], &o); why != "" { fmt.eprintfln("classeurtool site check: %s", why); return EXIT_USAGE }
		return tk_site.check(o) ? 0 : 1
	}
	fmt.eprintln("classeurtool site build <site> <out> | check [--site folder] [--shot file.png] [--browser program]")
	return EXIT_USAGE
}
