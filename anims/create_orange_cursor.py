from PIL import Image

# Load the original settarget cursor
img = Image.open('cursorsettarget_0.bmp')

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
        
        # Apply orange tint - boost red, reduce blue
        if r > 0 or g > 0 or b > 0:
            r_new = min(255, int(r * 1.2))  # Boost red
            g_new = int(g * 0.9)             # Slight reduce green
            b_new = max(0, int(b * 0.3))     # Significantly reduce blue
            
            pixels[x, y] = (r_new, g_new, b_new, a)

# Save as PNG
img.save('cursorprioritydef_0.png')
print("✓ Created cursorprioritydef_0.png")
