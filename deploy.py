# deploy.py - Deployment script for setting up the server environment
import os
import subprocess

# Configurable parameters (replace with your GitHub repo URL and DB credentials)
GIT_REPO_URL = "https://github.com/usuario/vinylstore.git"  # REPLACE with actual repository URL
DB_HOST = "REPLACE_WITH_RDS_ENDPOINT"
DB_NAME = "vinylstore"
DB_USER = "admin"
DB_PASS = "VinylPass123!"

# Clone the repository (if not already present)
repo_dir = "/opt/vinylstore"
if not os.path.exists(repo_dir):
    print(f"Cloning repository from {GIT_REPO_URL}...")
    subprocess.run(["git", "clone", GIT_REPO_URL, repo_dir], check=True)
else:
    print("Repository already exists, pulling latest changes...")
    subprocess.run(["git", "-C", repo_dir, "pull"], check=True)

# Install Python dependencies
req_file = os.path.join(repo_dir, "backend", "requirements.txt")
print("Installing Python dependencies...")
subprocess.run(["pip3", "install", "-r", req_file], check=True)

# Write systemd service file for Gunicorn
service_file = "/etc/systemd/system/vinylstore.service"
service_content = f"""[Unit]
Description=Gunicorn instance to serve vinyl store app
After=network.target

[Service]
User=ubuntu
WorkingDirectory={repo_dir}/backend
Environment="DB_HOST={DB_HOST}" "DB_NAME={DB_NAME}" "DB_USER={DB_USER}" "DB_PASS={DB_PASS}"
ExecStart=/usr/local/bin/gunicorn --workers 3 --bind 127.0.0.1:8000 app:app

[Install]
WantedBy=multi-user.target
"""
with open(service_file, "w") as f:
    f.write(service_content)

# Reload systemd and start the service
print("Enabling and starting vinylstore.service...")
subprocess.run(["systemctl", "daemon-reload"], check=True)
subprocess.run(["systemctl", "enable", "--now", "vinylstore.service"], check=True)

# Configure Nginx
nginx_site = "/etc/nginx/sites-available/vinylstore"
nginx_conf = f"""server {{
    listen 80 default_server;
    server_name _;
    root {repo_dir}/frontend;
    index index.html;
    location / {{
        try_files $uri $uri/ =404;
    }}
    location /api/ {{
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }}
}}
"""
with open(nginx_site, "w") as f:
    f.write(nginx_conf)

# Enable the new Nginx site and disable default
if os.path.exists("/etc/nginx/sites-enabled/default"):
    os.remove("/etc/nginx/sites-enabled/default")
subprocess.run(["ln", "-sf", nginx_site, "/etc/nginx/sites-enabled/"], check=True)

# Restart Nginx
print("Restarting Nginx...")
subprocess.run(["systemctl", "restart", "nginx"], check=True)

print("Deployment script completed successfully.")
