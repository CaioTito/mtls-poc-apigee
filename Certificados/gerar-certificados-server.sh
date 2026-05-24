# Criar arquivo de extensão com o SAN do ngrok
cat > san.ext << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = 0.tcp.sa.ngrok.io
DNS.2 = localhost
EOF

# Gerar nova chave do servidor
openssl genrsa -out server.key 2048

# Gerar CSR com SAN
openssl req -new -key server.key -out server.csr \
  -subj "//CN=0.tcp.sa.ngrok.io"

# Assinar com a CA incluindo o SAN
openssl x509 -req -days 365 -in server.csr \
  -CA ca.cert -CAkey ca.key \
  -CAcreateserial -out server.cert \
  -extfile san.ext -extensions v3_req

# Empacotar em .pfx
openssl pkcs12 -export -out server.pfx \
  -inkey server.key -in server.cert \
  -passout pass:senha123