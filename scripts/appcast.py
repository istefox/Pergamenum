#!/usr/bin/env python3
"""Inserisce o aggiorna un <item> nell'appcast di Sparkle e scrive il feed risultante.

ADR-0031 §D10, piano docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md.

Sparkle porta con sé `generate_appcast`, e non è usato qui. Deriva ogni URL di download
da un solo `--download-url-prefix`, mentre ogni release vive sotto il proprio tag; tratta
una cartella locale di archivi come la storia del feed, e quella cartella è `build/`, che
è gitignorata e sta su un Mac solo - un feed che dimentica il proprio passato quando un
disco viene azzerato è peggio di nessun feed; e genera delta binari, che sono un non-goal
esplicito. Di Sparkle si usa `sign_update`, che è l'unico modo di produrre la firma EdDSA.

Solo libreria standard: questo repository non ha un file di dipendenze Python dove mettere
altro, e `scripts/mcp-smoke.py` è il precedente di un helper `python3` sotto `scripts/`.

Sul parsing di XML preso dalla rete: si resta su `xml.etree.ElementTree`. `defusedxml` è un
pacchetto di terze parti e non ha dove essere dichiarato. ElementTree su Python 3 non
risolve entità esterne e rifiuta quelle non definite, quindi né XXE né billion-laughs si
applicano; in più il documento arriva in HTTPS da un repository di questo account. Un feed
che porta un `<!DOCTYPE` viene rifiutato *prima* di essere parsato, così il ragionamento è
applicato invece che ricordato.

Uso:
    scripts/appcast.py --feed-url <url> --version <build> --short-version <v> \\
        --min-system <x.y> --download-url <url> --signature <sparkle:edSignature> \\
        --length <bytes> --notes-link <url> --output <path>
    scripts/appcast.py --self-test

Non pubblica niente: scrive un file locale.
"""

import argparse
import email.utils
import os
import sys
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, fields

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

# Registrato una volta sola, a livello di modulo: senza, ElementTree serializza gli
# elementi del namespace come `ns0:version`, che Sparkle non legge.
ET.register_namespace("sparkle", SPARKLE_NS)

FEED_TITLE = "Pergamenum"
FEED_DESCRIPTION = "Aggiornamenti di Pergamenum"
FEED_LANGUAGE = "it"


class AppcastError(Exception):
    """Un errore che l'utente deve vedere: `main` lo stampa su stderr ed esce non-zero."""


def fail(message):
    raise AppcastError(message)


def sparkle(name):
    return "{%s}%s" % (SPARKLE_NS, name)


# --- Il feed pubblicato ------------------------------------------------------------


def default_fetch(url):
    """Scarica il feed. Restituisce i byte, oppure None se non esiste ancora (404)."""
    request = urllib.request.Request(url, headers={"User-Agent": "pergamenum-appcast"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        fail("il feed %s ha risposto HTTP %s" % (url, exc.code))
    except urllib.error.URLError as exc:
        fail("il feed %s non è raggiungibile: %s" % (url, exc.reason))


def load_feed(url, fetch=default_fetch):
    """Il 404 è la strada felice esattamente una volta: prima della prima release."""
    return fetch(url)


def parse_feed(raw):
    if b"<!DOCTYPE" in raw:
        fail("il feed pubblicato contiene un <!DOCTYPE: rifiutato senza parsarlo")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        fail("il feed pubblicato non è XML valido: %s" % exc)
    if root.tag != "rss":
        fail("la radice del feed è <%s>, non <rss>" % root.tag)
    return root


def skeleton(feed_url):
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = FEED_TITLE
    ET.SubElement(channel, "link").text = feed_url
    ET.SubElement(channel, "description").text = FEED_DESCRIPTION
    ET.SubElement(channel, "language").text = FEED_LANGUAGE
    return root


# --- L'item ------------------------------------------------------------------------


@dataclass(frozen=True)
class AppcastItem:
    """Ciò che descrive una build nel feed: l'unico posto dove l'elenco dei campi è scritto.

    `REQUIRED`, la CLI e il self-test lo leggono da qui invece di ripeterlo. `pub_date`
    resta vuoto sulla riga di comando e si risolve al momento di costruire l'item.
    """

    version: str
    short_version: str
    min_system: str
    download_url: str
    signature: str
    length: str
    notes_link: str
    pub_date: str = ""


ITEM_FIELDS = tuple(f.name for f in fields(AppcastItem) if f.name != "pub_date")


def make_item(spec):
    item = ET.Element("item")
    pub_date = spec.pub_date or email.utils.formatdate(localtime=True)
    ET.SubElement(item, "title").text = "%s %s" % (FEED_TITLE, spec.short_version)
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, sparkle("version")).text = str(spec.version)
    ET.SubElement(item, sparkle("shortVersionString")).text = str(spec.short_version)
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = str(spec.min_system)
    ET.SubElement(item, sparkle("releaseNotesLink")).text = spec.notes_link
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": spec.download_url,
            sparkle("edSignature"): spec.signature,
            "length": str(spec.length),
            "type": "application/octet-stream",
        },
    )
    return item


def build_feed(raw, feed_url, spec):
    """Restituisce la radice del feed con l'item di questa build inserito o sostituito."""
    root = skeleton(feed_url) if raw is None else parse_feed(raw)
    channel = root.find("channel")
    if channel is None:
        fail("il feed pubblicato non ha un <channel>")

    item = make_item(spec)

    existing = None
    for candidate in channel.findall("item"):
        node = candidate.find(sparkle("version"))
        if node is not None and (node.text or "").strip() == str(spec.version):
            existing = candidate
            break

    children = list(channel)
    if existing is not None:
        # Sostituito dove sta, non accodato: rieseguire la stessa build aggiorna l'item,
        # non ne aggiunge un secondo con lo stesso sparkle:version.
        index = children.index(existing)
        channel.remove(existing)
        channel.insert(index, item)
    else:
        items = channel.findall("item")
        if items:
            channel.insert(children.index(items[0]), item)
        else:
            channel.append(item)
    return root


def serialize(root):
    if hasattr(ET, "indent"):
        ET.indent(root, space="    ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


# --- Self-test ---------------------------------------------------------------------


FEED_URL = "https://istefox.github.io/pergamenum-updates/appcast.xml"

ITEM_DEFAULTS = {
    "min_system": "26.0",
    "download_url": "https://github.com/istefox/pergamenum-updates/releases/download/v1.1-56/Pergamenum-1.1-56.zip",
    "signature": "Zm9vYmFyc2lnbmF0dXJl",
    "length": "6580113",
    "notes_link": "https://github.com/istefox/pergamenum-updates/releases/tag/v1.1-56",
    "pub_date": "Thu, 04 Sep 2026 12:00:00 +0200",
}


def _feed(raw, version, short_version):
    spec = AppcastItem(version=version, short_version=short_version, **ITEM_DEFAULTS)
    return build_feed(raw, FEED_URL, spec)


def _check(report, condition, description):
    if not condition:
        fail("self-test fallito: %s" % description)
    report.append("  ok  %s" % description)


def _case_1(report):
    """Feed assente (404) -> uno skeleton fresco con un solo item, ben formato."""
    first = serialize(_feed(None, "56", "1.1"))
    root = ET.fromstring(first)
    _check(report, len(root.find("channel").findall("item")) == 1,
           "feed assente -> un solo <item>")
    _check(report, b"sparkle:version" in first,
           "il prefisso sparkle: è nell'output, non ns0:")
    _check(report, b"ns0:" not in first,
           "nessun prefisso ns0: residuo")
    _check(report, b'sparkle:edSignature="%s"' % ITEM_DEFAULTS["signature"].encode() in first,
           "l'enclosure porta sparkle:edSignature")
    return first


def _case_2(report, first):
    """Feed esistente con un item -> due item, il vecchio intatto, il nuovo per primo."""
    second = serialize(_feed(first, "57", "1.2"))
    root = ET.fromstring(second)
    items = root.find("channel").findall("item")
    versions = [item.find(sparkle("version")).text for item in items]
    _check(report, versions == ["57", "56"],
           "il nuovo item è in cima e il precedente è conservato (%s)" % versions)
    _check(report, items[1].find(sparkle("shortVersionString")).text == "1.1",
           "l'item preesistente non è stato riscritto")


def _case_3(report, first):
    """Stesso sparkle:version due volte -> resta un item, aggiornato."""
    third = serialize(_feed(first, "56", "1.1.1"))
    root = ET.fromstring(third)
    items = root.find("channel").findall("item")
    _check(report, len(items) == 1,
           "la stessa build non duplica l'item")
    _check(report, items[0].find(sparkle("shortVersionString")).text == "1.1.1",
           "l'item della stessa build è aggiornato sul posto")


def _case_4(report):
    """Feed esistente malformato -> errore rumoroso che nomina l'errore di parsing."""
    try:
        _feed(b"<rss><channel><item></channel></rss>", "58", "1.3")
    except AppcastError as exc:
        message = str(exc)
    else:
        message = ""
    _check(report, "non è XML valido" in message and "line" in message,
           "un feed malformato fallisce nominando l'errore di parsing (%s)" % message)


def _case_5(report):
    """Un <!DOCTYPE arriva al rifiuto prima del parser."""
    try:
        _feed(b"<!DOCTYPE rss [<!ENTITY x 'y'>]><rss><channel></channel></rss>", "59", "1.4")
    except AppcastError as exc:
        message = str(exc)
    else:
        message = ""
    _check(report, "DOCTYPE" in message,
           "un feed con <!DOCTYPE è rifiutato senza essere parsato")


def self_test():
    """Asserzioni in-process, senza rete e senza un secondo runner (ADR-0031 §D10)."""
    report = []

    # Il feed del caso 1 alimenta i casi 2 e 3, e viene scritto su disco alla fine.
    first = _case_1(report)
    _case_2(report, first)
    _case_3(report, first)
    _case_4(report)
    _case_5(report)

    handle, path = tempfile.mkstemp(prefix="appcast-selftest-", suffix=".xml")
    with os.fdopen(handle, "wb") as out:
        out.write(first)

    print("appcast.py --self-test: %d controlli" % len(report))
    print("\n".join(report))
    print("  feed del caso (1) scritto in %s" % path)
    return 0


# --- CLI ---------------------------------------------------------------------------


REQUIRED = ("feed_url",) + ITEM_FIELDS + ("output",)


def build_parser():
    parser = argparse.ArgumentParser(
        description="Inserisce o aggiorna un <item> nell'appcast di Sparkle."
    )
    parser.add_argument("--feed-url", help="URL dell'appcast attualmente pubblicato")
    parser.add_argument("--version", help="sparkle:version (CFBundleVersion)")
    parser.add_argument("--short-version", help="sparkle:shortVersionString")
    parser.add_argument("--min-system", help="sparkle:minimumSystemVersion")
    parser.add_argument("--download-url", help="URL dell'archivio da scaricare")
    parser.add_argument("--signature", help="valore di sparkle:edSignature da sign_update")
    parser.add_argument("--length", help="dimensione in byte dell'archivio")
    parser.add_argument("--notes-link", help="sparkle:releaseNotesLink")
    parser.add_argument("--output", help="dove scrivere il feed risultante")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="esegue le asserzioni interne, senza rete, e non scrive l'appcast",
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        if args.self_test:
            return self_test()

        missing = [name for name in REQUIRED if getattr(args, name) is None]
        if missing:
            fail("argomenti mancanti: %s" % ", ".join("--" + n.replace("_", "-") for n in missing))

        spec = AppcastItem(**{name: getattr(args, name) for name in ITEM_FIELDS})
        root = build_feed(load_feed(args.feed_url), args.feed_url, spec)
        with open(args.output, "wb") as handle:
            handle.write(serialize(root))
        print("appcast: scritto %s (build %s, versione %s)" % (args.output, args.version, args.short_version))
        return 0
    except AppcastError as exc:
        print("appcast: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
