#!/usr/bin/env python3
"""
deploy.py – automatiza setup y despliegues en tu EC2 Ubuntu

Uso:
  ./deploy.py setup   # Sólo la primera vez
  ./deploy.py deploy  # Para actualizaciones
"""
import os
import subprocess
import sys

REPO_URL = "https://github.com/tu_usuario/vinilos.git"
BASE_DIR = "/home/ubuntu/vinilos"


def run(cmd: str) -> None:
    """Ejecuta un comando y aborta si falla."""
    print(f"> {cmd}")
    subprocess.run(cmd, shell=True, check=True)


# ---------- SETUP INICIAL ----------
def setup() -> None:
    # 1) Instalar dependencias básicas
    run("sudo apt update && sudo apt install -y git nginx python3-pip")

    # 2) Clonar el repositorio si aún no existe
    if not os.path.isdir(BASE_DIR):
        run(f"git clone {REPO_URL} {BASE_DIR}")

    # 3) Backend: dependencias Python y servicio systemd
    run(f"pip3 install -r {BASE_DIR}/backend/requirements.txt")

    svc = f"""[Unit]
Description=Vinilos API
After=network.target

[Service]
User=ubuntu
WorkingDirectory={BASE_DIR}/backend
ExecStart=/usr/bin/gunicorn --bind 127.0.0.1:3000 app:app

[Install]
WantedBy=multi-user.target
"""
    with open("/tmp/vinilos.service", "w") as f:
        f.write(svc)
    run("sudo mv /tmp/vinilos.service /etc/systemd/system/vinilos.service")
    run("sudo systemctl daemon-reload && sudo systemctl enable --now vinilos")

    # 4) Frontend: copiar archivos estáticos
    run("sudo rm -rf /var/www/vinilos && sudo mkdir -p /var/www/vinilos")
    run(f"sudo cp -r {BASE_DIR}/frontend/* /var/www/vinilos/")
    run("sudo chown -R www-data:www-data /var/www/vinilos")

    # 5) Nginx virtual host
    nginx_cfg = """\
server {
    listen 80;
    server_name _;

    root /var/www/vinilos;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:3000/;
        proxy_set_header Host $host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
"""
    with open("/tmp/vinilos_nginx", "w") as f:
        f.write(nginx_cfg)
    run("sudo mv /tmp/vinilos_nginx /etc/nginx/sites-available/vinilos")
    run("sudo ln -sf /etc/nginx/sites-available/vinilos /etc/nginx/sites-enabled/")
    run("sudo nginx -t && sudo systemctl restart nginx")


# ---------- ACTUALIZACIONES ----------
def deploy() -> None:
    run(f"cd {BASE_DIR} && git pull")
    run(f"pip3 install -r {BASE_DIR}/backend/requirements.txt")
    run("sudo systemctl restart vinilos")

    run("sudo rm -rf /var/www/vinilos && sudo mkdir -p /var/www/vinilos")
    run(f"sudo cp -r {BASE_DIR}/frontend/* /var/www/vinilos/")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("setup", "deploy"):
        print("Uso: deploy.py [setup|deploy]")
        sys.exit(1)

    # Ejecuta la función correspondiente
    globals()[sys.argv[1]]()
