#!/bin/bash

# Fungsi untuk menampilkan pesan dengan warna
function echo_color() {
    echo -e "\e[1;32m$1\e[0m"
}

# Fungsi untuk memvalidasi input domain
function validate_domain() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        echo "Domain tidak boleh kosong!" | lolcat
        return 1
    fi
    # Validasi format domain sederhana
    if ! [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Format domain tidak valid! Contoh: example.com" | lolcat
        return 1
    fi
    return 0
}

# Fungsi untuk memvalidasi input password
function validate_password() {
    local password=$1
    if [[ -z "$password" ]]; then
        echo "Password tidak boleh kosong!" | lolcat
        return 1
    fi
    if [[ ${#password} -lt 8 ]]; then
        echo "Password harus memiliki setidaknya 8 karakter!" | lolcat
        return 1
    fi
    return 0
}

# Fungsi untuk menginstal Pterodactyl Panel
function install_pterodactyl() {
    echo_color "Menginstall Pterodactyl..."

    # Meminta pengguna untuk memasukkan domain
    while true; do
        read -p "Masukkan domain Anda (contoh: example.com): " subdomain
        validate_domain "$subdomain" && break
    done

    # Update dan Install Dependencies
    echo_color "══════════════════════════════════════════════"
    echo_color "> Preparing the Server"
    echo_color "══════════════════════════════════════════════"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg

    # Install PHP dan Extensions
    echo_color "══════════════════════════════════════════════"
    echo_color "> Installing PHP and Required Extensions"
    echo_color "══════════════════════════════════════════════"
    LC_ALL=C.UTF-8 sudo add-apt-repository -y ppa:ondrej/php
    sudo apt update
    sudo apt install -y php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip}

    # Install MariaDB
    echo_color "══════════════════════════════════════════════"
    echo_color "> Installing MariaDB"
    echo_color "══════════════════════════════════════════════"
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    sudo apt install -y mariadb-server
    sudo mysql_secure_installation

    # Install Redis
    echo_color "══════════════════════════════════════════════"
    echo_color "> Installing Redis"
    echo_color "══════════════════════════════════════════════"
    sudo apt install -y redis-server
    sudo systemctl enable redis-server
    sudo systemctl start redis-server

    # Install Composer
    echo_color "══════════════════════════════════════════════"
    echo_color "> Installing Composer"
    echo_color "══════════════════════════════════════════════"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Install Pterodactyl Panel
    echo_color "══════════════════════════════════════════════"
    echo_color "> Installing Pterodactyl Panel"
    echo_color "══════════════════════════════════════════════"
    sudo mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan key:generate --force

    # Konfigurasi Database
    echo_color "══════════════════════════════════════════════"
    echo_color "> Configuring Database"
    echo_color "══════════════════════════════════════════════"
    while true; do
        read -p "Masukkan password root MariaDB: " db_root_password
        validate_password "$db_root_password" && break
    done

    sudo mysql -u root -p"$db_root_password" <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'NEOXTOOLS';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    php artisan p:environment:setup
    php artisan p:environment:database
    php artisan migrate --seed --force
    php artisan p:user:make

    # Konfigurasi Nginx
    echo_color "══════════════════════════════════════════════"
    echo_color "> Configuring Nginx"
    echo_color "══════════════════════════════════════════════"
    sudo apt install -y nginx
    sudo rm -rf /etc/nginx/sites-enabled/default
    cat <<EOL | sudo tee /etc/nginx/sites-available/pterodactyl.conf
server {
    listen 80;
    server_name $subdomain;
    root /var/www/pterodactyl/public;

    index index.html index.htm index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    sudo systemctl restart nginx

    # Konfigurasi SSL (Opsional)
    echo_color "══════════════════════════════════════════════"
    echo_color "> Configuring SSL (Optional)"
    echo_color "══════════════════════════════════════════════"
    sudo apt install -y certbot python3-certbot-nginx
    read -p "Masukkan email Anda untuk konfigurasi SSL (opsional): " email
    if [[ -n "$email" ]]; then
        sudo certbot --nginx -d $subdomain --agree-tos --no-eff-email --email $email
    else
        echo "SSL tidak dikonfigurasi karena email tidak diberikan." | lolcat
    fi

    echo_color "══════════════════════════════════════════════"
    echo_color "> Setup Completed"
    echo_color "══════════════════════════════════════════════"
}

# Main loop
while true; do
    echo "============================================="
    echo "Pterodactyl Installation Script"
    echo "============================================="
    echo "1) Install Pterodactyl Panel"
    echo "2) Exit"
    echo "============================================="
    read -p "Enter your choice [1/2]: " choice

    if [[ "$choice" == "1" ]]; then
        install_pterodactyl
    elif [[ "$choice" == "2" ]]; then
        echo "Exiting... Goodbye!" | lolcat
        break
    else
        echo "Invalid choice, please try again!" | lolcat
    fi
done
