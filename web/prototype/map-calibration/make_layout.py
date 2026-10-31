import json, io, os
from PIL import Image, ImageDraw, ImageFont

W, H = 1400, 1600
X0, XS, Y0, YS = 12, 66, 4, 76
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "data", "locations.json")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "layout-guide.webp")

L = json.load(io.open(SRC, encoding="utf-8"))
def px(l):
    return ((l["map"]["x"] - X0) / XS * W, (l["map"]["y"] - Y0) / YS * H)

img = Image.new("RGB", (W, H), (138, 138, 132))
d = ImageDraw.Draw(img)

# 溪流：由上方偏左湧出，沿左側往下
river = [(430,0),(410,210),(372,300),(345,520),(318,760),(292,1010),(272,1240),(286,1430),(330,1600)]
d.line(river, fill=(74,106,138), width=86, joint="curve")

# 山路：右上山口進入，繞下匯入小鎮，再往下到浴場
road = [(1400,430),(1290,540),(1150,660),(1000,800),(860,930),(800,1060),(760,1240),(726,1470),(700,1600)]
d.line(road, fill=(104,104,98), width=30, joint="curve")
# 支線：老街—派出所—診所
d.line([(600,1180),(790,1150),(975,1140),(915,1300)], fill=(104,104,98), width=22, joint="curve")

try:
    font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 44)
except Exception:
    font = ImageFont.load_default()

BIG = {"sanquan", "jinghe", "temple", "bathhouse", "columbarium"}
rows = []
for i, l in enumerate(L["day"], 1):
    x, y = px(l)
    w, h = (150, 110) if l["id"] in BIG else (108, 80)
    box = [x - w/2, y - h/2, x + w/2, y + h/2]
    d.rectangle(box, fill=(224, 216, 202), outline=(30, 28, 26), width=5)
    t = str(i)
    tb = d.textbbox((0, 0), t, font=font)
    d.text((x - (tb[2]-tb[0])/2, y - (tb[3]-tb[1])/2 - tb[1]), t, fill=(30,28,26), font=font)
    rows.append((i, l["name"], round(x), round(y), l.get("chapter")))

img.save(OUT)
print("saved", OUT, img.size)
print()
for i, n, x, y, ch in rows:
    print("%2d  %-14s ch%-3s %4d,%4d   (%2d%% 橫, %2d%% 縱)" % (i, n, ch, x, y, round(x/W*100), round(y/H*100)))
