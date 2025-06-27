#!/bin/bash
# setup-ssl-certificates.sh - Automated SSL certificate setup

set -e

DOMAIN=${1:-"localhost"}
CERT_DIR="/opt/n8n-voice-ai/certs"
ACME_EMAIL=${ACME_EMAIL:-"admin@${DOMAIN}"}

echo "🔐 Setting up SSL certificates for domain: $DOMAIN"

# Create certificate directory
mkdir -p "$CERT_DIR"

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    sudo apt update
    sudo apt install -y certbot python3-certbot-dns-cloudflare
fi

# Generate Let's Encrypt certificates
if [ "$DOMAIN" != "localhost" ]; then
    echo "Generating Let's Encrypt certificate for $DOMAIN"
    sudo certbot certonly \
        --standalone \
        --email "$ACME_EMAIL" \
        --agree-tos \
        --no-eff-email \
        -d "$DOMAIN" \
        --cert-path "$CERT_DIR/cert.pem" \
        --key-path "$CERT_DIR/key.pem" \
        --fullchain-path "$CERT_DIR/fullchain.pem"
else
    echo "Generating self-signed certificate for localhost"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_DIR/key.pem" \
        -out "$CERT_DIR/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN"
    cp "$CERT_DIR/cert.pem" "$CERT_DIR/fullchain.pem"
fi

# Set proper permissions
sudo chown -R $USER:$USER "$CERT_DIR"
chmod 600 "$CERT_DIR"/key.pem
chmod 644 "$CERT_DIR"/{cert,fullchain}.pem

# Setup certificate renewal
if [ "$DOMAIN" != "localhost" ]; then
    echo "Setting up automatic certificate renewal"
    echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
fi

echo "✅ SSL certificates ready at: $CERT_DIR"
