import re

with open('/opt/infrastructure/roles/nas_docker/templates/docker-compose.yml.j2', 'r') as f:
    content = f.read()

services_content = content.split("services:\n")[1].split("\nnetworks:")[0]

blocks = re.split(r"{% if current_service == '(.*?)' %}", services_content)

import os
os.makedirs('/opt/infrastructure/roles/nas_docker/templates/compose', exist_ok=True)

for i in range(1, len(blocks), 2):
    service_name = blocks[i]
    service_content = blocks[i+1].split("{% endif %}")[0].strip()
    
    with open(f'/opt/infrastructure/roles/nas_docker/templates/compose/{service_name}.yml.j2', 'w') as out:
        out.write(f"services:\n{service_content}\n")
