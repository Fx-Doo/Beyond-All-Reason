import os

size_dirs = [
    ("icexuick_200", "200"),
    ("icexuick_166", "166"), 
    ("icexuick_133", "133"),
    ("icexuick_100", "100"),
    ("icexuick_75", "75")
]

for size_dir, size_num in size_dirs:
    txt_file = os.path.join(size_dir, "cursorprioritydef.txt")
    
    # Create proper definition file matching cursorattack.txt format
    # Uses full path prefix and 0.02 frame delay (matching attack cursor)
    content = "hotspot center\n"
    for i in range(60):
        content += f"frame anims/{size_dir}/cursorprioritydef_{i}.png 0.02\n"
    
    with open(txt_file, 'w') as f:
        f.write(content)
    
    print(f"✓ Fixed {size_dir}/cursorprioritydef.txt (full path format, 0.02s delay)")

print("\n✓ All cursor definitions fixed to match attack cursor format!")
