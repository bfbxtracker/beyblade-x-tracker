from html.parser import HTMLParser
from pathlib import Path

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.external = False
        self.parts = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script":
            self.active = True
            self.external = any(key.lower() == "src" for key, _ in attrs)
            self.parts = []

    def handle_data(self, data):
        if self.active:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.active:
            if not self.external and "".join(self.parts).strip():
                self.scripts.append("".join(self.parts))
            self.active = False

parser = InlineScripts()
parser.feed(Path("index.html").read_text(encoding="utf-8"))
if not parser.scripts:
    raise SystemExit("No inline scripts found in index.html")
for number, script in enumerate(parser.scripts, 1):
    target = Path(f"/tmp/bfbx-inline-{number}.js")
    target.write_text(script, encoding="utf-8")
    print(f"Extracted inline script {number}: {len(script)} characters")
