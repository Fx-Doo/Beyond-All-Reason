from PIL import Image

# Load the PNG and convert to BMP
img = Image.open('cursorprioritydef_0.png')
img.save('cursorprioritydef_0.bmp')
print("✓ Converted to BMP")
