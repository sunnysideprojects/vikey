#!/usr/bin/env python3
"""Write the Sparkle appcast for one release (used by scripts/release.sh).

    appcast.py VERSION BUILD ZIP_URL NOTES_URL CHANGES_MD 'sparkle:edSignature="…" length="…"' > appcast.xml

The feed holds only the newest release: it is uploaded with each GitHub release and ViKey reads it
from /releases/latest/download/appcast.xml. The release notes shown in Sparkle's window come from
the release's changes.md (summary line, "## " headings, "- " bullets, `code`, **bold**).
"""
import html
import re
import sys
from email.utils import formatdate


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)


def notes_html(markdown):
    out, in_list = [], False
    for raw in markdown.splitlines():
        line = raw.rstrip()
        bullet = re.match(r"\s*- (.*)", line)
        if in_list and not bullet:
            out.append("</ul>")
            in_list = False
        if not line:
            continue
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
        elif line.startswith("#"):
            out.append(f"<h3>{inline(line.lstrip('#').strip())}</h3>")
        else:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    version, build, zip_url, notes_url, changes, enclosure_attrs = sys.argv[1:]
    if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', enclosure_attrs.strip()):
        sys.exit(f"unexpected sign_update output: {enclosure_attrs!r}")
    with open(changes, encoding="utf-8") as f:
        notes = notes_html(f.read()).replace("]]>", "]]&gt;")
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>ViKey</title>
    <item>
      <title>ViKey {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{html.escape(notes_url)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{notes}
]]></description>
      <enclosure url="{html.escape(zip_url)}" {enclosure_attrs.strip()} type="application/octet-stream"/>
    </item>
  </channel>
</rss>""")


if __name__ == "__main__":
    main()
