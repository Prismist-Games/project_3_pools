
import os

target_dir = "/Users/ziggy/GitHub/project_3_pools/assets/sprites/city_bg"
for filename in os.listdir(target_dir):
    if filename.endswith(".png.import"):
        filepath = os.path.join(target_dir, filename)
        with open(filepath, 'rb') as f:
            content = f.read()
        
        target_str = b"process/size_limit=0"
        replacement_str = b"process/size_limit=2000"
        
        if target_str in content:
            new_content = content.replace(target_str, replacement_str)
            with open(filepath, 'wb') as f:
                f.write(new_content)
            print(f"Updated {filename}")
        else:
            print(f"Skipped {filename} (match not found)")
