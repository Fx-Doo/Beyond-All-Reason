from PIL import Image
import os
import glob

# Directories to process
size_dirs = [
    "C:\\Program Files\\Beyond-All-Reason\\data\\games\\BAR.sdd\\anims\\icexuick_200",
    "C:\\Program Files\\Beyond-All-Reason\\data\\games\\BAR.sdd\\anims\\icexuick_166",
    "C:\\Program Files\\Beyond-All-Reason\\data\\games\\BAR.sdd\\anims\\icexuick_133",
    "C:\\Program Files\\Beyond-All-Reason\\data\\games\\BAR.sdd\\anims\\icexuick_100",
    "C:\\Program Files\\Beyond-All-Reason\\data\\games\\BAR.sdd\\anims\\icexuick_75"
]

for size_dir in size_dirs:
    print(f"Processing {os.path.basename(size_dir)}...")
    
    # Find all cursorsettarget_*.png files
    for src_file in glob.glob(os.path.join(size_dir, "cursorsettarget_*.png")):
        # Get frame number
        frame_num = os.path.basename(src_file).replace("cursorsettarget_", "").replace(".png", "")
        dst_file = os.path.join(size_dir, f"cursorprioritydef_{frame_num}.png")
        
        # Load image
        img = Image.open(src_file)
        
        # Convert to RGBA if needed
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # Apply orange tint
        pixels = img.load()
        width, height = img.size
        
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[x, y]
                
                # Skip transparent pixels
                if a == 0:
                    continue
                
                # Apply orange tint
                if r > 0 or g > 0 or b > 0:
                    r_new = min(255, int(r * 1.3))  # Boost red moderately
                    g_new = int(g * 0.6)             # Keep more green for orange tone
                    b_new = max(0, int(b * 0.1))     # Minimize blue
                    
                    pixels[x, y] = (r_new, g_new, b_new, a)
        
        # Save
        img.save(dst_file)
        print(f"  ✓ {os.path.basename(dst_file)}")
    
    # Copy .txt definition file
    src_txt = os.path.join(size_dir, "cursorsettarget.txt")
    dst_txt = os.path.join(size_dir, "cursorprioritydef.txt")
    if os.path.exists(src_txt):
        with open(src_txt, 'r') as f:
            content = f.read()
        # Replace frame references
        content = content.replace("cursorsettarget_", "cursorprioritydef_")
        with open(dst_txt, 'w') as f:
            f.write(content)
        print(f"  ✓ {os.path.basename(dst_txt)}")

print("\n✓ All cursors created!")
