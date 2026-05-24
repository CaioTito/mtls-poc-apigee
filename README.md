# POC mTLS — Apigee X Privado

Prova de conceito de **mTLS (mutual TLS)** usando Apigee X como proxy, simulando o cenário real de ambientes **zero trust** em que toda comunicação entre serviços exige autenticação mútua por certificado

## Fluxo validado

```
VM (GCP, mesma VPC)
  → Apigee X privado (IP interno <APIGEE_INTERNAL_IP>)
    → Cloud NAT
      → ngrok TCP
        → MtlsServer .NET (localhost:5000)
```

**Resultado confirmado:** HTTP 200 com `clientCertSubject: "CN=my-client"` — o Apigee apresentou o certificado cliente ao servidor via mTLS.

---

## Estrutura do repositório

```
mTLS-POC/
├── .gitignore
├── README.md
│
├── Certificados/
│   ├── ca.cert                       # Certificado público da CA
│   ├── client.cert                   # Certificado público do cliente
│   ├── server.cert                   # Certificado público do servidor
│   ├── san.ext                       # Extensão SAN para o server.pfx
│   ├── gerar-certificados.sh         # Script: CA + cliente
│   └── gerar-certificados-server.sh  # Script: servidor com SAN do ngrok
│
├── MtlsServer/                       
│   ├── Program.cs
│   ├── MtlsServer.csproj
│   ├── MtlsServer.sln
│   ├── appsettings.json
│   └── Properties/
│       └── launchSettings.json
│
├── Apigee/
│   ├── proxy-endpoint.xml            
│   └── target-endpoint.xml          
│
└── docs/
    └── mtls-poc-completa.drawio      
```

> **Segurança:** arquivos `.key`, `.pfx`, `.p12`, `.csr` e `.srl` estão no `.gitignore` e nunca devem ser commitados. Só os certificados **públicos** (`.cert`) e os scripts ficam no repositório.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Observação |
|---|---|---|
| Git Bash | qualquer | Inclui OpenSSL — sem instalação adicional |
| OpenSSL | 3.x | `openssl version` para verificar |
| .NET SDK | 10.0 | `dotnet --version` |
| ngrok | qualquer | Conta gratuita; autenticar com `ngrok authtoken` |
| Conta GCP | — | Apigee X trial já provisionado |

---

## Fase 1 — Gerar os certificados

Execute os scripts no **Git Bash** dentro da pasta `Certificados/`.

### 1a. Gerar a CA e o certificado cliente

```bash
cd Certificados
bash gerar-certificados.sh
```

Gera: `ca.key`, `ca.cert`, `client.key`, `client.csr`, `client.cert`, `client.pfx`

### 1b. Gerar o certificado do servidor (com SAN do ngrok)

> **Por que o SAN é obrigatório?**
> O Apigee valida o hostname do destino no certificado do servidor. O ngrok TCP usa o host `0.tcp.sa.ngrok.io` — se esse hostname não estiver como SAN (Subject Alternative Name) no `server.pfx`, o handshake falha com:
> `SSL Handshake failed: No name matching 0.tcp.sa.ngrok.io found`

```bash
bash gerar-certificados-server.sh
```

Gera: `server.key`, `server.csr`, `server.cert`, `server.pfx`

> Todos os arquivos `.key`, `.pfx` e `.csr` são ignorados pelo `.gitignore`. Guarde-os localmente e nunca os commite.

---

## Fase 2 — Configurar e rodar o MtlsServer .NET

### 2a. Copiar o certificado do servidor para o projeto

```bash
# No Git Bash ou PowerShell
cp Certificados/server.pfx MtlsServer/
```

### 2b. Rodar o servidor

```bash
cd MtlsServer
dotnet run
```

O Kestrel sobe na porta `5000` com HTTPS, exigindo certificado cliente (`ClientCertificateMode = RequireCertificate`).

**Endpoint disponível:** `GET /`

Resposta de exemplo:

```json
{
  "message": "Conexão mTLS estabelecida com sucesso!",
  "clientCertSubject": "CN=my-client",
  "timestamp": "2025-05-24T19:00:00Z"
}
```

> **Nota sobre `ClientCertificateValidation`:** o servidor aceita qualquer certificado (`return true`) porque esta é uma POC. Em produção, valide o emissor (deve ser sua CA), o CN e a validade do certificado.

---

## Fase 3 — Expor o servidor com ngrok TCP

> **Por que TCP e não HTTP?**
> O ngrok no modo HTTP termina o TLS na borda e re-encripta internamente — isso desfaz o mTLS porque o Apigee jamais verá o handshake real. O modo **TCP passa os bytes brutos**, preservando o TLS de ponta a ponta.

```bash
ngrok tcp 5000
```

Anote a URL gerada:

```
Forwarding: tcp://0.tcp.sa.ngrok.io:PORTA -> localhost:5000
```

Você vai usar essa **PORTA** no Target Endpoint do Apigee (próxima fase).

---

## Fase 4 — Configurar o Apigee X

### 4a. Criar o Keystore (certificado cliente — o que o Apigee apresenta ao servidor)

1. **Apigee Console → Administrar → Ambientes → TLS Keystores**
2. Criar keystore: `keystore-teste`
3. Adicionar alias:
   - Nome: `cert-teste`
   - Tipo: **PKCS12 / PFX**
   - Arquivo: `client.pfx`
   - Senha: `senha123`

### 4b. Criar o Truststore (CA — para o Apigee confiar no server.pfx)

1. No mesmo menu, criar keystore: `truststore-teste`
2. Adicionar alias:
   - Nome: `ca-teste`
   - Tipo: **Somente certificado**
   - Arquivo: `ca.cert`

### 4c. Configurar o proxy

Use os XMLs da pasta `Apigee/` como referência.

**Proxy Endpoint** (`proxy-endpoint.xml`):
- BasePath: `/mtls`

**Target Endpoint** (`target-endpoint.xml`):
- URL: `https://0.tcp.sa.ngrok.io:PORTA` (substitua pela porta do ngrok)
- SSLInfo:
  - `Enabled`: true
  - `ClientAuthEnabled`: true
  - `KeyStore`: `keystore-teste`
  - `KeyAlias`: `cert-teste`
  - `TrustStore`: `truststore-teste`

> **Atenção:** use o **nome direto** do keystore (ex: `keystore-teste`), não o nome de uma Reference. References funcionam apenas para TargetServers, não para Target Endpoints diretos.

### 4d. Implantar o proxy

Salvar como nova revisão → Implantar → confirmar status **Deployed** sem erros de validação.

---

## Fase 5 — Infraestrutura GCP

### 5a. Cloud NAT (necessário para o Apigee alcançar a internet)

O Apigee X trial usa apenas IPs privados — sem Cloud NAT ele não consegue fazer chamadas externas (como para o ngrok).

1. **GCP Console → Network Services → Cloud NAT → Criar**
2. Nome: `apigee-nat`
3. Região: `southamerica-east1`
4. Criar Cloud Router junto: `apigee-router`

### 5b. VM na mesma VPC (necessária apenas no trial)

O Apigee X trial não expõe hostname público — só é acessível pelo IP interno `<APIGEE_INTERNAL_IP>` dentro da VPC.

1. **Compute Engine → Criar instância de VM**
2. Nome: `teste-apiproxy`
3. Tipo: `e2-micro`
4. Região: `southamerica-east1`
5. Rede: `default` (mesma VPC do Apigee)

> Em produção sua aplicação já estará dentro da VPC e essa VM não é necessária.

---

## Fase 6 — Validar com curl pela VM

Acesse a VM via SSH e execute:

```bash
curl -vk https://<APIGEE_INTERNAL_IP>/mtls \
  -H "Host: SEU-HOSTNAME.dns-replaceme.example.com"
```

> O hostname está em: **Apigee Console → Administração → Grupos de Ambientes**

**Resposta esperada (HTTP 200):**

```json
{
  "message": "Conexão mTLS estabelecida com sucesso!",
  "clientCertSubject": "CN=my-client",
  "timestamp": "2025-05-24T19:00:00Z"
}
```

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| `SSL Handshake failed: No name matching 0.tcp.sa.ngrok.io found` | SAN ausente no `server.pfx` | Regerar o `server.pfx` com `gerar-certificados-server.sh` que inclui o SAN |
| `404` no path | Apigee faz strip do BasePath antes de repassar ao backend | Servidor deve expor `/` (raiz), não `/mtls` |
| `503 SSL Handshake failed` | Cloud NAT ausente ou URL do ngrok desatualizada no Target | Verificar Cloud NAT ativo e atualizar a porta do ngrok no Target Endpoint |
| `Connection refused` na porta 80 | Apigee só aceita HTTPS (443) | Usar `https://` na URL do Target |
| `404` sem mensagem de erro do proxy | Header `Host` incorreto | Verificar o hostname do Environment Group no Apigee Console |
| `400 Bad Request` no Kestrel | Cliente enviou requisição sem certificado | Confirmar que `ClientAuthEnabled=true` no SSLInfo do Apigee |

---

## O que não é necessário nesta POC

Os componentes abaixo são necessários apenas para **mTLS de entrada via internet** (quando um cliente externo chama a API no Apigee com certificado). Nesta POC o mTLS é de **saída** (Apigee → backend):

- **Cloud Load Balancer** — não necessário para acesso interno à VPC
- **IP Estático Externo** — o Apigee trial só tem IP interno
- **Certificate Manager Trust Config** — necessário apenas para mTLS de entrada no Load Balancer
- **Server TLS Policy** — idem, só para mTLS de entrada

---

## Trial vs. Produção

| Aspecto | Trial | Produção |
|---|---|---|
| Hostname do Apigee | Placeholder (`*.dns-replaceme.example.com`) | Domínio real configurado |
| Acesso ao Apigee | Apenas por IP interno via VM na mesma VPC | Aplicação já na VPC — sem VM necessária |
| Cloud NAT | Necessário para saída à internet | Mesmo comportamento |
| Ngrok | Adequado para POC | Substituir pelo endpoint real do parceiro |

---

## Tecnologias

- [ASP.NET Core](https://learn.microsoft.com/aspnet/core) / .NET 10 — servidor mTLS com Kestrel
- [OpenSSL](https://www.openssl.org/) — geração de CA, certificados e PFX
- [Apigee X](https://cloud.google.com/apigee) — proxy com mTLS de saída
- [ngrok TCP](https://ngrok.com/docs/tcp/) — túnel TCP para expor o servidor local
- [Cloud NAT](https://cloud.google.com/nat) — saída à internet para o Apigee privado
- [draw.io](https://app.diagrams.net/) — fluxograma da arquitetura (`docs/mtls-poc-completa.drawio`)

---

## Aviso de segurança

> Os arquivos `.key`, `.pfx`, `.p12`, `.csr` e `.srl` contêm **chaves privadas** e estão bloqueados pelo `.gitignore`.
> Nunca os adicione ao repositório, mesmo que temporariamente.
> O `ca.key` em especial permite gerar certificados válidos assinados pela sua CA — guarde-o com segurança fora do repositório.
