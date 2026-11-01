"""Print cards.html to PDF with headless Chrome, scan every card-back QR with Apple Vision (tools/scan_qr.swift),
and check each back sits behind the right front after a long-edge flip.
Run from the project root with the local server up:  <venv>/bin/python -I tools/check_cards.py
Needs: pip install pymupdf opencv-python-headless"""
import os, re, subprocess, sys, tempfile
import fitz, cv2, numpy as np

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000/cards.html"
tmp = tempfile.mkdtemp()
pdf_path = os.path.join(tmp, "cards.pdf")
subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=15000",
                "--print-to-pdf=" + pdf_path, URL], capture_output=True)
cards = re.findall(r'\{ d: (\d+), name: "([^"]+)"', open("cards.html").read())
only = re.search(r"[?&]only=([\d,]+)", URL)  # same filter as cards.html
if only: cards = [c for c in cards if c[0] in only.group(1).split(",")]
pdf, px, MM = fitz.open(pdf_path), 300 / 25.4, 72 / 25.4
print("pages", len(pdf))
pngs = []
for i in range(1, len(pdf), 2):
    page = pdf[i]
    pix = page.get_pixmap(dpi=300)
    img = np.frombuffer(pix.samples, np.uint8).reshape(pix.h, pix.w, pix.n)[:, :, :3]
    words = page.get_text("words")
    for r in range(3):
        for c in range(3):
            x0, y0 = 10.5 + c * 63, 16.5 + r * 88
            cell = img[int(y0 * px):int((y0 + 88) * px), int(x0 * px):int((x0 + 63) * px)]
            if (cell < 140).sum() < 500: continue
            t = " ".join(w[4] for w in words if x0 * MM <= (w[0] + w[2]) / 2 < (x0 + 63) * MM and y0 * MM <= (w[1] + w[3]) / 2 < (y0 + 88) * MM)
            d = re.search(r"Door (\d+)", t).group(1)
            p = os.path.join(tmp, "s%d_r%d_c%d__%s.png" % (i // 2 + 1, r + 1, c + 1, d))
            cv2.imwrite(p, cv2.cvtColor(cell, cv2.COLOR_RGB2BGR)); pngs.append(p)
out = subprocess.run(["swift", os.path.join(os.path.dirname(__file__), "scan_qr.swift"), *pngs], capture_output=True, text=True).stdout
bad = n = 0
for line in out.splitlines():
    f, url = line.split(" ", 1); url = url.strip()
    s, r, c, d = re.match(r"s(\d)_r(\d)_c(\d)__(\d+)", f).groups()
    front = (int(s) - 1) * 9 + (int(r) - 1) * 3 + (3 - int(c))  # mirrored column -> index in CARDS
    exp = cards[front]; ok = url.endswith("?day=" + d) and exp[0] == d
    n += 1; bad += not ok
    print(f"sheet {s}: back Door {d}, QR {url.split('/')[-1]}, behind {exp[1]} (door {exp[0]})", "OK" if ok else "MISMATCH")
print(f"{n} cards checked:", "ALL GOOD" if n == len(cards) and not bad else "PROBLEMS")
