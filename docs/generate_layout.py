import klayout.db as db
import klayout.lay as lay
import os

# Initialize Layout and Top Cell
layout = db.Layout()
layout.dbu = 0.001 # 1nm DBU

top = layout.create_cell("ultra_low_latency_nasdaq_itch50_cutthrough")

# Layers: PR_BOUNDARY (235/0), M1 (68/20), M2 (69/20), M3 (70/20), M4 (71/20), M5 (72/20)
l_boundary = layout.layer(235, 0)
l_m1 = layout.layer(68, 20)
l_m2 = layout.layer(69, 20)
l_m3 = layout.layer(70, 20)
l_m4 = layout.layer(71, 20)
l_m5 = layout.layer(72, 20)

# Die Size: 450um x 450um (450000 x 450000 in DBU)
die_w = 450000
die_h = 450000
top.shapes(l_boundary).insert(db.Box(0, 0, die_w, die_h))

# Power Ring (VDD / VSS)
ring_w = 12000
margin = 15000
top.shapes(l_m4).insert(db.Box(margin, margin, die_w - margin, margin + ring_w))
top.shapes(l_m4).insert(db.Box(margin, die_h - margin - ring_w, die_w - margin, die_h - margin))
top.shapes(l_m5).insert(db.Box(margin, margin, margin + ring_w, die_h - margin))
top.shapes(l_m5).insert(db.Box(die_w - margin - ring_w, margin, die_w - margin, die_h - margin))

# Core Area Floorplanning (Standard Cell Blocks)
# 1. Lookahead Barrel Shifter (Left partition: 60um - 200um)
top.shapes(l_m1).insert(db.Box(55000, 55000, 200000, 395000))

# 2. Speculative Parser Matrix (Center partition: 210um - 330um)
top.shapes(l_m2).insert(db.Box(210000, 55000, 330000, 395000))

# 3. Direct L3 Pre-Trigger & Drop Gate (Top-Right partition)
top.shapes(l_m3).insert(db.Box(340000, 230000, 400000, 395000))

# 4. Registered Pipeline Stage (Bottom-Right partition)
top.shapes(l_m2).insert(db.Box(340000, 55000, 400000, 220000))

# Metal Power Grid Straps
for x in range(60000, 400000, 30000):
    top.shapes(l_m4).insert(db.Box(x, 50000, x + 4000, 400000))

for y in range(60000, 400000, 30000):
    top.shapes(l_m5).insert(db.Box(50000, y, 400000, y + 4000))

# Save GDSII
os.makedirs("docs", exist_ok=True)
layout.write("docs/layout_preview.gds")
print("GDSII layout exported successfully to docs/layout_preview.gds")

# Generate Image via LayoutView
lv = lay.LayoutView()
lv.show_layout(layout, 0)
lv.max_hier()
lv.save_image("docs/layout_preview.png", 800, 800)
print("Layout PNG rendered successfully to docs/layout_preview.png")