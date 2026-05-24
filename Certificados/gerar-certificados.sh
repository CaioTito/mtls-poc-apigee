#!/bin/bash

# 1. Chave privada da CA
openssl genrsa -out ca.key 4096

# 2. Certificado da CA
openssl req -new -x509 -days 730 -key ca.key -out ca.cert \
  -subj "//CN=MyLocalCA"

# 3. Chave privada do cliente
openssl genrsa -out client.key 2048

# 4. CSR do cliente
openssl req -new -key client.key -out client.csr \
  -subj "//CN=my-client"

# 5. Assinar o certificado do cliente
openssl x509 -req -days 365 -in client.csr \
  -CA ca.cert -CAkey ca.key \
  -CAcreateserial -out client.cert

# 6. Empacotar em .pfx
openssl pkcs12 -export -out client.pfx \
  -inkey client.key -in client.cert \
  -passout pass:senha123

echo "Certificados gerados com sucesso!"